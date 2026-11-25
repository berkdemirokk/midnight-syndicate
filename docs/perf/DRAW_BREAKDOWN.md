# Draw-call and primitive breakdown, City 01

Measured with `game/devtools/scenarios/draw_breakdown.gd` (capture `draw_breakdown`), RTX 5060 Ti 8 GB, Godot 4.7.2 Mobile renderer, 1920x1080, desktop numbers only (not iPhone numbers).
Raw data: `evidence/screens/draw_breakdown/<preset>_<moment>.json` (+ one baseline PNG per moment). Logs: `evidence/logs/draw_breakdown_high.log`, `evidence/logs/draw_breakdown_low.log`, `evidence/logs/draw_breakdown_medium.log`.
Re-run: `Godot_v4.7.2-stable_win64_console.exe --path game --resolution 1920x1080 --position 20000,0 res://devtools/capture_boot.tscn -- --capture=draw_breakdown --preset=high --timeout=600` (add `--moments=pack,results` to pick moments; moments: grid_intro, grid, pack, results, replay_orbit).

## Method

- Real race (City 01, Noctra Sable, 5 rivals, autopilot, `use_garage_paint = false`), 1 lap (the race_replay config, not race_city's 2 laps).
- At each moment the simulation is frozen (`Engine.time_scale = 0`: world, cars, camera and timers stop; rendering and `_process` keep running), so every row measures the same scene. Baseline and each row = PerfProbe over 60 frames (+10 warmup): peak and min of `RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME`, peak primitives.
- A category is hidden (`visible = false`, or the setting turned off), measured, restored. Delta = baseline minus hidden, so "-171" means 171 draws saved. Deltas are NOT additive: categories overlap (signs are inside Props, car LODs inside cars) and on High the mirror pass doubles everything it contains.
- Moments: `grid_intro` (countdown camera half way through its move, the race_replay shot), `grid` (the fixed grid camera of race_city), `pack` (about 10 s after GO, 3 rivals in view), `results` (results screen up), `replay_orbit` (REPLAY pressed, seeked to 2.5 s before the end, director in ORBIT). Replay was reachable cheaply (`ReplayPlayer.seek`).
- Absolute numbers differ a little from the old evidence JSONs (frozen scene, 1 lap): pack High 502 draws (old 501), grid High 489 / 483k prims (old 483k), grid_intro High 500 / 477k (old 517 / 504k), replay_orbit High 277 / 426k (old 584k prims), results High 463 (old 646). The old 646 was NOT reproduced: the old run was 2 laps with cars still moving; the cause is unverified.

## Answers

**Are UI draws counted? Yes.** The counter includes 2D canvas draws. Hiding the HUD CanvasLayer removes 51 to 57 draws in both the peak and the min frame (the same number, because the HUD is drawn once, not in the mirror pass). Switching the 3D viewport off (`disable_3d`) leaves 53 draws in a race frame, 87 to 90 on the results screen, 11 in the replay, all 2D. UI primitives are only about 5k.
- Race frame: HUD 51 to 52 draws. Results screen: HUD 54 to 57 plus results overlay 32, about 88 to 91 draws of pure UI. Replay UI: 11.
- That is about 21 percent of the Low budget (250) and 11 percent of High (500) spent on UI.

**Mirror pass cost (High only).** Peak minus min frame is the mirror: grid_intro 206 draws / 207k prims, grid 205 / 216k, pack 194 / 186k, results 176 / 228k, replay_orbit 133 / 197k. Disabling the PlanarReflection takes the High peak down to the min value (pack 502 to 308). It is about 40 percent of High peak draws and about 45 percent of High primitives. The main pass alone (High min) is almost the same as Low (pack 308 vs 306). So the High over-budget views are over budget only because of the mirror. The mirror renders everything on layer 0 within 150 m (rivals, props, signs, buildings, parked cars) except road and rain. Mirror share of a category = its peak delta minus its min delta (pack: Props 72, signs 62, rivals 70, player 16, building geometry 25, car LOD2 24).

**Lights: no draw effect.** Hiding every Light3D (177 city lights, car lights, moon, camera fill/rim), the reflection probes, glow, sky and fog gives delta 0 draws and 0 primitives in all moments (sky/glow/fog 1 draw only on the results screen). No light has shadows enabled (the "all shadows off" row never applied). On Mobile the lights are clustered in the shader, so they cost shader time, not draws. GPU time is not measured here.

**Zero or near-zero contributors:** Dressing (0 in every moment: 58 MultiMeshes, none drawn at these camera spots), ParkedCars (0 to 6 draws), rain 3, speed lines 1, car FX 0 to 10, car lights 0.

## Where the draws go (pack moment, High, baseline 502 peak / 308 min / 427k prims)

| contributor | draws peak | draws min | note |
|---|---:|---:|---|
| mirror pass (all of it) | 194 | 0 | prims 186k |
| props (Props MultiMeshes) | 146 | 74 | signs (`prop_sign_*`) are 122 of these (60 min) |
| rivals (5 cars, all LODs) | 140 | 70 | prims 119k |
| building geometry (FirstRow + SecondRow) | 64 | 39 | FirstRow LOD2: 32 draws for 898 prims |
| road | 38 | 30 | |
| player car | 37 | 21 | prims 92k |
| HUD | 52 | 52 | |
| car LOD2 / LOD1 / LOD0 (all cars) | 48 / 68 / 51 | 24 / 34 / 27 | LOD2 is only the far cars, still about 8 draws each |

The same ordering holds in grid, results and replay: cars and props lead, then buildings, road, HUD.

## Top 5 cuts, ranked by draws saved per visual cost (OPINION, estimates from the tables, none applied or re-measured)

1. **Merge first-row LOD2 buildings (zero visual cost).** FirstRow LOD2 costs 31 to 32 draws for under 1k primitives (pack 32 peak / 31 min, results 32 / 27). The SecondRow already uses MultiMeshes (13 draws). Merge the LOD2 children per chunk or per asset the same way. Saves about 30 on every preset and frame.
2. **Cut the HUD and results UI to a few batches (near-zero visual cost).** 52 draws for the HUD and 32 more on results, constant in every frame and preset. A static HUD of 10 to 15 batches is normal (fewer separate textures and materials, labels on one atlas, no per-element clip). Saves 35 to 40 per frame, 60 or more on results. With cut 1 this takes Low pack from 306 to about 235 (Low budget 250).
3. **Collapse the car LODs' draws.** Cars are the biggest block (rivals 140 plus player 37 peak at pack). LOD2 costs about 8 draws per car, LOD1 about 14, LOD0 about 17 to 21. Merge meshes per material (3 to 4 surfaces for LOD1, 1 to 2 for LOD2) and pull `lod1_start_m` (22 m) and `lod2_start_m` (70 m) in. Estimate 40 to 60 peak at pack, plus 60k to 100k prims at the grid when rivals are at LOD0. Visual cost low (distance only).
4. **Merge the sign meshes (low visual cost).** `prop_sign_*` MultiMeshes are about 85 percent of the prop draws (122 of 146 peak, 60 of 74 min at pack): each sign GLB has several surfaces and each chunk gets a MultiMesh per surface. Merge sign parts into one or two surfaces (frame plus emissive panel on one atlas material) and give signs a shorter far range than `prop_far_end_m`. Estimate 60 to 100 peak (about twice the min saving, because the mirror draws them too).
5. **Thin the mirror, do not kill it (medium visual cost).** The mirror is 194 peak draws. Keeping Props/signs and the SecondRow/LOD2 buildings out of it (`excluded_layers`) or cutting `max_distance_m` from 150 to about 60 saves roughly 70 to 130 peak draws and 100k+ prims, but the neon streaks on the wet road are the look of the game, so keep nearby signs and rivals in it. Cheaper variants: render the mirror every third frame (does not lower the peak) or lower `reflection_fraction_high` (fill rate, not draws).

Not worth cutting for draws: lights, probes, glow, sky, fog, dressing, parked cars, rain, speed lines (0 to 3 draws each).

Budget reading: High peak 500 (pack 502, grid_intro 500) is fixed by cuts 1 and 2 alone (about -65). Primitive budget 450k (grid 483k, grid_intro 477k): the primitives are cars (rivals 207k to 262k at the grid), building LOD0 (95k) and the mirror (207k to 216k), so cut 3 and cut 5 move them; draw merges (1, 2, 4) do not.

## Caveats

- Frozen frame, 1 lap. The results frame differs from the old 2-lap evidence (463 vs 646 draws on High), unexplained.
- Hiding an object measures only what the camera sees at that moment. `grid` and `pack` look at different parts of the track (Dressing is empty in all five views).
- Draw counts are from the desktop renderer; a mobile GPU or driver may batch differently. Draw deltas are not frame time.
- LOD rows hide the nodes named `LOD0`/`LOD1`/`LOD2` under the cars (`CarLod`) and under FirstRow; "all cars" counts every car at the LOD it was showing. Signs/neon rows are a name match (`sign`, `neon`, `billboard`) on MeshInstance3D/MultiMeshInstance3D, so they overlap Props.
- The Godot processes of the first test run hung after printing the summary (exit never came); they were killed. The later full runs exited normally (exit=0).

## Tables

Each table: baseline row, then draws saved (peak frame, min frame) and primitives saved (peak) when the category is hidden. Categories with no change are listed under each table. "2D only remainder" is an absolute count with the 3D world off (on High its peak still contains the mirror SubViewport, which the viewport switch does not stop).

#### grid_intro / high

| category | draws peak (delta) | draws min (delta) | prims peak (delta) |
|---|---:|---:|---:|
| **BASELINE** | **500** | **294** | **476,531** |
| cars: all rivals (not player) | -184 | -92 | -207,782 |
| cars: player | -22 | -12 | -59,400 |
| car LOD LOD0 (all cars incl. player) | -70 | -36 | -144,546 |
| car LOD LOD1 (all cars incl. player) | -136 | -68 | -122,636 |
| city: road + start grid | -25 | -16 | -21,104 |
| city: ALL building geometry (FirstRow+SecondRow) | -66 | -40 | -119,828 |
| city: FirstRow buildings LOD0 | -17 | -9 | -94,530 |
| city: FirstRow buildings LOD1 | -27 | -15 | -32,170 |
| city: FirstRow buildings LOD2 | -21 | -21 | -210 |
| city: SecondRow skyline/impostor MultiMeshes | -14 | -8 | -580 |
| props: layout prop MultiMeshes (Props) | -134 | -65 | -53,567 |
| signs/neon (name contains sign|neon|billboard; overlaps props/dressing) | -121 | -58 | -49,689 |
| rain (RainFx) | -3 | -3 | -2,440 |
| speed lines (SpeedLines) | -1 | -1 | -2 |
| HUD (RaceHUD CanvasLayer) | -51 | -51 | -4,744 |
| ALL CanvasLayers + replay UI (2D off) | -53 | -53 | -4,748 |
| planar reflection: disabled (mirror pass off) | -206 | -0 | -206,556 |
| 2D only remainder (absolute, 3D off; peak includes the mirror SubViewport) | 259 | 53 | 211,304 |

No change when hidden: car LOD LOD2 (all cars incl. player); car FX (CarFx particles/smoke/sparks/flame); car lights (headlights etc, all cars); dressing props (Dressing); parked cars (ParkedCars); lights: city (Lighting, non-directional); lights: ALL Light3D in scene (incl. moon, cars, cam fill/rim); lights: camera fill/rim only; lights: moon (directional) hidden; reflection probes; overlay (pause + results CanvasLayer); env: glow off; env: sky off (background -> colour); env: fog off.

#### grid_intro / low

| category | draws peak (delta) | draws min (delta) | prims peak (delta) |
|---|---:|---:|---:|
| **BASELINE** | **291** | **291** | **267,535** |
| cars: all rivals (not player) | -92 | -92 | -118,425 |
| cars: player | -12 | -12 | -35,509 |
| car LOD LOD0 (all cars incl. player) | -36 | -36 | -83,232 |
| car LOD LOD1 (all cars incl. player) | -68 | -68 | -70,702 |
| city: road + start grid | -16 | -16 | -12,918 |
| city: ALL building geometry (FirstRow+SecondRow) | -40 | -40 | -61,248 |
| city: FirstRow buildings LOD0 | -9 | -9 | -51,026 |
| city: FirstRow buildings LOD1 | -15 | -15 | -17,354 |
| city: FirstRow buildings LOD2 | -21 | -21 | -210 |
| city: SecondRow skyline/impostor MultiMeshes | -8 | -8 | -320 |
| props: layout prop MultiMeshes (Props) | -65 | -65 | -27,025 |
| signs/neon (name contains sign|neon|billboard; overlaps props/dressing) | -58 | -58 | -24,793 |
| speed lines (SpeedLines) | -1 | -1 | -2 |
| HUD (RaceHUD CanvasLayer) | -51 | -51 | -4,744 |
| ALL CanvasLayers + replay UI (2D off) | -53 | -53 | -4,748 |
| 2D only remainder (absolute, 3D off; peak includes the mirror SubViewport) | 53 | 53 | 4,748 |

No change when hidden: car LOD LOD2 (all cars incl. player); car FX (CarFx particles/smoke/sparks/flame); car lights (headlights etc, all cars); dressing props (Dressing); parked cars (ParkedCars); lights: city (Lighting, non-directional); lights: ALL Light3D in scene (incl. moon, cars, cam fill/rim); lights: camera fill/rim only; lights: moon (directional) hidden; reflection probes; overlay (pause + results CanvasLayer); env: glow off; env: sky off (background -> colour); env: fog off.

#### grid / high

| category | draws peak (delta) | draws min (delta) | prims peak (delta) |
|---|---:|---:|---:|
| **BASELINE** | **489** | **284** | **483,344** |
| cars: all rivals (not player) | -171 | -87 | -262,327 |
| car LOD LOD0 (all cars incl. player) | -79 | -41 | -169,567 |
| car LOD LOD1 (all cars incl. player) | -92 | -46 | -92,760 |
| city: road + start grid | -25 | -16 | -21,104 |
| city: ALL building geometry (FirstRow+SecondRow) | -73 | -40 | -129,506 |
| city: FirstRow buildings LOD0 | -17 | -9 | -98,554 |
| city: FirstRow buildings LOD1 | -29 | -14 | -33,766 |
| city: FirstRow buildings LOD2 | -19 | -18 | -190 |
| city: SecondRow skyline/impostor MultiMeshes | -17 | -8 | -670 |
| props: layout prop MultiMeshes (Props) | -155 | -76 | -59,545 |
| signs/neon (name contains sign|neon|billboard; overlaps props/dressing) | -143 | -70 | -55,747 |
| rain (RainFx) | -3 | -3 | -2,440 |
| speed lines (SpeedLines) | -1 | -1 | -2 |
| HUD (RaceHUD CanvasLayer) | -51 | -51 | -4,744 |
| ALL CanvasLayers + replay UI (2D off) | -53 | -53 | -4,748 |
| planar reflection: disabled (mirror pass off) | -205 | -0 | -215,585 |
| 2D only remainder (absolute, 3D off; peak includes the mirror SubViewport) | 258 | 53 | 220,333 |

No change when hidden: cars: player; car LOD LOD2 (all cars incl. player); car FX (CarFx particles/smoke/sparks/flame); car lights (headlights etc, all cars); dressing props (Dressing); parked cars (ParkedCars); lights: city (Lighting, non-directional); lights: ALL Light3D in scene (incl. moon, cars, cam fill/rim); lights: camera fill/rim only; lights: moon (directional) hidden; reflection probes; overlay (pause + results CanvasLayer); env: glow off; env: sky off (background -> colour); env: fog off.

#### grid / low

| category | draws peak (delta) | draws min (delta) | prims peak (delta) |
|---|---:|---:|---:|
| **BASELINE** | **281** | **281** | **265,319** |
| cars: all rivals (not player) | -87 | -87 | -147,671 |
| car LOD LOD0 (all cars incl. player) | -41 | -41 | -95,283 |
| car LOD LOD1 (all cars incl. player) | -46 | -46 | -52,388 |
| city: road + start grid | -16 | -16 | -12,918 |
| city: ALL building geometry (FirstRow+SecondRow) | -40 | -40 | -66,200 |
| city: FirstRow buildings LOD0 | -9 | -9 | -53,362 |
| city: FirstRow buildings LOD1 | -14 | -14 | -16,012 |
| city: FirstRow buildings LOD2 | -18 | -18 | -180 |
| city: SecondRow skyline/impostor MultiMeshes | -8 | -8 | -320 |
| props: layout prop MultiMeshes (Props) | -76 | -76 | -30,108 |
| signs/neon (name contains sign|neon|billboard; overlaps props/dressing) | -70 | -70 | -27,956 |
| speed lines (SpeedLines) | -1 | -1 | -2 |
| HUD (RaceHUD CanvasLayer) | -51 | -51 | -4,744 |
| ALL CanvasLayers + replay UI (2D off) | -53 | -53 | -4,748 |
| 2D only remainder (absolute, 3D off; peak includes the mirror SubViewport) | 53 | 53 | 4,748 |

No change when hidden: cars: player; car LOD LOD2 (all cars incl. player); car FX (CarFx particles/smoke/sparks/flame); car lights (headlights etc, all cars); dressing props (Dressing); parked cars (ParkedCars); lights: city (Lighting, non-directional); lights: ALL Light3D in scene (incl. moon, cars, cam fill/rim); lights: camera fill/rim only; lights: moon (directional) hidden; reflection probes; overlay (pause + results CanvasLayer); env: glow off; env: sky off (background -> colour); env: fog off.

#### pack / high

| category | draws peak (delta) | draws min (delta) | prims peak (delta) |
|---|---:|---:|---:|
| **BASELINE** | **502** | **308** | **427,500** |
| cars: all rivals (not player) | -140 | -70 | -119,196 |
| cars: player | -37 | -21 | -91,550 |
| car LOD LOD0 (all cars incl. player) | -51 | -27 | -144,426 |
| car LOD LOD1 (all cars incl. player) | -68 | -34 | -47,872 |
| car LOD LOD2 (all cars incl. player) | -48 | -24 | -17,984 |
| car FX (CarFx particles/smoke/sparks/flame) | -10 | -6 | -464 |
| city: road + start grid | -38 | -30 | -52,714 |
| city: ALL building geometry (FirstRow+SecondRow) | -64 | -39 | -98,663 |
| city: FirstRow buildings LOD0 | -14 | -6 | -73,338 |
| city: FirstRow buildings LOD1 | -19 | -9 | -24,314 |
| city: FirstRow buildings LOD2 | -32 | -31 | -898 |
| city: SecondRow skyline/impostor MultiMeshes | -13 | -7 | -530 |
| props: layout prop MultiMeshes (Props) | -146 | -74 | -54,166 |
| parked cars (ParkedCars) | -6 | -3 | -3,028 |
| signs/neon (name contains sign|neon|billboard; overlaps props/dressing) | -122 | -60 | -48,677 |
| rain (RainFx) | -3 | -3 | -2,440 |
| speed lines (SpeedLines) | -1 | -1 | -2 |
| HUD (RaceHUD CanvasLayer) | -52 | -52 | -5,322 |
| ALL CanvasLayers + replay UI (2D off) | -54 | -54 | -5,326 |
| planar reflection: disabled (mirror pass off) | -194 | -0 | -185,973 |
| 2D only remainder (absolute, 3D off; peak includes the mirror SubViewport) | 248 | 54 | 191,299 |

No change when hidden: car lights (headlights etc, all cars); dressing props (Dressing); lights: city (Lighting, non-directional); lights: ALL Light3D in scene (incl. moon, cars, cam fill/rim); lights: camera fill/rim only; lights: moon (directional) hidden; reflection probes; overlay (pause + results CanvasLayer); env: glow off; env: sky off (background -> colour); env: fog off.

#### pack / medium

| category | draws peak (delta) | draws min (delta) | prims peak (delta) |
|---|---:|---:|---:|
| **BASELINE** | **309** | **309** | **240,875** |
| cars: all rivals (not player) | -70 | -70 | -69,640 |
| cars: player | -21 | -21 | -52,493 |
| car LOD LOD0 (all cars incl. player) | -27 | -27 | -81,534 |
| car LOD LOD1 (all cars incl. player) | -34 | -34 | -29,330 |
| car LOD LOD2 (all cars incl. player) | -24 | -24 | -10,917 |
| car FX (CarFx particles/smoke/sparks/flame) | -6 | -6 | -352 |
| city: road + start grid | -30 | -30 | -39,704 |
| city: ALL building geometry (FirstRow+SecondRow) | -40 | -40 | -41,739 |
| city: FirstRow buildings LOD0 | -6 | -6 | -29,442 |
| city: FirstRow buildings LOD1 | -9 | -9 | -11,486 |
| city: FirstRow buildings LOD2 | -31 | -31 | -868 |
| city: SecondRow skyline/impostor MultiMeshes | -7 | -7 | -280 |
| props: layout prop MultiMeshes (Props) | -75 | -75 | -28,414 |
| parked cars (ParkedCars) | -3 | -3 | -1,514 |
| signs/neon (name contains sign|neon|billboard; overlaps props/dressing) | -61 | -61 | -25,003 |
| rain (RainFx) | -3 | -3 | -1,708 |
| speed lines (SpeedLines) | -1 | -1 | -2 |
| HUD (RaceHUD CanvasLayer) | -52 | -52 | -5,322 |
| ALL CanvasLayers + replay UI (2D off) | -54 | -54 | -5,326 |
| 2D only remainder (absolute, 3D off; peak includes the mirror SubViewport) | 54 | 54 | 5,326 |

No change when hidden: car lights (headlights etc, all cars); dressing props (Dressing); lights: city (Lighting, non-directional); lights: ALL Light3D in scene (incl. moon, cars, cam fill/rim); lights: camera fill/rim only; lights: moon (directional) hidden; reflection probes; overlay (pause + results CanvasLayer); env: glow off; env: sky off (background -> colour); env: fog off.

#### pack / low

| category | draws peak (delta) | draws min (delta) | prims peak (delta) |
|---|---:|---:|---:|
| **BASELINE** | **306** | **306** | **239,167** |
| cars: all rivals (not player) | -70 | -70 | -69,640 |
| cars: player | -21 | -21 | -52,493 |
| car LOD LOD0 (all cars incl. player) | -27 | -27 | -81,534 |
| car LOD LOD1 (all cars incl. player) | -34 | -34 | -29,330 |
| car LOD LOD2 (all cars incl. player) | -24 | -24 | -10,917 |
| car FX (CarFx particles/smoke/sparks/flame) | -6 | -6 | -352 |
| city: road + start grid | -30 | -30 | -39,704 |
| city: ALL building geometry (FirstRow+SecondRow) | -40 | -40 | -41,739 |
| city: FirstRow buildings LOD0 | -6 | -6 | -29,442 |
| city: FirstRow buildings LOD1 | -9 | -9 | -11,486 |
| city: FirstRow buildings LOD2 | -31 | -31 | -868 |
| city: SecondRow skyline/impostor MultiMeshes | -7 | -7 | -280 |
| props: layout prop MultiMeshes (Props) | -75 | -75 | -28,414 |
| parked cars (ParkedCars) | -3 | -3 | -1,514 |
| signs/neon (name contains sign|neon|billboard; overlaps props/dressing) | -61 | -61 | -25,003 |
| speed lines (SpeedLines) | -1 | -1 | -2 |
| HUD (RaceHUD CanvasLayer) | -52 | -52 | -5,322 |
| ALL CanvasLayers + replay UI (2D off) | -54 | -54 | -5,326 |
| 2D only remainder (absolute, 3D off; peak includes the mirror SubViewport) | 54 | 54 | 5,326 |

No change when hidden: car lights (headlights etc, all cars); dressing props (Dressing); lights: city (Lighting, non-directional); lights: ALL Light3D in scene (incl. moon, cars, cam fill/rim); lights: camera fill/rim only; lights: moon (directional) hidden; reflection probes; overlay (pause + results CanvasLayer); env: glow off; env: sky off (background -> colour); env: fog off.

#### results / high

| category | draws peak (delta) | draws min (delta) | prims peak (delta) |
|---|---:|---:|---:|
| **BASELINE** | **463** | **288** | **500,809** |
| cars: all rivals (not player) | -120 | -60 | -224,058 |
| cars: player | -34 | -17 | -75,056 |
| car LOD LOD0 (all cars incl. player) | -134 | -67 | -273,092 |
| car LOD LOD1 (all cars incl. player) | -20 | -10 | -26,022 |
| city: road + start grid | -25 | -16 | -37,422 |
| city: ALL building geometry (FirstRow+SecondRow) | -87 | -53 | -111,894 |
| city: FirstRow buildings LOD0 | -14 | -6 | -73,480 |
| city: FirstRow buildings LOD1 | -31 | -15 | -37,634 |
| city: FirstRow buildings LOD2 | -32 | -27 | -320 |
| city: SecondRow skyline/impostor MultiMeshes | -10 | -5 | -460 |
| props: layout prop MultiMeshes (Props) | -106 | -51 | -43,395 |
| signs/neon (name contains sign|neon|billboard; overlaps props/dressing) | -98 | -47 | -40,163 |
| rain (RainFx) | -3 | -3 | -2,440 |
| speed lines (SpeedLines) | -1 | -1 | -2 |
| HUD (RaceHUD CanvasLayer) | -54 | -54 | -5,336 |
| overlay (pause + results CanvasLayer) | -32 | -32 | -1,204 |
| ALL CanvasLayers + replay UI (2D off) | -88 | -88 | -6,544 |
| planar reflection: disabled (mirror pass off) | -176 | -1 | -227,766 |
| env: glow off | -1 | -1 | -48 |
| env: sky off (background -> colour) | -1 | -1 | -48 |
| env: fog off | -1 | -1 | -48 |
| 2D only remainder (absolute, 3D off; peak includes the mirror SubViewport) | 262 | 87 | 234,214 |

No change when hidden: car LOD LOD2 (all cars incl. player); car FX (CarFx particles/smoke/sparks/flame); car lights (headlights etc, all cars); dressing props (Dressing); parked cars (ParkedCars); lights: city (Lighting, non-directional); lights: ALL Light3D in scene (incl. moon, cars, cam fill/rim); lights: camera fill/rim only; lights: moon (directional) hidden; reflection probes.

#### results / low

| category | draws peak (delta) | draws min (delta) | prims peak (delta) |
|---|---:|---:|---:|
| **BASELINE** | **183** | **183** | **120,946** |
| cars: player | -17 | -17 | -40,307 |
| car LOD LOD0 (all cars incl. player) | -17 | -17 | -40,307 |
| city: road + start grid | -9 | -9 | -15,008 |
| city: ALL building geometry (FirstRow+SecondRow) | -14 | -14 | -38,064 |
| city: FirstRow buildings LOD0 | -4 | -4 | -30,204 |
| city: FirstRow buildings LOD1 | -6 | -6 | -7,660 |
| city: SecondRow skyline/impostor MultiMeshes | -4 | -4 | -200 |
| props: layout prop MultiMeshes (Props) | -52 | -52 | -20,809 |
| signs/neon (name contains sign|neon|billboard; overlaps props/dressing) | -43 | -43 | -19,083 |
| speed lines (SpeedLines) | -1 | -1 | -2 |
| HUD (RaceHUD CanvasLayer) | -57 | -57 | -5,544 |
| overlay (pause + results CanvasLayer) | -32 | -32 | -1,210 |
| ALL CanvasLayers + replay UI (2D off) | -91 | -91 | -6,758 |
| env: glow off | -1 | -1 | -48 |
| env: sky off (background -> colour) | -1 | -1 | -48 |
| env: fog off | -1 | -1 | -48 |
| 2D only remainder (absolute, 3D off; peak includes the mirror SubViewport) | 90 | 90 | 6,710 |

No change when hidden: cars: all rivals (not player); car LOD LOD1 (all cars incl. player); car LOD LOD2 (all cars incl. player); car FX (CarFx particles/smoke/sparks/flame); car lights (headlights etc, all cars); city: FirstRow buildings LOD2; dressing props (Dressing); parked cars (ParkedCars); lights: city (Lighting, non-directional); lights: ALL Light3D in scene (incl. moon, cars, cam fill/rim); lights: camera fill/rim only; lights: moon (directional) hidden; reflection probes.

#### replay_orbit / high

| category | draws peak (delta) | draws min (delta) | prims peak (delta) |
|---|---:|---:|---:|
| **BASELINE** | **277** | **144** | **426,184** |
| cars: all rivals (not player) | -106 | -52 | -213,076 |
| cars: player | -42 | -21 | -78,022 |
| car LOD LOD0 (all cars incl. player) | -136 | -68 | -288,164 |
| car LOD LOD1 (all cars incl. player) | -4 | -1 | -2,166 |
| car FX (CarFx particles/smoke/sparks/flame) | -8 | -4 | -768 |
| city: road + start grid | -9 | -5 | -35,366 |
| city: ALL building geometry (FirstRow+SecondRow) | -20 | -9 | -59,630 |
| city: FirstRow buildings LOD0 | -10 | -4 | -59,150 |
| city: SecondRow skyline/impostor MultiMeshes | -10 | -5 | -480 |
| props: layout prop MultiMeshes (Props) | -86 | -43 | -37,342 |
| signs/neon (name contains sign|neon|billboard; overlaps props/dressing) | -80 | -40 | -34,334 |
| rain (RainFx) | -3 | -3 | -2,440 |
| speed lines (SpeedLines) | -1 | -1 | -2 |
| ALL CanvasLayers + replay UI (2D off) | -11 | -11 | -308 |
| planar reflection: disabled (mirror pass off) | -133 | -0 | -197,133 |
| 2D only remainder (absolute, 3D off; peak includes the mirror SubViewport) | 144 | 11 | 197,441 |

No change when hidden: car LOD LOD2 (all cars incl. player); car lights (headlights etc, all cars); city: FirstRow buildings LOD1; city: FirstRow buildings LOD2; dressing props (Dressing); parked cars (ParkedCars); lights: city (Lighting, non-directional); lights: ALL Light3D in scene (incl. moon, cars, cam fill/rim); lights: camera fill/rim only; lights: moon (directional) hidden; reflection probes; overlay (pause + results CanvasLayer); env: glow off; env: sky off (background -> colour); env: fog off.

#### replay_orbit / low

| category | draws peak (delta) | draws min (delta) | prims peak (delta) |
|---|---:|---:|---:|
| **BASELINE** | **90** | **90** | **126,329** |
| cars: player | -21 | -21 | -42,989 |
| car LOD LOD0 (all cars incl. player) | -17 | -17 | -42,605 |
| car FX (CarFx particles/smoke/sparks/flame) | -4 | -4 | -384 |
| city: road + start grid | -7 | -7 | -25,596 |
| city: ALL building geometry (FirstRow+SecondRow) | -12 | -12 | -36,192 |
| city: FirstRow buildings LOD0 | -6 | -6 | -35,932 |
| city: SecondRow skyline/impostor MultiMeshes | -6 | -6 | -260 |
| props: layout prop MultiMeshes (Props) | -39 | -39 | -21,244 |
| signs/neon (name contains sign|neon|billboard; overlaps props/dressing) | -37 | -37 | -19,600 |
| speed lines (SpeedLines) | -1 | -1 | -2 |
| ALL CanvasLayers + replay UI (2D off) | -11 | -11 | -308 |
| 2D only remainder (absolute, 3D off; peak includes the mirror SubViewport) | 11 | 11 | 308 |

No change when hidden: cars: all rivals (not player); car LOD LOD1 (all cars incl. player); car LOD LOD2 (all cars incl. player); car lights (headlights etc, all cars); city: FirstRow buildings LOD1; city: FirstRow buildings LOD2; dressing props (Dressing); parked cars (ParkedCars); lights: city (Lighting, non-directional); lights: ALL Light3D in scene (incl. moon, cars, cam fill/rim); lights: camera fill/rim only; lights: moon (directional) hidden; reflection probes; overlay (pause + results CanvasLayer); env: glow off; env: sky off (background -> colour); env: fog off.
