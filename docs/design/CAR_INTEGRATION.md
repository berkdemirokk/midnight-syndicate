# Hero car engine integration (Noctra Sable)

Read first (2026-11-27): the sections down to "Noctra Sable R round 9" describe the project-made Blender models. Those
models are no longer in the game for the player's cars: all eleven cars of the shop are licensed CC BY 4.0 models now
(see the last two sections). The scene contract, the node names and `car_lod.gd` / `car_materials.gd` are unchanged.

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

## Noctra Sable R round 9 (greenhouse, wing)
- Node names and wheel/brake setup unchanged. Ship via tools/ship_assets.py (SHIP OK); ASSET_MANIFEST.json re-registered.
- Triangles: LOD0 86558, LOD1 27493, LOD2 6797. Height 1.155 m (within 3% of 1.19 m).
- Engine: the body still carries the glass, col_body (collision_only) and wheel/brake nodes as before.

## Licensed cars: part colours and baked shade (2026-11-27)
Why: a source model from vinish.dev has about 60 materials (chrome, projector glass, amber lamps, tan leather, yellow
calipers, black seals). The contract has 14 engine materials, and the first conversion painted every part of a group one
flat colour: white lamp discs, grey grille boxes, one-grey interiors. That, not the triangle count, made the cars look cheap.
- `assets_src/pipeline/prepare_vehicle.py` writes a vertex colour (COLOR_0) on every face. `VC_TARGETS` has six
  materials: for M_Trim, M_Chrome, M_Interior, M_BrakeDisc and M_Caliper the colour is the source material's colour
  times a baked shade; M_Rim carries a shade instead (see Rims) times the baked shade. Every other material gets
  white. Surfaces and draw calls are the same as before.
- Source colour: the glTF base colour factor times the mean of the base colour texture. A cut-out texture (alphaMode
  MASK or BLEND) is weighted by what is opaque: a chrome wire mesh that is 40 % wire is 40 % of the wire colour.
  `COLOUR_FIXES` holds colours that do not work flat (Screens: a dark glass blue, the mean of the lit map was a grey
  panel). A config may set `source_colours` to override a colour for one car.
- Metal folded into a matt material: where a source metal (metallicFactor from 0.6) lands in M_Trim or M_Interior (the
  far LODs fold chrome, alloy, exhaust and mirror into M_Trim), its colour is multiplied by 0.18. A mirror tint used as
  albedo is light grey plastic; rivals switch to LOD1 at 6 m in a race, so this is the common view of them.
- Rims: the reference is the wheel face, the colour with the most area looking away from the car in the spoke zone
  (0.22 to 0.5 of the tyre radius). That colour and everything brighter gets shade 1, darker parts down to 0.5. At
  LOD0 the player's rim colour is therefore full strength on the spokes of every car (flat spoke faces 0.91 to 0.99
  with the baked shade). At LOD1 the baked shade of a rim is one mean value for the wheel: the collapse to 12 % of
  the wheel smeared the per-corner pocket shade over the spokes.
- Baked shade (`bake_part_ao`): 24 cosine-weighted rays a vertex, reach 0.45 m, floor 0.28 (0.55 for brakes). Glass and
  lens covers do not occlude. A wheel and its brake are tested only against each other, so the shade turns with the wheel.
- Mapping changes in every `vehicle_configs/*.json`: Projector and Mirror go to M_Chrome at LOD0 (they were an
  emissive lamp and matt plastic). LOD1 and LOD2 keep their old surface lists.
- Engine (`car_materials.gd`): a surface of a `VERTEX_COLOURED` material whose mesh has COLOR_0 gets the `#vc` variant
  (albedo white, vertex colour as albedo; M_Rim keeps the player's rim colour). Every other material turns the flag off,
  because the glTF importer turns it on for any surface with COLOR_0. Cars without COLOR_0 (the project-made traffic
  sedans and the Arden Civic) keep the plain materials.
- M_Lens alpha 0.25 -> 0.1 for every car (one shared material): the cover laid a white veil over the lamp.
  `docs/art/CAR_01_BRIEF.md` still says about 0.25.
- Rebuild: `py -3.10 assets_src/pipeline/rebuild_vehicles.py [car_id ...]` (no ids = every config). It runs
  `prepare_vehicle.py` in Blender for each car and refreshes the car's three records in `ASSET_MANIFEST.json` (bytes,
  sha256, tris). Then `godot --headless --path game --import` and the tests.
- Garage: the paint mirrors `workshop_pano.jpg` (`CarMaterials.set_reflection` with blur 1.5 and highlight 3.0), not on
  the Low preset; the picture is loaded once (`_pano`). The key light uses one shadow map (orthogonal, 18 m: the
  farthest corner of the room is 15.9 m from the camera) instead of four cascades over 100 m; only the car casts a
  shadow there. Numbers (dev PC, RTX 5060 Ti, High preset, starter car): see `evidence/screens/garage/*.json`. Against
  the captures before the pass and with four cascades (339000 to 380299 primitives, 212 to 297 draw calls) the eight
  shots stay under 450000 primitives and 500 draw calls. With the pass and four cascades three shots were over the
  budget (436922 to 527729 primitives, seen during this session; those captures were overwritten and are not in
  evidence). Not captured: Medium and Low (1024 shadow atlas), a turning turntable.
- Independent review of this change (three Fable reviewers, each finding checked by a second one, 2026-11-27): six
  findings confirmed and fixed (far-LOD metals as light plastic, the Meridian mesh grille, rim shade inverted on three
  cars, the garage pass cost and preset gate, the lens note above). A second pass measured the fixes in the built
  files and found five smaller defects, fixed too (far-LOD rim shade, shadow reach, the panorama reloaded on every car
  switch, no test for the garage pass, doc sentences).

## All eleven shop cars are licensed models (2026-11-27, owner's yes to five downloads)
The five player cars that were still project-made Blender models were replaced in place: same car ids, scenes, specs
and saves, new GLBs under the same paths. Sources (CC BY 4.0, vinish.dev, about 3.7 MB each, in
`assets_src/third_party/vinish_cars/`): noctra_sable = "Track Day Coupe", atmaca_modified = "Drift Sedan", noctra_vela =
"Rally Hatchback", arden_bruiser = "Supercharged Street Machine", kestrel_gtr = "Electric Super GT". Credits:
`game/ui/credits_third_party.txt`, `THIRD_PARTY_LICENSES.md`, the 15 records in `ASSET_MANIFEST.json`.
- Configs: `vehicle_configs/<car_id>.json` for each; new keys `out_dir` (atmaca_modified lives in `bosfor_atmaca/`) and
  `source_file`, read by `rebuild_vehicles.py`. A second paint of a source (stripes) goes to M_Trim and keeps its own
  colour; the main paint is the one with the most area. `front_plate_material` is M_Trim on all five.
- Specs: wheelbase, tracks, wheel radii and body_size follow the new models; mass, power, grip and prices did not
  change. The Kestrel GT model is an electric car (no tail pipes) and still has the engine sound.
- Triangles (LOD0 / LOD1 / LOD2): Sable 89185 / 23479 / 6627, Strix S 86997 / 26952 / 6585, Vela 87685 / 27371 / 6444,
  Bruiser 88630 / 24033 / 5271, Kestrel GT 85455 / 24454 / 6716 (caps 90000 / 28000 / 7000, per-car decimate ratios in
  the configs; far-LOD body and trim are at the floor of the collapse).
- Rivals: every car of the shop has `"rival": true` now, so a grid mixes eleven models instead of six.
- Tail lamps: the GLBs no longer embed the tail-light atlas. `car_materials.gd` sets the two shared pictures
  (`shared/tail_atlas_day.jpg`, `tail_atlas_lit.jpg`) on an M_LightRear surface that has UVs and COLOR_0 (`#atlas`
  variant). Before, Godot extracted the atlas 18 times (55 MB of PNG, one texture pair per car and LOD in memory).
  Cars without `tail_cell` (Noctra Vela: smoked lenses with far-apart lamps; Kestrel GT: a thin full-width bar) use the
  plain red glowing material. The tyre normal map is not embedded either (the engine uses the tyre picture).
- Rear reflectors and amber indicators are M_Trim now (coloured plastic through the vertex colour); they were M_Lens
  and drew as colourless glass. The lights_rear node has one surface less.
- Tests: the five cars joined `test_car_licensed.gd` (eleven cars). `test_car_asset`, `test_car_bruiser`,
  `test_car_kestrel`, `test_car_vela`, `test_car_atmaca` keep their spec and driving checks; their sizes, wheel
  positions and triangle caps are the new models'. Studios: `car_studio`, `car_studio_bruiser`, `car_studio_kestrel`,
  `car_studio_vela` are copies of `car_studio_tayfun` with their own car.
- Still project-made: the traffic sedans (atmaca_stock, atmaca_taxi) and the Arden Civic. Their Blender sources and
  the old ones of the five replaced cars stay under `assets_src/vehicles/` (not shipped).
