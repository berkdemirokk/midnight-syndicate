# CAR - "Kestrel GT-R" asset brief

Owner: Art Director. Acceptance contract for the second playable car. ORIGINAL design: no real
car's silhouette, grille, light signature or badge, no real brand names anywhere (mesh names,
textures, plates). Fictional maker **Noctra**, model **Kestrel GT-R**.

## Identity
- Wide front-engine grand tourer. The opposite of the Sable R (mid-engine wedge): long bonnet,
  cab-rearward greenhouse, fastback roof into a short high tail, big rear diffuser.
- Reads as a heavy, fast, planted GT in a 64 px silhouette: the cabin sits over the rear axle,
  roughly 40% of the length is bonnet.
- Signature (ours): wide shallow mouth with horizontal slats under a pair of slim wrap-round pod
  head lamps (lit cells on a dark housing), a carbon bonnet louvre, front fender gills behind the
  front wheels, a painted fastback roof, a full-width tail light signature of THREE STACKED
  HORIZONTAL BLADES per side that join across the centre above the plate, a ducktail lip, a deep
  diffuser with seven strakes and quad centre-split exhaust tips, 10-spoke turbine wheels with a
  single centre-lock nut.

## Originality: what keeps it away from real cars
Review round 2 flagged the first pass (quad round tail lamps in a black panel, ducktail, slatted
nose, long-bonnet fastback) as too close to the C4/C5-era American front-engine sports coupes.
Changes, all kept in the final design:
- Tail lamps: no round lamps at all. Stacked horizontal light blades of different lengths with a
  centre link, a signature none of those cars has.
- Roof and glass: the greenhouse is body paint with a gloss black A-pillar only (those cars have
  a glass or black targa panel); the side glass is one continuous leaning pane.
- Nose and head lamps: slim wrap-round pods with cells under a dark housing, not pop-up or round
  lamps; wide slatted mouth with a flat splitter.
- Flank: a deep door scallop, tucked sill and a wider rear haunch (the doors are narrower than the
  fenders by 5 cm each side), no side coves.
- Wheels, text and badges are our own (`KESTREL GT-R`, no marque badge).

## Hard dimensions (metres, tolerance +-3%)
| item | value |
|---|---|
| body length (nose cap to tail cap, no splitter or lip) | 4.70 |
| overall length (with splitter and ducktail lip) | 4.80 (measured 4.80 on the shipped mesh) |
| overall width (body, no mirrors) | 1.98 |
| overall height | 1.28 |
| wheelbase | 2.75 |
| front track / rear track | 1.64 / 1.63 |
| front overhang / rear overhang | 0.93 / 1.02 |
| ground clearance | 0.12 |
| wheels | 20 inch (rim diameter 0.508) |
| tyre outer diameter front / rear | 0.686 / 0.704 |
| tyre width front / rear | 0.265 / 0.305 |
| roof peak position | 58% of length from the nose |
| windscreen rake | about 27 degrees from horizontal |
| bonnet length (nose to windscreen base) | 1.85 |

Mass 1560 kg class, so the spec makes it heavier, less agile and the fastest car.

## Coordinate system (Blender)
Same as the Sable: 1 unit = 1 m, Z up, nose to -Y, symmetric about X = 0, origin on the ground
between the axles. Front axle Y = -1.375, rear axle Y = +1.375. All transforms applied except
the wheels, whose origin is the wheel centre.

## Required objects (exact names, identical to the hero so car_lod.gd, CarMaterials and
CarVisual work unchanged)
body, glass, trim, lights_front, lights_rear, interior, underbody, exhaust, plate_rear,
wheel_FL, wheel_FR, wheel_RL, wheel_RR, brake_FL..brake_RR, col_body (hull <= 48 vertices,
extras collision_only = 1). Material names as in CAR_01_BRIEF.md (M_Paint, M_Glass, M_Pillar,
M_Carbon, M_Trim, M_Chrome, M_Interior, M_Plate, M_Lens, M_LightFront, M_LightRear, M_Tire,
M_Rim, M_BrakeDisc, M_Caliper). Tyre lettering `KESTREL GT-R`, plate text `KESTREL`.

## Budgets
LOD0 45k to 85k triangles, LOD1 <= 26k, LOD2 <= 7k (interior and brakes dropped at LOD2),
LOD0 at most 20 draw objects and 15 materials.

## Shape rules (pass/fail)
1. One smooth continuous body shell, controlled highlights, no faceting or poles.
2. Round arches concentric with the wheels, 35 to 55 mm tyre gap, arch lip, haunches wider
   than the cabin; the front fenders stand proud of the bonnet (power line).
3. Greenhouse narrower than the body, tumblehome, raked A-pillar, fastback rear glass in one
   piece, roof panel in body paint.
4. Panel gaps as 4 to 6 mm grooves: bonnet, doors, boot lid.
5. Wheels: concave 10-spoke rim with barrel, centre-lock nut, ventilated disc and caliper.
6. Nothing floats or intersects, symmetric left/right, no box shortcuts for the main forms.

## Look
Default paint: deep British-racing-style green is NOT used (too close to real marques'
heritage colours); the studio default is the project candy red; the garage lists the car with
a graphite metallic. Glass, trim, carbon and rubber follow the Sable material table.
