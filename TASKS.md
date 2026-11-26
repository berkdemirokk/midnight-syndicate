# TASKS — final release mission (deadline 2026-11-26 23:59 TRT)

Lead: Fable 5.2. Subagents and reviewers: Haiku 5.5 (isolated worktrees, independent review, lead looks at real
captures before accepting). Checkpoints: this file, PROGRESS.md, BLOCKERS.md, TEST_RESULTS.md,
GRAPHICS_BENCHMARK.md, RELEASE_CHECKLIST.md.

## P0 — blocks playing or shipping
- [ ] iOS build: blocked. GitHub repository secrets are missing (count 0): APPLE_TEAM_ID, ASC_KEY_ID,
      ASC_ISSUER_ID, ASC_KEY_P8. Workflow, export preset, App ID and App Store Connect record exist. Owner action.
- [ ] Windows exe is blocked by Smart App Control on the dev PC (unsigned template). The exported pck runs.
- [x] Full loop: menu -> career -> race -> results -> rewards -> garage/shop (tests cover it).

## P1 — graphics, driving, UX (most of today's effort)
First milestone: ORTAKOY — BOSPHORUS NIGHT RACE (track istanbul_bogaz at night, rain).
- [ ] Waterfront mosque landmark (running, Haiku)
- [ ] 3D lit suspension bridge, far-shore lights, ferry, moon sky (running, Haiku)
- [ ] Race dressing: barriers with banners, flags, crowd, cafe terraces, string lights (running, Haiku)
- [ ] Wheel spray, underglow, rain on lens (running, Haiku)
- [ ] HUD in the reference layout: leaderboard, progress strip, round minimap, tachometer (running, Haiku)
- [ ] Lead: warm street lighting vs cool night balance, wet road reflections, bloom, grade (PostFx added)
- [ ] Hero car detail pass: widebody, splitter, diffuser, wing, tyre tread, brake discs, Turkish-format plate, interior
- [ ] Paint streak artefact near arches/doors on Vela, Bruiser, Sable (not fixed by two agent rounds)
- [ ] 100-point visual gate from real captures against the reference
- [x] Day/sunset/night, trees, sea, paving, contact shadows, window interiors and sky reflection, street kit
- [x] Handling pass, traffic, mixed rival models, car shop, audio, career with Istanbul events

## P2 — more content (only after the Ortakoy scene passes its gate)
- [ ] Karakoy/Galata, Besiktas/Dolmabahce, Kadikoy/Moda, Taksim, Eurasia-tunnel themed tracks
- [ ] Police pursuit, drag mode, story missions, Ultra preset
- [ ] Pedestrians, more car models

## Not possible on this machine today (stated, not hidden)
- Real iPhone test and App Store submission (needs the secrets, then TestFlight, then a device).
- Phone FPS numbers (all measurements are desktop RTX 5060 Ti).
