# Time of day (DAY, SUNSET, NIGHT)

`TimeOfDay` (game/world/time_of_day/time_of_day.gd) holds one preset per hour. `RaceConfig.time_of_day`
("day", "sunset", "night", default "night") picks it. `RaceScene` creates the preset (`scene.tod`), tells the track
before it enters the tree (`CityBuilder.time_of_day`), and uses the car, rain, headlight and road fields itself.
NIGHT is the shipped look: `apply_environment` does nothing for it and `tune_material` restores every material value
the class scaled, so a night race after a day race in the same process is unchanged.

## What a preset sets

| Field | DAY | SUNSET | NIGHT |
|---|---|---|---|
| Sun | 58 deg, 165 deg behind the start heading (sun mostly behind the camera, shadows fall ahead and across the road), warm white, 3.0, shadow | 11 deg, 28 deg ahead, orange, 2.4, shadow | moon, no shadow (as before) |
| Sky | `day_sky.gdshader`: blue gradient, sun disk, soft clouds | same shader: pink-orange band, low sun | `night_sky.gdshader` (untouched) |
| Ambient | 30 percent sky radiance + near-neutral white, energy 1.3 (street shade stays grey, not blue) | 30 percent sky radiance + cool blue-violet fill, so shade is cool and sunlit faces stay orange | track values |
| Windows / neon / skyline glow | 0 / 0.18 / 0 (glass reads dark, signs dim) | 0.55 / 0.8 / 0.6 | 1 |
| Street lamps, floodlights, string lights | off | on | on |
| Road wetness / puddles / wall film | 0.12 / 0 / 0.1 | 0.85 / 0.7 / 0.5 | 1 |
| Planar road mirror (High) | off | off | on |
| Rain | off | off | on (when the graphics preset allows) |
| Headlights | off | on | on |
| Car fill and rim | x0.35 and x0.3, white | x0.7 and x0.8, warm | RaceConfig values |

Tunnel strips, traffic signals and road paint keep their light at every hour.

Daylight clean-ups (each a preset field, all restored at night from values stored in meta):

- `crown_scale`: the LED crown strips (`LedCrowns`) on tall towers are hidden at day and sunset (they read as floating
  wireframe lines against a lit sky).
- `container_albedo`: shipping containers and red newspaper boxes (`M_Container_*`, `M_Metal_Red`) are darkened, a flat
  saturated red under a strong sun blew out to a pure red block.
- `impostor_desat` / `impostor_scale`: far-building impostor boxes (`M_ImpostorAtlas`) are pulled toward grey.
- `parked_albedo` / `parked_metal`: parked car paint is lighter and less metallic (dark metallic paint mirrored the sky as flat grey).
- `pane_albedo_scale` (City 01 shader panes) and `pane_std_albedo` (Istanbul tracks, where `M_WindowAtlas` is a
  StandardMaterial3D) lighten the dark glass at sunset so floor slabs no longer read as bright outlines on black.

## Cost rules (measured, see report in the task commit)

- One directional shadow, orthogonal, 70 m, `directional_shadow_size` of the graphics preset, none on Low.
- Sun shadows are paid per caster, so casters are cut: a building casts from a shadows-only copy of its LOD2 box
  (10 triangles), a car from a shadows-only copy of its LOD2 (body, underbody, trim, wheels) on the mirror layer,
  road, ground, water, decals, far LODs and car particles do not cast.
- The planar road mirror re-renders the scene with its own shadow pass: with a mirror and the sun together the
  City 01 sunset peaked at 485 draws and 610k primitives. DAY and SUNSET therefore run without the mirror and rely on
  the GGX sheen of the wet asphalt, the sky radiance and the lamps. NIGHT keeps the mirror and has no shadow.

## Capture

`--capture=tod_tracks` shoots City 01, Maslak and Bogaz at day, sunset and night, 10 s into a race, as
`<track>_<tod>[_<preset>].png`. Options: `--only=maslak:day`, `--tracks=`, `--tods=`, `--sky` (extra wide sky shot),
`--casters` (prints the shadow casters per group), `--flow` (a one-lap race, then grid intro, results and replay shots
as `<track>_<tod>_grid|results|replay`), `--preset=low|medium|high` (the capture harness flag; the shot gets a suffix),
`--red [--px=x,y]` (diagnostic: lists every mesh whose projected bounds cover a screen pixel).

## Per-track grade

`TrackGrade` (game/world/time_of_day/track_grade.gd) adds a colour grade per track on top of the hour's preset.
`RaceScene._build_race` calls `TrackGrade.apply_to_world` once the environment exists, after `TimeOfDay` has written
the hour (one line). The table is keyed by the track scene file: `city_01` (Neon Wharf), `istanbul_maslak`,
`istanbul_bogaz` (Ortakoy/Bogaz). The dev circuit and unknown tracks are not graded.

| Track | Day | Sunset | Night |
|---|---|---|---|
| Neon Wharf (city) | teal ambient in shade, cool fog | teal ambient, cool-grey fog | teal ambient, saturation 1.10, teal fog |
| Maslak | steel-blue ambient, saturation 0.86 | steel-blue ambient, saturation 0.90 | cool ambient, saturation 0.84 |
| Ortakoy/Bogaz | warm shade ambient (blue cut 6 %), saturation 1.05, amber-tinted fog | warm shade ambient (blue cut 8 %), saturation 1.06, amber fog | warm shade ambient (blue cut 6 %), saturation 1.04 |

Each entry sets exposure, contrast, saturation (Environment adjustments), the ambient light colour (rgb multiplier,
at most 1.2) and the depth fog colour (mixed in by `fog_mix`). Values are absolute: each call starts from the
environment's base, the values it held before the last grade. That base is reused only while the environment still
holds exactly what that grade wrote. If `TimeOfDay` (or anything else) wrote the environment since, the current values
become the base, so a race at another hour in the same process is graded from its own preset.
`--no-grade` after the capture arguments skips the grade: the BEFORE switch for the evidence below (never passed by the game).

Limits, stated plainly:

- Split toning is shade only. A procedural 16x16x16 LUT on `adjustment_color_correction` was tried first and drew
  heavy coloured noise on the Godot 4.7 Mobile renderer, so it was removed. Highlight split tones and the magenta
  night highlights of Neon Wharf are NOT done. Follow-up: a non-LUT highlight route (post-process or a 3D texture),
  tested on a capture before anything is claimed.
- The shift is modest. Maslak night (the "cool-white" target) is barely distinguishable from the base in the sheet.
  Ortakoy day is warmer on the walls and less blue on the road, and the sky and the sun are untouched.
- An earlier Ortakoy setting (ambient blue cut 20 %, saturation 1.14) turned the asphalt brown and dimmed the road plane.
  It was reduced to the values above; the road now reads neutral dark asphalt again.
- Performance: see the Grade evidence section. Not established as free on Maslak night.

## Car contact shadow

Already in place before this grade: `ContactShadow` (game/fx/contact_shadow.gd) gives every race car a blob that follows
the road (`attach(car, true)`), traffic cars a child blob and parked cars one MultiMesh per cell, strength by hour
(0.92 day, 0.7 sunset, 0.95 night). It is not duplicated. Covered by test_contact_shadow.gd.
Not verified in this branch: a close car34 shadow-on / shadow-off pair and a wet night road shot. The existing
car34 sheet shows the dark blob under the wheels, but that is not an on/off comparison.

## Grade evidence

`evidence/screens/before_after_grade/`: nine track x hour sheets (`city_*`, `maslak_*`, `bogaz_*`, BEFORE | AFTER,
`--capture=tod_tracks`) and five Ortakoy day sheets (`bench_day_hero`, `bench_day_street`, `bench_day_car34`,
`bench_day_mosque`, `bench_day_gameplay`, `--capture=ortakoy_benchmark --tod=day`). BEFORE is the same build with
`--no-grade`, AFTER is the grade. Raw captures' perf JSON is in `raw/before` and `raw/after`; the PNGs are not committed.

Machine: RTX 5060 Ti (dev PC, not a phone), Vulkan, Mobile renderer, preset high, 1920x1080. Each figure is one
60-frame probe, so frame times carry run-to-run noise of about 0.5 to 1 ms on this PC.

Draw calls, one probe each (before / after): bogaz day 300 / 300, bogaz sunset 310 / 310, bogaz night 355 / 355,
maslak day 326 / 326, maslak night 366 / 366, city night 420 / 419, city day 373 / 375. The grade adds no draw calls.

Frame time, average ms, runs in order (before / after):
- bogaz night (3 runs each): 3.95, 4.13, 3.57 / 4.18, 3.65, 3.36. Median 3.95 / 3.65. No slower.
- maslak night (3 runs each): 4.11, 4.48, 4.18 / 7.04, 7.74, 3.97. Median 4.18 / 7.04. Two of three after runs are slower
  and this is not explained by draw calls. Not resolved: other sessions were using the GPU at the same time, so this is
  not a clean measurement. Treat Maslak night as NOT shown to be free until re-measured on an idle GPU.
- city night (1 run each): 4.87 / 4.76.

Clipping: luma_max in the capture JSON. Bogaz day 1.000 / 1.000, bogaz sunset 0.997 / 0.997, bogaz night 1.0 / 1.0, city day
1.000 / 1.000, maslak sunset 0.960 / 0.989 (rises, still below 1.0), maslak night 1.0 / 1.0. No shot reaches a
new hard clip, but the highlight regions of the sheets were not inspected one by one, so "highlights preserved" is not claimed.

Ortakoy day sheets: `bench_day_car34` now keeps the road neutral; the earlier brown road is gone. The change is subtle.
