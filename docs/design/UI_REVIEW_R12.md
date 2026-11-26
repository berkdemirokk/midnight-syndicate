# UI review, round 12 (premium pass)

Method: the `impeccable` skill (critique, then polish, then audit) and the `ui-ux-pro-max` skill (design system, game UI,
touch and accessibility rules). Both are web-first; their rules were applied to the Godot UI where they carry over (hierarchy,
one primary action per screen, 44 pt targets, contrast, focus visibility, restraint) and ignored where they do not (CSS, ARIA).
Every finding below comes from a real capture of the baseline build (commit 487cc63), looked at, before any change.
Captures: `evidence/screens/ui_*/` (desktop 1920x1080, iPhone 2556x1179), `race_city/`, `garage/`.

## The sizing problem that drove the pass

The project stretches the 1080 px base height (`canvas_items`, `expand`). An iPhone 15 landscape screen is about 393 pt tall, so
1 px is 0.36 pt. Measured on the baseline:

| element | px | iPhone pt | verdict |
|---|---|---|---|
| menu button height | 64 | 23 | fails the 44 pt target by half |
| HUD timers, body text | 24 | 8.7 | below the 11 pt floor |
| captions | 18 | 6.5 | unreadable |
| settings slider track | 6 | 2 | cannot be grabbed |
| event row height | 56 | 20 | fails; ten rows cannot grow to 124 px without scrolling |

Design rule adopted: `MSTheme.phone` (true on `OS.has_feature("mobile")`, switchable in tests and captures) multiplies type by
1.5, sets buttons and rows to 124 px (44.6 pt), and scales the HUD frame by 1.4. Desktop keeps the old sizes.

## Screen by screen

### Main menu (ui_main_menu)
Baseline: flat near-black field with five thin sine lines (a placeholder look), left-aligned column, a 96 px logo.
- Defect: the sheared logo glyphs had a jumping baseline (M low, T high) because the skew was applied per glyph by the font. It looked broken at first glance.
- No hierarchy: RACE, GARAGE, SETTINGS, QUIT are four identical boxes; the primary action is only marked by the focus ring.
- No sense of place or game: nothing says "night street racing in a city". No career state (stars, cash, rep).
- Version label floats alone in the corner.
Done: new `Logotype` control (whole line sheared as one shape, magenta shadow, cyan edge, SYNDICATE line, speed-line slash);
`menu_backdrop.gdshader` (one full-screen pass: haze, three skyline layers with flickering windows, a wet perspective road, lane
dashes, head and tail light streaks, left-side darkening for text contrast); RACE is a solid cyan primary button (theme variation
`PrimaryButton`); career strip (stars, cash, rep) on a backing plate; buttons fade in with a stagger. `set_backdrop()` still swaps in a real 3D scene.

### Settings (ui_settings)
Baseline: controls floating on black in two loose columns, tiny checkboxes with separate labels (the label is not tappable),
sliders thin, no UI-sound slider although `Settings` has the UI bus, a lot of dead space, no sense of grouping.
Done: two cards (graphics + audio, controls + language) with hairline section headers; every row 56 px desktop, 124 px phone;
checkbox rows are one full-width focusable button (label left, switch right); thicker slider track and larger grabber;
UI SOUNDS slider added (TR + EN); `ui_cancel` goes back; scroll follows focus.

### Pause (ui_pause)
Baseline: tall panel sheared by 6 degrees, so the whole panel read as tilted; title and buttons crammed, RESUME not distinguished.
Done: upright card, magenta title rule, RESUME as the primary button, buttons 440 px wide, 124 px tall on phone.

### Event select (ui_event_select)
Baseline: dense but clear; flat background; selected row only tinted; the detail panel stacked caption over value with a large
empty area; START looked like BACK; on a phone rows are 20 pt tall.
Done: live backdrop; selected row gets a cyan accent bar; the detail panel puts the caption left and the value right, one line per
pair; START is the primary button; star size grows on phone. On a phone the list is a window of four 124 px rows that follows the
selection (up and down keys move it, and two chevron buttons are added for touch); desktop shows all ten rows as before.

### Results (ui_results_mock)
Baseline: correct but static; rewards panel was mostly empty; stars small and appeared instantly; table rows left a large void
under six drivers; NEXT EVENT not marked as the main action.
Done: your finishing place is the hero of the reward panel (88 px, gold for 1st); stars are larger, pop in one after the other with
an overshoot and an expanding ring; cash and rep keep the count-up; table rows grow to fill the panel (capped at 92 px); the
primary action (NEXT EVENT, else RETRY) is solid cyan; footer buttons widen on phone. Still a single batched board.

### Race HUD (ui_hud_mock and race_city)
Baseline findings, in order of cost to the player:
1. Text sat directly on the 3D scene. In race_city the "DRIFT 2" and "BANKED +1" lines landed on lit office windows and the
   lap/time block on bright signage: the 4 px outline is not enough.
2. The speed digits (112 px) were wider than the inside of the arc: the "7" crossed the arc in both captures.
3. The speedometer sat at 60 percent of the width, directly under the car's rear (race_city drift shot).
4. Position suffix and total were stacked at 24 px next to an 72 px digit with no container; the suffix read like a typo ("5 TH").
5. Phone: 24 px timers are 8.7 pt.
Done: backing plates (skewed, `PLATE_BG` 66 percent) under position, lap/time, speedometer, nitro and every centre popup, all in
the existing rect batch; speed digits 96 px inside a radius-132 arc (nothing touches the ring); speedometer moved to 76 percent of
the width, clear of the car; position digit 80 px with a 28 px suffix; the whole HUD frame scales 1.4x on a phone. HUD draw calls
stay within the budget (see the report).

### Garage (garage/overview) - not changed, owned by another agent
Findings for whoever integrates car selection there: stat labels and bars sit straight on a busy scene with no plate (same defect
as the old HUD); BACK and RACE are 64 px tall (23 pt on a phone); the tab row and colour swatches are about 30 pt; RACE is not a
primary button. Everything routed through `MSTheme` (buttons, option buttons, fonts) already inherits the phone sizing and the
`PrimaryButton` variation; the painted parts (stat bars, swatches, tabs) need the same `MSTheme.k()` treatment.

## Known limits
- The `slant` font kind (per-glyph skew through `FontVariation`) still has the uneven baseline; the garage car-name label uses it.
  The new menus use `bold` for titles and the `Logotype` control for the wordmark.
- The phone layout is chosen when a scene is built; rotating or resizing a live scene does not rebuild it.
- Not measured on a device. Phone captures are desktop renders at 2556x1179 with the phone layout forced on.
