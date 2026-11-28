# STREET EMPIRE — brand guidelines

Product name: **STREET EMPIRE**. Tagline: **RULE THE CITY** (Turkish UI line: ŞEHRE HÜKMET; the lockup keeps the
English tagline). Replaces the rejected "Midnight Syndicate" identity for everything the player sees. Internal ids,
the iOS bundle identifier, signing and save files are unchanged (see `docs/brand/INTEGRATION.md`).

Positioning: premium street racing about building an empire across Istanbul districts. The look is a modern
motorsport broadcast and a car-maker configurator, not a neon arcade: graphite surfaces, one racing red, titanium
hairlines, pearl type, real cars in real light.

## Wordmark
- `game/ui/menus/logotype.gd` (`Logotype`), and the rendered files in `game/assets/branding/`.
- STREET and EMPIRE in Anton capitals, leaning 8 degrees as one shape, split by the red **blade** (a parallelogram
  from baseline to cap height, 0.16 em wide, 0.10 em gap on each side).
- Tagline: Manrope Bold capitals, tracked, titanium, behind a 28 px red rule. Optional (`Logotype.new(k, false)`).
- Minimum size: 24 px cap height on screen. Clear space: one cap height on every side.
- Never: outline, glow, gradient fill, drop shadow, a second colour on the letters, re-spacing, or straight (unslanted)
  letters.
- Monogram for small spaces (app icon, loading spinner): **SE** with the blade between the letters.

## Colour
| token (MSTheme) | hex | use |
|---|---|---|
| GRAPHITE | #101216 | base surface, screen background |
| GRAPHITE_2 | #181B21 | raised panels, buttons |
| GRAPHITE_3 | #24272E | hover surface, tracks of bars |
| RED | #F04432 | the one accent: primary action, selection edge, progress, brand blade |
| RED_DEEP | #B82A1C | pressed primary |
| TITANIUM | #C4C8CE | secondary text, hairlines, icons |
| PEARL | #F4F4F4 | primary text, focus ring |
| STEEL | #8E949D | captions (5.9:1 on graphite) |
| GOLD | #E9B856 | currency and stars only |
| GO | #55C78E | owned, gained, personal best |
| DANGER | #FF5440 | redline, wrong way, busted |

Rules: red is spent on one thing per screen region (the primary action or the current selection). Large areas are
graphite, never red. No neon cyan or magenta, no rainbow gradients, no glow on text. Old token names in code
(`CYAN`, `MAGENTA`, `AMBER`) are aliases of RED, PEARL, GOLD so older screens follow the brand.

Contrast (WCAG 2.2): PEARL on GRAPHITE 17.6:1, TITANIUM 11.0:1, STEEL 5.9:1, PEARL on RED 3.3:1 (large bold
labels only, 24 px+ bold, which every primary button uses).

## Typography (commercially permitted, SIL OFL 1.1, in `game/assets/branding/fonts/`)
| role | face | MSTheme.font kind |
|---|---|---|
| wordmark, hero titles | Anton, 8 degree lean | `slant` |
| headlines, big numbers (speed, position, prices) | Anton | `display` |
| buttons, titles in the UI face | Manrope ExtraBold | `bold` |
| figures in tables, money, times | Manrope ExtraBold, tabular | `digits` |
| captions, labels (capitals) | Manrope Bold, +2 px tracking | `tracked` |
| running text | Manrope Medium | `body` |

Scale at the 1920x1080 base (phones x1.5 through `MSTheme.px`): 16 caption, 22 body, 24 button, 32 section, 44 title,
64-96 display, 112-140 HUD speed. Turkish glyphs (ğ ş ı İ ç ö ü) are in both faces.

## Shape and space
- Chamfer: buttons and panels cut 10 px at the top-right and bottom-left corners (`MSTheme.box`). Cards inside scroll
  areas use 2 px corners (`MSTheme.card`). Selected rows and the active tab get a 4 px red left edge (`MSTheme.edged`).
- 8 px grid. 16 between rows, 32 between groups, 64-96 screen edges on desktop plus the safe-area insets.
- Touch targets: 64 px desktop, 124 px (44 pt) on a phone (`MSTheme.button_h`).
- One primary (solid red) button per screen. Secondary: graphite plate. Tertiary: `GhostButton` (text only).

## Motion
- Screen in: 240 ms fade + 24 px rise, ease-out cubic, children staggered 40 ms. Screen out: 160 ms fade.
- Selection: 120 ms. Number changes count up over 400 ms. Camera moves in the showroom: 1.2-2.0 s ease-in-out.
- Respect `Settings` reduced motion when it exists (see INTEGRATION.md); never animate text that must be read
  while driving.

## Imagery
- The selected car is always the hero: real 3D model, real paint, studio light (graphite cyclorama, overhead soft
  strips, a red accent light low and behind).
- Backdrops without a 3D scene: the graphite studio shader (`MenuBackdrop`). No skylines or fake gameplay frames.
- Districts are shown with their real names (Arden Bay Neon Wharf, Ortaköy, Maslak, Boğaz) and real progress only.

## App icon and splash
- Icon: graphite chamfered tile, SE monogram in pearl Anton with the red blade, no text beyond the monogram, no
  gradient beyond a soft top light. `assets_src/branding/make_brand_assets.py` renders `icon_1024.png` and the sizes.
- Splash: graphite, centred wordmark with tagline, nothing else.

## Name check (2026-11-28, public web search only; not legal advice)
See `docs/brand/NAME_CHECK.md`. "Street Empire" is a common English phrase; the owner must run a formal trademark
search (TÜRKPATENT, EUIPO, USPTO class 9/41) and an App Store Connect name reservation before launch.
