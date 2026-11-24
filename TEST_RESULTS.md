# Test results

Source of truth: `evidence/test_results.json` (written by `game/tests/run_tests.gd`, full run
rebuilds it). Command:
`godot --headless --fixed-fps 60 --path game -s res://tests/run_tests.gd`

The runner fails a test that (a) records a failed check, (b) hits a GDScript runtime error, or
(c) leaves nodes in the tree or the tree paused. (b) and (c) were added on 2026-11-24 after a
crashed race-scene test leaked the whole city into later vehicle tests and an earlier version
counted the crashed test as passed.

## Last full run — 2026-11-24, Godot 4.7.2 stable, Jolt, dev PC (Windows 11)
110 tests, 0 failed (commit c0c065d).

| file | pass | what it covers |
|---|---|---|
| test_vehicle | 18/18 | suspension settle, 0-100 3.08 s, 0-200 8.55 s, top 285 km/h, nitro 332 km/h, braking 25 m / 94 m, cornering, drift, reverse, chaos, drop, slope, anti-roll, hit signal, grid freeze, gears, wheel visuals |
| test_ai_race | 9/9 | track maths, AI laps, 4-car race, countdown, lap counting, rubber band, overtake, stuck recovery, wrong way |
| test_driver_camera | 14/14 | input mapping, steering ramp, chase camera distance/FOV/nitro kick/shake/wall pull-in, hood and orbit modes, touch zones |
| test_race_scene | 9/9 | race flow on the dev fallbacks (forced explicitly), results, pause, reset, retry, wheel sync |
| test_city_01 | 6/6 | real track builds (1.2 s), length within 0.85 %, ground under 60 samples, side walls hold, one AI lap 63.9 s, grid |
| test_world_materials | 5/5 | every material name bound, no magenta, textures exist |
| test_car_asset | 10/10 | hero car nodes, size, wheel origins, LOD switching, paint isolation, budgets |
| test_garage | 7/7 | paint, upgrades, orbit limits, preset views, strings |
| test_fx | 8/8 | shaders compile, CarFx signals, no orphans |
| test_ui | 7/7 | HUD readout, menus, i18n completeness (TR/EN) |
| test_game_state | 8/8 | save round trip, corrupt-file recovery, economy |
| test_settings | 7/7 | presets, dynamic resolution controller |
| test_smoke | 2/2 | harness |

## Known gaps (not covered by any test yet)
- Multi-car race on the real city track (being fixed: stuck events with 6-8 cars).
- Player driving with keyboard/touch through a whole race (only autopilot is exercised).
- Anything on a real iPhone. No device test exists.
