# World Tour: Istanbul, track 1: Maslak - Levent night loop (`istanbul_maslak`)

Original track, no real brands or logos. Sign names are invented (ASCII, because Blender's built-in font has no dotless i or
s-cedilla): GECE KAHVESI, BOGAZ BALIK, LALE PASAJI, YILDIZ SINEMA, KULE KITAP, AY ISIGI, CINAR CAY EVI, SIMIT FIRINI, ZUMRUT OTEL,
MARTI KAFE, MASLAK KULE, LALE PLAZA. The Maslak district is a glass-tower business avenue; no landmark is built or raced through.

## Generic track pipeline (new in this task)
```
assets_src/world/tracks/configs/<id>.json     one config per track: road (control points, widths, districts, tunnel, zebra, QA views)
                                              and layout (district -> building kit, signs, lamps, plaza, skylines, rules)
assets_src/world/tracks/build_road.py         Blender, --config <json> [--render]; writes <out_dir>/<id>_road.glb, <id>_centerline.json
assets_src/world/tracks/build_layout.py       py -3.10, --config <json>; writes <out_dir>/<id>_layout.json
assets_src/world/tracks/<id>/build_props_ist.py   per-track props (new neon sign texts, fountain) through the kit generator
tools/ship_world.py --track <id>              copies road, centreline, layout and per-track props into game/assets/world, registers them
game/world/city_01/city_builder.gd            exports layout_path, road_glb, catalog_path, centre_path (defaults = City 01)
game/world/<id>/<id>.tscn                     root script city_builder.gd with the track's paths and look
```
City 01 stays as it was: `assets_src/world/city_01/build_road.py` and `build_layout.py` are 10-line entry points that pass
`configs/city_01.json`.

### City 01 equivalence (checked)
- Road: regenerated with the generic script: `city_01_road.glb`, `city_01_centerline.json`, `materials.json` are byte-identical to the
  committed files (git reports no change). Only `report.json` `runtime_s` differs (timing).
- Layout: regenerated JSON equals the committed one in lights, probes, racing line, checks, lap length and every instance, except the
  `tris_lod0` / `tris_lod1` of the "AMPERE ENERGY" sign boxes (43 instances). Those numbers come from the kit catalog, which was
  regenerated after the committed layout was written (the catalog already says 1748/221, the committed layout still has 1300/165).
  The committed `city_01_layout.json` was left untouched.
- Engine: 186 of 186 tests passed after the CityBuilder change (before the Maslak test file was added).

## Maslak numbers (generator output)
- Lap 2250.2 m (config range 2000 to 2400), road 18 m, six lanes marked, kerb 0.3 m, sidewalk 3.5 m.
- Min radius 33.7 m (3-point circumradius), max gradient 3.45 %, closest non-adjacent plan approach 122.6 m (arc >= 150 m).
- Elevated viaduct: 271 samples (z up to 4.5 m, s 894 to 1434), fill walls and parapets as in City 01.
- Underpass: 129 samples (s 1540 to 1798), ceiling 5.2 m, tunnel lights.
- Districts: Maslak Avenue (start straight and first bend), Levent Plaza (T1 and the plaza straight, open right side with the fountain),
  Viaduct Reach, Underpass, Esentepe Row (return street).
- Layout: 152 first-row towers (downtown 26 to 44 storeys on the avenue and viaduct, neon 8 to 19 storeys on the plaza and return street),
  109 LOD2-only boxes behind, 695 props, 198 lights, 38 reflection probes.
- Glass: `pane_glow_tint` (pale cyan-white lit windows) and `pane_albedo_tint` (blue-green panes) on CityBuilder. They produce tinted
  copies of M_WindowAtlas and M_ImpostorAtlas per track; the shared library materials are never changed.
- LED crowns: `crown_color`: three emissive strips (front and both sides) on the roof edge of first-row buildings 100 m and taller,
  one MultiMesh draw.
- Lamps: lamp_led_double (cool white), on the elevated deck as well (`lamp_on_deck`).

## Race evidence (desktop, RTX 5060 Ti, Mobile renderer; not phone numbers)
Scenario `race_maslak` (copy of `race_city` on the new track, autopilot player + 5 opponents, 2 laps) and `maslak_districts`
(racing-line shots). Files: `evidence/screens/race_maslak/`, `evidence/screens/maslak_districts/` (each PNG has a .json with perf).
- LOD distances on this track: `lod0_end_m` 45 m (City 01: 70), `lod1_end_m` 140 m. With City 01's values the High racing_10s shot
  was 490 524 primitives (over the 450k budget); the tower LOD0 meshes are 10 to 13k triangles each.
- High (budget 500 draws, 450k primitives): grid 324 draws 275 208 prims, pack 383 / 440 316, racing_10s 383 / 444 304 (4.8 ms avg frame in the earlier run). Low (budget 250 draws): racing_10s_low 210 draws, 266 558 prims. Underpass 236 / 238 987, nitro 271 / 203 669. Pack and racing_10s are within 2 % of the primitive budget.
- Tests: `game/tests/test_istanbul_maslak.gd` (scene build, track data, a 5-AI race through RaceManager, the same race through
  RaceScene with `RaceConfig.track_scene`). The 5-AI race finishes in 63 s simulated with 1 stuck recovery.

## Limits
- No dedicated tunnel or viaduct look beyond the City 01 structure meshes (same materials).
- CityBuilder street dressing (`_dress_districts`) is keyed on the City 01 district names "Waterfront" and "Downtown canyon", so
  Maslak only gets the overpass-approach bollards and the layout props.
- The Bosphorus bridge silhouette is not modelled; the far skyline is the kit's skyline card (4 of them).
- Blender font text is ASCII only, so Turkish letters are written without diacritics.
