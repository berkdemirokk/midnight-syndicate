# REA_ANALYSIS: MIDNIGHT SYNDICATE research synthesis
Date: 2026-11-24. Inputs: C:\Users\berk\car race\docs\research\01 to 07.
Tags: [S] = the source research file marks it as read in a fetched page. [E] = estimate, inference, snippet-only or unverified. Numbers in "Decision" are starting values to tune in Godot, not verified facts.
## Method and limits
- The analysis used public sources only: store pages, official docs, developer talks and blogs, wikis, public reviews and public gameplay descriptions.
- The REA (reverse-engineer-anything) binary/decompilation tooling was deliberately NOT run on any competitor binary, because that would break the clean-room rule and store terms. REA tooling is reserved for inspecting this project's own builds.
- This file synthesizes the seven research files. It did not re-open the URLs. Tags come from those files; snippet-only claims stay [E]. Uncited claims in the inputs were dropped.
- Verification corrections are applied: NFSU2 has 11 unique sponsor races per stage (3 run); CarX Steam is 9,785 English reviews, 70% positive; the Windows-export exclusion is [E]; the NFSNL developer is unresolved.
- Failed or unreachable: both Gamezebo pages (HTTP 403, https://www.gamezebo.com/reviews/need-for-speed-no-limits-review-push-it-to-the-limit/), OpenGameArt (403, https://opengameart.org/), NFSU2 fandom (402, https://nfs.fandom.com/wiki/Need_for_Speed:_Underground_2), Pacejka page (404, https://en.wikipedia.org/wiki/Pacejka%27s_Magic_Formula), Eiserloh GDC talk (login wall, https://gdcvault.com/play/1023146/Math-for-Game-Programmers-Juicing), GameAIPro ch.38 (no text extracted). No reachable Reddit thread was found.
- Not found in any opened source: chase camera, rival AI and rubber banding for NFSNL and Asphalt; HUD and garage UX for NFSNL, Asphalt and NFSU2; lighting of NFSNL and Asphalt; Asphalt traction model.
- No quotations are reproduced. All references are paraphrased.
## 1. Arcade vehicle physics
**Observed in references:**
- Godot's VehicleWheel3D has known issues and is not built for realistic vehicle physics; custom integration is suggested. [S] https://docs.godotengine.org/en/stable/classes/class_vehiclewheel3d.html
- Stiffness is in N/mm (race cars roughly 50-100); damping about 0.3 normal, 0.5 race; max force above a quarter of mass. [S] https://docs.godotengine.org/en/stable/classes/class_vehiclewheel3d.html
- Jolt: opt-in in 4.4 (called experimental there); stable docs say new projects use it. Kinematic-frozen bodies skip some contacts unless a setting is on. [S] https://docs.godotengine.org/en/stable/tutorials/physics/using_jolt_physics.html ; https://godotengine.org/releases/4.4/
**Unknown / not verifiable:**
- Tire, grip and mass models of NFSNL, Asphalt and CSR2 were not found. [gap]
- Pacejka formula and Burnout drift scoring: not sourced. [gap] https://en.wikipedia.org/wiki/Pacejka%27s_Magic_Formula
**Decision for MIDNIGHT SYNDICATE:**
- RigidBody3D with own four-ray raycast suspension, forces at each contact; not VehicleBody3D. [E] https://github.com/Dechode/Godot-AdvancedVehicle (MIT reference)
- Spring: 60-90 N/mm equivalent; damping ratio 0.6-0.8; ride height 0.12-0.20 m; force clamped to >= 0 and to 3-4x quarter mass. [E] anchored by the VehicleWheel3D guidance above
- Tire: slip-angle lateral force, peak at 6-10 deg; mu 1.0-1.3 asphalt, 0.6-0.7 wet or drift; friction circle for combined force; anti-roll k 0.5-2x stiffness; downforce 0.3-1.0 of real. [E]
- Run a wheel_friction_slip sweep on 4.7.2 (stable default 10.5 vs 4.2 guidance 1.0). Set Jolt in project settings on creation and record it. [S] https://docs.godotengine.org/en/4.2/classes/class_vehiclewheel3d.html + [E]
**Acceptance test:**
- Drop test and 3-bump test: settle under 1.0 s; oscillation under 2% after 2 bounces. Headless Godot log. [E target]
- Flat-track sweep at 100, 160, 250 km/h: no loss of ground contact; no tunneling. [E target]
## 2. Steering and traction
**Observed in references:**
- NFSNL: tap to steer; acceleration and braking automated; drift and nitro are swipes. [S] https://www.pocketgamer.com/need-for-speed-no-limits/review/
- Asphalt: three drive modes; TouchDrive handles acceleration and steering; a manual-control competitive event exists. [S] https://en.wikipedia.org/wiki/Asphalt_9:_Legends ; https://www.pocketgamer.com/articles/076788/r/
- Critic: tilt steering is awkward and causes wall hits and ruined drifts. CarX: tilt is best default; movable buttons. [S] https://www.pocketgamer.com/articles/076788/r/ ; https://traxion.gg/carx-street-review-ios-leads-the-way-for-carxs-move-to-open-world/
**Unknown / not verifiable:**
- NFSNL and Asphalt traction models: not found. [gap]
- Current CarX controller support (2022 review only). [gap] https://traxion.gg/carx-street-review-ios-leads-the-way-for-carxs-move-to-open-world/
**Decision for MIDNIGHT SYNDICATE:**
- Assist on by default (auto-throttle, steering assist) with a manual toggle. [S] https://www.pocketgamer.com/need-for-speed-no-limits/review/ + [E]
- Two steering modes minimum: tilt (dead zone 3-5 deg, heavy smoothing) and slider; sensitivity slider. Gamepad out of v1 unless tested. [E]
- Steering rate 3-6 rad/s; touch smoothing 0.1 s; max angle = base x (1 - 0.65 t), t = speed / v_max, v_max about 300 km/h. [E]
- Brake and nitro as separate movable touch buttons. [S] https://traxion.gg/carx-street-review-ios-leads-the-way-for-carxs-move-to-open-world/ + [E]
**Acceptance test:**
- Device: 10 laps per steering mode; tilt wall hits per lap no more than slider + 1 in build one. [E target]
- Touch-to-steer latency logged under one frame plus 50 ms at 60 fps. [E target]
## 3. Drift
**Observed in references:**
- NFSNL: a downward swipe starts a drift. [S] https://www.pocketgamer.com/need-for-speed-no-limits/review/
- CarX countersteer snaps the car straight at once; a reviewer found it odd. [S] https://www.thexboxhub.com/carx-street-review/
- NFSU2 drift mode on parkade tracks with nitrous banned. [S] https://en.wikipedia.org/wiki/Need_for_Speed:_Underground_2
**Unknown / not verifiable:**
- Asphalt 360-degree flat spin from brake double-tap: not in the cited article. [gap] https://www.pocketgamer.com/articles/076788/r/
- CarX drift physics numbers: developer claim only. [gap] https://store.steampowered.com/app/1114150/CarX_Street/
**Decision for MIDNIGHT SYNDICATE:**
- Rear lateral grip 0.3-0.5 in the drift window; front grip 0.9-1.0. Slip clamp 45-60 deg with extra yaw damping beyond it. [E]
- Counter-steer assist 0.2-0.5, applied gradually so the car does not snap straight (answers the CarX complaint). [E]
- Score = abs(slip) x speed factor x time. Bank on exit when slip under 15 deg and speed over 40 km/h; combo lost on wall hit or grip recovery over 5 s. [E]
- Drift charges nitro, scaled by duration and angle, capped. [E] https://afkgaming.com/gaming/general/asphalt-9-legends-guide-the-most-efficient-ways-to-use-nitro (snippet)
**Acceptance test:**
- Automated: at 45 deg slip, steering recovery returns car under 15 deg within 2 s. [E target]
- Device: at least 8 of 10 three-second holds per tester without unintended straightening. [E target]
## 4. Nitro
**Observed in references:**
- Asphalt: fills from drift, stunts and ramps; timed perfect tap at a blue mark for about 5 s; full-bar shockwave. [E] https://racinggames.gg/article/how-to-get-a-perfect-nitro-in-asphalt-9-legends (snippet); Shockwave was earlier called Nitro Pulse [S] https://en.wikipedia.org/wiki/Asphalt_9:_Legends
- NFSNL: swipe up fires nitro. [S] https://www.pocketgamer.com/need-for-speed-no-limits/review/
- NFSU2: nitrous refilled by style points; banned in drift and Street X. CSR2: nitro slider trades burst for power. [S] https://en.wikipedia.org/wiki/Need_for_Speed:_Underground_2 ; https://www.pocketgamer.com/csr-racing-2/how-to-tune-your-car-in-csr-racing-2-tires-nitro-and-final-drive
**Unknown / not verifiable:**
- Exact charge rates and burst durations of Asphalt and NFSNL. [gap]
- Perfect-timing window size. [E]
**Decision for MIDNIGHT SYNDICATE:**
- Burst: 4-8 m/s2 for 1.5-3 s; top speed +10-20%. FOV kick 8-12 deg over 0.2 s, return 0.6 s. [E]
- Charge from drift, near-miss and stunt score; cap 1.0; no charge while braking. [E]
- Per-mode nitro allowed flag (NFSU2 pattern); optional timed-hit layer with one readable window. [S] https://en.wikipedia.org/wiki/Need_for_Speed:_Underground_2 + [E]
**Acceptance test:**
- 500 m straight: nitro top speed 10-20% above baseline; burst ends in 1.5-3 s. [E target]
## 5. Chase camera
**Observed in references:**
- No chase-camera detail for NFSNL or Asphalt was found in any opened source. [gap]
- Eiserloh GDC 2016 covers camera math and trauma shake; summary confirms topic only. [S] https://gamedeveloper.com/programming/video-sprucing-up-cameras-with-math
**Unknown / not verifiable:**
- Shake formula (talk not read); camera rigs, base FOV, takedown cameras. [gap]
**Decision for MIDNIGHT SYNDICATE:**
- Critically damped spring arm, smooth time 0.15-0.3 s; look-ahead 0.3 s x velocity, clamp 4 m. [E]
- Dynamic FOV +0.04-0.08 deg per km/h above a threshold. [E]
- Trauma shake = trauma squared; decay 1.0-1.5/s; added on crash and nitro. Keep shake under the nitro kick for night readability. [E] (file 06 formula, unverified)
**Acceptance test:**
- Steady 200 km/h: camera-to-car offset error under 0.5 m, logged. [E target]
- 60 s drive at medium on device: frame-time spread under 2 ms; shake decays within 1 s. [E target]
## 6. Rival AI
**Observed in references:**
- Photon arcade sample: chase-the-rabbit target on a baked line; line points carry speed and difficulty. [S] https://doc.photonengine.com/quantum/v2/game-samples/arcade-racing/ai
- Pure rejected classic rubber banding; uses clamped skills and target offsets capped at 150 m per update (not re-checked). [S] https://gamedeveloper.com/design/the-pure-advantage-advanced-racing-game-ai
- NFSNL has ghost-based Rival Races. [S] https://en.wikipedia.org/wiki/Need_for_Speed:_No_Limits
**Unknown / not verifiable:**
- NFSNL and Asphalt AI and rubber banding: not verified. [gap]
- Asphalt Unite AI-balance complaints: aggregator snippet. [E] https://www.gamepressure.com/games/asphalt-legends-unite/z46a58
**Decision for MIDNIGHT SYNDICATE:**
- Racing line: baked Path3D with per-node speed; pure-pursuit look-ahead clamp(0.5 s x speed, 6, 30) m. [E] https://docs.godotengine.org/en/stable/classes/class_path3d.html (curve origin rule [S])
- Target speed min(sqrt(a_lat x R), v_max_ai), a_lat 7-9 m/s2; braking look-ahead 40-80 m; overtake side offset 2-4 m. [E]
- Rubber band = skill offsets only, capped per update; AI top speed +/-3-5% only when gap over 4 s; never boost the player. [S] Pure link above + [E]
**Acceptance test:**
- Headless: 1,000 races, 7 AI, 3 tracks; no AI speed change over 5% between updates. [E target]
- Code check: rubber-band system never writes player velocity (assert). [E]
## 7. Police pursuit
**Observed in references:**
- Most Wanted (2005): heat adds roadblocks, spikes, helicopters and stronger units; backup delayed; cooldown has no published duration. [S] https://en.wikipedia.org/wiki/Need_for_Speed:_Most_Wanted_(2005_video_game)
- NFSNL police jump over ramps instead of stopping; Interceptor mode added Jan 23, 2023. [S] https://www.pocketgamer.com/need-for-speed-no-limits/review/ ; https://en.wikipedia.org/wiki/Need_for_Speed:_No_Limits
- EA endless-chase complaints concern Unbound, not NFSNL. [E] https://forums.ea.com/discussions/need-for-speed-unbound-discussion-en/cops/9403905 (snippet)
**Unknown / not verifiable:**
- Cooldown durations and 2005 heat-tier numbers. [gap]
**Decision for MIDNIGHT SYNDICATE:**
- States: Patrol, Suspect (3 s sight), Pursue (150 m), Intercept (PIT/ram), Roadblock (heat 3+), Escape (10-15 s no sight, cooldown 20-40 s), Busted. [E]
- Bust meter 0-100; fill 10-25/s when surrounded; 5 heat tiers at 20/40/60/80. [E]
- PIT only side-on below 80 km/h; ram above 30 km/h relative. Ramps stop or route units; no pass-through. Pursuit capped at 90 s. [E]
**Acceptance test:**
- Scripted: pursuit ends within 90 s in 19 of 20 runs. [E target]
- Physics log: no unit passes through a ramp mesh in 20 runs. [E target]
## 8. Race progression
**Observed in references:**
- NFSU2: five stages, world map, 11 sponsor races per stage (3 run); races found by driving; stage swaps locations. [S] https://en.wikipedia.org/wiki/Need_for_Speed:_Underground_2
- NFSU2 modes: circuit (up to 4 cars), sprint, drag, drift, Street X, URL tournament (up to 6 cars), outruns, photo events. [S] https://en.wikipedia.org/wiki/Need_for_Speed:_Underground_2
- NFSNL races finish under a minute per one review; campaign, car series, rival races, time-limited loaner events. [S] https://www.pocketgamer.com/need-for-speed-no-limits/review/ ; https://en.wikipedia.org/wiki/Need_for_Speed:_No_Limits
**Unknown / not verifiable:**
- NFSNL and Asphalt reward curves and unlock pacing. [gap]
**Decision for MIDNIGHT SYNDICATE:**
- One race framework with rule flags: lap count, car cap, nitro, manual shift, route type. [E] from NFSU2 modes [S]
- Races 60-120 s with a visible reward. [E] file 01 finding 5
- Fast travel and skip-to-race from stage 1 (answers the NFSU2 complaint [S]). [E]
- Races are world markers found by driving, plus a map. Stages swap the location set. [E]
**Acceptance test:**
- First race within 60 s of first launch on device; median race 60-120 s in playtest. [E target]
## 9. Car modification
**Observed in references:**
- NFSNL: most cars take wheels, body kits, paint, wraps and performance parts; event-only cars cannot be visually customized. [S] https://en.wikipedia.org/wiki/Need_for_Speed:_No_Limits
- NFSU2: visual and performance customization separate; only spoilers and hoods affect downforce; dyno graphs. [S] https://en.wikipedia.org/wiki/Need_for_Speed:_Underground_2
- CSR2: full interiors and real paint options were the biggest content cost; tuning sliders with live stat deltas. [S] https://www.pocketgamer.biz/the-making-of-csr-racing-2/ ; https://www.pocketgamer.com/csr-racing-2/how-to-tune-your-car-in-csr-racing-2-tires-nitro-and-final-drive
**Unknown / not verifiable:**
- Asphalt customization depth. [gap]
**Decision for MIDNIGHT SYNDICATE:**
- Cosmetic data separate from handling data; cosmetics never change physics. [E]
- Three tuning sliders with live delta and a dyno graph (power, torque). [S] pattern above + [E]
- Fewer, higher-quality cars: one fully built car per tier. [S] https://www.pocketgamer.biz/the-making-of-csr-racing-2/ + [E]
- Paint as a shader palette, not a texture per paint. [E]
**Acceptance test:**
- Unit test: physics output identical before and after any cosmetic change. [E]
- Stat delta shown within one frame; dyno redraw under 100 ms. [E target]
## 10. Garage experience
**Observed in references:**
- CSR2 garage visuals credited to console-style shader layers and a CAD pipeline, from search summaries only. [E] https://gamesbeat.com/?p=102887 ; https://www.redbull.com/us-en/csr2-first-look-interview
- NFSU2 dyno screen is part of the tuning flow. [S] https://en.wikipedia.org/wiki/Need_for_Speed:_Underground_2
**Unknown / not verifiable:**
- Garage camera rig, light setup and polygon counts for any reference. [gap]
**Decision for MIDNIGHT SYNDICATE:**
- One hero car on a turntable; key light, rim light, wet-floor reflection from decals and probes. [E]
- Tuning reachable in two taps from the garage. [E]
- Garage budget: at most 8 omni + 8 spot lights and 8 probes per mesh. [S] https://docs.godotengine.org/en/stable/tutorials/3d/lights_and_shadows.html + [E]
**Acceptance test:**
- Garage holds target frame rate on lowest supported device at Low (Godot profiler). [E target]
- Click-count test: tuning reachable in 2 taps. [E target]
## 11. Graphics and lighting
**Observed in references:**
- CSR2 2016: physically based shading, car paint simulation, static image-based lighting, weak-device workarounds. [S] https://gdcvault.com/play/1022998/Delivering-Console-Car-Visuals-on
- Mobile renderer lacks SSR, SSAO, SDFGI, VoxelGI, volumetric fog, TAA and FSR2; decals and clearcoat are available. [S] https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html ; https://docs.godotengine.org/en/stable/tutorials/3d/standard_material_3d.html
- Mobile caps: 8 omni + 8 spot per mesh; probes 8 per mesh. NFSU2 night, wet pavement and neon as the cited look (weak). [S] https://docs.godotengine.org/en/stable/tutorials/3d/lights_and_shadows.html ; [E] https://games.gg/need-for-speed-underground-2/ (snippet)
**Unknown / not verifiable:**
- glTF clearcoat, emissive strength and texture transform support: not stated. [gap] https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html
- Mobile decal limit; whether NFSU2 wet-road look was texture masking. [gap]
**Decision for MIDNIGHT SYNDICATE:**
- Mobile renderer only; wet road from decals, probes and authored roughness. Night look from emissive neon, one sun, few shadowed local lights. [E]
- Build check fails above 8 + 8 lights and 8 probes per mesh. [E]
- Test clearcoat, emissive and texture transform with one real Blender export before locking materials. [E]
**Acceptance test:**
- Build check counts lights and probes per mesh. [E]
- 60 fps target at Medium on lowest supported device; auto-drop to Low if missed. [E target]
## 12. UI/UX
**Observed in references:**
- NFSNL: tap to steer, swipe down to drift, swipe up for nitro. [S] https://www.pocketgamer.com/need-for-speed-no-limits/review/
- CSR2 drag gauge: two colors mark shift timing; nitro not used at start. [S] https://www.pocketgamer.com/csr-racing-2/how-to-accelerate-and-change-gears-optimally-in-csr-racing-2
- NFSU2 critics: comic-strip cutscenes, slang, no fast travel. [S] https://en.wikipedia.org/wiki/Need_for_Speed:_Underground_2
**Unknown / not verifiable:**
- NFSNL, Asphalt and NFSU2 HUD layouts beyond summaries. [gap]
**Decision for MIDNIGHT SYNDICATE:**
- One-thumb start and shift gauge: two color zones, clear do-not-shift cue. [E] (CSR2 pattern)
- Story as short HUD cards; no comic cutscenes; skip on every cutscene. [E]
- Movable touch buttons, saved per device; HUD inside safe areas. [S] https://traxion.gg/carx-street-review-ios-leads-the-way-for-carxs-move-to-open-world/ + [E]
**Acceptance test:**
- Recording on smallest and largest supported iPhone: all controls in thumb reach. [E target]
- At least 8 of 10 test starts land in green after one tutorial run. [E target]
## 13. Monetization
**Observed in references:**
- CSR2 (2016): Gold $2.99 (300) to $99.99 (16,500); gacha Keys (silver 50 for $2.99 random car; gold 10 for $9.99); some cars up to $30; fuel 10 races, refill 20 Gold. [S] https://www.pocketgamer.biz/how-does-csr-racing-2-monetise/
- CarX: IAP $0.99-$14.99; Premium 7 days $1.99; refuel by ad or credits. [S] https://apps.apple.com/app/id1458863319 ; https://traxion.gg/carx-street-review-ios-leads-the-way-for-carxs-move-to-open-world/
- Asphalt blueprint grinding and energy refills criticized; NFSNL unlock-by-purchase criticized. [S] https://en.wikipedia.org/wiki/Asphalt_9:_Legends ; https://en.wikipedia.org/wiki/Need_for_Speed:_No_Limits
- Apple 3.1.1: paid random items need disclosed odds; IAP currency may not expire. [S] https://developer.apple.com/app-store/review/guidelines/
- Zynga random-price test apology. [E] https://www.pocketgamer.biz/zynga-csr2-random-prices/ (snippet)
**Unknown / not verifiable:**
- Current CSR2 monetization (2016 only); Asphalt battle pass detail; Apple section 5.3 (truncated). [gap]
- Price point for this game: not set by this research. [gap]
**Decision for MIDNIGHT SYNDICATE:**
- Premium, offline; no energy, fuel or timer gates; no gacha; no random paid items; no per-player prices. [E]
- Optional non-expiring cosmetic IAP with restore, or one upfront price. No ads in v1; if added, rewarded and optional. [E]
**Acceptance test:**
- Code audit: no energy, fuel or timer gate in progression. [E]
- Restore-purchase test passes on a TestFlight build. [E]
## 14. Mobile optimization
**Observed in references:**
- CarX: heat and battery drain on iPhone; frame hitches on iPhone 13 mini; needs 3 GB RAM and iOS 15+. [S] https://traxion.gg/carx-street-review-ios-leads-the-way-for-carxs-move-to-open-world/ ; https://apps.apple.com/app/id1458863319
- Godot iOS export needs macOS with Xcode; Simulator is Compatibility only. [S] https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_ios.html
- CI costs: GitHub macOS $0.062/min vs Linux $0.006/min; Codemagic 500 Mac min/month free; Git LFS free 10 GiB. [S] https://docs.github.com/en/billing/concepts/product-billing/github-actions ; https://codemagic.io/pricing/ ; https://docs.github.com/en/billing/managing-billing-for-git-large-file-storage/about-billing-for-git-large-file-storage
**Unknown / not verifiable:**
- iOS minimum version and device tiers: not in 4.7 docs. [gap] https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_ios.html
- Whether Godot writes PrivacyInfo.xcprivacy itself. [gap] https://docs.godotengine.org/en/stable/classes/class_editorexportplatformios.html
**Decision for MIDNIGHT SYNDICATE:**
- Frame cap 30 or 60 (60 on High, 30 on Low); thermal-aware drop of render scale and particles one step at a time; render scale 0.6-1.0 by preset. [E]
- Device floor 3 GB RAM; memory budget about 1.5 GB. [E]
- Owner enrolls in Apple Developer Program ($99/yr). Per-build Mac step (GitHub macOS for public repo, or Codemagic); keep LFS out of CI. [S] https://developer.apple.com/programs/ + [E]
**Acceptance test:**
- 15-minute soak at target preset: under 1% frames over 50 ms; battery and temperature logged. [E target]
- Oldest supported device holds 30 fps on Low. [E target]
## 15. User complaints
**Observed in references:**
- Asphalt: blueprint grinding and energy refills most repeated; tilt causes wall hits and ruined drifts. [S] https://en.wikipedia.org/wiki/Asphalt_9:_Legends ; https://www.pocketgamer.com/articles/076788/r/
- CarX: 19-item complaint tally (reader count): crashes or black screens about 5, login about 4, purchases not delivered about 3, install or compatibility about 3. [S] https://www.sikayetvar.com/en/carx-street-us
- CarX: underpowered by club 2 and must grind or spend. [S] https://traxion.gg/carx-street-review-ios-leads-the-way-for-carxs-move-to-open-world/
- NFSU2 critics: no fast travel, product placement, comic cutscenes, no police. [S] https://en.wikipedia.org/wiki/Need_for_Speed:_Underground_2
- Asphalt single user: 35 blueprints missing after purchase. [E] https://www.sikayetvar.com/en/gameloft-us/asphalt-legends-purchase-missing-35-blueprints (snippet)
**Unknown / not verifiable:**
- Reddit and Discord sentiment: not reachable. [gap]
**Decision for MIDNIGHT SYNDICATE (complaint to rule):**
- No energy or fuel gate; no random prices or gacha. [E]
- Purchase delivery and restore tested before release; crash and compatibility matrix on minimum device class. [E]
- Countersteer tuned to catch slides; no grind wall, next class target shown before each race. [E]
- No fast-travel block; short cutscenes; no product placement. [E]
**Acceptance test:**
- Pre-release checklist: each rule above maps to a test that passes on device. [E]
- Unlock-curve simulation: time to each car class stays in target band. [E target]
## Renderer feature decisions for iOS (from file 04)
- Target Mobile renderer; Forward+ features off. [S] https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html
- Disabled: SSR, SSAO, SDFGI, VoxelGI, volumetric fog, TAA, FSR2, subsurface scattering. [S] https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html ; https://docs.godotengine.org/en/stable/tutorials/3d/standard_material_3d.html
- Lights: cap 8 omni + 8 spot per mesh; 256 + 256 visible; shadowed lights in view 4 / 8 / 16 by preset. [S] https://docs.godotengine.org/en/stable/tutorials/3d/lights_and_shadows.html + [E] presets
- Shadows: one sun; 2 PSSM splits Low, 4 Medium and High; soft filter. [S] https://docs.godotengine.org/en/stable/tutorials/3d/lights_and_shadows.html + [E]
- Probes: 1-4 per mesh by preset, hard cap 8. [S] https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html + [E]
- Occlusion culling: bake buildings; manual occluders for MultiMesh (excluded from baking). [S] https://docs.godotengine.org/en/stable/tutorials/3d/occlusion_culling.html
- AA: SMAA Low and Medium; MSAA 2x High; both available on Mobile. [S] https://godotengine.org/releases/4.5/ + [E]
- Textures: ETC2 default; ASTC via High Quality on Medium and High; max 2048 unless 4096 tested. [S] https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_images.html + [E]
- Shader baker at export; physics interpolation on; HDR output off in v1. [S] https://godotengine.org/releases/4.5/ ; https://godotengine.org/releases/4.4/ ; https://godotengine.org/releases/4.7/ + [E]
- Jolt setting confirmed on project creation (docs conflict). [S] https://docs.godotengine.org/en/stable/tutorials/physics/using_jolt_physics.html
- Unknown, verify on device: iOS minimum version and devices [gap]; Metal default status [gap]; Mobile decal limit [gap]. Real-device testing is required. [S] https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_ios.html
## Asset sourcing decisions (from file 05)
- Shipped assets CC0 only: Poly Haven and ambientCG need no credit. [S] https://polyhaven.com/license ; https://docs.ambientcg.com/license/
- Script ambientCG v3, not v2 (v2 no longer updated). [S] https://docs.ambientcg.com/api/v2/
- Poly Haven API: no key; unique User-Agent header. [S] https://polyhaven.com/our-api
- Shipped cars: Kenney Car Kit or Quaternius Cars pack (CC0). [S] https://kenney.nl/assets/car-kit ; https://quaternius.com/packs/cars.html
- Sketchfab: per model; only CC0 or CC-BY with credit recorded. [S] https://sketchfab.com/licenses (types only) + [E]
- OpenGameArt: not verifiable (403); avoid until each page is checked. [gap] https://opengameart.org/
- Freesound: CC0 only in the paid build; no NC or Sampling+. [S] https://freesound.org/help/faq/
- Local image-to-3D for blockouts only: TripoSR (MIT, about 6 GB) or InstantMesh (Apache-2.0). TRELLIS (16 GB) does not fit the 8 GB card. [S] https://github.com/VAST-AI-Research/TripoSR ; https://github.com/TencentARC/InstantMesh/blob/main/LICENSE ; https://github.com/microsoft/TRELLIS
- Hunyuan3D-2 excluded (license bars EU, UK, South Korea). SF3D only under $1M revenue. [S] https://github.com/Tencent-Hunyuan/Hunyuan3D-2/blob/main/LICENSE ; https://huggingface.co/stabilityai/stable-fast-3d
- Generated car meshes: blockout and proportion reference only, not final assets. [E] https://arxiv.org/pdf/2606.25300 (snippet)
- Asphalt: Poly Haven asphalt_02 (dry, 8K) and ambientCG Asphalt031 (CC0); wet look from in-engine roughness and puddle masks. [S] https://polyhaven.com/a/asphalt_02 ; https://ambientcg.com/view?id=Asphalt031 + [E]
- HDRI canary_wharf exists; time of day unverified. Other slugs unverified. [gap] https://polyhaven.com/a/canary_wharf
- Keep an attribution file anyway. [E]
