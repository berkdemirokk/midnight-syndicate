# Motion LOD review, 2026-11-28: status

Machine: Windows 11 dev PC, NVIDIA RTX 5060 Ti 8 GB, Godot 4.7.2, Mobile renderer. Not a phone.

## Status: tool delivered, review not done

Of the four perf package items, only the motion review tool works. These items are not done:
- the LOD evaluation on all 3 tracks, and any LOD or visibility-range fixes in `game/traffic/**` or
  `game/world/landmarks/**`
- the ~40 s spike bisect (START_HITCH.md has no Attempt 4)
- the cold-cache launch measurement
- the per-track material cost list

No LOD distance was changed. Nothing in this file claims a pop was found or fixed.

## The tool

- `game/devtools/scenarios/gameplay_reel.gd`: a real race (autopilot, 5 rivals, traffic on, night) is sampled as JPG
  frames from GO. Arguments after `--`: `--track=bogaz|city|maslak`, `--fps=8`, `--seconds=20`, and `--side` for a
  static camera 9 m beside the start, so the field drives past it. Run it through the capture harness under the GPU lock:
  `godot --path game --audio-driver Dummy --resolution 1920x1080 --position 20000,0 res://devtools/capture_boot.tscn -- --capture=gameplay_reel --track=bogaz --timeout=300`
- `tools/reel_sheet.py <frames_dir> <out_prefix> [--cols 4] [--every N] [--no-mp4]` writes a labelled contact sheet
  and an MP4. ffmpeg comes from PATH or from `FFMPEG_EXE`; nothing is downloaded. ffmpeg 8.1 (winget, already
  installed) is on PATH on this PC.
- The first committed version of the scenario never ran: `get_viewport()` does not exist on a scenario (RefCounted),
  so the script failed to parse. The lead fixed it to use `tree.root.get_texture()`.
- One reel is 160 frames, about 23 MB of JPGs at 960x540. Do not commit the raw frames. Commit the sheet and the MP4.

## First reel: Bogaz, chase camera, 8 fps, 20 s

Evidence:
- `evidence/screens/gameplay_reel/bogaz_chase_sheet.jpg` (every 4th frame, so 2 fps)
- `evidence/screens/gameplay_reel/bogaz_chase.mp4` (all 161 frames, re-encoded at CRF 30)
- `evidence/screens/gameplay_reel/bogaz_chase_meta.json`
- `evidence/screens/gameplay_reel/reel_end.png`

What the sheet shows:
- The capture works. Speed rises from 0 to 191 km/h by 12 s, with HUD, wet-road reflections and rivals in frame.
- From about 14 s the autopilot car runs into a group of rivals and parked cars. From 16.6 s to 20 s it stands at
  0 km/h. The last 3.5 s are static, so this reel shows no LOD transitions in that stretch. For motion review, use
  `--seconds=14`, or `--side` so the field drives past a fixed camera.
- At 2 fps the sheet cannot show a pop. A pop has to be found by stepping through the MP4 frame by frame, and that has
  not been done.

## Next step

Record a chase reel and a side reel for each of bogaz, city and maslak. Step through each MP4 and note the time and
the object of each visible switch. Then tune `visibility_range_end`, `visibility_range_*_margin` and
`visibility_range_fade_mode` for the traffic and landmark nodes responsible. Report the changes needed in other world
folders to the environment packages.

## Package lodmotion (follow-up, same day): result

Status: no pop confirmed in frames, and no LOD distance changed. What this package added:
- `gameplay_reel.gd --tod=night|day|sunset` (default night, as before). The output folder is now `<track>_<side|chase>_<tod>`.
- Reels recorded: side and chase for bogaz, city and maslak, day and night (8 fps, 20 s). The raw frames were not committed.
  The side camera hardly shows traffic. Two chase runs of the same reel stop matching after about frame 10, because the
  race does not replay the same way, so comparing before/after frames by index proves nothing.
- A measured renderer fact (below) that changes how every LOD switch in the game should be set.

### Measured: on the Mobile renderer a visibility-range margin does not fade

Probe: a scratch SceneTree script draws an unshaded quad with `visibility_range_end = 60`, `end_margin = 6`,
`VISIBILITY_RANGE_FADE_SELF`, then the same with `begin = 60`, `begin_margin = 6`. It reads the drawn intensity at
distances from 50 to 68 m, for a ShaderMaterial and for a StandardMaterial3D. Godot 4.7.2, RTX 5060 Ti.

| Renderer | end=60, margin 6 | begin=60, margin 6 |
|---|---|---|
| Mobile (the project's renderer) | fully drawn up to 65 m, gone at 68 m. No partial values. | gone at 53 m, fully drawn from 55 m. No partial values. |
| Forward+ (comparison only) | alpha falls from 0.98 at 55 m to 0.14 at 65 m | alpha rises from 0.14 at 55 m to 0.98 at 65 m |

A second probe moved the camera through a LOD pair (A: end 22, margin 2; B: begin 22, margin 0 or 2), first toward
the pair and then away from it. On Mobile both meshes are fully drawn from 22 to 24 m (B margin 0) or from 20 to 24 m
(B margin 2), in both directions. There is no gap and no dissolve. On Mobile a margin only extends the range at full
opacity, so a paired fade band means two LODs are both drawn opaque.

Consequences:
- The fades this package first added (car LOD1/LOD2 begin margin, landmark 6 m bands, greenery 6 m bands, event-dressing
  end fade) were reverted in review. On Mobile they fix no pop. They draw two LODs on top of each other: landmark LOD0+LOD1
  over 114-126 m and greenery over 54-66 m and 144-156 m. That costs GPU time and can z-fight where the two meshes
  overlap (the landmark dome, the tree crowns).
- Switches that already have paired margins draw two LODs at once today: `traffic_car.gd` (4 m on each side, so 8 m of
  double draw at 30, 80 and 170 m), `car_lod.gd` (LOD0 end margin 2 m: 22-24 m and 70-72 m), and parked cars in
  `city_builder.gd` (`lod_fade_m`). Not changed here. Setting their margins to 0 gives hard switches, and keeping them
  keeps the double draw. Lead decision.
- A real cross-fade on Mobile needs a dither in the material: a per-instance or per-node fade uniform, and a `discard`
  against a screen-space hash in each shader (foliage, landmark, car paint). That shader work is not done.
- `game/world/street_fronts/**` was not checked (lead area).

Tests: full suite headless, 0 failed (see the commit message for the counts).
