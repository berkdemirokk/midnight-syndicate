# Online LAN race (experimental)

Status: experimental, OFF by default. Local network / loopback only. This is NOT internet multiplayer.
No paid servers, no hosting, no port forwarding, no encryption, no authentication, no NAT traversal.
Do not expose the PC to the internet with this build.

## How to switch it on
- `game/net/net_config.gd`: `ENABLED = false` (default). Set it to true only for a deliberate test build.
- Or start the game with `--experimental-online` (after the user arguments: `-- --experimental-online`).
- Join code: the host gets a 6-character code (random, from 23 letters and 8 digits, no 0, O, 1, I, L) shown in the
  lobby overlay. Joining needs the same code in the Code field. `--code=ABCDEF` on the host or the joiner sets it
  (tests only; the code is then the same for every run that uses it). The code is checked on the server only and is
  never sent to other clients or written to the logs. It travels unencrypted in the hello, so anyone who can
  read LAN traffic can read it: the code keeps out guessers on a trusted LAN, not eavesdroppers.
- With either, the main menu shows "Online (LAN, experimental)" (Turkish: "Online (LAN, deneysel)"). Without them the
  button does not exist. All menu and lobby text goes through I18n (keys `net.*` in `ui/i18n.gd`).
- The server binds 127.0.0.1. A LAN address is accepted only when the game is started with `--address=<LAN IP>`;
  `0.0.0.0` and any other address are refused by the server itself (`NetSession.start_server`), not only by the UI.

## Smoke test
`py -3 tools/net_smoke.py` starts 1 server and 2 client Godot processes on 127.0.0.1 (headless, no GPU lock needed),
waits for them, and checks the logs: a client with a wrong code is refused first (`wrong_code_refused`), then join, ready,
start, GO, server results with a finished car, per-client snapshots and exit codes. The join code is random per run. Exit code 0 only when every check passes. Output: `evidence/net_smoke/<run>/`
(server and client logs, `summary.json`). Options: `--godot`, `--port`, `--laps`, `--run`, `--timeout`.

## Files
| file | role |
|---|---|
| game/net/net_config.gd | flags, constants (protocol 1, port 24580, bind 127.0.0.1, 8 players, 20 Hz, 100 ms interpolation, 120 m/s limit, rate and projection caps) |
| game/net/net_protocol.gd | message names, hello check, `validate_state` (finite values, speed, steer, sequence, teleport; a flagged reset waives only the teleport limit) |
| game/net/net_lobby.gd | lobby players, ready flags, start rule (2 ready), grid order = join order |
| game/net/net_race_authority.gd | server race truth: progress from validated positions (Track.get_progress), laps, finish order, DNF |
| game/net/net_session.gd | ENetConnection transport (create_host_bound), lobby and relay, rate cap, ping/pong |
| game/net/net_race_glue.gd | client: grid slot, shared countdown, 20 Hz state send, remote car interpolation, live standings, results screen |
| game/net/net_track.gd | the allow-listed track scene for the server and every client (`NetConfig.TRACK_ALLOW`); null falls back to DevTrack |
| game/net/net_lobby_menu.gd | lobby overlay: host (shows the join code), join (code field), ready, back |
| game/net/net_hello_limiter.gd | hello attempts per remote address: 5 per 10 s (wrong codes count) |
| tools/net_smoke.py | launcher: 1 server + 2 clients, log checks, `evidence/net_smoke/<run>/summary.json` |
| game/devtools/net_smoke.gd | the Godot side of the smoke test (server or client role) |
| game/tests/test_net_protocol.gd, test_net_race.gd, test_net_polish.gd | in-process unit tests (track allow-list, order rows, order validation) |
| game/tests/test_net_join.gd | join code format, right and wrong code, hello rate limit |

Small hooks in existing code: `race/race_config.gd` (net_hold_grid), `race/race_scene.gd` (no AI opponents and no
own countdown when net_hold_grid, `start_net_countdown()`, glue attach, local results skipped, retry does nothing
online), `ui/menus/main_menu.gd` (button shown only when online is enabled, and a one-time reason toast after a lost
connection).

## Protocol (version 1)
Messages are Dictionaries with key "t", sent with var_to_bytes and read with bytes_to_var (objects not allowed).
Packets above 64 KB are dropped.
- client to server: hello {v, name}, ready {on}, state {seq, xf, vel, steer, reset?}, ping {ts}, bye
- server to client: welcome {pid, v}, reject {reason}, lobby {players}, start {countdown, laps, grid, names},
  snap {pid, seq, xf, vel, steer}, peer_left {pid}, results {rows}, pong {ts}
- server to client also: order {rows} (unreliable, 4 Hz)
- State is unreliable (FLAG_UNSEQUENCED); hello, ready, lobby, start and results are reliable.

## Server rules
- Hello: every hello counts toward the rate limit of its address (5 per 10 s, right or wrong code). Then a different
  protocol version is rejected with the reason, names of 1 to 24 characters are required, and the hello must carry the
  host's join code (`code`, compared after trim and upper-case). Wrong code: rejected with reason "wrong join code"
  and key `code`; too many attempts: key `rate`. The client shows its own TR/EN text for both keys. Lobby full or a
  race running: rejected.
- Track: the race runs on the Bosphorus track (`res://world/istanbul_bogaz/istanbul_bogaz.tscn`). The server loads that scene
  for its racing line and grid, and names it in the start message (`track`). A client loads only an allow-listed name from
  that message; a client that cannot race the named track (off the allow-list or missing,
  `NetConfig.track_usable`) leaves the race with `net.track_missing` instead of racing another road. If the scene does not load on the server, the server logs a warning and uses the development circuit (
  `track` is then "", the same on every machine). The log line `[net] track: ...` shows which one ran.
- Start: when 2 or more players are ready the server sends start with a 3 s countdown. The race clock starts at GO on the server.
- Live order: while racing, the server sends `order` rows (pid, place, lap, metres) 4 times a second, unreliable. Clients
  check every row (`NetProtocol.clean_order`: integer pid, place 1..8, lap 0..laps, finite metres) and show the standings in the
  HUD (every online racer by name, the local player's place). Order rows are never trusted for progress or results.
- State checks: finite numbers, speed at most 120 m/s, steer within 1.01, strictly increasing sequence, and the
  position may move at most speed * dt * 1.5 + 2 m since the last accepted state. Refused states are counted
  and the last good state is kept.
- Rate cap: at most 40 accepted states per car per second on the server's simulation clock (2 x SNAP_HZ). The excess
  is dropped and counted as rate_limited. States from a car that has finished or DNF are dropped silently.
- Reset (R key, respawn): a state flagged reset may move the car anywhere. Only the teleport limit is waived; the
  sequence, finite and speed checks still apply. A reset never adds distance: progress follows the new spot, but
  distance changes only by a backward move (negative credit) and never by a forward one. Repeated resets
  therefore cannot shorten a lap. Test: 33 forward resets of 39 m add no distance (test_repeated_resets_add_no_distance).
  Cost to an honest player: a backward reset loses the metres it moves back.
- Progress: the server projects each accepted position onto the track. A projection that would move the car more
  than 25 m + 2 * 120 m/s * dt in one tick is ignored and counted (progress_jumps). A car with 200 such jumps
  (MAX_PROGRESS_JUMPS) is DNF with reason "track projection failed", so it is never placed on a guessed position.
- Distance credit: forward distance is credited at most at MAX_SPEED_MS (120 m/s) on the server clock, with up to
  0.5 s banked for late or bunched states. The per-state teleport limit alone would let a client that claims 120 m/s
  and sends at the 40 Hz rate cap move about 11 m per state (over 400 m/s); the credit cap stops that from shortening
  a lap. Test: test_claimed_speed_cannot_outrun_the_server_clock (80 such states in 2 s: 800 m moved, 240 m credited).
- Laps and order: laps come from the unwrapped distance along the line. Finish order is by server time. A car
  still running 15 s (FINISH_WAIT_S) after the first finish is DNF with reason time limit.
- Disconnect: the car is DNF with reason disconnected; the others continue. The client sees peer_left.
- Results: the server sends the rows (position, finished, dnf, time, distance, progress_jumps) and returns to the
  lobby with the ready flags cleared. Clients send bye and go back to the menu.
- Retry on an online results screen goes to the main menu (no new online race is started from it).
- A lost server shows "lost the connection to the server" on the main menu.

## Client rules
- Remote cars are visual only (CarFactory cars, frozen, no AI). They are drawn from snapshots 100 ms in the past
  (linear position, slerp rotation), using the client receive time.
- A client sends a reset flag when its car moved more than 12 m since the last sent state.
- The client stops sending when its race leaves RACING (the race scene path, when the car finishes). The smoke
  client does not know its finish; it sends until the results arrive, and the server drops those states silently.

## Measured (this PC, headless, Godot 4.7.2, 127.0.0.1, not a real network)
Join code run (lobby branch): `py -3.10 tools/net_smoke.py --run wp_lobby_1`, `evidence/net_smoke/wp_lobby_1/`. All 20
checks passed, including the wrong-code refusal. Ada 1st (47.35 s, 2205 m), Bo 2nd (48.06 s). In-game check with the
code: `py -3.10 tools/net_ingame_check.py --port 24631` under the GPU lock, exit 0, 4 shots, the server results match.
Latest run on the Bosphorus track: `evidence/net_smoke/wp_netpolish_2/` (`summary.json`, logs). Command:
`py -3.10 tools/net_smoke.py --run wp_netpolish_2`. All 20 checks passed. Ada 1st (47.31 s, 2205 m), Bo 2nd (48.06 s,
2207 m), both finished, 0 rejected, 0 rate limited, 189 order messages seen by each client (4 Hz).
In-game (rendered client on the race scene, `py -3.10 tools/net_ingame_check.py` under the GPU lock): exit 0, 4 shots
in `evidence/screens/net_client/` (grid, racing, remote, results). The HUD lists both names with the live order and the
results screen lists both finished (run times 47.30 s and 51.05 s). No DEV TRACK watermark.

Earlier smoke run on the development circuit: `evidence/net_smoke/run7_realtime/` (`summary.json`, logs).
Command: `py -3 tools/net_smoke.py --run run7_realtime`. All 16 checks passed. The three processes run headless at real time (no `--fixed-fps`), so the server clock is wall time.
- Join, ready, start: both clients joined, ready flags seen by both, start with 2 racers, grid slots 0 and 1.
- Client send rate: 20.0 Hz (939 states each over the race).
- Server accepted 939 (Ada) and 938 (Bo) states, rate limited 0, rejected 0, progress_jumps 0 for both.
- Snapshots received: Ada 938, Bo 939 (20.0 Hz each). Each client received every state the server accepted from the other.
- Results from the server, computed from validated positions and the server clock: Bo 1st (47.05 s, 1300.3 m),
  Ada 2nd (47.08 s, 1301.3 m). Both finished. A 1300 m lap at 47 s matches the AI pace on the development circuit.
- RTT on localhost (ping/pong): about 16.9 ms avg, 16.7 ms min for both clients. Both ends poll ENet once per frame
  (60 fps), so this is frame polling delay on loopback, not network latency.
- The whole smoke run takes about 53 s.

Earlier runs (not used as evidence):
- run6 (with `--fixed-fps 60`): passed all checks, but the headless processes ran uncapped, and the idle server
  stepped many more 1/60 s frames per wall second than the clients, so its clock read about 640 s for a 49 s lap.
  That is why the launcher now runs at real time.
- run5 (before the rate cap moved to the simulation clock): the wall-clock cap dropped 2790 states, both cars reached
  the projection-jump cap and were DNF, and nobody finished. The launcher now requires a finished car.
- run4 (the first version): Ada lost her connection right after GO. Not reproduced in run5, run6 or run7.
  The cause is unknown; the earlier log is not kept as evidence.

Unit tests: `game/tests/test_net_protocol.gd`, `test_net_race.gd`, `test_net_polish.gd`: 17 tests, 0 failed.
Full suite at the time: 383 tests, 0 failed (current count: see the results section) (`evidence/test_results.json`).

## Not done, risky
- Not internet multiplayer. No NAT traversal, no encryption, no authentication, no anti-cheat beyond the checks above.
- Clients load the race scene after the start message, so a slow-loading client reaches GO later than the server
  clock does; its finish time includes the load delay. Not a problem in the smoke test (no scene load), untested in game.
- The smoke test drives the same protocol with real cars in separate processes but skips race_scene.gd. The rendered
  in-game check (net_ingame_check.py) covers race_scene.gd, the HUD standings and the results screen for one client.
  The lobby overlay itself is not captured.
- The server's own reject and error texts (for example "lobby is full", "refused: ...") are protocol strings and are
  shown in English. Only the menu, lobby labels and the lost-connection and race-start messages go through I18n.
- The remote car in the in-game check reports speed 0 km/h: the glue does not set remote velocities (visual only).
- Remote cars have no LOD, shadow proxy or audio setup from race_scene; they are a visual approximation.
- A reset may move a car anywhere; the visual result is shown to every peer. It gives no distance, but it is not
  checked against the track, so a cheating client can show a car in a wrong place.
- The "Next" button on the online results screen stays hidden: event "online_lan" is not in the event ladder.
- The online race uses the Bosphorus track when it loads; the development circuit is only the fallback.
- ENet over WAN has not been tested. LAN or localhost only.
- Projection failures are counted per car but a cap of 200 is a guess, not measured on real play.

## Impairment and reconnect results (wp/net, dev PC, not a real network)

Status: sweep done on the dev PC (Windows 11, RTX 5060 Ti PC, Godot 4.7.2 headless, loopback plus one bind to the
PC's Wi-Fi LAN address). Not a phone, not a second device, not internet. Two racers, not three (see limits).

### What was built and changed in this pass
- `tools/net_impair_proxy.py`: UDP relay. Per direction: one-way delay = RTT/2 with uniform jitter, loss and
  duplication, seeded. Fixed in this pass: on Windows a client that exits makes the shared socket raise
  ConnectionResetError on the next recv, which killed the relay's client-to-server thread. The other clients then
  went silent and timed out. Now the reset is ignored and the reset report is switched off on the relay sockets
  (`SIO_UDP_CONNRESET`). The first leave_gone and kill_rejoin runs (`evidence/net_impair/wp2_*`) show the bug.
- `tools/net_impair_run.py`: kill_rejoin no longer requires the killed process to report results (the check now
  asks only for Ada and for the resumed Bo).
- Rejoin (`game/net/net_session.gd`):
  - A live racer's seat is taken over by the same name only from the same remote address as the old connection.
    Another address cannot kick a racer. Held seats after a drop are still claimed by name plus join code (trust
    assumption; no reconnect token yet).
  - No resume during the countdown (the other cars are not moving yet).
  - A seat still held when the race ends is marked DNF "disconnected" before the results are computed.
  - The rendered client (`game/net/net_lobby_menu.gd`) refuses a resume start and leaves the race. Reason: it does
    not restore the car from the resume state yet (`game/net/net_race_glue.gd`), so the car would be stuck or refused.
    The headless smoke client (`game/net/net_lan_smoke.gd`) resumes and is the only client that rejoins.
    So rejoin into the game is NOT available. Owner decision needed before it is enabled.
- Tests (full suite 474 tests, 0 failed): reconnect grace and expiry, held-seat listing for the race end, same-address
  rule for live takeover (`game/tests/test_net_reconnect.gd`); duplicate, reordered and timeout-gap states
  (`test_net_reconnect.gd`, renamed `test_long_gap_allowance_is_not_a_teleport`); hello deadline
  (`game/tests/test_net_reject.gd::test_hello_deadline`, existing). The server-side DNF after grace and the hello
  overdue disconnect in `_tick_server` have no dedicated unit test; they are covered by the leave_gone run below.

### Measured runs (2 racers, 1 lap, Ada and Bo, through the relay unless marked)
Finish times are the server clock from GO. "Lost" is the relay's count of dropped datagrams, to the server / to the
clients. "Accepted" is the server's count of accepted car states for that racer. Server rejects: 0 in every wp* run; the two lead re-runs had some (see their rows).
Client RTT is the average of both clients (ping/pong).

| run | impairment | result | Ada / Bo finish (s) | lost (to server / to clients) | accepted Ada / Bo | client RTT avg (ms) |
|---|---|---|---|---|---|---|
| wp5_rtt0 | relay only, 0 ms | PASS, order agrees | 47.56 / 47.93 | 0 / 0 | 921 / 929 | 17.0 / 17.0 |
| wp5_rtt80 | 80 ms RTT | PASS, order agrees | 47.45 / 47.85 | 0 / 0 | 921 / 929 | 102.9 / 103.0 |
| wp5_rtt150 | 150 ms RTT | PASS, order agrees | 47.66 / 48.06 | 0 / 0 | 921 / 929 | 167.7 / 169.5 |
| wp5_rtt250 | 250 ms RTT | PASS, order agrees | 47.62 / 47.98 | 0 / 0 | 916 / 917 | 274.5 / 275.4 |
| wp5_loss2 | 80 ms, 2 % loss | PASS, order agrees | 47.50 / 47.88 | 44 of 2330 / 66 of 2653 | 904 / 908 | 101.4 / 104.0 |
| wp5_loss5 | 80 ms, 5 % loss | PASS, order agrees | 47.64 / 48.06 | 132 of 2296 / 116 of 2596 | 865 / 876 | 100.9 / 99.4 |
| wp5_loss10 | 80 ms, 10 % loss | PASS, order agrees | 47.61 / 48.31 | 243 of 2319 / 265 of 2523 | 834 / 826 | 104.2 / 104.3 |
| wp5_combo | 150 ms, 10 ms jitter, 5 % loss, 0.5 % duplication | PASS, order agrees (Bo 1st, Ada 2nd) | 48.40 / 47.68 | 114 of 2282 / 152 of 2595 (duplicates 12 / 9) | 877 / 880 | 174.4 / 172.5 |
| wp5_lan_rtt80 | 80 ms; server and clients on LAN address 192.168.111.15 | PASS, order agrees | 47.63 / 48.01 | 0 / 0 | 921 / 928 | 106.5 / 102.4 |
| wp4_kill_rejoin | 80 ms; Bo killed 12 s after GO, relaunched with same name and code | PASS | 47.68 / 51.60 (Bo resumed) | 0 / 0 | 921 / 957 | not summarised |
| wp3_leave_gone | 80 ms; Bo sends BYE 12 s after GO, never returns | PASS: Ada finishes 48.82 s, Bo DNF after the 20 s grace | 48.82 / DNF | 0 / 0 | Bo 240, Ada 929 (Bo was pid 1 in this run) | not summarised |
| wp_plain_v3 (earlier) | relay only | PASS | 47.53 / 47.93 | 0 / 0 | 921 / 929 | not summarised |
| lead_kill_rejoin (lead re-run) | 150 ms, 5 % loss; Bo killed 12 s after GO, relaunched | PASS, order agrees; 10 teleport rejects for Bo right after the resume | 47.53 / 57.41 (Bo resumed) | 142 of 2689 / 145 of 2864 | see summary.json | Bo resumed 166.9 |
| lead_leave_gone (lead re-run) | 250 ms, 20 ms jitter, 10 % loss, seed 7; Bo sends BYE 12 s after GO | PASS: Ada 47.71 s, Bo DNF after the 20 s grace; 1 "sequence not increasing" reject (jitter reorders packets) | 47.71 / DNF | 154 of 1572 / see summary.json | see summary.json | Ada 277.6 |

Pre-fix failures kept as evidence: `evidence/net_impair/wp2_kill_rejoin` and `wp2_leave_gone` (the relay died when a
client exited; the other client then timed out). `r_rtt80_fg` is the earlier 80 ms foreground run.

Reading the numbers:
- The clients sent about 930 states each over the race (20 Hz). Under 10 % loss the server accepted about 830 of
  them. Lost states are not accepted, and no state was rejected as a teleport or a sequence error: loss costs
  states, not validity.
- Snapshots received fall with loss (about 735 to 750 of 930 at 10 %). The interpolation delay
  (`NetConfig.INTERP_DELAY_S` = 0.1 s) covers one lost snapshot at 20 Hz. Visible stutter at 5 % or 10 % loss was not
  judged by eye (no rendered run with an impaired link).
- The relay adds about 2 to 12 ms to the configured RTT (ping/pong), so treat the RTT labels as +/- 15 ms.
- The finish-time gap between the two racers was 0.3 to 0.9 s in every run. It says nothing about position error.
- Both kill_rejoin runs went through the live same-address takeover (ENet had not yet noticed the killed process),
  not the held-seat path. The held-seat claim after ENet times out is covered by unit tests only.
- lead_kill_rejoin (150 ms, 5 % loss): right after the resume the server refused Bo's next 10 states (about 0.6 s)
  as teleports of 5.8 to 6.8 m from the first state the resumed client sent; then it accepted them again and Bo
  finished. Cause not found. Bo finished 9.9 s after Ada (kill, Godot boot and reconnect over the impaired link).
  Must be understood before rejoin is enabled in the rendered game.
- kill_rejoin: Bo finished 3.9 s after Ada. The car does not drive while its client is down, so most of that gap is
  probably the time the seat was empty. Not measured separately.

### Not measured or not done (honest limits)
- Position error and rubber-banding are NOT measured. The server has no ground truth for a client's own car. The
  rejects by reason (teleport, sequence, projection) are the only proxy: 0 in every wp* run.
- Three racers were not run. The start rule begins the countdown when 2 players are ready, so a third client that
  readies a moment later is refused "a race is running". A lobby window before the countdown would fix it.
  OWNER DECISION: the window length, and whether the game rule changes.
- Second physical device: not available. The LAN run was from this PC to its own Wi-Fi address. No port was opened to
  the outside; the PC is not reachable from the internet. No firewall prompt was seen in these runs.
- Rendered in-game rejoin: not run live, and it is refused (see above). Enabling it needs a live kill-and-rejoin run
  with the real client.
- The live leave_gone and kill_rejoin runs use the headless smoke client, not the rendered race scene.
- The late-drop case (grace still running when the race ends) is marked DNF "disconnected" in code. No live run hit it.
- Not run: duplication-only, RTT above 250 ms, loss above 10 %, jitter-only.
- Not internet multiplayer. No NAT traversal, no encryption, no authentication, no hosting.
