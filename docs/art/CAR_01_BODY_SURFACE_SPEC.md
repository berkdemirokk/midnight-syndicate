# CAR 01 — body surface design data (Noctra Sable R)

Owner: Art Director (Fable). This file is the SHAPE of the car as numbers. The generator
implements it literally; proportions are not to be re-invented. It refines CAR_01_BRIEF.md
(which still rules object names, materials, budgets, outputs and the render rig).

## Parameters
`s` = distance from the nose tip along the car, 0 .. 4.45 m. Blender `y = s - 2.28`
(front axle s = 0.95, rear axle s = 3.61). `x` = half-width coordinate, `z` = height.
All curves below are given as control points `(s, value)` and are interpolated with a
C1 monotone cubic (PCHIP). Do not use a spline that overshoots.

### Longitudinal curves
| curve | control points (s, value) |
|---|---|
| `z_top` centreline top (bonnet, windscreen, roof, deck) | (0,0.400) (0.10,0.470) (0.40,0.575) (0.95,0.670) (1.28,0.760) (1.60,0.950) (1.90,1.130) (2.05,1.190) (2.40,1.170) (2.80,1.080) (3.30,0.975) (3.80,0.900) (4.20,0.875) (4.38,0.895) (4.45,0.885) |
| `z_bot` underside | (0,0.220) (0.15,0.135) (0.50,0.110) (3.70,0.110) (4.05,0.165) (4.45,0.300) |
| `w_max` widest half-width (plan view) | (0,0.620) (0.06,0.775) (0.25,0.880) (0.95,0.972) (1.50,0.930) (2.30,0.918) (3.00,0.952) (3.61,0.980) (4.10,0.950) (4.40,0.900) (4.45,0.860) |
| `z_sh` shoulder / fender crest height | (0,0.380) (0.12,0.495) (0.50,0.655) (0.95,0.772) (1.40,0.760) (2.00,0.742) (2.70,0.780) (3.20,0.850) (3.61,0.888) (4.10,0.865) (4.45,0.845) |
| `n_top` top-surface exponent | (0,2.0) (1.10,2.2) (1.45,3.4) (2.05,3.6) (3.00,3.3) (3.70,2.4) (4.45,2.0) |
| `shelf` flat shelf between shoulder and glass base | (0,0.0) (1.20,0.0) (1.55,0.055) (3.00,0.060) (3.70,0.0) (4.45,0.0) |

### Cross-section at a given s (half section, x >= 0), as a function of v in [0,1]
Let `H = z_sh - z_bot`, `xs = w_max - 0.115` (where the shoulder top ends).
Build the section as a smooth polyline through these anchors, in this order, then resample it
to a fixed number of points by arc length (keep more points on the shoulder and roof edge):

1. floor centre `(0, z_bot)`
2. floor edge `(w_max - 0.130, z_bot)`
3. rocker corner `(w_max - 0.065, z_bot + 0.045)`
4. lower side `(w_max - 0.022, z_bot + 0.30 H)`
5. widest point `(w_max, z_bot + 0.62 H)`
6. upper side `(w_max - 0.018, z_sh - 0.060)`
7. shoulder break `(w_max - 0.060, z_sh - 0.012)`
8. shoulder top `(xs, z_sh)`
9. top surface from `x = xs` to `x = 0`:
   `x_g = xs - shelf` is where the rise starts (the shelf falls `drop = 0.005 * min(1, shelf / 0.03)`
   inward, so the drop fades in with the shelf and never appears as a step);
   for `x <= x_g`: `q = (x_g - x) / x_g`, `z = z_sh + (z_top - z_sh) * (1 - (1 - q)^n_top)`.
   (Bonnet: `z_top < z_sh`, so the surface drops from the fender crest to a flat bonnet = fenders
   stand proud. Cabin: `z_top > z_sh`, steep side glass that rolls into a flat roof = tumblehome.)

Round anchors 2-3 and 6-8 with a Catmull-Rom/Bezier pass so there are no hard creases except
the deliberate shoulder break (keep it as a soft but readable character line).
Suggested density: 132 stations along s (denser near s 0-0.3, 1.2-2.1 and 4.2-4.45),
46 points around the half section. Mirror on X, weld the centreline.

### Nose and tail closure
- Nose: add five extra stations ahead of s = 0 that shrink the s = 0 section toward its own centre
  on an ellipse: for k = 1..5, a = k/5 * 80 degrees, scale = cos(a), forward offset = 0.045 * sin(a);
  shrink z fully but keep x scale at least 0.55 (the nose is a wide blade, not a point). Close the
  last ring with a grid fill. Result: a soft rounded leading edge, no flat plate, no pinching
  (the lead's first prototype pinched here with only two stations).
- Tail: at s = 4.45 keep the section, add one station 18 mm further back scaled 0.965, then cap
  flat (grid fill). The flat rear fascia carries the lights and plate.

### Checks the generator must print (fail the build if off by more than 3%)
length 4.45, width 1.96 (2 x max of w_max), height 1.19, shoulder at front axle 0.772,
shoulder at rear axle 0.888, bonnet centre at front axle 0.670 (lower than the fender crest).

## Wheel arches (boolean, gives closed wheel wells for free)
For each wheel subtract a cylinder with its axis along X: centre `(y_axle, z = tyre radius)`,
radius = tyre radius + 0.048, running from `x = 0.50` to `x = 1.30` (mirrored). Use the EXACT
boolean solver on the closed body. The cylinder's inner surface becomes the wheel well: assign
those faces to `M_Trim` and put them in the `underbody` object. Then bevel the arch rim edge
(the edge loop between paint and well faces) 7 mm with 2 segments to form a lip.
After the boolean: shade smooth by angle 35 degrees and add a Weighted Normal modifier, so the
big panels keep clean highlights.

## Panel lines (do them BEFORE the boolean, while grid indices are intact)
Grooves 5 mm wide, 5 mm deep: select the edge path, bevel 2.5 mm with 2 segments, push the new
middle vertices inward along the normal by 5 mm. Paths:
- door front cut: station nearest s = 1.52, from the rocker corner up to the shoulder top;
- door rear cut: s = 2.58, same span, then it turns forward along the shoulder for the top of
  the door (follow the shoulder-top line between s 1.52 and 2.58);
- bonnet shut line: a U shape, across the car at s = 0.22 between the two fender crests' inner
  edges (x <= 0.62), then back along x = 0.62 to s = 1.22;
- engine cover: a rectangle x <= 0.50 from s = 3.05 to s = 4.05;
- front and rear bumper joints: around the section at s = 0.42 and s = 4.02 from rocker to shoulder.

## Glazing (flush glass, split by parameter ranges; keep paint between as pillars)
Faces whose centre falls in these ranges go to the `glass` object (`M_Glass`), offset inward 2 mm:
- windscreen: s 1.36 .. 1.98, x <= `x_g - 0.07` (A-pillars remain paint, about 70 mm wide);
- side windows: s 1.62 .. 2.62, on the rising side-glass part only: z between `z_sh + 0.035`
  and `z_top - 0.075`, and x >= the roof edge (where the local surface slope is steeper than 30
  degrees from horizontal). B-pillar: leave s 2.62 .. 2.74 as paint; quarter window s 2.74 .. 3.02;
- rear screen / engine glass: s 2.62 .. 3.02, x <= 0.42.
The roof panel between windscreen top and rear screen stays paint (optionally `M_Carbon`).

## Surface-conforming details (evaluate the same surface function, offset along the normal)
Because the body is a function `S(s, v)`, every detail below is a patch of that function, offset
outward 3 mm (lenses 4 mm) and given thickness, never a floating box:
- front light blade (`lights_front`): band on the nose from s = 0.035 to 0.085 along the section,
  from x = 0.16 to x = 0.74 each side (centre notch of 0.32 m), following the shoulder line down
  around the corner. Inside it 9 small emitter cells per side under a clear lens;
- front lower intake (`trim`, dark mesh): on the nose cap, x <= 0.55, z 0.24 .. 0.34, recessed 30 mm;
- side intake behind the door (`trim`): a recessed scoop on the body side, s 2.66 .. 3.10,
  z from `z_bot + 0.36 H` to `z_bot + 0.72 H`, cut 60 mm into the body with a sloped rear wall
  and a dark mesh at the back;
- rear lights (`lights_rear`) on the flat rear fascia: per side three vertical claws 0.028 m wide,
  0.115 m tall, 0.045 m apart, starting at x = 0.50 outward, centred at z = 0.74, plus a thin
  10 mm bar joining left and right at z = 0.80;
- plate recess centred at z = 0.56, 0.36 x 0.12 m; the text NOCTRA must read correctly from
  behind the car (check for mirroring in the render);
- door handles: flush 0.16 x 0.025 m pads at s = 2.40, z = z_sh - 0.07;
- mirrors (`trim` + paint cap): on short arms at s = 1.58, x = w_max - 0.03, z = z_sh + 0.06,
  housing 0.20 x 0.11 x 0.09 m, teardrop, rounded.

## Aero and underbody (trim)
- front splitter: 25 mm thick plate following the nose plan curve, 45 mm proud of the nose,
  from s = -0.03 to 0.32, at z = 0.115, with two small end plates;
- side skirts: blade under the rocker from s = 1.30 to 3.15, 30 mm proud of the rocker, 60 mm tall;
- diffuser: from s = 3.95 to 4.47, rising with `z_bot`, five vertical strakes, twin exhaust tips
  (60 mm diameter, 90 mm apart, centred) inside a dark recess at z = 0.33;
- ducktail is in `z_top` already; add a low fixed wing: span 1.50 m, chord 0.24 m, real aerofoil
  section, at s = 4.22 .. 4.46, underside 0.10 m above the deck, on two swan-neck uprights at
  x = +-0.48; end plates 0.26 x 0.12 m.
- underbody: flat floor (already part of the closed body: assign floor faces to `M_Trim`).

## Wheels (replace any fan-blade rims)
- Tyre: revolve a cross-section polyline (64 segments around): flat tread with a 6 mm crown,
  four circumferential grooves 9 mm wide and 6 mm deep, rounded shoulders (radius about 22 mm),
  sidewall with a slight bulge, bead meeting the rim. Sidewall height: (tyre diameter - 0.50) / 2.
- Rim (rim diameter 0.50): barrel with inner and outer lips (lip 14 mm), FIVE twin spokes
  (ten blades in five pairs, pair opening 14 degrees), each blade tapered (38 mm wide at the hub
  to 24 mm at the barrel, 26 mm deep), CONCAVE: blades meet the barrel 12 mm inboard of the outer
  lip and sweep inward to a hub face 55 mm inboard; bevel every blade edge 2 mm. Hub 0.150 m
  diameter with a centre cap carrying a small original emblem (a plain ring with a notch) and
  five lug nuts on a 0.112 m circle. Rear rim is 10% deeper (more concave).
- Brake: ventilated disc 0.38 m (front) / 0.36 m (rear), 30 mm thick with a visible vent gap,
  drilled-hole pattern as a texture or geometry, hat in dark metal; caliper 0.22 m long, a rounded
  block wrapping the disc edge at the trailing upper side, bright yellow, with a recessed panel.
- Each wheel object's origin is at the wheel centre; left wheels are mirrored copies with the
  spokes mirrored (not rotated), so spoke direction is symmetric.

## What the lead will check in the renders
1. Side view: wedge nose, fender crest above the bonnet, roof peak at 46%, fastback into a
   ducktail, wheels fill the arches with an even 45 to 50 mm gap.
2. Front three-quarter: bonnet valley between proud fenders, a clear shoulder line running into
   the rear haunch, flush glazing with visible A and B pillars.
3. Highlights from the strip light run unbroken along the body side.
4. No boolean artefacts (black triangles, torn shading) around the arches.
5. Lights, intakes and the plate sit ON the surface. Text reads correctly.

## Proof of the data
`assets_src/vehicles/noctra_sable/proto/body_proto.py` is the lead's clay prototype of exactly
these curves (PCHIP, section builder, exact-boolean arches). It renders a correct sports-car
silhouette (see `proto/renders/`). Start the final generator from its `pchip`, `section` and
`cut_arches` functions; fix the two known prototype flaws listed above (nose closure, shelf step).
