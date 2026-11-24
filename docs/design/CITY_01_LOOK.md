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
