# World materials (city_01 engine materials)

Owner: Texture + Shader Agent. Code: `game/world/materials/material_library.gd` (class `MaterialLibrary`),
tuning in `world_material_tuning.gd` (Resource fields, defaults shown below). Shaders:
`game/world/materials/window_atlas.gdshader`, `water.gdshader`; reused: `shaders/wet_asphalt.gdshader`, `shaders/neon.gdshader`.
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
| M_Brick_Dark/Red/Painted, M_Plaster_*, M_Facade_Tile | Standard, triplanar | CC0 sets, uv_tile_m 1.2 to 2.0 m |
| M_Metal_*, M_Roof_Bitumen, M_Wood_Planks | Standard, triplanar | CC0 sets (corrugated, plate, bitumen, planks) |
| M_RoadPaint | Standard + faint emission | flat colour, emission 0.18 (road_paint_glow) |
| M_Water | ShaderMaterial water.gdshader | asphalt_04 normal, two layers scrolling 0.012/0.007 |
| M_ShopGlass | Standard, alpha | alpha 0.35, roughness 0.05 |
| M_WindowAtlas, M_ShopInterior | ShaderMaterial window_atlas | atlas albedo and emission, threshold glow |
| M_ImpostorAtlas | Standard, per building | impostor_<id>_basecolor / _emissive, emission 2.0 |
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
| window_energy_scale | 1.0 | x JSON window emission (3.0) and shop interior (2.0) |
| window_glow_threshold | 0.6 | atlas values below this do not glow |
| window_glow_saturation | 0.15 | 0 grey glow, 1 raw atlas colour (was 0.5: violet and blue windows) |
| road_paint_glow | 0.18 | road marking self-glow |
| glass_alpha | 0.35 | shopfront glass opacity |
| water_scroll | (0.012, 0.007) | UV units per second |
| lod0_end_m / lod1_end_m | 110 / 260 | building LOD switch distances |
| facade_albedo_scale | 2.2 | window and shop atlas tint x (JSON #202838 was near black, walls read black) |
| window_glow_tint | (1.0, 0.78, 0.5) | colour of lit window glow (warm) |
| ceiling_energy_scale | 0.06 | x JSON energy of M_CeilingStrip and M_TunnelLight (5 and 12 blew out to white) |
| CityBuilder ambient_color, ambient_energy | #2A3F6E, 1.6 | night fill for unlit walls (was #1B2B4D, 0.6) |

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
- No triangle, draw-call or frame-time numbers yet. Performance numbers only come from the perf probe.
