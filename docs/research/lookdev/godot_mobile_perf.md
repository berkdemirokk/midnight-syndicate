# Godot 4.7 Mobile renderer performance on iPhone

Date: 2026-11-28. Scope: MIDNIGHT SYNDICATE, Godot 4.7.2, Mobile renderer, iOS first.

Tags: [D] = read in an official doc page during this session. [S] = search snippet only. [R] = from our own repo docs. [E] = estimate or inference. Anything not tagged is opinion.

Honest limit first: no public source gives a draw-call or triangle budget for A15, A16 or A17 at 60 fps. The budgets below are our own. They come from our desktop measurements and our own targets. Phone numbers do not exist yet (BLOCKERS B2).

## 1) What the best mobile racers do (sourced, quantified)

Public numbers from big studios are rare. What we can say with a source:

- Apple's own guidance says a sustained game must hold its frame rate through long sessions, not only in a short test. [S] https://developer.apple.com/videos/play/meet-with-apple/242
- Third-party sustained tests on recent iPhones (single creators, not controlled benchmarks) show that demanding games set to 60 fps can drop to 45 to 59 fps after some play. Some newer phones hold 60 fps for an hour with little throttling. Older Pro models throttle more. Treat as indicative only. [S] https://www.notebookcheck.net/Tomb-Raider-iOS-testing-shows-iPhone-17-Pro-Max-holds-60-FPS-for-30-minutes-here-s-how-it-runs-on-the-7-year-old-iPhone-XS.1224717.0.html ; https://www.notebookcheck.net/iPhone-17-Pro-Max-AAA-gaming-test-shows-Resident-Evil-4-running-at-60-FPS-without-thermal-throttling.1122893.0.html
- The same tests report that the A17 Pro throttles more often than newer chips. The Metal HUD thermal state moves from "Fair" to "Serious" under load. [S] https://www.notebookcheck.net/iPhone-17-Pro-Max-AAA-gaming-test-shows-Resident-Evil-4-running-at-60-FPS-without-thermal-throttling.1122893.0.html
- Mobile racers in this class (Asphalt-style and CSR-style titles) usually cut fill rate and effects, not geometry, when they need to hold 30 or 60 fps. We did not find a primary source with exact numbers for them, so this is [E].
- A strong general rule from Apple's Metal guidance: draw opaque meshes first, transparent meshes last, and skip meshes that are fully hidden. [S] WWDC19 Metal best practices, found via https://developer.apple.com/wwdc19/606

What this means for us: the phone is hot after a few minutes of race and bandwidth is the first limit. Plan for a sustained 30 fps floor with 60 fps as the target, and measure a 10 minute session, not a 10 second test.

## 2) What that means in Godot 4.7 Mobile specifically

### Renderer limits (official docs, [D])

- The Mobile renderer has no SSR, SSAO, SSIL, SDFGI, VoxelGI, volumetric fog or TAA. Do not plan on them. [D] https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html
- Mobile supports MSAA 3D and 2D, FXAA and SMAA in its feature table. [D] same page
- Mobile uses Vulkan, Direct3D 12 or Metal. On iOS that is Metal. [D] same page
- Mobile caps lights at 8 Omni and 8 Spot per mesh resource. 256 Omni and 256 Spot may be visible in one camera view. [D] https://docs.godotengine.org/en/stable/tutorials/3d/lights_and_shadows.html (already verified in docs/research/04)
- Reflection probes: 8 per mesh on Mobile. [D] renderers page
- Occlusion culling gives Mobile its best relative gain, because Mobile has no depth prepass. [D] https://docs.godotengine.org/en/stable/tutorials/3d/occlusion_culling.html . Occlusion does not cull MultiMeshInstance3D, GPUParticles3D or CPUParticles3D, so those need manual occluders. [D] same page (see docs/research/04)
- Metal backend: Apple Silicon only, per the 4.4 release notes. [D] https://godotengine.org/releases/4.4/ . Our iPhone builds run on A-series chips, so this is a known gap to check on device. [E]

### Pipeline compilation and stutter (official docs, [D])

- Godot 4.4 and later precompile pipelines for Forward+ and Mobile. The docs say there is no project setting to toggle this. [D] https://docs.godotengine.org/en/stable/tutorials/performance/pipeline_compilations.html
- The docs call it "not a perfect solution."
- Features first seen during gameplay can still stutter. The docs suggest drawing the feature early, even off-screen. For example, add a hidden instance of an effect to a node that always exists. [D] same page
- 2D (Canvas) pipelines are not precompiled. The first draw of a new HUD element can hitch. [D] same page
- Material overrides cannot be compiled at the mesh step. [D] same page
- Changing MSAA during gameplay causes stutter. So does using different MSAA levels across viewports. [D] same page. This matters for our mirror SubViewport, which must match the main view's MSAA setting or be off.
- Draw-step compilations should not occur at all. If one does, report it. [D] same page

### Shader baker (4.5 and later, [D])

- Off by default. Enable per export preset: Export dialog, "Shader Baker > Enabled". [D] https://docs.godotengine.org/en/stable/tutorials/performance/pipeline_compilations.html
- It bakes only the driver set in `rendering/rendering_device/driver`. On a macOS host it supports Vulkan and Metal. [D] same page
- The docs say it "will generally not resolve existing stutters." It mainly cuts first-launch startup time, mostly on Direct3D 12 and Metal. [D] same page
- Forum evidence: one iOS developer on 4.5 saw no startup gain. [S] https://forum.godotengine.org/t/ios-app-rejected-unresponsive-on-launch/130784
- Apple developer forum (anecdote): about a 5 second freeze on first launch with Godot's Metal backend, caused by shader translation. Cache helps the next launch. [S] https://developer.apple.com/forums/thread/824902 . Unverified. Measure it on our build.

Recipe reading: turn the shader baker on for iOS exports (it is cheap). Do not count on it for stutter. Solve stutter with a warm-up pass (see section 3).

### Visibility ranges and HLOD (4.7 docs, [D])

- Properties in the inspector: Begin, Begin Margin, End, End Margin, Fade Mode. Begin and End are measured from the center of the instance's AABB in 3D units. [D] https://docs.godotengine.org/en/stable/tutorials/3d/visibility_ranges.html
- Note: a search snippet says 4.4 measured from the origin, not the AABB center. Check this in the editor before tuning. [S]
- Fade mode Disabled switches LOD at once and gives the best performance. Self and Dependencies alpha-fade, and that forces transparent rendering during the fade. Use Disabled for cars and props. [D] same page
- Visibility ranges work with MultiMeshInstance3D. The docs name it for artist-controlled HLOD. [D] same page
- Visibility Parent lets a parent hide its children. This is our HLOD tool for building blocks. [D] same page

### Texture compression (4.x docs, [R])

- Mobile default is ETC2. High Quality import switches to ASTC. [R] docs/research/04-godot-mobile-rendering.md (from the importing_images page, verified there)
- Texture size above 4096 may not display on mobile. Cap at 2048 for heavy sets. [R] same source
- Apple GPUs read ASTC well, so set High Quality for the car and building atlases. [E]

### Metal GPU behaviour (Apple, [S])

- Apple GPUs are tile-based deferred renderers. Load and store actions control how attachments move in and out of tile memory. Use "don't care" on store when a result is not read later. Memoryless attachments avoid system memory for transient targets. [S] https://developer.apple.com/documentation/xcode/optimizing-gpu-performance.md (title only read; detail from search snippets)
- Bandwidth is the usual limit. Cut overdraw and texture reads before cutting draw calls. [S] same
- Apple's Xcode docs describe the GPU frame capture, Summary viewer (memory and bandwidth), and Shader Cost Graph and Performance Heat Maps for newer GPUs. [S] https://developer.apple.com/documentation/xcode/analyzing-your-metal-workload.md

### MSAA vs FXAA vs SMAA (our data, [R])

- Godot Mobile supports MSAA, FXAA and SMAA. [D] renderers page
- Our High preset uses MSAA 2X. Our Medium FXAA test was reverted (commit 728ab27): no phone check, no measured gain. [R] docs/perf/GPU_PASS_2026-11-28.md
- Cost: MSAA multiplies depth and colour storage in tile memory. On a tile-based GPU that is cheap if the attachment stays in tile memory (memoryless). It is costly if the MSAA buffer is resolved to system memory every frame. We do not know which case Godot's Mobile path uses on Metal. [E] Test on device.
- SMAA 1x is the cheapest good-looking AA in the list. Use it as the Medium choice once tested on device. [E]

### Shadows (our data, [R])

- Mobile: one directional shadow with 4 PSSM splits is the stock option. Our High uses SOFT_LOW. Medium and Low are unchanged after the reverted test. [D] lights page, [R] GPU_PASS doc
- No light has shadows enabled in City 01 (DRAW_BREAKDOWN). So the shadow cost today is only the sun on day tracks. [R] docs/perf/DRAW_BREAKDOWN.md

### Our own draw budgets (repo, [R], desktop numbers only)

- Draw counts are per frame from `RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME`. Desktop RTX 5060 Ti. [R] docs/perf/DRAW_BREAKDOWN.md
- Current budgets in that doc: Low 250 draws, High 500 draws, High primitives 450k.
- Measured: pack High 502 draws, 427k primitives; grid High 489 draws, 483k primitives. The mirror (planar reflection) is about 40 percent of High draws and about 45 percent of High primitives. [R] same doc
- Lights, probes, glow, sky and fog show zero draw effect. They cost shader time, not draw calls. [R] same doc
- Caveat from the repo: desktop draw counts do not predict an A-series GPU. [R]

### Profiling on device (Apple and Godot, [S])

- Xcode Metal Capture: scheme GPU Frame Capture option, then the Metal Capture button in the debug bar. [S] https://developer.apple.com/documentation/xcode/capturing-a-metal-workload-in-xcode.md
- Metal HUD (Metal performance HUD): shows frame timing and thermal state. [S] https://developer.apple.com/videos/play/meet-with-apple/242
- Game Performance Overview template in Instruments. [S] same
- Godot's own profiler and monitors work on device through the remote debugger. Frame time and draw counts from the performance monitor. [E] Confirm the remote debugger works with the cloud-built iOS export before relying on it.
- Our constraint: we cannot read crash logs or device logs here (BLOCKERS B1). The build must show its own numbers on screen (ROADMAP step 4).

### iOS export issues in 4.x (sourced where possible)

- Export needs macOS with Xcode. Windows cannot export iOS directly. [D] https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_ios.html . Our path: GitHub Actions cloud Mac (BLOCKERS B1, `.github/workflows/build-ios.yml`).
- iOS simulator runs only the Compatibility renderer. Mobile features need a real device. [D] same page
- The 4.7 docs give no iOS minimum version and no device list. [D] https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_ios.html
- A 4.4 dev snapshot says no known issues. That is a pre-release note, not a bug list. [S] https://godotengine.org/article/dev-snapshot-godot-4-4-dev-1/
- Forum reports: a "chess squares" shader bug on a physical iOS device with the Mobile and Forward+ renderers (Terrain3D issue). Not confirmed for us. [S] https://github.com/TokisanGames/Terrain3D/issues/218
- Forum reports: a missing MetalFX framework broke an Xcode build. Check our build log for that. [S] https://forum.godotengine.org/tag/ios
- Check the GitHub issue tracker with the `platform:ios` label and the 4.7 milestone before each release. [E]

## 3) Concrete RECIPE for our game

Target numbers (our own, [E], to be measured on a device):

- iPhone 11, 12, 13 or SE 3 class (A13 to A15): 30 fps floor, 60 fps target on short sessions, no crash over 10 minutes.
- Draws per frame: Low at or under 250, High at or under 500 (existing budget). Phone budget: Low 200 and Medium 300 as a first guess, to be set after the first device session.
- Primitives: High at or under 450k on desktop. Phone number unknown; measure first.
- Frame time: p95 under 33 ms at 30 fps floor, under 16.7 ms for the 60 fps target.

Steps. Each has a verify step using the capture harness.

### Step 1: Put a performance card in the iOS build (B2 gate)

- Show on screen: average frame time, p95 frame time, draw count (peak and min), and time since start. Update every 60 frames. Store the last 10 minutes in memory and print them at the end of a race.
- Files: the performance HUD or diagnostics script under `game/` (find it with codegraph_explore for "frame time" and "RenderingServer"). Use `Performance.get_monitor(Performance.TIME_PROCESS)` and `RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME`.
- Thermal state: Godot has no public thermal API in this version that we confirmed. A short native plugin or an OS-level check is needed. Mark as unverified. Until then, the owner reads the Metal HUD on a test phone (Settings > Developer, or the Xcode Metal HUD) and reports the thermal state. [E]
- Verify: run `godot --path game --audio-driver Dummy --resolution 1920x1080 --position 20000,0 res://devtools/capture_boot.tscn -- --capture=gameplay_reel` and check the card appears with real numbers. Then the device session fills the card.

### Step 2: Merge first-row LOD2 buildings (about minus 30 draws, zero visual cost)

- Source: DRAW_BREAKDOWN cut 1. FirstRow LOD2 costs 31 to 32 draws for under 1k primitives.
- Files: the building chunk builder in `game/world/city_01/` (find with codegraph_explore for "FirstRow" and "LOD2"). Merge LOD2 children into one mesh per chunk per material.
- Verify: `godot --path game --resolution 1920x1080 --position 20000,0 res://devtools/capture_boot.tscn -- --capture=draw_breakdown --preset=high --moments=pack`. Expect the FirstRow LOD2 row to drop from 32 draws to about 2. Confirm the screenshot still looks the same. Then run `--capture=tod_tracks` for the look.

### Step 3: Batch the HUD to 10 to 15 draws (about minus 35 draws, near-zero visual cost)

- Source: DRAW_BREAKDOWN cut 2. HUD is 51 to 57 draws in every frame. Results overlay adds 32.
- Files: the RaceHUD scene and its child controls under `game/ui/`. Put labels on one atlas, remove per-element clipping where it is not needed, merge static panels into one `TextureRect` or `NinePatchRect` each.
- Verify: `--capture=draw_breakdown --preset=low --moments=pack`. The HUD row should drop from 51 to about 15. Check visually at 1920x1080 and at a phone-sized viewport (the owner's 16px gutter rule applies to the menus too).

### Step 4: Warm up pipelines and keep MSAA fixed (stop first-use stutter)

- Source: pipeline_compilations docs [D]. Draw each car body material, sign, neon and HUD element once, off-screen, during the loading screen. Add a hidden copy of the effects spawned in race (smoke, sparks, drift petals) to a node that always exists.
- Do not change MSAA or the viewport AA mode during a race. Set it once at boot. Keep the mirror SubViewport on the same MSAA as the main viewport, or off.
- Files: the loading or boot scene (`game/` boot script), `game/fx/planar_reflection.gd` (MSAA setting), `game/core/graphics_preset.gd`.
- Verify: `--capture=gameplay_reel` with a hitch log. Count frames over 33 ms in the first 15 seconds of a race. Target: zero hitches caused by a first draw of a new effect. On device, the owner reports stutter in the first 15 seconds of each race.

### Step 5: Collapse car LOD draws and pull LOD distances in (about minus 40 to 60 draws at pack)

- Source: DRAW_BREAKDOWN cut 3. LOD2 is about 8 draws per car, LOD1 about 14, LOD0 about 17 to 21.
- Files: the car LOD setup in `game/car/` (find with codegraph_explore for "lod1_start_m" and "lod2_start_m"). Merge surfaces per material: 3 or 4 for LOD1, 1 or 2 for LOD2. Move `lod1_start_m` from 22 m toward 15 m and `lod2_start_m` from 70 m toward 50 m. Set fade mode to Disabled for car LOD nodes.
- Verify: `--capture=draw_breakdown --preset=high --moments=grid` and `--capture=ortakoy_benchmark --preset=high`. Look at the car LOD rows. Check a close-up `car_studio_<id>` capture to make sure the car still reads well at its LOD0 range.

Optional later steps, not in the first five: cut sign MultiMeshes (about 60 to 100 draws, DRAW_BREAKDOWN cut 4), thin the mirror (cut 5, risky: the reflections are part of the look), and bake occlusion for buildings (Mobile's best case, see section 2).

## 4) Risks and what not to do

- Do not trust desktop frame times. The earlier GPU pass showed a single frame can read 5.66 ms in one run and 3.42 ms in another (docs/perf/GPU_PASS_2026-11-28.md). Only device numbers count.
- Do not switch on FXAA or SMAA for Medium without a device A/B. The reverted FXAA test shows this.
- Do not use SSR, SSAO, volumetric fog, TAA, SDFGI or VoxelGI. Mobile does not support them. Fake the wet road with decals, cubemaps and emissive streaks.
- Do not add a shadow to every light. Mobile is capped at 8 omni and 8 spot per mesh. Keep the lit count low.
- Do not change MSAA during play. The docs name it as a stutter source.
- Do not claim "App Store ready" or any iPhone fps number before a device run. Repo rule and B2.
- Do not treat the shader baker as a stutter fix. The docs say it will not resolve stutter. It is only a startup saving.
- Do not use Forward+ on iOS. It is not our target (BLOCKERS B12 also says the Forward+ path breaks the scene).
- Do not merge meshes that have different materials into one mesh, or the look breaks. Merge per material.
- Risk: the Metal backend on A-series phones is not confirmed by an Apple-side source in our docs (Apple Silicon note is for Mac). Device session is the test.
- Risk: visibility-range AABB versus origin difference between 4.4 and 4.7. Tune in the editor and check one car at each LOD boundary.

## 5) Sources

Official docs (read this session):
- https://docs.godotengine.org/en/stable/tutorials/performance/pipeline_compilations.html
- https://docs.godotengine.org/en/stable/tutorials/3d/visibility_ranges.html
- https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html
- https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_ios.html
- https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_ios.html
- https://docs.godotengine.org/en/stable/tutorials/3d/lights_and_shadows.html (via docs/research/04, verified there)
- https://docs.godotengine.org/en/stable/tutorials/3d/occlusion_culling.html (via docs/research/04)
- https://godotengine.org/releases/4.4/ (via docs/research/04)

Search results and snippets (not fully read):
- https://developer.apple.com/documentation/xcode/optimizing-gpu-performance.md (title only)
- https://developer.apple.com/documentation/xcode/analyzing-your-metal-workload.md
- https://developer.apple.com/documentation/xcode/capturing-a-metal-workload-in-xcode.md
- https://developer.apple.com/videos/play/meet-with-apple/242
- https://developer.apple.com/wwdc19/606
- https://developer.apple.com/forums/thread/824902 (anecdote, unverified)
- https://forum.godotengine.org/t/ios-app-rejected-unresponsive-on-launch/130784 (anecdote)
- https://forum.godotengine.org/tag/ios
- https://github.com/TokisanGames/Terrain3D/issues/218
- https://godotengine.org/article/dev-snapshot-godot-4-4-dev-1/
- https://www.notebookcheck.net/iPhone-17-Pro-Max-AAA-gaming-test-shows-Resident-Evil-4-running-at-60-FPS-without-thermal-throttling.1122893.0.html (third-party, indicative)
- https://www.notebookcheck.net/Tomb-Raider-iOS-testing-shows-iPhone-17-Pro-Max-holds-60-FPS-for-30-minutes-here-s-how-it-runs-on-the-7-year-old-iPhone-XS.1224717.0.html (third-party, indicative)

Repo sources:
- docs/perf/DRAW_BREAKDOWN.md
- docs/perf/GPU_PASS_2026-11-28.md
- docs/research/04-godot-mobile-rendering.md
- BLOCKERS.md (B1, B2, B12)

Not reached: the Godot 4.7 shader baker page on device behaviour, the Apple Metal optimisation page body (fetched title only), 4.7.2 release notes, and any public A15 to A17 draw budget.
