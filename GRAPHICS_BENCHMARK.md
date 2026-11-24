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

Pass: QA + optimization run, after the race reflection, car fill light, tyre smoke, city intrusion/skyline/draw-call and AI fixes.
Before = the numbers recorded in the previous pass of this section. After = this pass (same machine, same scenarios).

Sources: `evidence/screens/city_presets/*_300f.json` (scenario `city_presets`, run once per preset with `--preset=low|medium|high`, 60 settle frames, then `cap.measure` over 300 frames, vsync off) and `evidence/screens/race_city/*.json` (scenario `race_city`, one-lap run `--laps=1`, preset high, autopilot player, 5 rivals; each shot has a 60-frame probe). Logs: `evidence/logs/city_presets_qa_{low,medium,high}.log`, `evidence/logs/race_city_qa_1lap_r3.log` (the run that produced the shots kept here; r1 and r2 are earlier attempts).
The probe measures the frame loop on the CPU side with vsync off. It does not isolate GPU time, so treat the ms figures as relative numbers, not GPU cost.

### Optimization pass: race-pace pack, budgets, Low scale (current)

Machine: dev PC, RTX 5060 Ti, desktop, Mobile renderer (Vulkan), Windows 11, Godot 4.7.2, 1920x1080 window, vsync off. Dev PC numbers only.
Sources: `evidence/screens/city_presets/*_300f.json` (scenario `city_presets`, one run per preset, 300-frame probe per view), pack draw-call spread in `evidence/logs/city_presets_opt_{low,medium,high}.log`, race check `evidence/logs/race_city_opt_high_1lap.log`.

Changes in this pass:
- Planar mirror: off on Medium, on High only (`race/race_scene.gd` `_apply_reflection`). On High the mirror camera far plane is capped at 150 m (`PlanarReflection.max_distance_m`) and the mirror renders every second frame (`every_second_frame`).
- Mirror camera has physics interpolation off. The "Interpolated Camera3D triggered from outside physics process" warning came from `PlanarReflection/@SubViewport/@Camera3D`. The one-lap High race log has 0 of these warnings (the older race log had 2).
- Low renders at 0.67 on desktop. `GraphicsPreset.effective_scale()` returned 1.0 unless `scaling_confirmed_on_device` was set, so every preset read 1.00. Now desktop builds use the preset scale (Low 0.67, Medium 0.85, High 1.00). Phone builds still use 1.0 until a device measurement, and dynamic resolution stays gated on that measurement. Medium moved from 1.00 to 0.85 on desktop as a side effect of the same rule.
- `city_presets` pack view waits until two cars are above 120 km/h before settling and measuring (race pace; before, it was measured about 24 km/h after GO). Its log also prints the per-frame draw-call spread over 120 frames, because the probe reads one frame and the High mirror is on every second frame.

Pack view = 6 cars (player plus 5 rivals) at race pace, 300 frames. Budget verdicts use the worst sampled frame; the median is shown too.

| preset | budget (draw calls) | worst frame | median frame | verdict |
|---|---|---|---|---|
| low | 250 | 253 | 240 | FAIL (over by 3) |
| medium | 350 | 255 | 242 | PASS |
| high | 500 | 458 | 415 | PASS |

Before and after, pack view (draw calls):

| preset | before (previous pass, start of race, one probe frame) | after (race pace, one probe frame) | after, 120 sampled frames: min / median / max |
|---|---|---|---|
| low | 326 | 252 | 233 / 240 / 253 |
| medium | 629 | 254 | 234 / 242 / 255 |
| high | 633 | 247 | 238 / 415 / 458 |

The before column is not comparable with the after column. It was taken about one second after GO at about 24 km/h, from one frame. A race-pace before run was not measured. The High row alternates: frames that render the mirror sit near 415 to 458 draw calls, and the others near 238. So the mirror adds about 175 to 220 draw calls on each frame it renders.

Preset table (city views 300 frames each, pack at race pace; `draw calls` is the single probe frame; ms figures are CPU frame time, not GPU time):

| view | preset | ms avg | p95 | p99 | fps | draw calls | primitives | video MB | 3D scale |
|---|---|---|---|---|---|---|---|---|---|
| neon_strip | low | 1.46 | 2.72 | 5.42 | 684.7 | 193 | 127 966 | 634 | 0.67 |
| neon_strip | medium | 1.21 | 1.76 | 5.26 | 826.8 | 195 | 129 450 | 647 | 0.85 |
| neon_strip | high | 1.76 | 3.79 | 5.60 | 567.4 | 195 | 130 086 | 697 | 1.00 |
| downtown_overpass | low | 1.48 | 2.53 | 5.37 | 676.2 | 55 | 63 668 | 634 | 0.67 |
| downtown_overpass | medium | 1.81 | 3.17 | 5.55 | 552.4 | 57 | 65 152 | 647 | 0.85 |
| downtown_overpass | high | 1.27 | 1.46 | 1.68 | 787.7 | 57 | 65 788 | 697 | 1.00 |
| underpass | low | 1.00 | 2.00 | 4.47 | 998.4 | 157 | 42 724 | 634 | 0.67 |
| underpass | medium | 0.99 | 2.11 | 5.07 | 1013.5 | 159 | 44 208 | 647 | 0.85 |
| underpass | high | 0.90 | 0.96 | 2.74 | 1116.1 | 159 | 44 844 | 697 | 1.00 |
| pack (6 cars, race pace) | low | 2.12 | 3.06 | 3.54 | 470.8 | 252 | 210 656 | 723 | 0.67 |
| pack (6 cars, race pace) | medium | 2.29 | 3.96 | 5.42 | 436.0 | 254 | 212 140 | 736 | 0.85 |
| pack (6 cars, race pace) | high | 3.22 | 5.33 | 5.95 | 311.0 | 247 | 209 770 | 796 | 1.00 |

Race check (`race_city`, High, one lap, `--laps=1`): exit 0, no Interpolated Camera3D warning. Screenshot `evidence/screens/race_city/pack.png` shows the mirror on the wet road.

Not done in this pass:
- The mirror cull mask is not narrowed to cars, neon, signs, lamp heads, building LOD1/LOD2 and impostors. Only the road and the rain are excluded, so street furniture and small props are still mirrored. This needs layer assignment in `world/city_01/city_builder.gd` (prop MultiMeshes in `_build_props`, around line 497; building LOD meshes around line 249). Then set `PlanarReflection.excluded_layers` from `race_scene.gd`.
- High mirror resolution is still 0.33. The 0.40 target needs `race/race_config.gd` line 19 (`reflection_fraction_high`) changed to 0.40. That file is not owned in this pass.
- The every-second-frame mirror has not been checked for shimmer with motion. The stills show no obvious artifact, but that is not a stability test.
- Budget status: Low is over its 250 budget on the worst frame (253). Medium and High pass their budgets on the worst sampled frame.

No phone has been measured. These numbers come from a desktop GPU and say nothing reliable about iPhone frame rates or thermals.

### Preset table (city_presets, 300 frames each)

Draw calls are shown before and after. Budget: 350 draw calls, 450 000 primitives (city brief).

| preset | view | ms avg | p95 | p99 | fps | draw calls before -> after | primitives | video MB | 3D scale | planar | rain |
|---|---|---|---|---|---|---|---|---|---|---|---|
| low | neon_strip (grid, s=144) | 2.41 | 3.50 | 3.97 | 415.7 | 197 -> 193 | 127 966 | 659 | 1.00 | n/a (city view) | off |
| low | downtown_overpass (s=850) | 2.12 | 3.07 | 3.61 | 471.5 | 56 -> 55 | 63 668 | 659 | 1.00 | n/a | off |
| low | underpass (s=1620) | 0.85 | 0.86 | 5.44 | 1178.2 | 159 -> 157 | 42 724 | 659 | 1.00 | n/a | off |
| low | pack (6 cars, race) | 3.05 | 5.11 | 6.86 | 328.2 | 358 -> 326 | 260 316 | 748 | 1.00 | off (race path, Low) | off |
| medium | neon_strip | 1.40 | 2.01 | 5.24 | 713.2 | 199 -> 195 | 129 450 | 659 | 1.00 | n/a | on |
| medium | downtown_overpass | 1.23 | 1.32 | 5.28 | 815.9 | 58 -> 57 | 65 152 | 659 | 1.00 | n/a | on |
| medium | underpass | 0.79 | 0.85 | 1.02 | 1268.3 | 161 -> 159 | 44 208 | 659 | 1.00 | n/a | on |
| medium | pack (6 cars, race) | 3.51 | 6.42 | 8.41 | 284.8 | 360 -> 629 | 438 888 | 754 | 1.00 | on (race path) | on |
| high | neon_strip | 2.35 | 3.31 | 4.72 | 426.1 | 199 -> 195 | 130 086 | 697 | 1.00 | n/a | on |
| high | downtown_overpass | 1.86 | 3.08 | 4.64 | 538.3 | 58 -> 57 | 65 788 | 697 | 1.00 | n/a | on |
| high | underpass | 1.55 | 2.60 | 2.72 | 646.2 | 161 -> 159 | 44 844 | 697 | 1.00 | n/a | on |
| high | pack (6 cars, race) | 2.55 | 3.42 | 4.81 | 392.5 | 357 -> 633 | 455 525 | 796 | 1.00 | on (race path) | on |

Notes on the table:
- The pack row on Medium and High rose from about 358 to about 630 draw calls, and objects from about 600 to about 910. The race scene now attaches `PlanarReflection` on Medium and High (`race/race_scene.gd` `_apply_reflection`, off on Low). A mirror pass would redraw the cars, which fits the jump, but the cause is not isolated by a run with the reflection switched off. Low stays at 326 because it has no reflection.
- Before this pass the table said planar was off on every row. That was true for the city views only. `city_presets.gd` now prints and documents this (the print was a fixed string "planar=off" before).
- `scaling_3d_scale` reads 1.00 on all three presets. Low asks for 0.67 in `graphics_preset.gd`, but the value only applies once `scaling_confirmed_on_device` is true, and it is false. So Low is not rendered at 0.67 in this build.
- Rain follows `GraphicsPreset.rain_enabled` through `fx/rain.gd`: off on Low, on for Medium and High.
- Video memory is the process figure, not a city-only figure.
- The p99 values near 5 ms in the neon, downtown and underpass rows are spikes inside a 300-frame run. The cause is not confirmed (first-frame and shader work is likely). The pack rows are steady.
- The pack view is taken 1 s after GO at about 24 km/h, so the pack numbers are start-of-race, not race pace.

### Race shots (race_city, one-lap run, preset high)

Race shots show the HUD and race FX, so their counts are not directly comparable with the presets table.

| shot | draw calls before -> after | primitives | ms avg | p95 | p99 | fps | video MB |
|---|---|---|---|---|---|---|---|
| grid | 304 -> 530 | 479 373 | 2.92 | 4.19 | 5.59 | 342.9 | 791 |
| countdown_2 | 306 -> 532 | 479 377 | 2.45 | 3.22 | 6.45 | 408.6 | 795 |
| racing_10s (107 km/h, 5th) | 283 -> 481 | 506 243 | 2.76 | 3.58 | 3.71 | 362.7 | 796 |
| pack (4 rivals in view) | 277 -> 464 | 491 413 | 2.40 | 3.22 | 5.97 | 416.4 | 796 |
| drift | 183 -> 320 | 382 278 | 1.91 | 3.08 | 3.65 | 523.9 | 796 |
| racing_nitro (staged, 225.7 km/h, see notes) | not captured -> 541 | 481 173 | 2.44 | 3.04 | 5.04 | 409.2 | 796 |
| underpass | 264 -> 332 | 149 284 | 1.65 | 2.38 | 6.94 | 605.4 | 796 |
| results_1lap | 429 -> 411 | 320 052 | 2.61 | 3.21 | 6.05 | 383.7 | 798 |

Race draw calls rose on every shot except results. The likely cause is the same planar reflection on the road plus the new car fill light and tyre smoke. Not isolated.

### Budget comparison (city brief: 350 draw calls, 450 000 primitives)

| row | draw calls (vs 350) | primitives (vs 450 000) |
|---|---|---|
| preset neon_strip, low / medium / high | 193 / 195 / 195 PASS | 127 966 / 129 450 / 130 086 PASS |
| preset downtown_overpass, low / medium / high | 55 / 57 / 57 PASS | 63 668 / 65 152 / 65 788 PASS |
| preset underpass, low / medium / high | 157 / 159 / 159 PASS | 42 724 / 44 208 / 44 844 PASS |
| preset pack (6 cars), low / medium / high | 326 PASS / 629 FAIL / 633 FAIL | 260 316 PASS / 438 888 PASS / 455 525 FAIL (over by 5 525) |
| race_city grid | 530 FAIL | 479 373 PASS |
| race_city countdown_2 | 532 FAIL | 479 377 PASS |
| race_city racing_10s | 481 FAIL | 506 243 FAIL |
| race_city pack | 464 FAIL | 491 413 FAIL |
| race_city drift | 320 PASS | 382 278 PASS |
| race_city racing_nitro | 541 FAIL | 481 173 FAIL |
| race_city underpass | 332 PASS | 149 284 PASS |
| race_city results_1lap | 411 FAIL | 320 052 PASS |

Race and pack rows are over the draw-call budget after the race fixes. The budget was set for the city, so these rows are the first thing to optimise (the reflection pass is the first suspect).

### Known gaps in this table

- Low scale was fixed in the optimization pass above (0.67 on desktop). The preset table below it is the earlier pass, before that fix.
- No row has a GPU-timed number. The probe is CPU frame time.
- race_city `racing_nitro` is staged (capture only): the one-lap autopilot topped out at 177 to 138 km/h across runs and never reached 200 km/h. `race_city.gd` now sets the car's velocity to 230 km/h along the track tangent at s 200 to 240 m (the stretch where the track allows 252 km/h), then forces nitro. The shot was taken at 225.7 km/h. The car, physics and nitro are the real ones; the speed is not earned. The race is then driven on from there, so the one-lap race outcome in that run (1st, see results) is also not the autopilot's own pace.
- race_city `racing_nitro`: flames and speed lines are not clearly visible in the frame. Tyre smoke is visible at the rear wheels; the nitro bar drains. Not fixed in this pass.
- race_city 2 laps: not run. The `Capture` timeout is 120 s (`devtools/capture.gd` `timeout_s`, not set by the boot scene), and the one-lap run ended at 88 s. A two-lap race is expected to pass 120 s, but this was not measured.
- city_presets `downtown_overpass`: still faces a building block, not the guardrails. Not retaken in this pass.
- city_presets `pack` on all presets: start-of-race (see notes), not race pace.
- Results screen at one lap: CASH 1 000 and REP 100 (non-zero), player 1st. The earlier run without staging finished 6th with CASH 300 and REP 30.

## Visual quality gate — vertical slice, 2026-11-24 (round 3)

Two review stages on real captures from the capture harness (no mock-ups):
stage 1 = independent Haiku reviewer that did not build anything; stage 2 = lead (Claude) looking
at the same PNGs. Scale: 5 acceptable indie, 7 good commercial mobile, 9 top of the store.
Performance is desktop-only, so it is capped at 6 until a phone is measured.

| criterion | stage 1 | stage 2 (lead) | lead's reason, with the screenshot |
|---|---|---|---|
| vehicle geometry | 6 | 6 | credible original silhouette, strong wheels/brakes (`car_studio/`, `garage/overview.png`); greenhouse still boxy, wing plates plain |
| materials | 5 | 6 | clearcoat paint in the garage, convincing wet asphalt (`race_city/racing_10s.png`); rival paint reads near-black in the race, some facades flat |
| lighting | 6 | 7 | neon + lamp reflections on the wet road, lit tower windows, car-only fill light (`race_city/pack.png`, `city_districts/neon_strip.png`); waterfront and the 60 m establishing view still too dark |
| environment detail | 5 | 6 | Neon Strip dense with readable original signage; waterfront sparse; downtown street level plain |
| camera | 6 | 6 | stable chase framing with speed FOV (`race_city/racing_nitro.png`); no replay camera; drift shot weak |
| UI | 6 | 7 | coherent HUD, menus, garage and results (`race_city/results.png`); minimap sometimes over bright signs |
| effects | 5 | 5 | rain and reflections good; nitro flame reads as a white puff and speed lines are not visible at 180 km/h (`race_city/racing_nitro.png`) |
| performance | 5 | 6 | per-preset draw-call budgets met on the dev PC (table above); no phone measured |

Screens required by the brief: main menu, garage, car modification (garage paint/rims/upgrades),
race start, in-race camera, nitro, night atmosphere, results — captured. Car selection: one car
only (the garage shows it). **Police pursuit: not built (M3) — not evaluated.**

**Verdict: not passed for commercial quality.** The slice is complete and playable end to end
at an indie level (average 6.1 lead, 5.5 independent). Scaling content is still on hold.
Next fixes, in order: nitro flame + speed lines (effects 5), car paint readability in the race,
waterfront and establishing light, greenhouse/wing geometry.

### Round 4 — 2026-11-24 (after nitro/speed-line, paint and canopy fixes)

| criterion | stage 1 (independent, before the lead's paint and speed-line fixes) | stage 2 (lead, final captures) |
|---|---|---|
| vehicle geometry | 6 | 6 — continuous canopy and lower roof help; side glass still reads flat, small step at the rear of the greenhouse |
| materials | 6 | 6 — rivals now in distinct metallic colours (`race_city/pack.png`) |
| lighting | 6 | 7 |
| environment detail | 6 | 6 |
| camera | 5 | 6 |
| UI | 6 | 7 — speed lines reach into the HUD centre a little (`race_city/racing_nitro.png`) |
| effects | 5 | 6 — blue-white exhaust flames and speed lines now visible in the real race at 180 km/h |
| performance | 5 | 6 (desktop only) |

Verdict: **still not passed for commercial quality** (lead average 6.25). Earned evidence now covers
every vertical-slice item except police pursuit (not built). Remaining work toward 7+: car canopy
and side-glass shaping, pack-race traffic avoidance (stuck counts react chaotically to small AI
changes), speed-line mask over the HUD centre, waterfront and establishing light.

### Round 6 — 2026-11-25 (lead canopy rebuild, glass, flame, HUD scrim)

Two independent reviewers (art-director lens, technical-artist lens) looked at fresh captures
taken before the lead's last three fixes (glass border ring removed, flame colour, HUD scrim).
Note: both quoted race draw calls of 481-633 from an older table; the current per-preset table
above (Low 253 / Medium 255 / High 458 at race pace, budgets 250 / 350 / 500) supersedes them.

| criterion | art lens | tech lens | lead (final captures) |
|---|---|---|---|
| vehicle geometry | 6 | 6 | 7 — narrow greenhouse with tumblehome, one raked side window, A-pillar (`final/renders/contact_sheet.png` vs `contact_sheet_before_round5.png`, `garage/overview.png`); a few small steps remain at the windscreen corners |
| materials | 6 | 6 | 6 — clearcoat and wet road good; glass reads light grey at grazing angles in the garage (ceiling-bar fresnel) |
| lighting | 6 | 6.5 | 7 |
| environment detail | 5 | 6 | 6 — waterfront still sparse; rooftop "hexagon holes" in the 60 m view are AC units/tanks in shadow, not missing geometry, but they read badly |
| camera | 6 | 6 | 6 |
| UI | 6 | 6 | 7 — top scrim keeps the lap/time rows legible over neon (`ui_hud_mock/desktop_1920x1080.png`) |
| effects | 6 | 5.5 | 7 — nitro now a white-root, blue-to-magenta flame (`race_city/racing_nitro.png`), speed lines edge-only, rain, reflections |
| performance | 5 | 5 | 6 (desktop only) |

Verdict: **not passed** (lead average 6.5; materials, environment, camera and performance below 7;
performance cannot pass without a phone measurement). Next: environment density (waterfront,
rooftops), glass and car-paint read in the race, camera replay/cinematics, a phone build.
