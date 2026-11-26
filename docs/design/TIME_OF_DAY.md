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
