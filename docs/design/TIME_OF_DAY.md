# Time of day (DAY, SUNSET, NIGHT)

`TimeOfDay` (game/world/time_of_day/time_of_day.gd) holds one preset per hour. `RaceConfig.time_of_day`
("day", "sunset", "night", default "night") picks it. `RaceScene` creates the preset (`scene.tod`), tells the track
before it enters the tree (`CityBuilder.time_of_day`), and uses the car, rain, headlight and road fields itself.
NIGHT is the shipped look: `apply_environment` does nothing for it and `tune_material` restores every material value
the class scaled, so a night race after a day race in the same process is unchanged.

## What a preset sets

| Field | DAY | SUNSET | NIGHT |
|---|---|---|---|
| Sun | 66 deg, 200 deg behind the start heading, warm white, 2.0, shadow | 9 deg, 28 deg ahead, orange, 1.7, shadow | moon, no shadow (as before) |
| Sky | `day_sky.gdshader`: blue gradient, sun disk, soft clouds | same shader: pink-orange band, low sun | `night_sky.gdshader` (untouched) |
| Ambient | sky radiance 55 percent + neutral warm | sky radiance + violet | track values |
| Windows / neon / skyline glow | 0 / 0.18 / 0 (glass reads dark, signs dim) | 0.55 / 0.8 / 0.6 | 1 |
| Street lamps, floodlights, string lights | off | on | on |
| Road wetness / puddles / wall film | 0.12 / 0 / 0.1 | 0.85 / 0.7 / 0.5 | 1 |
| Planar road mirror (High) | off | off | on |
| Rain | off | off | on (when the graphics preset allows) |
| Headlights | off | on | on |
| Car fill and rim | x0.35 and x0.3, white | x0.7 and x0.8, warm | RaceConfig values |

Tunnel strips, traffic signals and road paint keep their light at every hour.

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
`--casters` (prints the shadow casters per group).
