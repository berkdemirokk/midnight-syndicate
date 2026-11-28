"""LAN smoke test for the experimental online race: 1 server + 2 clients on 127.0.0.1.

Starts three headless Godot processes (game/devtools/net_smoke.gd), waits for them, then checks the logs:
join, ready, start (countdown), GO, per-client snapshot counts and the server-computed results. First a client with
a wrong join code must be refused. The join code is random per run (or --code=ABCDEF); it is passed on the command
line only and never written to the logs or the summary.
Exit code 0 only when every check passes. Logs and a summary go to evidence/net_smoke/<run>/.

Usage: python tools/net_smoke.py [--godot PATH] [--port 24590] [--laps 1] [--run NAME] [--timeout 600] [--code ABCDEF]
"""

import argparse
import datetime
import json
import os
import re
import secrets
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(ROOT, "game")
DEFAULT_GODOT = "C:/Users/berk/tools/godot/Godot_v4.7.2-stable_win64_console.exe"
CLIENTS = ["Ada", "Bo"]
CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"  ## same as NetConfig.CODE_ALPHABET (no 0, O, 1, I, L)
CODE_LEN = 6
WRONG_CODE = "ZZZZZZ"  ## valid form, not the host's code (unless the host code is that, then YYYYYY)


def new_code():
    return "".join(secrets.choice(CODE_ALPHABET) for _ in range(CODE_LEN))


def godot_cmd(godot, role, port, laps, name=None, code=None):
    args = [godot, "--headless", "--audio-driver", "Dummy", "--path", GAME,
            "-s", "res://devtools/net_smoke.gd", "--", "--role=" + role, "--port=%d" % port, "--laps=%d" % laps]
    if name:
        args.append("--name=" + name)
    if code:
        args.append("--code=" + code)
    return args


def read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return ""


def wait_for(path, needle, timeout_s):
    end = time.time() + timeout_s
    while time.time() < end:
        if needle in read(path):
            return True
        time.sleep(0.2)
    return False


def parse_results(line):
    rows = []
    for m in re.finditer(r'"pid": (\d+), "name": "([^"]*)", "position": (\d+), "finished": (true|false), '
                         r'"dnf": (true|false), "time": ([-\d.e+]+)', line):
        rows.append({"pid": int(m.group(1)), "name": m.group(2), "position": int(m.group(3)),
                     "finished": m.group(4) == "true", "dnf": m.group(5) == "true", "time_s": float(m.group(6))})
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--godot", default=DEFAULT_GODOT)
    ap.add_argument("--port", type=int, default=24590)
    ap.add_argument("--laps", type=int, default=1)
    ap.add_argument("--run", default=datetime.datetime.now().strftime("run_%Y%m%d_%H%M%S"))
    ap.add_argument("--timeout", type=int, default=600)
    ap.add_argument("--code", default="", help="join code for the host and the clients (random when empty)")
    a = ap.parse_args()
    code = a.code.strip().upper() or new_code()
    if len(code) != CODE_LEN or any(c not in CODE_ALPHABET for c in code):
        raise SystemExit("--code must be %d characters from %s" % (CODE_LEN, CODE_ALPHABET))
    wrong = WRONG_CODE if code != WRONG_CODE else "YYYYYY"

    out = os.path.join(ROOT, "evidence", "net_smoke", a.run)
    os.makedirs(out, exist_ok=True)
    logs = {"server": os.path.join(out, "server.log")}
    for n in CLIENTS:
        logs[n] = os.path.join(out, "client_%s.log" % n.lower())
    logs["eve"] = os.path.join(out, "client_wrong_code.log")

    procs = {}
    handles = []

    def start(key, args):
        fh = open(logs[key], "w", encoding="utf-8")
        handles.append(fh)
        procs[key] = subprocess.Popen(args, stdout=fh, stderr=subprocess.STDOUT, cwd=ROOT)

    try:
        start("server", godot_cmd(a.godot, "server", a.port, a.laps, code=code))
        if not wait_for(logs["server"], "[smoke] server up", 60):
            raise SystemExit("server did not come up, see %s" % logs["server"])
        # A client with the wrong code must be refused before anyone else joins (it exits 1 on the reject).
        start("eve", godot_cmd(a.godot, "client", a.port, a.laps, "Eve", wrong))
        try:
            procs["eve"].wait(120)
        except subprocess.TimeoutExpired:
            pass
        for n in CLIENTS:
            start(n, godot_cmd(a.godot, "client", a.port, a.laps, n, code))
            time.sleep(1.0)
        deadline = time.time() + a.timeout
        for key, p in procs.items():
            try:
                p.wait(max(1, deadline - time.time()))
            except subprocess.TimeoutExpired:
                p.kill()
                p.wait()
                print("[check] %s killed after the timeout" % key)
    finally:
        for p in procs.values():
            if p.poll() is None:
                p.kill()
        for fh in handles:
            fh.close()

    srv = read(logs["server"])
    cl = {n: read(logs[n]) for n in CLIENTS}
    checks = {}
    checks["server_exit_0"] = procs["server"].returncode == 0
    checks["wrong_code_refused"] = ("[smoke] Eve rejected: wrong join code" in read(logs["eve"])
                                    and "[net] reject hello: wrong join code" in srv)
    checks["joins_2"] = len(re.findall(r"\[net\] join pid", srv)) == 2
    checks["ready_2"] = len(re.findall(r"\[net\] ready pid \d+: true", srv)) >= 2
    checks["start_2_racers"] = "[net] start: 2 racers" in srv
    checks["track_bogaz"] = "[net] track: res://world/istanbul_bogaz/istanbul_bogaz.tscn" in srv  ## no dev circuit fallback
    checks["server_go"] = "[net] GO, server race clock starts" in srv
    checks["server_results"] = "[net] results:" in srv
    line_res = next((ln for ln in srv.splitlines() if ln.startswith("[net] results:")), "")
    rows = parse_results(line_res)
    checks["results_both_cars"] = len(rows) == 2
    checks["car_finished"] = any(r["finished"] for r in rows)  ## a run where nobody finishes is not a pass
    snaps = {}
    for n in CLIENTS:
        m = re.search(r"received (\d+) snapshots \(([\d.]+) Hz\)", cl[n])
        snaps[n] = int(m.group(1)) if m else -1
        rtt = re.search(r"rtt_ms last ([\d.]+) min ([\d.]+) avg ([\d.]+)", cl[n])
        snaps[n + "_rtt_ms"] = [float(rtt.group(i)) for i in (1, 2, 3)] if rtt else None
        checks[n + "_go"] = ("[smoke] %s GO" % n) in cl[n]
        checks[n + "_results"] = ("[smoke] %s results:" % n) in cl[n]
        checks[n + "_exit_0"] = procs[n].returncode == 0
        checks[n + "_snapshots"] = snaps[n] > 0
        orders = re.search(r"orders seen (\d+)", cl[n])
        checks[n + "_orders"] = orders is not None and int(orders.group(1)) > 0  ## live standings arrived
    acc = re.search(r"accepted states per pid: (\{[^}]*\})", srv)
    summary = {
        "run": a.run,
        "port": a.port,
        "laps": a.laps,
        "checks": checks,
        "passed": all(checks.values()),
        "server_results": rows,
        "accepted_by_pid": acc.group(1) if acc else None,
        "client_snapshots": {n: snaps[n] for n in CLIENTS},
        "client_rtt_ms_last_min_avg": {n: snaps[n + "_rtt_ms"] for n in CLIENTS},
        "exit_codes": {k: p.returncode for k, p in procs.items()},
    }
    with open(os.path.join(out, "summary.json"), "w", encoding="utf-8") as f:
        json.dump(summary, f, indent=2)
    for k, v in checks.items():
        print("[check] %-18s %s" % (k, "ok" if v else "FAIL"))
    print("[smoke] %s, summary %s" % ("PASS" if summary["passed"] else "FAIL", os.path.join(out, "summary.json")))
    return 0 if summary["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
