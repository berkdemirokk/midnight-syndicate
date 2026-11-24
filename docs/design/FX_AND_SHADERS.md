# FX and shaders (Shader Agent)

Code: `game/shaders/`, `game/fx/`. Tests: `game/tests/test_fx.gd` (10 pass, `--only=test_fx`).
Capture rigs: `game/devtools/scenarios/fx_wet_road.gd`, `fx_showcase.gd`. Both use test geometry
(a grey block, a flat road, plain walls). That geometry is a test rig, not art.
Renderer: Mobile. No SSR, SSAO, SDFGI or volumetric fog. The wet look is faked with roughness,
darkening, ripple normals and an optional mirror texture.

## Pieces
| Piece | Files | What it does |
|---|---|---|
| Wet asphalt | `shaders/wet_asphalt.gdshader` | World-XZ UV in metres. R vertex colour = puddle mask, G = groove wear. Damp darkening, puddle roughness 0.08, damp roughness 0.2. Damp and puddle areas flatten the texture normal (that detail caused glints). 2 layers of rain-ring normals in puddles, edge-faded per cell. Optional mirror lookup. |
| Planar reflection | `fx/planar_reflection.gd` (PlanarReflection) | SubViewport at `resolution_fraction` of the screen. Mirrored Camera3D about `plane_height`. Each frame it sets `planar_vp` (mirror projection * view) on every target material, and the shader projects each road point into the mirror view. |
| Neon | `shaders/neon.gdshader` | Unshaded HDR emissive. Per-instance flicker. Optional UV scroll for arrow signs. |
| Speed lines | `shaders/speed_lines.gdshader`, `fx/speed_lines.gd` | Full-screen radial streaks. `set_intensity(v)` clamps to 0..1. |
| Rain | `fx/rain.gd` | Stretched streaks and ground splashes in a box that follows the camera. Off when `rain_enabled` is false. |
| Nitro | `fx/nitro_flame.gd` | Two additive flames, a hot core, an ignition pop (one-shot, explosive) and one OmniLight. `set_strength` scales length. |
| Tyre smoke | `fx/tire_smoke.gd` | Grey lit puffs at rear contacts, peak alpha 0.25, drift from lateral velocity, 1.0 s fade, pixel fade near the lens (1.5 to 5 m). Amount is set by CarFx. |
| Sparks | `fx/sparks.gd` | Pool of 4 one-shot bursts (explosive, gravity, stretched). `burst(world_pos)`. |
| Headlights | `fx/headlights.gd` | Two SpotLight3D, soft cone, short range, no shadows. |
| Car FX | `fx/car_fx.gd` (CarFx) | Child of an ArcadeCar. Drives everything from `nitro_started/ended`, `hit`, and `speed_kmh`, `wheel_slip`, `is_drifting`, `linear_velocity`. |

## Exports and uniforms
- wet_asphalt: `albedo_tex`, `normal_tex`, `roughness_tex`, `tile_metres` (4), `wetness`, `puddle_level`, `rain_intensity`, `tint`, `planar_reflection`, `planar_enabled` (0/1), `planar_vp` (mat4, set by PlanarReflection).
- neon: `base_color`, `energy` (0..16), `flicker_phase` (instance), `flicker_amount`, `flicker_speed`, `scroll_speed`, `mask_tex`, `use_mask`.
- PlanarReflection: `plane_height`, `resolution_fraction` (0.33), `every_second_frame`, `excluded_layers` (default bits 1 and 9: road on layer 2, rain on layer 10). Bit 0 must stay in the mirror.
- CarFx: `exhaust_points`, `rear_wheel_offsets` (wheelbase 2.66 m, rear track 1.64 m; contact height and exhaust points are estimates, not checked against the model), `smoke_slip_deg` (8.0, rear slip angle where smoke starts), `smoke_launch_max_kmh` (40), `smoke_launch_throttle` (0.5), `spark_min_impulse`, `headlights_on` (true), `speed_lines_on` (false).
- Headlights: `energy` (40), `range_m` (22), `cone_deg` (32), `cast_shadows` (false).
- Rain: `streak_amount` (900 at scale 1.0), `splash_amount` (160), `ground_y`, `fall_speed`, `box_half_extent`.

## Measured cost (dev PC (desktop GPU): NVIDIA RTX 5060 Ti, Vulkan, Mobile renderer, preset high, 1920x1061)
Source: `evidence/screens/<scenario>/<name>_measure.json`, 300 frames each. Not a phone.
| Scene | Draw calls | frame avg ms | frame p95 ms |
|---|---|---|---|
| Wet road, dry | 29 | 0.645 | 0.660 |
| Wet road, wet | 29 | 0.645 | 0.662 |
| Wet + rain | 31 | 0.653 | 0.664 |
| Wet + rain + planar | 57 | 0.701 | 0.716 |
| Showcase: nitro flame | 8 | 0.416 | 0.480 |
| Showcase: tyre smoke | 5 | 0.403 | 0.457 |
| Showcase: sparks | 4 | 0.377 | 0.428 |
| Showcase: headlights | 3 | 0.434 | 0.471 |

Planar on adds about 0.05 ms on this rig (0.653 to 0.701). Rain adds about 0.01 ms. The rigs are almost empty
scenes. Real city cost is not measured. Multi-car cost (opponents with CarFx and two headlights each) is not measured.

## Low and Medium
- Low: rain off through `rain_enabled`; particle counts scale with `particle_amount_scale`.
- Medium: preset values; rain on at its preset scale.
- Planar reflection: High only in intent. Nothing in the game calls `set_enabled` from the preset yet; the lead must wire it.
- Speed lines: off by default on every CarFx (race_scene attaches one to every car).

## Tyre smoke gating (CarFx._process)
Smoke is on per rear wheel only when the wheel is in contact and one of these holds:
- rear slip angle above `smoke_slip_deg` (8 deg; amount ramps to full over 12 deg). The angle is the lateral
  over longitudinal velocity of the rear contact point, from `linear_velocity` and `angular_velocity`.
- `is_drifting` (amount at least 0.5).
- standing-start wheelspin: speed below 40 km/h and throttle at least 0.5 (amount 0.6).
`wheel_slip` is NOT used. It is lateral grip usage (|f_lat| / f_max) and reads high under plain acceleration,
which caused the grey blobs over the frame at 113 km/h. ArcadeCar has no public longitudinal slip, so the
standing-start rule is a throttle and speed proxy, not measured wheelspin.
Test: a straight run from 60 to 150 km/h emits no smoke above 40 km/h; a drifting car emits.

## Status
- Fixed this pass: planar reflection now works (mirror projection, layer mask keeps the default layer,
  material receives `planar_vp` and `planar_enabled`); puddles show mirrored lamps and neon.
  Sparkle reduced (normal flattening, ripple edge fade). Sparks burst properly (explosive emission).
  Speed lines no longer built per car by default.
- Partial: nitro flame reads as separate blue-magenta puffs, not a flame shape. Headlight beam is faint on the test ground.
- Not done: `car_paint.gdshader` (clearcoat test on a sphere not run; StandardMaterial3D clearcoat not yet judged).
  `window_emissive.gdshader` not written. HUD SpeedFx in race_scene is not driven by anyone (race_scene is lead-owned).
  Rear wheel contact height and exhaust points not checked against the car model.
- Tyre smoke re-judged on fx_showcase (rig light added, since lit smoke needs a light). Puffs read as small grey
  wisps at the rear wheels, not fog banks. Not judged in a moving race capture yet.
- Known: `RID of type CanvasItem was leaked` warning at test exit, cause not confirmed.
