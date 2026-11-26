# CAR 02 — "Arden Bruiser" asset brief

Owner: Art Director. Acceptance contract for the second car. Original design, no real car's
silhouette, grille, light signature or badge; no real brand names anywhere (meshes, textures, plates).

## Identity
- Fictional maker: **Arden Motor Works** (city Arden Bay). Model: **Bruiser**. Front-engine, rear-drive
  modern muscle coupe. Heavy, loud, loose rear: it is the drift car.
- Mood: long, heavy bonnet, planted wide hips, short deck. Must read as a different car from the hero
  (mid-engine wedge) in a 64 px silhouette: the hero has the cabin forward and a low nose; the Bruiser has
  the cabin set back, a tall blunt nose and a long hood.
- Signature (ours): wide, tall, shallow-mesh grille with a thick horizontal bar and a stepped lower lip;
  twin stacked rectangular-with-cut-corner headlight pods at the fender ends; central power bulge on the
  bonnet with two blade vents; one continuous horizontal tail light bar spanning the deck with a notched
  centre and a thin lower bar; short ducktail lip; quad exhaust tips in a dark lower valance.

## Hard dimensions (metres, tolerance +-3%)
| item | value |
|---|---|
| overall length | 4.85 |
| overall width (body, no mirrors) | 1.92 |
| overall height | 1.36 |
| wheelbase | 2.85 |
| front track / rear track | 1.60 / 1.58 |
| front overhang / rear overhang | 0.95 / 1.05 |
| ground clearance | 0.13 |
| tyre outer diameter front / rear | 0.69 / 0.71 |
| tyre width front / rear | 0.275 / 0.315 |
| rim diameter | 19 in front / 20 in rear |
| roof peak position | 57% of length from nose |
| windscreen rake | about 35 degrees from horizontal |

## Coordinate system (Blender), same as the hero
- 1 unit = 1 m. Z up. Nose at **-Y**. Scene origin on the ground, midway between the axles.
- Front axle Y = -1.425, rear axle Y = +1.425.

## Objects and materials
Identical node and material names to docs/art/CAR_01_BRIEF.md: body, glass, trim, lights_front,
lights_rear, interior, underbody, exhaust, plate_rear, wheel_FL..RR, brake_FL..RR, col_body (<= 48 vertices,
`collision_only` extra). Materials M_Paint, M_Pillar, M_Glass, M_Lens, M_LightFront, M_LightRear, M_Carbon,
M_Rim, M_Tire, M_BrakeDisc, M_Caliper, M_Trim, M_Chrome, M_Interior, M_Plate (<= 15).

## Shape rules
1. One continuous smooth shell, 4 to 6 mm grooves for hood, doors, trunk and bumpers.
2. Real arches concentric with the wheels; rear haunches wider than the cabin.
3. Cabin set back: windscreen base about 37% of length, fastback roofline falling to a short deck.
4. Tall nose (leading edge about 0.60 m), long bonnet with a power bulge (about 35 mm), high shoulder rising
   toward the rear, deck about 0.95 m.
5. Tail: full-width light bar, plate in the lower centre, quad exhausts.
6. Wheels: six-spoke concave design (distinct from the hero's twin-spoke), deep barrel, caliper behind.

## Budgets
LOD0 <= 85 000 triangles, LOD1 <= 26 000, LOD2 <= 7 000. <= 15 materials, <= 20 draw objects at LOD0.

## Handling character (game/vehicles/specs/arden_bruiser.tres)
Strong acceleration (engine force above the hero), heavy (about 1750 kg), loose rear (low rear grip, low
drift-entry thresholds, weaker yaw damping): drifts easily.
