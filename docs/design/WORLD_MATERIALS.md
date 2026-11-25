# World materials (city_01 engine materials)

Owner: Texture + Shader Agent. Code: `game/world/materials/material_library.gd` (class `MaterialLibrary`),
tuning in `world_material_tuning.gd` (Resource fields, defaults shown below). Shaders:
`game/world/materials/window_atlas.gdshader`, `water.gdshader`; `shaders/wet_facade.gdshader` (walls, round 7); reused: `shaders/wet_asphalt.gdshader`, `shaders/neon.gdshader`.
Car glass (M_Glass) lives in `game/vehicles/noctra_sable/car_materials.gd`; see the car glass section below.
Data: `tools/ship_world.py` copies the source kits into `game/assets/world/` and registers each file in ASSET_MANIFEST.json.
Import: no `.import` overrides set. Godot's default GLB import handles the `-col` and `-colonly` suffixes.

## Use
- `MaterialLibrary.apply(root, building_id := "")` binds every mesh surface by its material name. Shared
  materials are one instance per name. `M_ImpostorAtlas` is per building id.
- `MaterialLibrary.report_unbound()` lists names that fell back to magenta. It must stay empty.
- `apply()` also sets visibility ranges on `LOD0/1/2` nodes (Godot does not import them). Without this the
  LOD2 impostor box covers the facade.

## Name -> material
| name(s) | material | source / notes |
|---|---|---|
| M_Asphalt | ShaderMaterial wet_asphalt | asphalt_02 set, 4 m tile, wetness 1, puddle 0.6, rain 0.2 |
| M_Curb | Standard, triplanar | brushed_concrete_03, 0.35 wet |
| M_Paving | Standard, triplanar | concrete_pavers_02, 0.35 wet |
| M_Ground | Standard, triplanar | concrete_pavement_03, 0.35 wet |
| M_Concrete_Wall, M_Concrete_Smooth/Stained/Panels | Standard, triplanar | CC0 set from materials.json |
| M_Brick_Dark/Red/Painted, M_Plaster_*, M_Facade_Tile, M_Concrete_Wall/Smooth/Stained/Panels | ShaderMaterial wet_facade (round 7, reworked round 8) | CC0 sets, uv_tile_m 1.2 to 2.0 m; falls back to Standard, triplanar if a set lacks a map, or when `use_wet_facade` is false |
| M_Metal_Corrugated, M_Metal_Painted | Standard, triplanar, neutral grey | rooftop plant: albedo texture dropped, colour `rooftop_plant_colour`, normal and roughness maps kept |
| M_Metal_Rusty, M_Roof_Bitumen, M_Wood_Planks | Standard, triplanar | CC0 sets (rust, bitumen, planks) |
| M_RoadPaint | Standard + faint emission | flat colour, emission 0.05 (road_paint_glow) |
| M_Water | ShaderMaterial water.gdshader | asphalt_04 normal, two layers scrolling 0.012/0.007 |
| M_ShopGlass | Standard, alpha | alpha 0.35, roughness 0.05 |
| M_WindowAtlas, M_ShopInterior | ShaderMaterial window_atlas | atlas albedo and emission, threshold glow |
| M_ImpostorAtlas | ShaderMaterial window_atlas, per building | impostor_<id>_basecolor / _emissive |
| M_Neon_Cyan/Magenta/Amber/Red/White, M_Bulb_*, M_Lamp_*, M_Signal_Red, M_CeilingStrip, M_TunnelLight, M_Aircraft_Red | ShaderMaterial neon.gdshader, unshaded | colour from emission, energy = JSON strength x neon_energy_scale |
| M_Poster_01..06, M_Skyline | Standard, backlit | albedo and emission textures, energy 2.2 (posters), 1.6 (skyline) |
| M_TunnelStripe | Standard + emission | amber, 0.4 |
| M_Manhole, M_Grate, M_ExpansionJoint, M_Rail, props (M_Bollard, M_Chevron_*, M_Container_*, ...) | Standard, flat | JSON colour, roughness, metallic |
| anything else | M_Unbound_Debug (magenta) | counted in report_unbound() |

## Parameters (defaults in world_material_tuning.gd)
| field | value | effect |
|---|---|---|
| wetness | 0.35 | textured surfaces: albedo x0.895, roughness x0.825 |
| texture_tile_m | 4.0 | fallback tile for CC0 sets without uv_tile_m |
| asphalt_tile_m / puddle / rain | 4.0 / 0.6 / 0.2 | wet_asphalt uniforms |
| neon_energy_scale | 1.0 | x JSON emission (signs 9, tunnel light 12, sodium lamp 14) |
| window_energy_scale | 0.8 | x JSON window emission (3.0) and shop interior (2.0) |
| window_glow_threshold | 0.6 | atlas values below this do not glow |
| window_glow_saturation | 0.15 | 0 grey glow, 1 raw atlas colour (was 0.5: violet and blue windows) |
| road_paint_glow | 0.05 | road marking self-glow (at 0.18 the markings read as bright blue plastic) |
| glass_alpha | 0.35 | shopfront glass opacity |
| water_scroll | (0.012, 0.007) | UV units per second |
| lod0_end_m / lod1_end_m | 110 / 260 | building LOD switch distances |
| facade_albedo_scale | 3.0 | window and shop atlas tint x (JSON #202838 was near black, walls read black) |
| window_glow_tint | (1.0, 0.78, 0.5) | colour of lit window glow (warm) |
| ceiling_energy_scale | 0.06 | x JSON energy of M_CeilingStrip and M_TunnelLight (5 and 12 blew out to white) |
| wall_albedo_scale | 2.2 | M_Brick, M_Concrete walls and M_Facade_Tile albedo x |
| roof_albedo_scale | 3.0 | M_Roof_Bitumen albedo x |
| CityBuilder ambient_color, ambient_energy | #2A3F6E, 1.6 | night fill for unlit walls (was #1B2B4D, 0.6) |
| rooftop_plant_colour | #4D4F54 (0.30, 0.31, 0.33) | rooftop plant albedo. The painted plate's blue texture read as blue boxes from 60 m |
| rooftop_metal_metallic | 0.15 | rooftop plant metallic |
| use_wet_facade | true | false = plain Standard walls (A/B perf runs, kill switch) |
| facade_wall_darken / facade_wall_gloss | 0.2 / 0.35 | whole-wall rain film: darkening and roughness drop on every metre |
| facade_wet_band_m / facade_wet_soft_m | 1.2 / 0.3 | wet band at the wall foot (height, soft edge) |
| facade_wet_darken / facade_wet_gloss | 0.35 / 0.6 | extra darkening and roughness drop inside the wet band |
| facade_storey_m | 3.4 | height period of the streak and grime bands |
| facade_streak_density / facade_streak_stretch | 6.0 / 0.3 | rain streaks per metre across the wall, vertical noise frequency per metre (lower = longer) |
| facade_streak_threshold / facade_streak_darken / facade_streak_gloss | 0.6 / 0.2 / 0.4 | which streaks show, darkening and roughness drop along them |
| facade_sill_boost | 0.6 | extra streak strength at the foot of each storey band (sills, ledges) |
| facade_grime | 0.2 | darkening at the foot of each storey band |

## Wet facades (`shaders/wet_facade.gdshader`)
Walls were dry-looking under rain. Each CC0 wall set (albedo, normal, roughness) uses one spatial shader:
- Albedo and roughness are pre-scaled in `MaterialLibrary._facade()` with the same wetness and wall-albedo terms as
  `_standard()`, so the shader only adds the rain layers.
- Projection: dominant axis of the face in world space (X faces use z and y, Z faces x and y, top faces x and z).
  Three lookups in total (albedo, normal with a manual tangent to view space, roughness). No Standard-style triplanar.
  Corners switch projection axis at the edge, so texture is sharp there (see known gaps).
- (0) whole wall: darkening `facade_wall_darken` and roughness drop `facade_wall_gloss` on every metre (the rain film).
- (a) wet band: 1.2 m at the foot of the wall, soft edge 0.3 m, darker and glossier.
- (b) rain streaks: two hashes per pixel (no texture): one column per 1/6 m across the wall, blended vertically over
  about 3.3 m, shaped by a short fade. Lower roughness and darkening. Stronger at the foot of each 3.4 m storey
  band (under sills and ledges).
- (c) grime: darker toward the foot of each storey band.
Approximation: the storey bands and sills are height periodic, not read from the building. Ledge and sill faces are
projected on the ground plane and get no separate sill geometry.

Round 8 (QA findings): the wet layers were too weak to read at 60 m. Wall darkening and gloss were added for the whole
wall, the wet band and streak strength were raised, and `use_wet_facade` was added for A/B runs.

### Perf (desktop only, RTX 5060 Ti, high preset, `neon_strip`, 300 frames)
The earlier "before/after" table (1.27 vs 1.37 ms) was not reproducible. The baseline JSON it cited is not under
`evidence/`. `evidence/screens/city_districts_before/` has different counts (365 draw calls, 209,452 primitives)
and is not the same scene state. Run-to-run spread on identical code is larger than the claimed delta.

A/B round 8 (same build, only `use_wet_facade` toggled; each row is one full `city_districts` run; JSON copies in the
scratchpad of the round):

| run | draw calls | primitives | frame ms avg | p95 | p99 |
|---|---|---|---|---|---|
| plain walls (`use_wet_facade` false), run 1 | 300 | 213 260 | 1.306 | 2.176 | 4.177 |
| plain walls, run 2 | 300 | 213 260 | 1.500 | 2.689 | 4.844 |
| wet facade, run 1 | 300 | 213 260 | 1.945 | 2.889 | 4.263 |
| wet facade, run 2 | 300 | 213 260 | 1.393 | 2.535 | 4.156 |

Means: plain 1.40 ms, wet facade 1.67 ms, but the two runs of each setting differ by 0.2 to 0.55 ms, so the
difference is not separable from noise. Draw calls and primitives are identical. Other runs of the wet build on the
same day: 2.03 ms (before the round 8 tuning), 1.28 ms (after it), and 1.13 ms in the QA run. The wet facade costs no
draw calls and no extra geometry. Its shader cost is small (one extra hash pass) but not measured in isolation.
A first version with four-hash value noise was replaced by the two-hash version above. Not a phone number.

## Car glass (round 7, round 8 streaks, `vehicles/noctra_sable/car_materials.gd`, M_Glass)
The garage windscreen read light grey at grazing angles. Measured on the garage overview (same crop, mean RGB):
- Opaque black glass gave near black (36), so the grey is what the glass passes or reflects, not its own colour.
- Lowering specular (0.25 to 0.04 or 0.08) and raising roughness (0.03 to 0.06 or 0.1) changed nothing measurable (about 110 to 111).
  At grazing angles the Fresnel term dominates, so specular does not control it.
- Lowering alpha to 0.42 made it brighter (119): more of the bright background shows through.
- Alpha 0.85 with specular 0.08 reads as smoked glass (about 77). This is `GLASS_TINT` in code.

Round 8: `GLASS_ROUGHNESS` is 0.1, and a fixed 32 x 32 roughness map (`_glass_streak_map()`, columns random, constant
down each column, red channel 0.6 to 1.0) scales it to about 0.06 to 0.10. Triplanar, 1.5 repeats per metre, so
reflections break into faint vertical streaks. The map is built in code and cached. The dead `GLASS_ALPHA` constant
was removed (it was overwritten by `GLASS_TINT` and had no effect). The streaks are subtle at garage distance.

## Why the window threshold exists
`M_WindowAtlas` is bright across most of its emissive atlas (pale blue and orange bands, about 27% of
pixels above mid grey). With plain StandardMaterial3D emission at energy 3 the facades blew out to white
(measured, round 1). The threshold shader makes only the brightest cells glow. Lit windows bloom and the
wall stays dark. Source of the atlas layout: `assets_src/world/kit_buildings/out/window_atlas_emissive.png`.

## Capture scenario `world_materials` (devtools/scenarios/world_materials.gd)
Five buildings (one per district: neon, downtown, market, waterfront, parking) behind road, kerb and
sidewalk, five neon sign props, two sodium lamps with OmniLight3D (energy 7, range 26), ambient 1.2.
Shots: wide, shopfront_close, windows_close, road_close, signs_close in `evidence/screens/world_materials/`.
Look-and-fix rounds: 6 (blow-out, window scale, threshold shader, LOD ranges, threshold and light, desaturation).

## Known gaps
- No mirror reflection in the scenario. The reference (`layout_renders/neon_strip.png`) depends on wet
  reflections; the planar hookup stays with the scene (`PlanarReflection` on M_Asphalt).
- Road reads flat and dark; puddle mask barely shows. Shop interiors glow only faintly.
- Neon bloom is milder than the reference. Signs are readable (no magenta anywhere).
- JSON files are read at run time from res://. Export filters must include `*.json` under assets/world.
- Walls are darker and streakier after round 8 but still read as dry brick from 60 m in places. The wet look is a
  darkening, streak and gloss read, not real reflections on walls. The light grey stone tower on the right of
  `establishing_60m.png` is unchanged: it is not a wet-facade material and its albedo was not changed.
- Facade streaks follow world height, not the building's own storeys or sills. No per-building variation.
- Facade corners: the dominant-axis projection makes the texture switch axis at each building edge. Checked only in the
  city_districts captures; no close corner shot was made.
- Plaster walls keep the old albedo (they were not in the brick and concrete wall scaling).
- Rooftop slab: the large corrugated roof on the left of `establishing_60m.png` still reads blue-grey. The likely cause is
  the blue night ambient (CityBuilder, #2A3F6E), not the material. Not changed: the ambient belongs to the lighting owner.
  Not verified against a material swap.
- Car studio `front34.png` shows a bright horizontal light bar top right and a bloom blob lower right. Not verified against
  a pre-change capture (none kept). Not caused by a material change in this round as far as checked.
- Perf numbers are desktop only (see the wet facade section). No phone measurement.
