# Environment look development for mobile racing cities (Godot 4.7 Mobile, iOS)

Scope: city look for the three tracks (Ortakoy/Bosphorus day, Maslak business district, neon harbour).
Topics: kits and trim sheets, atlases, baked light, facades, road detail, skyline, colour per track.
Facts are marked [S] (read in a source) or [E] (estimate or inference). Unverified items say so.
Read first: docs/art/VISUAL_TARGET.md, docs/research/04-godot-mobile-rendering.md (already settles the
Mobile renderer feature table, light caps and probe caps; not repeated in full here).

## 1) What the best mobile racers do

Sourced evidence on this topic is thin. Most public material is either a studio summary or a vendor blog.

- Modular kits with trim sheets. A trim sheet is one texture with horizontal or vertical strips of
  materials. A whole building face can use one material, which cuts material count and draw calls. [S, weak]
  Source: Blender city-map write-up for a mobile racer, https://bestgami.com/blender-city-map-creation-for-rebel-racing/
  A 80.lv talk summary on a large mobile city reports that batching, atlases and shared trim materials
  "significantly" cut draw calls. No numbers given. [S, vague]
  Source: https://80.lv/articles/designing-large-scale-mobile-game-cities-production-optimization-worldbuilding-expertise
- Trim sheet talk. A GDC talk titled "The Ultimate Trim Texturing Techniques" is named in a blog. I could not open
  it, so its content is unverified. [E]
  Source (secondary): https://www.exp-points.com/scifi-facility-trim-texture-study
- Draw-call budget. A vendor blog says mid-range mobile should stay near 100 draw calls per frame, and gives
  100 to 150 for 2026. Vendor claim, unverified against a primary source. [E]
  Source: https://www.creatuneagency.com/en/blog/low-poly-3d-models-for-mobile-games/
- Wet road reflections in the target class. A 2018 GSMArena review says the game uses screen-space
  reflections on cars and puddles. Weak source, not a technical breakdown. [S, weak]
  Source: https://www.gsmarena.com/asphalt_9_legends_game_review_for_ios_and_android-news-32552.php
  Gameloft talks or frame analyses were not found in this pass. A future search on gdcvault.com or Digital Foundry
  frame analysis would be the next step. [unverified gap]
- Interior mapping for building windows. A real-time pixel-shader technique. The interior is raycast against
  regular walls, ceilings and floors, so no room geometry is needed. Ray cost does not grow with the number of
  rooms. Van Dongen (2008) is the primary source. Works in shader model 2.0 and up. [S]
  Sources: https://www.proun-game.com/Oogst3D/CODING/InteriorMapping/InteriorMapping.pdf ;
  https://www.gamedeveloper.com/programming/interior-mapping-rendering-real-rooms-without-geometry
  The claim that a well-known open-world game uses it is unconfirmed. Do not repeat it as fact. [E]

Takeaway for us: the target look comes from a small number of big, bright, reflective hero surfaces plus
cheap depth cues (fog, glow, lit windows). It does not come from dense geometry in the city.

## 2) What that means in Godot 4.7 Mobile

### Hard limits on the Mobile renderer [S, from docs/research/04]

- No SSR, SSAO, SSIL, SDFGI, VoxelGI, volumetric fog or TAA. The renderers page lists these as
  Forward+ only. Source: https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html
- Decals work on Mobile but only 8 per mesh resource. Extra decals on the same mesh are dropped.
  Source: https://github.com/godotengine/godot-docs/blob/master/tutorials/3d/using_decals.rst (the cap note)
- ReflectionProbe: 8 per mesh on Mobile, 2 on Compatibility, unlimited on Forward+.
  Source: https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html
- Light caps: 8 Omni and 8 Spot per mesh resource on Mobile. Source:
  https://docs.godotengine.org/en/stable/tutorials/3d/lights_and_shadows.html
- Occlusion culling gives Mobile its biggest relative gain (no depth prepass). Source:
  https://docs.godotengine.org/en/stable/tutorials/3d/occlusion_culling.html

### SDFGI and VoxelGI

Both are off on Mobile. The 4.4 and stable docs say SDFGI and VoxelGI are Forward+ only. A 2026 Godot
proposal discussion adds a maintainer view that mobile GPUs are too weak for real-time GI at playable
frame rates. Do not plan any real-time GI on this project.
Sources: https://docs.godotengine.org/en/stable/tutorials/3d/global_illumination/using_sdfgi.html ;
https://github.com/godotengine/godot-proposals/discussions/14762

### LightmapGI (baked GI) on Mobile

- Official docs: lightmaps baked on desktop can be shown on the Mobile renderer. The docs say Android shows
  lightmaps only if they were baked elsewhere. [S] Source:
  https://docs.godotengine.org/en/4.2/tutorials/3d/global_illumination/using_lightmap_gi.html
  The same page for stable says baking is not supported in the web editor. [S]
  Source: https://docs.godotengine.org/en/stable/tutorials/3d/global_illumination/using_lightmap_gi.html
- Baking needs a Vulkan backend (Forward+ or Mobile). Compatibility cannot render LightmapGI. [S]
  Source: https://docs.godotengine.org/en/4.1/classes/class_lightmapgi.html
- Only sibling or child meshes of a LightmapGI node are baked. At most 8 LightmapGI nodes render at once. [S]
- Baking reserves the UV2 channel. CSG and primitive meshes cannot be baked (no UV2). [S, 4.1 and 4.2 docs]
- Known Mobile bug: repeated bakes with a procedural sky on the Mobile renderer give black lightmaps. It does
  not happen on Forward+, or with Environment Mode set to Disabled or Custom Color. [S]
  Source: https://github.com/godotengine/godot/issues/84823
- Unconfirmed: a forum thread reports a 4.4 RC app closing on a phone with Mobile-baked lightmaps. [E, unconfirmed]
  Source: https://forum.godotengine.org/t/lightmap-gi-not-doing-a-damn-thing/99603

### Can LightmapGI be baked headless or from a script?

No documented way. [S for docs, E for forum]
- Official docs say baking is an editor function.
- Forum users report that `LightmapGI.bake()` is not exposed to scripting, even in editor builds. [E]
  Source: https://forum.godotengine.org/t/is-it-possible-to-bake-lightmapgi-node-using-headless-godot-editor/129607
- A headless editor reports no GPU device and says baking is unsupported. A custom build may return
  BAKE_ERROR_NO_LIGHTMAPPER. [E]
- Third-party option: pavlaka bakes with Blender Cycles and can run from the command line with `--pavlaka-bake`.
  It is a different pipeline, so output will not match the native lightmapper. Command syntax not verified. [E]
  Source: https://github.com/milkru/pavlaka

Plan: bake in the Godot editor on this Windows PC with the Vulkan backend. Commit the baked lightmap
resources. Ship them to iOS. Verify on a real iPhone, since the Simulator is Compatibility only [S].
Our Windows PC is the desktop host the docs describe, so the Android-style "bake elsewhere" rule
fits. Whether iOS behaves the same way is [E]; test it.

### ReflectionProbe

- Mobile cap: 8 probes per mesh. Keep probes per mesh at 2 to 4 [E].
- Open issue: on the Mobile renderer, a probe returns about twice the radiance it captured, and clips at 1.0.
  Check it before tuning brightness. [S] Source: https://github.com/godotengine/godot/issues/124069
- Update mode: use "once" for static blocks. Real-time probes are costly. Source (4.4 docs):
  https://docs.godotengine.org/en/4.4/tutorials/3d/global_illumination/reflection_probes.html
- Our code: draw_breakdown.gd already reads a `lighting/ReflectionProbes` node. Use that node for the baseline
  measurement. [repo]

### Decals

- Mobile: 8 decals per mesh resource. Put road decals (puddles, skid marks, wet patches) on a separate
  road chunk mesh, and keep each chunk to 8 or fewer decals. [E]
- Decal cost is not documented for Mobile. Measure it. [unverified]

### Fog, glow and grading (what we already use)

- time_of_day.gd sets fog colour, fog begin and end, aerial fog, sun scatter and glow per track. [repo]
- Non-volumetric fog support on Mobile is not stated in the renderer table read. Test it on device. [E]
- Volumetric fog is off on Mobile [S]. The repo's world_materials and fx_wet_road scenarios use plain fog
  only. Keep it that way.

## 3) Recipe for our game

Each step names files from the repo where I found them. Targets are starting numbers, to be measured.
Desktop numbers are not iPhone numbers (project rule).

### Step 1: Bake static city light into lightmaps (Ortakoy and Maslak first)
- Mark road, kerbs, building shells and kit roots as static. Give each street block its own LightmapGI
  child set. Stay under 8 LightmapGI nodes in view.
- Give every baked mesh a UV2 unwrap. Lightmap size 512 to 1024 per block [E].
- Set Environment Mode to Custom Color or Disabled when baking. Avoid the procedural-sky black lightmap bug [S].
- Files: game/world/istanbul_bogaz/, game/world/istanbul_maslak/ (scenes), game/world/city_01/city_builder.gd
  (kit roots placed here; check that it keeps UV2).
- Verify: capture `tod_tracks` and `ortakoy_benchmark`. Check that the road and walls show bounce light
  and no black patches. Check the frame time with draw_breakdown on the Windows PC. Then measure on an iPhone.

### Step 2: Trim sheets and atlases for facades (cut material and draw count)
- One trim-sheet material per street family, not one per shop. Target: 4 or fewer facade materials per track [E].
- Keep texture max 2048 on Mobile (4096 is a display risk) [S, from 04 doc].
- Files: game/world/materials/material_library.gd, game/world/materials/istanbul_materials.gd,
  game/world/street_fronts/storefront.gd.
- Verify: draw_breakdown counts before and after; target fewer MeshInstance3D nodes per track.

### Step 3: Interior mapping on lit windows (the depth cue the target needs)
- Add a parallax interior term to window_atlas.gdshader for LOD0 facades only (within 30 m,
  LOD0_END_M in street_fronts.gd). Use 3 to 4 room layers with random tint per window cell [E].
- Keep the per-pixel cost low: a few ray-plane steps, no extra texture fetches beyond the atlas [E].
- Files: game/world/materials/window_atlas.gdshader, game/world/street_fronts/street_fronts.gd (LOD0_END_M).
- Verify: gameplay_reel at night. Frame time on device must stay within budget. Do not ship if the device
  time rises by more than the agreed budget (set by the lead).

### Step 4: Wet road without SSR (use the mirror path that already exists)
- Keep the existing wet-road mirror (MIRROR_LAYER in street_fronts.gd) for reflections. Do not add SSR.
- Add decal puddles and skid marks on separate road chunks, 8 decals or fewer per mesh [S].
- Keep the neon colour streaks as emissive strips on the road, not as extra lights. Respect the 8 + 8
  light cap per mesh [S].
- Files: game/world/street_fronts/street_fronts.gd (mirror layer), game/world/time_of_day/track_grade.gd
  (wet grade), game/devtools/scenarios/fx_wet_road.gd.
- Verify: capture fx_wet_road and gameplay_reel; check streak count and colour on the road.

### Step 5: One ReflectionProbe per block, update once, 2 to 4 per mesh
- Place probes per street block, not per building. Update mode once. Check the 2x brightness issue first
  (issue 124069) and trim intensity to match the baseline [S].
- Files: the lighting scene that holds the `ReflectionProbes` node (used by draw_breakdown.gd).
- Verify: draw_breakdown "reflection probes" group before and after; visual check on chrome and paint.

### Step 6: Colour script per track in time_of_day.gd, not in the art
- Keep fog colour, glow and grade as per-track values in time_of_day.gd. Do not bake colour into textures.
- Target palette: Ortakoy day = warm sun, blossom pink in fog; Maslak = cool steel; harbour = teal and magenta neon.
- Verify: tod_tracks scenario (one frame per track and time) and compare with VISUAL_TARGET.md.

## 4) Risks and what not to do

- Do not plan SDFGI, VoxelGI, SSR, SSAO, volumetric fog or TAA. They do not run on Mobile [S].
- Do not assume headless bake works. Bake in the editor only [S/E].
- Do not put more than 8 decals on one mesh. The rest are dropped silently [S].
- Do not add more than 8 probes or 8 + 8 lights to one mesh [S].
- Do not trust the iOS Simulator for Mobile look. It runs Compatibility only [S]. Test on a real iPhone.
- Do not bake lightmaps with a procedural sky on Mobile without checking for black output [S].
- Do not ship interior mapping on far facades. It costs shader time on every pixel that sees a window.
- Do not report desktop frame times as iPhone numbers (project rule).
- Lightmap size and texture budget numbers here are starting points [E]. Measure before locking.

## 5) Sources

Official Godot docs
- https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html
- https://docs.godotengine.org/en/stable/tutorials/3d/lights_and_shadows.html
- https://docs.godotengine.org/en/stable/tutorials/3d/occlusion_culling.html
- https://docs.godotengine.org/en/stable/tutorials/3d/global_illumination/using_lightmap_gi.html
- https://docs.godotengine.org/en/4.2/tutorials/3d/global_illumination/using_lightmap_gi.html
- https://docs.godotengine.org/en/4.1/classes/class_lightmapgi.html
- https://docs.godotengine.org/en/stable/tutorials/3d/global_illumination/using_sdfgi.html
- https://docs.godotengine.org/en/4.4/tutorials/3d/global_illumination/reflection_probes.html
- https://github.com/godotengine/godot-docs/blob/master/tutorials/3d/using_decals.rst

Godot issues, forum, proposals
- https://github.com/godotengine/godot/issues/84823 (Mobile lightmap black after repeated bake)
- https://github.com/godotengine/godot/issues/124069 (Mobile probe radiance 2x)
- https://github.com/godotengine/godot-proposals/discussions/14762 (SDFGI and VoxelGI on Mobile)
- https://forum.godotengine.org/t/lightmap-gi-not-doing-a-damn-thing/99603 (unconfirmed crash report)
- https://forum.godotengine.org/t/baked-lights-in-mobile-renderer-show-in-just-two-scenes/121094
- https://forum.godotengine.org/t/is-it-possible-to-bake-lightmapgi-node-using-headless-godot-editor/129607 (headless bake)
- https://github.com/milkru/pavlaka (third-party Cycles lightmapper)

Techniques and production
- https://www.proun-game.com/Oogst3D/CODING/InteriorMapping/InteriorMapping.pdf (Van Dongen, interior mapping)
- https://www.gamedeveloper.com/programming/interior-mapping-rendering-real-rooms-without-geometry
- https://80.lv/articles/designing-large-scale-mobile-game-cities-production-optimization-worldbuilding-expertise
- https://bestgami.com/blender-city-map-creation-for-rebel-racing/ (trim sheet kit, weak source)
- https://www.exp-points.com/scifi-facility-trim-texture-study (names a GDC trim talk, unverified)
- https://www.creatuneagency.com/en/blog/low-poly-3d-models-for-mobile-games/ (draw-call numbers, vendor claim)
- https://www.gsmarena.com/asphalt_9_legends_game_review_for_ios_and_android-news-32552.php (SSR claim, weak)

Not verified in this pass
- GDC talk contents on trim sheets. Gameloft talks on wet roads. Mobile decal cost. Mobile non-volumetric fog
  support. Draw-call budget from a primary source. iOS behaviour of Mobile-baked lightmaps.
