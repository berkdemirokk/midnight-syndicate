# Police pursuit mode

Status: opt-in and disabled. `PursuitMode.ENABLED` is `false` in every build, and `RaceConfig.pursuit` is `false` by default. A race gets the mode only when both are true. Normal races add no police node and no police car, and their results do not change.

## Pieces

| File | Role |
|---|---|
| `game/race/pursuit/pursuit_mode.gd` | `PursuitMode` node: kill switch, spawn, despawn, roadblock, heat HUD, escape reward |
| `game/race/pursuit/police_driver.gd` | `PoliceDriver` (extends `AIDriver`): lane is the player's lateral offset, speed gets a heat catch-up |
| `game/race/pursuit/roadblock.gd` | `Roadblock`: barrier layout that leaves one lane open, placement check |
| `game/race/pursuit/pursuit_hud.gd` | `PursuitHud`: heat label and BUSTED / ESCAPED banner |
| `game/race/pursuit/pursuit_mode.gd` rules | `PursuitState` (`game/ai/pursuit_state.gd`) is used unchanged: heat 1-5, chase, cooldown, escaped, busted |
| `game/race/race_config.gd` | `pursuit: bool = false` |
| `game/race/race_scene.gd` | After `race.setup`, adds one `PursuitMode` child when `config_used.pursuit and PursuitMode.ENABLED` |
| `game/tests/test_pursuit_mode.gd` | 15 in-process tests |
| `game/devtools/scenarios/pursuit_demo.gd` | Capture scenario that force-enables the mode for one run |

## Rules

- Start: `PursuitMode.start()` on GO runs `PursuitState.start(1)`. Each step spawns police first, then ticks the rules, so the first police car exists before the chase is judged. There is no false escape on GO.
- Heat: the state rises by one level every 25 s of chase, up to 5.
- Police cap by heat: 1, 2, 2, 3, 3 for heat 1 to 5 (`PursuitMode.max_police_for_heat`).
- Spawn: one car every 4 s while below the cap. Spawn points are 75, 82 and 88 m behind the player, at the player's lane and at plus or minus 3 m. The first spot that is out of the camera frustum wins. If none is hidden, the farthest free spot is used. `PursuitMode.last_spawn_hidden` records which case happened. Out of view is best effort: no hit rate is measured yet, and a long straight can still show a police car. A spot needs 6 m of clear space from every car.
- Despawn: police more than 250 m behind or ahead of the player (track distance) are removed.
- Chase rules: a police car out of sensing range (90 m, or no police at all) starts the cooldown. Police spawn 75 to 88 m back, so a chase begins in range. Heat rises one level every 25 s of chase, so heat 2 takes 25 s and heat 3 (roadblock) takes 50 s. The test `test_chase_holds_and_heat_rises` covers this. Eight seconds of cooldown ends in ESCAPED. A bust happens when a police car is within 8 m and the player is at or below 10 km/h for 4 s (BUSTED). The thresholds are those in `PursuitState`.
- Catch-up: a police driver aims at the player's lateral offset along the track. Its speed skill is 0.94 + 0.01 per heat level. Its speed gets 2 % per heat level, read through `get_rubber_band()`. The top speed of the car still caps it.
- Roadblock: at heat 3 or more (`PursuitState.can_request_roadblock`), with no roadblock up and a 30 s cooldown after one is placed. The barriers sit 150, 175 or 200 m ahead, in the first spot that works. They follow the road edges from `Track.get_road_span` (on City 01 the kerb lines of the centreline file, because the racing line there is not the road centre). Layouts use 3 barriers (or 2 on narrow roads) on the left and centre, and always leave at least 3 m of open lane on the right. A spot is refused when any car is within 12 m of a barrier. The barriers are StaticBody3D props, so cars stop on them. They are removed once the player is 40 m past.
- Escape reward: 200 cash per heat level, added with `GameState.add_cash` on ESCAPED. Nothing else is paid. The rules do not tick until the first police car exists, so a chase whose spawn spots are all blocked cannot escape or pay.
- Visuals: dark-blue body (`#16305C`), no text, no logos. A light bar on the roof flashes red and blue with emissive materials and no light sources.

## Not done or known limits

- Police drivers can still follow slower rivals (AIDriver sensing). They do not steer around the player.
- Spawns are 75 to 88 m behind. On long straights a police car can still be in view if all candidate spots are visible. The hit rate of out-of-view spawns is not measured.
- The BUSTED and ESCAPED outcomes stop the police and show a banner. The results screen does not change. Pursuit races are opt-in, and in them the roadblock barriers are solid, so they can block rival AIs and change race positions.
- No real police livery. Barriers are plain props, not tuned models.
- Not checked on a phone. Desktop numbers are not phone numbers.
- The roadblock is a barrier line, not a navigation or AI avoidance problem. The AI is not tuned to avoid it.
- `ENABLED` is a static var rather than a const, so tests and capture can flip it for one run. Normal builds leave it false.
