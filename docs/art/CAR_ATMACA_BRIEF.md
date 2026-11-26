# CAR — "Bosfor Atmaca" (Istanbul family sedan, three variants)

Owner: Art Director (lead). Original car by the fictional maker Bosfor ("hawk" = atmaca). It evokes the
1980s-90s Turkish family sedan street culture (boxy three-box four-door, flat bonnet and boot, rectangular
lamps, thin pillars, big glasshouse, plain flat sides with one crease) without copying any real car.
No real maker's name, badge, grille, lamp signature or silhouette (no Tofas, Fiat, Renault, Murat, Sahin,
Dogan, Kartal). The plate and boot lettering read BOSFOR / ATMACA only.

## What makes it its own (not a copy)
- Lamps: front units are hexagonal "cut-corner" rectangles (upper inner corner chamfered), with a slim
  amber strip under each. Tail lamps are three stacked bars (red, amber, white reverse), wide and low on the tail panel.
- Grille: a full-width black band with eight vertical chrome slats and a thin chrome frame, no centre badge
  (a small BOSFOR bar sits on the lower edge).
- C-pillar: broad sail panel with three horizontal louvre slots, vertical rear edge of the rear door glass.
- Body side: a single crease at z 0.60 that runs the whole length, nothing else.
- Bumpers: slim wrap-around bars with rubber end caps (chrome on stock, black on modified).

## Dimensions (metres; Z up, nose -Y, origin at wheelbase mid-point, x right)
Length 4.30 (incl. bumpers), width 1.65 (mirrors tucked inside; modified 1.76 with flares), height 1.40
(modified 1.35, taxi 1.51 with the roof sign),
wheelbase 2.45 (front axle y -1.225, rear +1.225), front overhang 0.825, rear 1.025.
Stock: 165/80 R13 tyres (radius 0.295, width 0.165), steel wheels with chrome hubcaps, track 1.42,
ground clearance 0.17. Modified: lowered 0.05 m, 195/50 R15 (radius 0.2875, width 0.195) on 15 inch
five-spoke aftermarket rims, track 1.48, riveted-look flares, front lip, side skirts, ducktail boot spoiler,
tinted glass. Taxi: stock body, yellow, roof sign TAKSI (emissive, original shape), black sawtooth band.

## Variants (same body, same node names as the hero car)
1. `stock`: paint is chosen at runtime (cream default in the file; white, burgundy via paint_colour).
2. `modified`: the player's cheap starter. Sporty paint chosen at runtime.
3. `taxi`: yellow, traffic only.

Node names: body, glass, trim, interior, underbody, lights_front, lights_rear, plate_rear, wheel_FL..RR,
brake_FL..RR, col_body (extras collision_only). Wheel origin = wheel centre, outboard face at +X for the left
wheel, spin about local X. Materials: M_Paint, M_GlassClear (stock, taxi) or M_Glass (modified, smoked by the
engine), M_Trim, M_Chrome, M_LightFront, M_LightRear, M_Rim, M_Tire, M_BrakeDisc, M_Caliper, M_Interior,
M_Plate, M_TaxiSign (emissive, taxi only).

## Budgets (whole car, wheels included)
LOD0 at most 45 000 triangles, LOD1 15 000, LOD2 5 000 (no brakes, no interior at LOD2).

## Acceptance
Cycles renders (front34, rear34, side) of all three read as a believable, charming period sedan: flat
panels with crisp creases and soft bevels, no faceting, tyres filling the arches, straight window edges,
pillars thin. In-engine capture `car_studio_atmaca` shows the same. Dimensions within 3 percent.
