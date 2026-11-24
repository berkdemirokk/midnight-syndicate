# CITY 01 road, Neon Wharf Loop: notes

Generator: `build_road.py` (Blender 5.3, deterministic, about 5 s without renders).
Run: `blender --background --factory-startup --python build_road.py -- --render`

## Outputs (road_out/)
- `city_01_road.glb`: 10.5 MB, no embedded textures, 13 named M_ slots, one colour set COLOR_0 (authored `Col`: R puddle, G groove wear, B district/4).
- `materials.json`: 13 slots, sRGB base, roughness, emission, UV note. Matches the GLB slot list.
- `city_01_centerline.json`: godot_y_up. 1102 samples at 1.9993 m, edges, grid slots, start line, 4 gates, control points, zebra positions.
- `report.json`: checks with their definitions, triangles and objects per kind.

## Checks (all pass; recomputed from the exported JSON)
- Lap length 2203.2 m (2200 to 2500).
- Min radius 28.56 m at s = 1817 m. Method: circumradius of 3 consecutive 2 m samples (strictest window). Margin to 28 m is only 0.56 m.
- Max gradient 2.66% (at most 6%).
- Non-adjacent closest plan approach, by minimum arc separation:
  - arc >= 150 m (the stated "non-adjacent" definition): 123.6 m (s 1943 and 2095).
  - arc >= 100 m: 87.9 m (s 1763 and 1865).
  - arc >= 45 m: 43.2 m (s 1791 and 1837), on the radius-30 m bend at control point 14. This is curvature, not a near pass, and it is below 45 m. Reported as is.
- Seam gap 2.0 m: the loop closes (wrap-around indices).

## Deviation from the brief
- One helper point added between control points 9 and 10, at (530, 20, 0), bulging the waterfront 20 m east. Lap was 2199.4 m without it. Brief control points are unmoved. Control point numbers keep their brief indices.

## Geometry
- Centreline: closed centripetal Catmull-Rom, z smoothed (sigma 6 m on samples). Banking up to 3 deg only in the sweep between points 7 and 9.
- Width 14 m, 16 m at points 15 to 17 with 40 m blends. Crown 1.5%.
- Road quads: 8 across, about 2 m along, UV in metres.
- Kerbs (M_Curb, 0.15 m, bevelled road edge), sidewalks 3.5 m, promenade 6 m with quay face to z = -1.2. Water plane 400 m east.
- Overpass (z > 0.8 m): fill walls, 0.9 m parapets with steel top rail, expansion joints.
- Underpass (points 11 to 14): ceiling 5.2 m clear over the road, spanning exactly between the two wall lines, side walls, ceiling light strips (M_TunnelLight), amber wall stripe, portal frames.
- Trench retaining walls on the ramps, with a 2 m street-level rim ledge.
- Ground: 12 m cells, 250 m margin. Cells touching the trench, tube or bay are split into 2 m sub-cells, and a sub-cell is kept only if all corners are outside.
- Markings at 5 mm: dashed lanes, edge lines, checkered start/finish, 8 grid boxes, 3 arrows x 2 lanes before T1, 4 zebra crossings (stripes along the traffic direction), hairpin chevrons on the outside.
- 24 manholes and 16 grates, seeded, 3 mm above the road.
- Collision: invisible 3 m `wall_XX-colonly` loops on both building lines, double-sided. Road, sidewalk and structure chunks are `-col`.

## Triangles (89 844 total, 19 chunks of about 120 m)
road 30 856, ground 21 122, markings 12 036, structure 11 130, wall 8 816, sidewalk 4 914, decals 464, water 506.

## Fixes this round
- Kerbs were written with M_Asphalt. Now M_Curb.
- Underpass wedge in view_underpass.png: the ground mesh poked through the tube and trench footprint (12 m cells). Fixed by the sub-cell cut. Confirmed by object-family isolation. The ceiling also spanned the wrong width on the promenade side; fixed.
- Non-adjacent check: now stated with its definition and three thresholds. Recomputed from JSON.
- Radius check: now the 3-point circumradius method.
- Back faces of double-sided walls shared vertices and Blender reported 26 meshes invalid. Now separate geometry, no warnings.
- GLB: the colour export used defaults, so the authored data went to COLOR_1 and COLOR_0 was flat white. Now COLOR_0 only, and it carries the authored values.
- Top map: labels moved clear of P-markers, framing widened, sun raised obliquely, glossy water toned for the QA render only, label shadows removed.
- Overpass view moved to the straight climb (points 5 to 6) with 35 mm lens, so both parapets read.
- Zebra crossings were transverse bars (ladder). Now stripes along the traffic direction; new street view view_zebra.png.
- Hairpin view moved closer to the apex for the chevrons.

## Known defects and open items
- Not built (outside this task's list): jersey barriers, guardrails, chevron boards, waterfront railing, amber portal lights, buildings and props. The street views are bare road, kerbs, walls and markings. Scope gap, not a road defect.
- Start/finish checker band is in the geometry but not clearly legible in the start grid view.
- Chevrons on the hairpin read as a row of short white bars at street level; a dedicated close-up would be needed to judge the shape.
- Water edge at the span ends is not blended. Water reads near black in the QA top map (roughness lowered for QA only; the GLB keeps 0.05).
- Renders use EEVEE, temporary dark wet asphalt and placeholder point lights, not the final night lighting.
- The wall loops are colliders only: visible in Blender QA, hidden in the top map and street views.
