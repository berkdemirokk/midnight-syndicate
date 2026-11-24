# CITY 01 engine assembly

Owner: Environment Agent. Code: `game/world/city_01/`. Tests: `game/tests/test_city_01.gd`. Source of truth:
`game/assets/world/city_01/city_01_layout.json` (copy of the layout, Godot coordinates).

## Node tree (`city_01.tscn`, root script `CityBuilder extends Track`)
```
City01 (CityBuilder)            Track contract; builds everything in _ready from the layout JSON
  Geometry
    Road                        city_01_road.glb, library materials, ground collider removed
    FirstRow                    148 building instances (LOD0/1/2 children with visibility ranges, occluder each)
    SecondRow                   10 MultiMeshInstance3D (LOD2 boxes, 51 instances)
    Props                       840 MultiMeshInstance3D (per chunk, category and LOD band)
    Colliders_00..18            one merged StaticBody3D per 120 m chunk (368 prop shapes, incl. 126 railing boxes)
    FallFloor                   box 6000 m at y -30 (catches a car that leaves the walls)
  RacingLine (Path3D)           closed Curve3D, 551 points, Catmull-Rom handles
  StartGrid                     Grid0..Grid7 Marker3D, -Z = race direction, origin = car rest height (+0.47 m)
  Checkpoints                   CP0 start line, CP1..CP3 gates; Area3D, layer 3, mask vehicles
  Lighting
    WorldEnvironment            fog, ACES tonemap, glow, blue-black sky colour, ambient colour
    <lights>                    SpotLight3D (lamp heads, accents), OmniLight3D (neon, tunnel, strings)
    ReflectionProbes            37 ReflectionProbe, box projection, update once, interior off
```

## How things are built
- Buildings: `bld_*.glb` per layout instance; `MaterialLibrary.apply(root, asset)`; LOD0 to 70 m, LOD1 to 180 m,
  cross-fade 4 m (`FADE_SELF`). Collider is the importer's `-colonly` trimesh (checked by ray).
- Second row: one MultiMesh per building type, LOD2 mesh with library materials, no range end.
- Props: one MultiMeshInstance3D per (file, chunk, category, mesh child). Range: furniture 0-90 m, circuit/lamp/
  sign/overhead 0-250 m, bay unlimited. Files with `_lod1` split at 60 m (near LOD0, far LOD1, 4 m fades).
- Props without a collider in the GLB (quay railings) get a box from their mesh AABB.
- Lights: layout energy x 0.35, colour from hex, no shadows, distance fade from 70 m over 30 m. Lamp heads 55 deg cone.
- Occluders: one BoxOccluder3D per first-row building, 90 % of the collider box, at its centre.

## Light budget (Mobile: 8 omni + 8 spot per mesh)
- Volumes: every road piece, building LOD0 and near prop MultiMesh (678 AABBs). Ground, decals, markings and water
  are excluded because their AABBs cover the circuit. Far groups are excluded (lights are faded there).
- Layout has 178 lights. Before budget: worst volume 13 omni, 15 spot. 28 lights dropped (nearest kept per volume).
- Kept: 150 lights. Test recount of the built nodes: worst per mesh 8 omni, 8 spot (limit 8). Log lines in `light_report`.
- Reflection probes: worst per mesh 3 (limit 8).

## Results (dev PC, RTX 5060 Ti, desktop, Mobile renderer, headless test run)
- Scene load (`_ready`): about 1.2 s. Test limit 5 s.
- Counts: 1127 instances (148 + 51 + 928), 850 MultiMeshes, 368 prop collider shapes, 148 occluders, 37 probes,
  150 lights built, 0 unbound materials, 0 missing props.
- Track length 2184.5 m vs layout 2203.2 m (0.85 %, inside the 1 % limit; Catmull-Rom handles shorten the curve).
- Ground rays: 60 of 60 line samples hit road, worst height difference 0.13 m. Grid: 8 of 8 found.
- Side walls: 6 pushes per side at 22 m/s for 2 s. Stop lateral 13.2 m left, 9.1 m right; none fell.
- AI lap (skill 1.0, one car): 63.9 s, max 6.41 m from the road centre (kerb at 6.8 m), 0 stuck events.
- Eight cars on grid: min gap 8.75 m, rest error 0.00 m.
- Draw calls: the race_dev capture (full race scene, HUD, car) gave 379 draw calls and 300 926 primitives at the
  racing shot. The brief target is 350 draw calls; this is over it. Frame average 2.7 ms at 368 fps, dev PC only.

## Known gaps (not done or not right)
- An 8-car race does not finish in 170 s headless. Stuck events remain with prop colliders removed (12 vs 14),
  with road walls removed too (13), and with AI traffic disabled (5). A single car is clean. Not isolated; likely
  car-to-car physics or the AI. Not fixed: AI code is read-only here.
- Overpass guardrails sit at about +6.6 to +6.8 m and -8.0 to -8.5 m from the racing line, leaving almost no
  clearance at the kerb. Layout issue (guardrail offset 7.25 m), not moved by the engine.
- Ground collider removed: it sat at -0.3 m above the underpass approach and dropped the car about 0.3 m at 1378 m.
  Road and sidewalk colliders cover the drivable surface now. The layout owner should check the ground mesh there.
- `test_race_scene::test_autopilot_completes_one_lap_with_results` now fails: it expects the dev watermark, which
  race_scene.gd only creates on the dev circuit. The city exists now, so the check is stale. Owner must update it.
- No city capture scenario: devtools is not owned here. Only race_dev shots exist as harness evidence.
- Sign facing: `flip_signs` is false. Checked only from the chase camera (readable); not checked in a side view.
- Light energy scale 0.35 and fog density are unverified beyond the race_dev shots. Sky is a flat colour, the CC0 HDRI is not tested.
- Waterfront side wall: the stop at 13.2 m is an unidentified obstacle, not the 19.8 m quay railing.
- Second-row and far props are outside the light budget (their lights are faded beyond about 100 m).
