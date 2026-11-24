# In-game evidence: City 01 vertical slice

Dev PC only (RTX 5060 Ti, Mobile renderer, 1920x1080). No phone has been measured.
Shots come from the capture harness (`--capture=race_city`, `--capture=city_presets`). Perf JSON sits beside each PNG.

## Race shots (`evidence/screens/race_city/`)
Race: real track City 01, real Noctra Sable, 5 rivals, autopilot player. Preset high. Fails on dev track, dev mule or DevWatermark: none present.
Final shots come from the one-lap run (`--laps=1`). The two-lap spec run times out at 120 s before the finish; see "Not shown".

- `grid.png`: fixed camera behind and beside the 6-car grid at s 144 m; all six cars and the neon street read.
- `countdown_2.png`: the "2" frame, same fixed camera, 0 km/h.
- `racing_10s.png`: chase camera 10 s after GO at 109 km/h; wheel smoke covers the lower half of the frame.
- `pack.png`: chase camera with three rivals ahead at 109 km/h; the smoke again hides the road in front.
- `drift.png`: 1.5 s handbrake drift at s 1005 m, HUD "DRIFT 14", 135 km/h; slip angle 44 deg; the car is dark against the lit wall.
- `underpass.png`: inside the tunnel at s 1560 m, 153 km/h; ceiling strips and dash lights read; the car body is almost black.
- `results_1lap.png`: results screen after the one-lap race, 6th of 6 at 01:34.78; CASH and REP show 0.

## Preset shots (`evidence/screens/city_presets/`)
Same three viewpoints on Low, Medium and High, plus the 6-car pack. Each *_low, *_medium, *_high PNG has a 300-frame measure JSON.

- `neon_strip_{low,medium,high}.png`: grid street at s 144 m; rain streaks appear on Medium and High only.
- `downtown_overpass_{low,medium,high}.png`: faces a building block, not the overpass guardrails (s 688 to 1040 m). Viewpoint is misframed.
- `underpass_{low,medium,high}.png`: tunnel interior at s 1620 m; rain streaks on Medium and High only.
- `pack_{low,medium,high}.png`: six cars behind a camera 30 m back; taken 1 s after GO at 38 km/h, so the pack numbers are start-of-race, not race pace.

## Not shown
- `racing_nitro`: not captured. The autopilot never reached 200 km/h (top 180.9 km/h) and stalled at s 496 to 585 m after wall or traffic hits (impulses 1 700 to 7 000).
- Two-lap results and the two-lap finish: not captured within the 120 s harness limit.
- Low at 0.67 scale: not in effect in this build (3D scale reads 1.00 on every preset).
- Planar reflection in the race: not wired into the game path, so no shot has it.
- Police pursuit: not built.
- Phone or any device other than the dev PC: not measured.
- Wet road reflections at 60 m: checked visually only, no measurement.
- Frame-time numbers are CPU frame-loop times from the probe, not GPU timings.
