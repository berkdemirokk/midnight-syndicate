"""UDP impairment relay for the LAN race tests (ENet runs over UDP).

Clients connect to --listen (host:port) and the relay forwards their datagrams to the real server at --server
(host:port). Server replies are relayed back to the client they belong to. Every datagram, in both directions, is
delayed by half the configured RTT plus or minus up to half the jitter, dropped with probability --loss, and
duplicated with probability --dup (the copy gets its own delay, so duplicates can also arrive out of order).
Random draws come from --seed, so a run is repeatable. Datagrams only go to the given server address.

Stats (per direction) are written as JSON to --stats when the stop file appears, or on Ctrl+C.
Usage: py -3.10 tools/net_impair_proxy.py --listen 127.0.0.1:24591 --server 127.0.0.1:24590 --rtt-ms 150 --loss 0.02
       --stats out/proxy.json --stop-file out/proxy.stop
Self check (loopback only, no Godot): py -3.10 tools/net_impair_proxy.py --selftest
"""

import argparse
import heapq
import json
import os
import random
import socket
import sys
import threading
import time


class Relay:
    def __init__(self, listen, server, rtt_ms, jitter_ms, loss, dup, seed):
        self.listen = listen
        self.server = server
        self.half = max(rtt_ms, 0.0) / 2000.0  # one way, seconds
        self.jitter = max(jitter_ms, 0.0) / 1000.0
        self.loss = min(max(loss, 0.0), 1.0)
        self.dup = min(max(dup, 0.0), 1.0)
        self.rng = random.Random(seed)
        self.cond = threading.Condition()
        self.heap = []  # (due, n, direction, sock, data, dest)
        self.n = 0
        self.stopping = False
        self.clients = {}  # client addr -> upstream socket
        self.lock = threading.Lock()
        self.stats = {d: {"in": 0, "sent": 0, "lost": 0, "duplicated": 0, "bytes_in": 0}
                      for d in ("to_server", "to_client")}
        self.max_queue = 0
        self.front = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.front.bind(listen)
        self.front.settimeout(0.2)

    def _delay(self):
        j = self.rng.uniform(-self.jitter, self.jitter) if self.jitter > 0 else 0.0
        return max(self.half + j, 0.0)

    def _schedule(self, direction, sock, data, dest):
        with self.lock:
            st = self.stats[direction]
            st["in"] += 1
            st["bytes_in"] += len(data)
            if self.rng.random() < self.loss:
                st["lost"] += 1
                return
            copies = 1
            if self.rng.random() < self.dup:
                copies = 2
                st["duplicated"] += 1
            delays = [self._delay() for _ in range(copies)]
        with self.cond:
            now = time.monotonic()
            for d in delays:
                self.n += 1
                heapq.heappush(self.heap, (now + d, self.n, direction, sock, data, dest))
            self.max_queue = max(self.max_queue, len(self.heap))
            self.cond.notify()

    def _upstream(self, client):
        with self.lock:
            sock = self.clients.get(client)
            if sock is None:
                sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                sock.bind((self.server[0], 0))  # same address family and route as the server (LAN IP or loopback)
                sock.settimeout(0.2)
                self.clients[client] = sock
                threading.Thread(target=self._pump_back, args=(client, sock), daemon=True).start()
            return sock

    def _pump_back(self, client, sock):
        while not self.stopping:
            try:
                data, src = sock.recvfrom(65535)
            except socket.timeout:
                continue
            except OSError:
                return
            if src == self.server:
                self._schedule("to_client", self.front, data, client)

    def _pump_front(self):
        while not self.stopping:
            try:
                data, src = self.front.recvfrom(65535)
            except socket.timeout:
                continue
            except OSError:
                return
            self._schedule("to_server", self._upstream(src), data, self.server)

    def _sender(self):
        while True:
            with self.cond:
                while not self.stopping and (not self.heap or self.heap[0][0] > time.monotonic()):
                    wait = (self.heap[0][0] - time.monotonic()) if self.heap else 0.2
                    self.cond.wait(min(max(wait, 0.0), 0.2))
                if not self.heap:
                    if self.stopping:
                        return
                    continue
                if self.stopping and self.heap[0][0] > time.monotonic() + 0.5:
                    return  # packets not due within the stop grace period are dropped
                _, _, direction, sock, data, dest = heapq.heappop(self.heap)
            try:
                sock.sendto(data, dest)
                with self.lock:
                    self.stats[direction]["sent"] += 1
            except OSError:
                pass

    def start(self):
        for target in (self._pump_front, self._sender):
            threading.Thread(target=target, daemon=True).start()

    def stop(self):
        self.stopping = True
        with self.cond:
            self.cond.notify_all()
        time.sleep(0.6)
        self.front.close()
        for sock in self.clients.values():
            sock.close()

    def report(self):
        return {
            "listen": "%s:%d" % self.listen,
            "server": "%s:%d" % self.server,
            "one_way_delay_ms": round(self.half * 1000.0, 3),
            "jitter_ms": round(self.jitter * 1000.0, 3),
            "loss": self.loss,
            "dup": self.dup,
            "clients_seen": len(self.clients),
            "max_queue": self.max_queue,
            "directions": self.stats,
        }


def windows_timer_resolution():
    # Windows sleeps in ~15.6 ms steps by default, which would smear a 20 ms impairment step. 1 ms is enough here.
    if os.name == "nt":
        try:
            import ctypes
            ctypes.windll.winmm.timeBeginPeriod(1)
        except OSError:
            pass


def parse_addr(text):
    host, port = text.rsplit(":", 1)
    return (host, int(port))


def selftest():
    windows_timer_resolution()
    srv = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    srv.bind(("127.0.0.1", 0))
    srv.settimeout(2.0)
    relay = Relay(("127.0.0.1", 0), srv.getsockname(), 100.0, 0.0, 0.0, 0.0, 1)
    relay.front.close()
    relay.front = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    relay.front.bind(("127.0.0.1", 0))
    relay.front.settimeout(0.2)
    relay.listen = relay.front.getsockname()
    relay.start()
    cli = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    cli.settimeout(2.0)
    rtts = []
    for i in range(20):
        t0 = time.monotonic()
        cli.sendto(b"x%d" % i, relay.listen)
        data, src = srv.recvfrom(100)
        srv.sendto(data, src)
        back, _ = cli.recvfrom(100)
        assert back == b"x%d" % i, "echo mismatch"
        rtts.append((time.monotonic() - t0) * 1000.0)
    med = sorted(rtts)[len(rtts) // 2]
    ok_rtt = 95.0 <= med <= 140.0
    relay.loss = 1.0
    cli.sendto(b"lost", relay.listen)
    try:
        srv.settimeout(0.5)
        srv.recvfrom(100)
        ok_loss = False
    except socket.timeout:
        ok_loss = True
    relay.stop()
    print(json.dumps({"median_rtt_ms": round(med, 1), "rtt_ok": ok_rtt, "total_loss_ok": ok_loss}))
    return 0 if ok_rtt and ok_loss else 1


def main():
    if "--selftest" in sys.argv:
        return selftest()
    windows_timer_resolution()
    ap = argparse.ArgumentParser()
    ap.add_argument("--listen", required=True)
    ap.add_argument("--server", required=True)
    ap.add_argument("--rtt-ms", type=float, default=0.0)
    ap.add_argument("--jitter-ms", type=float, default=0.0)
    ap.add_argument("--loss", type=float, default=0.0)
    ap.add_argument("--dup", type=float, default=0.0)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--stats", default="")
    ap.add_argument("--stop-file", default="")
    a = ap.parse_args()
    relay = Relay(parse_addr(a.listen), parse_addr(a.server), a.rtt_ms, a.jitter_ms, a.loss, a.dup, a.seed)
    relay.start()
    print("[proxy] %s -> %s, one-way %.1f ms, jitter %.1f ms, loss %.3f, dup %.3f" % (
        a.listen, a.server, relay.half * 1000, relay.jitter * 1000, relay.loss, relay.dup), flush=True)
    try:
        while not (a.stop_file and os.path.exists(a.stop_file)):
            time.sleep(0.2)
    except KeyboardInterrupt:
        pass
    relay.stop()
    rep = relay.report()
    if a.stats:
        os.makedirs(os.path.dirname(os.path.abspath(a.stats)), exist_ok=True)
        with open(a.stats, "w", encoding="utf-8") as f:
            json.dump(rep, f, indent=2)
    print("[proxy] stopped: %s" % json.dumps(rep["directions"]), flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
