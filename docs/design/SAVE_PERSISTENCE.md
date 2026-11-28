# Save persistence: progression survives a restart

Status: implemented and tested (wp/persist). Owner: GameState (game/core/game_state.gd).

## What is saved

One JSON profile in `user://save.json` (Windows: `%APPDATA%/Godot/app_userdata/Midnight Syndicate/save.json`):

- cash, rep, stats (races, wins, cash_earned)
- owned_cars, selected_car
- car_setups per owned car: paint_color, rim_color (hex without #), upgrades (engine, tires, nitro, weight; 0 to 5)
- career per event: best_time, best_position, stars
- version (current 2; migrations for versions 0 and 1 live in `_migrate`)

Every mutator (add_cash, buy_car, set_paint, upgrade, record_result, select_car, ...) calls `_commit`, which saves at once. Nothing waits for the app to quit, so a kill loses at most the save in progress.

## How a save is written

`save_profile()` writes in this order, and each step keeps the last good copy:

1. Write `save.json.tmp`, read it back as JSON. Failure stops here; the main file is untouched.
2. If the main file is readable, copy it to `save.json.bak.tmp`, check it, rename it to `save.json.bak`. A blocked or failed backup stops the save and keeps the primary.
3. Rename `save.json.tmp` over `save.json`.

A kill at any point leaves either the old main file or the new one whole, and a backup that is the save before it.

## How a load works

`open_profile(path)`: main file, then `.bak`, then defaults. Every field is type checked and clamped by `_sanitize`, so a bad value never crashes the game. A leftover `.tmp` is never read.

## Proof

- In-process: `game/tests/test_persistence_restart.gd` (full career round trip with exact cash 47720, a second restart, torn main falls back to backup, missing main falls back to backup, stale .tmp ignored, a recovered profile keeps a clean backup) and the existing `test_game_state.gd`.
- Cross-process: `tools/restart_check.py` runs `game/tests/persist_restart_driver.gd` as separate Godot processes on a temporary save file. Process A starts the career, process B must load the identical snapshot, a process killed during a save must leave a whole main file and a backup one save behind, and a torn main file must load the backup. The real save is hashed before and after and must not change.

Run:

    py -3.10 tools/restart_check.py

## Defect found and fixed

The cross-process check showed that the starter car colours were stored as `#8e0f1e` and `#c0c0c0` in a new profile, but as `8e0f1e` and `c0c0c0` after any save and reload (saved colours never carry the #). Consumers use `Color.from_string`, which takes both forms, so nothing broke on screen, but a restart changed the stored value. The defaults now use the saved form.

## Not covered

- Cloud or multi-device save. Offline only, one file per device.
- A crash that corrupts both the main file and the backup at the same time falls back to defaults (the existing test_both_corrupt_gives_defaults covers that by design).
- The save is not encrypted. Progress is not protected against editing.
