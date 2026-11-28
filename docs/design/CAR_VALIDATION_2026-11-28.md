# Car validation 2026-11-28

Scope: the 11 catalog cars in game/vehicles/car_catalog.gd. Branch wp/cars, base 8f44660 (release/rc-2026-11-28 before the reviewfix merge).

Verdict: spec, studio visual, wheel arches, race night and race day pass for all 11 cars. The LOD0 render budget (20 objects/draw calls) fails for all 11 cars, and that fix is out of scope. LOD pops cannot be judged from still frames.

## Automated checks (game/tests/test_car_validation.gd, 4 tests, all PASS)

- Scene loads, LOD0/LOD1/LOD2 present, all required nodes present: PASS for all 11.
- Spec sanity (mass, wheel radii, track, wheelbase, body width, top speed, engine, brake, grip, display_name), and rivals >= 252 km/h track speed: PASS for all 11.
- Wheel centres at spec radius (+-0.03 m) at LOD0, so wheels touch the ground: PASS for all 11.
- LOD0 visible mesh nodes <= 20: PASS (17 each). This guards the node count only. It is not the render budget (see below). Surfaces per car are recorded as metrics: 25 to 27.
- Full headless suite on wp/cars: 461 tests, 0 failed (base 8f44660 has 457, plus these 4). The 463 on the RC commit a0155a5 includes 6 reviewfix tests that are not on this branch.

## Per-car table

Studio = car_studio_<id> scenario (front34, rear34, side, wheel_closeup, lights_on, paint_variants; Atmaca: modified_*, stock_*, taxi_*, paint_row). Race = `--capture=ortakoy_benchmark --tod=night|day --car=<id>` (car34, hero, gameplay, mosque, street shots).

| Car | Spec + wheels (test) | Studio visual | Wheels in arches | Object budget LOD0 | Race night | Race day | LOD pops | Studio PNG |
|---|---|---|---|---|---|---|---|---|
| noctra_tayfun (street) | PASS | PASS | PASS | FAIL (59 objects, 59 draw calls; empty studio 20) | PASS | PASS | not evaluable | evidence/screens/car_studio_tayfun/front34.png |
| noctra_sable (street) | PASS | PASS | PASS | FAIL (59 objects, 59 draw calls; empty studio 20) | PASS | PASS | not evaluable | evidence/screens/car_studio/front34.png |
| atmaca_modified (classic) | PASS | PASS | PASS | FAIL (59 objects, 59 draw calls; empty studio 20) | PASS | PASS | not evaluable | evidence/screens/car_studio_atmaca/modified_front34.png |
| noctra_vela (hatch) | PASS | PASS | PASS | FAIL (59 objects, 59 draw calls; empty studio 20) | PASS | PASS | not evaluable | evidence/screens/car_studio_vela/front34.png |
| arden_bruiser (muscle) | PASS | PASS | PASS | FAIL (59 objects, 59 draw calls; empty studio 20) | PASS | PASS | not evaluable | evidence/screens/car_studio_bruiser/front34.png |
| kestrel_gtr (gt) | PASS | PASS | PASS | FAIL (59 objects, 59 draw calls; empty studio 20) | PASS | PASS | not evaluable | evidence/screens/car_studio_kestrel/front34.png |
| kestrel_vanta (super) | PASS | PASS | PASS | FAIL (59 objects, 59 draw calls; empty studio 20) | PASS | PASS | not evaluable | evidence/screens/car_studio_vanta/front34.png |
| arden_havoc (muscle) | PASS | PASS | PASS | FAIL (59 objects, 59 draw calls; empty studio 20) | PASS | PASS | not evaluable | evidence/screens/car_studio_havoc/front34.png |
| kestrel_marten (sport) | PASS | PASS | PASS | FAIL (59 objects, 59 draw calls; empty studio 20) | PASS | PASS | not evaluable | evidence/screens/car_studio_marten/front34.png |
| noctra_meridian (gt) | PASS | PASS | PASS | FAIL (59 objects, 59 draw calls; empty studio 20) | PASS | PASS | not evaluable | evidence/screens/car_studio_meridian/front34.png |
| bosfor_yildirim (hyper) | PASS | PASS | PASS | FAIL (59 objects, 59 draw calls; empty studio 20) | PASS | PASS | not evaluable | evidence/screens/car_studio_yildirim/front34.png |

Studio visual PASS covers: no missing, pink or white materials; tail lamps red; brake glow in lights_on; glass not opaque black; plate readable; paint reflection sane; no floating parts. The red ring at the Atmaca modified front and rear bumpers is a tow hook, part of the model, not a floating part.

Wheels in arches: judged on side.png of each studio dir (Atmaca: modified_side.png) and on the race car34 shots.

Race PASS covers: wheels on the ground, red tail lamps, readable plate, nitro flames, no missing materials, for night and day.

## Object budget (FAIL for all 11)

- Studio perf JSON (front34.json; Atmaca modified_front34.json): objects 59 and draw_calls 59 for every car. The empty studio (empty_studio.json, every dir except Atmaca, which has none) is 20, so each car adds 39 at LOD0, about twice the 20 budget.
- Mesh surfaces at LOD0: 25 to 27 per car (test metrics). Each material surface is its own draw.
- Fix: merge meshes or materials per car (atlas the trim, lamp and interior materials). That is bigger than a small defect and is not done here.

## LOD pops

Every capture is a still frame, so a pop between frames cannot be seen. No LOD artefact shows in any race still. A moving-camera capture would be needed to judge this.

## Evidence

- Studio: evidence/screens/car_studio*/ (11 dirs, re-captured on this branch).
- Race contact sheets (11 cars, order as the table, 480 px tiles): evidence/screens/car_studio_race/race_{night,day}_{car34,hero,gameplay}.jpg.
- Race full-size PNG and perf JSON: evidence/screens/ortakoy_benchmark/bench_<tod>_<shot>_<id>.png. About 2.4 MB each (106 MB for car34 and gameplay alone), so they are not committed. Re-create them with the race command above.

## Caveats

- Studio and race checks were made on contact sheets (480 to 960 px tiles), with spot checks at full size for tayfun lights_on and the tayfun race car34 shot.
- The lod2 studio shots at 100 m are almost black in the dark studio and were not judged.
- No small defects were found, so game/vehicles/** is unchanged.
