# Hero car engine integration (Noctra Sable)

Owner: car_godot agent. Code: `game/vehicles/noctra_sable/`, `game/tests/test_car_asset.gd`, `game/devtools/scenarios/car_studio.gd`.
Re-ship after every car build: `py -3.10 tools/ship_assets.py` (copies the three LOD GLBs, checks sha256, registers them in ASSET_MANIFEST.json with tris and material counts read from the GLB).

## Import facts (Godot 4.7.2 glTF importer, probe on the shipped LOD GLBs, final ship sha 0e60.. / 2a82.. / 8bf6..)
- KHR_materials_emissive_strength: imported. M_LightFront emission 6.0, M_LightRear 4.0.
- KHR_materials_clearcoat: listed in the GLB, NOT imported. Every M_Paint, M_Carbon and M_Pillar arrives with clearcoat_enabled = false.
  CarMaterials sets clearcoat in code. This answers BLOCKERS.md B6: emissive yes, clearcoat no.
- Normal maps: imported (paint flake 512, tyre 1024, carbon 512, brake, lens, plate).
- Metallic and roughness factors: imported. M_BrakeDisc roughness is driven by a texture.
- Alpha: M_Glass alpha 0.35 and M_Lens alpha 0.25 imported as alpha blend.
- M_Rim source albedo is (0.31, 0.33, 0.37). CarMaterials used to override it to 0.08 (read as black); now it keeps the source value.
- Node names survive as MeshInstance3D names. No animations, no skins.

## Geometry (LOD0, col_body excluded, test_car_asset this session)
- Bounding box: 1.95 x 1.19 x 4.546 m (X, Y, Z). Brief 1.96 x 1.19 x 4.45. All within 3%.
- Wheel origins at wheel centres, checked by test (front axle 1.33 m ahead, rear 1.33 m behind, radii 0.335 / 0.35).
  Only origins are checked, not that each wheel mesh is centred on its origin.
- Triangles, from the shipped GLBs: LOD0 86 397, LOD1 27 498, LOD2 6 799. Budgets: 45k-90k, 28k, 7k. All pass.

## Materials: OPEN BLOCKER
- LOD0 has 15 material names (test: "LOD0 uses 15 materials, max 14"). The brief budget is 14 (CAR_01_BRIEF.md, Budgets). Test FAILS: test_triangle_and_material_budgets.
- The extra one is M_Pillar (gloss black pillars), added in assets_src/vehicles/noctra_sable/final/details.py:400 ("material count 15, per the lead").
  Not in the brief's material table. The fix belongs to the asset side: give pillar faces M_Trim or M_Carbon, or the lead changes the budget.
  Not fixed here: assets_src is not in this agent's ownership, and the test is not loosened.
- Re-ship records material_count from the GLB (15 for LOD0, 15 LOD1, 12 LOD2).

## Scene contract (noctra_sable.tscn, root `CarLod`, Node3D)
- Children LOD0, LOD1, LOD2 hold the GLB models. Every required node exists in LOD0.
- Distance switching by visibility_range on each MeshInstance3D: LOD0 0-22 m, LOD1 22-70 m, LOD2 70 m+, 2 m dithered fade on LOD0 and LOD1.
- `force_lod0` (player, garage) and `force_lod` (capture, tests) draw one LOD only, with no range.
- col_body is hidden in every LOD and casts no shadow.
- Shadow casters: body, underbody, trim, four wheels. Lamps, glass, brakes, plate, exhaust do not cast.
- `get_wheel_nodes()` and `get_brake_nodes()` return the active LOD's nodes. `get_active_lod()` follows camera distance.

## Materials (car_materials.gd, by material name)
- Per car (never shared, so paint does not leak): M_Paint, M_Rim, M_LightRear.
- Shared and cached by name: the rest.
- M_Paint: metallic 0.85, roughness 0.32, clearcoat 1.0 at roughness 0.04, flake normal 0.12, tiled 4x.
- M_Glass: alpha 0.35, roughness 0.03, depth write off, render priority 1 (drawn after opaque). Only this order was checked.
- M_LightRear: 0.6 at rest, 4.0 braking (`set_brake_lights`). CarVisual also drives this material.

## Capture studio (car_studio.gd, evaluation only)
- Three look-and-fix rounds this session: rim albedo restored to source value (metal reads grey-silver, not black);
  graphite paint lifted to (0.2, 0.21, 0.23); light bar emission 4.0 -> 1.2.
- Shots and perf JSON: `evidence/screens/car_studio/`.
- Still visible: the overhead light bars clip to white across the top of paint_variants; glass shows only a faint interior;
  the floor shows light blobs (spot and omni highlights) more than bar reflections.

## Known defects outside this agent's ownership (not fixed here)
- car_visual.gd `setup()` uses `find_child` on the whole model, so it always finds LOD0's wheels. When LOD1 or LOD2 is visible,
  the visible wheels do not spin or steer. Fix: take wheels and brakes from `get_wheel_nodes()` / `get_brake_nodes()` each time the active LOD changes.
- test_race_scene.gd test_paint_sets_body_albedo reads 'Visual/DevCar/body', which is null now that the race config uses noctra_sable.tscn.
  The test raises SCRIPT ERROR and still reports PASS.
- test_vehicle.gd test_slope fails in the full suite. Not checked here whether the car caused it.
