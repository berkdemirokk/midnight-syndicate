# Car shading research: hero cars on phones (Godot 4.7 Mobile)

Date: 2026-11-28. Scope: how premium mobile racers shade player cars, what that means for MIDNIGHT SYNDICATE on Godot 4.7 Mobile (iOS), and a recipe. Tags: [S] = read in a source. [E] = estimate. [U] = unverified.

Honest limit: the search index gave few primary sources on how Gameloft or EA shade cars. Most car-specific numbers below come from marketplace listings and vendor docs, not from the studios. Treat studio techniques as [U] unless a talk or slide is read.

Reads done first (not repeated here): docs/art/VISUAL_TARGET.md, docs/research/04-godot-mobile-rendering.md, BENCHMARK_MATRIX_2026-11-28.md, and game/vehicles/noctra_sable/car_materials.gd. Note: `car_visual.gd` does not exist in game/vehicles/noctra_sable/ (only car_lod.gd, car_materials.gd, noctra_sable.tscn). The visual code lives in car_materials.gd.

## 1) What the best mobile racers do (sourced, quantified where possible)

### 1.1 Paint
- Layer model. Metallic paint is a base colour, flakes on top, then a clearcoat on top of that. The clearcoat reflectivity can be set on its own. [S] Autodesk VRED metallic carpaint docs: https://help.autodesk.com/cloudhelp/2015/ENU/VRED/files/GUID-E7583594-A43C-4462-A70E-058CEF9E56C0.htm
- Flakes are a randomised normal per flake, which can drive a bump map. In real time this is a tiling flake normal or noise, not geometry. [S] Maxon Flakes shader: https://help.maxon.net/r3d/houdini/en-us/Content/html/Shader+Flakes.html
- Real-time mobile car paint was done with a hybrid trick. NaturalMotion's GDC 2016 talk on CSR Racing 2 covers "car paint simulation, an HDR-like adaptation and some hybrid methods to create the illusion of dynamic specular reflections while maintaining glossy surfaces". No numbers are given in the public description. [S] session description: https://gdcvault.com/play/1022998/Delivering-Console-Car-Visuals-on (GDC 2016, Liam Murphy). Technique name not given: [U] for the exact method.
- Mobile flake paint can be one fragment pass with Fresnel colour blend, clearcoat and a noise flake. [S, community shader] https://godotshaders.com/shader/automotive-paint/
- Car Paint Pro (Unity) says it is optimised for mobile but recommends high-end PCs for its full version. [S] https://assetstore.unity.com/packages/vfx/shaders/directx-11/car-paint-pro-76361

### 1.2 Reflections
- Static image-based lighting plus a dynamic "illusion" of specular. This is the CSR2 approach (GDC 2016, see above). [S]
- Street mirror in the paint: the team already uses a second-pass shader (`res://shaders/car_reflection.gdshader`) with a panorama. This matches the hybrid approach. [S, our code: car_materials.gd `set_reflection`, lines 134 to 149]
- Reflection probes on mobile: max 8 per mesh resource; Once (default) updates on move; Always is "much slower"; shadows should stay off for Always probes. A probe centred on a car can reflect itself, so a cull mask can exclude the car. [S] https://docs.godotengine.org/en/stable/tutorials/3d/global_illumination/reflection_probes.html
- Engine note for clearcoat: in 4.7 clearcoat now has energy conservation and takes sky reflections and reflection probes into account, "a better fit for materials like car paint". [S] https://godotengine.org/releases/4.7/ (the page calls it BaseMaterial3D in the older text).

### 1.3 Lights (headlights, tail lamps)
- Emissive lamps with bloom. Unity's HDRP guide says an emissive material only feeds global illumination when the Emission checkbox is on, and emissive intensity can change at run time. [S] https://learn.unity.com/tutorial/create-and-calibrate-an-illuminated-object-using-hdrp (Unity, not Godot).
- Our code already does this: tail lamps rest at 1.4 (just above bloom threshold 1.3), brake 5.0; lens albedo smoke and a clear cover at alpha 0.1. [S, car_materials.gd lines 50 to 52, 45]
- Community note: an iridescent headlight plastic material with colour-shifting is a known look. [S] https://forums.unrealengine.com/t/community-tutorial-ue5-substrate-car-paint-and-irridescent-plastic-headlights-full-step-by-step-tutorial/2703257 (UE5, transfer only as an idea) [U] for Godot.

### 1.4 Glass and interior
- Glass gets a rim Fresnel for the edge reflection (ours: GLASS_RIM 0.9). The public sources do not give a glass recipe. [U] for studio methods.
- Transparent materials draw after opaque ones and are not written to the normal-roughness buffer. [S] Godot 3D limitations (Chinese copy read): https://docs.godotengine.org/zh-cn/4.x/tutorials/3d/3d_rendering_limitations.html . Test in the editor.

### 1.5 Polycount and textures (phones)
Marketplace listings are the only numbers found. They are not studio specs. [S listings, treat as [E]]
- Mobile-oriented car packs: LOD0 about 930 polygons (chassis 512x512 PSD, wheels 256x256) [S] https://assetstore.unity.com/packages/slug/12866 ; another pack LOD0 1,408 / LOD1 981 / LOD2 636 polygons [S] https://marketplace.unity.com/packages/3d/vehicles/land/modern-muscle-car-12871 (listing series, check page).
- PC-leaning realistic car: LOD0 55,606 tris, LOD1 33,608, LOD2 11,257. [S] https://sketchfab.com/3d-models/real-car-8-29bedf78c9784a1080625c3d72fce8ab
- Our licensed cars are stylised low poly (CC BY). Check their tri count in ASSET_MANIFEST.json before deciding LOD budgets. [U] current numbers not read here.
- Racing LOD advice: players see the rear of the car ahead most. Give the back more detail (vertex weighting). A fast-moving car can switch LOD more aggressively than a slow one. [S] https://developer.microsoft.com/en-us/games/articles/2025/12/level-of-detail-vehicle-models-simplygon/ (Simplygon, Dec 2025)

## 2) What this means in Godot 4.7 Mobile

| Topic | Fact | Source | Action |
|---|---|---|---|
| Clearcoat | 4.7 improved energy conservation, sky and probe reflections | [S] godotengine.org/releases/4.7 | Keep clearcoat on the paint (already done) |
| Probes per mesh | Mobile: 8 max | [S] reflection probes page | Keep probes per car at 1 to 2 |
| Probe update | Once is default; Always is slow | [S] same | Bake street probe once per track, not per frame |
| Self-reflection | Use cull mask | [S] same | Exclude car layer from its own probe |
| Mesh LOD threshold | Higher = less detail, faster | [S] reflection probes page | Use for probe render of distant cars |
| SSR / SSAO / SDFGI / TAA / volumetric fog | Not on Mobile | [S] 04-godot-mobile-rendering.md | Fake wet reflections with the paint pass |
| Mobile colour precision | Lower than Forward+ | [S] Godot 3D limitations, Mobile section | Watch for banding in dark paint |
| Vulkan Mobile | Matches or beats Compatibility in some benchmarks | [S] godotengine.org/releases/4.7 | Keep Mobile renderer |
| Anisotropy | Listed for Mobile in material docs | [S] 04 research file | Keep rim anisotropy 0.75 (wheel rims) |
| glTF clearcoat import | Not in 4.7 docs | [E] 04 research file | We set clearcoat in code (already done) |

Known risk: no confirmed Godot issue found for clearcoat plus anisotropy plus transparency together on Mobile. [U]

## 3) RECIPE for MIDNIGHT SYNDICATE

Each step names the file, the target and the check. Use the capture harness (device and desktop). Never claim a result that the capture did not show.

### Step 1. Paint: flake and clearcoat depth on the hero car
- File: game/vehicles/noctra_sable/car_materials.gd (PAINT_* consts, `_build` "M_Paint").
- Keep: clearcoat 1.0, clearcoat roughness 0.04, flake tiling 48, metallic 0.32, roughness 0.3 with flake map.
- Add (small): a clearcoat-only night pass so neon lamps show crisp streaks. Do not raise flake normal above 0.035 (already tuned out as sandpaper).
- Target: a crisp hot specular on roof and rear arch; no pink wash (already fixed 2026-11-28).
- Verify: capture `car_studio_<id>` (day and night) and `ortakoy_benchmark`. Look at roof and rear arch in the image. Pass only if the specular is sharp and the colour is still candy red (#8E0F1E).

### Step 2. Reflections on the body: street panorama plus one probe
- Files: car_materials.gd `set_reflection` (paint pass, strength 0.5, blur max 1.6), shaders/car_reflection.gdshader, race_scene.gd (where the panorama is set).
- Add: one ReflectionProbe per track placed on the street, mode Once, cull mask excluding the car layer, Box Projection on (small cost), shadows off. Re-bake only on track load.
- Mobile cap: max 8 probes per mesh, so keep 1 to 2 per car.
- Target: reflections change as the car moves past lamps, with no cost per frame.
- Verify: `gameplay_reel` (maslak_chase and ortakoy) frame time before and after on the named machine, plus a still of a car passing a neon sign. Mark numbers as measured on the RTX 5060 Ti desktop, not iPhone.

### Step 3. Lamps and glass: make the light do the work
- Files: car_materials.gd (REAR_REST 1.4, REAR_BRAKE 5.0, LENS_*, GLASS_*), and the front lamp material (M_LightFront, not in the read range; check).
- Add: front lamp emission about 2.0 to 3.0 at night only (bloom threshold 1.3 in our env). Keep lens cover alpha low (0.1).
- Glass: keep smoked tint alpha 0.62 and rim 0.9. Do not add a second glass pass (already cut for budget).
- Verify: night capture of two cars side by side; lamps must bloom and the glass must show a rim. Check that the dark interior is still readable.

### Step 4. LOD: budget the car by distance and speed
- File: game/vehicles/noctra_sable/car_lod.gd (194 lines; read its thresholds first).
- Targets (estimate, [E], set from the real tri count of the licensed car): LOD0 for player and near cars; LOD1 at about 60 percent tris; LOD2 at about 30 percent. Give LOD0 more detail on the rear half (Simplygon advice).
- Switch LOD more aggressively for cars passing at speed.
- Verify: count tris per LOD in the import log or with a script; capture the `gameplay_reel` with the player car and a traffic car at 30 m. The rear of the car in front must not show a pop.

### Step 5. Measure on a phone before any claim
- Use the Godot profiler on iPhone with a Release build (export needs macOS and Xcode, see 04 research file). Desktop numbers go in a separate table and must name the GPU.
- Compare three builds: current, after steps 1 to 3, after step 4. Record frame time and draw calls. Do not say "App Store ready" without a real device test (CLAUDE.md rule).
- Verify: `tests/run_tests.gd` still passes (exit 0), and the captures are the only evidence used in TEST_RESULTS.md.

## 4) Risks and what not to do
- Do not use subsurface scattering (Forward+ only) on the car body. [S] 04 research file.
- Do not use SSR or SSAO for wet reflections. Not on Mobile. [S]
- Do not put more than 8 probes on one mesh. [S]
- Do not run an Always-mode probe on the car or the track. Frame cost. [S]
- Do not raise flake normal strength for "sparkle": it reads as sandpaper at race distance (already tested in car_materials.gd comments).
- Do not raise bloom threshold to fix lamps: it lights the whole street. Lift emission on the lamp only.
- Do not copy a studio shader or asset. Clean-room: learn the layer model and numbers only.
- Do not trust marketplace polycounts as studio budgets. They are [E].
- Clearcoat on Mobile with anisotropy and transparent glass: no confirmed bug found. Test on the device, not only in the editor. [U]
- Speed feel: LOD pop at speed is more visible than low poly. Test at 200+ km/h in capture.

## 5) Sources
1. Autodesk VRED, Metallic Carpaint: https://help.autodesk.com/cloudhelp/2015/ENU/VRED/files/GUID-E7583594-A43C-4462-A70E-058CEF9E56C0.htm
2. Maxon, Flakes Shader: https://help.maxon.net/r3d/houdini/en-us/Content/html/Shader+Flakes.html
3. GDC Vault, Delivering Console Car Visuals on Mobile With CSR Racing 2 (GDC 2016, Liam Murphy): https://gdcvault.com/play/1022998/Delivering-Console-Car-Visuals-on
4. Godot docs, Reflection probes: https://docs.godotengine.org/en/stable/tutorials/3d/global_illumination/reflection_probes.html
5. Godot 4.7 release notes: https://godotengine.org/releases/4.7/
6. Godot docs, 3D rendering limitations (zh-cn copy): https://docs.godotengine.org/zh-cn/4.x/tutorials/3d/3d_rendering_limitations.html
7. Godot shaders, Automotive Paint: https://godotshaders.com/shader/automotive-paint/
8. Unity Asset Store, Car Paint Pro: https://assetstore.unity.com/packages/vfx/shaders/directx-11/car-paint-pro-76361
9. Unity Learn, Create and calibrate an illuminated object using HDRP: https://learn.unity.com/tutorial/create-and-calibrate-an-illuminated-object-using-hdrp
10. Unity Asset Store, mobile car pack (930 polygons LOD0): https://assetstore.unity.com/packages/slug/12866
11. Sketchfab, real car 8 (LOD counts): https://sketchfab.com/3d-models/real-car-8-29bedf78c9784a1080625c3d72fce8ab
12. Microsoft Game Dev, Vehicle LODs for racing games with Simplygon (Dec 2025): https://developer.microsoft.com/en-us/games/articles/2025/12/level-of-detail-vehicle-models-simplygon/
13. Gameloft, Lead vehicle artist (Asphalt 9, no numbers): https://www.en.gameloft.com/blog/players/lead-vehicle-artist
14. Unreal community, UE5 car paint and headlight tutorial (idea only): https://forums.unrealengine.com/t/community-tutorial-ue5-substrate-car-paint-and-irridescent-plastic-headlights-full-step-by-step-tutorial/2703257
15. Repo: docs/research/04-godot-mobile-rendering.md, docs/art/VISUAL_TARGET.md, game/vehicles/noctra_sable/car_materials.gd
