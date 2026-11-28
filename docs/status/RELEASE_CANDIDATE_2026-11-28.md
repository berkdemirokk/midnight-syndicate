# Release candidate 2026-11-28 (overnight)

Branch: `release/rc-2026-11-28` (from `feature/vertical-slice` a4c30a1). Integration PR:
https://github.com/berkdemirokk/midnight-syndicate/pull/9 (draft, base feature/vertical-slice). main untouched; no branch
deleted; no force-push; ChatGPT branches untouched (PR #8 merged once, here only).
Machine for every number below: dev PC, Windows 11, NVIDIA RTX 5060 Ti 8 GB, Godot 4.7.2 Mobile renderer. No iPhone was
measured tonight: no number here is a phone number, and "App Store ready" is NOT claimed.

How the work was done: the lead (Opus 5.5) planned, did the lighting/sky/road pass itself and integrated. Every other
change was a work package built by a Haiku 5.5 worker in its own git worktree, reviewed by an independent Haiku reviewer,
then by an Opus lead reviewer (who re-ran tests and captures and fixed what they found), then merged by the lead. A final
independent release review (5 finders + adversarial verifiers) found 7 real defects; all 7 were fixed before 05:00.

## What changed tonight
| area | what | verified by |
|---|---|---|
| Integration | PR #8 (30 events, save safety, AI recovery, garage upgrades, time-trial economy, pursuit rules, CI evidence) merged once | 355 tests, 0 failed after the merge; PR #8 CI green |
| Lighting | day/sunset: ACES white 6, afternoon sun 34 deg, 2-split sun shadow, depth fog with haze on the far shore, clear sky, street-dark lower sky (no blue rims), warm car fill/rim, day fill direction bug fixed, arcade grade | evidence/screens/before_after_2026-11-28 |
| Road | dry asphalt specular per hour, roughness from the macro tone, wet road in metre-scale patches with a softer mirror, mirror blur 9 -> 5 taps, kerb wet film, paint on the asphalt grain, stone plinth instead of a bare grey barrier (Bogaz rebuilt) | captures day/sunset/night |
| Architecture | photo rows: tangents, textured party walls (desaturated plaster) and tile roofs, 0.8 m eaves with soffit/fascia, glass gloss, bridge day colours; smooth mosque dome normals | bench_day_street/hero/mosque |
| Cars | neutral rims, tyre sheen, street panorama in the paint per hour; validation of all 11 cars: see CAR_VALIDATION_2026-11-28.md if merged | bench_*_car34 |
| Camera | Asphalt-style lower chase framing (after a night mirror primitive diet), long-lens orbit, horizontal FOV cap, nitro punch | test_driver_camera, captures |
| AI | queued cars not "stuck", 2 m recovery either way, follow brake | telemetry: stuck 114 -> 66, teleports 76 -> 30, unfinished 11 -> 2 |
| Modes | drift (2 events) and elimination (2 events) | test_modes, mode captures |
| Pursuit | opt-in police mode; career event "Boğaz kaçışı" (bust = no reward); chase stops at the finish; no pause after bust | test_pursuit_mode, test_escape_event, captures |
| Online (experimental, off) | LAN race: lobby with 6-char join code, ready, countdown, 20 Hz sync, interpolation, server-authoritative laps/results, disconnect DNF, Bosphorus track, live standings, TR/EN, rate limit, hello deadline | net_smoke (real processes) + rendered in-game check |
| Player experience | first-run onboarding (OS language, controls, 3 hints), records screen, touch pause/restart/reset + auto-pause, 88 px garage targets, TR touch labels, TR/EN fixes | tests + ui captures |
| Economy | reward table x4: owning everything = 1.79 full 3-star careers (was 7.17) | tools/economy_sim.py, ECONOMY_2026-11-28.md |
| Save | backup failure no longer drops the save; cross-process restart check incl. crash during save | tools/restart_check.py, SAVE_PERSISTENCE.md |
| Performance | mirror diet, probes off on Low, shadow filter per preset, Medium FXAA; soak (10 headless + 8 rendered races) shows no drift after the first race | GPU_PASS, NIGHT_DIET, SOAK docs |
| iOS | compile check ios-check-5 passed on GitHub Actions (build only, no upload) | run 46086560575 |

## Not done / release blockers (honest list)
- 30 vehicles: 11 ship. More need the owner's approval to download licensed models (CLAUDE.md) or days of modelling.
- Real-device test: none (needs the owner's iPhone, B1/B2). No phone frame time, heat or memory number exists.
- App Store submission: owner-only steps and decisions (price, bundle id, age rating, screenshots on device).
- Internet multiplayer: LAN/loopback only; no free authorised hosting; no accounts, no encryption, no global ranking.
- Race-start/periodic frame spikes: start window clean in tests (0 frames > 25 ms in 5 s after GO), a ~40 s spike unexplained unless round 11 found it.
- Sound never judged by ear; drift/elimination thresholds and the economy need a human playtest; mode events sit at the end of the ladder.
- Quality versus Asphalt/NFS: clearly better than last night on the same camera, still behind the references (stylised licensed cars, photo facades flat at grazing angles, no global illumination).

## Build and test
- Tests: `godot --headless --audio-driver Dummy --fixed-fps 60 --path game -s res://tests/run_tests.gd`
- Evidence check: `py -3.10 tools/verify_test_evidence.py evidence/test_results.json`
- Assets: `py -3.10 tools/asset_factory.py validate`
- Benchmark captures: `godot --path game --audio-driver Dummy --resolution 1920x1080 --position 20000,0 res://devtools/capture_boot.tscn -- --capture=ortakoy_benchmark`
- Online: `py -3.10 tools/net_smoke.py`, `py -3.10 tools/net_ingame_check.py` (menu entry: start with `-- --experimental-online`)
- Restart/persistence: `py -3.10 tools/restart_check.py`; economy: `py -3.10 tools/economy_sim.py`
- Before/after: `py -3.10 tools/before_after.py <before_dir> evidence/screens/ortakoy_benchmark evidence/screens/before_after_2026-11-28`
- iOS compile check: push a tag `ios-check-N` (build only); `ios-release-N` uploads to TestFlight and stays owner-only.

## Licensing
No third-party asset was downloaded tonight. Every texture and model used was already recorded in ASSET_MANIFEST.json and
THIRD_PARTY_LICENSES.md (CC0 clay plaster, roof tiles, sandstone; licensed CC BY cars; event barrier kit is project-made).
Asset manifest validate: 657 records, 0 failing. No real brands, no logos, fictional police livery.
