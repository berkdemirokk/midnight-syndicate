# STREET EMPIRE UI overhaul — integration notes

Branch `feature/street-empire-ui-overhaul`, cut from `release/rc-2026-11-28` at eb6abcd. UI-only: no physics, AI,
race logic, networking, world geometry or save changes. Bundle identifier, signing, save path and save format are
untouched; existing player progression loads as before.

## What the branch changes
| area | files |
|---|---|
| Brand system | `game/ui/theme/ms_theme.gd` (tokens, fonts, chamfer shapes; old names aliased), `game/ui/theme/star_pips.gd`, `game/ui/menus/logotype.gd`, `game/ui/menus/menu_backdrop.gd(.gdshader)`, `game/assets/branding/fonts/*` (OFL), `docs/brand/*` |
| Main menu | `game/ui/menus/main_menu.gd` (rewrite), `game/ui/showroom/showroom_stage.gd` (new 3D showroom) |
| Career | `game/ui/menus/event_select.gd` (district tabs) |
| Garage | `game/ui/garage/garage_hud.gd`, `garage_stats.gd`, `garage.gd` (framing + room rebrand), `garage_orbit.gd` untouched |
| Race HUD | `game/ui/hud/*.gd`, visuals in `game/race/pursuit/pursuit_hud.gd`, colours in `game/vehicles/touch/touch_controls.gd` |
| Other screens | pause, results, settings (+credits), records, onboarding, `game/net/net_lobby_menu.gd` (visuals only), `game/ui/menus/loading_card.gd` |
| Strings | `game/ui/i18n.gd` (new keys under `# --- street empire: ... ---` anchors; `menu.race` now PLAY/OYNA; two event titles lost "Midnight") |
| Branding renders | `game/assets/branding/icon_*.png`, `icon.ico`, `splash_1920.png` replaced in place; `wordmark_street_empire.png`; generator `assets_src/branding/make_brand_assets.py` |
| Tools | `tools/ui_capture.py` (one capture at a time on the shared GPU), `tools/asset_factory.py` (accepts OFL-1.1 fonts) |

## Shared files touched (small, flagged for the gameplay session)
- `game/core/router.gd`: the fade rect now carries the STREET EMPIRE loading card (shown while the next scene loads,
  faded with the rect). Fade timing and headless/capture behaviour unchanged.
- `game/race/pursuit/pursuit_hud.gd`: joins group `pursuit_hud`; `RaceHUD` starts its centre popups 84 px lower when
  that group exists (the heat line used to be covered by the drift popup).
- `tools/asset_factory.py`: new kind `font`, source `ofl:google-fonts`, licence `OFL-1.1`, own section in
  THIRD_PARTY_LICENSES.md. The project rule "CC0 or CC BY only" gets one exception: OFL fonts, which the owner asked for
  ("commercially permitted fonts").
- Tests: `test_ui.gd` expects PLAY/OYNA instead of RACE/YARIŞ (the main menu's primary is PLAY now);
  `test_events.gd` / `test_ui_r12.gd` window-count checks count rows of the current district (the list is grouped by
  district). No check was removed or loosened.

## Lead-owned changes the branch did NOT make (please apply when merging)
1. `game/project.godot`: `config/name="Street Empire"`; `boot_splash/bg_color=Color(0.063, 0.071, 0.086, 1)` (graphite,
   matches the new splash).
2. `game/export_presets.cfg`: Windows `product_name`, `company_name`, `file_description` → "Street Empire"; export file
   names `StreetEmpire.exe` / `StreetEmpire.ipa` if wanted. **Do not change the iOS bundle identifier.** The iOS
   display name (`application/name` or the project name) becomes "Street Empire" only after the App Store name check
   (`docs/brand/NAME_CHECK.md`).
3. `CLAUDE.md`, `ARCHITECTURE.md`, ROADMAP: product name.

## Known merge overlaps with other branches
- `wp/uiresults` (results paint chips, NEW BEST tag) and `wp/uimenus` (event select route loop) edit the same screens.
  Their logic additions should be re-applied on top of this branch's layouts; colours must come from MSTheme tokens.
- `i18n.gd`: expect line-level conflicts only.

## Requirements for the gameplay side (UI is ready, data is missing)
- **NEW BEST on results**: the results screen needs a flag in the result dictionary (e.g. `"new_best": true` from
  `GameState.record_result`), then it shows the GO tag.
- **District control** (rival crews, leaders, territory): not in the game; the UI shows only real stars per district.
  Needed: (1) a persisted owner per district in GameState with save versioning; (2) crew/leader data in EventCatalog
  from a real source; (3) take/lose rules (boss event, rival challenge); (4) a reward tied to owned districts; (5) tests
  for ownership transitions and migration. The career tabs and the main menu district rows are the places to show it.
- **Player level**: no level exists; the menu shows REP with the next real car unlock (CarCatalog rep gates). A level
  would need a rule in GameState.
- **Reduced motion**: a Settings flag would let the showroom camera and menu intro stand still.

## How to verify
```
godot --headless --fixed-fps 60 --audio-driver Dummy --path game -s res://tests/run_tests.gd
py -3.10 tools/ui_capture.py ui_main_menu   # and: ui_event_select garage garage_shop ui_hud_mock ui_pause ui_results_mock ui_settings ui_records ui_onboarding ui_lobby ui_loading ui_touch pursuit_demo mode_drift_hud
py -3.10 tools/asset_factory.py validate
```
Before/after sheets: `evidence/screens/street_empire_before_after/`.
