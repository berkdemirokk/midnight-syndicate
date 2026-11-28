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

No cause found, and this attempt has no valid comparison: the retained baseline files show no spike at all (0 of 3, see the provenance note below), so no variant result can show a removal. No fix was made. No `game/` code or `project.godot` changed; only the probe script and this doc.

## Results (frames over 25 ms, 36 to 44 s after GO)

| variant | run 1 | run 2 | run 3 |
|---|---|---|---|
| baseline (retained files) | none (max 21.4 ms) | none (max 24.2 ms) | none (max 21.2 ms) |
| baseline (first launch, not retained) | 44.2 ms at 41.07 s (unverified) | 28.7 ms at 40.77 s (unverified) | same file as above |
| (a) street lamps off | storm: 54 frames over 25 ms, 235 ms at 36.06 s, 45.7 ms at 37.83 s | 43.9 ms at 40.67 s | none |
| (b) rain off | 27.6 ms at 41.21 s | none | none |
| (c) traffic off | not run: `traffic_enabled = false` is already set in the probe, so the baseline has no traffic | | |
| (d) mirror off | not re-run: attempt 2 (4 runs) already measured it, and 3 of 4 runs still spiked | | |
| (e) audio off | not run: the probe already uses `--audio-driver Dummy` | | |

Max frame over 0 to 60 s: baseline (retained) 21.4, 24.2, 21.2 ms. Lamps off: 398.6 (run 1, see below), 43.9, 25.0 ms. Rain off: 27.6, 23.8, 24.0 ms.

## What was ruled out or checked

- **Lap boundary.** Lap completions for every car land at 46.7 s and later in all 9 runs, never at 36 to 44 s. The spike is not a lap event.
- **Node churn and timers.** Zero `node_added`, `node_removed` or Timer timeout events between 0 and 60 s after GO in any run. Node count is flat.
- **Nearby nodes at spike frames (baseline runs 1 and 2).** The nearest visible non-car nodes are the rain `GPUParticles3D`, the lamp `OmniLight3D` (`lamp_head_054`), the ChaseCamera fill and rim lights, and car wheel-spray and CarFx particles. The same set is present in every run, so the list alone does not single out one cause.
- **Probe echo.** The spike-frame scan lands in the next frame (see attempt 2). The first frame of each cluster is the one counted.

## Caveats

- **Provenance (lead review).** The variant loop was launched twice by mistake and both launches wrote the same file names. The first launch finished all 9 runs (base 1-3, lamps 1-3, rain 1-3, about 04:59 to 05:09). The second launch then overwrote `base_1.json` (05:10) and `base_2.json` (05:11) and was still running base 3 at review time. So the lamps and rain files and `base_3.json` are from the first launch, while `base_1.json` and `base_2.json` are from the second. The two baseline spikes first reported (44.2 ms and 28.7 ms) came from the overwritten first-launch files and cannot be checked. The retained baseline files have zero frames over 25 ms in 0 to 60 s. A snapshot of the files as reviewed is in the scratchpad folder `hitch3_snapshot_0513`.
- The baseline rate is low: 0 of 3 in the retained files (2 of 5 if the unverified first-launch numbers are counted), 8 of 15 in attempt 2. With a roughly 50 % rate, a 3 of 3 absence happens by chance in about 1 run in 8, so no single-variant result can be called a removal. Two of the three variants gave one spike each, so neither is clearly better or worse than the baseline.
- Hiding the lamps (run 1 of the lamps set) produced a storm of 25 to 400 ms frames across the whole run (54 frames over 25 ms, in bursts at about 2, 3, 7, 12, 36, 38 and 48 s; worst 398.6 ms at 1.96 s), not only near 40 s. Runs 2 and 3 of the same variant had no storm. It is not clear whether that is the cost of hiding Light3D nodes at countdown (forward light cluster changes or shader compiles), or noise from the probe. It was not investigated. Do not read it as a result for the lamps.
- ResourceLoader loads were not logged (the probe hooks nodes and timers, not loads). Not checked.

## Next step if reopened

1. Run 6 or more baseline runs to pin the rate, then 6 runs per variant. A variant needs 0 spikes in at least 6 of 6 while the baseline shows them.
2. Log ResourceLoader calls (wrap `ResourceLoader.load` through a probe hook, or count `Resource` creation) in the 36 to 44 s window.
3. Repeat the lamp storm with `--no-lamps` alone, no other variant, to see whether hiding lights mid-race is itself costly.

---

# Attempt 4 (wp-spike2, 2026-11-28): six baseline runs and a Resource-count probe, no fix

Same machine and rules as attempts 1 to 3 (Ryzen 5 7600, RTX 5060 Ti 8 GB, Godot 4.7.2, Forward Mobile, rendered under the GPU lock, not a phone). Probe: `game/devtools/scenarios/hitch_probe_run.gd` (`hitch_probe.gd` wrapper), default flags, bogaz, Tayfun, 60 s after GO. No `game/` file other than the probe was changed. No fix is claimed.

## Verdict

- **No fix.** The spike at about 40 s is not reproduced in a usable way in this session, and no cause is identified. There is no 6 of 6 result, so no fix is claimed.
- **Resource loads are ruled out as the cause of the 40 s spike.** `Performance.OBJECT_RESOURCE_COUNT` rises by one or two in the first 12 s of the race, then by one more in each run at 32 to 40 s after GO, at a track point away from the spike (see below). Those late creations do not line up with the spike frames.
- **The baseline is contaminated.** Five of six runs had sustained frame times of 25 to 35 ms over the whole race. That is not the attempt 2 picture (0 frames over 25 ms in the first 5 s in 15 runs). The GPU lock was queued behind other sessions, and the desktop CPU load was about 43 % (Chrome, Claude, Codex and other Godot processes from other worktrees). Only run 1 is close to the attempt 2 picture. Its numbers are the only clean ones.

## Baseline runs (6 x 60 s, one loop, unique names `spike2/a4/base_r1..6`)

Machine state from the loop log (`godot_procs_before` counts processes named Godot_v4; it does not show CPU use by them). Post-GO = frames from GO to GO+60 s, recomputed from the raw JSON with `analyse.py`.

| run | Godot procs before / after | post-GO frames | frames > 25 ms, 0 to 5 s | frames > 25 ms, 0 to 60 s | frames > 25 ms, 36 to 44 s | max frame 0 to 60 s (ms) | median frame (ms) | median process ms |
|---|---|---|---|---|---|---|---|---|
| r1 | 2 / 4 | 3602 | 0 | 1 | 0 | 25.1 | 16.66 | 12.3 |
| r2 | 4 / 2 | 3259 | 18 | 327 | 59 | 513.4 | 16.03 | 21.2 |
| r3 | 2 / 2 | 3291 | 35 | 437 | 59 | 341.8 | 16.07 | 23.7 |
| r4 | 2 / 2 | 3478 | 30 | 424 | 53 | 564.5 | 16.06 | 23.0 |
| r5 | 2 / 4 | 3510 | 27 | 391 | 58 | 247.2 | 16.16 | 22.8 |
| r6 | 6 / 4 | 2951 | 36 | 858 | 186 | 134.1 | 17.15 | 27.3 |

Notes on these numbers:
- The "frames over 25 ms" counts include the cluster echo described in attempt 2. The clusters of 25 to 35 ms frames run through the whole race, so the counts are not spike counts. Counting cluster starts only gives 202 to 334 clusters in runs 2 to 6.
- r1 is the only run without a sustained slowdown. It has no frame over 25 ms in 36 to 44 s, and one frame over 25 ms in the whole race (at about 58 s). That is one clean run with no spike in the window. It cannot pin the rate on its own.
- Run 4 had the 40 s band of 25 to 35 ms frames, and one 564 ms frame at 44.6 s (not at 40 s). Run 5 had one 247 ms frame at about 2.7 s. Run 2 had 513 ms and run 3 had 342 ms (times not checked against the events). The 36 to 44 s window is inside the contamination in runs 2 to 6, so the "spike near 40 s" of attempt 2 cannot be counted in this batch.
- Node count is flat at 4463 through the race in every run. No node is added or removed after GO.
- The spec compile delta over the race is 641 to 701 per run (a cumulative counter read per frame). Not used in the conclusion.
- Run 6 was queued behind another session's GPU lock for about 10 minutes (`loop.log`, 14:49 to 15:04). The loop kept a single run at a time.

## Resource-count probe (new in this attempt)

`hitch_probe_run.gd` now also reads `Performance.OBJECT_RESOURCE_COUNT` every frame, adds it as a 15th frame field (`res_count`), and logs an event `resource` "count a -> b" for each change after countdown. Raw counts for all six runs:

- At GO and the first 12 s: the count rises by 6 to 7 (for example 1329 to 1336). These are the setup loads of the race (MusicPlayer, HUD, pause and results screens, car materials).
- After 12 s: exactly one more Resource in each of runs 1, 2, 3, 4, 5 and 6, at 32.2 to 39.9 s after GO. That is 0 or 1 in the 36 to 44 s window in each run. Runs 4 and 5 created it at 32 s, so it is not a fixed 36 to 44 s event.
- Track position at the late creation: runs 1, 3 and 6 at x -264, z -158 (speed 162 km/h); runs 2, 4 and 5 at x -140, z 260 (speed 56 to 97 km/h). The spike position from attempt 2 (x -241 to -255, z -193 to -235) is about 40 m away from both.
- The probe cannot name the class of the created Resource (only the count moves). Not identified.
- Result: **resource creation does not line up with the spike, and the spike is not at the creation point.** No `ResourceLoader` call is made in the race after GO according to the scene scripts (every `load()` in `game/race` and `game/world` runs at setup, checked by grep). The one late Resource is a lazy creation of something not yet identified. It is not evidence for or against the spike.

## Far-LOD rewrite counter

Not added. `CarLod.set_forced` rewrites visibility ranges at race setup (`race_scene.gd` line 454), not per frame, so a per-frame counter would be 0. Not measured.

## What was ruled out or not reproduced

- Race-start window (0 to 5 s): the contaminated runs show 18 to 36 frames over 25 ms, so the start is not clean in this batch. Attempt 2's clean start (0 frames in 15 runs) was not reproduced.
- Late Resource creation (above): not at the spike.
- Node churn after GO: none (4463 nodes, constant).
- Lap events: unchanged from attempt 3 (laps from 46.7 s).
- Lamp, rain, mirror, audio: not re-run in this attempt (the contamination makes one-variant runs uninterpretable). The attempt 3 bisect stays the last word on those.

## Not done

- The 6 of 6 fix check (no fix). Attempt 3's next steps are still open: 6 or more clean baseline runs with no other Godot process and no other render on the machine, then the lamp-only variant.
- Cold-cache first launch (not measured, as in attempts 1 to 3).
- Resource class attribution for the late creation (needs a probe that enumerates resources on the count change, or a `--no-lamps`/`--no-rain` variant run with the same counter).
- Phone measurement: none. Desktop numbers only.

## Files

- `game/devtools/scenarios/hitch_probe_run.gd`: resource count field and event (devtools only).
- `docs/perf/START_HITCH.md`: this section.
- Raw JSON and logs: `spike2/a4/` in the scratchpad (not in the repo; about 1 MB per run).
- Analysis script: `spike2/a4/analyse.py` (scratchpad).

## Next step if reopened

1. Wait for an idle GPU lock and a quiet desktop (no other Godot or browser load), then run 6 baseline runs with a `godot_procs` and CPU log per run. Accept a run only if its 0 to 5 s window is clean (no frame over 25 ms), as in attempt 2. Otherwise the batch is invalid.
2. Name the late Resource: on the count change, list the classes of the nodes that got a new material or texture in the same frame.
3. Only then a variant (`--no-lamps` alone, per attempt 3's caveat).
