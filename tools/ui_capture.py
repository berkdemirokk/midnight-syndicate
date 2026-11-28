"""One harness capture at a time on the shared GPU (STREET EMPIRE UI work).

Usage: py -3.10 tools/ui_capture.py <scenario> [extra args after --, e.g. --size=2556x1179 --preset=low]

- Takes a machine-wide lock file (%TEMP%/street_empire_gpu.lock) so parallel workers queue instead of stacking renders.
- Waits until the GPU has at least MIN_FREE_MB of free memory (another session's asset generation may hold it).
- Runs the capture silently (--audio-driver Dummy), off-screen, from this checkout's game/ folder.
- Exit code = Godot's exit code (0 ok, 1 scenario failed, 2 timeout); 3 = could not get the lock or GPU memory in time.
Log: %TEMP%/street_empire_capture_<scenario>.log
"""
import os
import subprocess
import sys
import time

GODOT = r"C:\Users\berk\tools\godot\Godot_v4.7.2-stable_win64_console.exe"
LOCK = os.path.join(os.environ.get("TEMP", "."), "street_empire_gpu.lock")
MIN_FREE_MB = 1800
WAIT_S = 1800
STALE_S = 900  # a lock older than this belonged to a crashed run


def free_mb() -> int:
    try:
        out = subprocess.run(["nvidia-smi", "--query-gpu=memory.total,memory.used", "--format=csv,noheader,nounits"],
                             capture_output=True, text=True, timeout=10).stdout.strip().splitlines()[0]
        total, used = (int(v) for v in out.split(","))
        return total - used
    except Exception:
        return 1 << 20  # no nvidia-smi: do not block


def acquire() -> bool:
    t0 = time.time()
    while time.time() - t0 < WAIT_S:
        try:
            fd = os.open(LOCK, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
            os.write(fd, str(os.getpid()).encode())
            os.close(fd)
            return True
        except FileExistsError:
            try:
                if time.time() - os.path.getmtime(LOCK) > STALE_S:
                    os.remove(LOCK)
                    continue
            except OSError:
                pass
            time.sleep(2.0)
    return False


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 3
    scenario = sys.argv[1]
    extra = sys.argv[2:]
    repo = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
    if not acquire():
        print("no GPU lock after %d s" % WAIT_S)
        return 3
    try:
        t0 = time.time()
        while free_mb() < MIN_FREE_MB:
            if time.time() - t0 > WAIT_S:
                print("GPU memory never freed up")
                return 3
            time.sleep(5.0)
        log = os.path.join(os.environ.get("TEMP", "."), "street_empire_capture_%s.log" % scenario)
        cmd = [GODOT, "--path", os.path.join(repo, "game"), "--audio-driver", "Dummy", "--resolution", "1920x1080",
               "--position", "20000,0", "res://devtools/capture_boot.tscn", "--", "--capture=" + scenario] + extra
        with open(log, "w", encoding="utf-8", errors="replace") as f:
            rc = subprocess.run(cmd, stdout=f, stderr=subprocess.STDOUT, timeout=600).returncode
        print("capture %s exit %d (%.0f s) log %s" % (scenario, rc, time.time() - t0, log))
        return rc
    finally:
        try:
            os.remove(LOCK)
        except OSError:
            pass


if __name__ == "__main__":
    sys.exit(main())
