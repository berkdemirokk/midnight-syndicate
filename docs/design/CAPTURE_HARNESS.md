# Capture harness

Owner: Core Systems. Code: `game/devtools/`. Only screenshots made by this harness count as evidence.

## Usage
From the repo root (`C:\Users\berk\car race`):

```
"C:\Users\berk\tools\godot\Godot_v4.7.2-stable_win64_console.exe" --path "game" --resolution 1920x1080 --position 40,40 res://devtools/capture_boot.tscn -- --capture=<scenario> [--size=WxH] [--preset=low|medium|high]
```

- `--capture=<scenario>` runs `game/devtools/scenarios/<scenario>.gd`. Without it, `Capture` does nothing.
- `--size=WxH` sets the window size before the scenario starts. Without it the `--resolution` window is used.
  The PNG is the real viewport: check `image_size` in the json. On the dev PC a 1920x1080 request gave 1920x1061.
- `--preset=` sets the `Settings` graphics preset for the run (default `high`). Capture turns `Settings.autosave` off, so the player's settings file is never rewritten.
- Exit codes: 0 ok; 1 the scenario called `cap.fail()`, or took no shot; 2 hard timeout (default 120 s, `Capture.timeout_s`).

## Scenario API
A scenario extends the base by path and overrides `run()`:

```
extends "res://devtools/capture_scenario.gd"
func run() -> void:
    var node := await cap.load_scene("res://world/city_01/city_01.tscn")
    await cap.wait_frames(30)        # render frames before shooting
    await cap.wait_seconds(1.0)
    await cap.shot("night_overview") # PNG + json with a 60-frame perf probe
    await cap.measure("long_run", 600)
    cap.set_size(1280, 720)          # applies on the next frame
    cap.fail("message")              # marks the run as failed (exit 1)
```

- `cap` is the `CaptureHarness` autoload, `tree` is the `SceneTree`.
- `load_scene(path)` frees the previous scene from this call and returns the new root.
- `shot(name)` waits for `RenderingServer.frame_post_draw`, saves the viewport, and fails if the frame is uniform (luminance range below `min_luma_range`).

## Output layout
```
evidence/screens/<scenario>/<name>.png    the frame
evidence/screens/<scenario>/<name>.json   scenario, preset, image size, luma range, perf
evidence/screens/<scenario>/<name>.json   from measure(): name, preset, perf (same name = overwrite; folder created on demand)
```

Perf dictionary fields (`devtools/perf_probe.gd`): `frames`, `frame_ms_avg`, `frame_ms_p95`,
`frame_ms_p99`, `fps`, `draw_calls`, `primitives`, `objects`, `video_mem_mb`, `adapter`,
`renderer`, `driver`, `os`, `viewport_size`, `scaling_3d_scale`.

The probe turns vsync off and `Engine.max_fps` to 0 for the run, after 10 warm-up frames, and
restores both afterwards. Numbers from this PC are desktop numbers, never iPhone numbers.

## Self-test
`harness_selftest` builds a lit sphere, floor, coloured light and glow in code, shoots
`selftest_sphere` and measures 600 frames:

```
... -- --capture=harness_selftest
```

Output: `evidence/screens/harness_selftest/selftest_sphere.png`. It must show the sphere.

## Scope
Capture is inert in normal runs. `Router` also skips its fade when `--capture=` is present.
