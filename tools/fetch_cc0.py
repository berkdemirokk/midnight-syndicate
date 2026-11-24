#!/usr/bin/env python3
"""Pinned CC0 texture and HDRI fetcher for MIDNIGHT SYNDICATE (Poly Haven API only).

Subcommands (run with: py -3.10 tools/fetch_cc0.py <cmd>):
  pin           query api.polyhaven.com for every asset in tools/cc0_assets.json and write the
                file URLs, md5 and sizes back into that file (run again only to re-pin).
  fetch         download pinned files to assets_src/textures/cc0/<id>/ (md5 and size checked).
  process       copy into game/assets/textures/cc0/<id>/ as basecolor.jpg, normal.jpg,
                roughness.jpg (textures) or environment.hdr (HDRIs); checks sizes are the pinned ones.
  register-all  register every processed asset in ASSET_MANIFEST.json via tools/asset_factory.py.
  all           fetch, process, register-all in that order.

Only Poly Haven is used; ambientCG is not used in this pass. No personal data and no project
name are sent: the only request header is a generic User-Agent.
"""
import argparse
import datetime
import hashlib
import json
import os
import shutil
import subprocess
import sys
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import asset_factory  # noqa: E402  (same folder; provides image_size and the manifest API)

ROOT = os.path.dirname(HERE)
CFG = os.path.join(HERE, "cc0_assets.json")
SRC = os.path.join(ROOT, "assets_src", "textures", "cc0")
DST = os.path.join(ROOT, "game", "assets", "textures", "cc0")
ALLOWED_HOSTS = ("dl.polyhaven.org", "api.polyhaven.com", "polyhaven.com")
POT = {"1k": 1024, "2k": 2048}


def load_cfg():
    with open(CFG, encoding="utf-8") as f:
        return json.load(f)


def save_cfg(cfg):
    tmp = CFG + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as f:
        json.dump(cfg, f, indent=2, ensure_ascii=False)
        f.write("\n")
    os.replace(tmp, CFG)


def http_json(cfg, url):
    req = urllib.request.Request(url, headers={"User-Agent": cfg["user_agent"]})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read().decode("utf-8"))


def check_host(url):
    from urllib.parse import urlparse
    u = urlparse(url)
    if u.scheme != "https" or u.hostname not in ALLOWED_HOSTS:
        raise SystemExit("refusing URL outside Poly Haven hosts: " + url)


def cmd_pin(cfg):
    for a in cfg["assets"]:
        info = http_json(cfg, "%s/info/%s" % (cfg["api"], a["id"]))
        files = http_json(cfg, "%s/files/%s" % (cfg["api"], a["id"]))
        want_type = 0 if a["kind"] == "hdri" else 1  # Poly Haven: 0 HDRI, 1 texture, 2 model
        if info.get("type") != want_type:
            raise SystemExit("%s: API type %r does not match kind %s" % (a["id"], info.get("type"), a["kind"]))
        lic = info.get("license")  # not provided today; if it ever is, it must be CC0
        if lic is not None and str(lic).upper() not in ("CC0", "CC0-1.0", "CC0 1.0"):
            raise SystemExit("%s: API licence %r is not CC0, skipped" % (a["id"], lic))
        pinned = {}
        for mapname, key in a["maps"].items():
            fmt = a.get("format", "jpg")
            node = files[key][a["res"]][fmt]
            check_host(node["url"])
            pinned[mapname] = {
                "file_key": key,
                "url": node["url"],
                "md5": node["md5"],
                "size": node["size"],
                "filename": node["url"].rsplit("/", 1)[-1],
            }
        a["pin"] = {
            "name": info.get("name"),
            "category": info.get("category"),
            "authors": sorted(info.get("authors", {}).keys()),
            "licence": "CC0-1.0",
            "licence_basis": "polyhaven.com/license (site-wide CC0); API licence field: %s" % ("present" if lic else "absent"),
            "source_url": "https://polyhaven.com/a/%s" % a["id"],
            "files": pinned,
            "pinned_utc": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
        }
        print("pinned %-26s %-8s %d file(s)" % (a["id"], a["res"], len(pinned)))
    save_cfg(cfg)


def md5_of(path):
    h = hashlib.md5()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def cmd_fetch(cfg):
    for a in cfg["assets"]:
        if "pin" not in a:
            raise SystemExit("%s is not pinned; run pin first" % a["id"])
        if a["pin"]["licence"] != "CC0-1.0":
            raise SystemExit("%s: licence not CC0, refusing" % a["id"])
        folder = os.path.join(SRC, a["id"])
        os.makedirs(folder, exist_ok=True)
        for mapname, f in a["pin"]["files"].items():
            dest = os.path.join(folder, f["filename"])
            if os.path.isfile(dest) and os.path.getsize(dest) == f["size"] and md5_of(dest) == f["md5"]:
                continue
            check_host(f["url"])
            part = dest + ".part"
            req = urllib.request.Request(f["url"], headers={"User-Agent": cfg["user_agent"]})
            with urllib.request.urlopen(req, timeout=300) as r, open(part, "wb") as out:
                shutil.copyfileobj(r, out, 1 << 20)
            if os.path.getsize(part) != f["size"] or md5_of(part) != f["md5"]:
                os.remove(part)
                raise SystemExit("%s/%s: size or md5 mismatch" % (a["id"], f["filename"]))
            os.replace(part, dest)
            print("fetched %s/%s (%d bytes)" % (a["id"], f["filename"], f["size"]))


def cmd_process(cfg):
    for a in cfg["assets"]:
        out = os.path.join(DST, a["id"])
        os.makedirs(out, exist_ok=True)
        src_dir = os.path.join(SRC, a["id"])
        for mapname, f in a["pin"]["files"].items():
            src = os.path.join(src_dir, f["filename"])
            if a["kind"] == "hdri":
                name = "environment.hdr"
            else:
                name = mapname + ".jpg"
            dst = os.path.join(out, name)
            shutil.copyfile(src, dst)
            w, h = asset_factory.image_size(dst)
            want = POT[a["res"]]
            # HDRIs are equirectangular (2:1); textures are square
            exp = (want, want // 2) if a["kind"] == "hdri" else (want, want)
            if (w, h) != exp or (w & (w - 1)) or (h & (h - 1)):
                raise SystemExit("%s/%s: %dx%d, expected %dx%d" % (a["id"], name, w, h, exp[0], exp[1]))
        print("processed %-26s -> %s" % (a["id"], os.path.relpath(out, ROOT)))


def cmd_register_all(cfg):
    for a in cfg["assets"]:
        folder = os.path.join(DST, a["id"])
        rel = os.path.relpath(folder, ROOT).replace("\\", "/")
        authors = ", ".join(a["pin"]["authors"]) or "Poly Haven"
        used = a.get("material", "environment light (HDRI)")
        notes = "%s: %s. Pinned in tools/cc0_assets.json." % (used, a["use"])
        cmd = [sys.executable, os.path.join(HERE, "asset_factory.py"), "register",
               "--id", a["id"], "--kind", "hdri" if a["kind"] == "hdri" else "texture",
               "--path", rel, "--source", "cc0:polyhaven",
               "--source-url", a["pin"]["source_url"], "--license", "CC0-1.0",
               "--author", authors, "--tris", "0", "--materials", "1" if a["kind"] != "hdri" else "0",
               "--notes", notes]
        subprocess.run(cmd, check=True, cwd=ROOT)


def main(argv):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("cmd", choices=["pin", "fetch", "process", "register-all", "all"])
    args = p.parse_args(argv)
    cfg = load_cfg()
    if args.cmd == "pin":
        cmd_pin(cfg)
    elif args.cmd == "fetch":
        cmd_fetch(cfg)
    elif args.cmd == "process":
        cmd_process(cfg)
    elif args.cmd == "register-all":
        cmd_register_all(cfg)
    else:
        cmd_fetch(cfg)
        cmd_process(cfg)
        cmd_register_all(cfg)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
