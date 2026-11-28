# Release candidate 2026-11-28 (overnight)

Branch: `release/rc-2026-11-28` (from `feature/vertical-slice` a4c30a1). Integration PR: see the PR link in the
handoff. main untouched; no branch deleted; no force-push; ChatGPT branches untouched (PR #8 merged once, here only).
Machine for every number below: dev PC, Windows 11, NVIDIA RTX 5060 Ti 8 GB, Godot 4.7.2 Mobile renderer. No iPhone
was measured tonight: no number here is a phone number, and "App Store ready" is not claimed.

## What changed tonight
| area | what | verified by |
|---|---|---|
| Integration | PR #8 (30 events, save safety, AI recovery, garage upgrades, time-trial economy, pursuit rules, CI evidence) merged once | 355 tests, 0 failed after the merge; PR #8 CI green |
| Lighting | day/sunset: ACES white 6, afternoon sun 34 deg, 2-split sun shadow, real depth fog with aerial haze on the far shore, clear sky, street-dark ground half of the sky (no blue rims), warm car fill/rim, day fill direction bug fixed, mild grade | ortakoy_benchmark captures, before/after sheets |
| Road | dry asphalt specular per hour (no blue sheen), roughness follows the macro tone, wet road in metre-scale patches with a softer mirror, mirror blur 9 -> 5 taps, kerb/sidewalk wet film and specular per hour, paint on the asphalt grain | captures day/sunset/night |
| Cars | neutral rims (metal 0.75), tyre sheen, street panorama in the paint per hour | bench_*_car34 |
| Architecture | photo rows: tangents, textured party walls and tile roofs, 0.8 m eaves with soffit and fascia, glass gloss, bridge day colours, plaster tone | bench_day_street / hero |
| Camera | long-lens finish/grid orbit, horizontal FOV cap for wide phones, nitro punch (kick-back, FOV punch, blur burst), blur early-out | test_driver_camera, nitro capture |
| AI | queued cars are not "stuck", recovery frees after 2 m either way, follow brake | telemetry matrix before/after (stuck 114 -> 66, teleports 76 -> 30, unfinished 11 -> 2) |
| Online (experimental, off) | LAN race: lobby, ready, shared countdown, 20 Hz state, interpolation, server-authoritative laps/results, disconnect DNF, Bosphorus track, live standings, TR/EN | 3-process smoke + rendered in-game check |
| Pursuit (experimental, off) | opt-in police mode: heat 1-5, police spawn/despawn, chase AI, roadblock with an open lane, bust/escape, HUD | 15 tests + pursuit_demo captures |
| Performance | mirror diet (no glow/tonemap/shadow atlas/MSAA in the mirror), probes off on Low, shadow filter per preset, Medium FXAA | GPU_PASS_2026-11-28.md |
| UX | (see below) | |

## Not done / known limitations
- Race-start hitch not fixed (warm-up attempt showed no real reduction; docs/perf/START_HITCH.md).
- Asphalt-style lower chase framing not landed: it breaks the night primitive budget (see night diet result below).
- Online is LAN/loopback only, not internet multiplayer; the host is a dedicated server process; no auth/encryption.
- Pursuit barriers and light bar are simple; police AI tuned only in sim.
- No iPhone measurement, no iOS build tonight.

## Build and test
- Tests: `godot --headless --audio-driver Dummy --fixed-fps 60 --path game -s res://tests/run_tests.gd`
- Evidence check: `py -3.10 tools/verify_test_evidence.py evidence/test_results.json`
- Assets: `py -3.10 tools/asset_factory.py validate`
- Benchmark captures: `godot --path game --audio-driver Dummy --resolution 1920x1080 --position 20000,0 res://devtools/capture_boot.tscn -- --capture=ortakoy_benchmark`
- Online: `py -3.10 tools/net_smoke.py` and `py -3.10 tools/net_ingame_check.py` (start the game with `-- --experimental-online` to see the menu entry)
- Before/after: `py -3.10 tools/before_after.py <before_dir> evidence/screens/ortakoy_benchmark evidence/screens/before_after_2026-11-28`

## Licensing
No third-party asset was downloaded tonight. Every texture and model used is already recorded in ASSET_MANIFEST.json
and THIRD_PARTY_LICENSES.md (CC0 clay plaster and roof tiles, licensed cars). No real brands, no logos, fictional
police livery.
