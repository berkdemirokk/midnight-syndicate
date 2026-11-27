# Race-start hitch: shader warm-up (investigation, NOT accepted)

Machine: Windows 11 dev PC, AMD Ryzen 5 7600, NVIDIA RTX 5060 Ti 8 GB, Godot 4.7.2, Forward Mobile, rendered (GPU lock). Not a phone. Desktop numbers are never phone numbers.

Branch base: release candidate 168c27a. This doc and the unapplied patch are the only changes; no game code is touched.

## Verdict

No warm-up change is committed. The measured runs do not show a real reduction, so the change was not accepted.
- With the warm-up in place (3 runs, same runner): 0 frames over 25 ms in the 5 s after GO, in each run.
- Without it (3 runs, same runner): 5, 0 and 0 frames over 25 ms. So the difference is one spike in one run, which is within noise.
- The 52 of 301 frames over 25 ms measured earlier today (docs/perf/DRIVE_TELEMETRY.md, section 5) did not reproduce on this PC in these runs.
- Compile events did not move out of the GO window with the warm-up. See the counters below.

## What was measured

Runner: `game/devtools/scenarios/drive_telemetry.gd --mode=hitch` (bogaz, Tayfun, grid 8, rendered, default vsync, GPU lock). Window: 0 to 5 s after GO. The frame time is the `process_frame` delta.

| run set | post-GO frames > 25 ms | post-GO frames > 33 ms | post-GO max ms | post-GO median ms | countdown frames > 25 ms |
|---|---|---|---|---|---|
| without warm-up, run 1 | 5 | 5 | 80.6 | 16.7 | 0 |
| without warm-up, run 2 | 0 | 0 | 20.9 | 16.7 | 0 |
| without warm-up, run 3 | 0 | 0 | 20.1 | 16.7 | 0 |
| with warm-up, run 1 | 0 | 0 | 19.5 | 16.7 | 0 |
| with warm-up, run 2 | 0 | 0 | 20.1 | 16.7 | 0 |
| with warm-up, run 3 | 0 | 0 | 20.8 | 16.7 | 0 |

Each run has 294 to 301 post-GO frames and 180 to 181 countdown frames. The screen reports 180 Hz (`screen_refresh_hz` 180.06 in the run JSON), with default vsync. The median frame is 16.7 ms (about 60 fps), so a 60 fps cap comes from another source, which is not identified.

The lead reviewer recomputed every number in this table from the six raw run JSON files (`base_hitch_1..3.json`, `warm_hitch_1..3.json`). Those files are not kept in the repo.

## Compile counters (what compiles at GO)

Probe: same scene and config, with `RenderingServer.get_rendering_info(RENDERING_INFO_PIPELINE_COMPILATIONS_*)` read every frame. The counters are cumulative. The probe is not committed.

Without warm-up, per phase (one run, `probe_nowarm_3`; recomputed by the lead reviewer from its JSON):

| phase | SURFACE | DRAW | SPECIALIZATION |
|---|---|---|---|
| grid beat (before countdown) | 103 | 35 | 273 |
| countdown | 0 | 2 | 82 |
| 0 to 1 s after GO | 0 | 0 | 10 |
| 1 to 3 s after GO | 0 | 4 | 40 |
| 3 to 6 s after GO | 0 | 2 | 71 |

With warm-up (one run, total only): grid 419 compiles, 0 to 6 s after GO 129 compiles. Without warm-up (same window, two runs): 125 and 127. So the warm-up did not remove the compiles that happen after GO.

Reading: after GO, the compiles are almost all SPECIALIZATION variants (about 20 per second), not new surfaces. Their trigger is not the FX nodes that the warm-up copies (car FX nitro flame, tyre smoke, sparks, wheel spray, speed lines). Likely candidates are light and shadow state changes in the Forward Mobile lighting (headlight, underglow, nitro light visibility toggles). That is a hypothesis, not measured.

Frames over 25 ms did not line up with compile events in the runs that had them. One probe run without warm-up had three spikes near 37 ms at about 1.35 s, 2.96 s and 4.5 s after GO, with no compile events in those frames. The spikes come about every 1.5 s. The probe run with warm-up had three spikes near 73 to 75 ms at 1.1 s, 2.0 s and 3.5 s, also with no compile events. A second probe run without warm-up had none. So the cause of those spikes is not identified.

## Project settings (checked in this build, not edited)

Read with `ProjectSettings` in the editor build of Godot 4.7.2:
- `rendering/rendering_device/pipeline_cache/enable = true` (default). Compiled Vulkan pipelines are stored on disk in the user data folder (`%APPDATA%/Godot/app_userdata/Midnight Syndicate`) and reloaded on the next launch. The runs above are warm-cache runs, because the cache was already written by earlier runs of this project.
- `rendering/shader_compiler/shader_cache/enabled = true` (default, with compression on).
- No ubershader or other pipeline-warm-up setting exists in this build's project settings (searched the property list for `ubershader`, `pipeline` and `shader_cache`).
- Consequence: a cold first launch on a device can show more compile hitching than these warm-cache runs. That cold case was not measured. It needs a separate user data folder, which was not set up.

## Not done

- Cold-cache runs (first launch) were not measured. The shared user data cache was not cleared, because other sessions use it.
- Per-material attribution of the SPECIALIZATION compiles was not done. The counters give totals only.
- The spikes of about 1.5 s period were not explained.
- No phone measurement.
- The probe and warm-up code were removed from the branch. The attempt is kept as a patch in the repo: `docs/perf/START_HITCH_warmup_attempt.patch` (against 168c27a; not applied).

## Next step if this is reopened

Find the light or shadow state change behind the SPECIALIZATION compiles, with a per-frame log of light visibility and shadow toggles next to the counters. Then decide whether a warm-up on the lighting state is worth it.
