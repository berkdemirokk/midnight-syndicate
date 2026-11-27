# Online LAN race (experimental)

Status: experimental, OFF by default. Local network / loopback only. This is NOT internet multiplayer.
No paid servers, no hosting, no port forwarding, no encryption, no authentication, no NAT traversal.
Do not expose the PC to the internet with this build.

## How to switch it on
- `game/net/net_config.gd`: `ENABLED = false` (default). Set it to true only for a deliberate test build.
- Or start the game with `--experimental-online` (after the user arguments: `-- --experimental-online`).
- With either, the main menu shows "Online (LAN, experimental)". Without them the button does not exist.
- The server binds 127.0.0.1. A LAN address is accepted only when the game is started with `--address=<LAN IP>`;
  `0.0.0.0` and any other address are refused by the server itself (`NetSession.start_server`), not only by the UI.

## Smoke test
`py -3 tools/net_smoke.py` starts 1 server and 2 client Godot processes on 127.0.0.1 (headless, no GPU lock needed),
waits for them, and checks the logs: join, ready, start, GO, server results with a finished car, per-client
snapshots and exit codes. Exit code 0 only when every check passes. Output: `evidence/net_smoke/<run>/`
(server and client logs, `summary.json`). Options: `--godot`, `--port`, `--laps`, `--run`, `--timeout`.

## Files
| file | role |
|---|---|
| game/net/net_config.gd | flags, constants (protocol 1, port 24580, bind 127.0.0.1, 8 players, 20 Hz, 100 ms interpolation, 120 m/s limit, rate and projection caps) |
| game/net/net_protocol.gd | message names, hello check, `validate_state` (finite values, speed, steer, sequence, teleport; a flagged reset waives only the teleport limit) |
| game/net/net_lobby.gd | lobby players, ready flags, start rule (2 ready), grid order = join order |
| game/net/net_race_authority.gd | server race truth: progress from validated positions (Track.get_progress), laps, finish order, DNF |
| game/net/net_session.gd | ENetConnection transport (create_host_bound), lobby and relay, rate cap, ping/pong |
| game/net/net_race_glue.gd | client: grid slot, shared countdown, 20 Hz state send, remote car interpolation, results screen |
| game/net/net_lobby_menu.gd | lobby overlay: host, join, ready, back |
| tools/net_smoke.py | launcher: 1 server + 2 clients, log checks, `evidence/net_smoke/<run>/summary.json` |
| game/devtools/net_smoke.gd | the Godot side of the smoke test (server or client role) |
| game/tests/test_net_protocol.gd, test_net_race.gd | in-process unit tests (14 tests) |

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
- State is unreliable (FLAG_UNSEQUENCED); hello, ready, lobby, start and results are reliable.

## Server rules
- Hello: a different protocol version is rejected with the reason. Names 1 to 24 characters. Lobby full or a race
  running: rejected.
- Start: when 2 or more players are ready the server sends start with a 3 s countdown and builds the race on the
  development circuit (DevTrack, the same geometry on every machine). The race clock starts at GO on the server.
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
Final run: `evidence/net_smoke/run7_realtime/` (`summary.json`, logs). Command: `py -3 tools/net_smoke.py --run run7_realtime`.
All 16 checks passed. The three processes run headless at real time (no `--fixed-fps`), so the server clock is wall time.
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

Unit tests: `game/tests/test_net_protocol.gd`, `test_net_race.gd`: 14 tests, 0 failed.

## Not done, risky
- Not internet multiplayer. No NAT traversal, no encryption, no authentication, no anti-cheat beyond the checks above.
- Clients load the race scene after the start message, so a slow-loading client reaches GO later than the server
  clock does; its finish time includes the load delay. Not a problem in the smoke test (no scene load), untested in game.
- The race scene path (net_race_glue inside race_scene.gd, the lobby overlay, the results screen) was not run in a
  real scene and not captured with the capture harness. The smoke test drives the same protocol with real cars in
  separate processes but skips race_scene.gd. No screenshots exist for the online path.
- Remote cars have no LOD, shadow proxy or audio setup from race_scene; they are a visual approximation.
- A reset may move a car anywhere; the visual result is shown to every peer. It gives no distance, but it is not
  checked against the track, so a cheating client can show a car in a wrong place.
- The "Next" button on the online results screen stays hidden: event "online_lan" is not in the event ladder.
- The online race uses the development circuit (track_scene empty), not a final track.
- ENet over WAN has not been tested. LAN or localhost only.
- Projection failures are counted per car but a cap of 200 is a guess, not measured on real play.
