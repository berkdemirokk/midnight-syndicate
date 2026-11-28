#!/usr/bin/env python3
# Proves player progression survives a restart, across separate Godot processes.
#
# Runs game/tests/persist_restart_driver.gd as separate headless Godot processes against a temporary
# save file (an absolute path outside user://, so the real save is never written):
#   1. setup  - process A starts a career (car, paint, rim, upgrades, event results, selection) and saves it.
#   2. verify - process B loads the save; its snapshot must equal the setup snapshot. Cash is also checked
#               against an independently computed 69061.
#   3. crash  - process C saves in a loop and is killed while save.json.tmp exists (retried up to 5 times).
#               The main file must still parse, and the backup must be the last good save (equal to main
#               or one behind). Then a verify run must load the main file.
#   4. torn   - the main file is cut in half (what a torn write leaves). Verify must load the backup and
#               report source=backup with the backup rep.
# Exit 0 only when every check passes. The real save (APPDATA/Godot/app_userdata/Midnight Syndicate/save.json)
# is hashed before and after and must not change.
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

GODOT = os.environ.get("GODOT", r"C:\Users\berk\tools\godot\Godot_v4.7.2-stable_win64_console.exe")
GAME = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "game"))
DRIVER = "res://tests/persist_restart_driver.gd"
REAL_SAVE = os.path.join(os.environ.get("APPDATA", ""), "Godot", "app_userdata", "Midnight Syndicate", "save.json")
EXPECTED_CASH = 69061  # 5000 + 50000 - 8000 car - 800 - 1600 upgrades + 24461 rewards (17472 x1.4: reward table x1.4 again for the 24-car roster, 2026-11-28)

results = []


def check(ok, what):
    results.append((bool(ok), what))
    print(("PASS " if ok else "FAIL ") + what)
    return bool(ok)


def sha(path):
    if not os.path.exists(path):
        return "absent"
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def godot_args(phase, save, out):
    return [GODOT, "--headless", "--audio-driver", "Dummy", "--path", GAME, "-s", DRIVER,
            "--", "--phase=" + phase, "--save=" + save, "--out=" + out]


def run(phase, save, out):
    p = subprocess.run(godot_args(phase, save, out), capture_output=True, text=True, timeout=180)
    if p.returncode != 0:
        print("  driver %s exited %d: %s" % (phase, p.returncode, (p.stderr or p.stdout)[-600:]))
    return p.returncode


def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def parse_file(path):
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else None
    except (OSError, ValueError):
        return None


def differing_fields(expected, actual):
    return [k for k in expected if k != "source" and expected[k] != actual.get(k)]


def main():
    real_before = sha(REAL_SAVE)
    tmp = tempfile.mkdtemp(prefix="midnight_persist_")
    save = os.path.join(tmp, "save.json").replace("\\", "/")

    def out(name):
        return os.path.join(tmp, name).replace("\\", "/")

    print("temp save: " + save)
    try:
        # 1. process A: start the career and save it
        rc = run("setup", save, out("expected.json"))
        check(rc == 0, "process A (setup) ran and exited 0")
        expected = load(out("expected.json"))
        check(expected["cash"] == EXPECTED_CASH, "setup cash is %d (expected %d)" % (expected["cash"], EXPECTED_CASH))
        check(expected["event_stars"] == 3 and expected["total_stars"] == 5,
              "setup stars are 3 on the event and 5 in total")

        # 2. process B: a separate process loads the same file
        rc = run("verify", save, out("actual1.json"))
        check(rc == 0, "process B (verify) ran and exited 0")
        actual = load(out("actual1.json"))
        diff = differing_fields(expected, actual)
        check(not diff, "restart: every field matches after a new process loads the save%s"
              % ("" if not diff else " (differs: %s)" % ", ".join(diff)))
        check(actual.get("source") == "main", "restart loaded the main file, source=%s" % actual.get("source"))

        # 3. process C: killed in the middle of a save
        main_path = save
        bak_path = save + ".bak"
        tmp_path = save + ".tmp"
        # The kill must land while save.json.tmp exists; retry a few times so exit 0 means it did.
        killed_mid_write = False
        for attempt in range(5):
            proc = subprocess.Popen(godot_args("loop", save, out("loop.json")),
                                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            deadline = time.time() + 60
            # Wait until process C itself has saved at least twice (main rep >= setup rep + 2), so the
            # backup is one of C's saves and not the one process A left behind.
            while time.time() < deadline and proc.poll() is None:
                m = parse_file(main_path)
                if m is not None and int(m.get("rep", 0)) >= expected["rep"] + 2:
                    break
                time.sleep(0.01)
            while time.time() < deadline and proc.poll() is None:
                if os.path.exists(tmp_path):
                    killed_mid_write = True
                    break
            proc.kill()
            proc.wait()
            if killed_mid_write:
                break
        check(os.path.exists(bak_path), "a backup exists after the kill")
        check(killed_mid_write, "process C was killed while a save was in progress (.tmp present, attempt %d)" % (attempt + 1))

        main_after = parse_file(main_path)
        bak_after = parse_file(bak_path)
        check(main_after is not None, "after the kill the main file is still whole JSON")
        check(bak_after is not None, "after the kill the backup is still whole JSON")
        if main_after is not None and bak_after is not None:
            rep_main, rep_bak = int(main_after["rep"]), int(bak_after["rep"])
            check(rep_bak in (rep_main - 1, rep_main),
                  "backup rep %d is the last good save (main rep %d or one before)" % (rep_bak, rep_main))
            check(rep_bak >= expected["rep"] + 1, "process C saved at least twice before the kill (backup rep %d > setup rep %d)" % (rep_bak, expected["rep"]))
        rc = run("verify", save, out("actual2.json"))
        check(rc == 0, "process D (verify after kill) loads the file")
        actual2 = load(out("actual2.json"))
        check(actual2.get("source") == "main" and main_after is not None and actual2["rep"] == main_after["rep"],
              "after the kill the game loads the main file")
        check(actual2["cash"] == expected["cash"] and actual2["owned"] == expected["owned"]
              and actual2["selected"] == expected["selected"],
              "after the kill the career (cash, garage, selection) is intact")

        # 4. torn main file: a crash that cut the main file in half
        with open(main_path, encoding="utf-8") as f:
            text = f.read()
        with open(main_path, "w", encoding="utf-8", newline="\n") as f:
            f.write(text[: len(text) // 2])
        check(parse_file(main_path) is None, "main file is torn (cut in half) for this check")
        rc = run("verify", save, out("actual3.json"))
        check(rc == 0, "process E (verify with torn main) ran and exited 0")
        actual3 = load(out("actual3.json")) if os.path.exists(out("actual3.json")) else {}
        check(actual3.get("source") == "backup", "torn main falls back to the backup, source=%s" % actual3.get("source"))
        check(bak_after is not None and actual3["rep"] == bak_after["rep"],
              "loaded rep %s equals the backup rep" % actual3.get("rep"))
        check(actual3.get("cash") == expected["cash"] and actual3.get("owned") == expected["owned"],
              "backup keeps the career (cash, garage) intact")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    real_after = sha(REAL_SAVE)
    check(real_before == real_after, "the real save file was not touched (sha256 before equals after)")
    failed = [w for ok, w in results if not ok]
    print("== %d checks, %d failed ==" % (len(results), len(failed)))
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
