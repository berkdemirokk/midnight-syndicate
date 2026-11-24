# In-game evidence: City 01 vertical slice

Dev PC only (RTX 5060 Ti, Mobile renderer, 1920x1080 window, 1920x1061 image). No phone has been measured.
Shots come from the capture harness (`--capture=race_city`, `--capture=city_presets`). Perf JSON sits beside each PNG.
Numbers: `GRAPHICS_BENCHMARK.md`, section "City 01 in engine". All numbers here are dev PC numbers.

## Race shots (`evidence/screens/race_city/`)
Race: real track City 01, real Noctra Sable, 5 rivals, autopilot player, 2 laps (the spec race, no `--laps` flag).
Run: `--capture=race_city --preset=high --timeout=400`. Log: `evidence/logs/race_city_r2_high.log`.
Result: `[CAPTURE] scenario=race_city shots=7 errors=0 exit=0`, race ended at 159.9 s. No SCRIPT ERROR, Parse Error or SHADER ERROR. Dev track, dev mule and DevWatermark: none present.
Race reflection is on (planar reflection on the road, High preset).

No staging in this run. The scenario no longer sets the car's velocity, no longer sets nitro charge, and no longer forces the autopilot's nitro gate (`force_nitro_above_kmh` is off). The earlier staged `racing_nitro` shot and the one-lap `results_1lap` shot came from that staging and are removed from this folder. Speed and nitro below are whatever the game produced.

Shots, in race order (all on the High run above):
- `grid.png`: fixed camera behind and beside the 6-car grid. 0 km/h, 6th of 6, lap 1 of 2. Earned.
- `countdown_2.png`: the "2" overlay, same fixed camera, 0 km/h. Earned.
- `racing_10s.png`: chase camera at 10.25 s after GO, 116 km/h, 6th. Wet road with reflections, neon signs, rivals ahead. Earned. (The Low and Medium frames below are at 9.98 s, so this is not the identical moment.)
- `pack.png`: chase camera with 5 rivals in view, 5th, 93 km/h. Rain streaks and reflections on the road. Earned.
- `drift.png`: NOT a visible drift. Handbrake, throttle and steer input held for 1.0 s on a corner entry at s 713 m (curvature 0.023), with the autopilot paused. Position and velocity are not touched. The HUD reads "DRIFT 0" and "BANKED +0", max slip 0.4 deg. The shot shows the input only, not a slide. Not retaken in this pass.
- `underpass.png`: inside the tunnel at s 1560 m on lap 1, 137 km/h, 3rd, lap time 48.39 s. Ceiling strips and the car read; the car body is dark. Earned.
- `racing_nitro.png`: NOT TAKEN. The shot needs lap 2, speed at or above 200 km/h and `nitro_active`. The car reached 207.0 km/h on lap 2, but `nitro_active` was never true at or above 200 km/h before the results screen. The log line is "NO nitro shot". Nothing was forced. The nitro bar is full in the frames, but that is charge, not active nitro.
- `results.png`: results after 2 laps, "RACE COMPLETE", 3rd of 6 (Nova Rike, the player) at 02:19.61, best lap 01:09.06, CASH 300, REP 30 (non-zero rewards). Earned.

Max speed reached in the full race: 207.0 km/h (lap 2). The track allows 252 km/h at s 220 m; the car did not reach it.

## Preset comparison at the same race time (`racing_10s_low.png`, `racing_10s_medium.png`)
Two extra runs with `--stop-after-10s --preset=low` and `--preset=medium`. Each takes one shot 10 s after GO. Both frames show 00:09.98 on the timer, 116 km/h, 6th. Earned, same race state in both.
- `racing_10s_low.png`: Low, 3D scale 0.67 (the earlier note said 1.00; this run reads 0.67). Rain streaks are faint, road reflections weaker than Medium. Probe: 1.68 ms frame avg, 594 fps, 276 draw calls.
- `racing_10s_medium.png`: Medium, 3D scale 0.85. Rain and road reflection visible. Probe: 1.83 ms frame avg, 547 fps, 278 draw calls.
- High at 10.25 s (`racing_10s.png`) for comparison: 2.61 ms frame avg, 383 fps, 274 draw calls. Probe numbers come from the perf probe in each run's JSON.

These fps values are CPU frame-loop times on the dev PC. They are not phone numbers and not GPU timings.

## Preset shots (`evidence/screens/city_presets/`)
Same three viewpoints on Low, Medium and High, plus the 6-car pack. Each *_low, *_medium, *_high PNG has a 300-frame measure JSON.
Logs: `evidence/logs/city_presets_qa_{low,medium,high}.log`.

- `neon_strip_{low,medium,high}.png`: grid street at s 144 m, checkered start line; rain streaks appear on Medium and High only.
- `downtown_overpass_{low,medium,high}.png`: faces a building block, not the overpass guardrails (s 688 to 1040 m). Viewpoint is misframed; not retaken in this pass.
- `underpass_{low,medium,high}.png`: tunnel interior at s 1620 m; rain streaks on Medium and High only.
- `pack_{low,medium,high}.png`: six cars behind a camera 30 m back; taken 1 s after GO at about 24 km/h, so the pack numbers are start-of-race, not race pace. Medium and High show the rain and the reflection; Low does not.

## Not shown
- Nitro active above 200 km/h: not produced by the autopilot in the 2-lap High run (lap 2 top 207.0 km/h, no nitro_active above 200). No racing_nitro frame exists.
- Nitro flames and speed lines: not shown in any frame.
- A real drift: not shown. The drift frame is handbrake input at 93 km/h on a mild corner, slip 0.4 deg.
- Low and Medium 2-lap runs: only the 10 s frame exists for each. No Low or Medium results screen.
- Police pursuit: not built.
- Phone or any device other than the dev PC: not measured.
- Wet road reflections at 60 m: checked visually only, no measurement.
- Frame-time numbers are CPU frame-loop times from the probe, not GPU timings.
- Planar reflection in the city views (`city_presets`): not attached (the views are city-only). It is attached in the race path on Medium and High.
- Earlier "Low at 0.67 scale not in effect" note: superseded by the 0.67 reading above.
