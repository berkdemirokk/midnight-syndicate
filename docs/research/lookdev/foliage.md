# Foliage for mobile racers: research and recipe

Scope: blossom and street trees, impostors, cards, alpha on mobile, overdraw, wind, LOD, petals.
Target: the owner's day drift frame (big pink blossom canopy over the road, back-lit, volumetric).
Renderer: Godot 4.7.2, Mobile renderer, iOS first.

Rule for every number below: "Verified" means read on the page. "Unverified" means general knowledge or a forum guess. No number here is measured on our game yet.

## 1) What the best mobile racers do

- Trees are real volume near the road, and cheap cards far away. Near trees use a modest leaf mesh or cut-out cards. Far trees become impostors. Source: Microsoft vegetation guide (see Sources). Unverified exact numbers.
- Overdraw is the main cost. Transparent leaves stack many times on a phone GPU. Simplygon's approach is a tight-fit impostor that follows the leaf silhouette, so there are fewer transparent layers. Source: Simplygon. Verified as a vendor claim, not measured.
- Leaf textures are kept small. A forum thread on Godot mobile foliage reports that 1024 x 1024 leaf textures are oversized, and suggests 128 or 256 for leaves. Verified as forum advice, no measurements. Source: Godot forum thread 106682.
- Blossom and petals are particles, not geometry. They are cheap if the count is low and they are not shadow casters. Our `game/fx/petals.gd` already does this.
- Clean lighting, not heavy shading. Foliage uses Lambert with no specular on mobile. Our `foliage.gdshader` and `tree_photo.gdshader` already use `diffuse_lambert` and `specular_disabled`.
- I could not find a sourced GDC talk or benchmark with exact polycounts, card counts or fill-rate numbers for mobile racers. This is a gap. Unverified.

## 2) What it means in Godot 4.7 Mobile

### Automatic instancing is off on Mobile
- Verified: the Godot optimizing page says automatic instancing is "only implemented in the Forward+ renderer, not Mobile or Compatibility." Source: Godot optimizing 3D performance.
- Meaning: we cannot rely on automatic instancing. Our `greenery.gd` uses MultiMeshInstance3D, which is the correct path. Keep it.
- The same page says alpha-blended materials are never instanced, and instancing needs opaque or alpha-tested (scissor or hash) materials.

### Alpha scissor versus alpha blend
- Verified: the page says "the material must be opaque or alpha-tested (alpha scissor or alpha hash)" for instancing.
- Verified: Godot's docs say to use as few transparent objects as possible, and that stacked transparent billboards "may start eating into fill rate."
- Our leaves are cut out with `discard` in the shader (`foliage.gdshader` line 36, `tree_photo.gdshader` line 37). This is the alpha-tested path. Good.
- Unverified: a manual `discard` in a fragment shader can stop early depth testing on some GPUs, which costs fill rate. Test this on the capture harness before trusting it. Our `alpha_cut` default is 0.35 in the photo shader.

### Alpha to coverage (anti-aliasing for scissor edges)
- Verified: Godot's anti-aliasing page says MSAA "does not reduce transparency aliasing" for Alpha Scissor materials. Alpha to coverage is the fix, "effective at reducing aliasing on transparent materials without introducing any blurriness," with a "moderate" cost.
- Verified: the same page says MSAA levels above 2x "are unlikely to run smoothly on mobile GPUs," and FXAA is usually the only viable option on low-end mobile.
- Verified: TAA and FSR2 are not available on the Mobile renderer.
- Our custom foliage shaders do not set an alpha-to-coverage option. The option is exposed on `StandardMaterial3D` and `ORMMaterial3D` only. Unverified whether it can be enabled from our custom `.gdshader` path. Check this before the recipe step.
- Mobile cost of alpha to coverage is not measured. Test it.

### Visibility ranges (LOD) in Godot 4.7
- Verified: Begin is measured from the instance's AABB centre, and End too (4.7 docs). Older docs said origin. Use the 4.7 meaning.
- Verified: Fade mode Disabled switches instantly and gives the best performance. Self and Dependencies alpha-blend the fade and force transparent rendering, which costs fill rate.
- Verified: Dithering is faster than alpha fading but shows a "noisy" pattern. It needs separate materials per LOD and works best with two LODs.
- Our `greenery.gd` uses `LOD_RANGES` of 0-60, 60-150, 150-320 m with no margins (hard pops). That matches the cheapest mode. Keep it.
- Verified: the docs say that Visibility Parent (HLOD) lets child nodes follow a parent range. Not used by us yet.

### Impostors in Godot
- Verified: the Godot docs say visibility ranges "are also a good way to set up impostors for distant geometry."
- Verified: an example in the docs shows a Sprite3D impostor at distance. That is a plain sprite, not a view-dependent impostor.
- Verified: a free addon exists, `Godot-Octahedral-Impostors` by SIsilicon, which bakes octahedral impostors. Its licence is not checked here. Before use, check it is MIT, CC0 or CC BY and record it in `THIRD_PARTY_LICENSES.md`. Unverified licence.
- Octahedral impostors pick the view angle from a small atlas (8 x 8 or similar). Unverified numbers for mobile.

### Wind
- Our `foliage.gdshader` sways vertices with a sum of two sines, weighted by height (`sway_amp_m` 0.12 m, `sway_speed` 1.1, `sway_height_m` 9 m). This is cheap. Good.
- Verified: the Godot docs say vertex animation "can be very expensive on some platforms." Keep the sway to vertex math only. No per-tree materials.

### Known issues to watch
- Verified: the Godot forum thread on mobile foliage found the foliage drop from 60 to 23 FPS, with alpha as the costliest option, and that shadows were not the cause. The thread gives no measured numbers. Source: forum 106682.
- Verified: one forum answer says alpha-blended leaves need depth prepass, which adds cost. Source: forum 130869 (qualitative).

## 3) Recipe for our game

Each step names the file, the target number, and how to verify it. Targets are proposals, not measurements. The capture harness is the only evidence that counts. Use `--resolution 1920x1080` and state the machine (Windows RTX 5060 Ti) on every number. Do not report desktop numbers as iPhone numbers.

### Step 1: Keep every tree leaf alpha-tested, never alpha-blended
- Files: `game/shaders/foliage.gdshader`, `game/shaders/tree_photo.gdshader`, `game/world/greenery/greenery.gd`.
- Target: zero alpha-blended tree materials. Trunks and leaves stay in MultiMesh.
- Verify: `godot --path game ... -- --capture=tod_tracks` and grep the materials list in the debug output for `transparency`. Expect none on trees.

### Step 2: Shrink leaf textures to the size each LOD needs
- Files: `assets_src/world/kit_trees/prepare_licensed_trees.py` (leaf atlas), `game/assets/world/kits/trees_photo/`.
- Target: LOD0 leaves at 512 px, LOD1 at 256 px, LOD2 cards at 256 px. Power-of-two only. Test 1024 px on the hero blossom tree only if the frame still reads well.
- Verify: `ortakoy_benchmark` scenario frame time before and after, plus a `tod_tracks` still of the blossom street. Compare visually to the owner's day frame: canopy must still read as pink mass, not grey dots.

### Step 3: Set one tight LOD ladder and use Fade Disabled
- Files: `game/world/greenery/greenery.gd` (`LOD_RANGES`, `CROWN_R_M`).
- Target: keep 0-60 / 60-150 / 150-320 m. Keep fade mode Disabled. Add a 5 m begin margin only to hide pops if the reel shows a pop visibly.
- Verify: `gameplay_reel` scenario; look at a drive past a blossom row for pops.

### Step 4: Replace far photo cards with a tight-fit impostor, only after Step 2 is measured
- Files: `game/world/greenery/greenery.gd` (LOD2 cards), new asset built from `assets_src/world/kit_trees/`.
- Target: fewer transparent layers at 150 m+. Keep alpha-tested edges. Count cards per tree: target 2 to 3 crossed cards, not 6.
- Verify: a before and after frame time in `ortakoy_benchmark` on the same scene seed. Accept only if the gain is measured. Check the addon licence first.

### Step 5: Keep petals as one GPUParticles3D, capped, and turn them off on Low
- Files: `game/fx/petals.gd` (`AMOUNT` 140, `LIFETIME_S` 7, `BOX` 36 x 9 x 36).
- Target: keep the count at 140 on Medium/High. Do not raise it. Overdraw from sprites counts, so do not raise petal size past 0.07 m.
- Verify: `tod_tracks` still with petals visible on the Ortakoy route, and the existing Low-off check.

Extra step (optional): test alpha to coverage on the hero blossom trees only. Enable it only if the custom shader can take it. Measure the cost on desktop first and mark it as desktop data.

## 4) Risks and what not to do

- Do not switch to alpha blend for "softer" leaves. That adds sorting and fill-rate cost on the Mobile renderer.
- Do not use MSAA above 2x on iPhone. Use FXAA or alpha to coverage instead.
- Do not add a second wind system per tree. One shared vertex sway is enough.
- Do not pour thousands of tiny per-tree materials. Keep the atlas. Mobile has no automatic instancing.
- Do not turn on Self or Dependencies fades on foliage. They force transparency during the fade.
- Do not use an octahedral impostor addon without a licence check. Zero-budget rule: only CC0 or CC BY.
- Do not report frame time from the desktop capture as iPhone performance.
- Unverified risk: a `discard` shader can cost early-Z on the GPU. Measure it, do not assume.

## 5) Sources

- Godot docs, Optimizing 3D performance (instancing, alpha scissor and hash, Mobile limits, MultiMesh, transparency): https://docs.godotengine.org/en/stable/tutorials/performance/optimizing_3d_performance.html
- Godot docs, Visibility ranges (HLOD) (Begin/End, fade modes, dithering, impostors): https://docs.godotengine.org/en/stable/tutorials/3d/visibility_ranges.html
- Godot docs, 3D antialiasing (alpha scissor, alpha to coverage, MSAA limits on mobile): https://docs.godotengine.org/en/stable/tutorials/3d/3d_antialiasing.html
- Godot forum, "Simple tree foliage reduces productivity on mobile devices. What is the reason?": https://forum.godotengine.org/t/simple-tree-foliage-reduces-productivity-on-mobile-devices-what-is-the-reason/106682
- Godot forum, "Geometry vs. Alpha for detailed pine tree": https://forum.godotengine.org/t/geometry-vs-alpha-for-detailed-pine-tree/130869
- Simplygon, "How to Optimize Vegetation with Simplygon" (tight-fit impostors, overdraw claim, vendor source): https://developer.microsoft.com/en-us/games/articles/2026/01/how-to-optimize-vegetation-with-simplygon/
- Godot Octahedral Impostors addon (licence unchecked): https://github.com/SIsilicon/Godot-Octahedral-Impostors
- Three.js forum, "A forest of octahedral impostors" (LOD distances 15 to 100 and 100+, overdraw note, qualitative): https://discourse.threejs.org/t/a-forest-of-octahedral-impostors/85735

Not read: the GDC Vault (no talk found by search), ArtStation and 80.lv breakdowns of mobile racers, and any Godot GitHub issue on alpha to coverage on Mobile. These are open gaps.
