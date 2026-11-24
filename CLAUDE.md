# MIDNIGHT SYNDICATE — session instructions

Original cinematic 3D arcade street racing game. Godot 4.7.2 stable, GDScript, Mobile renderer,
iOS first, offline. Goal: a commercially shippable game, not a demo.

## Start of every session
1. Read PROGRESS.md (where we are), BLOCKERS.md (what is stuck), ROADMAP.md (what is next).
2. Read ARCHITECTURE.md before touching code, the art briefs in docs/art/ before touching assets.
3. Do not redo finished work. Research lives in docs/research/ and REA_ANALYSIS.md: reuse it.
4. Run the tests before and after changes (command below).

## Environment (Windows 11, RTX 5060 Ti 8 GB)
- Godot: `C:\Users\berk\tools\godot\Godot_v4.7.2-stable_win64_console.exe` (outside the repo)
- Blender 5.3: `C:\Program Files\Blender Foundation\Blender 5.3\blender.exe`
- Python: `py -3.10` (no pip installs without the owner's approval)
- Godot project root is `game/`. Assets are authored in `assets_src/` and shipped to `game/assets/`.

## Commands
```
# import (after adding class_name scripts or assets)
godot --headless --path game --import
# logic tests (exit code 0 = pass, results in evidence/test_results.json)
godot --headless --fixed-fps 60 --path game -s res://tests/run_tests.gd [-- --only=test_x]
# real screenshots (the only screenshots that count as evidence)
godot --path game --resolution 1920x1080 res://devtools/capture_boot.tscn -- --capture=<scenario>
# asset manifest
py -3.10 tools/asset_factory.py validate
```

## Model routing
- Lead (Fable): architecture, contracts, art direction, critical graphics judgement, final review.
- Subagents default to Haiku. Every delegated task names the files it owns and its acceptance
  criteria, and is followed by an independent review before the lead accepts it.
- Limited parallelism, disjoint file ownership. `game/project.godot`, `game/tests/run_tests.gd`
  and the contract files are lead-owned.

## Rules that do not bend
- Clean-room: public sources only. Never decompile, extract or copy another game's code, art,
  audio, names or brands. Everything in the game is original (maker "Noctra", city "Arden Bay").
- Graphics first. No primitive-box cars or cities as final assets, no flat-colour-only final
  materials, no screenshot that did not come from the capture harness, no "done" without a real
  render that was looked at.
- Evidence over claims: performance numbers are measured and name the machine; desktop numbers are
  never reported as iPhone numbers; "App Store ready" is not said before a real Xcode build and a
  real iPhone test.
- Zero extra cost: no paid APIs, assets, hosting or build services. Third-party assets are CC0
  only, recorded in ASSET_MANIFEST.json and THIRD_PARTY_LICENSES.md when downloaded.
- Ask the owner before anything that spends money, accepts an agreement, publishes, sends a
  message, deletes, or downloads large files.
- Secrets and signing files never enter the repository.

## Project memory files
ROADMAP.md, PROGRESS.md, ARCHITECTURE.md, GAME_DESIGN_DOCUMENT.md, REA_ANALYSIS.md,
COMPETITOR_ANALYSIS.md, ASSET_MANIFEST.json, GRAPHICS_BENCHMARK.md, TEST_RESULTS.md, BLOCKERS.md,
THIRD_PARTY_LICENSES.md, RELEASE_CHECKLIST.md, AGENTS.md. Update PROGRESS.md at the end of every
session with what really changed, the test evidence and the commit SHAs.
