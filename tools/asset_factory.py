#!/usr/bin/env python3
"""MIDNIGHT SYNDICATE asset factory: manifest registration, validation and licence report.

Python 3.10, standard library only. Run as: py -3.10 tools/asset_factory.py <command> ...

Commands
  register  --id --kind {texture,model,hdri,audio,generated} --path --source SOURCE
            --source-url URL --license LICENCE --author TEXT --tris N --tex-size WxH
            --materials N --notes TEXT
            Upserts one record in ASSET_MANIFEST.json. --path is relative to the repo root
            (a file, or a folder for texture sets). Measures sizes and hashes itself.
  validate  Checks every record (file present, sha256, licence allow-list, source_url for
            third-party, glTF binary magic and JSON chunk, power-of-two texture sizes, HDR/PNG/JPEG
            headers). Prints a table, writes test_result per record, exit 1 on any failure.
  licenses  Regenerates THIRD_PARTY_LICENSES.md from the manifest (third-party records only).
  selftest  Runs the built-in checks in a temp folder. Exit 0 when all pass.

Global options (before the command): --root DIR (default: repo root), --manifest FILE.
Sources: cc0:polyhaven, cc0:ambientcg, generated:blender, generated:script.
Licences: CC0-1.0 (third-party) or project-owned (generated).
"""
import argparse
import datetime
import hashlib
import json
import os
import struct
import sys
import tempfile
import time
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
KINDS = ("texture", "model", "hdri", "audio", "generated")
SOURCES = ("cc0:polyhaven", "cc0:ambientcg", "generated:blender", "generated:script")
LICENCES = ("CC0-1.0", "project-owned")
THIRD_PARTY_PREFIX = "cc0:"
IMAGE_EXT = (".jpg", ".jpeg", ".png", ".hdr")
FIELDS = ("id", "kind", "path", "source", "source_url", "license", "author", "tris",
          "texture_sizes", "material_count", "bytes", "sha256", "test_result", "added", "notes")


# ---------- headers and hashes -------------------------------------------------------------

def _png_size(data):
    if data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        raise ValueError("not a PNG")
    return struct.unpack(">II", data[16:24])


def _jpeg_size(data):
    if data[:2] != b"\xff\xd8":
        raise ValueError("not a JPEG")
    i = 2
    while i + 4 <= len(data):
        if data[i] != 0xFF:
            raise ValueError("bad JPEG marker")
        m = data[i + 1]
        if m == 0xFF:
            i += 1
            continue
        if m in (0xD8, 0x01) or 0xD0 <= m <= 0xD7:
            i += 2
            continue
        seg = struct.unpack(">H", data[i + 2:i + 4])[0]
        if m in (0xC0, 0xC1, 0xC2):
            h, w = struct.unpack(">HH", data[i + 5:i + 9])
            return w, h
        i += 2 + seg
    raise ValueError("JPEG has no SOF marker")


def _hdr_size(data):
    # Radiance RGBE: header lines, blank line, then "-Y h +X w"
    lines = data[:4096].split(b"\n")
    if not lines[0].startswith(b"#?"):
        raise ValueError("not a Radiance HDR")
    for line in lines[1:]:
        t = line.split()
        if len(t) == 4 and t[0] in (b"-Y", b"+Y") and t[2] in (b"+X", b"-X"):
            return int(t[3]), int(t[1])
    raise ValueError("HDR resolution line not found")


def image_size(path):
    """(width, height) of a PNG, JPEG or Radiance HDR file, read from its header."""
    with open(path, "rb") as f:
        data = f.read()
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return _png_size(data)
    if data[:2] == b"\xff\xd8":
        return _jpeg_size(data)
    if data[:2] == b"#?":
        return _hdr_size(data)
    raise ValueError("unsupported image: " + path)


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def _walk(full):
    out = []
    for dp, _, fns in os.walk(full):
        for fn in fns:
            out.append(os.path.join(dp, fn))
    return sorted(out, key=lambda p: os.path.relpath(p, full).replace("\\", "/"))


def hash_path(full):
    """sha256 of a file, or of a folder's (relpath, sha256) list. Returns (sha, bytes)."""
    if os.path.isfile(full):
        return sha256_file(full), os.path.getsize(full)
    h = hashlib.sha256()
    total = 0
    for p in _walk(full):
        rel = os.path.relpath(p, full).replace("\\", "/")
        h.update(("%s\t%s\n" % (rel, sha256_file(p))).encode("utf-8"))
        total += os.path.getsize(p)
    return h.hexdigest(), total


def texture_sizes(full):
    """{file name: [w, h]} for every image under a file or folder."""
    files = [full] if os.path.isfile(full) else [p for p in _walk(full)]
    out = {}
    for p in files:
        if os.path.splitext(p)[1].lower() in IMAGE_EXT:
            name = os.path.relpath(p, full if os.path.isdir(full) else os.path.dirname(full))
            out[name.replace("\\", "/")] = list(image_size(p))
    return out


def glb_check(path):
    """Returns the glTF JSON dict of a GLB file or raises ValueError."""
    with open(path, "rb") as f:
        data = f.read()
    if len(data) < 20 or data[:4] != b"glTF":
        raise ValueError("GLB magic missing")
    version, length = struct.unpack("<II", data[4:12])
    if version != 2:
        raise ValueError("glTF version %d, expected 2" % version)
    if length != len(data):
        raise ValueError("GLB length field %d != file size %d" % (length, len(data)))
    clen, ctype = struct.unpack("<II", data[12:20])
    if ctype != 0x4E4F534A:  # "JSON"
        raise ValueError("first GLB chunk is not JSON")
    try:
        return json.loads(data[20:20 + clen].decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as e:
        raise ValueError("GLB JSON chunk does not parse: %s" % e)


# ---------- manifest with lock and atomic write ---------------------------------------------

class Manifest:
    def __init__(self, path):
        self.path = path
        self.lock = path + ".lock"
        self.data = {"schema": 1, "records": []}

    def __enter__(self):
        deadline = time.time() + 60
        while True:
            try:
                fd = os.open(self.lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
                os.write(fd, str(os.getpid()).encode())
                os.close(fd)
                break
            except FileExistsError:
                if time.time() - os.path.getmtime(self.lock) > 300:
                    os.remove(self.lock)  # stale lock from a crashed run
                    continue
                if time.time() > deadline:
                    raise SystemExit("manifest lock held too long: " + self.lock)
                time.sleep(0.2)
        if os.path.exists(self.path):
            with open(self.path, encoding="utf-8") as f:
                self.data = json.load(f)
        return self

    def __exit__(self, *exc):
        try:
            if exc[0] is None:
                tmp = self.path + ".tmp"
                with open(tmp, "w", encoding="utf-8", newline="\n") as f:
                    json.dump(self.data, f, indent=2, ensure_ascii=False)
                    f.write("\n")
                os.replace(tmp, self.path)  # atomic on the same volume
        finally:
            os.remove(self.lock)
        return False

    def upsert(self, rec):
        recs = self.data["records"]
        for i, r in enumerate(recs):
            if r["id"] == rec["id"]:
                recs[i] = rec
                return
        recs.append(rec)


# ---------- commands -----------------------------------------------------------------------

def _abs(root, rel):
    return os.path.normpath(os.path.join(root, rel))


def cmd_register(args, root, manifest_path):
    try:
        return _register(args, root, manifest_path)
    except (ValueError, OSError) as e:  # bad header or unreadable file: refuse, do not crash
        raise SystemExit("cannot read asset: %s" % e)


def _register(args, root, manifest_path):
    if args.kind not in KINDS:
        raise SystemExit("kind must be one of %s" % (KINDS,))
    if args.source not in SOURCES:
        raise SystemExit("source must be one of %s" % (SOURCES,))
    if args.license not in LICENCES:
        raise SystemExit("licence %r is not on the allow-list %s" % (args.license, LICENCES))
    third = args.source.startswith(THIRD_PARTY_PREFIX)
    if third and args.license != "CC0-1.0":
        raise SystemExit("third-party assets must be CC0-1.0")
    if not third and args.license != "project-owned":
        raise SystemExit("generated assets must be project-owned")
    if third and not (args.source_url or "").startswith("https://"):
        raise SystemExit("third-party records need an https --source-url")
    full = _abs(root, args.path)
    if not os.path.exists(full):
        raise SystemExit("path does not exist: " + args.path)
    sizes = {}
    if args.kind in ("texture", "hdri"):
        sizes = texture_sizes(full)
        if not sizes:
            raise SystemExit("no image files under " + args.path)
        if args.tex_size:
            want = [int(v) for v in args.tex_size.lower().split("x")]
            bad = [k for k, v in sizes.items() if v != want]
            if bad:
                raise SystemExit("texture size mismatch for %s (want %s)" % (bad, args.tex_size))
    if args.kind == "model":
        if not os.path.isfile(full):
            raise SystemExit("model must be a single GLB file")
        glb_check(full)
    sha, nbytes = hash_path(full)
    rec = {
        "id": args.id, "kind": args.kind, "path": args.path.replace("\\", "/"),
        "source": args.source, "source_url": args.source_url or "",
        "license": args.license, "author": args.author or ("project" if not third else ""),
        "tris": int(args.tris or 0), "texture_sizes": sizes,
        "material_count": int(args.materials or 0), "bytes": nbytes, "sha256": sha,
        "test_result": "unvalidated", "added": datetime.date.today().isoformat(),
        "notes": args.notes or "",
    }
    with Manifest(manifest_path) as m:
        m.upsert(rec)
    print("registered %s (%s, %d bytes, sha256 %s...)" % (args.id, args.kind, nbytes, sha[:12]))
    return 0


def check_record(rec, root):
    """Returns a list of failure strings; empty means pass."""
    fails = []
    full = _abs(root, rec["path"])
    if not os.path.exists(full):
        return ["file missing: " + rec["path"]]
    sha, _ = hash_path(full)
    if sha != rec["sha256"]:
        fails.append("sha256 mismatch")
    if rec["license"] not in LICENCES:
        fails.append("licence not on allow-list: " + str(rec["license"]))
    if rec["source"].startswith(THIRD_PARTY_PREFIX):
        if not str(rec.get("source_url", "")).startswith("https://"):
            fails.append("third-party record without https source_url")
        if rec["license"] != "CC0-1.0":
            fails.append("third-party record not CC0-1.0")
    if rec["kind"] == "model":
        try:
            glb_check(full)
        except (ValueError, OSError) as e:
            fails.append("GLB: %s" % e)
    if rec["kind"] in ("texture", "hdri"):
        try:
            sizes = texture_sizes(full)
        except (ValueError, OSError) as e:
            return fails + ["image header: %s" % e]
        if not sizes:
            fails.append("no image files")
        for name, (w, h) in sizes.items():
            pot = w > 0 and h > 0 and not (w & (w - 1)) and not (h & (h - 1))
            # textures are square; HDRIs are equirectangular 2:1
            shape_ok = (w == h) if rec["kind"] == "texture" else (w == 2 * h)
            if not (pot and shape_ok):
                fails.append("%s is %dx%d, not a power-of-two %s" % (
                    name, w, h, "square" if rec["kind"] == "texture" else "2:1 panorama"))
        if rec["kind"] == "texture" and rec.get("texture_sizes") and rec["texture_sizes"] != sizes:
            fails.append("texture sizes differ from registration")
    return fails


def cmd_validate(args, root, manifest_path):
    if not os.path.exists(manifest_path):
        raise SystemExit("no manifest at " + manifest_path)
    bad = 0
    rows = []
    with Manifest(manifest_path) as m:
        for rec in m.data["records"]:
            fails = check_record(rec, root)
            rec["test_result"] = "pass" if not fails else "fail: " + "; ".join(fails)
            if fails:
                bad += 1
            rows.append((rec["id"], rec["kind"], rec["source"], rec["license"], rec["test_result"]))
    w = [max(len(str(r[i])) for r in rows + [("id", "kind", "source", "licence", "result")]) for i in range(5)]
    hdr = ("id", "kind", "source", "licence", "result")
    print(" | ".join(h.ljust(w[i]) for i, h in enumerate(hdr)))
    print("-+-".join("-" * x for x in w))
    for r in rows:
        print(" | ".join(str(v).ljust(w[i]) for i, v in enumerate(r)))
    print("%d record(s), %d failing" % (len(rows), bad))
    return 1 if bad else 0


def cmd_licenses(args, root, manifest_path, out_path):
    if not os.path.exists(manifest_path):
        raise SystemExit("no manifest at " + manifest_path)
    with open(manifest_path, encoding="utf-8") as f:
        recs = [r for r in json.load(f)["records"] if r["source"].startswith(THIRD_PARTY_PREFIX)]
    lines = [
        "# Third-party licences",
        "",
        "Generated by `tools/asset_factory.py licenses` from `ASSET_MANIFEST.json`. Do not hand-edit.",
        "",
        "All third-party assets listed here are CC0 1.0 (public domain dedication). Attribution is",
        "not required by the licence; the authors are credited anyway. Source: Poly Haven,",
        "https://polyhaven.com/license.",
        "",
        "| id | kind | source | URL | licence | author | where used | downloaded | sha256 (first 12) |",
        "|---|---|---|---|---|---|---|---|---|",
    ]
    for r in sorted(recs, key=lambda r: r["id"]):
        lines.append("| %s | %s | %s | %s | %s | %s | %s | %s | %s |" % (
            r["id"], r["kind"], r["source"], r["source_url"], r["license"], r["author"] or "-",
            (r.get("notes") or "-").replace("|", "/"), r["added"], r["sha256"][:12]))
    lines.append("")
    tmp = out_path + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))
    os.replace(tmp, out_path)
    print("wrote %s (%d third-party rows)" % (out_path, len(recs)))
    return 0


# ---------- self-test ----------------------------------------------------------------------

def _make_png(path, w, h):
    rows = []
    for y in range(h):
        row = bytearray([0])
        for x in range(w):
            row += bytes([(x * 7) & 255, (y * 5) & 255, 128])
        rows.append(bytes(row))
    data = b"".join(rows)

    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(data)) + chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(png)


def _make_glb(path, bad_magic=False):
    js = json.dumps({"asset": {"version": "2.0"}}).encode("utf-8")
    js += b" " * ((4 - len(js) % 4) % 4)
    total = 12 + 8 + len(js)
    magic = b"XXXX" if bad_magic else b"glTF"
    with open(path, "wb") as f:
        f.write(magic + struct.pack("<II", 2, total) + struct.pack("<II", len(js), 0x4E4F534A) + js)


def cmd_selftest():
    fails = []

    def ok(cond, what):
        print(("PASS " if cond else "FAIL ") + what)
        if not cond:
            fails.append(what)

    with tempfile.TemporaryDirectory() as tmp:
        root = os.path.join(tmp, "repo")
        os.makedirs(os.path.join(root, "tex", "set"))
        os.makedirs(os.path.join(root, "models"))
        _make_png(os.path.join(root, "tex", "set", "basecolor.png"), 8, 8)
        _make_png(os.path.join(root, "tex", "set", "normal.png"), 8, 8)
        _make_glb(os.path.join(root, "models", "car.glb"))
        _make_glb(os.path.join(root, "models", "bad.glb"), bad_magic=True)
        man = os.path.join(root, "ASSET_MANIFEST.json")
        third_party = os.path.join(root, "THIRD_PARTY_LICENSES.md")

        def reg(*extra):
            base = ["--root", root, "--manifest", man, "register"]
            ns = argparse.Namespace(**parse_register(base + list(extra)))
            return cmd_register(ns, root, man)

        ok(_run_reg(reg, "--id", "set_ok", "--kind", "texture", "--path", "tex/set",
                    "--source", "cc0:polyhaven", "--source-url", "https://polyhaven.com/a/x",
                    "--license", "CC0-1.0", "--author", "A", "--notes", "test") == 0, "register CC0 texture set")
        ok(_run_reg(reg, "--id", "car", "--kind", "model", "--path", "models/car.glb",
                    "--source", "generated:blender", "--license", "project-owned", "--tris", "12") == 0,
           "register generated GLB")
        ok(_run_reg(reg, "--id", "bad_licence", "--kind", "texture", "--path", "tex/set",
                    "--source", "cc0:polyhaven", "--source-url", "https://x.example/a",
                    "--license", "GPL-3.0") == 2, "reject licence off allow-list")
        ok(_run_reg(reg, "--id", "no_url", "--kind", "texture", "--path", "tex/set",
                    "--source", "cc0:polyhaven", "--license", "CC0-1.0") == 2, "reject third-party without URL")
        ok(_run_reg(reg, "--id", "bad_glb", "--kind", "model", "--path", "models/bad.glb",
                    "--source", "generated:blender", "--license", "project-owned") == 2, "reject bad GLB magic at register")
        ok(_run_reg(reg, "--id", "wrong_size", "--kind", "texture", "--path", "tex/set",
                    "--source", "generated:script", "--license", "project-owned",
                    "--tex-size", "512x256") == 2, "reject texture size mismatch")
        rc = cmd_validate(argparse.Namespace(), root, man)
        ok(rc == 0, "validate passes on clean set")
        # corrupt a file: validate must fail with exit 1
        with open(os.path.join(root, "tex", "set", "normal.png"), "ab") as f:
            f.write(b"x")
        ok(cmd_validate(argparse.Namespace(), root, man) == 1, "validate fails after file edit (sha256)")
        _make_png(os.path.join(root, "tex", "set", "normal.png"), 8, 8)
        ok(cmd_validate(argparse.Namespace(), root, man) == 0, "validate passes again after restoring file")
        ok(cmd_licenses(argparse.Namespace(), root, man, third_party) == 0, "licences writes report")
        text = open(third_party, encoding="utf-8").read()
        ok("| set_ok |" in text and "| car |" not in text, "report lists third-party rows only")
        ok(image_size(os.path.join(root, "tex", "set", "basecolor.png")) == (8, 8), "PNG header size reads 8x8")

    print("selftest: %d failure(s)" % len(fails))
    return 1 if fails else 0


def parse_register(argv):
    p = argparse.ArgumentParser(add_help=False)
    p.add_argument("--root")
    p.add_argument("--manifest")
    p.add_argument("command")
    p.add_argument("--id", required=True)
    p.add_argument("--kind", required=True)
    p.add_argument("--path", required=True)
    p.add_argument("--source", required=True)
    p.add_argument("--source-url", default="")
    p.add_argument("--license", required=True)
    p.add_argument("--author", default="")
    p.add_argument("--tris", default="0")
    p.add_argument("--tex-size", default="")
    p.add_argument("--materials", default="0")
    p.add_argument("--notes", default="")
    ns = p.parse_args(argv)
    return vars(ns)


def _run_reg(reg, *argv):
    """Run register with SystemExit turned into an exit code; prints the message."""
    try:
        return reg(*argv)
    except SystemExit as e:
        msg = e.code if isinstance(e.code, str) else ""
        if msg:
            print("refused: " + msg)
        return 2


# ---------- main ---------------------------------------------------------------------------

def main(argv):
    g = argparse.ArgumentParser(add_help=True)
    g.add_argument("--root", default=REPO)
    g.add_argument("--manifest", default=None)
    g.add_argument("command", choices=["register", "validate", "licenses", "selftest"])
    known, rest = g.parse_known_args(argv)
    root = os.path.abspath(known.root)
    man = known.manifest or os.path.join(root, "ASSET_MANIFEST.json")
    if known.command == "selftest":
        return cmd_selftest()
    if known.command == "validate":
        return cmd_validate(None, root, man)
    if known.command == "licenses":
        return cmd_licenses(None, root, man, os.path.join(root, "THIRD_PARTY_LICENSES.md"))
    ns = parse_register([known.command] + rest)
    ns = argparse.Namespace(**ns)
    try:
        return cmd_register(ns, root, man)
    except SystemExit as e:
        if isinstance(e.code, str):
            print("refused: " + e.code, file=sys.stderr)
            return 2
        raise


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
