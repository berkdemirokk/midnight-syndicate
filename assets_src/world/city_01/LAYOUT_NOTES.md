# CITY 01 layout: notes (Environment Agent, fix round 2)

Generator: `build_layout.py` (py -3.10 + numpy, about 15 s). Output: `layout_out/city_01_layout.json` (godot_y_up, 394 KB).
Preview: `build_layout_preview.py` (Blender 5.3, EEVEE, about 10 s for all 7 renders). Run:
`"C:\Program Files\Blender Foundation\Blender 5.3\blender.exe" --background --factory-startup --python build_layout_preview.py --`

## Conventions
- Each instance: `position` (godot m), `yaw` (rad about +Y), local +Z = front. Buildings face the road.
- Building local frame: facade at z = 0, body to z = -depth, canopy to z = +1.45.
- Lights: `type`, `position`, `direction` (spots), `color`, `energy`, `range`, `shadows: false`, `district`, `s_offset_m` (nearest lap offset).
- Racing: grid, start line, gates, lap length copied from the road file; racing line every 4 m (551 points).

## Fixed in this round
- Waterfront tower: a building now needs its whole footprint span inside the district of its pool. The 44-storey Downtown tower
  that spilled into the Waterfront is gone. Waterfront now has 10 low buildings (1 storey warehouses, 5 storey parking).
- Neon Strip: pool excludes buildings under 8 storeys (MIN_STOREYS). Neon storeys now 8 to 19.
- LOD2-only boxes now carry width_m, depth_m, height_m and row_back_m.
- Downtown interior: LOD2 boxes at 30 m and 60 m behind the first row (25 Downtown LOD2 boxes, was 8). Still sparse, see open items.
- Light count: check now reports 3D and plan (x,z) counts and the larger of the two. Worst case: 24 (plan) at lap offset 571.8 m,
  22 (3D). Target 24 met, with no margin.
- Preview: bay water plane on the open-water side from the quay face outward, fog colour #101A2E as the sky stand-in for mist.

## Buildings
- First row 148: Neon 64, Old Market 44, Downtown 30, Waterfront 10.
- Gaps: 0.5, 1.0 or 1.5 m (88%), 4 to 6 m alleys (12%). Market stalls go into 5 Old Market alley gaps.
- Rejects: footprint wall points closer than 10.0 m to the centreline (canopy 8.0 m), SAT overlap with any placed footprint plus 0.5 m margin,
  underpass (district 3) and trench (y < -0.8) within about 12 samples, water side for the open-water (left) line.
- Second row: 51 LOD2-only boxes (Neon 26, Downtown 25): 30 m behind a first-row facade, and a 60 m row in Downtown.
- Coverage (building line within 6 m of a facade, 2 m samples): left 56.4% overall, 93.8% of eligible length; right 76.3% overall, 97.2% eligible.
  Eligible excludes underpass, trench and the water side.
- Downtown first-row bases at y 0.0 beside the overpass deck (up to 3 m). No viaduct fill or columns are placed by this layout.

## Props (928 instances)
- Lamps: 46 posts every 28 to 32 m alternating sides; sodium in Waterfront and Old Market, LED double in Neon and Downtown; none in the tunnel or on the overpass.
- Tunnel: 29 ceiling omnis every 12 m, 58 wall fixtures, 6 fans every 60 m (right wall only).
- Signs: fascia boxes and blades on anchors (Neon 90%, Market 50%, Downtown 15%); 8 rooftop 12x5 billboards on tall land-side buildings.
  Blade text faces one way; the flipped copy relies on a 1.4 m offset not checked in renders.
- Street: 47 jersey barriers on corners, 126 quay railings and 17 promenade barriers on the Waterfront, 178 guardrail segments on the overpass at offset 7.25 m,
  6 chevron boards (apexes at samples 253, 505, 993), 30 cones and traffic cones at the start, 24 zebra items (traffic lights and bollards),
  3 bus shelters, 11 litter bins, 7 planters, 4 hydrants, 2 benches, 2 newspaper boxes, 1 cabinet.
- Overhead: 17 string-light spans across Old Market every 20 m, 5 cable spans sparsely in Neon.
- Bay: 2 container stacks, 2 gantry cranes, 2 skyline cards (bay east at offset 430 m, Downtown outer side at 330 m).

## Lights (178)
- Lamp heads 71, neon fills 40 (cap, largest signs, range 10 to 14 m), tunnel omnis 29, string lights, traffic lights, landmark accents 6, crane lights, bus shelter panel.
- Lamp heads range 22 m (brief). String lights keep one of four bulb hints (shortcut, holds the light count).

## Reflection probes: 37 boxes, 60 m apart, extents 10.5 x 12.5 x 30 m (tunnel 10.5 x 2.6 x 30 m).
## Budget (40 viewpoints, 1.4 m eye, race heading, 70 deg hfov, 350 m far, LOD0 < 60 m, LOD1 < 160 m, LOD2 beyond)
- Triangles: worst 202 481 (target 450 000): PASS. Includes road 89 844.
- Draw calls before instancing: worst three 852, 905, 864 (by triangles); peak 991. Target 350: FAIL.
- Draw groups after instancing (asset and LOD, 5 to 49 across viewpoints) are the number the engine needs with MultiMesh. Not verified in the engine.

## Blender preview (layout_renders/, 1600x900, EEVEE, LOD0 only)
- Seven renders (top map, five street views, 60 m establishing). neon_strip.png reads well; waterfront.png is still weak (see open items).

## Known defects and open items
- Draw calls before instancing: peak 991 vs 350 target. Needs merging of per-building parts or a MultiMesh pass in the engine. Not done.
- Downtown interior: 25 LOD2 boxes at 30 m and 60 m, scattered. The loop interior is still largely open. Towers there are not done.
- Waterfront street view: 10 low buildings and sodium lamps every 30 m on the land side. Lamps read only within about 60 m and the bay is almost invisible in EEVEE. Not done.
- Downtown viaduct fill and columns not modelled (overpass deck up to 3 m above building bases).
- Coverage on the left line is 56.4% overall. The rest is the water side and the underpass by design.
- Mist: EEVEE here has no volumetric fog. The #101A2E sky is only a stand-in.
- Reflection probes are placed in the file but not rendered. The engine must check them.
- Posters (6 textures) are not placed on facades or roof billboards.
- Parked-car slots and car LOD2 are not placed (brief: filled later).
- Overpass guardrails at offset 7.25 m may clash with the road GLB parapets. Not checked against the parapet geometry.
- Racing line: smoothed Gaussian shift, max shift 3.48 m (limit 4.5 m). Not driven.
- Far skyline towers beyond the second row are not placed, only the two skyline cards.
- Centreline helper point at (530, 20, 0) is from the road agent's file, not this layout; the Waterfront bulge follows from it.
