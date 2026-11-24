# Camera

Owner: Gameplay Agent (camera). Code: `game/camera/chase_camera.gd`. Tests: `game/tests/test_driver_camera.gd`.

## Behaviour (CHASE)
- Corner look-into: the look point shifts toward the inside of the corner by up to `look_inside_m`
  (1.2 m), driven by the car's yaw rate (`angular_velocity.y`, full at `yaw_full_rad_s` 0.6 rad/s),
  smoothed with `look_smooth_s` 0.35 s. Public state: `look_side` (+1 right, -1 left).
- Roll into turns: up to `max_roll_deg` 2.5 deg, same yaw-rate signal, smoothed with `roll_smooth_s`
  0.4 s. Roll is applied only in CHASE, so grid and finish shots stay level. Public state: `roll_rad`.
- Speed feel: the camera is lowered by up to `speed_drop_m` 0.06 m at top speed.
- Speed shake: a 35 Hz shake ramps in from 180 to 240 km/h (`speed_shake_m` 0.012 m peak), scaled
  by the `camera_shake` setting.
- Nitro kick back: on `nitro_started` the distance grows by `nitro_kick_back_m` 0.4 m, eased to 0
  over `nitro_kick_back_s` 0.8 s (smoothstep). It is added before the wall limit, so it cannot push
  the camera through a wall. The existing FOV kick and trauma are unchanged.

## No clipping
- Rear wall ray (existing): pulls the distance in.
- Ceiling probe: a ray up from the rear of the camera; the camera height is capped at the roof minus
  `wall_margin_m` (floor 0.2 m above the car origin).
- Side probes: rays 2 m to each side at camera height; the drift swing is clamped to the wall face
  minus the margin.

## Finish camera
- `ChaseCamera.start_finish_orbit()` sets ORBIT (slow orbit, `orbit_rate_rad_s` 0.15, radius 9 m).
- Not yet wired. `race_scene.gd` (not owned here) must call it in `_on_race_finished`, before
  `results_screen.show_results`:
  `camera.start_finish_orbit()`

## Tests (test_driver_camera.gd, 21 checks, all pass)
Look shifts toward the inside and returns to centre; roll sign, limit and zero in ORBIT; nitro kick
at 0.4 m, half at 0.4 s, zero after 0.8 s; speed lowers the camera and adds shake only above 180 km/h;
ceiling keeps the camera under the roof; side wall limits the swing; finish orbit radius.

## Known limits
- The look and roll effects are small (about 2 deg of roll at most), so they are hard to see in stills.
- Finish orbit is a hard cut (`set_mode` snaps), not a blend.
- Ceiling and side probes sample at the car's current position only; no per-frame sweep.
- Speed shake and roll are not checked against a phone frame budget (desktop only).
