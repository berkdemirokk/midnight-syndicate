# Racing AI, race manager and track

Code: `game/ai/ai_driver.gd` (AIDriver), `game/race/race_manager.gd` (RaceManager), `game/world/track.gd` (Track).
Test circuit: `game/tests/helpers/test_track.gd`. Tests: `game/tests/test_ai_race.gd` (9 tests, all pass at 60 Hz).

## Track
- RacingLine is a closed Catmull-Rom Curve3D (last point repeats the first). Sampled every 4 m at `_ready`.
- Target speed profile: `v = min(max_speed, sqrt(a_lat * r))`, then a backward pass for braking (11 m/s^2)
  and a forward pass for acceleration (9 m/s^2), both around the loop twice.
- Progress: nearest sample plus projection on its two neighbouring segments. An optional hint narrows the search to 120 m.
  No allocation per call.
- Lateral offset: positive = right of the race direction (+X when driving -Z). Curvature: signed, positive = right turn.

## AI driver
- Runs before its ArcadeCar (physics priority -1), so the car reads this tick's input.
- Pure pursuit: look-ahead 8 m + 0.45 s x speed (8 to 45 m), aimed at the racing line shifted by the lane offset.
- Speed: target = min(profile at car, profile 0.6 s ahead) x skill x rubber band, capped at the car top speed.
  Throttle or brake is proportional to the error. Nitro only on straights (radius over 250 m) when the target is
  more than 10 m/s (36 km/h) above the speed.
- Noise: two smooth sines, phase from `noise_seed`. RaceManager sets it to the grid slot, so drivers differ.
  Braking points +-4 % of target speed, steering +-0.03.
- Overtaking: a slower car within 20 m ahead in our lane triggers a 2.5 m lane shift to the side with the most room.
  A side is refused when a car is alongside on it (7 m along, 3.2 m across). The shift returns at 1.5 m/s.
- Stuck: under 5 km/h for 2.5 s while racing starts a 1.5 s reverse. If still under 5 km/h, the car is reset onto the line facing forward.
- Rubber band: RaceManager pushes the player's unwrapped race distance minus ours each tick. Gap beyond 150 m moves
  target speed by up to +-8 % (ahead of the player: down, behind: up). Never above the top speed. Neutral without a gap.
- Finished or idle cars brake at 0.5 while above 20 km/h, then coast to a stop.

## Race manager
- Grid: cars on Grid0..7 (two columns, 9 m rows), frozen. Countdown emits 3, 2, 1, 0 (GO), unfreezes, emits race_started.
- Laps: four virtual gates at 25, 50, 75 and 100 % of the line. Only a forward step into the next quarter counts, and only
  when the previous gates were passed in order. Crossing the line on the grid or reversing across it adds no lap.
- Positions: finished cars by finish order, then unfinished cars by unwrapped race distance. position_changed fires only on change.
- End: when the player finishes, the rest get 15 s. When all cars finish, the race ends at once. Unfinished cars get
  `race_time x total_distance / distance_so_far`. race_finished fires once with results sorted by total_time.
- Wrong way: the player's velocity along the line below -3 m/s for 0.5 s emits wrong_way_changed(true); forward clears it.
- setup() resets the race state, so a second race on the same node works.

## Measured (headless, --fixed-fps 60, test circuit 1265 m, 316 samples)
| Metric | Value |
|---|---|
| Length vs summed sample chords | within 1 % (test range) |
| Progress error vs walked offset | 0.000012 m |
| Target speed hairpin / straight | 16.0 / 58.2 m/s |
| Lateral offset at +-3 m | +3.0000 / -3.0000 m |
| Solo AI, skill 1.0: lap 1 / lap 2 | 51.6 s / 49.1 s |
| Solo AI max abs lateral (limit 7 m) | 5.72 m |
| Solo AI stuck events | 0 |
| 4 AI race totals by position (skills 1.0/0.95/0.9/0.85) | 102.5 / 103.2 / 131.0 / 136.4 s |
| 4 AI race best laps by position | 49.9 / 50.2 / 58.2 / 53.5 s |
| Min car up.y over race (no flips) | 0.9995 |
| Countdown: movement before GO | 0.0 m |
| Reverse across start: laps added | 0 (reverse and forward crossing), 1 for the forward lap |
| Rubber band at +75 / +225 / +700 / -225 / -700 m | 1.00 / 1.04 / 1.08 / 0.96 / 0.92 |
| Overtake: max lateral reached, 30 m behind a parked car | 4.87 m (shift 2.5 m plus overshoot) |
| Stuck: events while held 3 s / forward after release 8 s | 1 / 178 m |
| Wrong-way signal | true after 0.5 s backwards, false after forward |

## Limits and open items
- Lateral accel limit tuned to 9.5 m/s^2 after 13 m/s^2 gave 11 m excursions at the car grip limit under throttle.
- Solo lateral margin (5.7 of 7 m) is modest. Re-check after any grip or steering change in ArcadeCar.
- Overtake overshoot (4.9 m) is measured, not tuned. The car body may touch the parked car in that test (not checked).
- Track length is 1.27 km, a little above the 1.2 km target.
- Estimated times for unfinished cars are a pace extrapolation, not simulated.
- Nitro use by the AI is not measured yet.
