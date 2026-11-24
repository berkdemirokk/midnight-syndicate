# Roadmap

Counts are cut before quality is. A milestone closes only on evidence (tests, real captures,
measured numbers), never on a document.

## M0 — Foundations
- [x] Environment verified (Godot 4.7.2, Blender 5.3, Git, gh, GPU)
- [x] Public-source research with verification pass (docs/research, REA_ANALYSIS, COMPETITOR_ANALYSIS)
- [x] Architecture, contracts, test harness
- [ ] Asset factory (manifest, licences, CC0 fetch) validated
- [ ] CI: headless tests on GitHub Actions (free Linux runner)

## M1 — Vertical slice (quality gate before any scale-up)
- [ ] Hero car "Noctra Sable R": LOD0-2, wheels separate, PBR, passes the car brief
- [ ] Circuit "Neon Wharf Loop": road, 5 districts, building kit, props, lights
- [ ] Arcade driving: suspension, grip, drift, nitro (all vehicle tests green)
- [ ] Chase camera, player input (keyboard, controller, touch)
- [ ] Rival AI completes clean laps, race manager, results
- [ ] Race HUD, main menu, pause, results, settings (TR/EN)
- [ ] Interactive 3D garage (orbit, paint, rims)
- [ ] Wet asphalt, neon glow, rain, nitro flame, tyre smoke, sparks, speed lines
- [ ] Graphics presets Low/Medium/High + dynamic resolution, measured on the dev PC
- [ ] Visual quality gate: 8 criteria scored on real captures, two review stages, lead sign-off
- [ ] Windows build runs from an exported binary

## M2 — Game loop
Save/load career, economy, upgrades and tuning, sprint + time trial + drag modes, engine and tyre
audio (CC0), haptics, onboarding, controller polish, replay camera, damage feedback.

## M3 — Pursuit and world
Police AI (heat, roadblocks, bust/escape), traffic, second track, cars 2-4, story missions act 1.

## M4 — Content and device
Third track, cars 5-10, missions to 30, localisation pass, first iPhone build (needs macOS/Xcode
access: see BLOCKERS.md), thermal and frame-time sessions on real devices, preset tuning.

## M5 — Release
Icon, launch screen, privacy manifest, screenshots from the capture harness, store text, age
rating, TestFlight internal, external, review submission (owner decisions throughout).

## Scope guard
First commercial target: 10 cars, 3 tracks, 30 missions, 5 modes, TR + EN, offline career.
Re-evaluated at the end of M1 against the real cost of one car and one track.
