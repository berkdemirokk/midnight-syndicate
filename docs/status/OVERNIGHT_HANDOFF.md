# Overnight handoff (2026-11-28)

Brief: `docs/status/OVERNIGHT_MASTER.md`. Lead: Opus 5.5. Release candidate branch: `release/rc-2026-11-28`
(pushed; worktree `.claude/worktrees/fable-graphics-visual-quality-105c41`).

## Done and verified
- 23:47 fetch; PR #8 (`integration/chatgpt-gameplay-2026-11-27`, one commit 31d04dc on a4c30a1) checked: mergeable,
  its CI green (logic-tests and asset-validation, runs 46065339129 / 46065346897).
- PR #8 merged once into the RC (d02fd4e). Local full suite: 355 tests, 0 failed; `tools/verify_test_evidence.py`
  verified 355; asset manifest 657 records, 0 failing. Commits ce4b242, then the uid files.
- Graphics audit (6 Opus auditors, each checked by an Opus verifier): digest kept outside the repo; the corrected
  proposals are what the work packages implement.

## In progress
- Lead: day/sunset lighting (ACES white 6, real depth fog, hazy sky, street-dark ground half, warm car fill/rim,
  day fill direction bug), dry asphalt and kerb specular per hour, mirror blur 9 -> 5 taps, sea colours per hour,
  neutral rims, tyre sheen, paint street reflection per hour.
- Haiku packages (worktrees `.claude/worktrees/wp-<key>`, branches `wp/<key>`), each reviewed by a Haiku reviewer and
  an Opus lead reviewer: arch (photo rows: textured party walls, roofs, eaves, glass gloss, bridge), camera (framing,
  orbit, FOV cap, nitro punch), online (LAN race, disabled by default), pursuit (opt-in mode, disabled by default),
  drive (telemetry report, no physics change), perf (mirror diet, probes off on Low, shadow filter, Medium FXAA).

## Commands
- Tests: `godot --headless --audio-driver Dummy --fixed-fps 60 --path game -s res://tests/run_tests.gd`
- Benchmark shots: `godot --path game --audio-driver Dummy --resolution 1920x1080 --position 20000,0 res://devtools/capture_boot.tscn -- --capture=ortakoy_benchmark`
- Godot can hang at exit after a capture has finished (seen 2026-11-28 00:20); the capture line `[CAPTURE] ... exit=N`
  is the result.

## Pending
- Merge reviewed packages into the RC, combined tests and captures, integration PR, final report.
