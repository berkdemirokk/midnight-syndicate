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
