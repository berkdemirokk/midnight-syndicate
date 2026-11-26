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

### Next (superseded list below kept for history)
0. Environment density (waterfront, rooftops), camera replay, car read in the race, phone build.
1. Gate items below 7: car canopy/side glass, pack-race traffic avoidance, speed-line HUD mask,
   waterfront light. 2. M2 game loop: career, audio (needs CC0 download approval), onboarding.
3. Owner decisions: export templates (Windows .exe), macOS/Xcode access for iOS.
