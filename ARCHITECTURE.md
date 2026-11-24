# MIDNIGHT SYNDICATE — Architecture

Engine: Godot 4.7.2 stable, GDScript only, Mobile renderer (Metal on iOS, Vulkan/D3D12 on the
Windows dev machine). Physics: Jolt (engine default), 60 Hz fixed step, physics interpolation on.
Offline only. No network code, no third-party SDKs in the vertical slice.

## Repository layout
```
game/                 Godot project root (only this folder is imported by Godot)
  project.godot
  core/               autoloads and shared types
  vehicles/           car controller, input, visuals, car scenes, CarSpec resources
  ai/                 racing line, rival driver, police driver
  race/               race manager, checkpoints, results
  camera/             chase camera, replay camera
  fx/                 nitro flame, tyre smoke, sparks, speed lines, rain
  shaders/            *.gdshader (wet asphalt, car paint, neon, rain)
  ui/                 hud/, menus/, garage/, theme/
  world/city_01/      first track: scene, environment, lighting
  assets/             imported GLB/PNG/OGG (output of the asset factory, never hand-edited)
  tests/              headless tests (run_tests.gd + test_*.gd)
  devtools/           capture harness for real screenshots, perf probe
assets_src/           Blender generators, .blend files, source textures (not imported by Godot)
tools/                Python/PowerShell automation (asset factory, manifest, validation, CI helpers)
docs/                 research, art briefs, design notes
replica/              recon map and feature matrix (Replica method adapted to games)
evidence/             screenshots, renders, test logs referenced by reports
```

## Conventions
- Units: metres, kilograms, seconds. Godot forward is **-Z**. A car node's forward is its -Z.
  Blender cars are authored nose to -Y, which arrives in Godot facing +Z, so every imported car
  mesh sits under a `Visual` node rotated 180 degrees about Y.
- Collision layers: 1 world/static, 2 vehicles, 3 triggers (checkpoints), 4 props (dynamic), 5 police sensors.
- Input actions are created in code by `core/input_setup.gd` (no hand-edited input map):
  `accelerate, brake, steer_left, steer_right, handbrake, nitro, pause, reset_car, camera_toggle`.
- Scripts use static typing everywhere. No `await` inside `_physics_process`.
- Game logic reads no rendering state. Rendering/VFX/audio read car state only (one-way).
- Every tunable number lives in a `Resource` (`CarSpec`, `GraphicsPreset`, `RaceEvent`), not in code.

## Core contracts (other systems may depend only on these)

### `vehicles/vehicle_input.gd`
```gdscript
class_name VehicleInput extends RefCounted
var throttle: float = 0.0   # 0..1
var brake: float = 0.0      # 0..1 (also reverse when nearly stopped)
var steer: float = 0.0      # -1 left .. +1 right
var handbrake: bool = false
var nitro: bool = false
```

### `vehicles/car_spec.gd` (`class_name CarSpec extends Resource`)
Mass, wheelbase, track, wheel radius front/rear, suspension rest/stiffness/damping, engine force
curve, top speed, brake force, grip front/rear, drift grip multiplier, steering angle at low/high
speed, nitro force multiplier, nitro capacity seconds, nitro refill rates, downforce, display name.

### `vehicles/arcade_car.gd` (`class_name ArcadeCar extends RigidBody3D`)
```gdscript
@export var spec: CarSpec
var input: VehicleInput                 # written by a driver (player, AI, police), read here
# read-only state for everyone else:
var speed_kmh: float
var forward_speed: float                # m/s along -Z, negative when reversing
var is_grounded: bool
var grounded_wheels: int
var is_drifting: bool
var drift_angle_deg: float              # signed slip angle
var drift_score: float                  # current chain
var nitro_amount: float                 # 0..1
var nitro_active: bool
var gear: int
var rpm_norm: float                     # 0..1, for audio and tachometer
var wheel_contact: Array[bool]          # FL, FR, RL, RR
var wheel_compression: PackedFloat32Array
var wheel_spin_rad: PackedFloat32Array  # accumulated spin angle for visuals
var steer_angle_rad: float
signal drift_started
signal drift_ended(score: float)
signal nitro_started
signal nitro_ended
signal hit(impulse: float, world_pos: Vector3)
func reset_to(xf: Transform3D) -> void
func set_frozen_for_grid(frozen: bool) -> void
```
Model: custom raycast suspension on a RigidBody3D (four shape/ray casts, spring-damper), per-wheel
lateral grip with a friction-circle clamp, rear-wheel drive force from a speed-based curve, speed
sensitive steering, arcade assists (yaw damping, counter-steer assist while drifting, extra
gravity when airborne, upright torque). VehicleBody3D is not used.

### Drivers (write `car.input` every physics tick)
- `vehicles/player_driver.gd` — keyboard, controller, touch (tap-steer + auto-accelerate option).
- `ai/ai_driver.gd` — pure-pursuit on the racing line, per-point target speed, overtaking offset,
  bounded rubber-band (max ±8% engine force, never above player top speed).
- `ai/police_driver.gd` — later milestone.

### Track scene contract (`world/<track>/<track>.tscn`)
```
Track (Node3D, script track.gd)
  Geometry            imported GLB(s) with static collision
  RacingLine (Path3D) closed Curve3D, forward = race direction
  StartGrid (Node3D)  Marker3D children Grid0..Grid7, -Z = race direction
  Checkpoints (Node3D) Area3D children CP0..CPn in order (CP0 = start/finish line)
  Lighting            WorldEnvironment, lights, ReflectionProbes
```
`track.gd` exposes `get_progress(world_pos) -> float` (0..length along the line),
`get_point_ahead(offset, distance) -> Vector3`, `get_target_speed(offset) -> float`, `length`.

### `race/race_manager.gd`
State machine `GRID -> COUNTDOWN -> RACING -> FINISHED`. Tracks laps by ordered checkpoints,
positions by `lap * length + progress`. Emits `countdown_tick(n)`, `race_started`,
`lap_completed(car, lap, time)`, `position_changed(car, pos)`, `race_finished(results)`.
The HUD listens to these signals and reads `ArcadeCar` state; it never drives logic.

### Autoloads (`core/`)
| name | file | role |
|---|---|---|
| `InputSetup` | input_setup.gd | creates input actions |
| `Settings` | settings.gd | graphics presets Low/Medium/High, audio, controls; applies to viewport and environment |
| `GameState` | game_state.gd | profile, garage, wallet, career; JSON save in `user://save.json` with version + backup |
| `Router` | router.gd | scene changes with fade |
| `Capture` | ../devtools/capture.gd | inert unless `-- --capture=<scenario>`; drives a scenario, saves PNGs, quits |

## Rendering plan (Mobile renderer)
- Night city read: baked or static sky colour + fog, emissive neon and windows with glow,
  wet asphalt shader (low roughness, puddle mask, normal ripples, planar-fake streak reflections),
  ReflectionProbes along the track (box projected), one shadow-casting moon/street key light at
  most, the rest unshadowed omni/spot lights in range-limited clusters, car headlight spots.
- Car paint: StandardMaterial3D clearcoat first; custom shader only if measured cost allows.
- Presets: `GraphicsPreset` resources set scaling_3d_scale, MSAA, glow, shadow size, probe
  count, particle amount, light count. Dynamic resolution = scaling_3d_scale stepped by a frame
  time controller.
- Any feature not confirmed on iOS in `docs/research/04-godot-mobile-rendering.md` stays off in
  the Low/Medium presets until measured on a device.

## Testing and evidence
- `godot --headless --path game -s tests/run_tests.gd` runs logic tests (suspension settles,
  0-100 time, top speed, braking distance, drift entry/exit, nitro drain/refill, AI completes a
  lap without leaving the track, lap counting, save/load round trip). Exit code non-zero on fail.
- `godot --path game -- --capture=<scenario>` renders real frames to `evidence/screens/`.
  A screenshot only counts if it came from this harness.
- Performance numbers come from `devtools/perf_probe.gd` (frame time percentiles, draw calls,
  primitives, VRAM) and are recorded in GRAPHICS_BENCHMARK.md with the machine they ran on.
  Desktop numbers are never reported as iPhone numbers.

## Asset factory
`assets_src/**/build_*.py` (Blender, deterministic) -> GLB + textures -> `tools/asset_factory.py`
validates (names, budgets, textures, licence fields), copies into `game/assets/`, and updates
ASSET_MANIFEST.json. Third-party sources are recorded in THIRD_PARTY_LICENSES.md at download time.
