# CITY 01 props kit (Environment Agent) - notes

## Files
- `build_props.py` - deterministic generator (Blender 5.3, `--background --factory-startup --python`). Writes `out/`.
- `render_props.py` - evidence renders. Args: `contact | signs | signs_close | corner | bay`.
- `out/prop_<id>.glb` x43 (LOD0 visuals + colliders only), `out/prop_<id>_lod1.glb` x18 (LOD1 files),
  `out/textures/` (poster_01..06.png 1024x512, skyline_night.png 2048x512), `out/materials.json`,
  `out/catalog.json` (coords godot_y_up, `lod1_file` per item), `out/report.json` (all_pass = true).
- `renders/` - contact_sheet, neon_sign_wall, neon_blade_signs, neon_arrow_and_24h_closeup, street_corner, bay_backdrop (1600x900, EEVEE, Standard view).

## Conventions
- Blender: metres, Z up, every prop faces -Y. Godot: godot = (bx, bz, -by). Catalog positions use that conversion.
- Origins: ground props on ground contact; wall signs at the wall face; billboard at roof surface; spans at left anchor base.
- Colliders: `jersey_barrier-colonly`, `guardrail_segment-colonly` (box). Nothing else has a collider.
- LOD1: for props above 800 tris, a separate file `prop_<id>_lod1.glb` (<= 35% tris). It is NOT in the main GLB.
  The engine loads it as the LOD1 level and never draws it together with LOD0.
  Neon sign LOD1 is a flat caps-only stand-in for the tube letters (tube decimation cannot reach 35%).
- Materials: named `M_*` slots only, no images in any GLB. Look per slot in `materials.json`.
- Neon letters: each glyph outline is a round tube of radius 11 mm, standing off the face by 11 mm
  (text converted by the built-in font, curve resolution 3). Emissive strength 9 on the neon slots.
- Blade signs: text sits on the +X face and reads toward +Y. Place a copy rotated 180 deg about Z for the other traffic direction.

## Numbers (tris = LOD0 visible; GLB total = LOD0 + colliders; catalog `tris` is LOD0 visible)
- Lamps: sodium 912, LED double 752, traffic light 972.
- Signs (12): blades 1144-1984, fascia 4 m 1268-1300, fascia 8 m 1772-2308, arrow 1648, open/24H 2628, billboard 12x5 2288. All in 400-3000.
- Posters 110 each. Furniture 204-972. Jersey barrier 36 (+12 collider), guardrail 108 (+12), chevron 168, cone 396, quay railing 340, tunnel fan 312, wall light 120.
- Overhead: cable span 588, string lights 1164. Bay: containers 1872, gantry crane 2456, skyline card 80.

## Registration
- `py -3.10 tools/asset_factory.py register` re-run (upsert by id) for 43 GLBs `props_kit_<id>` and 18 LOD files `props_kit_<id>_lod1`, from `assets_src/world/kit_props/out/`.
- `validate`: all kit records pass. The 22 failing records are CC0 records outside this kit (sha256 mismatch), not touched here.
- Textures: props_kit_tex_* re-registered after the text rename (poster_03 changed). All 68 kit records pass validate; the rebuild changed GLB bytes for every kit file, so all were re-registered.

## Fixed in this round
- Neon glow: compositor Glare (Bloom) now works on Blender 5.3 (compositor is a node group, Glare type is an input socket). Renders show the glow. The engine's own glow still applies in game.
- Neon letters are tubes, not flat stickers. Diamond O fixed by curve resolution.
- Sodium lamp: lantern hood plus emissive lens and bulb.
- Jersey barrier: base, sloped wall and top lip (still simple, reads as a block at distance).
- Arrow sign text enlarged to 0.8 x 0.4 m, kept inside the shaft.
- LOD1 separated into its own file. GLB tri totals now match catalog + colliders (kapi 1272, container 1872, gantry 2456).
- Traffic light red reads red in renders (Standard view transform, was AgX washing it pink-white).
- Render: wall shot camera re-aimed, rooftop slab under the billboard, bay camera re-framed so the container stack is whole.

## Known defects (honest, still open)
- Blade signs in the wall shot are seen at grazing angles, so the far ones read as thin slivers. Better wall view needs a separate camera set.
- Contact sheet labels are still small at 1600x900 and the bottom row is clipped. The skyline card position was not confirmed in the sheet.
- Bus shelter advert panel is a dim strip; roller shutter is a flat slab. Not changed.
- Bay render shows a blurred lit-window band under the skyline base. The skyline texture itself has one skyline and no mirrored band, so the cause is in the scene (not established).
- Sign and poster names renamed to avoid real drink brands: KIRIN NOODLE BAR -> KOI NOODLE BAR, VOLT ENERGY -> AMPERE ENERGY (sign and poster 03). Catalog ids and GLB file names unchanged. "EFES TEA HOUSE" is not in this kit (no sign, poster or text uses it).
- Stale renders: contact_sheet.png, bay_backdrop.png, street_corner.png and neon_arrow_and_24h_closeup.png were not re-rendered and may still show the old sign text.
- Open items: sign text is a single built-in font (no custom typeface); poster art has no logos.
