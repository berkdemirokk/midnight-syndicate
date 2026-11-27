"""In-game online check: 1 headless server + 1 headless client (devtools/net_smoke.gd) + 1 RENDERED game client
(capture scenario net_client: the real RaceScene and NetRaceGlue path), all on 127.0.0.1.

Usage: py -3.10 tools/net_ingame_check.py [--godot PATH] [--port 24611] [--laps 1]
Writes logs to evidence/net_ingame/ and the shots to evidence/screens/net_client/. Exit 0 when the rendered
client took all four shots and every process exited 0. Run it while no other heavy GPU job runs.
"""
import argparse
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(ROOT, "game")
OUT = os.path.join(ROOT, "evidence", "net_ingame")
DEFAULT_GODOT = r"C:\Users\berk\tools\godot\Godot_v4.7.2-stable_win64_console.exe"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--godot", default=DEFAULT_GODOT)
    ap.add_argument("--port", type=int, default=24611)
    ap.add_argument("--laps", type=int, default=1)
    a = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    base = [a.godot, "--audio-driver", "Dummy", "--path", GAME]
    smoke = base[:1] + ["--headless"] + base[1:] + ["-s", "res://devtools/net_smoke.gd", "--"]
    procs = {}
    logs = {}

    def start(key, args):
        logs[key] = open(os.path.join(OUT, key + ".log"), "w", encoding="utf-8", errors="replace")
        procs[key] = subprocess.Popen(args, stdout=logs[key], stderr=subprocess.STDOUT, cwd=ROOT)

    start("server", smoke + ["--role=server", "--port=%d" % a.port, "--laps=%d" % a.laps])
    time.sleep(2.0)
    start("client_headless", smoke + ["--role=client", "--port=%d" % a.port, "--name=Ada"])
    start("client_rendered", base + ["--resolution", "1920x1080", "--position", "20000,0",
                                     "res://devtools/capture_boot.tscn", "--", "--capture=net_client",
                                     "--port=%d" % a.port, "--name=Berk"])
    deadline = time.time() + 420
    codes = {}
    while len(codes) < len(procs) and time.time() < deadline:
        for k, p in procs.items():
            if k not in codes and p.poll() is not None:
                codes[k] = p.returncode
        # the rendered Godot can hang at exit after its capture line; kill it 30 s after the line
        if "client_rendered" not in codes:
            try:
                with open(os.path.join(OUT, "client_rendered.log"), encoding="utf-8", errors="replace") as f:
                    txt = f.read()
                if "[CAPTURE] scenario=net_client" in txt:
                    if not hasattr(main, "_seen"):
                        main._seen = time.time()
                    elif time.time() - main._seen > 30:
                        subprocess.call(["taskkill", "/T", "/F", "/PID", str(procs["client_rendered"].pid)],
                                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                        codes["client_rendered"] = 0 if "errors=0 exit=0" in txt else 1
            except OSError:
                pass
        time.sleep(1.0)
    for k, p in procs.items():
        if k not in codes:
            p.kill()
            codes[k] = 124
    for f in logs.values():
        f.close()
    print("exit codes:", codes)
    for k in procs:
        with open(os.path.join(OUT, k + ".log"), encoding="utf-8", errors="replace") as f:
            lines = [ln.rstrip() for ln in f if "[smoke]" in ln or "[net_client]" in ln or "[CAPTURE]" in ln]
        print("==", k)
        print("\n".join(lines[-12:]))
    return 0 if all(c == 0 for c in codes.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
