# CITY 01 look (in engine)

Owner: lighting and look agent. Scenario: `game/devtools/scenarios/city_districts.gd`. Captures: `evidence/screens/city_districts/`.
Target: `assets_src/world/city_01/layout_renders/neon_strip.png`. Status: PARTIAL (rounds 0 to 3 done; the black-facade blocker is fixed, downtown, underpass and waterfront still short of the reference).

## Setup used for every shot
- Preset High (`--preset=high`), 1920x1080, FOV 70, eye 1.3 m above the racing line, looking 32 m along the race direction.
- Wetness 1.0 and rain intensity 1.0 on the M_Asphalt material. Rain scene (`fx/rain.tscn`) on.
- PlanarReflection on, plane = racing-line height at the camera (updated per shot). Road meshes on layer bit 1 so the mirror skips them.
- Shot points (arc length on the racing line): neon_strip s=144 (start grid), downtown s=750, waterfront s=1250,
  underpass s=1620, old_market s=1950. Establishing: 60 m up, 40 m to the side of s=144, looking at the strip.
- Each shot: 60 settle frames, PNG, then 300-frame perf probe (`*_measure.json`).

## Round 0 (baseline, layout values, current code)
- Glow: intensity 0.8, HDR threshold 1.0. Window emission scale 1.0.
- neon_strip: reads as a street. Signs bloom, wet road mirrors the signs, facades readable. Closest to the target.
- downtown: towers are flat saturated blue slabs (window atlas emission). Walls black, no depth. Reads as boxes.
- underpass: ceiling strip lights blow out to white bands. Amber stripe is flat.
- Close rain streaks look like poles 1 m from the lens. Not owned here (fx/rain), noted only.

## Round 1 (change: glow intensity 0.8 -> 0.55, HDR threshold 1.0 -> 1.3 in `city_builder.gd`)
- Underpass: strips still white, only slightly less blown out. Strips are emissive above threshold; threshold alone does not fix them.
- neon_strip: signs keep their bloom, text still readable.
- No stronger change than this: round 1 was the first measured step, not a full pass.

## Round 2 (change: `window_energy_scale` 1.0 -> 0.6 in `world_material_tuning.gd`)
- Downtown: windows less hot, but still saturated blue and red. Facades still flat. Not solved by emission alone.
- Underpass and neon_strip unchanged by this change.
- `test_city_01` run after round 2: 6 of 6 pass (`evidence/logs/test_city_01_r2.log`).

## Not done in this pass
- Rounds 3 to 5 (fill light for black facades, per-district lamp colour, fog, reflection_strength / smear / grain, puddle level, tonemap exposure).
- Per-district tuning of lamp spot energy and sodium vs cool colour.
- race_city.gd (real race scenario): not written.
- city_presets.gd (Low/Medium/High perf table): not written. No Low or Medium numbers exist.
- GRAPHICS_BENCHMARK.md "City 01 in engine" section: not written.
- Full 82-test suite run: not done in this pass.
- Perf numbers from the district shots were recorded in JSON but not reviewed here. Nothing is claimed from them.

## Self-assessment against the brief's acceptance test
("does not read as boxes on a plane: facade depth, signage, street furniture, light rhythm, readable road edge")
- neon_strip: partial pass. Signage and wet reflection read. Facade depth is weak (flat walls with few modules visible). Light rhythm present.
- downtown: fail. Towers read as flat emissive slabs; no visible depth or rhythm at this view.
- waterfront: not reviewed in this pass (captured, not assessed).
- underpass: fail. Ceiling strip blows out; road edge readable, but the glow dominates the frame.
- old_market: not reviewed in this pass (captured, not assessed).
- establishing_60m: not reviewed in this pass (captured, not assessed).

## What still looks wrong
1. Underpass ceiling strips saturate to white. Needs emission energy per class (strip vs neon) or a lower strip energy.
2. Downtown windows are flat saturated blue and red. Window atlas emission is too uniform.
3. Downtown facades show no depth from this camera; the layout modules may be too thin at this range.
4. Facades in neon_strip are dark and flat in places; no fill light added yet (brief asks for a few wide low-energy fills within the per-mesh budget).
5. Rain particles close to the lens read as thick poles (fx/rain, not owned here).
6. Planar mirror: all Road meshes (road, kerb, sidewalk) are on layer bit 1 and left out of the mirror. Whether that is right for the sidewalk is not checked.
7. Lamp heads and lane markings have not been checked for z-fighting at these distances.

## Round 3 (this pass: review findings of the in-engine city)
Changes (all tunables, no code paths changed):
- `world_material_tuning.gd`: `facade_albedo_scale` 2.2 (new), `window_glow_saturation` 0.5 -> 0.15, `window_glow_tint` warm (1.0, 0.78, 0.5) (new), `ceiling_energy_scale` 0.06 (new).
- `material_library.gd`: window and shop atlas tint = JSON colour x `facade_albedo_scale`; `glow_tint` passed to the shader; ceiling strip and tunnel light energy x `ceiling_energy_scale`.
- `window_atlas.gdshader`: `glow_tint` uniform applied to the luminance part of the glow.
- `city_builder.gd`: night ambient colour `#2A3F6E` (was `#1B2B4D`) and energy 1.6 (was 0.6), exported as `ambient_color` and `ambient_energy`.

Cause found for the black frames: the M_WindowAtlas JSON base colour is #202838 and the shader multiplies the atlas albedo by it, so every facade was near black under the night ambient. Only lamp-lit walls showed. Lifting the tint and the ambient made the walls readable. This was the blocker in the establishing shot (the window quads were the only lit parts).

Results (captures `evidence/screens/city_districts/`, final run r6):
- establishing_60m: the facades now show brick, window openings and roofs. It is still a dark night view and the top-left corner is blown out roof light. The blocker (floating quads on black) is gone.
- downtown: towers read as building blocks with warm and violet windows. Still no cyan or magenta read on the towers; the atlas windows are violet, not neon. Still weak.
- underpass: ceiling strips are light blue at about 0.7 HDR, no longer white-clipped, but still the largest bright shapes in the frame. The amber wall stripe (M_TunnelStripe, emission 0.4) still reads as a flat band across the horizon. Not changed: the stripe is a wall mesh in the road GLB and its placement was not checked in a side view.
- waterfront: still dark (lowest readability). Facades and road edge are visible now; no sodium pool is present in this view. Not solved.
- neon_strip: closest to the reference. Facades show brick texture and window rhythm; sign text (ORBIT RECORDS, VOLT ENERGY, LUMEN CINEMA, KOI NOODLE BAR) is readable; wet road mirrors signs.
- old_market: captured, not fully assessed in this pass.

Known and not done:
- Rain streaks near the lens read as thick poles in some shots. This is `fx/rain` (not owned here).
- The amber stripe and the ceiling strip are both large flat shapes in the underpass. A geometry or placement check in a side view is needed.
- Waterfront needs a sodium lamp or fill pass. Not done.
- Downtown needs a cyan or magenta neon read on the towers. Not done. The atlas glow is the only window light source.
- race_city: a real race capture now exists (`evidence/screens/race_city/`). The nitro shot failed: the autopilot player car sat below 6 km/h for about 30 s at a wall (reverse gear in the shot). AI and physics code are not owned here.

Self-assessment after round 3: the blocker is fixed. Majors are partly fixed (downtown and underpass better, waterfront not). The scene is still not at the reference look.

## Second pass (lighting and look agent, rounds 4 to 9 of the brief's count)
Baseline copies: `evidence/screens/city_districts_before/`. Captures: `evidence/screens/city_districts/`, logs `evidence/logs/capture_city_r1..r6.log`.

### Findings that changed the plan
- Downtown was not dark because its lamps were dropped. Its shot (s=750) sat past the downtown lamp run (s 514 to 665), so no lamp was in frame. Shot moved to s=590.
- The light budget dropped 36 lights before this pass. Causes: double street lamps (25 lamp heads within 3 m of another head) and 16 neon fill omnis at range 12 to 14 touching the road volumes. After the fixes the budget drops 12, all underpass tunnel strips (budget log: `road_12..14`, `sidewalk_12..17`, `structure_12..14`).
- Layout sample spacing of the racing line is 4 m (551 points over 2203 m), so the scenario's SAMPLE_M=4 is right. The centerline is 2 m.
- Depth fog: exponential fog at 0.0045 put about 74 percent fog on anything 300 m out, so the bay skyline was invisible. Now depth fog from 220 m to 1200 m. Near city unchanged.
- Waterfront shot faced along the road, so the bay and skyline were out of frame. Camera yaw 80 degrees added to the shot.

### Round 4 (underpass and budget)
- New `game/shaders/tunnel_light.gdshader`: world-space dash, 1.2 m lit, 0.6 m dark, energy 3 (`tunnel_light_energy`). M_TunnelLight routed to it.
- M_TunnelStripe now painted #B8901E, roughness 0.5, no emission.
- Tunnel omni strips x2 (`tunnel_light_energy_scale`).
- `neon_fill` range capped at 8 m; `lamp_head` range capped at 18 m; double-lamp heads merged (`lamp_merge_m`).
- Kerb (M_Curb) albedo x1.8, sidewalk (M_Paving) x1.2; road paint glow 0.02 to 0.05.
- Result (`underpass.png`): fixtures read as separate dashes, walls and stripe visible, road edge readable. Last looked at after round 1 of this pass.

### Round 5 (lamps and market)
- Lamp spot energy per district (`lamp_district_scale`): downtown x4, waterfront x8, market x4, neon x1 (reference unchanged).
- String lights x3 (`string_light_energy_scale`).
- Result (`old_market.png`): warm pools on the street and dapple from the string lights. Looked at after round 5.
- Downtown (`downtown.png`, after round 5): towers, signage (BLUE HERON SUSHI, red and teal fronts), kerb visible on the left. Overpass guardrails not checked in frame.

### Round 6 (waterfront skyline)
- Waterfront camera yawed to the bay (`yaw` 80).
- M_Skyline emission scaled by `skyline_emission_scale` 0.35, applied in the texture branch. It had been blown to pure white at 1.6.
- Result (`waterfront.png`): skyline card and lit windows across the water, two gantry cranes visible, water reflects the card. Pools on the promenade road are still weak.

### Establishing shot (point 6 of the brief)
- Checked the building GLBs. LOD0 holds every material, LOD1 keeps walls, window atlas and frame-less shell (it drops only Aircraft_Red, Frame and Metal_Painted). LOD ranges switch at 70 m and 180 m with a 4 m fade. No visibility gap between window panes and walls was found.
- The "floating windows" in `establishing_60m.png` are lit window cells on near-black walls and roofs (roof bitumen and wall albedo under 1.2 night ambient). Not fixed in this pass.

### Test results
- `test_world_materials`: 5 of 5 pass (`evidence/logs/tests_city_r6.log`).
- `test_city_01`: 4 of 6 pass, including `count_lights_dropped` 12 and `light_worst_per_mesh_*` 8. Two fail: `test_single_ai_lap` and `test_eight_cars_on_grid`. Cause is outside this agent's files: `game/ai/ai_driver.gd:88` calls `_build_profile()`, which does not exist, so `race_manager.gd` and the test script fail to compile. Owner must fix that file.

### Per-district score against the brief's acceptance test (0 to 10)
Acceptance test: "does not read as boxes on a plane: facade depth, signage, street furniture, light rhythm, readable road edge".
- neon_strip (reference): 6. Signs, wet reflections and kerb read. Facade depth still weak.
- downtown: 5. Towers, signage and kerb read at street level; road pools weak; overpass guardrails not verified.
- waterfront: 4. Bay and skyline now read; promenade lamp pools still weak; warehouse fills not added.
- underpass: 7. Rhythmic fixtures, lit walls, painted stripe, readable edge.
- old_market: 6. Warm lamp pools and string dapple; facade depth average.
- establishing_60m: 2. Black walls and roofs; windows float. Not solved.

### Still not done
- Warehouse land-side fills on the waterfront (brief item 2, last clause).
- Downtown overpass guardrails and parapet light catch (brief item 3).
- Establishing: unlit walls and roofs (fill or roof albedo).
- Road-paint readability at 60 m was not measured, only visually checked in the neon and downtown shots.
- No perf numbers from this pass were reviewed.

## Third pass (lighting and look agent, brief of 2026-11-24: rival paint, waterfront, establishing)
Baseline for every round: `evidence/screens/city_districts_round0/` (snapshot of the second pass). Logs `evidence/logs/capture_city_round1.log`, `capture_city_round2.log`, `capture_city_round3.log`, base `capture_city_r1_base.log`.

### Round 1 (framing and facade albedo)
- `city_districts.gd`: waterfront yaw 80 -> 27. At yaw 80 the camera looked past every promenade lamp (all 9 lamp heads at heading -15..-21 deg were outside the frame), so the pools were never in view.
- `world_material_tuning.gd` new `wall_albedo_scale` 1.8; `material_library.gd` multiplies the albedo of the building brick and concrete materials by it.
- Result: waterfront shows warm sodium pools on the promenade, the lit lamp heads, the sidewalk kerb catching light, the skyline card with lit windows. Establishing: walls still near-black (first version only scaled `M_Concrete_Wall`, which the building kit does not use; fixed in round 2).

### Round 2 (wall-wash spots and the correct facade materials)
- `material_library.gd`: the wall scale now covers `M_Brick*`, `M_Concrete*` and `M_Facade_Tile` (the materials the building kit uses).
- `city_builder.gd`: new `_wall_wash_lights`. Three warm spots (`wall_wash_*` exports, colour #FFB26B) over the road at the waterfront warehouses (`bld_waterfront*`, s 1150 to 1400, spaced 35 m), aimed at the land-side facades. They go through the normal light budget.
- Result: establishing shows brick texture, window openings and roofs on the facades; lit windows sit on visible walls. Downtown and Neon Strip compared with round 0: no regression seen (Neon Strip signs and wet reflections unchanged; downtown walls slightly lighter).

### Round 3 (wall-wash energy)
- `wall_wash_energy` 7 -> 14 (JSON scale; effective 8.4 after `light_energy_scale`). The warehouse lower storeys read lit; the change is small in frame because the wash is aimed at the warehouse base.
- Light budget: 58 dropped lights in the scene (round 0: 56). All road, sidewalk and structure volumes stay at 8 kept omni or spot lights or fewer; the new drops are prop lamp volumes.
- Tests: `test_city_01` and `test_world_materials` 12 of 12 pass (`evidence/logs/tests_city_round3.log`).

### Rival paint (RaceConfig): palette set, NOT visible in the race yet
- `race_config.gd` `opponent_paints`: electric blue #1F5BFF, signal orange #FF6A13, acid green #7BE000, pearl white #E8ECF2, violet #8A3BFF, sun yellow #F2C200, teal #12B5A5. All distinct; the player keeps candy red.
- Race capture (`evidence/screens/race_city/racing_10s.png`, `pack.png`, run after the palette change): every car in frame is still candy red (#8E0F1E) including the rivals.
- Cause (outside this agent's files): `vehicles/noctra_sable/car_lod.gd` `_ready()` calls `CarMaterials.apply(self, paint_colour)` with its own default `paint_colour` (CarMaterials.DEFAULT_PAINT). `CarFactory.create` sets the paint before the car enters the tree, so `_ready` replaces the paint materials with candy red. `CarVisual.set_paint` then changes only the orphaned materials. The player's navy `player_paint` is hidden the same way.
- Fix needed (owner: vehicles): in `vehicles/car_factory.gd`, set `(model as CarLod).paint_colour = paint` before `visual.add_child(model)` when the model is a `CarLod`, or have `CarLod._ready` take the paint from the CarVisual. Then re-capture race_city and check pack.png.

### Open items (not done in this pass)
- Waterfront: no container stacks or quay railing catch light in the frame; water reflection of the skyline is hard to see at this exposure.
- Underpass: ceiling dashes still the largest bright shapes (unchanged this pass, judged acceptable).
- Full suite (`evidence/logs/tests_full_city_look.log`): 123 tests, 1 failed: `test_race_scene.gd::test_car_fill_light_reaches_only_the_car_layer` (12 car meshes not on the fill layer). The test file was modified after the last passing run (`tests_r3_full_suite.log`, 21:48; test file 21:58). Not in this agent's files; not investigated further.

## Fourth pass (brief of 2026-11-25: waterfront, establishing, downtown, underpass; rounds 0 to 4)
Baseline (round 0, unchanged code): `evidence/screens/city_districts_look_r0/`. Logs `evidence/logs/capture_city_look_r0..r4.log`.
Shot list now has 7 shots: `waterfront_stacks` added (s 1279, yaw 80, faces the container stack and gantry crane across the quay).

### Round 1 (floodlights, roofs and walls, underpass energy)
- `city_builder.gd`: new `_floodlights()`: one cool-white spot (`floodlight_*` exports, source `floodlight`, no distance fade) above each waterfront `container_stack` and `gantry_crane` (s 1100 to 1420). New `lamp_district_scale` waterfront 8 -> 10 in round 2.
- `world_material_tuning.gd`: `roof_albedo_scale` 2.0 -> 3.0, `wall_albedo_scale` 1.8 -> 2.2, `tunnel_light_energy` 3.0 -> 1.5. `city_builder.gd`: `tunnel_light_energy_scale` 2.0 -> 3.0.
- Look: establishing roofs now read as blue roof planes; walls brighter. Underpass dashes still blown out at 1.5 (see round 3 for why). Waterfront: floodlights not visible in frame.

### Round 2 (floodlight range, promenade lamps, underpass energy)
- `floodlight_range_m` 60 -> 30. The 60 m sphere touched many light-budget volumes; the range was cut to keep the lights in budget. `lamp_district_scale` waterfront 10. `tunnel_light_energy` 1.5 -> 0.9.
- Look: promenade pools slightly warmer on the road. Underpass dashes still near white.

### Round 3 (underpass fixture energy, scene check)
- `tunnel_light_energy` 0.9 -> 0.4. The shader is unshaded and writes `base * energy` in linear space; sRGB output makes 0.9 look white. 0.4 gives grey-blue fixtures, not blown out.
- `city_districts.gd` now prints the count of `floodlight_*` spots in the scene: 4 in the scene (all kept by the budget). Not a budget drop; they were out of frame.
- Look: underpass fixtures read as separate grey-blue dashes; walls and the painted stripe unchanged (the stripe is still a flat band).

### Round 4 (new waterfront_stacks shot)
- Added `waterfront_stacks` (s 1279, yaw 80). Look: the far skyline card reads, but the containers and crane base do NOT read. They are behind the quay fence and too far (350 to 380 m) for the floodlights to light a visible area; the crane base is still dark.
- Neon Strip compared with round 0 (`neon_strip.png`): no regression seen. Signs read, wet reflections unchanged, facades a little lighter from the wall albedo.
- Downtown compared with round 0 (`downtown.png`): essentially unchanged. Overpass deck lamp pools and parapet catch light were NOT done.

### Tests
- `test_city_01` + `test_world_materials` (round 4): 12 of 12 pass (`evidence/logs/tests_city_look_r4.log`).
- Full suite (round 4): 131 tests, 0 failed (`evidence/logs/tests_full_city_look_r4.log`).
- Import after round 1: no SCRIPT ERROR, Parse Error or SHADER ERROR.

### Status against the brief
1. Waterfront: partly. Promenade pools warmer; the skyline card reads; floodlights are placed and in budget but do NOT show in any frame. Quay railing light catch NOT done. Container stacks NOT visible.
2. Establishing: partly. Roof planes read; walls brighter; floating window cells on the dark side walls remain. No moonlight change (moon already at 0.25, no shadows).
3. Downtown street level: NOT done (overpass lamp pools, parapets).
4. Underpass: partly. Dashes dimmed from blown-out white to grey-blue fixtures, now not the brightest shapes (the stripe and walls are still dark). Walls lit in rhythm NOT verified.

### Still open (next pass)
- Frame the containers: a closer or higher camera at the quay, or a floodlight range that reaches the camera side.
- Quay railing material (M_Metal_Painted or the railing kit) needs a rim or sheen to catch light.
- Downtown overpass: place lamps for the deck and raise the parapet albedo.
- Establishing: the lit window cells on near-black side walls; raise facade albedo further or add a wall-wash fill there.

## Fifth pass (Environment Agent, brief of 2026-11-25: parked cars, waterfront, rooftops, downtown)
Scope this pass: rooftops only. Parked cars, waterfront bollards and boats, downtown bus shelters and overpass lamps were NOT built.

### Round 0 (baseline, code before this pass)
- Capture `evidence/screens/city_districts/` (run `env_city_districts_r0.log`, 0 SCRIPT ERROR). The first run's PNGs were overwritten by round 1; no separate copy was kept.
- establishing_60m: rooftop plant (M_Metal_Corrugated tanks, M_Metal_Painted AC units) reads as black hexagon holes. Metallic 0.5 reflects the dark night sky.

### Round 1 (rooftop plant metal)
- `world_material_tuning.gd`: `rooftop_metal_albedo_scale` 2.5, `rooftop_metal_metallic` 0.15 (new).
- `material_library.gd`: M_Metal_Corrugated and M_Metal_Painted get the albedo scale and the lower metallic. M_Metal_Painted is also used on fire escapes and balconies, so those change too.
- Look (`establishing_60m.png`): tanks and AC units now read as lit blue-grey volumes on the roofs. The black holes are gone. The tint is a little saturated blue from the night ambient.
- Look (`neon_strip.png`): no regression. Signs, wet reflections and facades as before. Fire-escape metal lighter.
- Tests (`env_tests_r1.log`): test_city_01, test_world_materials and test_city_race, 22 of 22 pass, 0 failed.

### Race capture (race_city)
- `env_race_city_r1.log`: the run exited with code 0 but printed no `[CAPTURE]` line and wrote no new files. The race_city PNGs and JSONs on disk are the earlier ones (24-25 Nov). Not re-looked at this pass. Cause not found; not retried.
- The perf numbers for the race pack shot are therefore the earlier run's: pack 493 draw calls, 419 325 primitives; racing_10s 487 draw calls, 418 887 primitives (desktop, High). Before and after are the same file, so there is no before/after race comparison.

### Neon strip perf (desktop, High; not a same-session baseline)
- Earlier snapshot `evidence/screens/city_districts_round0/neon_strip_measure.json`: 355 draw calls, 219 664 primitives.
- This pass `neon_strip_measure.json`: 300 draw calls, 213 260 primitives.
- The change from the rooftop material is a material change only, so the drop comes from earlier passes, not this one. Do not read it as a result of this pass.

### Open (not done in this pass)
1. Parked cars (60 to 120 MultiMesh cars, six night paints): not built.
2. Waterfront: container stacks still outside the frame; bollards, boats, quay sodium pools, warehouse lit windows: not done.
3. Downtown: bus shelters with lit adverts, benches, overpass deck lamps and parapet light catch: not done.
4. Establishing: lit window cells still on near-black side walls.
5. Only one capture round this pass (the brief asks for at least four). The race_city run needs a fix to its run before it can be used.

## Env pass 2 (QA findings follow-up), 2026-11-25

### Round 1 of capture-look-fix: parked cars (brief item 1)
- Built: `game/world/city_01/parked_cars.gd` bakes the Noctra Sable LOD2 model (non-paint surfaces in one body mesh, M_Paint surfaces in one paint mesh, M_LightFront left out so headlights are off).
- Placement (`city_builder.gd` `_build_parked_cars`): kerb side only, every 12 m on both sides of the lap, outside the corridor (kerb + 0.5 m + 1.0 m gap, every footprint corner at least 0.4 m outside), and clear of building boxes and box prop colliders (0.5 m). 131 candidates accepted, 90 kept (evenly thinned, seed 7).
- Draw groups: 1 body MultiMesh + 6 paint MultiMeshes (dark grey, navy, maroon, white, silver, black), clearcoat paint in code.
- Not done in this round: LOD1 within 60 m (LOD2 only, no per-instance LOD on a MultiMesh); no distance culling on the parked node (its origin is the city origin, so visibility_range would be wrong); no parking decks, alley gaps or lots as named placements (kerb side only); rear-lamp emissive variation (all cars keep the rest emission 0.6).
- Light budget: `Parked*` nodes are left out of the budget volumes (their AABB spans the lap).
- Tests: `test_parked_cars_outside_corridor` (60 to 120 cars, worst corner margin <= -0.4 m, no colliders). test_city_01 8/8 pass.
- Capture city_districts (high, desktop): neon_strip shows no parked cars (the strip has no free kerb space); waterfront.png shows a row of lit cars on the land-side kerb. Neon strip perf after: 314 draw calls, 1,441,040 primitives, 4.08 ms avg (RTX 5060 Ti, desktop). A same-session before number was not captured.
- Log: `evidence/logs/env_r2_city_districts.log`, `evidence/logs/env_r2_city.log`.

### Not done in this pass
- Brief item 2 (waterfront: container stacks and cranes nearer the quay, bollards, quay boats, promenade sodium pools, lit warehouse windows): not changed.
- Brief item 4 (downtown: bus shelters, benches, overpass lamp pools, parapet light): not changed.
- Brief item 3 (rooftop plant): already changed in the earlier pass; not revisited.
- Capture-look-fix rounds: 1 of the 4 required. race_city run: not done in this pass.

## Dressing pass (Environment Agent, brief of 2026-11-25: waterfront and downtown street dressing)
Built in `city_builder.gd` `_dress_districts`, called after the layout props. Kit props only (`assets/world/kits/props`).
Every spot is checked against the corridor (0.3 m clear), building boxes (0.5 m), the layout's furniture and lamps
(circles), and the dressing already placed. Sidewalk props keep a 1.2 m walking lane to the kerb or the wall.

### Round 0 (baseline, dressing pass off, same code otherwise)
- Waterfront: 45 draw calls, 52,971 primitives. Downtown: 153 draw calls, 132,468 primitives. Neon strip: 300 draw calls, 213,260 primitives.
- The old `evidence/screens` perf JSON from earlier builds (55 draws, 134,823 primitives for the waterfront) does not match this code and is not used.

### Round 1 to 4 (placements, one capture per round, looked at waterfront, waterfront_stacks, downtown)
- Quay bollards: every 6 m on the water side, 1.2 m in from the building line. Bollards in total: 87 placed (77 tagged waterfront, which includes the quay run and the far approach; 10 tagged downtown, the near approach), 2 missed. Visible as small lit posts on the left of waterfront.png.
- Promenade: bench and bin pairs every 40 m on the land side (9 benches, 9 bins). Sodium lamp grid at 30 m: 4 lamps added where the layout left gaps (ends of the run, 1007 to 1022 m and 1382 to 1442 m). All 15 waterfront lamp heads survive the light budget (`waterfront_lamps_kept` 15 of 15), so the neon fill ranges were not shortened.
- Land-side lot: 2 container stacks and 1 gantry crane (rails along the road). Only the lateral 58 m spots are free: 34 to 52 m are taken by the parking structures (`bld_parking`). The lot is behind the parking deck; `waterfront_lot` shot shows the deck, not the stacks.
- Downtown: the sidewalks are about 2.0 m wide between the corridor edge (7.3 m) and the building colliders (faces at 9.3 m), so a 1.6 m shelter plus the 1.2 m lane fits only in the gaps between buildings. One shelter fits (s 539, right side, with its advert light); the shelter at s 648 and the other three intended shelters do not fit. Benches, planters and newspaper boxes: one each at street level.
- Downtown dressing is limited to street level (overpass deck y above 0.5 m excluded).
- Overpass approaches: bollards searched within 12 m of both deck ends (the near end at 680 m, the far end at 1052 m), counted in the bollard totals above.
- Lights: the shelter advert (omni, 3 x 0.6 energy) and the new lamp heads (spot, catalog sodium colour) go through the same budget as the layout lights.

### Numbers (desktop, high preset, RTX 5060 Ti, measure run)
- Waterfront: 45 to 60 draw calls, 52,971 to 56,089 primitives.
- Downtown: 153 to 161 draw calls, 132,468 to 134,348 primitives.
- Neon strip: 300 draw calls, 213,260 primitives both before and after; dressing adds nothing there.
- Waterfront stacks shot: 26 to 32 draw calls, 34,294 to 36,974 primitives.

### Tests
- `test_street_dressing` (new): no placed prop reaches the corridor, every sidewalk prop keeps 1.2 m of lane, every kerb prop is outside the 7.0 m kerb line, counts (77 bollards, 8 benches, 4 lamps, 1 shelter, 2 stacks, 1 crane). test_city_01 9/9 pass.

### Not done or not right
- Downtown does not get its shelters every 120 m: 1 of 4 intended. Fix is in the layout (wider sidewalks or setbacks), not the dressing pass.
- Land-side stacks and crane are not visible from the racing line in any shot: they sit behind the parking deck at 58 m. Owner of the layout should decide on a position.
- The overpass bollard at the start of the deck (downtown, 668 to 680 m) lands on the deck edge in some sides; not checked in a capture.
- `waterfront_lot` shot added to `city_districts` (yaw -55, facing the land side).
