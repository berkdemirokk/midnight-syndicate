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

---

# Attempt 2 (hitch2, 2026-11-28): where the spikes are, with measurements

Machine and rules as above: Windows 11, Ryzen 5 7600, RTX 5060 Ti 8 GB, Godot 4.7.2, Forward Mobile, rendered under the GPU lock. Not a phone. No game behaviour changed. Probe: `game/devtools/scenarios/hitch_probe.gd` + `hitch_probe_run.gd` (new, committed with this doc).

## Verdict

No fix accepted. Nothing to measure a reduction against:
- The race start window (0 to 5 s after GO) had **0 frames over 25 ms in all 19 rendered runs** (15 with the mirror on, 4 with it off; the max frame in the window was 19.7 to 23.3 ms). The start itself is clean on this PC.
- The periodic 37 ms / 73 ms spikes every ~1.5 s from attempt 1 did **not** reproduce. In 15 runs of 60 s after GO there is no periodic pattern.
- What does recur is one isolated spike at about 40.2 to 41.2 s after GO (26 to 54 ms, 8 of 15 runs). It sits at the same track point in each run. Its cause is **not** identified.
- Hypothesis (2), that light toggles cause the SPECIALIZATION compiles: **no clear link in this sample** (see below; the sample of toggle frames is small).

## How it was measured

`hitch_probe_run.gd` runs the same race as `drive_telemetry --mode=hitch` (bogaz, Tayfun, grid 8, rendered), but records from the grid to GO + 60 s. Per frame: frame delta, process and physics time, draw calls and primitives, pipeline compile counters (surface, draw, specialization), node count, viewport 3D scale, the number of nodes added, race state and the player's x, z and speed. Events, stamped in ms: node added or removed, Timer timeouts, AudioStreamPlayer start and stop, Light3D visibility or shadow change, lap completion, race finish. On a spike frame (dt > 25 ms) it also lists the nearest visible nodes that are not the player's own car.

**Probe overhead (lead review correction).** The probe's own work lands in the measured frames. `_poll_events()` runs `find_children` over the whole tree (about 4461 nodes) every frame after countdown, and `dt` is taken at the top of the next loop iteration, so that cost is inside every measured frame. The spike-frame scan (`_log_nearby`) is also counted, in the frame after the spike. In the runs that have the scan (11, 12, 15, 16, 18, 19), each spike is followed by a 23 to 32 ms frame, while runs without the scan show 9.5 to 12 ms after a spike. So the 2nd and 3rd frames of a cluster (for example run 19: 40.86, 40.89, 40.91 s; runs 11, 16, 18) are most likely probe echo, not engine cost. Count the first frame of a cluster only. A rerun that times the poll and scan separately was not done.

Runs were 1 to 15 with the mirror on, 16 to 19 with `--no-mirror` (an experiment that stops every SubViewport after countdown). Raw JSON is in the scratchpad, not in the repo.

### Counts (mirror on, 15 runs, 60 s after GO)

| metric | result |
|---|---|
| frames > 25 ms, 0 to 5 s after GO | 0 in all 15 runs (max 19.7 to 23.3 ms) |
| frames > 25 ms, 0 to 60 s after GO | 0 in 5 runs, 1 to 2 in 10 runs |
| frames > 33 ms, 0 to 60 s after GO | 0 in 8 runs, 1 in 7 runs |
| spike near 40.2 to 41.2 s after GO | 8 of 15 runs, 26 to 54 ms |
| other spikes | 6.5 s (26 ms, run 2), 26.7 s (303 ms, run 4), 29 ms at 41.2 s (run 11) |
| median frame, 60 s | 16.66 ms in every run |
| TIME_PROCESS / TIME_PHYSICS during racing | about 9 to 11 ms / 1 to 3 ms |

The 303 ms frame at 26.7 s in run 4 happened once and had no logged event in its window. Its cause is unknown.

### Mirror off (4 runs, experiment)

The spike near 40.5 to 40.9 s is still there in 3 of 4 runs (25 to 32 ms). Its size is a little smaller and the sample is small, but the wet-road mirror is not its main source. Start window: still 0 frames over 25 ms.

### Hypothesis 1: source of the periodic spikes

Checked and ruled out for the window after GO (none of these lines up with the spikes):
- **Node churn.** No node is added or removed after GO. The node count stays at 4461 through the race (`node_added` events are only the MusicPlayer at GO).
- **Timers.** No Timer timeout event fired in 60 s (the probe hooks every Timer, including those added later).
- **Audio.** About 5 AudioStreamPlayer3D starts and stops a second come from the car engines. Their timing does not match the spikes. MusicPlayer and UI sounds start at GO with no hitch in the window.
- **Dynamic resolution.** The 3D scale stays at 1.0 (`scaling_confirmed_on_device` is false on this preset), so no step happens.
- **Lap events.** Lap completions are at 47 to 60 s, not at the spike (not rechecked against the raw data in lead review).
- **Mirror.** Mostly ruled out, see above.
- **Shader compiles.** No compile count jump on the spike frames (the spike frames show spec delta 0 in most runs).

Not ruled out: the spike is tied to a track position (the car reaches about x -241 to -255, z -193 to -235, at 185 to 202 km/h, at 40.2 to 41.2 s in every run where it happens). The nearby-node list exists only for runs 11, 12, 15, 16, 18 and 19 (runs 1 to 8, 13, 14 and 17 have no scan data; the 40 s spike in runs 1, 5, 6, 7 and 8 has no nearby data). On those frames the nearby non-car nodes were: street lamp `OmniLight3D` (`lamp_head_054`, about 7 m), `Rain` `GPUParticles3D` (about 8 m), `ChaseCamera` fill and rim lights (about 8 m). Any of these, or the lamp lights as a group, is a candidate. Not tested.

### Hypothesis 2: SPECIALIZATION compiles and light toggles

- The car `CarFx` `OmniLight3D` nodes toggle visibility 137 to 181 times per 60 s race (which effect drives them was not checked); that is 135 to 174 frames with a toggle per run, about 4 to 5 % of frames. Mean specialization compiles per frame are 0.132 to 0.259 in frames with a toggle and 0.175 to 0.186 in frames without one. In several runs (7, 9, 17, 19) the toggle mean is clearly above the no-toggle mean, in others below. With so few toggle frames this shows no clear link either way; it does not rule one out.
- Compiles keep arriving through the race at about 0.18 per frame (about 11 per second) with no toggle in the frame. The big batch (about 120) comes in the grid beat, before countdown, as already measured in attempt 1. So compiles are not only at GO.
- Shadow state changes were not seen in the probe (no `shadow_enabled` flips).

Reading: compiles after GO are spread out, one or two per frame, and cost little. They do not explain the spikes.

## Project settings (not changed)

No `project.godot` change is proposed from this evidence. Attempt 1 checked the pipeline cache and shader cache (both on, default). No ubershader setting was found in this build. Cold-cache first launch still was not measured.

## Next step if this is reopened

1. Bisect the 40 s spike: with a per-run flag, turn off the street lamp lights (`lamp_head_*`, `floodlight_*`) and then the rain emitter, and count spikes over at least 4 runs each. Only then consider a fix, in one file.
2. Measure a cold cache with a separate user data folder (the probe's `--out` plus a `user://` override).
3. The 303 ms frame at 26.7 s (run 4) is not explained. Repeat it before chasing it.

## Files

- `game/devtools/scenarios/hitch_probe.gd` and `hitch_probe_run.gd` (new): the probe. Usage in the file header. Rendered only, under the GPU lock.
- No change to `game/` outside devtools. `game/project.godot` untouched.
- Note: running the test suite rewrites `evidence/test_results.json`. Restore it with `git checkout -- evidence/test_results.json` after each run so the worktree stays clean.
- Counts in this section were recomputed from the raw probe JSON in lead review (2026-11-28) and corrected where the first draft was wrong.

---

# Attempt 3 (wp-spike, 2026-11-28): bisect of the 40 s spike, no fix

Same machine, rules and probe as attempt 2 (`hitch_probe_run.gd`, GPU lock, rendered, 60 s after GO, desktop only). Two new probe flags: `--no-lamps` (hides every `lamp_head_*` and `floodlight_*` Light3D after countdown) and `--no-rain` (stops and hides every GPUParticles3D whose path contains "rain" after countdown). Raw JSON is in the scratchpad, not in the repo.

## Verdict

No cause found. No variant removed the spike in 3 of 3 runs while the baseline showed it, so no fix was made. Only `devtools/` was changed. No `game/` code is touched.

## Results (frames over 25 ms, 36 to 44 s after GO)

| variant | run 1 | run 2 | run 3 |
|---|---|---|---|
| baseline | 44.2 ms at 41.07 s (+30.4 at 41.10) | 28.7 ms at 40.77 s (+26.2 at 40.80) | none |
| (a) street lamps off | storm: 54 frames over 25 ms, 235 ms at 36.06 s, 45.7 ms at 37.83 s | 43.9 ms at 40.67 s | none |
| (b) rain off | 27.6 ms at 41.21 s | none | none |
| (c) traffic off | not run: `traffic_enabled = false` is already set in the probe, so the baseline has no traffic | | |
| (d) mirror off | not re-run: attempt 2 (4 runs) already measured it, and 3 of 4 runs still spiked | | |
| (e) audio off | not run: the probe already uses `--audio-driver Dummy` | | |

Max frame over 0 to 60 s: baseline 44.2, 28.7, 21.2 ms. Lamps off: 398.6 (run 1, see below), 43.9, 25.0 ms. Rain off: 27.6, 23.8, 24.0 ms.

## What was ruled out or checked

- **Lap boundary.** Lap completions for every car land at 46.7 s and later in all 9 runs, never at 36 to 44 s. The spike is not a lap event.
- **Node churn and timers.** Zero `node_added`, `node_removed` or Timer timeout events between 0 and 60 s after GO in any run. Node count is flat.
- **Nearby nodes at spike frames (baseline runs 1 and 2).** The nearest visible non-car nodes are the rain `GPUParticles3D`, the lamp `OmniLight3D` (`lamp_head_054`), the ChaseCamera fill and rim lights, and car wheel-spray and CarFx particles. The same set is present in every run, so the list alone does not single out one cause.
- **Probe echo.** The spike-frame scan lands in the next frame (see attempt 2). The first frame of each cluster is the one counted.

## Caveats

- The baseline rate is low in this sample: 2 of 3 runs here, 8 of 15 in attempt 2. With a roughly 50 % rate, a 3 of 3 absence happens by chance in about 1 run in 8, so no single-variant result can be called a removal. Two of the three variants gave one spike each, so neither is clearly better or worse than the baseline.
- Hiding the lamps (run 1 of the lamps set) produced a long storm of 25 to 240 ms frames from 36 s on, with 54 spikes in 60 s. It is not clear whether that is the cause of hiding Light3D nodes at the mid-race (forward light cluster changes or shader compiles), or noise from the probe. It was not investigated. Do not read it as a result for the lamps.
- ResourceLoader loads were not logged (the probe hooks nodes and timers, not loads). Not checked.

## Next step if reopened

1. Run 6 or more baseline runs to pin the rate, then 6 runs per variant. A variant needs 0 spikes in at least 6 of 6 while the baseline shows them.
2. Log ResourceLoader calls (wrap `ResourceLoader.load` through a probe hook, or count `Resource` creation) in the 36 to 44 s window.
3. Repeat the lamp storm with `--no-lamps` alone, no other variant, to see whether hiding lights mid-race is itself costly.
