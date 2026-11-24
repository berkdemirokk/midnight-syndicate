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

Machine line: dev PC, NVIDIA RTX 5060 Ti 8 GB, Windows 11, Godot 4.7.2 Mobile renderer (Vulkan on desktop), 1920x1080, vsync off.
These are dev PC numbers. No phone has been measured. These numbers come from a desktop GPU and say nothing reliable about iPhone frame rates or thermals.

Sources: `evidence/screens/city_presets/*_300f.json` (scenario `city_presets`, run once per preset with `--preset=low|medium|high`, 60 settle frames, then `cap.measure` over 300 frames, vsync off) and `evidence/screens/race_city/*.json` (scenario `race_city`, one-lap run `--laps=1`, default preset high, autopilot player, 5 rivals; each shot has a 60-frame probe). Logs: `evidence/logs/city_presets_*.log`, `evidence/logs/race_city_1lap_try1.log`.
The probe measures the frame loop on the CPU side with vsync off. It does not isolate GPU time, so treat the ms figures as relative numbers, not GPU cost.

### Preset table (city_presets, 300 frames each)

Columns: preset, view, frame ms avg, p95, p99, fps, draw calls, primitives, video memory (process, MB), scaling_3d_scale, planar reflection, rain.

| preset | view | ms avg | p95 | p99 | fps | draw calls | primitives | video MB | 3D scale | planar | rain |
|---|---|---|---|---|---|---|---|---|---|---|---|
| low | neon_strip (grid, s=144) | 1.36 | 1.89 | 5.28 | 737.6 | 197 | 122 803 | 659 | 1.00 | off | off |
| low | downtown_overpass (s=850) | 1.16 | 1.18 | 5.35 | 862.1 | 56 | 53 498 | 659 | 1.00 | off | off |
| low | underpass (s=1620) | 0.81 | 0.87 | 1.03 | 1230.3 | 159 | 42 496 | 659 | 1.00 | off | off |
| low | pack (6 cars, race) | 1.83 | 2.39 | 2.58 | 546.8 | 358 | 242 040 | 748 | 1.00 | off | off |
| medium | neon_strip | 1.33 | 1.70 | 5.25 | 754.2 | 199 | 124 287 | 659 | 1.00 | off | on |
| medium | downtown_overpass | 1.22 | 1.23 | 5.53 | 822.9 | 58 | 54 982 | 659 | 1.00 | off | on |
| medium | underpass | 0.87 | 0.90 | 5.43 | 1147.8 | 161 | 43 980 | 659 | 1.00 | off | on |
| medium | pack (6 cars, race) | 1.81 | 2.40 | 2.54 | 552.6 | 360 | 243 444 | 748 | 1.00 | off | on |
| high | neon_strip | 1.43 | 1.72 | 2.89 | 701.3 | 199 | 124 923 | 697 | 1.00 | off | on |
| high | downtown_overpass | 1.28 | 1.30 | 5.55 | 780.4 | 58 | 55 618 | 697 | 1.00 | off | on |
| high | underpass | 0.95 | 1.00 | 5.53 | 1057.2 | 161 | 44 616 | 697 | 1.00 | off | on |
| high | pack (6 cars, race) | 1.87 | 2.45 | 2.60 | 535.9 | 357 | 243 860 | 786 | 1.00 | off | on |

Notes on the table:
- `scaling_3d_scale` reads 1.00 on all three presets. Low asks for 0.67 in `graphics_preset.gd`, but the value only applies once `scaling_confirmed_on_device` is true, and it is false. So Low is not rendered at 0.67 in this build.
- Planar reflection is off on every row. The game race path never attaches `PlanarReflection` (only devtools do), so it is not part of the in-game build.
- Rain follows `GraphicsPreset.rain_enabled` through `fx/rain.gd`: off on Low, on for Medium and High.
- Video memory is the process figure, not a city-only figure.
- The p99 values near 5 ms in the neon, downtown and underpass rows are spikes inside a 300-frame run. The cause is not confirmed (first-frame and shader work is likely). The pack rows are steady.

### Race shots (race_city, one-lap run, preset high)

| shot | draw calls | primitives | ms avg | p95 | p99 | fps | video MB |
|---|---|---|---|---|---|---|---|
| grid | 304 | 263 751 | 2.57 | 3.43 | 6.27 | 388.9 | 781 |
| countdown_2 | 306 | 263 755 | 2.00 | 2.17 | 6.00 | 500.6 | 785 |
| racing_10s | 283 | 311 049 | 2.41 | 3.17 | 7.02 | 414.8 | 786 |
| pack | 277 | 303 400 | 2.01 | 2.78 | 6.35 | 497.2 | 786 |
| drift | 183 | 114 355 | 1.54 | 2.21 | 2.59 | 651.2 | 787 |
| underpass | 264 | 111 137 | 1.54 | 2.16 | 6.65 | 647.8 | 787 |
| results_1lap | 429 | 382 167 | 2.09 | 2.47 | 5.76 | 478.7 | 788 |
| racing_nitro | not captured | | | | | | |

Each row is one 60-frame probe taken inside the shot. Race scenes carry the HUD and the race FX, so their counts are not directly comparable with the presets table.

### Budget comparison (city brief: 350 draw calls, 450 000 primitives)

| row | draw calls (vs 350) | primitives (vs 450 000) |
|---|---|---|
| preset neon_strip, low / medium / high | 197 / 199 / 199 PASS | 122 803 / 124 287 / 124 923 PASS |
| preset downtown_overpass, low / medium / high | 56 / 58 / 58 PASS | 53 498 / 54 982 / 55 618 PASS |
| preset underpass, low / medium / high | 159 / 161 / 161 PASS | 42 496 / 43 980 / 44 616 PASS |
| preset pack (6 cars), low / medium / high | 358 / 360 / 357 FAIL | 242 040 / 243 444 / 243 860 PASS |
| race_city grid | 304 PASS | 263 751 PASS |
| race_city countdown_2 | 306 PASS | 263 755 PASS |
| race_city racing_10s | 283 PASS | 311 049 PASS |
| race_city pack | 277 PASS | 303 400 PASS |
| race_city drift | 183 PASS | 114 355 PASS |
| race_city underpass | 264 PASS | 111 137 PASS |
| race_city results_1lap | 429 FAIL | 382 167 PASS |

The pack rows fail the draw-call budget on all three presets by 7 to 10 calls. The race_city pack shot is lower (277) because its camera and frame differ. The results screen is over the draw-call budget (429) because the full results UI is drawn on top of the race.

### Known gaps in this table

- Low is not at 0.67 scale in this build (see above). The Low/High comparison therefore does not measure the Low preset's intended cost.
- No row has a GPU-timed number. The probe is CPU frame time.
- race_city `racing_nitro`: not captured. The autopilot never reached 200 km/h (top speed 180.9 km/h). The car also stalled at s 496 to 585 m with wall or traffic hits (impulses 1 700 to 7 000), so the nitro gate was not met in any run.
- race_city `results` at two laps: not captured. Two-lap runs hit the 120 s harness timeout before the finish. The one-lap run captured `results_1lap`.
