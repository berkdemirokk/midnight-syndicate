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
