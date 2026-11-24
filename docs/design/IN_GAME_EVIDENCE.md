# In-game evidence: City 01 vertical slice

Dev PC only (RTX 5060 Ti, Mobile renderer, 1920x1080). No phone has been measured.
Shots come from the capture harness (`--capture=race_city`, `--capture=city_presets`). Perf JSON sits beside each PNG.
Numbers: `GRAPHICS_BENCHMARK.md`, section "City 01 in engine".

## Race shots (`evidence/screens/race_city/`)
Race: real track City 01, real Noctra Sable, 5 rivals, autopilot player. Preset high. Fails on dev track, dev mule or DevWatermark: none present.
Final shots come from the one-lap run (`--laps=1`, log `evidence/logs/race_city_qa_1lap_r3.log`). The two-lap spec run was not run; see "Not shown".
Race reflection is on in this run (planar reflection on the road, High preset).

- `grid.png`: fixed camera behind and beside the 6-car grid at s 144 m; the grid cars and the neon street read. 0 km/h.
- `countdown_2.png`: the "2" frame, same fixed camera, 0 km/h.
- `racing_nitro.png`: STAGED (capture only). The car is set to 230 km/h along the track tangent at s 200 m, the stretch the track allows at 252 km/h, then nitro is forced. Shot at 225.7 km/h on the chase camera. Tyre smoke at the rear wheels. Flames and speed lines are not clearly visible in the frame.
- `racing_10s.png`: chase camera 10 s after GO at 107 km/h, 5th; a red-lit traffic pack ahead on a wet road with the reflection.
- `pack.png`: chase camera with four rivals in view at 4 to 5th place; the wet road reflects the cars and the street lights.
- `drift.png`: handbrake drift into a corner, HUD "DRIFT 3" and "BANKED +1", 113 km/h; slip angle 43 deg.
- `underpass.png`: inside the tunnel at s 1560 m, 148 km/h, 1st; ceiling strips and the car read; the car body is dark.
- `results_1lap.png`: results screen after the one-lap race, "YOU WON", 1st of 6 at 01:08.21, CASH 1 000, REP 100 (non-zero). Result is from the staged run.

## Preset shots (`evidence/screens/city_presets/`)
Same three viewpoints on Low, Medium and High, plus the 6-car pack. Each *_low, *_medium, *_high PNG has a 300-frame measure JSON.
Logs: `evidence/logs/city_presets_qa_{low,medium,high}.log`.

- `neon_strip_{low,medium,high}.png`: grid street at s 144 m, checkered start line; rain streaks appear on Medium and High only.
- `downtown_overpass_{low,medium,high}.png`: faces a building block, not the overpass guardrails (s 688 to 1040 m). Viewpoint is misframed; not retaken in this pass.
- `underpass_{low,medium,high}.png`: tunnel interior at s 1620 m; rain streaks on Medium and High only.
- `pack_{low,medium,high}.png`: six cars behind a camera 30 m back; taken 1 s after GO at about 24 km/h, so the pack numbers are start-of-race, not race pace. Medium and High show the rain and the reflection; Low does not.

## Not shown
- Race at 2 laps and the two-lap finish: not run. The capture timeout is 120 s (`devtools/capture.gd` `timeout_s`). The one-lap run ended at 88 s, so a two-lap run is expected to pass 120 s. Not measured.
- Real (unstaged) 200 km/h: the autopilot never reached it in the one-lap runs (top 177.2 km/h in one run, 138.4 km/h before staging in another). The nitro shot is staged, see above.
- Nitro flames and speed lines in the nitro frame: not clearly visible. Not fixed in this pass.
- Low at 0.67 scale: not in effect in this build (3D scale reads 1.00 on every preset).
- Planar reflection in the city views: not attached (the views are city-only). It is attached in the race path on Medium and High.
- Police pursuit: not built.
- Phone or any device other than the dev PC: not measured.
- Wet road reflections at 60 m: checked visually only, no measurement.
- Frame-time numbers are CPU frame-loop times from the probe, not GPU timings.
