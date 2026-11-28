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
Full suite: 383 tests, 0 failed (`evidence/test_results.json`).

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
