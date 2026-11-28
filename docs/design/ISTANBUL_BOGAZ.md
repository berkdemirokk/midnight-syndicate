# World Tour: Istanbul, track 2: Bogaz coast road (`istanbul_bogaz`)

Original track, no real brands or logos. A Bebek to Arnavutkoy style night loop of about 2.2 km, wet and raining. Sign names are invented
(ASCII text, Blender's font has no dotless i or s-cedilla): ISKELE KAHVESI, KAYIK BALIK, KANDIL LOKANTA, MAVI DENIZ, NAR EVI, NAR MEYHANE,
DENIZ KAFE (new for this track) plus the Maslak set (GECE KAHVESI, LALE PASAJI, AY ISIGI, CINAR CAY EVI, SIMIT FIRINI, MARTI KAFE, ...).
The Asian shore, the domes and the suspension bridge are distant silhouette cards across the water. Nothing is raced through, no landmark is replicated.

## Layout (clockwise, Bosphorus on the left)
| Section | district | what |
|---|---|---|
| Bebek Sahil | s 137 to 540 | 14 m coast road, promenade and seaside railing on the water side, yali row (butter, wood, rose) and wooden-house rows with cumba on the land side, start grid, a ferry pier |
| Arnavutkoy Sahil | s 540 to 908 | coast road bends right, second pier, fish and simit carts on the promenade, bridge and domes cards ahead |
| Kalyoncu Sokak | s 908 to 1141 | narrow (10 m) cobbled street, tram rails on the right lane with poles and catenary, ahsap rows, signs on every shop fascia |
| Yokus Tepe | s 1141 to 1379 | short climb to a crest (3.6 m) and the descent, same cobbled street, retaining walls under the road |
| Cengelkoy Donus | s 1379 to 2210 | asphalt again, return street and north street back to the corner |

Numbers (generator): lap 2210.3 m, min radius 40.3 m, max gradient 1.9 %, 347 water-side samples, 306 cobble samples, 2 piers.

## Pipeline additions (all config driven, City 01 and Maslak untouched)
- `assets_src/world/tracks/configs/istanbul_bogaz.json`: road and layout config. New road keys: `narrow_cp` + `narrow_w` (road narrows with 40 m blends),
  `cobble_cp` (road surface slot `M_Cobble`, no paint, no manholes), `piers` (paved slab with skirts and mooring posts over the water).
  New layout keys: `extra_building_catalogs`, `quay` (seaside railing, warm promenade lamps, furniture), `tram` (12 m rail segments on the right lane),
  `pier_lights`, `corner_barriers`, `skylines[].asset`, `plaza[].face`, and `{"cp", "s"}` positions next to `{"i"}`.
- `assets_src/world/tracks/istanbul_bogaz/build_props_bogaz.py`: 7 new invented neon signs through the kit generator.
- `game/world/city_01/city_builder.gd`: building and prop files not found in the City 01 kits resolve in `kits/istanbul/` (`_bld_path`, `_prop_path`);
  the prop category `skyline` is unlimited in distance like `bay` (the cards were culled at 200 m before).
- `game/world/materials/material_library.gd`: `kits/istanbul/materials.json` added, `IstanbulMaterials.handles()` hook in `_build` (the kit report asked for it).
- Scene `game/world/istanbul_bogaz/istanbul_bogaz.tscn`, capture scenarios `race_bogaz` (grid, countdown, racing_10s, pack, drift, cobble, nitro, results) and
  `bogaz_districts` (racing-line shots), test `game/tests/test_istanbul_bogaz.gd`.

## Race and capture evidence
See the numbers at the end of this file (filled from `evidence/screens/race_bogaz/*.json`).

### Numbers (desktop, RTX 5060 Ti, Mobile renderer; not phone numbers)
Scenario `race_bogaz` (real race scene, autopilot player + 5 opponents, 2 laps, High preset, 1920x1080) and a Low run with `--stop-after-10s --preset=low`.
Peak draw calls / primitives per shot: grid 331 / 288 783, countdown 333 / 288 787, pack 371 / 352 036, racing_10s_high 360 / 345 465,
drift 286 / 341 268, cobble street 149 / 222 622, nitro 212 / 195 873, results 88 / 114 211. racing_10s_low: 218 draws / 240 897 primitives.
Budgets: High 500 draws / 450k primitives, Low 250 draws. All shots are inside them. Frame time 2.5 to 6 ms on this machine.
`bogaz_districts` has 10 racing-line shots plus an elevated establishing shot (`evidence/screens/bogaz_districts/`).
Tests: `test_istanbul_bogaz.gd` (4 tests: scene build with kit content and skyline visibility, track data, 5-AI race through RaceManager:
52.8 s, 0 stuck, min upright 0.988; same race through RaceScene: 4 stuck recoveries, limit 8). Full suite 198 passed, 0 failed.

## Limits
- Water is the City 01 `M_Water` plane: dark, reflects the sky only, no moving light reflections of the Asian shore cards.
- The climb (3.6 m) is built as the City 01 elevated deck (fill walls, expansion joints are skipped on cobble) beside houses that stand at ground level.
- Tram rails are bright where lamps hit the metal and read like dashed paint at grazing angles. No tram vehicle.
- Ferry piers are slabs with posts and masts, no ferry boat. Yalis stand on the land side, not over the water.
- 19 lights are dropped by the per-mesh light budget (150 built).
- Parked cars line the promenade kerb (City 01 parked-car pass); a rival that leaves the road at the start can end up beside them (visible in racing_10s).
- Blender sign text is ASCII only.

## Ortakoy 3D row bays: attempt, not shipped (2026-11-28)
Goal (brief): replace the flat photo fronts of the first row the chase camera sees (roughly within 25 m of the road) with modular 3D bays (recessed windows,
cumba, balconies, shop fronts with night glow). Result: the bays look worse than the photo fronts, so nothing is merged into the
game build. Scope actually tried: land-side first-row frontages in the first 900 m of track distance (`MAX_S_M = 900.0` in
`rows_bays.gd`), skipping any bay that would reach inside the 7.3 m race corridor. Branch `wp/ortakoy3d` stays at the base for code; the evidence sheets are kept as the record of this attempt.

What was built (uncommitted, in the worktree and the WIP copies, not in the game):
- `assets_src/world/kit_istanbul_rows/build_rows.py` (Blender 5.3 python): two 6 m bays (a: timber cumba over floors 2-3, b:
  balcony and French door), LOD0 and LOD1 GLBs with the surfaces M_Plaster, M_Trim, M_Wood, M_Glass, M_Glow, M_Iron, M_Awning, M_Roof.
  Triangles: a LOD0 1692 / LOD1 1344, b LOD0 1560 / LOD1 1176.
- `game/world/street_fronts/rows_bays.gd` (RowBays: MultiMesh per 60 m chunk, kind and LOD) and a flag `USE_BAYS` in
  `photo_fronts.gd`. The flag was on only for the AFTER captures and was reverted before the commit.
- `game/tests/test_istanbul_rows.gd` (3 tests). Full suite with the bays code present but the flag off: 470 passed, 0 failed.

Numbers (desktop, RTX 5060 Ti, Mobile renderer, High, 60 frames; not phone numbers). BEFORE = a fresh re-capture of base 0e37938,
not the committed `evidence/screens/ortakoy_benchmark/*.json`; AFTER = bays on. Draw calls and primitives match the committed JSON;
frame times are one 60-frame run each and noisy (night gameplay: 3.38 ms here, 4.17 ms in the committed JSON), so only the day hero
rise is clearly outside the noise:
| shot | draws before to after | primitives before to after | avg frame ms before to after |
|---|---|---|---|
| night street | 334 to 337 | 281,407 to 305,115 | 2.19 to 2.68 |
| night hero | 376 to 375 | 424,444 to 440,736 | 2.30 to 3.13 |
| night gameplay | 409 to 409 | 440,774 to 459,082 | 3.38 to 4.07 |
| day street | 279 to 280 | 251,805 to 277,755 | 1.78 to 1.87 |
| day hero | 310 to 305 | 377,513 to 391,997 | 2.12 to 3.95 |

Looked at (`evidence/screens/before_after_ortakoy3d/`): all six sheets (day and night street, hero, gameplay), by the builder and the
lead reviewer. Every sheet shows the same result; none contradicts the verdict.
Verdict from the pictures: the bays read as flat orange-brown boxes. The plaster texture does not show, every bay has the same
colour, the shop fronts do not read as shops, and the photo fronts (with their signs, awnings and colour variety) are better.
Primitives rise 8 to 10 percent and the frame time rises, with no draw-call saving. Not shipped.

What would have to change before a second try (owner decision on the time): per-bay colour variety (MultiMesh instance colour),
shop signs and awnings on the ground floor, a real plaster albedo and roughness check in a QA render before any capture,
and a check of the photo_fronts test that pins the photo rows on Bogaz (it would have to change with the flag).
Not done: street life (kerbs, lamps, benches, bins, bollards, trees and parked vehicles were not added), no new lamp or tree assets.
