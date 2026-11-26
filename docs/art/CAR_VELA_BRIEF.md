# CAR VELA — "Noctra Vela" hot hatch

Original compact 3-door hot hatch, front-wheel-drive feel. Clearly a different class from the Sable R
(low mid-engine GT) and the Arden Civic (four-door sedan). No real silhouette, badge or logo; plate and tyre
text say VELA / NOCTRA only.

## Pipeline
Same surface engine as `noctra_sable/final/body.py` (PCHIP curves, section anchors, bisect-cut glazing,
arch boolean), copied to `assets_src/vehicles/noctra_vela/` with its own curve data. `build_car.py` builds
body, glass, trim, lights, interior, underbody, exhaust, plate, wheels, brakes, `col_body`, textures, then LODs
by decimation and the GLBs (`out/`). `render_car.py` renders the Cycles studio views (`renders/`).
`preview_body.py` is a 10 second body-only silhouette preview. Same object names, material names and
`col_body` extras as the hero, so `car_lod.gd`, `CarMaterials` and `CarVisual` work unchanged.

## Dimensions (m, Z up, nose -Y, tolerance 3%)
| item | value |
|---|---|
| length (body surface incl. nose and tail rounding) | 4.05 (mesh 4.08; splitter and tips make the model box 4.13) |
| width, body without mirrors | 1.80 (mesh 1.83) |
| height | 1.42 (mesh 1.425) |
| wheelbase | 2.55 (axles at s 0.755 and 3.305, Y_OFFSET 2.03) |
| front / rear track | 1.55 / 1.53 |
| tyre | 225/40 R18, outer radius 0.32, width 0.225, rim 18 in (lip radius 0.234) |
| arch gap | 34 mm radius over the tyre: the tyre fills the opening |
| ground clearance | 0.125 |

## Curve data (s from the nose, 0 to 4.00, PCHIP)
- z_top: (0,.49) (.06,.585) (.18,.69) (.45,.765) (.755,.80) (1.0,.85) (1.12,.90) (1.35,1.03) (1.6,1.19) (1.85,1.32) (2.1,1.395) (2.5,1.425) (2.9,1.415) (3.25,1.385) (3.52,1.34) (3.66,1.27) (3.8,1.13) (3.92,1.03) (4.0,.985)
- z_bot: (0,.27) (.12,.19) (.4,.14) (.8,.125) (3.3,.125) (3.7,.19) (4.0,.34)
- w_max (half width, wide arches): (0,.62) (.06,.77) (.25,.87) (.755,.915) (1.3,.875) (2.0,.865) (2.7,.875) (3.305,.915) (3.6,.905) (3.82,.875) (4.0,.83)
- z_sh (belt): (0,.49) (.08,.585) (.2,.695) (.45,.795) (.755,.855) (1.2,.895) (1.8,.925) (2.4,.945) (3.0,.965) (3.5,.985) (3.75,.98) (4.0,.955)
- Greenhouse: shelf 0.07, side glass leans 15 degrees, roof crown 0.028; short bonnet (windscreen base at s 1.14, 28% of the length), steep hatch (glass from the roof edge at s 3.52 down to 3.86).
- Tail: three rounding rings, then a flat cap (lamps, plate, valance).

## Details
Slim wedge headlamps on the bonnet corners (lens, day-running bar, projector block), black grille slot and wide
mouth with surface-following bars, carbon splitter, rocker and skirts, roof spoiler overhanging the hatch glass,
door-glass B-pillar band, 3-door single door handle, mirrors, vertical tail lamps joined by a light bar, plate,
twin corner exhaust tips, three diffuser strakes, ten-spoke concave 18 in rims, yellow calipers.

## Budgets and files
LOD0 66 442 (max 70 000), LOD1 21 490 (max 22 000), LOD2 5 899 (max 6 000). Shipped to
`game/assets/vehicles/noctra_vela/`; scene `game/vehicles/noctra_vela/noctra_vela.tscn` (script
`vehicles/noctra_sable/car_lod.gd`), spec `game/vehicles/specs/noctra_vela.tres`.

## Known limits
The nose is rounder than a production hatch; glass interior is a coarse placeholder cabin; mirrors sit outside
the 1.80 m body width (box 1.94 with mirrors).

## Revision 2 (review fixes)
Shorter cabin (roof peak at s 2.3, hatch glass 3.38 to 3.70), body ends at s 3.94 (short tail overhang), belt line lowered
and rising toward the rear, door scallop and narrower mid body for visible rear haunches (width 1.85 at the rear arch),
tapered and rounded tail, roof wing with shaped end plates, slim dark headlamp housings with DRL bar and projector (no milky
lens), near-black liner, cross panel grooves removed (they made zigzag seams in engine). Grey wedges seen in the studio
shots are reflections of the studio softboxes on the glass, not geometry. Known limits: nose bumper corner is still soft;
faint reflection jitter along the lower door.
