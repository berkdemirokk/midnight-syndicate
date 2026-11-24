# Graphics benchmark

Numbers from the dev PC only. Never present these as phone numbers (B1 and B2 in BLOCKERS.md: no iPhone test yet).
Machine: dev PC, NVIDIA GeForce RTX 5060 Ti, Windows 11, Godot 4.7.2 Mobile renderer, 1920x1080 window (viewport 1920x1061).
Probe: `devtools/perf_probe.gd`, 60 frames after warm-up, vsync off.

## Hero car in engine

Machine: dev PC, RTX 5060 Ti, Windows 11, Godot 4.7.2 Mobile renderer, 1920x1080 (viewport 1920x1061). Dev PC numbers only, not phone numbers.
Source: shipped GLBs, final ship of this session (sha256 0e60.. LOD0, 2a82.. LOD1, 8bf6.. LOD2). Captures: `evidence/screens/car_studio/`, perf JSON beside each PNG.

Triangles per LOD (whole car, col_body excluded): LOD0 86 397, LOD1 27 498, LOD2 6 799. Budgets 45k-90k, 28k, 7k. All pass.
Materials at LOD0: 15 names, budget 14. FAIL, extra material M_Pillar (see docs/design/CAR_INTEGRATION.md).
Draw objects at LOD0: 17 (col_body excluded), budget 20. Pass.

Draw calls and objects from the perf counter (single run each; frame times are noisy, not used for claims):
| shot | draw calls | primitives | frame ms avg |
|---|---|---|---|
| empty_studio (no car, baseline) | 4 | 24 | 0.60 |
| front34 (LOD0, one car) | 21 | 93 503 | 0.92 |
| side (LOD0) | 20 | 90 341 | 0.90 |
| wheel_closeup (LOD0) | 21 | 164 621 | 1.42 |
| lights_on (LOD0, brake lamps) | 21 | 93 513 | 0.90 |
| rear34 (LOD0) | 21 | 93 513 | 0.91 |
| lod1 (forced, one car) | 30 | 44 820 | 0.44 |
| lod2 (forced, one car) | 25 | 9 566 | 0.38 |
| paint_variants (three cars, LOD0) | 57 | 332 081 | 1.08 |

Car alone (shot minus baseline): LOD0 17 draw calls per car (matches the 17 LOD0 objects). LOD2 21.
LOD1 shows 26, more than LOD0 with the same 17 mesh objects. Not explained, not chased. Shadow passes may be in the counter.

Texture memory: not measured per car. The perf probe reports one process figure, 444 MB video memory, identical in every shot, so it is not a car figure.
Car texture sources: flake 512 px, carbon base and normal 512 px, tyre base and normal 1024 px, brake, lens and plate per LOD.

## Garage

Machine: dev PC, NVIDIA GeForce RTX 5060 Ti, Windows 11, Godot 4.7.2 Mobile renderer, preset `high`, dev PC numbers only, not phone numbers.
Source: `evidence/screens/garage/*.json` (capture scenario `garage`, 60-frame probe after warm-up, vsync off).

| shot | size | draw calls | primitives | objects | frame ms avg | p95 | video MB |
|---|---|---|---|---|---|---|---|
| overview | 1920x1080 | 190 | 103 829 | 330 | 1.54 | 5.36 | 510 |
| front | 1920x1080 | 209 | 104 661 | 349 | 1.40 | 2.26 | 510 |
| overview | 2556x1179 | 205 | 108 105 | 345 | 2.12 | 5.51 | 566 |

Frame times are single runs and noisy. Video memory is the process figure, not a garage-only figure.

### Garage, review round 2 (same machine, same preset)

Source: `evidence/screens/garage/*.json` after the lighting, tab and upgrade-row fixes.

| shot | size | draw calls | primitives | objects | frame ms avg | p95 | video MB |
|---|---|---|---|---|---|---|---|
| overview | 1920x1080 | 190 | 103 829 | 330 | 1.67 | 5.52 | 511 |
| front | 1920x1080 | 209 | 104 661 | 349 | 1.54 | 1.57 | 511 |
| rims_tab | 1920x1080 | 191 | - | - | 1.66 | 5.52 | 511 |
| overview | 2556x1179 | 205 | 108 109 | 347 | 1.99 | 5.32 | 567 |

Dev PC numbers only, not phone numbers. Frame times are single 60-frame probes. Video memory is the process figure.

## City 01 in engine

Machine: dev PC, NVIDIA GeForce RTX 5060 Ti, Windows 11, Godot 4.7.2 Mobile renderer, 1920x1080 window (viewport 1920x1061), preset `high`. Dev PC numbers only, not phone numbers.
Sources: `evidence/screens/city_districts/*.json` (district run after the material round 3: window glow tint, facade albedo, ambient, ceiling strip scale) and `evidence/screens/race_city/*.json` (race run, one lap, autopilot). Each shot carries a 60-frame probe; the `_measure` files carry a 300-frame probe. Frame times are single runs and noisy.

Scene: 1127 instances, 850 MultiMeshes, 148 occluders, 37 reflection probes, 150 lights built (28 dropped by the budget), worst per mesh 8 omni and 8 spot, probes 3 (test_city_01). Scene load about 1.2 s.

| shot | draw calls | primitives | frame ms avg | p95 | p99 | video MB (process) |
|---|---|---|---|---|---|---|
| city_districts neon_strip | 369 | 215 400 | 2.37 | 3.44 | 6.08 | 707 |
| city_districts neon_strip, 300-frame | 369 | - | 1.70 | 2.03 | 3.73 | 707 |
| city_districts downtown | 108 | - | 1.62 | 1.82 | 5.76 | 707 |
| city_districts establishing_60m | 256 | - | 2.52 | 2.73 | 6.03 | 707 |
| city_districts underpass | 281 | - | 1.44 | 5.69 | 9.92 | 707 |
| city_districts underpass, 300-frame | 281 | - | 0.95 | 1.01 | 1.23 | 707 |
| city_districts waterfront | 92 | - | 1.45 | 1.68 | 5.99 | 707 |
| city_districts old_market | 163 | - | 1.74 | 5.36 | 5.98 | 707 |
| race_city grid | 179 | - | 1.96 | 3.14 | 5.72 | 781 |
| race_city countdown_2 | 220 | - | 1.47 | 2.10 | 5.74 | 785 |
| race_city racing_5s | 380 | - | 2.21 | 2.79 | 6.55 | 786 |
| race_city racing_20s_nitro | 324 | - | 2.08 | 3.11 | 7.12 | 787 |
| race_city results | 439 | - | 2.39 | 3.00 | 6.10 | 788 |

Reading: the brief target is 350 draw calls. The race shots are over it (380 racing, 439 with the results screen up). Of the district shots only neon_strip (369) is over it; the others are 92 to 281.
The p99 spikes of 5 to 10 ms in single 60-frame probes are shader or first-frame compile noise, not confirmed. Use the 300-frame `_measure` files for any claim. No phone measurement exists for this scene.
