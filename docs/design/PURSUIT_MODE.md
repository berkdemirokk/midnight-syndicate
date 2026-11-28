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
- Escape reward: 200 cash per heat level times the event `mult` (`PursuitMode._event_mult`, the value the select screen shows), rounded, added with `GameState.add_cash` on ESCAPED. Nothing else is paid. Race finish pay is unchanged. The rules do not tick until the first police car exists, so a chase whose spawn spots are all blocked cannot escape or pay.
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
- No real police livery. Barriers are the event kit jersey segments (`event_barrier_1/2.glb`, sponsor boards), scaled to 2 m and touching; no police-car blockers yet.
- Not checked on a phone. Desktop numbers are not phone numbers.
- The roadblock is a barrier line, not a navigation or AI avoidance problem. The AI is not tuned to avoid it.
- `ENABLED` is a static var rather than a const, so tests and capture can flip it for one run. Normal builds leave it false.
- On BUSTED only the RaceManager stops (race clock and lap counting) and the autopilot is switched off; the car body is not frozen, so it coasts (or a human player can still steer) behind the banner and the results screen, as after a normal finish. Not covered by a test.

## Update: survive goal, pursuit events, HUD gauges and radar (wp/pursuit)

- Goals. `PursuitState.start(heat, survive_for_s)`. With `survive_s == 0` the goal is escape: a full cooldown ends in ESCAPED (ESCAPED on the HUD). With `survive_s > 0` the goal is survive: that much chase time (`PursuitState.total_s`, cooldown not counted) without a bust ends in ESCAPED, shown as SURVIVED. A bust always wins. The survive time comes from the event (`"survive_s"` in `EventCatalog`), read by `PursuitMode` through the race scene's `config_used.event_id`.
- Pursuit events in `game/race/events.gd` (pursuit section, after `bogaz_escape`): five open runs on all three tracks (`pursuit_wharf_escape`, `pursuit_wharf_survive`, `pursuit_maslak_escape`, `pursuit_maslak_survive`, `pursuit_bogaz_survive`; Bosphorus escape is `bogaz_escape`) and three career runs (`pursuit_harbour_chase` 120 s survive over 3 laps, `pursuit_maslak_hunt` escape, `pursuit_bogaz_gauntlet` 180 s survive over 4 laps). The career runs sit right after `elim_maslak`, before `bogaz_escape`, so the ladder gates them in turn (1 star on `elim_maslak` opens the harbour chase, and so on); `test_career_pursuit_events_are_gated_by_the_ladder` covers it. Every survive run has laps x 60 s above its survive time, so a fast player cannot finish the race before the goal (the race finish stops the chase without pay). `EventCatalog.count()` is now 43. Test counts in `test_events.gd` and `test_modes.gd` were updated for that.
- Mult rebalance (review fix): the eight new pursuit runs were 2.0 to 5.0; they are now 1.5 to 3.25 (sum 17.5). With the old values the career cost band in `test_economy.gd` failed (1.47, band 1.5 to 2.0). With the new values it is 1.56. The Bosphorus escape `mult` stays 3.0.
- No "Pursuit" section header exists in event select: the pursuit runs are rows in the normal event list. Owner decision: a dedicated Pursuit entry belongs to the menu redesign package (the UI package owns those screens), so it is not added here.
- HUD scaling (review fix): radar, gauges and pips scale with the screen height (`screen_h / 1080`, clamped to 0.6 to 1.25) instead of fixed 1920x1080 pixels. The redraw runs only when a gauge or a radar dot changes (`set_gauges` compares before queuing).
- HUD (`game/race/pursuit/pursuit_hud.gd`): heat pips (five, filled to the heat level), a goal line (ESCAPE, or SURVIVE m:ss counting down), a bust gauge (red, fills while a police car is within 8 m and the player is stopped) and an escape gauge (cyan, fills during cooldown), and a radar on the left (police cars in the player's frame, 120 m range, rim when further). Strings: `pursuit.goal.escape`, `pursuit.goal.survive`, `pursuit.survived`, `pursuit.gauge.bust`, `pursuit.gauge.escape`.
- Tests: `game/tests/test_pursuit_heat.gd` (heat steps at 25, 50, 75, 100 s; roadblock eligible only from heat 3 in chase; start heat clamped), `game/tests/test_pursuit_survive.gd` (survive goal ends in ESCAPED at 60 s; cooldown is not chase time; bust wins over the survive goal; escape goal never ends by timer; reset; event catalog consistency and translations). `test_escape_event.gd` skips every pursuit event in its "normal events are police-free" check.
- Capture: `pursuit_demo` now also writes `pursuit_heat_5` (real heat 5 HUD, radar with police), `pursuit_escape` (real escape: police moved 150 m back, the 8 s cooldown runs, the payout goes to a temp profile) and `pursuit_bust` (the BUST banner set directly, not reached by play).

Not done in this package (owner decisions or later work):
- Spike strips at heat 4+: not built. They need a new prop, a tyre-deflation effect and handling tuning on real cars; no existing system does this.
- Evade bonus and heat cash multipliers beyond 200 cash per heat level on escape: not built.
- Hiding spots and side streets with faster cooldown: not built. The tracks have no side-street data for this.
- Siren audio: no siren sound exists in the repo, and no download is allowed. The light bar is the only cue.
- Boxing or ramming at higher heat: police still only chase and use the bust rule; no ramming force is applied.
- Escape payout now uses the event `mult` (fixed in review). Pursuit race finish pay is the normal career table.
- Real bust captured in play: not captured. The bust shot uses the banner set directly (`pm.state.phase = BUSTED`). Heat 5 is also forced (`pm.state.heat = 5`): those two shots show the HUD, not the rules reaching that state. Only the escape shot comes from the rules (police drivers switched off and moved 150 m back, the 8 s cooldown runs, ESCAPED at heat 5, reward 1000 = 200 x 5 x mult 1.0 on the demo's default config).
- Phone size: the HUD scales with the screen, but no phone-size capture exists yet. Desktop 1920x1061 only.
- Siren cue: not built (see above). The HUD and light bar are the only pursuit cues.
- The before/after sheet compares base 0e37938 (no pursuit HUD) with this package. The change is in the HUD only (radar, pips, gauges). The world render is unchanged, so the sheet does not show a visual gain beyond the HUD.

## Evidence (review fix)

- `evidence/screens/pursuit_demo/`: pursuit_police_behind (heat 1), pursuit_roadblock and pursuit_roadblock_close (heat 3 roadblock, barriers 28 to 29 m ahead in frame), pursuit_heat_5 (forced), pursuit_escape (real rules), pursuit_bust (forced banner). PNG with JSON sidecars, 1920x1061, RTX 5060 Ti dev PC.
- `evidence/screens/before_after_pursuit/`: BEFORE (base 0e37938, the three pre-package shots) | AFTER, JPG at half size. Only the three shots that exist on both sides.
- Full suite on this commit: see `evidence/test_results.json` (478 tests, 0 failed after the lead review).
- Not run: GPU queue was shared with other sessions. Each capture was run once per attempt; the first run failed on a parse error in the scenario (fixed in c2ec624).

## Lead review (2026-11-28)

- Career gating fixed: the three career runs moved in front of `bogaz_escape` (they were after the open runs, so the first one unlocked at once).
- Survive length fixed: `pursuit_harbour_chase` was 120 s over 2 laps and `pursuit_bogaz_gauntlet` 240 s over 3 laps; at 3-star lap pace (68 to 75 s) the race finished before the goal, and the race finish stops the chase without pay. Now 3 laps / 120 s and 4 laps / 180 s, with a test (laps x 60 s > survive_s).
- HUD: the bust and escape gauges had no captions and vanished on a dark sky. They now carry the `pursuit.gauge.*` captions and a coloured outline.
- HUD: heat pips moved below the gauge captions (they overlapped), and radar dots are drawn over the player arrow (a police car alongside was hidden under it).
- Evidence re-made on this code: `pursuit_demo` re-captured (6 shots, errors 0, escape phase ESCAPED at heat 5, reward 1000), before/after sheets rebuilt from base 0e37938 PNGs and the new PNGs, full suite 478 tests, 0 failed (`evidence/test_results.json`). The gain is in the HUD only; the world render is unchanged. Heat 5 and bust shots stay state-forced.

## Update: pursuit2 (menu entry, boxing and ram, hiding spots, HUD hint)

- Menu entry: the main menu has a "POLİS TAKİBİ" / "POLICE PURSUIT" button between GARAGE and RECORDS (88 px touch target, built in code like the other menu buttons, `main_menu.tscn` unchanged). It opens `res://race/pursuit/pursuit_select.tscn` (`PursuitSelect`), which lists the open pursuit runs (`PursuitSelect.run_ids()`: rows with `pursuit` and `open`). That is six rows: the five pursuit runs of the wave 1 update plus `bogaz_escape`, which is also open and pursuit. The event select screen is not used: it has no mode filter and it is not in this package's ownership. Start goes through Router with the event's RaceConfig; Back returns to the main menu.
- Boxing (heat 4 and 5): the first two police cars (`PursuitMode.boxer_side`) take the box points beside the player's lane, 2.5 m left and right, and hold 12 m ahead of the player (`PoliceDriver.box_side`, `box_ahead_m`). `PoliceDriver.box_throttle` pushes a car that is behind its point and holds back one that is past it. The third police car chases as before.
- Ram (heat 5): a police car directly behind the player (within 6 m, the player ahead of it) adds an impulse to the player's body of mass x 3 m/s. It is not a teleport. A 6 s cooldown follows (`PursuitMode.can_ram`, `RAM_COOLDOWN_S`). No damage model exists; the ram is only the push.
- Hiding spots: `HidingSpots` lists 3 or 4 track stretches per track, as fractions of the lap (city 01, Bosphorus, Maslak). In a spot, with no police car in the camera frustum, the escape cooldown runs at 2x (`PursuitState.tick(..., cooldown_mult)`). The stretches are rule zones with no side-road geometry: the tracks have no side-street data yet. A spot with a police car in view runs at 1x.
- HUD hint: while the player is in a spot, the bottom centre of the HUD shows "SAKLANMA NOKTASI: KAÇIŞ x2" / "HIDING SPOT: ESCAPE x2" (no police in view) or "HIDING SPOT: POLICE IN SIGHT".
- Evade bonus: `PursuitMode.evade_bonus()` returns the cash paid on ESCAPED and the string `pursuit.evade` exists. NOT wired to the results screen: that needs one line in `race_scene.gd` (the `rewards` dict) and a line in `results_screen.gd`, both outside this package's ownership.
- Tests: `game/tests/test_pursuit_tactics.gd` (box counts and sides, box gap and throttle, ram conditions, hiding multiplier and ranges, the escape tick count at x2, HUD hint), `game/tests/test_pursuit_menu.gd` (menu button opens the select, the select lists and starts the open runs, normal events have no pursuit).
- Capture: `pursuit_demo` now also writes `pursuit_menu_button`, `pursuit_select`, `pursuit_box_heat_5` (heat 5, four seconds after the forced heat step, box side and gap printed as `PURSUIT_DEMO box`) and `pursuit_hiding_spot` (the first shot where the player is inside a spot, found by driving, not forced).

Still not done (this package):
- Evade bonus on the results screen (see above).
- The box and ram are not tuned on real cars. A box can fail when the player is much faster than the boxers.
- Hiding spots are rule zones, not side streets, and "police in view" uses the camera frustum only.
- Phone-size captures not made.
