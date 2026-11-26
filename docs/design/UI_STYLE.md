# UI style (MIDNIGHT SYNDICATE)

Code: `game/ui/`. Shared theme: `ui/theme/ms_theme.gd` (`MSTheme.build()`). Strings: `ui/i18n.gd` (`I18n.t`).

## Colour tokens
| token | hex | use |
|---|---|---|
| BG | #0A0D14 | backdrop, screen background |
| PANEL_BG | #111827 at 82% | panels, buttons |
| CYAN | #19E6FF | primary accent, focus fill, speed arc |
| MAGENTA | #FF2BD6 | focus ring, secondary accent |
| AMBER | #FFC23D | warning, cash |
| DANGER | #FF3B30 | redline, wrong way |
| TEXT | #F2F5FA | primary text |
| MUTED | #8A94A6 | captions, secondary text |

## Type scale (px at 1920x1080 base)
- 112 HUD speed digits (largest HUD element)
- 96 logotype, 200 countdown (transient overlay only)
- 72 race position, 56 reward values
- 40 titles and lap value, 28 buttons and the total position
- 24 body and HUD times, 18 to 20 captions (tracked)

Fonts: Godot fallback font through `FontVariation`. Bold uses `variation_embolden`, slant uses
`variation_transform`, digits use the `tnum` OpenType feature (`MSTheme.font(kind)`).
No downloaded fonts or images.

## Components
- Buttons and chips: 12 degree lean (`SKEW_RATIO`), 1 px cyan border, min 360x64, 24/12 padding.
  Focus: 2 px magenta ring, no fill. Hover and pressed: cyan tint 16% and 32%.
- Large containers (tables, pause panel): half the lean, so tall panels do not tilt too far.
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
