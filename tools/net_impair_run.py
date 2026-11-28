"""One impaired LAN race: 1 server + 3 clients (Godot headless) with a UDP impairment relay between them.

Starts the server on ADDRESS:PORT, the relay on ADDRESS:PORT+1 (clients connect there, the relay forwards to the
server), then three clients. Scenarios:
  plain       all three finish the race.
  kill_rejoin Bo is killed KILL_AFTER s after GO (no BYE) and relaunched at once with the same name and join code.
              The server hands Bo's seat back with the car's last accepted state; Bo continues and finishes.
  leave_gone  Cy leaves cleanly (BYE) LEAVE_AFTER s after GO and never comes back. The server holds the seat for
              the grace period, then Cy is DNF with reason disconnected.
Checks, metrics and the per-run summary go to evidence/net_impair/<run>/summary.json. The join code is random per run
and is passed on the command line only. Exit code 0 only when every check passes.

Usage: py -3.10 tools/net_impair_run.py --run NAME [--rtt-ms 150] [--jitter-ms 10] [--loss 0.02] [--dup 0.005]
       [--address 127.0.0.1] [--port 24700] [--scenario plain] [--seed 1]
"""

import argparse
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
CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"  # same as NetConfig.CODE_ALPHABET
CLIENTS = ["Ada", "Bo"]  # the start rule begins the countdown at 2 ready, so a third racer is refused


def read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return ""


def wait_for(path, needle, timeout_s, proc=None):
    end = time.time() + timeout_s
    while time.time() < end:
        if needle in read(path):
            return True
        if proc is not None and proc.poll() is not None:
            return False
        time.sleep(0.2)
    return False


def parse_rows(line):
    rows = []
    for m in re.finditer(r'"pid": (\d+), "name": "([^"]*)", "position": (\d+), "finished": (true|false), '
                         r'"dnf": (true|false), "time": ([-\d.e+]+)', line):
        rows.append({"pid": int(m.group(1)), "name": m.group(2), "position": int(m.group(3)),
                     "finished": m.group(4) == "true", "dnf": m.group(5) == "true", "time_s": float(m.group(6))})
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--run", required=True)
    ap.add_argument("--godot", default=DEFAULT_GODOT)
    ap.add_argument("--address", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=24700)
    ap.add_argument("--rtt-ms", type=float, default=0.0)
    ap.add_argument("--jitter-ms", type=float, default=0.0)
    ap.add_argument("--loss", type=float, default=0.0)
    ap.add_argument("--dup", type=float, default=0.0)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--scenario", choices=["plain", "kill_rejoin", "leave_gone"], default="plain")
    ap.add_argument("--kill-after", type=float, default=12.0)
    ap.add_argument("--leave-after", type=float, default=12.0)
    ap.add_argument("--timeout", type=int, default=420)
    ap.add_argument("--direct", action="store_true", help="clients connect straight to the server (no relay)")
    a = ap.parse_args()

    code = "".join(secrets.choice(CODE_ALPHABET) for _ in range(6))
    out = os.path.join(ROOT, "evidence", "net_impair", a.run)
    os.makedirs(out, exist_ok=True)
    proxy_port = a.port + 1
    client_port = a.port if a.direct else proxy_port  ## --direct: no relay, a baseline for the relay itself
    stop_file = os.path.join(out, "proxy.stop")
    if os.path.exists(stop_file):
        os.remove(stop_file)
    procs, handles = {}, []

    def godot(role, name=None, port=a.port, extra=()):
        args = [a.godot, "--headless", "--audio-driver", "Dummy", "--path", GAME,
                "-s", "res://net/net_lan_smoke.gd", "--", "--role=" + role, "--port=%d" % port,
                "--address=%s" % a.address, "--laps=1", "--code=" + code]
        if name:
            args.append("--name=" + name)
        return args + list(extra)

    def start(key, args, log_name):
        fh = open(os.path.join(out, log_name), "w", encoding="utf-8")
        handles.append(fh)
        procs[key] = subprocess.Popen(args, stdout=fh, stderr=subprocess.STDOUT, cwd=ROOT)
        return procs[key]

    try:
        start("server", godot("server"), "server.log")
        if not wait_for(os.path.join(out, "server.log"), "[smoke] server up", 90, procs["server"]):
            raise SystemExit("server did not come up")
        proxy_args = [sys.executable, os.path.join(ROOT, "tools", "net_impair_proxy.py"),
                      "--listen", "%s:%d" % (a.address, proxy_port), "--server", "%s:%d" % (a.address, a.port),
                      "--rtt-ms", str(a.rtt_ms), "--jitter-ms", str(a.jitter_ms), "--loss", str(a.loss),
                      "--dup", str(a.dup), "--seed", str(a.seed), "--stats", os.path.join(out, "proxy.json"),
                      "--stop-file", stop_file]
        if not a.direct:
            start("proxy", proxy_args, "proxy.log")
            if not wait_for(os.path.join(out, "proxy.log"), "[proxy]", 20, procs["proxy"]):
                raise SystemExit("proxy did not start")
        for n in CLIENTS:
            extra = ["--wait-players=%d" % len(CLIENTS)]
            if a.scenario == "leave_gone" and n == "Bo":
                extra.append("--leave-after=%s" % a.leave_after)
            start(n, godot("client", n, client_port, extra), "client_%s.log" % n.lower())
            time.sleep(1.0)
        resumed = None
        if a.scenario == "kill_rejoin":
            if wait_for(os.path.join(out, "client_bo.log"), "[smoke] Bo GO", 150, procs["Bo"]):
                time.sleep(a.kill_after)
                procs["Bo"].kill()
                procs["Bo"].wait()
                resumed = start("Bo2", godot("client", "Bo", client_port), "client_bo_resumed.log")
        deadline = time.time() + a.timeout
        for key in ["server"] + CLIENTS + (["Bo2"] if resumed else []):
            if key not in procs:
                continue
            try:
                procs[key].wait(max(1, deadline - time.time()))
            except subprocess.TimeoutExpired:
                procs[key].kill()
                procs[key].wait()
                print("[check] %s killed after the timeout" % key)
    finally:
        open(stop_file, "w").close()
        if "proxy" in procs:
            try:
                procs["proxy"].wait(30)
            except subprocess.TimeoutExpired:
                procs["proxy"].kill()
        for p in procs.values():
            if p.poll() is None:
                p.kill()
        for fh in handles:
            fh.close()

    srv = read(os.path.join(out, "server.log"))
    cl = {n: read(os.path.join(out, "client_%s.log" % n.lower())) for n in CLIENTS}
    bo_res = read(os.path.join(out, "client_bo_resumed.log")) if resumed else ""
    server_rows = parse_rows(next((ln for ln in srv.splitlines() if ln.startswith("[net] results:")), ""))
    rejects = {}
    for m in re.finditer(r"\[net\] reject state pid \d+: (\w+)", srv):
        rejects[m.group(1)] = rejects.get(m.group(1), 0) + 1
    acc_m = re.search(r"accepted states per pid: \{([^}]*)\}", srv)
    accepted = {int(k): int(v) for k, v in re.findall(r"(\d+): (\d+)", acc_m.group(1))} if acc_m else {}
    proxy = {}
    if os.path.exists(os.path.join(out, "proxy.json")):
        proxy = json.load(open(os.path.join(out, "proxy.json"), encoding="utf-8"))["directions"]

    checks = {}
    checks["server_exit_0"] = procs["server"].returncode == 0
    checks["joins_2"] = len(re.findall(r"\[net\] join pid", srv)) == 2
    checks["start_2_racers"] = "[net] start: 2 racers" in srv
    checks["server_go"] = "[net] GO, server race clock starts" in srv
    checks["server_results_2_rows"] = len(server_rows) == 2
    per_client = {}
    for n in CLIENTS:
        text = cl[n]
        m = re.search(r"sent (\d+) states \(([\d.]+) Hz\), received (\d+) snapshots \(([\d.]+) Hz\), rejected (\d+), "
                      r"rtt_ms last ([\d.]+) min ([\d.]+) avg ([\d.]+)", text)
        rows = parse_rows(next((ln for ln in text.splitlines() if "results:" in ln and "server" not in ln), ""))
        per_client[n] = {
            "sent": int(m.group(1)) if m else None, "sent_hz": float(m.group(2)) if m else None,
            "snapshots": int(m.group(3)) if m else None, "snapshot_hz": float(m.group(4)) if m else None,
            "client_rejected": int(m.group(5)) if m else None,
            "rtt_ms_last_min_avg": [float(m.group(i)) for i in (6, 7, 8)] if m else None,
            "results": rows,
        }
    # Who must receive the results: everyone, except the client that left for good (leave_gone) and the killed
    # process (kill_rejoin, whose results come from the resumed process).
    must_result = {"plain": CLIENTS, "leave_gone": ["Ada"], "kill_rejoin": ["Ada", "Bo"]}[a.scenario]
    for n in must_result:
        checks["%s_results" % n.lower()] = len(per_client[n]["results"]) == 2
    if a.scenario == "kill_rejoin":
        checks["server_resumed_bo"] = "[net] resume pid" in srv
        checks["bo_resumed_go"] = "[smoke] Bo GO (resumed)" in bo_res
        checks["bo_resumed_results"] = len(parse_rows(next((ln for ln in bo_res.splitlines()
                                                             if "results:" in ln and "server" not in ln), ""))) == 2
    if a.scenario == "leave_gone":
        checks["bo_left_bye"] = "leaves the race (bye, no rejoin)" in cl["Bo"]
        checks["seat_held"] = "dropped in the race, seat held" in srv
        checks["bo_dnf_after_grace"] = "did not come back within the grace period: DNF" in srv
        bo_row = next((r for r in server_rows if r["name"] == "Bo"), None)
        checks["bo_dnf_in_results"] = bool(bo_row and bo_row["dnf"] and not bo_row["finished"])
    # Finish order agreement: every client and the server list the same order.
    ref = [(r["name"], r["position"]) for r in sorted(server_rows, key=lambda r: r["position"])]
    agree = {}
    for n in CLIENTS:
        rows = per_client[n]["results"]
        if rows:
            agree[n] = [(r["name"], r["position"]) for r in sorted(rows, key=lambda r: r["position"])] == ref
    if a.scenario == "kill_rejoin" and parse_rows(bo_res):
        agree["Bo_resumed"] = [(r["name"], r["position"]) for r in sorted(parse_rows(bo_res),
                                                                          key=lambda r: r["position"])] == ref
    checks["finish_order_agrees"] = bool(ref) and bool(agree) and all(agree.values())
    checks["a_car_finished"] = any(r["finished"] for r in server_rows)
    summary = {
        "run": a.run, "scenario": a.scenario, "address": a.address,
        "impairment": {"rtt_ms": a.rtt_ms, "jitter_ms": a.jitter_ms, "loss": a.loss, "dup": a.dup, "seed": a.seed},
        "checks": checks, "passed": all(checks.values()),
        "server_results": server_rows,
        "server_rejects_by_reason": rejects,
        "server_accepted_by_pid": accepted,
        "proxy_directions": proxy,
        "clients": per_client,
        "finish_order_agrees": agree,
    }
    with open(os.path.join(out, "summary.json"), "w", encoding="utf-8") as f:
        json.dump(summary, f, indent=2)
    for k, v in checks.items():
        print("[check] %-24s %s" % (k, "ok" if v else "FAIL"))
    print("[net_impair] %s %s, summary %s" % (a.run, "PASS" if summary["passed"] else "FAIL",
                                             os.path.join(out, "summary.json")))
    return 0 if summary["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
