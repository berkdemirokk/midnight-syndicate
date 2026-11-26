# TASKS — final release mission (deadline 2026-11-26 23:59 TRT)

Lead: Fable 5.2. Subagents and reviewers: Haiku 5.5 (isolated worktrees, independent review, lead looks at real
captures before accepting). Checkpoints: this file, PROGRESS.md, BLOCKERS.md, TEST_RESULTS.md,
GRAPHICS_BENCHMARK.md, RELEASE_CHECKLIST.md.

## P0 — blocks playing or shipping
- [ ] iOS build: blocked. GitHub repository secrets are missing (count 0): APPLE_TEAM_ID, ASC_KEY_ID,
      ASC_ISSUER_ID, ASC_KEY_P8. Workflow, export preset, App ID and App Store Connect record exist. Owner action.
- [ ] Windows exe is blocked by Smart App Control on the dev PC (unsigned template). The exported pck runs.
- [x] Full loop: menu -> career -> race -> results -> rewards -> garage/shop (tests cover it).

## P1 — graphics, driving, UX
First milestone: ORTAKOY — BOSPHORUS RACE (track istanbul_bogaz; benchmark scenario `ortakoy_benchmark`, day / dusk / night).
- [x] Waterfront mosque: relief, drum, turrets, fluted minarets, photo-based sandstone (CC0), baked AO
- [x] 3D suspension bridge, far-shore lights, ferry, moon sky (flat skyline cards hidden)
- [x] Race dressing: barriers with banners, flags, cafe terraces (spectator cards switched off: read as toys)
- [x] Wheel spray, underglow, rain on lens
- [x] HUD in the reference layout with live data
- [x] Licensed cars: six CC BY 4.0 models (starter Noctra Tayfun, licensed rival grid), credits in settings
- [x] Road: photo-based asphalt, rubber on the racing groove, oil stains
- [x] Day light: sun, neutral sky fill, baked AO, dry walls without sky mirror
- [x] Land-side street: licensed shop houses with Turkish signs, lit at night (generic style, see open items)
- [x] Trees: licensed plane, cypress, magnolia, street tree
- [x] Spectators as 3D figures, licensed ferry, rain beads on paint, mosque pass 3
- [x] Photo-texture pipeline (generated straight-on pictures on simple geometry, night picture as glow map)
- [x] Istanbul row houses with photo fronts on the whole Bosphorus lap; photo rows and towers on Maslak and Neon Wharf
- [x] Mosque photo walls, far shore photo band, photo trees, printed sponsor boards, photo spectators, photo garage
- [ ] Sea-side wall and kerb, bridge day material, car reflections of the new street, day GI
- [ ] Gate: lead score about 81/100, target 90 not reached; owner review pending (rescue gate G6)

## P2 — more content (only after the Ortakoy scene passes its gate)
- [ ] Karakoy/Galata, Besiktas/Dolmabahce, Kadikoy/Moda, Taksim, Eurasia-tunnel themed tracks
- [ ] Police pursuit, drag mode, story missions, Ultra preset
- [ ] Pedestrians, more car models

## Not possible on this machine today (stated, not hidden)
- Real iPhone test and App Store submission (needs the secrets, then TestFlight, then a device).
- Phone FPS numbers (all measurements are desktop RTX 5060 Ti).
