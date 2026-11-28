# Production plan: lookdev and feel sprint (2026-11-28)

Lead: Opus. Workers: Haiku, each in its own worktree, one independent review per package before merge.
Inputs: the 10 notes in this folder, `docs/art/VISUAL_TARGET.md`, `docs/status/MASTER_CHECKLIST.md`, `PROGRESS.md`
(sessions 7 to 9), and the code they name (checked in the repo on 2026-11-28).
All numbers marked "dev PC" were or will be measured on Windows 11, RTX 5060 Ti 8 GB, Godot 4.7.2 Mobile renderer,
1920x1080. Dev PC numbers are not iPhone numbers.

---

## 0. Research audit (what was wrong, stale or unsupported)

Five claims that decide the plan, checked by the lead on 2026-11-28 against the primary pages:

| # | Claim (note) | Check | Result |
|---|---|---|---|
| V1 | Mobile has no SSR, SSAO, SDFGI, VoxelGI, volumetric fog or TAA; probes 8 per mesh; lights 8 per mesh / 256 per view; MSAA, FXAA, SMAA and LightmapGI supported (all notes) | renderers.html feature table | **Confirmed.** The decal cap of 8 per mesh is not on this page (it is in the decals doc); keep it as a rule. |
| V2 | Bake LightmapGI in the editor and ship it (environment_lookdev step 1) | forum 129607 (Calinou): `LightmapGI.bake()` is not exposed to scripting, not even in editor builds | **Confirmed, but the plan does not fit our game.** Our tracks are built at runtime by `city_builder.gd` from JSON (`istanbul_bogaz.tscn` holds only the builder node). There are no saved meshes to bake, and three times of day would need three bakes per track. **LightmapGI is dropped.** Replacement in section 2. |
| V3 | Mobile probe returns about 2x radiance and clips at 1.0, "open issue" (environment_lookdev) | github issue 124069 | **Behaviour confirmed on 4.7.2; status wrong.** The issue is closed as *not planned*. Workaround from the thread: probe `intensity` 0.5 on Mobile. Bright neon still clips at 1.0. Any new probe must use 0.5 and must not be the source of neon highlights. |
| V4 | Metal is "Apple Silicon only", so A-series iPhones are a risk (godot_mobile_perf) | 4.4 release notes: "limited to Apple Silicon (ARM) devices" | **Misread.** A-series iPhone chips are Apple Silicon ARM devices; the note excludes Intel Macs, not iPhones. Remove this risk. Confirm the driver in the next iOS build log only. |
| V5 | 4.7 clearcoat gained energy conservation and sky/probe reflections, "a better fit for car paint"; AreaLight3D Mobile support not stated (car_shading, night_wet_roads) | godotengine.org/releases/4.7 | **Confirmed both.** Do not use AreaLight3D this sprint. |
| V6 | Visibility-range fade Self forces transparency; Disabled is cheapest (foliage, perf) | visibility_ranges.html | **Confirmed**, and the page adds: the fade mode only acts when a margin is above 0. Our LODs use FADE_SELF with margin 0, so they already switch hard. The perf note's "set fade to Disabled" is a no-op. The lead reverted the margins in 861a0908 for the same reason. |

Other corrections found while reading the code:
- **Tonemapper is ACES, not AgX** (`city_builder.gd:1676`, garage, menu). The "AgX ignores White on Mobile" trap in
  night_wet_roads and post_and_camera does not apply. `tonemap_white` 6.0 / 2.5 / 1.0 does take effect. Their step 1 is done.
- **The glow threshold is already set explicitly** on every track (`time_of_day.gd:287`, Bosphorus 1.05). night_wet_roads step 2 is done.
- **The mirror already has preset tiers** (`race_scene.gd:717-719`: fraction per preset, `every_second_frame` on Medium).
  night_wet_roads step 3 is mostly done.
- **The shake curve**: post_and_camera puts "shake = trauma^2" and "0.3/0.6/0.9 gives 3/22/73 %" in one table. Those
  percentages are trauma cubed (0.3^3 = 2.7 %). Our code uses trauma squared with incommensurate sines (smooth, not
  random), and a `camera_shake` setting (0..1) already exists. Only a reduced-motion switch for blur and FOV kick is missing.
- **Car LOD distances**: godot_mobile_perf step 5 says to pull `lod1_start_m` from 22 m to 15 m. Rivals already switch at
  6 m / 35 m (`race_config.gd:25-26`). Only the player keeps 22 / 70. The real car problem is 59 objects at LOD0 against a
  20 budget (MASTER_CHECKLIST 2b).
- **DRAW_BREAKDOWN cuts 1 and 2** (FirstRow LOD2, HUD) were measured on City 01 before the session 3 batching pass.
  Re-measure on Bosphorus before anyone works on them.
- `car_visual.gd` exists, at `game/vehicles/car_visual.gd` (car_shading said it did not; it looked in the wrong folder).
- The ui_ux 44 pt target is unverified (the HIG body did not load). The repo constant `PHONE_BUTTON_H = 124 px` stays the rule.
- free_multiplayer calls the Apple Developer fee "already needed". That is an owner cost, not zero. Listed in section 5.
- Weak sources used for direction only, never for numbers: fan wikis (Asphalt, NFS), Grokipedia, marketplace polycounts,
  vendor draw-call blogs, and the GSMArena "SSR" claim.
- agent-reach: the CLI is blocked on this PC ("Permission denied" from `~/.local/bin/agent-reach`, also seen in
  engine_audio). The checks above used WebFetch.

---

## 1. Acceptance criteria per area

Each item says how it is checked. "Look" means the lead judges a harness capture against VISUAL_TARGET.md and the owner
signs off on the sheet. Only the end-of-sprint pass (section 6) produces evidence.

| Area | Criterion | Check |
|---|---|---|
| Car | Paint stays candy red: shaded body pixels within dE 10 of #8E0F1E on day, sunset and night studio shots | `car_studio_tayfun` + `car_studio_sable`, sampled by `tools/` script |
| Car | Sharp hot specular on roof and rear arch, no pink wash (look) | same shots + `ortakoy_benchmark` hero |
| Car | LOD0 ≤ 25 surfaces per car (now 59 objects); LOD1 ≤ 6; LOD2 ≤ 2 | `test_car_licensed.gd` surface counts |
| Car | No visible LOD pop on the car ahead at 200+ km/h | side reel stepped frame by frame |
| Car | Night: front lamps bloom, the tail lamps glow at rest and flare on brake, the glass rim shows | night studio shot of 2 cars |
| Environment | Photo facades read depth at grazing angles at night (lit windows show a room, not a flat glow) | `gameplay_reel` night, bogaz + maslak |
| Environment | Contact darkening at wall bases, kerbs and under eaves on every track (no floating buildings) | `tod_tracks` day |
| Environment | Per-track palette: Ortakoy warm + blossom pink, Maslak cool steel, Wharf teal/magenta (look) | `tod_tracks` contact sheet |
| Foliage | Zero alpha-blended tree materials; leaf atlases ≤ 512 px (LOD0), ≤ 256 px (LOD1/2) | `test_greenery.gd` assertion |
| Foliage | Blossom canopy reads as pink mass at 30-60 m, back-lit at sunset (look) | `tod_tracks` bogaz day + sunset |
| Foliage | Petals ≤ 140, off on Low (exists) | `test_fx.gd` |
| Night/wet | Neon and lamps streak on the wet road; centre lines visible; no square-grid artefact | `fx_wet_road`, night reels; on iPhone by eye |
| Night/wet | Rival cars light the road with pools, not real lights: ≤ 2 SpotLight3D in the scene (player only) | node count test |
| Camera/post | One screen-copy pass only (post_grade); blur taps 0 / 3 / 5 for Low / Medium / High | `test_perf_presets.gd` |
| Camera/post | Reduced motion OFF turns off blur, speed shake and FOV kick | unit test |
| Camera/post | FOV rest-to-top + nitro sum ≤ 16 deg; the car fills ≥ 18 % of frame width at top speed | reel frame at 0/120/200 km/h |
| Handling | Touch: finger down to 90 % lock ≤ 9 physics ticks at 60 km/h, ≤ 15 ticks at 200 km/h (60 Hz) | `test_handling_feel.gd` |
| Handling | Steer assist: zero-input lap of `istanbul_bogaz` within 15 % of the autopilot lap, ≤ 2 wall hits | headless probe |
| Handling | Drift exit and grip exit speeds 2 s after the corner within 5 % (Sable, Vela) | probe JSON in `evidence/` |
| Handling | Wall friction combine rule written down, reproduced by 2 wall settings | probe |
| UI | Every touch control ≥ `button_h()` and inside the safe frame, with zero and forced insets | unit test |
| UI | Speed digits ≥ 18 % of screen height; ≤ 3 accent colours on the HUD (look) | HUD capture 1920x1080 + 2532x1170 |
| UI | HUD ≤ 20 draw calls in a race frame | `draw_breakdown` HUD row |
| Audio | 20 s mix: peak ≤ 0.891 (-1 dBFS), no clipped samples | WAV render stats |
| Audio | Tyre gain monotonic in slip up to the knee, silent under slip 0.2; ≤ 4 tyre voices | `test_audio_layers.gd` |
| Audio | CarAudio ≤ 50 µs/frame on the dev PC; owner listening sign-off | perf log + owner |
| Perf (dev PC proxy) | High ≤ 500 draws / 450k primitives, Medium ≤ 350, Low ≤ 250 on every race view and track | `draw_breakdown` all presets |
| Perf (dev PC proxy) | 0 frames > 25 ms in the 15 s after GO, over 10 runs | `hitch_probe` |
| Perf (iPhone, owner) | Sustained 30 fps floor over 10 min, p95 frame < 33.3 ms; 60 fps target on A15+ for the first 2 min | on-screen perf card |
| Perf (iPhone, owner) | Thermal state ≤ "Serious" after 10 min (Metal HUD); no crash; first launch < 10 s | owner report |
| Perf (iPhone, owner) | Touch steering does not feel late; mirror has no grid; no stutter in the first 15 s | owner report on a checklist |

---

## 2. Technique per gap

| Gap | Technique chosen | Why | Source |
|---|---|---|---|
| Flat lighting, no GI (MASTER 1) | **Offline AO/bounce baked in Blender Cycles into the road GLB (texture) and the kit GLBs (vertex colour)**, extending `bake_vertex_ao.py`; keep `day_bounce.gd` fill. No LightmapGI. | Runtime-built tracks and three times of day rule out LightmapGI (V2). AO does not depend on time of day. Blender runs headless from scripts. | V2; existing pipeline (PROGRESS session 4) |
| Flat photo facades at night | **Interior mapping** in `photo_facade.gdshader`: the room parallax is masked by the night picture's lit windows; LOD0 only (≤ 30 m) | Real depth with no geometry; cost is per pixel and bounded by LOD0 | Van Dongen 2008 (environment_lookdev) |
| Car paint depth | Keep clearcoat 1.0 / 0.04 + street panorama pass; add a night-only clearcoat streak term; flake normal stays ≤ 0.035 | 4.7 clearcoat now uses sky and probes (V5); the panorama pass matches the CSR2 "hybrid specular" idea | V5; GDC 2016 CSR2 session text |
| Car draw calls (59 vs 20) | Merge surfaces per material in `assets_src/pipeline` (vertex colours already carry part colours) | Part colours moved to COLOR_0 in session 7, so surfaces can merge without losing looks | MASTER 2b; Simplygon racing LOD note |
| Car LOD pop | Hard switch (margin 0), more rear detail kept at decimation | Mobile fades double-draw (861a0908); players see the rear most | V6; Simplygon |
| Probes for street reflections | **No new track probes this sprint.** Panorama per track stays the reflection source | Probe 2x/clip bug is closed not planned (V3) | V3 |
| Foliage overdraw | Alpha-tested only, leaf atlases shrunk per LOD, 2-3 crossed cards at LOD2; impostor addon only after a licence check | Mobile has no auto-instancing; alpha blend costs fill rate | Godot optimizing-3D + visibility-range docs |
| Rival headlights | Additive `glow_pool.gdshader` quad under each rival lamp; player keeps 2 spots | Real lights cost per pixel; the pool shader already exists | Mobile light caps (V1); Unity cookie-cost reports [U] |
| Speed feel | Keep the one-pass post; preset tap budget; reduced-motion switch; test 3 chase distances | One screen copy per frame; stacking effects cause motion sickness | Godot screen-reading docs; issue 108935 [S]; Eiserloh GDC 2016 |
| Touch lag | Touch skips the keyboard ramp | The ramp caps the rate at speed (0.45 s full lock at top speed) | player_driver.gd arithmetic |
| Phone players who do not steer | Steer-assist mode with a hard cap of a few degrees | The genre default is assisted steering | handling_feel 1.1 (fan guide, idea only) |
| Drift vs grip balance | Short exit push on both lines | Unbound review: the grip exit pays "just like drifting" | gamermatters review |
| Tyre audio | Per-wheel voice, 3 slip ranges with equal-power crossfade | Standard layered method | Dolby Inertial Drift blog; patents (idea only) |
| Mix clipping | Music duck 6-9 dB + master limiter at -1 dBFS | Current peak 0.226 is fine; the limiter guards the new layers | Godot audio buses doc |
| First-use stutter | Off-screen warm-up of materials and FX during loading; shader baker on for iOS (startup only) | Docs: precompilation is "not a perfect solution", the baker does not fix stutter | pipeline_compilations doc |
| No phone numbers | On-screen perf card in release builds | B1: device logs cannot be read here | BLOCKERS B1/B2 |

Dropped this sprint, with the reason: LightmapGI (V2), new ReflectionProbes (V3), AreaLight3D (V5), chromatic
aberration and per-object motion blur (an extra screen copy or a velocity buffer), SSR of any kind (V1), MSAA above 2x,
HDR 2D, internet multiplayer code (owner decision first, section 5).

---

## 3. Work packages (Haiku)

Rules for every package: own only the files listed; add tests as `game/tests/test_*.gd` (the runner auto-discovers them;
do not edit `run_tests.gd`, `project.godot` or the contract files); run the full suite before and after
(`godot --headless --fixed-fps 60 --path game -s res://tests/run_tests.gd`, exit 0); no screenshots during the package
except where "evidence" says so; every Godot run uses `--audio-driver Dummy`. One GPU job at a time on the PC (Blender
renders and Godot captures share one 8 GB card).

### Wave A: parallel, CPU and headless only (start at once, 6 workers)

**WP-A1 Touch steer rate.** Goal: touch reaches lock fast at every speed.
Files: `game/vehicles/player_driver.gd` (`_update_steer` only), new `game/tests/test_touch_steer.gd`.
Recipe: give touch its own rate (`touch_turn_rate` 14) with no high-speed cap; the keyboard ramp stays unchanged.
Test: ticks to 90 % lock ≤ 9 at 60 km/h and ≤ 15 at 200 km/h; the keyboard numbers stay equal to the current ones.
Evidence: test output. Deps: none.

**WP-A2 Wall friction rule probe.** Goal: know Jolt's combine rule before any wall tuning.
Files: new `game/tests/test_wall_friction_rule.gd` (probe only, no gameplay change).
Recipe: glancing 15 deg hit at 120 km/h against a wall with friction 1.0 rough false, then rough true, then 0.05.
Record kept speed for each; infer lowest-wins, highest-wins or geometric mean.
Test: three numbers recorded and the rule stated in the test name. Evidence: `evidence/handling/wall_rule.json`. Deps: none.

**WP-A3 Drift and grip exit push.** Goal: drift pays on exit, the grip line pays the same.
Files: `game/vehicles/arcade_car.gd` (drift-exit path + 2 constants), new `game/tests/test_exit_push.gd`.
Recipe: 0.3 s at 1.15x engine force when a drift ends above `drift_entry_speed_kmh`; the same push after a grip turn
with yaw rate above a threshold at the same speed.
Test: speed 2 s after exit, drift vs grip, within 5 % on Sable and Vela; no change on straight-line acceleration tests.
Evidence: `evidence/handling/exit_push.json`. Deps: WP-A2 done (do not tune both at once).

**WP-A4 Steer assist mode.** Goal: a phone player who never steers finishes a lap.
Files: `game/vehicles/player_driver.gd` (new `MODE_ASSIST` branch only; WP-A1 merges first), `game/core/settings.gd`
(option value), new `game/tests/test_steer_assist.gd`.
Recipe: target heading = racing line point 12 m ahead; assist steer capped at 6 deg; player input adds on top; drift and
nitro stay manual. Settings label TR/EN.
Test: headless zero-input lap on `istanbul_bogaz` within 15 % of the autopilot lap, ≤ 2 wall hits.
Evidence: probe JSON. Deps: WP-A1 merged.
Implemented deviations (approved by the lead review, 2026-11-28): look-ahead 0.6 s x speed, 12..45 m (a fixed 12 m gave
21 contacts, a fixed 30 m 2 to 20: the 30 m result flipped with tiny Jolt contact differences, which is why the full suite
failed and the solo run passed; it was not a leaked state). Speed hold at 0.9 x the autopilot line speed, and only while no
accelerate or brake input is held, so manual pedal input is not capped. Dev PC: 53.8 s vs 52.38 s (1.027), 0 contacts,
the same in 6 of 6 runs with and without race scenes run first.

**WP-A5 Tyre audio and mix guard.** Goal: drifts sound like drifts; nothing clips.
Files: new `game/audio/tyre_audio.gd`, `game/audio/car_audio.gd` (hook only), `game/tests/test_audio_layers.gd`.
Recipe: 4 per-wheel voices (`max_polyphony` 1), rolling vs sliding by slip ratio, 3 slip-angle ranges with equal-power
crossfade, pitch +8 % at high slip, gain clamped 0..1. No per-frame allocation.
Test: monotonic sweep 0 to 1.5, silence under 0.2, ≤ 4 voices; 20 s mix peak ≤ 0.891.
Evidence: `evidence/audio/race20_player_mix.wav` stats. Deps: none. (Bus limiter and ducking: lead, section 4.)

**WP-A6 Perf card and warm-up.** Goal: the next iPhone session returns numbers; no first-use hitches.
Files: new `game/ui/hud/perf_card.gd`, new `game/core/pipeline_warmup.gd`, the loading screen script (hook only),
new `game/tests/test_perf_card.gd`.
Recipe: card shows mean and p95 frame time, peak and min draws, minutes since start; updates every 60 frames; keeps
10 min in a ring buffer; prints a summary at race end; toggle in settings, on by default in TestFlight builds. Warm-up
draws every car material, neon, smoke, sparks, petals and HUD element once off-screen while loading.
Test: card fields are numbers after 120 frames; ring buffer caps at 36000 samples. Evidence: `hitch_probe` 10 runs at the
end of the sprint (section 6). Deps: none.

**WP-A7 Reduced motion and blur budget.** Goal: speed effects scale by preset and can be turned off.
Files: `game/fx/post_fx.gd`, `game/shaders/post_grade.gdshader` (tap count uniform), `game/camera/chase_camera.gd`
(FOV kick gate only), `game/core/settings.gd` (WP-A4 merges first), new `game/tests/test_reduced_motion.gd`.
Recipe: `blur_taps` 0 / 3 / 5 by preset (the loop keeps const 6 and breaks on the uniform); setting `reduced_motion`
OFF / LOW / HIGH: OFF disables blur, speed shake and nitro FOV kick.
Test: each preset's tap count; OFF gives zero blur, zero speed shake, zero kick. Deps: WP-A4 (settings.gd).

### Wave B: asset and scene work (parallel by file, GPU jobs queued one at a time)

**WP-B1 Car surface merge.** Goal: LOD0 ≤ 25 surfaces, LOD1 ≤ 6, LOD2 ≤ 2 for all 11 cars, same look.
Files: `assets_src/pipeline/prepare_vehicle.py` (merge step), `assets_src/pipeline/rebuild_vehicles.py`,
`game/assets/vehicles/**` (rebuilt output), `game/tests/test_car_licensed.gd` (surface caps).
Recipe: merge by engine material name after the COLOR_0 transfer; keep paint, glass, lamp lens, tyre, rim as separate
surfaces; at decimation weight the rear half 1.5x. Rebuild all cars in one Blender batch (GPU queue slot 1).
Test: surface caps; `test_part_colours_reach_the_right_materials` still passes; tri caps 90000 / 28000 / 7000 kept.
Evidence: `car_studio_*` for 4 cars before/after (taken in section 6). Deps: none. Heaviest package: start first in Wave B.

**WP-B2 AO bake for road and kits.** Goal: contact darkening on every track without runtime cost.
Files: `assets_src/pipeline/bake_vertex_ao.py`, new `assets_src/pipeline/bake_road_ao.py`,
`game/assets/world/istanbul_bogaz/istanbul_bogaz_road.glb` and the maslak/city road GLBs, `game/shaders/wet_asphalt.gdshader`
(sample an AO texture on UV2, multiply into albedo and the reflection mask).
Recipe: add a UV2 unwrap to each road GLB if it has none; Cycles AO bake, 1024 px per road GLB, kerbs and wall bases in the scene from the layout JSON as occluders; kit
GLBs get vertex AO the same way the Ortakoy kit did.
Test: the road material has an AO texture; the ASSET_MANIFEST validator passes (`py -3.10 tools/asset_factory.py validate`).
Evidence: `tod_tracks` day (section 6). Deps: none. GPU queue slot 2.

**WP-B3 Foliage diet.** Goal: same pink mass, less fill.
Files: `assets_src/world/kit_trees/prepare_licensed_trees.py`, `game/assets/world/kits/trees_photo/**`,
`game/world/greenery/greenery.gd` (LOD2 card count only), `game/tests/test_greenery.gd`.
Recipe: atlases 512 (LOD0) / 256 (LOD1, LOD2), power of two; LOD2 2-3 crossed cards; assert no tree material uses
alpha blend. Do not touch `LOD_RANGES` or the sway.
Test: atlas sizes and transparency mode asserted. Evidence: `tod_tracks` bogaz day + sunset (section 6). Deps: none.

**WP-B4 Rival lamp pools.** Goal: rivals light the wet road without real lights.
Files: `game/fx/headlights.gd`, `game/fx/car_fx.gd` (hook), new `game/tests/test_lamp_pools.gd`.
Recipe: rivals and traffic get one additive quad per lamp pair with `glow_pool.gdshader` (night and sunset only); player
keeps its 2 SpotLight3D; pools off on Low.
Test: ≤ 2 SpotLight3D in a 6-car night race; pool count = cars - 1. Deps: none.

**WP-B5 Draw re-measure on Bosphorus, then sign merge.** Goal: know the current top draw sinks; cut the biggest cheap one.
Files: `game/devtools/scenarios/draw_breakdown.gd` (track argument), `docs/perf/DRAW_BREAKDOWN.md`, then
`assets_src/pipeline/prepare_static.py` (sign parts to 2 surfaces) and the sign GLBs.
Recipe: run `draw_breakdown --track=bogaz` High/Medium/Low (GPU queue slot 3); if HUD > 20 or FirstRow LOD2 > 10, report
to the lead instead of fixing; merge sign surfaces.
Test: sign MultiMesh count halves; budgets still met. Evidence: the JSON per preset. Deps: none.

**WP-B6 Shader baker and export check.** Goal: faster first launch on iOS.
Files: `game/export_presets.cfg` (iOS preset only).
Recipe: enable Shader Baker in the iOS preset; touch nothing else.
Test: the CI iOS compile check stays green. Evidence: run id. Deps: lead approval of the preset edit.

### Order and batching

```
Wave A: A1, A2, A5, A6 start together -> A3 (after A2), A4 (after A1) -> A7 (after A4)
Wave B: B1, B2, B3, B4, B5 code edits start together with Wave A
GPU queue (one at a time): B1 Blender rebuild -> B2 Cycles bake -> B5 draw_breakdown
Lead tracks (section 4) run beside both waves; integration last
Section 6 verification pass once, after all merges
```

---

## 4. Lead (Opus) work

1. **Interior mapping shader** in `game/world/street_fronts/photo_facade.gdshader`: mask from `night_tex` luminance,
   3-4 room layers, random tint per cell, LOD0 rows only, `night` uniform gates it. Hard shader, look-critical.
2. **Night clearcoat streak term** in `game/shaders/car_reflection.gdshader` / `car_materials.gd` (flake ≤ 0.035).
3. **Look decisions**: chase distance A/B/C (current, 4.0/1.15, 3.4/1.10) and FOV rest/top (62/72 vs 66/76) from one reel
   each; per-track palettes in `time_of_day.gd`; whether a rival lamp pool reads as light or as a decal.
4. **Audio bus layout** (`game/default_bus_layout.tres`, lead-owned): music duck 6-9 dB, 50 ms attack, 400 ms release;
   master limiter -1 dBFS.
5. **Paint sampler**: a short `tools/paint_de.py` (mean dE of masked body pixels against #8E0F1E) for section 6.
6. **Contracts**: the reduced-motion and steering-mode setting keys; the perf card toggle; approve WP-B6.
7. **Reviews**: every package gets one independent Haiku review, then the lead reads the diff and the test output.
8. **Integration**: merge in dependency order, run the full suite after each merge, then run section 6.
9. **Records**: PROGRESS.md entry with real numbers and SHAs; update MASTER_CHECKLIST rows 1, 2b, 3, 17, 23, 27.

---

## 5. Owner-only decisions and external dependencies

| Item | Why it needs the owner | Blocks |
|---|---|---|
| iPhone session with the new TestFlight build (model name, 10 min race, perf card photo, Metal HUD thermal state, touch feel, mirror artefacts, stutter in first 15 s) | Only the owner has a device (B1/B2) | all iPhone criteria; any "App Store ready" claim |
| Push the release tag for the iOS build | Release tags are pushed by the owner | the TestFlight build with this sprint |
| Listen to the engine, tyre and mix renders | Nobody has judged the sound by ear | audio sign-off |
| Pick between camera A/B/C and FOV sheets | Taste call | camera lock |
| Online play: choose EOS (Epic account + EOS terms), Game Center (Apple Developer Program, about $99/year, plus a native GKMatch plugin) or Cloudflare signalling (account + terms) | Each needs an account and an agreement; Game Center needs a paid membership | internet multiplayer (MASTER 9, 11) |
| Downloads: more licensed cars (MASTER 2), the octahedral impostor addon (licence check first), an OFL display font (B4) | Downloads need the owner's yes | 30-car scope, far-tree impostors, HUD font |
| Bundle id, team id, price, age rating (B7, MASTER 26) | Account owner | App Store submission |

---

## 6. End-of-sprint verification pass (once, after all merges)

Run serially on the dev PC with the GPU free. Harness:
`godot --path game --audio-driver Dummy --resolution 1920x1080 --position 20000,0 res://devtools/capture_boot.tscn -- --capture=<scenario> [args]`

1. **Tests and assets**: full suite exit 0 (count recorded); `py -3.10 tools/asset_factory.py validate` 0 failing.
2. **Stills**:
   - `car_studio_tayfun`, `car_studio_sable`, `car_studio_vela`, `car_studio_kestrel`: day and night, before/after sheet.
     Run the paint dE sampler.
   - `tod_tracks`: all tracks, day/sunset/night, High, plus bogaz Low. Contact sheet.
   - `ortakoy_benchmark`: all moments.
   - `fx_wet_road`, `garage`, the race HUD at 1920x1080 and 2532x1170.
3. **Reels** (`gameplay_reel`, 8 fps, 14 s; then `tools/reel_sheet.py` for a sheet and an MP4):
   - bogaz chase day, bogaz chase sunset, maslak chase night, city side night.
   - Camera A/B/C: 3 bogaz chase reels at 200 km/h, for the owner's pick.
   - Step through each MP4 for LOD pops; note time and object.
4. **Numbers** (dev PC, named machine):
   - `draw_breakdown` High/Medium/Low on bogaz, maslak and city: peak draws and primitives against the budgets.
   - `hitch_probe`: 10 runs, frames > 25 ms in the 15 s after GO.
   - Night gameplay mean and p95 frame time.
   - CarAudio µs per frame; the 20 s mix peak and RMS.
   - Handling probe JSONs (A1 to A4).
5. **Look review**: the lead scores each area in section 1 against VISUAL_TARGET.md on the sheets. The owner signs off on
   the car, foliage and night sheets.
6. **Ship**: iOS compile check green, then the owner pushes the release tag and runs the iPhone checklist in section 5.
   Desktop results go in TEST_RESULTS.md and GRAPHICS_BENCHMARK.md; iPhone results go in a separate table only when the
   owner reports them.
