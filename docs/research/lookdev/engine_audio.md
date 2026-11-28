# Racing game audio: research and recipe for MIDNIGHT SYNDICATE

Date: 2026-11-28. Scope: engine, tyres, wind, impacts, ambience, mix, voices, free sources, Godot 4.7 tools.
Method: public web pages only (search snippets and page fetches). Clean-room: techniques and numbers only.
Our own code was read: `game/audio/engine_layers.gd`, `docs/design/AUDIO_2026-11-28.md`.
The agent-reach CLI was not used (blocked on this PC).

Status of claims: "verified" means a fetched page said it. "snippet" means only a search result said it.
"unverified" means no source was read. Nobody has listened to our loops. A listening check is required.

---

## 1) What the best racers do (sourced)

**Layered, crossfaded engine loops tied to RPM and load.**
- Turn 10 (Forza) describes each car as well over 100 wave files. Physics inputs layer and crossfade them. Source: https://designingsound.org/2014/08/11/vehicle-engine-design-project-cars-forza-motorsport-5-and-rev/ (snippet).
- Gamasutra / Gamedeveloper article "Capturing Engine Sounds for Games" (verified): most cross-faded sets use on-load and off-load loops. A steady load is a blend of the two. On-load runs go low to high RPM. Off-load runs go high to low RPM. Recording at 48 kHz, 16-bit. Mics near exhaust, induction and in the cockpit. No loop count is given. https://www.gamedeveloper.com/audio/capturing-engine-sounds-for-games
- Audiokinetic loop-based engine design with Wwise, part 2 (snippet): pitch-controlled loops by RPM, plus separate on-load and off-load layers. https://www.audiokinetic.com/en/loop-based-car-engine-design-with-wwise-part-2
- Gran Turismo (Polyphony, snippet): loops recorded at several engine speeds, pitch-shifted and crossfaded. A designer draws an intake curve against throttle and an exhaust curve against load. Polyphony also gave a GDC 2024 talk (snippet). https://www.gtplanet.net/?p=146400
- Procedural alternative: AudioGaming AudioMotors (FMOD plugin, snippet). It synthesises engine load, accel/decel and gear changes instead of fixed RPM loops. https://www.mcvuk.com/development/how-to-make-racing-car-engines-roar-using-audiomotors-fmod
- Granular engine synthesis is discussed in Audiokinetic's sampling vs granular article (snippet only; the fetch returned 403). Treat its numbers as unverified. https://www.audiokinetic.com/engine-sound-modeling-from-sampling-to-granular-synthesis-in-wwise

**Small-budget example (verified).** The web.dev "Sounds of Racer" case study used 3 files only: an accel file with gear shifts that ends on a high-RPM loop, a decel file, and an idle loop. Throttle (0 to 1) times 3 gives the start position in seconds in the accel file. Loop points at 5 s and 9 s. When throttle is released, playback saves its position, plays decel, and on re-press jumps back to the matching point. The authors say 5 or 6 layer files per RPM layer sounded poor and loaded slowly. Source: https://web.dev/racer-sound
- Relevance: a jump-to-matching-position trick keeps the engine coherent without many layers. Our 12-voice band system is heavier. It is a better fit for quality, but it needs a CPU check on a phone.

**Tyre squeal by slip (patents, technique only; snippet).**
- A Sony driving-game patent classifies slip angle into ranges and crossfades three squeal waveforms. At large slip it becomes more pitched and aggressive. https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/8078300
- Another patent maps slip angle to volume and pitch with preset curves. https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/12626547
- Dolby (Wwise, drift game, verified in search): each tyre plays rolling and sliding sounds from car speed and slip at that wheel. https://games.dolby.com/blog/inertial-drift/
- Patents are cited to learn the idea only. We do not copy their claims.

**Wind, impacts, ambience.** The searches found no solid source for wind-by-speed or environment reverb zones in racing games. Mark these unverified. Our own plan is in section 3.

## 2) What it means in Godot 4.7 Mobile

**AudioStreamPlayer3D (verified, docs page marked stable).** https://docs.godotengine.org/en/stable/classes/class_audiostreamplayer3d.html
- `attenuation_model` default 0 (inverse distance). Options: inverse, inverse square, log, disabled.
- `unit_size` default 10.0. Scales the falloff.
- `max_distance` default 0.0 (off). Set it above 0 to cut sounds far away and save CPU. The cut is always linear.
- `max_polyphony` default 1. When exceeded, the oldest sound on that node is cut. This matters for shot and skid loops.
- `panning_strength` default 1.0. Set 0.0 to turn off stereo panning.
- `doppler_tracking`: enable on both player and listener to be exact.
- `area_mask`: routes sounds to buses or reverb by Area3D layer. Useful for tunnels and garages.

**AudioStreamInteractive and AudioStreamSynchronized (docs, 4.3 pages marked outdated; snippet).**
- Interactive: clips plus a transition table, with fade modes. Default FADE_AUTOMATIC. Playable through AudioStreamPlayer3D. https://docs.godotengine.org/en/4.3/classes/class_audiostreaminteractive.html
- Synchronized: several sub-streams start together and end with the last one. Max 32 sub-streams. Per-stream volume. https://docs.godotengine.org/en/4.3/classes/class_audiostreamsynchronized.html
- Use Synchronized for the 12-voice engine (one stream per band x load, all in phase). Our current code drives voices directly from `CarAudio`, which is fine and more controllable. Keep it unless the sync gives a clear win.
- Use Interactive for gear-shift transition stingers and the limiter bounce.
- Caveat: check the 4.7 class reference. The results we read were older versions.

**Buses and ducking (docs, 4.4 page; snippet).** Ducking is done with a bus effect that reads another bus's level, or with a compressor on the music bus. Renaming a bus breaks any player that refers to it by name. https://docs.godotengine.org/en/4.4/tutorials/audio/audio_buses.html

**Latency and timing (snippet).**
- `AudioStreamPlayer.play()` does not start at once. The sound starts at the next audio mix chunk. Use `AudioServer.get_time_to_next_mix()` to estimate it. https://docs.godotengine.org/en/4.4/tutorials/audio/sync_with_audio.html
- Godot issue 38215: `AudioServer.get_output_latency()` returns the same value in every case, so do not trust it for timing. https://github.com/godotengine/godot/issues/38215
- Android latency threads exist (OpenSL ES vs AAudio). No iOS or Metal-specific audio bug was found. Unverified for iOS. https://forum.godotengine.org/t/audio-latency-on-android-devices/134704
- The renderer (Mobile vs Forward+) does not change audio. Audio cost is CPU only.

**Our current code (read).** `game/audio/engine_layers.gd`: 6 bands x on/off load = 12 loops, equal-power crossfade inside a per-band zone. Max 2 audible loops. `CarAudio` measured about 20 us per frame on the dev PC (not a phone number).

## 3) RECIPE for our game

Each step names the file, the target, and the check. Checks use our harness and tests. Listening is always the owner's job.

**Step 1. Make the engine layers match the real load, then add a turbo layer.**
- Files: `game/audio/engine_layers.gd`, `game/audio/car_audio.gd`, `tools/audio_synth/engine_layers.py`.
- Add a turbo spool loop (rising pitch with boost) and a blow-off one-shot on throttle lift after boost.
- Target: spool rise 0.6 to 1.2 s from idle to boost. Blow-off under 0.4 s, gated by a boost threshold.
- Check: a new test in `game/tests/test_audio_layers.gd` (boost > 0 only above threshold). Capture: `gameplay_reel` with audio mix render to `evidence/audio/`.

**Step 2. Gear shift cut and pop, with an interactive transition.**
- Files: `game/audio/car_audio.gd` (shift handler already has an upshift cut). Add a short pop one-shot.
- Target: cut 0.15 to 0.25 s on upshift (we have 0.25 s). Pop under 80 ms and -6 dB under the engine.
- Check: the existing race trace test (20 s, upshift per 3 s cycle). Compare `evidence/audio/race20_log.csv`.

**Step 3. Tyre layers by slip, with a 3-range squeal crossfade.**
- Files: `game/audio/car_audio.gd`, new `game/audio/tyre_audio.gd`, per-wheel data from the vehicle code (`HANDLING_2026-11-28.md` owns the slip values).
- Use slip ratio for rolling vs sliding gain. Use slip angle in three ranges (low, mid, high) with equal-power crossfade. Pitch rises a little with high slip.
- Use the Dolby idea: each wheel has its own voice, with `max_polyphony` 1 per wheel.
- Target: 4 voices max for tyres; a silence under 0.2 slip; gain clamped to 0..1.
- Check: a headless sweep test (slip 0 to 1.5) asserting monotonic gain up to the knee, plus a capture on drift scenes.

**Step 4. Environment ambience per track and time of day, with an area mask.**
- Files: `game/audio/music_player.gd` (or a new ambience script), track scene `Area3D` nodes, `docs/design/TIME_OF_DAY.md`.
- Per track: Ortakoy water and boats, Maslak traffic hum, harbour gulls and buoys. Day and night gains differ.
- Use `AudioStreamPlayer3D` with `max_distance` 120 to 250 m and `attenuation_model` inverse square for water. Route tunnels and garages with `area_mask` to a reverb bus.
- Target: ambience under 6 voices total; mono, 22.05 kHz where possible to save memory.
- Check: a headless test that the ambience loops register in `AudioLib.FILES` and load. Listening check by the owner.

**Step 5. Mix: music ducking under engine, bus levels, limiter.**
- Files: `game/default_bus_layout.tres` (lead-owned; ask the lead first), `game/audio/music_player.gd`.
- Duck the music bus by 6 to 9 dB while the engine RMS is above a threshold, with 50 ms attack and 400 ms release.
- Put a limiter on the master bus at -1 dBFS. Keep engine loops at the RMS levels from the notes (0.028 to 0.160), not peak.
- Target: no clipping in the 20 s mix (current peak 0.226, RMS 0.073 from `race20_player_mix.wav`).
- Check: a render of the mix to WAV and its peak and RMS, saved under `evidence/audio/`.

Bonus steps (later): wind by speed (noise bed gain = speed^2, cut under 30 km/h), impacts by force (scrape, heavy hit, glass) with a per-material pool of 6 to 8 one-shots, and voice budgets (player 4 engine + 4 tyre + 2 impact + 2 ambience = 12 voices).

## 4) Risks and what not to do

- Do not claim sound quality. Nobody has listened to the loops. Owner listening is required. Say "in tune on the dev PC" only.
- Do not copy the patents or any game's sound files. Use them for the idea only.
- Do not use the Sonniss GDC bundle in the shipped game without owner approval. The project rule is CC0 or CC BY 4.0 only. The Sonniss EULA is a custom licence. The 2024 bundle bars AI training. A forum user says it bars unchanged republishing. Verify the licence on the official Sonniss page before any decision. https://licenseorg.com/guide/music-audio/sonniss (not legal advice). https://freesound.org/forum/legal-help-and-attribution-questions/42190
- Freesound: many CC0 files exist, but downloads need a login. The agent cannot log in or make an account. The owner must do that. Check each file's licence on its page.
- OpenGameArt: `racing car engine sound loops` by domasx2 is listed as CC0 (snippet). Verify on the page before use. https://opengameart.org/content/racing-car-engine-sound-loops
  - Excluded: `Car Engine Loop 96kHz, 4s` and `engine loop heavy vehicle/tank` are CC BY 3.0 (snippet). CC BY needs a credit line in `game/ui/credits_third_party.txt` and an entry in `THIRD_PARTY_LICENSES.md`. https://opengameart.org/content/car-engine-loop-96khz-4s
  - SuperTuxKart sound effects (CC0, snippet): https://opengameart.org/content/supertuxkart-sound-effects
- Do not raise polyphony by stacking the same stream. Use `max_polyphony` on a separate node per voice, as the forum thread warns about cut-offs.
- Do not trust `get_output_latency()` for timing. Measure instead.
- Do not add a per-frame allocation in `update_audio`. The 998 us spike on the dev PC is a warning sign.
- Do not tune phone CPU from dev-PC numbers. Report only as "dev PC" until a real iPhone measurement exists.
- Do not add more than 12 engine loops without a CPU check.

## 5) Sources list

Verified (fetched):
- https://docs.godotengine.org/en/stable/classes/class_audiostreamplayer3d.html
- https://www.gamedeveloper.com/audio/capturing-engine-sounds-for-games
- https://web.dev/racer-sound
- https://games.dolby.com/blog/inertial-drift/ (search snippet, page not fetched; treat as snippet)

Snippet only (search results, not fetched):
- https://designingsound.org/2014/08/11/vehicle-engine-design-project-cars-forza-motorsport-5-and-rev/
- https://www.audiokinetic.com/en/loop-based-car-engine-design-with-wwise-part-2
- https://www.gtplanet.net/?p=146400
- https://www.mcvuk.com/development/how-to-make-racing-car-engines-roar-using-audiomotors-fmod
- https://www.audiokinetic.com/engine-sound-modeling-from-sampling-to-granular-synthesis-in-wwise (fetch returned 403)
- https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/8078300
- https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/12626547
- https://docs.godotengine.org/en/4.3/classes/class_audiostreaminteractive.html (outdated page)
- https://docs.godotengine.org/en/4.3/classes/class_audiostreamsynchronized.html (outdated page)
- https://docs.godotengine.org/en/4.4/tutorials/audio/audio_buses.html
- https://docs.godotengine.org/en/4.4/tutorials/audio/sync_with_audio.html
- https://github.com/godotengine/godot/issues/38215
- https://forum.godotengine.org/t/audio-latency-on-android-devices/134704
- https://licenseorg.com/guide/music-audio/sonniss
- https://freesound.org/forum/legal-help-and-attribution-questions/42190
- https://bedroomproducersblog.com/2026/03/16/sonniss-gdc-2026-bundle/
- https://opengameart.org/content/racing-car-engine-sound-loops
- https://opengameart.org/content/supertuxkart-sound-effects
- https://opengameart.org/content/car-engine-loop-96khz-4s

Repo files read: `game/audio/engine_layers.gd`, `docs/design/AUDIO_2026-11-28.md`.
