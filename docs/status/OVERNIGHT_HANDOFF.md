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

## Done since 00:30 (all on release/rc-2026-11-28, pushed)
- Lead lighting pass: 41d7e47, 5220b50, 80ecdcc (day/sunset look, fog, asphalt/kerb specular, patchy wet road,
  mirror 5 taps, rims/tyres, sea). Captures in evidence/screens/ortakoy_benchmark/.
- Merged after Haiku review + Opus lead review: wp/drive (telemetry report docs/perf/DRIVE_TELEMETRY.md),
  wp/perf (mirror diet, probes off on Low, shadow filter per preset, Medium FXAA; docs/perf/GPU_PASS_2026-11-28.md),
  wp/arch (textured party walls, roofs, eaves, glass gloss, bridge day colours), wp/online (LAN race, off by default).
  Full suite after the merges: 380 tests, 0 failed.
- Online in-game path verified (9d11983): tools/net_ingame_check.py, rendered client + headless client + server on
  127.0.0.1; fixed two real bugs (remote cars were static walls; clients stopped sending at the local finish -> DNF).

## Final state (05:35)
- release/rc-2026-11-28 at 84bf82c (+ doc commits): 467 tests, 0 failed; asset manifest 657/0; restart_check 21/21;
  net_smoke PASS and rendered online check (both cars finished) on the merged RC; iOS compile ios-check-5 green,
  ios-check-6 started on the final RC.
- Draft PR #9 to feature/vertical-slice. Nothing merged into feature/vertical-slice or main; ChatGPT branches untouched.
- Full status: docs/status/MASTER_CHECKLIST.md and docs/status/RELEASE_CANDIDATE_2026-11-28.md.

## Continue from here
1. Owner: review PR #9 (draft); merge into feature/vertical-slice when happy (it was never merged by the lead).
2. Owner: install the next TestFlight build (push tag ios-release-2 on the PR head) and report phone model, fps, heat.
3. Next work packages: car mesh/material merge to reach 20 objects per car at LOD0; the ~40 s spike (6+ runs per arm,
   log ResourceLoader); human playtest of drift/elimination thresholds and the economy; overtaking AI; Maslak/Neon Wharf
   look pass; more cars only after the owner approves downloads.
4. Worktrees wp-* under .claude/worktrees are merged; remove them when the owner agrees (disk).

## Commands
- Tests: `godot --headless --audio-driver Dummy --fixed-fps 60 --path game -s res://tests/run_tests.gd`
- Benchmark: `godot --path game --audio-driver Dummy --resolution 1920x1080 --position 20000,0 res://devtools/capture_boot.tscn -- --capture=ortakoy_benchmark`
- Online: `py -3.10 tools/net_smoke.py`, `py -3.10 tools/net_ingame_check.py`; persistence: `py -3.10 tools/restart_check.py`
