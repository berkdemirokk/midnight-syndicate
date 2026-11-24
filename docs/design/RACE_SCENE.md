# Race scene (race assembly)

Owner: Gameplay Agent. Code: `race/race_scene.gd` (+ `.tscn`), `race/race_config.gd`, `vehicles/car_factory.gd`, `vehicles/car_visual.gd`,
`vehicles/dev_visual.gd`, `world/dev_track/dev_track.gd`. Tests: `tests/test_race_scene.gd`. Capture: `devtools/scenarios/race_dev.gd`.

## Node tree
```
RaceScene (Node3D, race_scene.gd)
  World (Node3D)                  rebuilt by retry()
    Track                         track scene, or DevTrack.build() when the scene is missing
    DefaultEnvironment            WorldEnvironment, only when the track has none
    <car> x (opponents + 1)       CarFactory; the player is always last
      Visual (rot 180 deg Y)      model root sits under it
        model root                imported scene, or DevCar (dev mule)
      CarVisual                   wheels, brakes, body tilt, paint, rear lamps
      AIDriver                    autopilot player (opponents get one from RaceManager)
      PlayerDriver                player without autopilot
      CarFx                       only if res://fx/car_fx.tscn exists
    ChaseCamera                   ORBIT on the grid, CHASE from GO
    RaceManager
    RainFx                        only if res://fx/rain.tscn exists
  HUD (RaceHUD, race_hud.tscn)
    SpeedFx > SpeedLines          only if res://fx/speed_lines.tscn exists
    TouchControls                 non-autopilot only
  Overlay (CanvasLayer, layer 20)
    PauseMenu, ResultsScreen
  DevWatermarkLayer (layer 21)    dev circuit only; above the overlay so no screen hides it
    DevWatermark                  "DEV TRACK"
```

## Config (`RaceConfig` resource)
Source order: the `config` export, else `Router.take_params()["config"]`, else a default `RaceConfig`.
Fields: `track_scene`, `car_scene`, `car_spec_path`, `laps` (3), `opponent_count` (5, max 7), `opponent_skills`,
`opponent_names`, `opponent_paints`, `player_name`, `player_paint`, `autopilot`, `autopilot_skill`, `event_id`.
The player takes grid slot `opponent_count`, the last one used.

## Contracts for the optional paths
- Track: root `Track` with `RacingLine` (closed Path3D, forward = race direction), `StartGrid` holding
  `Grid0..Grid7` Marker3D (-Z = race direction), and optionally a `WorldEnvironment`.
- Car model: root Node3D with `body`, `glass`, `wheel_FL`, `wheel_FR`, `wheel_RL`, `wheel_RR` (origin at the hub),
  `brake_FL`..`brake_RR`, `lights_front`, `lights_rear`. Nose faces +Z. Materials `M_Paint` and `M_LightRear`.
  Missing names are skipped with a warning.
- FX: `res://fx/car_fx.tscn` (child of each car), `res://fx/speed_lines.tscn` (into `SpeedFx`),
  `res://fx/rain.tscn`. Each is skipped when absent.

## Swapping in the real track and car
1. Track: save it as `res://world/city_01/city_01.tscn` or set `RaceConfig.track_scene`. Follow the Track contract.
2. Car: import it as `res://vehicles/noctra_sable/noctra_sable.tscn` or set `RaceConfig.car_scene`, with the names above.
   The dev mule is used only while the file is missing. Then re-run `test_race_scene` and `race_dev`.

## Behaviour
- Grid: 1.5 s beat, then `start_countdown()` (3, 2, 1, GO). Camera ORBITs on the grid, CHASEs at GO. Results pay via `GameState.record_result`.
- Reset (`reset_car` action, handled once in `RaceScene._unhandled_input`, both driver paths): back to the last progress on the line, facing forward, zero speed.
- Capture `racing_20s_nitro` waits for 150 km/h first, because the flame strength scales with speed (`car_fx.gd`).
- RETRY and pause restart rebuild in place, keeping the config (not `Router.reload()`: lead decision). MENU goes to `main_menu.tscn`.

## Known gaps (not done)
- Real track and car paths, and the non-autopilot path (PlayerDriver, touch), are not exercised: tests use the dev fallbacks and autopilot.
- Wrong-way is wired to the HUD and `RaceScene.wrong_way`, untested. The garage button is hidden until the garage exists (shortcut: reads ResultsScreen's private `_garage_btn`).
- "DEV CAR" and "DEV TRACK" are literal strings, not I18n keys (dev-only by design).
