# Kestrel GT-R (second car)

Same Blender surface engine as the Noctra Sable R (body.py grid shell, details.py, wheels.py,
textures.py, build_car.py), with its own curve data and layout. Brief: docs/art/CAR_KESTREL_BRIEF.md.

## Build, render, ship
```
blender --background --factory-startup --python build_car.py > logs\build.log     (about 15 s)
blender --background --factory-startup --python render_car.py -- cycles renders   (about 2 min, OPTIX)
blender --background --factory-startup --python validate_car.py > logs\validate.log
py -3.10 ship.py                      (copies the GLBs into game/, registers them in ASSET_MANIFEST.json)
```
`render_car.py -- eevee <dir> <views>` is the quick iteration loop (8 s for six views).

## What differs from the hero
- Stations: Y_OFFSET 2.305, length 4.70, axles at s 0.93 / 3.68 (wheelbase 2.75), windscreen s 1.85-2.50,
  roof peak s 2.75 (58%), fastback glass s 3.30-3.95 (one piece, 0.50 half-width), cabin blend 1.70-4.15.
- Curves: Z_TOP, Z_BOT, W_MAX, Z_SH, N_TOP, SHELF re-drawn (long bonnet, fenders stand 80 mm over the bonnet
  centre, deck 0.985 m). Z_SH is straight through the cabin so the belt plane cuts a clean window edge.
- Details: wide slatted mouth, slim wrap-round head lamp pods (4 lit cells each), bonnet louvre pocket with
  carbon slats, front fender gills, quad round tail lamps (ring, dark core, dot) on a lamp panel with the plate,
  7-strake diffuser, quad exhaust tips split about the centre, ducktail carbon lip (no wing), seat/dash layout moved
  rearward, parcel shelf under the fastback glass.
- Wheels: 20 inch (rim seat radius 0.254), 10 twisted turbine spokes, hex centre-lock nut (no lug circle),
  0.41 / 0.39 m discs, orange calipers. Tyre lettering KESTREL GT-R, plate text KESTREL.
- pre_slice() cuts each pocket outline into the grid first, so intakes have straight edges (the hero's are ragged).
- Interior liner: the rear patch starts at z 0.84, above the arch. The first build ran it through the rear wheel
  and showed a flat grey disc where the rim should be.
- SEG 48 (tyre, rim, discs) and 30 disc vanes keep LOD0 at 83.7k (hero uses 64 / 36).

## Numbers (validate_car.py, report.json: every check passes)
- Triangles: LOD0 83 665, LOD1 25 788, LOD2 6 799 (visible objects, col_body excluded). 17 draw objects, 15 materials.
- Mesh bounds 4.80 x 2.01 x 1.28 m (length includes the nose and tail caps, width includes mirrors).
- GLB sizes 7.2 / 4.7 / 3.6 MB.

## Known limits
- Body is not watertight (floor, arches and glass are split off, as on the hero): 10 958 open edges on `body`.
- Fender gill slats are almost invisible in the Cycles lights (black on black); they show in EEVEE.
- Head lamp pod is limited to s 0.20-0.34: a longer pod intersects the curving fender.
- Flank is a tall plain slab (belt 0.92-0.99 m); only a 26 mm door scallop breaks it.
- Tail lamp emission reads pale pink in Cycles (strength 4.0 on near-white-hot ring).
- No separate wing: the ducktail lip is the only aero piece besides the splitter and diffuser.
