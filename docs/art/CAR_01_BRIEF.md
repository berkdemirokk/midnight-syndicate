# CAR 01 — "Noctra Sable R" asset brief

Owner: Art Director (Fable). This brief is the acceptance contract for the first hero car.
The car is an ORIGINAL design. Do not reproduce the silhouette, light signature, grille or
badge of any real car. No real brand names anywhere (mesh names, textures, plates).

## Identity
- Fictional maker: **Noctra**. Model: **Sable R**. Mid-engine two-seat street coupe, tuner culture.
- Mood: low, wide, predatory wedge. Reads clearly as a sports car in a 64 px silhouette.
- Signature (ours): thin full-width front light blade split by a centre notch, three short
  vertical "claw" tail lights per side joined by a thin bar, ducktail with a low fixed wing,
  deep side intake behind the door, twin centre exhaust inside the diffuser.

## Hard dimensions (metres, tolerance ±3%)
| item | value |
|---|---|
| overall length | 4.45 |
| overall width (body, no mirrors) | 1.96 |
| overall height | 1.19 |
| wheelbase | 2.66 |
| front track / rear track | 1.66 / 1.64 |
| front overhang / rear overhang | 0.95 / 0.84 |
| ground clearance | 0.11 |
| tyre outer diameter front / rear | 0.67 / 0.70 |
| tyre width front / rear | 0.255 / 0.315 |
| rim diameter | 0.50 |
| roof peak position | 46% of length from nose |
| windscreen rake | about 27 degrees from horizontal |

## Coordinate system (Blender)
- 1 unit = 1 m. Z up. Car nose points to **-Y**. X is left/right, symmetric about X = 0.
- Scene origin = ground plane, centred between the axles (midpoint of wheelbase).
- Front axle at Y = -1.33, rear axle at Y = +1.33. Wheels touch Z = 0.
- All object transforms applied (scale 1, rotation 0) except wheels, which keep their origin
  at the wheel centre.

## Required objects (exact names)
| object | content | material(s) |
|---|---|---|
| `body` | all painted panels, one continuous smooth shell, doors/bonnet/panel gaps as real grooves | `M_Paint` |
| `glass` | windscreen, side windows, rear window, slightly inset from the body | `M_Glass` |
| `trim` | splitter, side skirts, diffuser, wing, mirror housings, intake meshes, window surrounds | `M_Trim`, `M_Carbon` |
| `lights_front` | light blade lenses and inner emitters | `M_LightFront`, `M_Lens` |
| `lights_rear` | claw tail lights and bar | `M_LightRear` |
| `interior` | tub, dashboard, two seats, steering wheel. Low detail but must not look empty through glass | `M_Interior` |
| `underbody` | flat floor closing the bottom, wheel-well liners (dark, closed, no see-through holes) | `M_Trim` |
| `exhaust` | twin tips | `M_Chrome` |
| `plate_rear` | number plate carrying the text `NOCTRA` | `M_Plate` |
| `wheel_FL`, `wheel_FR`, `wheel_RL`, `wheel_RR` | tyre + rim, origin at wheel centre, spins about local X | `M_Tire`, `M_Rim` |
| `brake_FL` .. `brake_RR` | disc + caliper, separate from the wheel (they do not spin with it visually wrong; disc may be parented later in engine) | `M_BrakeDisc`, `M_Caliper` |
| `col_body` | convex collision hull, at most 48 vertices, not rendered | none |

## Shape quality rules (the part that decides pass/fail)
1. The body is ONE smooth, continuous surface with controlled highlights. No faceting, no
   pinching, no visible poles on the bonnet, roof or doors. Smooth shading with correct normals.
2. Real wheel arches: round openings concentric with the wheels, 35 to 55 mm gap to the tyre,
   a visible arch lip, and the body bulges outward over each wheel (haunches). The rear haunch
   is wider than the cabin.
3. The cabin (greenhouse) is narrower than the body, with tumblehome (side glass leans in),
   A-pillars, a roofline that falls into the tail (fastback), and a clear shoulder line.
4. The nose is low (leading edge about 0.42 m high), the bonnet rises to the windscreen base.
   The tail is high (deck about 0.86 m) and ends in a ducktail.
5. Panel gaps: doors, bonnet, engine cover and bumper joints exist as 4 to 6 mm grooves or
   as geometry edges that shade as gaps. Door handles, fuel flap optional.
6. Wheels: a multi-spoke rim with real depth (5 double spokes or 10 spokes, concave), a rim
   barrel, a centre cap, lug holes or nuts. Tyre has a rounded shoulder, a sidewall, and tread
   (geometry grooves or a normal map). No flat cylinders.
7. Nothing intersects visibly. Nothing floats. Symmetric left/right.
8. No primitive shortcuts: a box body, a cylinder wheel, or flat-colour-only final materials
   are an automatic fail.

## Materials (Principled BSDF, must survive glTF export)
| material | spec |
|---|---|
| `M_Paint` | base colour deep candy red `#8E0F1E`, metallic 0.85, roughness 0.32, clearcoat 1.0, clearcoat roughness 0.04, plus a fine flake normal texture (512 px, tiling) |
| `M_Glass` | dark tint `#0A0F12`, roughness 0.03, alpha blend about 0.35, metallic 0 |
| `M_Trim` | satin black plastic, roughness 0.55 |
| `M_Carbon` | carbon weave: base colour + normal texture (512 px tiling twill), roughness 0.35, clearcoat 0.6 |
| `M_Rim` | dark gunmetal, metallic 1.0, roughness 0.28 |
| `M_Tire` | rubber, roughness 0.85, normal map with tread and sidewall lettering `NOCTRA R-SPEC` (1024 px) |
| `M_LightFront` | emissive cool white `#DDEBFF`, strength 6 |
| `M_LightRear` | emissive red `#FF1A1A`, strength 4 |
| `M_Lens` | clear lens, roughness 0.05, alpha about 0.25 |
| `M_BrakeDisc` | steel with a radial brushed normal or roughness texture |
| `M_Caliper` | bright yellow `#F2C200`, roughness 0.4 |
| `M_Interior` | dark grey, roughness 0.7 |
| `M_Chrome` | metallic 1, roughness 0.12 |
| `M_Plate` | texture with the plate text |

Textures are generated by script (numpy / Blender image API), saved as PNG next to the GLB and
packed into the GLB. Power-of-two sizes, at most 1024 px. No downloaded textures for the car.

## Budgets
| LOD | triangles (whole car) | use |
|---|---|---|
| LOD0 | 45 000 to 90 000 | garage, player car close-up |
| LOD1 | at most 28 000 | rivals at mid distance |
| LOD2 | at most 7 000 | far traffic, reflections |
At most 14 materials, at most 20 draw-call objects at LOD0.

## Required outputs (inside your own attempt folder only)
```
build_car.py            the single generator script, deterministic, re-runnable
render_car.py           render rig (may be inside build_car.py)
validate_car.py         writes report.json
out/noctra_sable_lod0.glb, _lod1.glb, _lod2.glb    (glTF 2.0 binary, +Y up, textures embedded)
out/noctra_sable.blend
out/textures/*.png
renders/front34.png, rear34.png, side.png, top.png, wheel_closeup.png, front_low.png   (1600x900)
renders/contact_sheet.png   (2x3 grid of the six views, 2400x1350)
report.json
NOTES.md               what you built, defects you still see, what you would fix next
```

## Render rig (same for every attempt, so results are comparable)
- Dark studio: world colour `#05060A`, glossy dark floor (roughness 0.15) so reflections show.
- Three area lights: large soft key above front-left (cool white), long strip light along one
  side for a continuous highlight on the body side, warm rim light from rear-right.
- Camera 50 to 70 mm. Views: front three-quarter (eye height 0.9 m), rear three-quarter, pure
  side, top, wheel close-up (front left), low front (eye height 0.35 m).
- EEVEE for iteration is fine; final six views in Cycles (GPU if available, 96 samples, denoise)
  or EEVEE with ray tracing enabled. State which one you used.

## report.json fields
`attempt, blender_version, engine_used, dims {length,width,height,wheelbase}, tris {lod0,lod1,lod2},
objects_present [..], objects_missing [..], materials [..], textures [{name,size}],
non_manifold_edges_body, glb_sizes_bytes, glb_reimport_ok (bool), checks [{name, pass, detail}],
self_score {geometry, materials, wheels, details} (0-10 each, honest), known_defects [..]`

## Process rules
- Blender is at `C:\Program Files\Blender Foundation\Blender 5.3\blender.exe` (version 5.3.0).
  Run it in background: `blender.exe --background --factory-startup --python script.py`.
  Blender 5.x changed parts of the Python API (render engine names, node sockets, glTF exporter
  options). Never assume: probe with a tiny script (`dir()`, `bl_rna.properties`) and read the
  error text when a call fails.
- Look at your own renders with the Read tool after every build. Do at least four
  build → render → look → fix rounds. Record each round in NOTES.md with the defect and the fix.
- If a step fails, find the cause before re-running. Never re-run an unchanged failing command.
- Do not print large logs: redirect Blender stdout to a log file and read only its tail.
- Work only inside your attempt folder. Do not edit files outside it.
- Be honest in report.json. A truthful 5/10 is useful; an inflated 9/10 is a failure.
