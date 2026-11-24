# Stage 2A notes: Noctra Sable R details (details.py on body.py)

Build: `blender --background --factory-startup --python details.py` (logs in logs/). Renders in renders_stage2a/ (1600x900, EEVEE, 48 samples).

## Art lead rulings R1-R6 (applied in body.py)
- R1 tail: z_bot end (4.05,0.190),(4.45,0.400); ducktail z_top (4.20,0.872),(4.36,0.905),(4.45,0.915). Tail cap sliced at z 0.585/0.66/0.84, lower fascia is a 35 mm recess (M_Trim), lamp surround 8 mm recess.
- R2 glass from z_sh + 0.030 (side and quarter). Deviation: side glass still starts at s 2.02, not 1.62; windscreen takes s 1.36-1.98 and the A-pillar strip would otherwise be glass.
- R3 n_top cabin (1.45,3.0),(2.05,3.0),(3.00,2.9). Shelf unchanged.
- R4 wheel centres x 0.815 front, 0.800 rear (dummy wheels in details.py).
- R5 rocker below z_bot+0.085 is M_Trim (body face slots); door scallop 18 mm, centred 45% of side height, s 1.25-2.70, built inside _half() so the surface, normals and details agree.
- R6 key light 330 -> 200, top light 120 -> 70. Bonnet highlight is no longer clipped.

## Objects (14 at LOD0 before brakes; budget 20)
body (paint + trim slot: sills, pocket walls, mirror housing tops), glass, underbody, trim (splitter, skirts, strakes, wing, uprights, endplates, mirror bases and faces, door pads, antenna, lens housing, intake slats), lights_front (lens + 9 emitters per side), lights_rear (claws + bar), plate_rear (plate + NOCTRA letters as geometry), exhaust (chrome tips, dark mouths), interior (liner, floor, dash, binnacle, tunnel, 2 seats, wheel), wheel_FL/FR/RL/RR (dummy cylinders), col_body (33-vertex hull, hidden in render).
Triangles: 38.5k total at this stage (no tyre, rim or brake detail yet).

## Method
Every detail is a patch of S(s,v) or S(s,x) offset along the surface normal (add_thick). Recesses are pocket() cuts: faces are removed, the floor is offset inward and walls are built on the open boundary. Pockets: nose intake 30 mm, brake ducts 12 mm, side intake 60 mm, diffuser 35 mm, lamp surround 8 mm.

## Render rounds (four build, render, look, fix)
1. Interior boxes poked out above the shoulder (grey slab in side view); tail cap fan made star-shaped slivers. Fix: dark liner 30 mm inside the surface (s 1.40-3.06); horizontal cuts in the tail fan at z 0.585/0.66/0.84.
2. Tail reads as a dark recessed diffuser with painted upper band and claws in a dark surround; NOCTRA reads correctly from behind; side glass starts at the beltline; no see-through holes in top or low views; tyres inside the arches. Cabin too dark to read seats.
3. Interior base lifted to #4A4E56 (dark grey) for silhouettes; splitter end plates reduced to 6 x 70 x 50 mm.
4. Brake-duct pockets narrowed to 12 mm deep (still angular at the splitter edge).

## Known defects (honest)
- Cabin still a bubble (R3 applied, the shape is still tall); seats and wheel read only as dark silhouettes through the tint.
- Front light blade does not wrap the nose corner; it stops at the shoulder.
- Front lower intake: recess only, no mesh. Brake ducts are angular notches.
- Splitter follows the nose underside (z_bot + 3 mm), not the flat z 0.115 in the spec, because a flat plate would float under the nose tip.
- Side intake: stepped lower edge from the grid; sloped rear wall not built.
- Wing: cambered section, but uprights and end plates read as blocks at this detail level.
- Steering wheel sits in front of the left seat (not symmetric; interior only).
- M_Carbon has no weave texture; M_Paint has no flake normal; no tyre tread or rim (stage 2B).
- Dark trim (M_Trim, M_Tire) reads mid grey under the strip light. This is a rig effect; the lead should decide the light balance.
- Brake objects (brake_FL..RR) not built (stage 2B). Wheels are dummy dark cylinders at R4 positions.
- Lamp claws sit 2 mm behind the fascia plane inside the surround; the lens is not a separate lens object.

## Checks
body.py dimension checks pass (length 4.45, width 1.96, height 1.19, shoulders 0.772/0.888, bonnet 0.670; mesh length 4.512, +1.4%).
Self-score: geometry 6, details 5, materials 3, interior 3 (honest; the body is still the stage-1 shape with the rulings applied).
