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
