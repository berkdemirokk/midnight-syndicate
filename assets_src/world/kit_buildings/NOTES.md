# Building kit (Environment Agent) - notes

Owner folder: assets_src/world/kit_buildings/. No git commits made.

## Run
- Build (deterministic, seed 20261124): `blender.exe --background --factory-startup --python build_buildings.py -- build`
- QA renders: `... -- render beauty|sheet|close` (EEVEE, 1600x900). Renders hook CC0 textures onto the M_ slots locally; GLBs carry no images.
- Files: build_buildings.py (generator), render_buildings.py (QA only), out/ (20 GLBs, textures, materials.json, catalog.json, report.json, build_log.txt), renders/.

## What is built
10 types x 2 variants (a, b) = 20 GLBs `bld_<type>_<variant>.glb`:
- neon_01 (a 8 / b 10 storeys), neon_02 (13 / 16), neon_03 (19 / 15, roof billboard frame): commercial strips, blade anchors.
- downtown_01 (26 / 30), downtown_02 (36 / 42), downtown_03 (44 / 32): 4-storey podium, curtain-wall tower with mullion relief, spandrels, 3-floor crown with red aircraft lights, antenna.
- market_01 (3 / 2), market_02 (4 / 5): brick and plaster shophouses, awnings, shutters, one blade anchor.
- waterfront_01 (a 24x40 / b 30x34 m): corrugated gable warehouse, roller doors with slats, jambs and header; no ribs across openings.
- parking_01 (5 decks, a 30x40 / b 36x40 m): open front decks, lit ceiling strips, columns, switchback ramps on the street side (rise from 8 m out), side ramp.
Variant b has its own massing (ALT_B table in the generator); a keeps SPECS dimensions.

## Round 2 fixes (review of 6/10)
- Podium trims moved off the shingle-reading slot; M_Facade_Tile repeat 6 m -> 1.2 m (slot now unused, reserved). Downtown_03a base moved off M_Concrete_Panels (basketweave look at the base).
- M_ShopInterior is a 1024 px atlas with four 512 cards: goods shelves, cafe, boutique (mannequins, rails), bar. Each shop takes a card by offset plus index, so shops on one building differ.
- M_ShopGlass is BLEND with alpha 0.25 in the GLB (materials.json alpha, alpha_mode). Interior card shows through.
- Blade anchors on towers (2, tower front) and markets (1, upper front). Neon as before.
- Variant b massing differs (storeys, width, depth, bays, shops): see catalog.json.
- Warehouse rib boxes no longer cross doors or windows.
- Tower beauty at 14 m crops the tower by design. Added beauty_full_bld_downtown_0N.png: camera back to max(200 m, 1.6 x height), so base and crown are in frame.

## Numbers (report.json, LOD0 tris)
| building | a | b | LOD1/LOD0 (max) | LOD2 |
|---|---|---|---|---|
| neon_01 | 3468 | 3624 | 0.21 | 10 |
| neon_02 | 4596 | 6932 | 0.22 | 10 |
| neon_03 | 8170 | 7522 | 0.21 | 10 |
| downtown_01 | 10050 | 10978 | 0.12 | 30 |
| downtown_02 | 13170 | 13194 | 0.13 | 30 |
| downtown_03 | 11302 | 10802 | 0.15 | 30 |
| market_01 | 3918 | 3338 | 0.05 | 10 |
| market_02 | 4870 | 4934 | 0.06 | 10 |
| waterfront_01 | 3202 | 3058 | 0.07 | 16 |
| parking_01 | 3518 | 3758 | 0.18 | 10 |
All LOD0 within budget (3000 to 12000; towers to 18000). All LOD1 at most 30 % of LOD0. One box collider per building: `<id>-colonly`.
Note: the earlier 2950-tri waterfront_01_b is fixed by door jambs and headers.

## Materials and textures
- materials.json: one record per M_ slot (base colour, roughness, metallic, emission, alpha where used, uv rule, CC0 paths under game/assets/textures/cc0/<id>/ or generated files). Coordinates godot_y_up.
- CC0 slots map to the sets listed in CC0_SLOTS; UVs in metres, tiled every uv_tile_m.
- Generated: window_atlas_basecolor/emissive.png (2048, 8x8 tiles), shop_interior_basecolor/emissive.png (1024, 2x2 cards), impostor_<id>_basecolor/emissive.png (512 each, one per building; TL front, TR back, BL left, BR right, roof patch in BL corner).
- Flat slots: M_Frame, M_SignBand (neutral, empty), M_ShopGlass (alpha 0.25), M_Awning_Red/Teal, M_Aircraft_Red, M_CeilingStrip, M_CollisionOnly.

## Anchors (catalog.json, godot coordinates relative to origin)
- anchor_sign_XX on each shopfront fascia (strip, tower podium, market, parking).
- anchor_blade_XX: neon (2-3), downtown (2, tower front), market (1). Warehouse and parking have none (not in brief).
- anchor_roof_01: billboard face (neon_03), tower crown (downtown), warehouse ridge.

## Evidence (renders/)
- beauty_bld_<type>.png: street level, 28 mm, eye 1.6 m, 14 m road to the facade (10 images, variant a).
- beauty_full_bld_downtown_0N.png: whole tower, 28 mm, back 200 m or more (3).
- lineup_elevation.png: all 10 types, variant a, LOD0, orthographic.
- close_shopfront.png, close_window_reveal.png, close_rooftop.png.
Round 3 renders looked at: shop cards differ within a building, podium reads as brick or smooth concrete, parking ramp visible, waterfront doors read as doors.

## Known defects / not done
- No bloom: EEVEE in Blender 5.3 here has no bloom; neon glare is for the engine.
- Shop glass alpha 0.25 is a BLEND material: engine must sort it after opaque geometry.
- Parking reads as open decks with solid side walls; no full envelope or mesh screen.
- Shop interior is a flat card with simple silhouettes, not modelled stock.
- Impostor textures are per building: the engine binds the building's own file, not one shared material.
- Tower beauty at street level still crops the crown by design; full view is the separate render.
- Not done: copy into game/assets/ and city_01_layout.json placement.
- Asset factory: 64 records registered (20 GLBs, window atlas pair, shop pair, 40 impostor files). All 64 pass `validate`. The overall validate run shows other agents' records and pre-existing CC0 sha256 mismatches (50 failing records in total); not touched here.
