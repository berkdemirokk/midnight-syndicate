# Night and wet roads: cheap techniques for mobile racers (Godot 4.7 Mobile)

Date: 2026-11-28. Scope: wet-road reflections, neon and bloom, headlight pools, rain and spray, lens effects, night tone mapping. Target: iPhone, Godot 4.7.2, Mobile renderer, offline.

Status key: [S] = source read or confirmed. [E] = our reasoning, not measured. [U] = unverified (search snippet only, or no number given).

---

## 1. What the best mobile racers do

**Asphalt Legends (Gameloft, Jet Engine).** Wet-road highlights come from HDR and pixel shaders: sky and road specular. [S: https://thecoolestvideogames.fandom.com/wiki/Asphalt_Legends_Unite ; weak, fan wiki]. A Grokipedia summary says the same, but it is user-written, so treat it as [U]: https://grokipedia.com/page/asphalt_legends . No Gameloft talk on wet night or neon was found. [U]

**Need for Speed Heat (PC and console, not mobile).** Fan press praises neon light reflected on wet night roads [S: https://racinggames.gg/need-for-speed/need-for-speed-unbound-3-things-it-should-keep-from-heat/ , opinion]. A modder page for Heat says road reflections are "pretty busted" and that screen-space reflections sit at the wrong depth [U: modder opinion, Frostbite 3: https://helixmod.blogspot.com/2019/11/need-for-speed-heat.html is not that page, so treat as search snippet only]. Lesson: even AAA teams had reflection depth problems. Test reflections at the real camera angles, not only at the hero shot.

**Apex GP (indie, sky mirror by emission).** The road gets a fake sky reflection. Water Fresnel is computed against the sky radiance, with albedo left out. The reflection is an emission term, tuned against measured sky brightness. [S: https://guudgames.itch.io/apex-gp/devlog/1768333/wet-asphalt-that-mirrors-the-sky-and-shadows-baked-where-trees-stand]
- Road under the horizon reached 0.91x sky on desktop, 0.98x on mobile (first pass, gain 1.05, exponent 4).
- Second pass: gain 1.5, exponent 5.0, water-to-road ratio 0.957 at the chase camera.
- No frame cost for the reflection is given. [U]
- Why it matters for us: our `wet_asphalt.gdshader` already writes `EMISSION = refl * fres * amount * reflection_strength`. The same idea works without a second camera. The sky term can be tuned the same way.

**Unity mobile light-cookie reports (forum, [U]).** One developer saw a directional cookie cut frame rate by about 30%. Another profiler showed about 10 ms of cookie cost on an Android device. [U: https://discussions.unity.com/t/light-cookie-performance-cost/664681 and https://discussions.unity.com/t/30-lights-emulation-in-mobile/712442 , search snippets]. Lesson: a real light with a cookie is expensive on phones. A quad with a light texture is the usual cheap substitute.

**Practical rule across these sources:** the look comes from a few strong light sources, a wet mirror that is tinted and blurred, and a fake sky term. Full real-time reflection of the whole city is not needed.

---

## 2. What this means in Godot 4.7 Mobile

### 2.1 Feature support on Mobile [S]
Source: https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html (feature table, read in this session).

| Feature | Mobile |
|---|---|
| Screen-space reflections (SSR) | Not supported |
| SSAO, SSIL | Not supported |
| SDFGI, VoxelGI | Not supported |
| Volumetric fog | Not supported |
| TAA | Not supported |
| Glow | Supported |
| Decals | Supported |
| Reflection probes | Supported, 8 per mesh |
| Omni and spot lights | 8 each per mesh, 256 each per view |
| 2D HDR viewport | Supported |

**Consequence:** there is no SSR path. Wet roads must come from a planar mirror, a fake sky term, roughness and normal work, or probes. Do not start a custom screen-space trace on a phone. [E]

### 2.2 Glow and bloom [S]
Source: https://docs.godotengine.org/en/stable/tutorials/3d/environment_and_post_processing.html
- Glow shows where light is above `glow_hdr_threshold` or where Bloom is above 0.
- Default threshold is 1.0. Lower values let more light bleed.
- Mobile uses bilinear upscale by default, not bicubic. Bicubic costs GPU time.
- HDR 2D is supported on Mobile. It has a performance cost. With HDR 2D on, 2D renders in linear space, so `source_color` hints matter.

**Default change to watch [S]:** PR #110077 changed `glow_hdr_threshold` from 1.0 to 0.0 in a 4.6 dev build. It changed how glow looks. Issue #112469 was closed on 2025-11-10 (commit 802eb0b). The maintainer agreed to revert it for now. The reporter suggested 1.0 for Forward+ and 0.9 for Mobile. [S: https://github.com/godotengine/godot/issues/112469 ]. Lesson: set the threshold explicitly in code. Do not rely on the default.

### 2.3 Tone mapping [S]
Same environment page.
- Linear is the fastest. It clips.
- ACES and AgX are slower. AgX is the slowest.
- White of 6.0 to 8.0 is recommended for photoreal lighting.
- **Mobile trap:** with AgX, Mobile, and HDR 2D disabled, the White value is ignored and 2.0 is used.

**Check in our code [E]:** `game/world/time_of_day/time_of_day.gd` sets `tonemap_white = 6.0` for day and `2.5` in one preset. The comment on the default field says night `1.0` clips walls. We must confirm which tone mapper the Environment uses. If it is AgX with HDR 2D off, the White values above do nothing and the night preset is really 2.0. This is a quick check in the Environment resource and in the capture numbers.

### 2.4 Planar mirror: what we already have [S, our code]
`game/fx/planar_reflection.gd`:
- Mirror camera in a SubViewport at `resolution_fraction` 0.33 of the screen (each axis). That is about 11% of the pixels. [E]
- `every_second_frame` option. Mirror is re-rendered on even frames only.
- `max_distance_m` 150. Far plane is clipped so distant buildings do not appear.
- `excluded_layers` removes road, car LOD0 detail, small props and rain from the mirror.
- Mirror environment: tonemap linear, glow off, background = fog colour (avoids a violet sky band).

`game/shaders/wet_asphalt.gdshader`:
- Mirror taps: 5 taps, vertical smear, interleaved-gradient jitter. Grain from the normal.
- Puddle and damp split. Damp road gets `damp_reflectivity` 0.55 and patchiness 0.45.
- `EMISSION` carries the reflection, boosted by `reflection_strength` 2.4.

**Cost estimate [E]:** the mirror pass is a second scene render with fewer pixels, so roughly a tenth of the fill cost, plus a second draw-call and culling pass for the mirror layers. Draw calls for the mirror are not counted yet. Do not quote a number until we measure it on an iPhone.

**Known platform risk [S, UE forum, unverified fix]:** https://forums.unrealengine.com/t/mobile-planar-reflection-render-bug/466991 reports a mobile planar texture drawing as a square grid on device. Engine 4.25.1, device not stated, no fix in replies. Our code has no such check. We must look at the mirror on the real iPhone, not only in the desktop capture.

### 2.5 Other planar and wet-road methods (search snippets, [U])
- Three.js wet-ground note: hide ground during the mirror pass, render the scene to a render target, flip X, warp UVs with normal map and ripple offset. https://github.com/ektogamat/threejs-conference/blob/main/docs/techniques/wet-ground.md (read in search snippet only; fetch returned 503).
- Echoes of Somewhere: a mobile planar material with a reflectance mask, normal distortion, and optional blur. https://echoesofsomewhere.com/2023/02/11/ai-assisted-gamedev-adding-reflections/ [U]
- Vortex Engine issue #348: one planar reflection per frame budget, mirrored culling, Fresnel and wetness mask. https://github.com/shadow-kernel/Vortex-Engine/issues/348 [U]
- A paid Unreal SSPR plugin reflects the previous frame across the plane. Vendor claim, not checked. https://www.fab.com/listings/62177197-5a1b-429d-8670-9cad724e3901?lang=en [U]

### 2.6 Godot 4.7 changes that touch this [S]
Source: https://godotengine.org/releases/4.7/
- Clearcoat now accounts for sky reflections and reflection probes. This helps the car paint, not the road directly.
- New `AreaLight3D` node: rectangular lights with softer shadows and better reflections. Mobile support is not stated. [U]
- HDR output on iOS is listed for 4.7. Browser previews may not show it. Not a night-look change for us unless we test HDR output on the phone. [E]
- No change listed for glow, tone mapping, SSR, planar reflection, or decals.

### 2.7 Headlight pools and light streaks [U mostly]
- Real spot lights on Mobile: 8 per mesh, 256 per view. Each one adds shader cost to every lit pixel. [S, renderer table]
- Cheap route: a camera-facing quad or decal under each headlight with a soft cone texture, additive. The Unity forum suggests this as a fake pool. [U]
- Decals are supported on Mobile [S]. Our decal budget is unknown. Test it.

---

## 3. Recipe for our game

Five steps, in order. Each one ends with a check the capture harness can show.

**Step 1. Pin the night tone mapper and white point.**
- Files: `game/world/time_of_day/time_of_day.gd` (NIGHT preset, `tonemap_white`, `exposure`), the world Environment resource.
- Action: read the current tone mapper. If it is AgX, write down that White is ignored on Mobile with HDR 2D off. Decide: either switch to ACES with White 6 (day) and tune night exposure, or keep AgX and drop the White numbers from the code so they stop lying.
- Target: one number per preset that actually takes effect. No dead values.
- Verify: `godot --path game --audio-driver Dummy --resolution 1920x1080 --position 20000,0 res://devtools/capture_boot.tscn -- --capture=tod_tracks` then compare the night frames to the current `evidence/screens/tod_tracks/*.png`. Look at wall highlights and the road. Owner signs off on the crop.

**Step 2. Pin the glow threshold and check bloom on neon.**
- Files: the Environment `glow_hdr_threshold`, `glow_bloom`, `glow_intensity` via `time_of_day.gd`.
- Action: set `glow_hdr_threshold` explicitly on every preset (night starting point 1.0 or 0.9 for Mobile per the issue thread). Keep bilinear upscale. Keep bloom at the night value (0.06 per current code). Do not enable HDR 2D unless step 1 requires it, because it has a per-frame cost. [E]
- Target: neon signs bloom, road does not veil, sky does not glow.
- Verify: `--capture=ortakoy_benchmark` and `--capture=gameplay_reel` at night. Crops of neon signs and the wet road. Measure on the iPhone build, not on the desktop.

**Step 3. Make the wet mirror cheaper and safer on phones.**
- Files: `game/fx/planar_reflection.gd` (`resolution_fraction`, `every_second_frame`, `max_distance_m`, `excluded_layers`), `game/shaders/wet_asphalt.gdshader` (`reflection_strength`, `reflection_smear`, `reflection_grain`).
- Action: add a Mobile tier. Start at 0.33 resolution, `every_second_frame` true, `max_distance_m` 120 to 150. Keep the 5-tap smear. Add a short debug toggle so the team can see the mirror alone.
- Target: mirror pass under about 2 ms on iPhone [E: our target, not measured]. No grid or square artefacts.
- Verify: on-device check of the mirror at night on Maslak and the harbour. Also a desktop capture with `--capture=tod_tracks`. Desktop frame times are not iPhone numbers. Name the machine in every number.

**Step 4. Replace extra real lights with pools and streaks.**
- Files: `game/fx/headlights.gd`, `game/fx/underglow.gd`, `game/fx/car_fx.gd`, `game/fx/rain.gd`.
- Action: keep at most the existing real headlight (or none for far cars). Add a quad or decal "light pool" under each headlight, additive, with a soft cone texture. Use it for the street-lamp pools on wet road too.
- Target: a pool of light under each headlight. Draw-call count stays at or below the current figure (the night frames are at 423 draws, 410,342 primitives per `evidence/screens/tod_tracks/city_night.json`; that is from the RATING_STRATEGY note, not re-read here).
- Verify: `--capture=gameplay_reel` at night, count draws in the JSON, look at the pool in the crop.

**Step 5. Rain and spray for wet feel, cheap and short-lived.**
- Files: `game/fx/rain.gd`, `game/fx/wheel_spray.gd`, `game/fx/rain_on_lens.gd`, `game/fx/speed_lines.gd`.
- Action: keep rain on the GPU and short-lived. Keep spray tied to wheel contact with puddles. Use a light lens drop layer, not a full-screen distortion. Cap particles per emitter under about 200 on CPU [S for guidance style: docs tutorial and our own rules, see the earlier research file].
- Target: visible spray only on puddles, no lens smear at speed.
- Verify: `--capture=gameplay_reel` with rain on. Look at the spray crops. Check the particle count in the capture JSON.

---

## 4. Risks and what not to do

1. **Do not write SSR.** Mobile does not have it. A custom screen-space trace costs more than the mirror and is hard to make correct.
2. **Do not add real spot lights per car.** Each is a per-pixel cost on phones. The cap is 8 per mesh and 256 per view. Use pools.
3. **Do not trust desktop frame time for the phone.** The mirror and glow costs differ on a tile-based GPU. Measure on the iPhone build.
4. **Do not trust the Godot default glow threshold.** It changed in 4.6 dev and was reverted. Set it in code.
5. **Do not leave dead tone-mapping numbers in code.** On AgX with HDR 2D off, White is ignored. Check before tuning.
6. **Do not use `AreaLight3D` on the road until it is tested on Mobile.** The 4.7 notes do not state Mobile support. [U]
7. **Do not claim a visual match to any reference game from a tuned number alone.** The owner judges the crops.
8. **Watch the planar grid bug.** The UE forum shows a mobile planar texture drawing as a square grid on device. Check the mirror on the phone.
9. **Light cookies are expensive on phones.** One forum reported 30% frame loss. Use a quad instead. [U]

---

## 5. Sources

Read or confirmed in this session:
- https://docs.godotengine.org/en/stable/tutorials/3d/environment_and_post_processing.html (glow, HDR 2D, tone mapping, Mobile notes)
- https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html (Mobile feature table: SSR, probes, lights, decals, HDR 2D)
- https://godotengine.org/releases/4.7/ (clearcoat, AreaLight3D, HDR output)
- https://github.com/godotengine/godot/issues/112469 (glow_hdr_threshold default change and revert)
- https://guudgames.itch.io/apex-gp/devlog/1768333/wet-asphalt-that-mirrors-the-sky-and-shadows-baked-where-trees-stand (sky mirror by emission, numbers)
- https://forums.unrealengine.com/t/mobile-planar-reflection-render-bug/466991 (mobile planar grid bug, UE 4.25.1)

Search snippets only (not opened or fetch failed) [U]:
- https://thecoolestvideogames.fandom.com/wiki/Asphalt_Legends_Unite (Asphalt Legends HDR and shader summary, fan wiki)
- https://grokipedia.com/page/asphalt_legends (user-written wiki)
- https://racinggames.gg/need-for-speed/need-for-speed-unbound-3-things-it-should-keep-from-heat/ (neon on wet roads, opinion)
- https://helixmod.blogspot.com/2019/11/need-for-speed-heat.html (Heat SSR and road reflection complaints, modder)
- https://github.com/ektogamat/threejs-conference/blob/main/docs/techniques/wet-ground.md (wet-ground planar method; fetch returned 503)
- https://echoesofsomewhere.com/2023/02/11/ai-assisted-gamedev-adding-reflections/ (mobile planar material)
- https://github.com/shadow-kernel/Vortex-Engine/issues/348 (one mirror per frame budget)
- https://www.fab.com/listings/62177197-5a1b-429d-8670-9cad724e3901?lang=en (paid Unreal SSPR plugin, vendor claim)
- https://discussions.unity.com/t/light-cookie-performance-cost/664681 (cookie frame cost)
- https://discussions.unity.com/t/30-lights-emulation-in-mobile/712442 (pixel light budget, cookie quad idea)

Our repo files (read in part, this session):
- `game/shaders/wet_asphalt.gdshader` (full read)
- `game/fx/planar_reflection.gd` (full read)
- `game/world/time_of_day/time_of_day.gd` (grep only: NIGHT preset, tonemap_white, glow values)
- `docs/art/VISUAL_TARGET.md`, `docs/research/04-godot-mobile-rendering.md`, `docs/research/03-nfsu2-and-street-atmosphere.md`, `docs/research/BENCHMARK_MATRIX_2026-11-28.md`, `docs/research/RATING_STRATEGY_2026-11-27.md` (grep excerpts)
- `game/fx/rain.gd`, `game/fx/wheel_spray.gd`, `game/fx/headlights.gd`: named in the recipe; not read in full in this session.
