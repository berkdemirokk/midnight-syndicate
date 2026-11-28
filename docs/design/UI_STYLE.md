# UI style (STREET EMPIRE)

Code: `game/ui/`. Shared theme: `ui/theme/ms_theme.gd` (`MSTheme.build()`). Strings: `ui/i18n.gd` (`I18n.t`).
Brand rules (colour, type, shapes, motion, imagery): `docs/brand/BRAND_GUIDELINES.md`. Integration: `docs/brand/INTEGRATION.md`.

## Colour tokens (2026-11-28 STREET EMPIRE overhaul)
Graphite #101216 base, racing red #F04432 accent, titanium #C4C8CE, pearl #F4F4F4, steel #8E949D captions, gold
#E9B856 money/stars, go #55C78E owned/gained, danger #FF5440. The old names stay as aliases: `CYAN` = red,
`MAGENTA` = pearl, `AMBER` = gold. No neon.

## Type
Anton (`display`, `slant`) for headlines and big numbers; Manrope (`body`, `bold`, `digits`, `tracked`) for the UI.
SIL OFL 1.1 files in `game/assets/branding/fonts/`. Scale: see the brand guidelines.

## Components
- Buttons and panels: chamfered corners (`MSTheme.box`, 10 px cut top-right and bottom-left), hairline titanium border.
  Focus: 2 px pearl ring. Hover: lifted graphite with a 4 px edge; pressed: red edge. Primary: solid red (`PrimaryButton`).
- HUD labels: no panel, 4 px dark outline for contrast on night backdrops.
- Grid: 8 px. Gaps: 16 between rows, 32 between sections.
- Thumb zones: keep bottom-left and bottom-right corners free. The speedometer sits centre-right,
  nitro centre-left, both inside the bottom 40% but clear of the corners.
- Safe area: `MSTheme.safe_insets()` added to every HUD and menu margin. Zero on desktop.

## Rules
- Only update a label when its value changes (`RaceHUD._set_text`).
- Every visible string goes through `I18n.t`. Tests fail on keys missing in Turkish or English, or used but undefined.
- Menus refresh text on `Settings.changed("general")`.

## Round 12 additions (see UI_REVIEW_R12.md)
- Device class: `MSTheme.phone` (true on mobile builds). `MSTheme.px(n)` scales type 1.5x, `MSTheme.button_h()` is 64 px on
  desktop and 124 px (44 pt on an iPhone) on a phone. Scenes read these at build time. Previews and tests call `MSTheme.set_phone(true)`.
- Primary action: theme variation `PrimaryButton` (solid cyan, dark label), one per screen. Painted boards (results, event select)
  use `MSTheme.PRIMARY_FILL` for the same look.
- Backing plates: `MSTheme.PLATE_BG` under every HUD cluster and popup; cards with `MSTheme.card()` (unslanted) inside scroll areas.
- Wordmark: `Logotype` control. Titles use the `bold` font kind (the `slant` kind has an uneven baseline).
- Menu backdrop: `MenuBackdrop` (menu_backdrop.gdshader), one full-screen pass, used by main menu, settings, event select, results.
- HUD: the whole frame scales by `RaceHUD.hud_scale()` (1.4 on phone); speed digits 96 px inside a radius-132 arc; gauge at 76 percent width.
