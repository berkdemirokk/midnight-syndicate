# Progress

## Session 1 — 2026-11-24
Branch `feature/vertical-slice` (local only; no remote yet).

### Done, with evidence
- Environment: Godot 4.7.2 (official, SHA512 verified, outside the repo), Blender 5.3, Git, gh,
  RTX 5060 Ti. No macOS (iOS build blocked, see BLOCKERS.md).
- Research (public sources, verified): docs/research/01-07, REA_ANALYSIS.md,
  COMPETITOR_ANALYSIS.md, replica/recon.md + features.csv. REA binary tooling deliberately not run
  on competitor games (clean-room).
- Architecture + contracts + headless test runner. 110 tests pass (TEST_RESULTS.md).
- Hero car "Noctra Sable R" (original): body built from lead-authored surface data
  (docs/art/CAR_01_BODY_SURFACE_SPEC.md), LOD0 86k / LOD1 27k / LOD2 6.8k tris, 15 materials,
  generated textures, Cycles renders `assets_src/vehicles/noctra_sable/final/renders/`, in engine
  with clearcoat paint and LOD switching (`evidence/screens/car_studio/`).
  Lead score: geometry 6, materials 6, wheels 7, details 5. Two independent reviews: 4.5 then 6.
- City "Neon Wharf Loop": road (2.2 km), 20 building GLBs with LODs, 43 props, layout (1127
  instances, 178 lights, 37 probes); in engine with material library, MultiMesh props, budgeted
  lights, probes, occluders, track data (`evidence/screens/city_districts/`).
  Neon Strip in engine reads close to the target; downtown towers fixed; underpass, waterfront,
  downtown street level still weak (second look pass running).
- Gameplay: raycast arcade car, drift, nitro, chase camera, touch/keyboard/controller input, AI,
  race manager, HUD, menus (TR/EN), pause, results, save/load, settings presets with dynamic
  resolution, garage with paint/rims/upgrades (`evidence/screens/garage/`).
- FX: wet asphalt + planar reflection, rain, nitro flame, tyre smoke, sparks, speed lines,
  headlights.

### Commits
401e9dc, b1bf219, f48a621, 6b73228, bb6bb04, 80b60f7, 88c5be7, 081f20c, ce807a8, 542671f,
c0c065d (see `git log`).

### Not done / open
- Visual quality gate not passed yet (needs the second look pass and real race captures).
- 6-8 car races on the city track get stuck (root-cause work running).
- No performance numbers for the city yet; none at all for a phone.
- Police pursuit, traffic, career, audio: later milestones (ROADMAP.md).
- No GitHub remote, CI never executed, no export templates, no Windows .exe, no iOS build.

### Later the same session (rounds 2-4 of the quality gate)
- Test runner hardening: crashed tests fail, leaked nodes are freed (root cause of the
  order-dependent failures). 124 tests pass.
- Public repo https://github.com/berkdemirokk/midnight-syndicate (owner decision); cloud CI green
  (logic tests + asset validation on Linux); tools/ci_local.ps1 runs the same locally.
- Engine city look fixed by the lead (glass windows, impostors, paint, ambient, reflections, sign
  overlaps); wet reflections and a car-only fill light in the real race.
- Real 2-lap race with the real car and track, earned nitro shot (flames + speed lines), rewards.
- Per-preset draw-call budgets met on the dev PC (Low 253 / Medium 255 / High 458 vs 250/350/500).
- Quality gate recorded with two review stages in GRAPHICS_BENCHMARK.md: lead 6.25 average,
  not passed for commercial quality.
- Commits up to 53a5fad.

### Session 2 — 2026-11-25 (gate rounds 5-6)
- Pack AI: track-frame car avoidance; lead fix of a recovery deadlock (one car stuck 110 times,
  race never finished). Canonical race tests strict; nitro/grid sweep checks for stuck loops
  (pack contacts are chaotic in Jolt; see docs/design/AI_AND_RACE.md).
- Camera polish (corner look-in, roll, nitro kick, ceiling pull-in, finish orbit).
- Lead rebuilt the car canopy (narrow greenhouse, raked one-piece side window, A-pillar), glass,
  nitro flame, HUD scrim, speed lines.
- Gate round 6: lead average 6.5, independent 5.75 / 5.9. Not passed. 138 tests pass.
- Commits up to ddce0ba.

### Session 2, later — 2026-11-25 (gate rounds 7-9)
- Round 7: race replay with trackside cameras, grid intro, rooftops. Round 8: Arden Civic traffic
  sedan (7 materials, 7000/2500/800 tris) parked along the lap, 115 street dressing props.
- Textures: mipmaps and VRAM compression on every 3D texture, anisotropic road.
- Captures run off-screen without focus (owner complaint about Godot windows popping up).
- Round 9: wet facades, skyline tower silhouettes, gradient night sky, downtown sidewalks and
  shelters, harbour stacks/crane in view, evidence races in candy red.
- PerfProbe fixed to report peak counters: it exposed High over budget on the grid (483k
  primitives), results (646 draws) and finish orbit (577k), and Low races at 280-303 draws (250).
- Gate round 9: lead 6.4, art 6.0, tech 5.7. Not passed. 146 tests pass.
- Round 10 (lighting and rain): per-mesh light budget fixed by splitting over-budget meshes
  (lights dropped 64 -> 4, tunnel lit), downtown/overpass street lamps, car rim light, rain rewrite
  (shelter, road-height ripples, depth falloff, speed slant). Gate: lead 6.4, art 5.75, tech 5.6.
  149 tests pass. High race views at 501 draws (budget 500), Low 276 (250): budgets next.

## Session 3 — 2026-11-25/26 (product pass)
Parallel agents in isolated worktrees, each reviewed independently, merged by the lead.
- Budgets: per-category draw breakdown, HUD/results batching, mirror diet, LOD tuning. All
  race and preset views on City 01 within budget (High race 377-430 draws / <=435k primitives,
  Medium 260, Low 249); replay orbit 469k primitives is the one view over (fix in progress).
- Audio: 25 original procedurally synthesised sounds (engine layers, tyres, nitro, impacts, UI,
  race and menu music) wired into cars, countdown, finish, menus and pause; volume buses.
- Career: 10 events (6 Arden Bay + 4 World Tour Istanbul), stars, unlocks, next-event button.
- Istanbul: generic track pipeline; Maslak-Levent (towers, viaduct, underpass) and Bosphorus
  coast road (yali, cumba rows, cobbled tram street, piers, bridge/dome skyline cards); 5-AI
  races finish on both; original Turkish sign names, no real brands.
- Visuals: cars seated on their suspension (bodies floated 0.49 m above the wheels before),
  showroom garage (glossy mirror floor, three-point light), drift smoke + skid marks, car glass
  edges and arch liners, app icon and boot splash.
- Build: Windows export (243 MB exe + pck). The exe is blocked by Smart App Control on the dev PC
  (unsigned template, BLOCKERS B9); the exported pck runs (menu and race, no errors).
- Captures and tests are silent and off-screen. 199+ tests pass.
- Commits up to 6037fd2 (see git log).

## Session 4 — 2026-11-26 (Ortakoy graphics rescue)
Short status lives in `evidence/PROGRESS.md` (rescue package format); this is the session record.
- Scope narrowed by the owner to ONE scene: the Ortakoy coast on `istanbul_bogaz`. Benchmark scenario
  `ortakoy_benchmark` (day, dusk, night; hero, car34, street, mosque, gameplay). All shots are harness captures.
- Cars: six CC BY 4.0 models by vinish.dev (original designs, no makes) through `assets_src/pipeline/prepare_vehicle.py`
  (material merge to the engine names, three LODs, source corner normals kept, Turkish-layout plates).
  Starter is Noctra Tayfun; rivals are drawn from the licensed cars. Credits in settings; licence evidence in `licenses/`.
- Landmark and far scenery: mosque (two detail passes, sandstone and marble from Poly Haven CC0, floodlit at night),
  3D bridge, far shore with lights, ferry, moon sky. Event dressing: barriers with banners, flags, cafe terraces.
- Houses: Istanbul kit detail pass (casings, shutters, bays, balconies), baked per-vertex AO (`assets_src/pipeline/bake_vertex_ao.py`).
- Look: day sun and sky fill, blue-hour preset, window rooms and greyed glass reflection, asphalt rubber and oil,
  tyre spray, underglow, lens drops, HUD restyle with live data, closer chase camera.
- Budgets: mirror pass skips building LOD0; Low preset trims props, signs, traffic. Peaks on the benchmark: see evidence/evidence.json.
- Tests: 309, 0 failed at b4cbbf3 (evidence/test.log). Asset manifest 534 records, 0 failing.
- Rescue package (MIDNIGHT_RESCUE/) adopted: gates, tools, `third_party_assets.json`, `evidence/evidence.json` (checker passes).
- Not done: gate 90 (lead score about 76), house fronts still simple, trees, spectators, rain beads; iOS build (secrets missing),
  iPhone test, signed Windows exe. No push since c191d50 (rescue package rule); main untouched.
- Commits: 305e457 .. f284ce7 on feature/vertical-slice (see git log).

## Session 5 — night of 2026-11-26 (licensed environment, playable by morning)
- Overnight workflow, four Haiku builders in isolated worktrees, each followed by an independent Haiku review and one fix
  pass. None of the four reviews approved its part as final; the lead merged them, looked at the day, dusk and night
  captures and fixed what was visibly broken.
- Street fronts (`game/world/street_fronts/`): the land-side kit houses in the first 900 m are replaced by licensed
  CC BY 4.0 shop houses and a few mansions (vinish.dev) with Turkish signs, lit glass and pavement light pools at night.
  Lead fix: LOD1 and the mirror copy now drop loose parts by size (`cull_islands` in `assets_src/pipeline/prepare_static.py`)
  instead of a collapse, which had left stretched triangles across the facades (an independent Haiku review of the lead's change
  found the mansions still collapsing and the night spectators black: both fixed, spectators get a small warm fill); florist pots and brackets removed; full
  models to 30 m. Triangle caps in `test_street_fronts.gd` set by the lead to the shipped meshes (shop 6000 / 1300 / 460,
  mansion 19000 / 3300 / 1400); the frame budget decides.
- Trees: licensed plane, cypress, magnolia (as the judas tree) and a street tree with matching impostors.
- Spectators: eight licensed figures as MultiMesh behind the barriers (LOD0 to 45 m, LOD1 to 160 m); licensed ferry.
- Mosque pass 3: traceried windows, cornice, buttressed drum, minaret balconies, portico, quay balustrade; original budgets kept.
- Lead, same night: rain beads on wet paint, save version 2 (old saves move to the Noctra Tayfun), always-open
  "Ortakoy Night" event first in the career list, `Oyunu_Baslat.bat` start script.
- Evidence: 320 tests, 0 failed (evidence/test.log). Benchmark peak 422 draws / 421256 primitives (budget 500 / 450000),
  night gameplay 368 fps on the dev PC (RTX 5060 Ti; not an iPhone number). Manifest 609 records, 0 failing; 30 third-party
  sources recorded; credits file has 28 lines. Pack rebuilt (`build/windows/midnight_syndicate.pck`, 250 MB) and smoke-run.
- Known deviations from the builders' briefs, accepted by the lead for now: shop LOD0 range 30 m (brief 55 m), mansion
  chance 8 %, florist and corner-shop LOD1 without glass textures, crowd figures in an idle pose with no faces, plane trees rare.
- Not done: gate 90 (lead score about 81), Istanbul-style upper floors, sea wall and kerb, posed spectators; iOS build
  (secrets missing), iPhone test, signed Windows exe. No push since c191d50; main untouched.
- Commits: e76c935, 4a77537, 64a14bb, 2159371, 60cab60, bdf3c11, 9630600, 4e20f33, 286467f, 8041f78 and the evidence commit after it.

## Session 6 — night of 2026-11-26 to 27 (photo-texture pipeline)
- Method change that finally moved the look: straight-on pictures made with ChatGPT image generation (owner's Plus
  account, text prompts only, no reference image, no text or logos) are mapped on very simple geometry, and the night
  picture of the same thing is the glow map. Notes for sessions: `docs/art/PHOTO_TEXTURE_PIPELINE.md`. Records:
  `ASSET_MANIFEST.json` source `generated:ai`, sources kept in `assets_src/ai_generated/chatgpt/`.
- Lead: `game/world/street_fronts/photo_fronts.gd` + `photo_facade.gdshader`. Photo rows replace the first-row kit
  buildings on all three tracks: Bosphorus (two Istanbul row-house sets, 157 rows / 557 houses, both sides, whole lap),
  Maslak and Neon Wharf (modern, neon-street, market and tower sets). One merged mesh a row, about 20 triangles a house.
  Mosque hall walls as photo quads with a floodlit night glow map (`landmarks.gd`).
- Four parallel Haiku sessions in their own worktrees, merged by the lead: garage as a photo-textured workshop, far shore
  as a photo band, street trees as photo cards with lit night crowns, printed sponsor boards and photo spectator cards.
- Disk: 28 old worktrees removed with the owner's yes (45 GB), pip and stale temp caches purged.
- Evidence and numbers: see `evidence/evidence.json` and `evidence/PROGRESS.md` (final check of this session).
- Not done: cars are still the licensed stylised models (no real makes allowed), day lighting has no GI, no iPhone test,
  no iOS build (secrets missing), no push since c191d50, main untouched. The owner's target pictures are AI concepts with
  real-brand cars; the game is closer to them but is not that image.

## Session 6b — 2026-11-27 morning (reflections, relief, cars, first TestFlight upload)
- Paint: second pass on the car paint mirrors a street panorama (`car_reflection.gdshader`, night 0.55 / sunset 0.3 /
  day 0.16). Facades and mosque walls: normal maps derived from the pictures (`build_relief.py`).
- Cars (Haiku sessions, merged): area-weighted paint normals on LOD0 with panel gaps kept sharp, textured tail lights.
  Day: ground bounce fill (`day_bounce.gd`). Far shore band fades out at its ends.
- iOS: secrets set by the owner. Workflow fixed over four check runs (archive unsigned, export step signs).
  `ios-check-4` green (run 45949516766). `ios-release-1` (commit 0428c35, run 45963571142): "Upload succeeded",
  the build is in App Store Connect for TestFlight. Warning only: built with the iOS 26.5 SDK, iOS 27 SDK needed from April 2027.
- Evidence: 333 tests, 0 failed. Bosphorus peak 400 draws / 443146 primitives, Neon Wharf night 499 / 378534
  (budget 500 / 450000: both at the limit). Night 188 fps on the dev PC, measured while other GPU jobs ran (not an iPhone number).
- Not done: never run on an iPhone (no fps, heat or touch numbers), so not "App Store ready". Cars are still stylised
  licensed low-poly models, no baked GI; the owner's target pictures are not matched one to one. Lead gate about 88 (target 90).
  main untouched. Six merged session worktrees still on disk.
- Commits: bf70f98, 110c71e, 2acf183, b72fb63, 055bd6b, 78a2f75, 6571a6d, 673526c, 8c8d888, c6562f2, 0b4a523, 0428c35.

## Session 7 — 2026-11-27 afternoon (why the cars looked cheap, and the fix)
- Owner: "çok dandik hala arabalar", "sadece fable 5.2 kullan", "kalite acil artsın". Work done by the lead (Fable) alone;
  two review workflows with Fable agents. No Haiku sessions.
- Root cause found: a licensed source model has about 60 materials; `prepare_vehicle.py` merged them into the 14 engine
  materials as flat colours (white lamp discs, grey grille boxes, one-grey cabins, flat rims). The triangle count was never
  the problem (LOD0 about 89000).
- Fix, all six licensed cars: the source part colours and a baked ambient-occlusion shade travel as vertex colours
  (COLOR_0), used as albedo by M_Trim, M_Chrome, M_Interior, M_BrakeDisc, M_Caliper and as a shade under the rim colour.
  Projector and mirror glass are chrome parts at LOD0, the lens cover is clear (alpha 0.1). Same surfaces and draw calls.
  Details: `docs/design/CAR_INTEGRATION.md`, last section. New test `test_part_colours_reach_the_right_materials`.
- Garage: the paint mirrors a workshop panorama (generated picture, floor half dimmed), not on the Low preset; the key
  light uses one shadow map instead of four cascades. Garage screen (impeccable critique, lead in-thread): stats on a
  backing panel, RACE as the one filled button, touch wording.
- Earlier the same day: tyre picture on every tyre (wheel-local projection), quilted interior for the project-made cars,
  night street panoramas for Maslak and Neon Wharf in the paint, rain beads 0.4 -> 0.2, rim metallic 0.8 -> 0.5,
  car names (Noctra Cyclon, Velmar Strix / Strix S, Velmar Fulmen; ids and paths unchanged).
- Independent review (workflow, three Fable reviewers, each finding checked by a second agent): six findings confirmed and
  fixed: far-LOD metals drawn as light plastic (rivals switch to LOD1 at 6 m), the Meridian mesh grille, rim shade
  inverted on black-spoke wheels, the garage pass cost and its missing preset gate, the lens change reaching the
  project-made cars. A second workflow (two Fable checkers) measured the fixes in the built files: all six hold. It
  reported five smaller defects, also fixed: far-LOD rim shade smeared by the decimation (now one mean shade a wheel),
  the garage shadow reach (40 m -> 18 m), the panorama reloaded on every car switch, no test for the garage pass
  (added: `test_paint_mirrors_the_workshop_except_on_low`), doc sentences without a file behind them.
- Found by that new test: the garage showed a raw key for three car classes (sport, super, hyper had no label). Fixed.
- Evidence (dev PC, RTX 5060 Ti, High preset; not iPhone numbers): 335 tests, 0 failed. Bosphorus peak 399 draw calls /
  443219 primitives, Maslak night 396 / 307289, Neon Wharf night 481 / 373547 (budget 500 / 450000). Garage up to 304 /
  390886. Night gameplay 340 fps. Manifest 653 records, 0 failing. Studio shots of all ten cars re-captured.
- Not done: the five project-made player cars (Noctra Sable R, Velmar Strix S, Noctra Vela, Arden Bruiser, Kestrel GT)
  and the traffic cars are still the crude procedural models; licensed replacements of the same quality exist at the
  same source (CC BY 4.0, about 3.7 MB each) and wait for the owner's yes to download. Rear reflectors and the Havoc
  mirror indicators are colourless glass (older than this session). Found, not fixed: every licensed car GLB embeds the
  tail-light atlas, so Godot extracts it 18 times (55 MB of PNG beside the GLBs, untracked, and as many textures in
  the pack); one shared texture set by `car_materials.gd` would do. No baked GI. The TestFlight build (ios-release-1,
  commit 0428c35) has none of today's work. Never run on an iPhone by the lead: the owner said "Denedim" and has not
  reported what they saw. The owner's target (their concept pictures, "Need for Speed'i geçebilmemiz lazım") is not reached.
- Commits: 83b14f3, f83a96f, b57967c, 1b260e8, 3e25639 and the commit that carries this entry.

## Session 8 — 2026-11-27 evening (the last five project-made cars replaced)
- Owner's yes ("tamam yap") to download five models: "Track Day Coupe", "Drift Sedan", "Rally Hatchback",
  "Supercharged Street Machine", "Electric Super GT" (vinish.dev, CC BY 4.0, 18.6 MB in all, no login). They replace
  the project-made models of Noctra Sable R, Velmar Strix S, Noctra Vela, Arden Bruiser and Kestrel GT in place: same
  ids, scenes, saves and prices. All eleven shop cars are licensed models now and all eleven race as rivals.
- Pipeline: `assets_src/pipeline/rebuild_vehicles.py` (one command rebuilds every car and refreshes the manifest),
  five new `vehicle_configs`, per-car decimation to the 90000 / 28000 / 7000 caps.
- One shared tail-light atlas: the GLBs no longer embed it and `car_materials.gd` sets it. 236 extracted texture files
  left the repo (the atlas alone was extracted 18 times, 55 MB). Rear reflectors and amber indicators are coloured
  parts now (they were colourless glass).
- Specs follow the new models (wheelbase, tracks, radii, body size); performance values unchanged. The Sable keeps
  its gearing through a final drive of 3.2457 for the larger rear wheel (the gear test caught the drift).
- Tests: per-car tests point at the new models; the five joined `test_car_licensed.gd`. 335 tests, 0 failed.
- Evidence (dev PC, RTX 5060 Ti, High; not iPhone numbers): Bosphorus peak 408 draw calls / 443576 primitives, Maslak
  night 349 / 373584, Neon Wharf night 423 / 410342, garage and shop up to 304 / 390966 (budget 500 / 450000).
  Studio shots of all eleven cars, garage, shop, the Ortakoy benchmark and four of the 43 tod_tracks shots (Maslak
  and Neon Wharf, day and night, High) re-taken. Not re-taken in that session: the other 39 tod_tracks shots (every
  Bosphorus one, every Low and Medium one) and race_bogaz / race_maslak / race_city / race_replay / race_kestrel,
  which still showed the replaced models. Manifest 655 records, 0 failing. (Sentence corrected after the review.)
- Owner's new bar the same evening: "Asphalt 4.7 almış App Store'da, hedef onu geçmek" and the Asphalt Ferrari key
  art as the quality reference. Said plainly to the owner: out-producing those studios is not possible here; the
  plan in ROADMAP.md goes for the rating instead. The ChatGPT work chat was deleted at the owner's request.
- Not done: traffic cars (two sedans, the Arden Civic) are still project-made. The Kestrel GT model is an electric car
  and keeps the engine sound. No iPhone measurement in the lead's hands. The TestFlight build is older than today.
- Commits: ad0f4de (part colours) and the commit that carries this entry.

### Next (superseded list below kept for history)
0. Environment density (waterfront, rooftops), camera replay, car read in the race, phone build.
1. Gate items below 7: car canopy/side glass, pack-race traffic avoidance, speed-line HUD mask,
   waterfront light. 2. M2 game loop: career, audio (needs CC0 download approval), onboarding.
3. Owner decisions: export templates (Windows .exe), macOS/Xcode access for iOS.

## Session 9 — night of 2026-11-27 to 28 (overnight release candidate)
- Owner briefs: graphics first, then the overnight studio brief (docs/status/OVERNIGHT_MASTER.md) and the full-game override.
  Lead Opus 5.5; workers Haiku 5.5 in their own worktrees; every package reviewed by a Haiku reviewer and an Opus lead
  reviewer before the lead merged it. Branch `release/rc-2026-11-28`, draft PR https://github.com/berkdemirokk/midnight-syndicate/pull/9.
- PR #8 (ChatGPT gameplay integration) verified (CI green, 355 tests locally) and merged once into the RC.
- Lead: day/sunset look (ACES white 6, afternoon sun, 2-split shadow, depth fog, clear sky, dark lower sky, warm car
  fill), dry/wet road per hour, patchy wet mirror, mirror 5 taps, rims/tyres, sea, plaster tone, before/after tooling.
- Merged packages: drive telemetry, GPU pass, photo-row architecture, LAN online (+ in-game fixes by the lead), AI churn,
  start-hitch attempts (findings only), net polish (Bosphorus, standings, TR/EN), UX, camera, pursuit, night diet +
  Asphalt-style framing, roadblock barriers, soak, smooth dome, drift + elimination modes, private lobby code, escape
  event, persistence check, onboarding + records, economy x4, touch survival, stone plinth, polish, release-review fixes
  (7 verified defects), car validation.
- Evidence: final full suite and checks in docs/status/RELEASE_CANDIDATE_2026-11-28.md; iOS compile check ios-check-5
  green (no upload). Dev PC numbers only; no iPhone test.
- Not done: 30 cars (owner approval for downloads), car LOD0 draw calls 59 vs budget 20 per car (needs a mesh/material
  merge pass), real-device test, App Store submission, internet multiplayer, the ~40 s frame spike, human playtest of
  modes/economy, sound by ear. Full list: docs/status/MASTER_CHECKLIST.md.

## Fleet C (wp/fleetC), 2026-11-28
- Budget blocker fixed: test_car_licensed test_budgets now passes (14/14). Only decimation ratios changed in
  assets_src/pipeline/vehicle_configs/{noctra_volta,noctra_regent,noctra_sovereign,noctra_monarch,noctra_titan}.json,
  then rebuilt with rebuild_vehicles.py (one Blender run under gpu_run). Godot LOD tris after: volta 88095/25196/6855,
  regent 79001/25628/6692, sovereign 77738/25089/6420, monarch 86228/24323/6092, titan 66999/19141/6797 (budgets 90000/28000/7000).
  LOD0 materials 12-13 and surfaces 22-23 (ratchet unchanged). Known floor: body/trim LOD2 ratios stopped reducing faces, wheel ratio did.
- Full suite 555 tests, 0 failed (before and after this fix only the budget test changed).
- Economy: NOT applied. Five cars are not in car_catalog.gd. tools/economy_sim.py currently gives 1.56 (10 buyable cars); the
  +five-car estimate was 2.04 against a 1.5-2.0 band. Owner decision needed (see BLOCKERS B13).
- Quality: titan proportions fail (B14), volta front red glow open (B15). Studio renders refreshed: evidence/screens/car_studio_{volta,regent,sovereign,monarch,titan}/.
- Lead review (Opus), 2026-11-28: dropped noctra_regent (same vinish.dev body as noctra_sovereign, only the wing differs)
  and noctra_monarch (same body as the catalogued noctra_meridian) with all their files and records. Front plates of
  volta, sovereign and titan were mirrored or clipped, so they are blanked like the other cars (front_plate_material
  M_Trim) and the three cars were rebuilt. Godot tris volta 88094/25196/6855, sovereign 77737/25089/6420,
  titan 66997/19141/6797. Studio renders of the three re-captured (16 shots each, errors=0) and looked at; a titan
  race capture on the city track was looked at (rear plate legible, reads as an SUV). B14 and B15 closed. Full suite
  555 tests, 0 failed. asset_factory validate: 682 records, 0 failing. Economy and catalog entries still wait on B13.
## WP-B6 Shader Baker (wp/b6baker)
- Changed: `game/export_presets.cfg` iOS preset `shader_baker/enabled=true` (3c3720d4); new test `game/tests/test_export_shader_baker.gd` (a4008e03) checks the key is on for iOS and nowhere else.
- Key confirmed as a string in the Godot 4.7.2 binary. Effect on first launch: not measured (headless export may skip the bake).
- CI iOS compile check: OPEN, no run id (build-ios.yml runs on `ios-check-*` tags only; the worker did not push).
- Lead review (Opus): key `shader_baker/enabled` found 4x in Godot_v4.7.2-stable_win64.exe. Local headless `--export-release "iOS"` with a dummy team id (as CI's sed does) finished with warnings only (`.ipa` needs macOS; pre-existing boot_splash warning), no Shader Baker error, so the CI headless export is not broken by the key; the bake itself is likely skipped headless. Full suite 572 tests, 0 failed, exit 0. Preset edit approved by the lead.

## Session 10 — 2026-11-28 (quality rescue, research sprint, production sprint)

Owner rejected the RC quality. Director Opus 5.5, Haiku 5.5 workers in sparse worktrees, Haiku review + Opus gate per package.
Branch release/rc-2026-11-28, head after this session in git log (pushed). Dev PC numbers only (RTX 5060 Ti).

What really changed (all merged after review, full suite green at each checkpoint):
- Environment (lead): 3D storefronts replace the photo shop band on all three tracks (7bfe241, per-shop night light
  eb6abcd); brick/concrete side walls on Wharf/Maslak (f433e35); CC0 Poly Haven street furniture in front of the rows
  (2528ba8, 035fe81); erguvan (Judas tree) rows on the Ortakoy pavements and the MultiMesh-at-origin cull bug fixed
  (8537f42f); erguvan petals (759e5f0a); night interior parallax on photo facades (162e6af3); capture runs never
  auto-pause (6ec3ce4).
- Cars: 11 -> 24 licensed vinish.dev CC BY 4.0 cars (fleetD 4, fleetC 3, fleetF 6 classics); 9 candidates rejected as
  re-skins of shipped bodies (geometry screen docs/design/FLEET_SCREEN_ROUND2.md); 3 police cars; brake disc+caliper
  merged (LOD0 21-23 surfaces); day paint deeper red (1395367d); panorama slides over the clear coat (ea254937).
- Gameplay: speed feel (182 km/h at 8 s, was 159), AI racing line/overtake/defence on, 10 reverse events + chapters,
  pursuit menu/aggression/hiding spots, touch steer 4 ticks to lock (was 11), steer-assist mode, drift exit push,
  reduced-motion setting, denser drift smoke.
- UI/audio: main menu with 3D car + loading screen, HUD, results, settings (5 tabs), layered engine wired, per-wheel
  tyre audio, CC0 siren, music ducking (0e182fc3).
- Perf/release: perf card for iPhone sessions, pipeline warm-up, iOS Shader Baker, App Store metadata draft;
  ios-check-7 and ios-check-8 green (build only).
- Research: docs/research/lookdev/ (10 sourced notes + PRODUCTION_PLAN.md, Opus-audited).
- Economy: reward table x1.96 overall (7840/4704/2352/784) for the 24-car roster; economy_sim 1.58 (band 1.5-2.0).

Evidence: full suite 601 tests, 0 failed (after fleetF); asset manifest 734 records, 0 failing; final pass
(tod_tracks 3x3, ortakoy_benchmark, 6 car studios, 3 reels, draw_breakdown 3 presets x 2 tracks, garage/HUD/menu)
0 errors except one blank LOD2 frame in car_studio_kartal. Bogaz High peak 411 draws / 427k primitives (budget 500/450k).

Not done / blockers: 30 cars (24; vinish.dev has no more distinct realistic bodies; the rest needs owner Sketchfab
downloads or modelling); internet multiplayer (needs an owner account: EOS, Game Center or Cloudflare); no iPhone
measurement; nobody listened to the audio; no human playtest; Noctra Tayfun/Cyclon silhouette resembles a famous
rear-engine sports car (owner to judge brand risk); quality is clearly better but not proven equal to NFS/Asphalt.


## Session 10-UI — 2026-11-28 (STREET EMPIRE brand and UI overhaul, parallel UI studio session)
- Owner brief: rename the product to **STREET EMPIRE — RULE THE CITY** and redesign every player-facing screen.
  Branch `feature/street-empire-ui-overhaul` (own worktree), draft PR https://github.com/berkdemirokk/midnight-syndicate/pull/10.
  Lead Opus 5.5; Haiku workers (HUD, garage, career, remaining screens) with lead review rounds and one independent
  Haiku code review (findings fixed). UI only: no physics, AI, race, network, world or save changes.
- Brand: `docs/brand/BRAND_GUIDELINES.md` (graphite/racing red/titanium/pearl), Anton + Manrope (SIL OFL 1.1, local
  copies, no download; asset_factory accepts OFL fonts), wordmark, SE icon, splash, Router loading card. All screens
  restyle through `MSTheme` (old token names aliased).
- Main menu: real 3D showroom with the selected car (`game/ui/showroom/showroom_stage.gd`), lite tier for phones/Low,
  PLAY starts the next unfinished career event, real REP/cash/stars/district progress, profile card.
- Career district tabs, garage configurator with purchase confirmation and rebranded room sign, broadcast-style race
  and pursuit HUD, pause/results/settings/records/onboarding/lobby/pursuit select in the brand.
- Merged release/rc-2026-11-28 (career2 chapters, pursuit2, uiresults) into the branch; conflicts resolved, see the
  merge commit.
- Evidence (dev PC RTX 5060 Ti; not iPhone numbers): full suite 561 tests, 0 failed (merged tree); asset manifest 677
  records, 0 failing; captures of every UI scenario and 63 before/after sheets in
  `evidence/screens/street_empire_before_after/`.
- Not done / blockers: lead-owned name changes (project.godot, export presets) listed in `docs/brand/INTEGRATION.md`;
  App Store name "Street Empire" may be taken (a "Street Empire Life Simulator" exists, `docs/brand/NAME_CHECK.md`);
  no rival crews/district control/player level in the game (UI shows only real data; requirements in INTEGRATION.md);
  world signage still says "MIDNIGHT ISTANBUL" on event barriers (world assets, other session); touch pads sit in the
  middle band in the 2532x1170 captures (pre-existing, same before the overhaul); pursuit_demo capture fails at the
  release's new hiding-spot step (gameplay, not UI); never run on an iPhone.
- Commits: f231cb2, 3c5d95d, 1cab86f, 206d45e, bc0c684 and the commit that carries this entry.
