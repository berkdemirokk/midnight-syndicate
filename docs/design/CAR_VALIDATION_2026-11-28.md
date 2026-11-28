# Car validation 2026-11-28

Scope: 11 catalog cars (game/vehicles/car_catalog.gd). Branch wp/cars, worktree wp-cars, base release/rc-2026-11-28.

## Automated checks (game/tests/test_car_validation.gd, 4 tests, all PASS)

- Scene loads, LOD0/LOD1/LOD2 present, all REQUIRED nodes present: PASS for all 11.
- Spec sanity (mass, wheel radii, track, wheelbase, body width, top speed, engine, brake, grip, display_name); rivals >= 252 km/h track speed: PASS for all 11.
- Wheel centres at spec radius (+-0.03 m) at LOD0: PASS for all 11.
- LOD0 visible MeshInstance3D nodes <= 20: PASS (17 each). Surface count (25-27) is recorded as a metric, see the budget FAIL below.
- Full headless suite: 461 tests, 0 failed.

## Per-car table

Studio = contact sheet of front34, rear34, side, wheel_closeup, lights_on, paint_variants. Race = ortakoy_benchmark --car=<id>.

| Car | Spec and wheels (test) | Studio visual | Object budget LOD0 | Race night | Race day | Studio front34 PNG |
|---|---|---|---|---|---|---|
| noctra_tayfun (street) | PASS | PASS | FAIL | PASS (viewed) | PASS (viewed) | evidence/screens/car_studio_tayfun/front34.png |
| noctra_sable (street) | PASS | PASS | FAIL | PASS (viewed) | not captured in time box | evidence/screens/car_studio/front34.png |
| atmaca_modified (classic) | PASS | PASS | FAIL | not captured in time box | not captured in time box | evidence/screens/car_studio_atmaca/front34.png |
| noctra_vela (hatch) | PASS | PASS | FAIL | not captured in time box | not captured in time box | evidence/screens/car_studio_vela/front34.png |
| arden_bruiser (muscle) | PASS | PASS | FAIL | not captured in time box | not captured in time box | evidence/screens/car_studio_bruiser/front34.png |
| kestrel_gtr (gt) | PASS | PASS | FAIL | not captured in time box | not captured in time box | evidence/screens/car_studio_kestrel/front34.png |
| kestrel_vanta (super) | PASS | PASS | FAIL | not captured in time box | not captured in time box | evidence/screens/car_studio_vanta/front34.png |
| arden_havoc (muscle) | PASS | PASS | FAIL | not captured in time box | not captured in time box | evidence/screens/car_studio_havoc/front34.png |
| kestrel_marten (sport) | PASS | PASS | FAIL | not captured in time box | not captured in time box | evidence/screens/car_studio_marten/front34.png |
| noctra_meridian (gt) | PASS | PASS | FAIL | not captured in time box | not captured in time box | evidence/screens/car_studio_meridian/front34.png |
| bosfor_yildirim (hyper) | PASS | PASS | FAIL | not captured in time box | not captured in time box | evidence/screens/car_studio_yildirim/front34.png |

Studio PASS covers: no missing or pink materials, tail lamps red, brake glow in lights_on, glass not opaque black, plate readable at tile size, paint reflection sane, no floating parts.

## Object budget (FAIL for all 11)

- Node count at LOD0 is 17 per car: PASS against a 20 limit.
- Mesh surfaces at LOD0 are 25-27 per car (scene tree, headless).
- Studio perf JSON: the LOD0 car adds 39 objects and 39 draw calls over the empty studio (20) for every car (front34.json vs empty_studio.json). LOD1 adds 63, LOD2 adds 33.
- Cause: about 27 material surfaces per car, and perf counts 39 objects. The 20 limit is exceeded on every car. Fix is merging meshes or materials per car, bigger than a small defect, not done here.

## LOD and race checks
- LOD pops in race shots: not evaluated in detail; only tayfun and sable race shots were viewed.
- lod2 studio shots at 100 m are almost black in the dark studio. Not judged.

## Evidence

- noctra_tayfun: evidence/screens/car_studio_tayfun/ (front34, rear34, side, wheel_closeup, lights_on, paint_variants .png)
- noctra_sable: evidence/screens/car_studio/ (front34, rear34, side, wheel_closeup, lights_on, paint_variants .png)
- atmaca_modified: evidence/screens/car_studio_atmaca/ (front34, rear34, side, wheel_closeup, lights_on, paint_variants .png)
- noctra_vela: evidence/screens/car_studio_vela/ (front34, rear34, side, wheel_closeup, lights_on, paint_variants .png)
- arden_bruiser: evidence/screens/car_studio_bruiser/ (front34, rear34, side, wheel_closeup, lights_on, paint_variants .png)
- kestrel_gtr: evidence/screens/car_studio_kestrel/ (front34, rear34, side, wheel_closeup, lights_on, paint_variants .png)
- kestrel_vanta: evidence/screens/car_studio_vanta/ (front34, rear34, side, wheel_closeup, lights_on, paint_variants .png)
- arden_havoc: evidence/screens/car_studio_havoc/ (front34, rear34, side, wheel_closeup, lights_on, paint_variants .png)
- kestrel_marten: evidence/screens/car_studio_marten/ (front34, rear34, side, wheel_closeup, lights_on, paint_variants .png)
- noctra_meridian: evidence/screens/car_studio_meridian/ (front34, rear34, side, wheel_closeup, lights_on, paint_variants .png)
- bosfor_yildirim: evidence/screens/car_studio_yildirim/ (front34, rear34, side, wheel_closeup, lights_on, paint_variants .png)
- Atmaca modified: evidence/screens/car_studio_atmaca/modified_*.png and paint_row.png
- Race tayfun: evidence/screens/ortakoy_benchmark/bench_night_*_noctra_tayfun.png and bench_day_*_noctra_tayfun.png
- Race sable night: evidence/screens/ortakoy_benchmark/bench_night_*_noctra_sable.png

## Caveats and not done
- Studio and race shots were viewed as 640 px contact sheets, not opened one by one at full size. Plate and lamp details are confirmed only at that scale.
- Race captures for 9 cars were still running when this doc was written and were not finished. Those rows are not claimed as PASS. The runner could not be stopped (permission denied), so ortakoy_benchmark outputs are not committed.
- No small defects were found, so no game/vehicles changes were made.
- Not done: race night and day for 9 cars, full-size PNG review, race LOD pop review, the object budget fix.
