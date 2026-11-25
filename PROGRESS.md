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

### Next (superseded list below kept for history)
0. Environment density (waterfront, rooftops), camera replay, car read in the race, phone build.
1. Gate items below 7: car canopy/side glass, pack-race traffic avoidance, speed-line HUD mask,
   waterfront light. 2. M2 game loop: career, audio (needs CC0 download approval), onboarding.
3. Owner decisions: export templates (Windows .exe), macOS/Xcode access for iOS.
