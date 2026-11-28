# Night diet, 2026-11-28

Goal: fit the Asphalt-style chase framing (longer look, lower camera) under the High primitive budget
(450 000) and the draw budget (500) on day, sunset and night. Desktop numbers only (RTX 5060 Ti, 1920x1080,
Godot 4.7.2 Mobile, `ortakoy_benchmark`). They are not iPhone numbers.

## Where the night mirror cost goes

The planar road mirror (game/fx/planar_reflection.gd, race_scene.gd `_apply_reflection`) re-renders the scene.
At night, `bench_night_gameplay` with the mirror off drops from 446 065 to 365 033 primitives (-81 k) and from 401 to 318 draws.
Day and sunset have no mirror (`TimeOfDay.road_mirror = false`).

Single-category experiments on `bench_night_gameplay` (each run alone, mirror on, base 444 604 with mirror far 40 m):

| experiment (mirror only) | primitives | draws | note |
|---|---:|---:|---|
| mirror far 60 m (today) | 446 065 | 401 | base, before any edit |
| mirror far 40 m | 444 604 | 392 | far geometry is cheap: -1.5 k only, not used |
| hide MirrorLOD1 street fronts | 444 596 | 392 | ~0 |
| hide greenery | 444 596 | 392 | ~0 |
| hide Props | 443 515 | 385 | -1.1 k |
| hide signs (`*sign*`) | 443 836 | 388 | -0.8 k, the neon look stays |
| hide car-mirror copies (`*_mirror` buildings) | 443 890 | 390 | -0.7 k |
| hide roadside sidewalk/structure/markings/decals | 443 064 | 385 | -1.5 k |
| hide CarFx particles | 444 596 | 392 | 0 |
| hide rival cars from mirror | 417 050 | 365 | -27.5 k |
| hide player car from mirror | 415 755 | 382 | -28.8 k |
| **player car mirror uses the LOD2 copy** | **424 472** | **390** | **-20.1 k, applied** |

Conclusion: the mirror cost is cars. Props, signs, greenery and road-side pieces are each around 1 k and
were not worth a visual change. The player car's mirror copy was the LOD1 copy (about 20 k primitives at 5 m).

## What changed

1. `game/race/race_scene.gd`: new `_cheap_player_mirror(lod)`, called from `_add_car` for the player only
   (`not rival`). It hides the LOD1 mirror copy and shows the existing 7k-tri LOD2 mirror copy at all mirror
   distances. Rivals keep the LOD1/LOD2 split of `car_lod.gd`. Nothing in the main camera changes, because the
   mirror copies sit on the mirror-only layer.
2. `game/camera/chase_camera.gd` (primary framing, applied): `distance_top_m` 5.4 to 5.9,
   `height_m` 1.28 to 1.18, `look_ahead_m` 3.0 to 9.0, `look_height_m` 0.55 to 0.85, `look_inside_m` 1.2 to 2.2.
   The fallback (look_ahead 7.0, look_height 0.75) was not needed.
3. `game/tests/test_driver_camera.gd`: the chase-camera "car angle from view centre" band widened from 10 to 12 deg.
   With look_ahead 9 m the car sits 11.3 deg off centre, still on screen. No other test changed.
4. `mirror far distance`: unchanged at 60 m (race_config `reflection_max_distance_m`). The 40 m cut saved 1.5 k only.

## Numbers after the change (primary framing + player mirror LOD2)

| capture | primitives | draws | budget |
|---|---:|---:|---|
| night gameplay | 440 729 | 408 | < 450 000, < 500 |
| night hero | 425 108 | 376 | |
| night street | 281 711 | 334 | (unchanged, same as before, not framed) |
| day gameplay | 418 740 | 352 | |
| day hero | 378 177 | 310 | |
| sunset gameplay | 418 441 | 361 | |
| sunset hero | 378 377 | 321 | |

Before (today's framing, today's mirror): night gameplay 446 065 / 401, night hero 445 240 / 378.
Framing alone (lead's measurement): 462 532 / 458 842 primitives for primary / fallback.

## Visual check

Read: `evidence/screens/ortakoy_benchmark/bench_night_hero.png` and `bench_night_gameplay.png` (after the change).
The wet road still reflects the mosque lights, the street fronts' lit windows, the rival cars and the player car's
underglow. The player's car reflection is a LOD2 model, softer on the wet road but still readable.

## Tests

- `test_driver_camera`: 22 tests, 0 failed.
- Full suite: 401 tests, 0 failed (baseline 401).
- No new test: `_cheap_player_mirror` only sets visibility on existing copies, and the capture checks cover it.

## Not done

- Phone numbers: not measured (this is a desktop run).
- The fallback framing (look_ahead 7.0 / look_height 0.75) was not measured because the primary fits.
- Mirror LOD2 for the player is not guarded by a test.
- GPU frame time was not measured as a budget, only the primitive and draw counts.

## Lead review re-run (same machine, same day)

- Re-captured `--capture=ortakoy_benchmark` and `--tod=sunset`: night gameplay 441 078 / 409, night hero 425 108 / 376,
  day gameplay 419 053 / 353, day hero 378 177 / 310, sunset gameplay 418 441 / 361, sunset hero 378 377 / 321.
  All under 450 000 and 500.
- The committed `bench_sunset_gameplay.json` has `frame_ms_p99` 155.6 ms (one hitch in 60 frames). The re-run gave
  4.66 ms, so it was a one-off. Frame times are not part of this budget; do not quote that p99.
- The regenerated PNGs show the HUD in Turkish (`Sen`, `km/sa`) where the release baseline showed English. That comes
  from the capture machine's locale, not from this change; primitive and draw counts do not depend on it.
- `bench_*_street.png` changed slightly (pixel noise / rain); its primitives and draws are unchanged.
