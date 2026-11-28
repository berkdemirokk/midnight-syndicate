# Post-processing and camera for speed sensation

Scope: FOV, chase camera, shake, nitro punch, radial blur, speed lines, grading, vignette, chromatic aberration,
and what Godot 4.7 Mobile can do. Our code is in `game/camera/chase_camera.gd`, `game/fx/post_fx.gd`,
`game/fx/speed_lines.gd` and `game/shaders/post_grade.gdshader`.

Honest summary first: public sources do not give measured camera numbers for Asphalt, Need for Speed, Burnout or
Forza. The numbers below come from docs, talks, and open-source projects. Each one is marked by how much we trust it.

Legend: [V] verified in a primary source we opened. [S] search snippet or secondary. [C] community or fan source.
[E] our own estimate. [U] unverified.

## 1) What the best mobile racers do

Public facts about the big titles are thin. What we could confirm:

- Motion blur and speed cues sit on the edges of the frame, not on the car. A general article and an open
  issue both say this. [S] https://antidote.gg/how-video-games-trick-your-brain-into-feeling-fast/ and
  https://github.com/karllondor/Nitro-Wheelz-/issues/52 (research only, not implemented in that project).
- Community consensus on Forza Horizon 6: a moderate-to-narrow chase FOV, and motion blur off or low for a clean
  picture. The FOV values in fan guides use different scales, so they are not comparable. [C]
  https://grindout.com/forza-6/guides/best-settings and https://dotesports.com/forza/news/best-forza-horizon-6-pc-settings
- Burnout Paradise: a PC review says full speed feel needs motion blur on. A ResetEra thread says the stock blur
  is weak because it is expensive. [C] https://www.resetera.com/threads/best-way-to-play-burnout-paradise-in-2026.1594357/
- Need for Speed (Most Wanted era): fan writeups say heavy blur and camera shake sit on a wide FOV. [S]
  No source gave NFS chase distance or FOV values. The only numbers we found are from a fan camera for Assetto
  Corsa, styled after NFS Underground 2: distance 2.8 m, height 1.3 m, pitch 3.4 degrees, with a dynamic FOV and an
  accel/brake kick. [C] https://www.overtake.gg/downloads/bacc-need-for-speed-better-arcade-chaser-camera-for-csp.49841/
- Asphalt: no camera numbers found in any opened source. Do not copy any camera from Asphalt or NFS on the strength of
  this file. [gap]

### Quantified numbers we can use

| Item | Value | Source and trust |
|---|---|---|
| Base FOV, arcade chase | about 70 deg at rest, 8 to 12 deg more on nitro, return over about 0.6 s | [E] from `docs/research/06-arcade-vehicle-physics-and-ai.md` |
| Speed FOV slope | 0.04 to 0.08 deg per km/h above a threshold | [E] same file |
| Nitro FOV kick | +8 to +12 deg, 0.2 s up, 0.6 s down | [E] same file |
| Shake curve | shake = trauma^2 (some slides say trauma^3) | [V] Eiserloh, GDC 2016 slides: https://media.gdcvault.com/gdc2016/Presentations/Eiserloh_Squirrel_JuicingYourCameras.pdf |
| Trauma decay | linear, 1.0 to 1.5 per s | [E] same file family; the decay rate is in our own code too |
| Shake noise | smoothed (Perlin-style) noise, not random values | [V] Eiserloh; transcript: https://archive.org/stream/GDC2016Eiserloh/GDC2016-Eiserloh_djvu.txt |
| Trauma 0.3 / 0.6 / 0.9 | about 3% / 22% / 73% shake | [S] slide summary, same talk |
| Chase distance, community | 2.8 to 3.4 m behind, 1.1 to 1.3 m high, 4 deg pitch | [C] BACC (above) and PR text from another project (engine not stated): https://github.com/ruenocos/Bike-/pull/3 |
| Chase FOV, another open project | 75.5 to 83.5 deg, distance 13.5 to 19 m | [C] Nitro-Wheelz issue #52 (Godot project, not ours, not measured) |
| Blur sample budget on mobile | 12 to 16 passes is the usual upper limit quoted | [C] https://creative-core-studio.itch.io/godot-motion-blur-shader |

Our own numbers, from code: fov_rest 62, fov_top 72, nitro_fov_kick 6, nitro_punch_deg 4, MAX_HFOV 125,
max_hfov_gain 14, distance 4.5 m to 5.9 m, height 1.18 m, speed shake from 150 to 240 km/h at 0.012 m, shake 16 Hz,
trauma decay 1.2 per s, nitro trauma 0.12. PostFx blur ramps from 110 to 260 km/h, nitro adds 0.35. Speed lines
ramp from 160 to 180 km/h. These are the baseline to test against.

## 2) What that means in Godot 4.7 Mobile

Checked against the 4.7 stable docs we opened:
https://docs.godotengine.org/en/stable/tutorials/3d/environment_and_post_processing.html

- Glow: works on Mobile. Mobile upscale uses bilinear by default. [V]
- Tonemapping: Linear, Reinhard, Filmic, ACES, AgX. On Mobile with AgX, the White value is ignored and 2.0 is used. [V]
  Our tonemap mode is not checked here; the lead should check it in the environment resource.
- Adjustments (brightness, contrast, saturation) and a 3D colour LUT (Texture3D, 33 slices in the template) run after
  tonemapping. [V] The LUT cost on Mobile is not measured. [U]
- Fog: depth and height fog work. Volumetric fog does not on Mobile. [V with 04 research]
- Depth of field: exists through CameraAttributes. Not used by us. Not a speed effect. [V]
- Motion blur: not in the docs. We must write it ourselves. [V, absent]
- SSAO, SSR, SDFGI, VoxelGI, TAA: not on Mobile. [V, see `docs/research/04-godot-mobile-rendering.md`]
- Chromatic aberration: not built in. Needs a custom screen shader. [V, absent]

Screen-reading cost (the main cost of our post pass):

- `hint_screen_texture` makes the engine copy the whole viewport to a back buffer before the node draws. Instanced
  scenes need a BackBufferCopy node. [V] https://docs.godotengine.org/en/4.4/tutorials/shaders/screen-reading_shaders.html
- A Godot issue reports the full-viewport copy is the cost on fill-rate-bound phones, and that cost stacks with each
  extra copy. [S] https://github.com/godotengine/godot/issues/108935
- Known bug: BackBufferCopy in Rect mode can stop `hint_screen_texture` updating. Avoid Rect mode. [V issue open or
  closed status not checked] https://github.com/godotengine/godot/issues/111096
- Glow blend changed to happen before tonemapping in the 4.6 dev line (PR). Check glow levels after any version bump.
  [S] https://github.com/godotengine/godot/pull/110671

Our `post_grade.gdshader` already does one screen copy with five extra taps, and it does the grade and vignette in the
same pass. That is the right shape: one copy, no extra pass. [V, read the file]

## 3) Recipe for our game

Each step names the file, the target and how to check it. Capture commands are from `CLAUDE.md`. Every capture uses
`--audio-driver Dummy`. Phone numbers are not desktop numbers.

### Step 1: keep one finishing pass

- Files: `game/shaders/post_grade.gdshader`, `game/fx/post_fx.gd`.
- Do not add Environment adjustments or a second full-screen pass. Put any LUT into the existing shader, or skip it.
- Check the tonemap mode in the race environment. If it is AgX, the docs say White is ignored on Mobile. Use ACES or
  Filmic, then compare.
- Verify: `godot --path game --audio-driver Dummy --resolution 1920x1080 --position 20000,0 res://devtools/capture_boot.tscn -- --capture=tod_tracks`.
  Look at the day, sunset and night frames. Colour must not wash to grey or go pink.

### Step 2: retune the chase lens in small steps

- Files: `game/camera/chase_camera.gd` (`fov_rest`, `fov_top`, `nitro_fov_kick`, `nitro_punch_deg`).
- Target: FOV grows by 10 to 14 deg from rest to top speed (the community range is 8 to 12 deg on nitro; ours is 10 on
  speed plus 6 on nitro, so keep the sum under about 16 deg). Try `fov_rest` 66 and `fov_top` 76 first. Keep the
  `MAX_HFOV_DEG` cap for wide phones.
- Verify: `gameplay_reel` at 0, 60, 120 and 180 km/h, plus one nitro burst. Check the car does not look far away and
  the road edges do not warp. Ask the owner to pick between the old and new frames.

### Step 3: test the chase distance

- Files: `chase_camera.gd` (`distance_rest_m`, `distance_top_m`, `height_m`).
- Our camera sits 4.5 to 5.9 m back and 1.18 m high. The community camera uses 2.8 to 3.4 m and 1.1 to 1.3 m. The
  closer camera should read as faster. This is a hypothesis. [U]
- Test three pairs: current, 4.0 m / 1.15 m, and 3.4 m / 1.1 m at top speed. Capture each. Keep the wall-probe code
  working for the closer pairs; the wall pull is already in the code.
- Verify: side-by-side captures from `gameplay_reel`. The car must stay fully framed on Maslak and the Bosphorus
  wall corners.

### Step 4: put the blur behind a tap budget and check it on a phone

- Files: `post_grade.gdshader` (the loop `for (int i = 1; i < 6; i++)`), `post_fx.gd` (`BLUR_FROM_KMH`, `BLUR_FULL_KMH`).
- Keep the radial blur. The centre stays sharp, the horizon stays weak. Keep the blur on the canvas layer under the HUD.
- Expose the tap count per preset: 3 taps on Medium, 5 on High, none on Low. The loop limit can stay as a constant
  if the preset uses an `if` on the count.
- Verify on desktop with `ortakoy_benchmark`, then measure on the owner's iPhone. Report the device name, the preset
  and median and p95 frame time. No desktop number may be called an iPhone number.

### Step 5: check the shake curve and add a way to turn motion down

- Files: `chase_camera.gd` (`trauma`, `shake_hz`, `trauma_decay`, `nitro_trauma`, `hit_trauma_max`, `_shake_offset`).
- Confirm the shake uses trauma squared and smoothed noise, as the Eiserloh talk says. If it uses random values,
  switch to noise.
- Add a reduced-motion setting: OFF, LOW, HIGH, default LOW on phones. OFF turns off the blur, speed shake and
  FOV kick, and keeps the speed lines off. The open project issue above also proposes this.
- Add a unit test for the curve in `game/tests/run_tests.gd` (lead-owned): trauma 0.5 must give a quarter of the full
  shake, and trauma 0 must give none. Run `godot --headless --fixed-fps 60 --path game -s res://tests/run_tests.gd`.

Optional, lower priority:

- Speed lines: keep them. They start at 160 km/h. Keep `hud_clear_rect` so they never cover the speed number.
- Chromatic aberration: skip. Godot has no built-in version, it needs another screen read or three taps, and no
  source we opened shows that it helps a phone racer. [E]
- Per-object motion blur: skip for now. It needs a velocity buffer, and the public issue says it needs Mobile or
  Forward+ with an Android frame-time test. [S]

## 4) Risks and what not to do

- Stacking effects. Blur, FOV kick, shake, speed lines and the nitro punch all fire on the same event. Each one
  alone reads well. Together they can cause motion sickness and mush the frame. Cap the total: blur plus shake
  plus speed lines should peak at once only on nitro. Test the stack, not each part.
- Copying a rig from a game. The only numbers we found are from fan mods or other open projects. Treat them as
  starting points, not targets. Clean-room rule applies.
- Measuring on desktop and calling it phone. The Mobile renderer, the Compatibility renderer and the phone GPU all
  differ. The Nitro-Wheelz issue is a Compatibility project and says so. Do not mix its numbers with ours.
- Edge blur with a wide FOV on a notch phone. Check the corners and the Dynamic Island area in the capture.
- Adding a new screen copy per effect. Each `hint_screen_texture` copy costs fill rate. Merge, do not stack.
- Rect-mode BackBufferCopy. Known bug. Use the whole viewport.
- AgX on Mobile without checking White. The docs say the value is ignored.
- Trusting search snippets for numbers. The Forza FOV numbers conflict by a factor of about two (49 versus 80 to 90
  on different scales). Only the owner's footage or our capture can settle a value.

## 5) Sources

Opened and read (primary or official):
- Godot 4.7 stable, environment and post-processing: https://docs.godotengine.org/en/stable/tutorials/3d/environment_and_post_processing.html
- Godot 4.4, screen-reading shaders: https://docs.godotengine.org/en/4.4/tutorials/shaders/screen-reading_shaders.html
- Eiserloh, GDC 2016 slides (trauma, shake): https://media.gdcvault.com/gdc2016/Presentations/Eiserloh_Squirrel_JuicingYourCameras.pdf
- Eiserloh, transcript: https://archive.org/stream/GDC2016Eiserloh/GDC2016-Eiserloh_djvu.txt (search snippet only; not read in full)
- Nitro-Wheelz issue 52 (mobile speed cues, research only): https://github.com/karllondor/Nitro-Wheelz-/issues/52
- Bike- PR 3 (FOV kick, camera distance, HUD on canvas layer): https://github.com/ruenocos/Bike-/pull/3
- Godot issue 108935 (hint_screen_texture cost): https://github.com/godotengine/godot/issues/108935 (search snippet)

Seen as search results or snippets only:
- BACC camera for AC, NFS-inspired: https://www.overtake.gg/downloads/bacc-need-for-speed-better-arcade-chaser-camera-for-csp.49841/
- Godot motion blur shader (pass count advice): https://creative-core-studio.itch.io/godot-motion-blur-shader
- Godot issue 111096 (BackBufferCopy Rect bug): https://github.com/godotengine/godot/issues/111096
- Godot PR 110671 (glow before tonemap): https://github.com/godotengine/godot/pull/110671
- Forza FH6 settings guides: https://grindout.com/forza-6/guides/best-settings and https://dotesports.com/forza/news/best-forza-horizon-6-pc-settings
- Burnout Paradise thread: https://www.resetera.com/threads/best-way-to-play-burnout-paradise-in-2026.1594357/
- Speed feel forum threads: https://gamedev.net/forums/topic/548292-racing-game-motion-blur/
- General speed-perception article: https://antidote.gg/how-video-games-trick-your-brain-into-feeling-fast/

Not found: Asphalt or NFS chase cam rig values; Burnout Paradise camera values; a GDC talk on racing speed feel with numbers.

Prior project notes reused (do not redo): `docs/research/04-godot-mobile-rendering.md`, `docs/research/06-arcade-vehicle-physics-and-ai.md`,
`docs/research/01-mobile-arcade-racers.md`.
