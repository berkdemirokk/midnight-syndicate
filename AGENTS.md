# Agents

Lead: Claude Fable 5.2 (CTO, game director, lead architect, art director for critical calls).
Workers: Claude Haiku 5.5 subagents, started through the real subagent/workflow mechanism.
Every worker task has: owned files, acceptance criteria, a required evidence type, and an
independent reviewer that did not write the work. The lead accepts or rejects on evidence.

## Roster and ownership
| agent | owns | evidence it must return |
|---|---|---|
| REA Research | docs/research/*.md | sources table, [S]/[E] tags, verification pass |
| Replica Architect | replica/recon.md, replica/features.csv | screen/flow/feature counts |
| Art Director (lead) | docs/art/*_BRIEF.md | briefs are the acceptance contracts |
| 3D Asset | assets_src/vehicles/** | GLB + Blender renders + report.json |
| Blender Automation | assets_src/**/build_*.py, tools/ | deterministic re-run, logs |
| Texture | tools/fetch_cc0.py, game/assets/textures/**, manifest, licences | manifest validate output, contact sheet |
| Shader | game/shaders/** | capture-harness screenshots, perf probe |
| Environment | assets_src/world/**, game/world/** | district renders, layout numbers |
| Vehicle Physics | game/vehicles/arcade_car.gd, specs, VEHICLE_TUNING.md | headless test metrics |
| Racing AI | game/ai/**, game/world/track.gd, game/race/** | lap completion tests |
| Police AI | game/ai/police_driver.gd (later milestone) | pursuit tests |
| Gameplay | game/vehicles/player_driver.gd, game/camera/**, race scene glue | tests + captures |
| UI/UX | game/ui/** | captures at 1920x1080 and 2556x1179 |
| Audio | game/audio/** (later milestone) | CC0 sources in manifest |
| Optimization | game/core/settings.gd presets, perf scenarios | GRAPHICS_BENCHMARK.md rows |
| QA | game/tests/test_*.gd, TEST_RESULTS.md | exit codes, test_results.json |
| Independent Review | nothing (read-only) | defect list with severity and evidence |
| iOS Release | .github/workflows/**, docs/release/**, RELEASE_CHECKLIST.md | what is verified vs not |

Lead-owned, workers do not edit: game/project.godot, game/tests/run_tests.gd,
game/tests/test_case.gd, game/core/input_setup.gd, game/vehicles/vehicle_input.gd, ARCHITECTURE.md,
CLAUDE.md, ROADMAP.md.

## Working rules for workers
- Read ARCHITECTURE.md and the relevant brief first. Work only in owned files.
- Root-cause before retry. Never repeat an unchanged failing command.
- Logs go to files; read tails. No binaries or whole repos in context.
- Visual work is looked at (Read the PNG) every round. Honest scores.
- Never weaken a test range to pass. Report the measured number.
- No commits, no installs, no downloads unless the task says the owner approved them.

## Loop per milestone
RESEARCH -> PLAN -> IMPLEMENT -> BUILD -> TEST -> RENDER -> REVIEW -> FIX -> RETEST -> COMMIT
Two review stages for visuals: independent Haiku reviewer, then the lead on real screenshots.
