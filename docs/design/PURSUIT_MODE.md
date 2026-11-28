# Police pursuit mode

Status: opt-in. `PursuitMode.ENABLED` is `false` in every build, and `RaceConfig.pursuit` is `false` by default. A race gets the mode when `RaceConfig.pursuit` is true and either `PursuitMode.ENABLED` is true or the race is a career event that opts in (`RaceConfig.pursuit_event`). Only the Bosphorus escape event opts in, so the mode is playable from the career menu while the global kill switch stays off. Normal races add no police node and no police car, and their results do not change.

## Pieces

| File | Role |
|---|---|
| `game/race/pursuit/pursuit_mode.gd` | `PursuitMode` node: kill switch, spawn, despawn, roadblock, heat HUD, escape reward |
| `game/race/pursuit/police_driver.gd` | `PoliceDriver` (extends `AIDriver`): lane is the player's lateral offset, speed gets a heat catch-up |
| `game/race/pursuit/roadblock.gd` | `Roadblock`: barrier layout that leaves one lane open, placement check |
| `game/race/pursuit/pursuit_hud.gd` | `PursuitHud`: heat label and BUSTED / ESCAPED banner |
| `game/race/pursuit/pursuit_mode.gd` rules | `PursuitState` (`game/ai/pursuit_state.gd`) is used unchanged: heat 1-5, chase, cooldown, escaped, busted |
| `game/race/race_config.gd` | `pursuit: bool = false`, `pursuit_event: bool = false` (set by an event that opts in) |
| `game/race/race_scene.gd` | After `race.setup`, adds one `PursuitMode` child when `config_used.pursuit and (PursuitMode.ENABLED or config_used.pursuit_event)`. On BUSTED it stops the race and shows a result with no time, no reward and no record |
| `game/race/events.gd` | Career event `bogaz_escape` ("Boğaz kaçışı" / "Bosphorus escape"): istanbul_bogaz, night, 2 laps, `open` and `pursuit` |
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

## Career event: Bosphorus escape

- Event `bogaz_escape` is open from the start, so it never locks and never gates the ladder. The Next button after the last ladder event skips open events, so it does not offer this one.
- It races on istanbul_bogaz at night, 2 laps, against 3 street-class rivals (skills 0.90, 0.88, 0.86), with police pursuit on.
- Escaped: the ESCAPED banner shows and the cash reward is paid. The race goes on to its finish, which pays the normal reward.
- Busted: the BUSTED banner shows, the race stops for the player, and 3 s later the results screen shows no standings, no cash and no record; no stars are awarded (the star row shows three dim stars). The event can be retried.
- Strings are in `game/ui/i18n.gd` (tr and en): `event.bogaz_escape.name`, `pursuit.heat`, `pursuit.busted`, `pursuit.escaped`, `pursuit.busted.result`.
- Test: `game/tests/test_escape_event.gd` (reachable and localized, other events police-free, the event flag passes the gate with the kill switch off, and a forced bust on the real event scene with no standings, stars, cash or record and a later finish ignored, and an autopilot run to a finish or a bust with the result checked).

## Not done or known limits

- Police drivers can still follow slower rivals (AIDriver sensing). They do not steer around the player.
- Spawns are 75 to 88 m behind. On long straights a police car can still be in view if all candidate spots are visible. The hit rate of out-of-view spawns is not measured.
- ESCAPED keeps the race running; BUSTED ends it for the player (see the event section). The roadblock barriers are solid in pursuit races, so they can block rival AIs and change race positions.
- No real police livery. Barriers are plain props, not tuned models.
- Not checked on a phone. Desktop numbers are not phone numbers.
- The roadblock is a barrier line, not a navigation or AI avoidance problem. The AI is not tuned to avoid it.
- `ENABLED` is a static var rather than a const, so tests and capture can flip it for one run. Normal builds leave it false.
- On BUSTED only the RaceManager stops (race clock and lap counting) and the autopilot is switched off; the car body is not frozen, so it coasts (or a human player can still steer) behind the banner and the results screen, as after a normal finish. Not covered by a test.
