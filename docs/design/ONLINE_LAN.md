# Online LAN race (experimental)

Status: experimental, OFF by default. Local network / loopback only. This is NOT internet multiplayer.
No paid servers, no hosting, no port forwarding guidance. Do not expose the PC to the internet with this build.

## How to switch it on
- `game/net/net_config.gd`: `ENABLED = false` (default). Set it to true only for a deliberate test build.
- Or start the game with `--experimental-online` (after the user arguments: `-- --experimental-online`).
- With either, the main menu shows "Online (LAN, experimental)". Without them the button does not exist.

## Files
| file | role |
|---|---|
| game/net/net_config.gd | flags, constants (protocol version 1, port 24580, bind 127.0.0.1, 8 players, 20 Hz, 100 ms interpolation delay, 120 m/s limit) |
| game/net/net_protocol.gd | message names, hello check, `validate_state` (finite values, speed, steer, sequence, teleport) |
| game/net/net_lobby.gd | lobby players, ready flags, start rule (2 ready), grid order = join order |
| game/net/net_race_authority.gd | server-side race truth: progress from validated positions (Track.get_progress), laps, finish order, DNF |
| game/net/net_session.gd | ENetConnection transport (create_host_bound, so the server binds 127.0.0.1), lobby and relay, ping/pong |
| game/net/net_race_glue.gd | client: grid slot, shared countdown, 20 Hz state send, remote car interpolation, results screen |
| game/net/net_lobby_menu.gd | lobby overlay: host, join, ready, back |
| game/devtools/net_smoke.gd | multi-process smoke test (1 server, 2 clients with the AI driving real cars) |
| game/tests/test_net_protocol.gd, test_net_race.gd | in-process unit tests |

Small hooks in existing code: `race/race_config.gd` (net_hold_grid), `race/race_scene.gd` (no AI opponents and no
own countdown when net_hold_grid, `start_net_countdown()`, glue attach, local results skipped), `ui/menus/main_menu.gd`
(button shown only when online is enabled, and a one-time reason toast after a lost connection).

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
- Reset: a state flagged reset (client saw a move over 12 m between two sent states) is accepted once when the new
  spot is at most 40 m from the old one. Progress then follows the new spot.
- Progress: the server projects each accepted position onto the track. A projection that would move the car more
  than 25 m + 2 * 120 m/s * dt in one tick is ignored and counted (progress_jumps).
- Laps and order: laps come from the unwrapped distance along the line. Finish order is by server time. A car
  still running 15 s (FINISH_WAIT_S) after the first finish is DNF with reason time limit.
- Disconnect: the car is DNF with reason disconnected; the others continue. The client sees peer_left.
- After results the server clears the ready flags and returns to the lobby. Clients send bye and go back to the menu.
- A lost server shows "lost the connection to the server" on the main menu.

## Client rules
- Remote cars are visual only (CarFactory cars, frozen, no AI). They are drawn from snapshots 100 ms in the past
  (linear position, slerp rotation), using the client receive time.
- The local race uses the normal RaceManager for the countdown and the car. Its own results are skipped; the server
  results are shown.

## Measured (this PC, headless, Godot 4.7.2, not a real network)
Numbers are filled in from the smoke run below. Headless runs are not paced in real time, so race times here are
server clock values from a headless run, not lap times a player would see.

Smoke run 4 (server + 2 clients, 127.0.0.1, 1 lap, DevTrack, headless, uncapped frame pacing, this PC):
- Join, ready, start: both clients joined, lobby updated, countdown 3.0 s sent to both, grid slots 0 and 1.
- Server accepted 3567 car states, relayed 3567 snapshots. Rejected 13695: mostly "not racing" after a driver finished,
  because clients keep sending until results arrive (known, see Not done).
- Results sent by the server: Ada 1st (server time 609.12 s, 0 progress jumps), Bo 2nd (609.88 s, 31 progress jumps ignored).
- Ada lost her connection right after GO on this run (ENet timeout under load); the server kept her result and sent results to Bo.
- Client send rate: 20.0 Hz (1 state per 50 ms of the client clock). Bo sent 55351 states in total (keeps sending after finishing).
- Snapshots received by Bo: 939 (not every relayed state arrived in this loaded run).
- RTT (ping/pong, localhost): min 0.12 ms, average about 1100 ms on this loaded PC. The average is dominated by the uncapped
  headless client loop, not the network, so it is not a usable latency number.
- Server clock vs real time: headless frames are not paced to real time, so the 609 s race time is a clock value, not a lap time.
Unit tests (game/tests/test_net_protocol.gd, test_net_race.gd): 9 tests, 0 failed.


## Not done, risky
- Not internet multiplayer. No NAT traversal, no encryption, no authentication, no anti-cheat beyond the checks above.
- The race scene glue and the lobby overlay were not run in a real race scene or captured with the capture harness.
  The smoke test drives the same protocol with real cars in separate processes but skips race_scene.gd.
- Remote cars have no LOD, shadow proxy or audio setup from race_scene; they are a visual approximation.
- Rate limiting of incoming states is not implemented; one client can flood the relay within the 64 KB rule.
- The online race uses the development circuit (track_scene empty), not a final track.
- ENet over WAN has not been tested. LAN only.
