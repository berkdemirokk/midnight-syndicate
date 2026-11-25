# Camera

Owner: Gameplay Agent (camera and replay). Code: `game/camera/chase_camera.gd`, `game/camera/replay_director.gd`,
`game/replay/replay_recorder.gd`, `game/replay/replay_player.gd`. Tests: `game/tests/test_driver_camera.gd`,
`game/tests/test_replay.gd`. Capture: `game/devtools/scenarios/race_replay.gd`.

## Chase (CHASE, unchanged apart from the grid intro)
- Corner look-into (`look_inside_m` 1.2 m), roll (`max_roll_deg` 2.5), speed drop and shake, nitro kick back.
- Wall rays: rear wall pulls the distance in, ceiling and side probes cap height and swing.
- ORBIT (`set_mode`) is the pre-race grid view. `race_scene.gd` still starts the chase-camera orbit when the race
  finishes, so it runs behind the results screen; the replay is separate and does not use it.

## Grid intro
- `ChaseCamera.start_grid_intro(from_pos, from_look, seconds)`. `race_scene.gd` starts it when the countdown starts
  (3 s), from 30 m behind the pack centre and 14 m high, looking at the centre. It calls `snap()` first, so the
  smoothed chase state is current when the intro hands over.
- Each frame it blends from the start to the live chase pose with `smoothstep`; FOV eases from 52 deg. At the end
  it hands over to CHASE. `intro_progress()` (0..1) lets the capture shoot at a fixed point of the move.
- Test: the hand-over step is at most 0.05 m (measured 0.023 m).

## Race replay
- `ReplayRecorder`: 30 Hz samples of every car between `race_started` and `race_finished`: pose, steer, wheel spin
  and wheel compression, speed, velocity, nitro, drift, slip, brake input, wheel contact. One preallocated ring of
  300 s (9000 samples x 25 floats per car). The buffer size is constant and the ring wraps (tested).
- `ReplayPlayer`: the cars are frozen with physics off and written from the recording each physics tick. `read()`
  interpolates position, velocity and compression; spin, flags and contact hold the earlier sample. Nitro and drift
  signals fire on change. Leaving restores the cars and the HUD.
- Overlay: REPLAY tag, progress bar, PAUSE, RESTART, RESULTS (the controls the brief asks for).
- `ReplayDirector`: 20 TV spots, alternating sides, every third one high (5 m), placed from the Track API 5 m beyond
  the drivable width. The spot nearest ahead of the player within 6 to 80 m is used (spots are about 65 m apart on
  the 1.3 km lap). A spot is usable only if: the road beside it sees the spot, the spot sees the car at 0.4 m and
  1.0 m height, and no other car is within 3 m of the lens. Rival cars block views (only the player's body is
  excluded). The lens is 20 deg close and 30 deg at 25 m.
- Every 20 s a 4 s insert, alternating CHASE and BUMPER, skipped when its view is blocked. The last 6 s orbit the
  finishing car at 9 m; each orbit angle must have a clear view of the car, else the director uses a TV spot.
- Camera positions inside geometry are rejected: ray queries start with `hit_from_inside`, so a camera placed
  inside a wall is blocked.
- Ray queries reuse one parameter object per director; no allocation per tick in the ray tests.

## Results screen
- REPLAY button after RETRY (`results_screen.gd`, `replay_pressed`), shown only when a recording exists.
  Texts in I18n: `results.replay`, `replay.*` (TR and EN). `RaceScene.start_replay` handles the signal.

## Evidence (race_replay scenario, City 01, 1 lap, Noctra Sable, high preset, desktop RTX 5060 Ti)
Shots in `evidence/screens/race_replay/`, run `race_replay` after the last change, exit 0, 6 shots, 10 TV cuts.
- replay_tv_1: player centred, readable, about 14 % of frame width.
- replay_tv_2: player at 6 to 10 m, large and cropped at the left edge. A car close to the lens is gone.
- replay_tv_3: player centred on a high spot, distant and small.
- replay_bumper: bumper insert, player in frame.
- replay_finish_orbit: finishing car in frame, clear of walls.
- grid_intro_mid: taken at intro progress 0.60; the player car is a dark silhouette cropped at the bottom edge.

## Known limits
- Overpass and underpass spots are not identified; spots alternate sides and height only.
- Replayed cars have no contact shadow; tv_3 still reads as slightly raised. Not resolved.
- Near spots frame the car large and cropped; no shot is re-framed by the director.
- Grid intro frame at 60 % shows the player cropped at the bottom edge.
- Replay runs at physics rate (60 Hz); not checked on a phone.
- Performance: none measured. No perf JSON for the replay path.
