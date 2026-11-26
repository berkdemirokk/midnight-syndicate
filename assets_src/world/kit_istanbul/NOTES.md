# Istanbul kit (World Tour: Istanbul) - notes

Run: `blender.exe --background --factory-startup --python build_istanbul.py -- build` (deterministic, seed 20261126),
then `py -3.10 ship_istanbul.py` (copy to `game/assets/world/kits/istanbul/`, register in ASSET_MANIFEST.json).
QA: `render_istanbul.py -- yali3q|yali|rows|lod|props_close|tram|sky` into `renders/`.
Reuses `kit_buildings/build_buildings.py` (Builder, Face, window atlas, impostor atlas) and `kit_props/build_props.py` (Geo, build_prop).

## Content (one `catalog.json`: `buildings[]` in the building-kit format, `items[]` in the props-kit format)
| id | what | LOD0 / LOD1 / LOD2 tris |
|---|---|---|
| bld_yali_a | butter pastel yali, 3 floors, 2 stacked cumba bays | 4460 / 396 / 16 |
| bld_yali_b | dark-wood yali, 2 floors, 24 m, 1.7 m eaves, 3 cumba | 3814 / 318 / 16 |
| bld_yali_c | dusty-rose yali, 3 floors, central 2-floor bay | 4238 / 334 / 16 |
| bld_ahsap_row_a | 3 pastel houses (3-4 floors), shops, cumba | 3968 / 488 / 36 |
| bld_ahsap_row_b | 4 narrow wooden houses, green shutters | 4218 / 550 / 48 |
| bld_ahsap_row_c | old apartment row, balconies, cumba, shops | 6484 / 648 / 36 |
| tram_rail_segment | 12 m bed, 2 rails, 2 poles, catenary | 1476 (LOD1 442) |
| cobble_strip | 12 m granite kerb, setts, cobble field | 1764 (LOD1 528) |
| seaside_railing | 6 m cast-iron railing, 4 scroll rings | 1636 (LOD1 489) |
| promenade_lamp | 4.9 m lamp, light in catalog | 928 (LOD1 278) |
| simit_cart / fish_cart | original wheeled stalls, no text, light in catalog | 1924 / 1388 |
| ferry_pier_light | 5.3 m mast, cool light + red marker | 732 |
| skyline_asia_hills / skyline_bridge / skyline_domes | far cards 551 / 513 / 416 m, mesh cut to the silhouette | 602 / 454 / 750 |

Conventions as the other kits: Blender Z up, front faces -Y, godot = (bx, bz, -by). Long props run along +X from the origin.
Tram: poles on +Y, arms reach to the track centre. Cobble strip: kerb on -Y (road side), field on +Y.
Buildings: anchors `anchor_sign_NN` (yali: above the door; rows: on each shop fascia) for invented Turkish sign names.
Skyline cards: curved arc R 900 like prop_skyline_card, u along the arc, v up; place at the far water side, faces -Y.

## Materials
New names only in `materials.json` (existing M_ names come from the other three files): M_Plaster_Butter/Rose/Sky/Sage/Ochre/Cream
(CC0 plaster sets, tinted, they match the wet-facade prefix), M_Wood_Yali_Dark / M_Wood_Oxblood (CC0 planks, tinted),
M_Paint_Shutter_Green, M_Paint_Door_Blue, M_Roof_Tile and M_Cobble (generated, project-owned), M_Cart_Teal, M_Simit_Dough,
M_Fish_Silver, M_Skyline_Asia/Bridge/Domes (single texture, albedo = emission). Code for the skyline ones: `game/world/materials/istanbul_materials.gd`.

## Honest limits
- Not placed in a track and no in-engine capture yet, so no draw-call or primitive numbers for Istanbul. Blender renders only.
- LOD2 impostor shows white in the QA renders (QA does not hook the impostor atlas); the game binds the atlas by building id.
- Blender warns that several prop meshes are "not valid" on glTF export (degenerate pole faces of spheres); the GLBs load and render.
- QA lights are Blender point lights, not the game's lamps; pastel plasters will look different under the wet-facade shader.
- Sign names are not baked in; the sign anchors are empty.
