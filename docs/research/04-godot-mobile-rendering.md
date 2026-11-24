# Godot 4.7 Mobile Rendering on iOS: Feature x Renderer Research

Date: 2026-11-24. Target: Godot 4.7.x stable, iOS, offline, night city racer.
Tags: [S] = read in the source. [E] = estimate or inference. Unknown = stated as not confirmed.
Where 4.7 docs are silent, 4.4 and 4.5 release notes are used and labelled.

## Sources

| URL | What it gave | Loaded |
|---|---|---|
| https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html | Feature x renderer table, Metal/Vulkan/D3D12/GL driver notes | yes |
| https://docs.godotengine.org/en/stable/tutorials/3d/standard_material_3d.html | StandardMaterial3D features (clearcoat, SSS, particle trails) | yes |
| https://docs.godotengine.org/en/stable/tutorials/3d/lights_and_shadows.html | Mobile light limits per mesh, shadow atlas, PSSM, filter modes, decal cluster limit | yes |
| https://docs.godotengine.org/en/stable/tutorials/3d/environment_and_post_processing.html | Glow, SSR, SSAO, SSIL, SDFGI renderer support | yes |
| https://docs.godotengine.org/en/stable/tutorials/3d/occlusion_culling.html | OccluderInstance3D, renderer differences, baking exclusions | yes |
| https://docs.godotengine.org/en/stable/tutorials/3d/particles/index.html | GPU vs CPU particles | yes |
| https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_images.html | VRAM compression, ASTC/ETC2, High Quality option | yes |
| https://docs.godotengine.org/en/stable/tutorials/physics/using_jolt_physics.html | Jolt default statement for new projects, switch path | yes |
| https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_ios.html | macOS + Xcode requirement, simulator renderer limit | yes |
| https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_ios.html | Same content, 4.7-labelled; no iOS minimum version | yes |
| https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html | glTF formats only; no extension list | yes |
| https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/index.html | Links only, no extension list | yes |
| https://godotengine.org/releases/4.7/ | 4.7 highlights: HDR on iOS, clearcoat improved, particles scale/rotation, AreaLight3D | yes |
| https://godotengine.org/releases/4.5/ | Shader baker, F16 Mobile, SMAA 1x, stencil, bent normals | yes |
| https://godotengine.org/releases/4.4/ | Metal backend (Apple Silicon only), physics interpolation 3D, Jolt experimental, ubershaders | yes |
| https://docs.godotengine.org/en/stable/tutorials/3d/3d_rendering_limits.html | 404 | no (failed) |
| https://docs.godotengine.org/en/stable/tutorials/shaders/shader_baker.html | 404 | no (failed) |
| https://docs.godotengine.org/en/stable/tutorials/physics/physics_interpolation.html | 404 | no (failed) |
| https://docs.godotengine.org/en/stable/tutorials/rendering/visibility_ranges.html | 404 | no (failed) |
| https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html | 404 (4.7 path loaded instead) | no (failed) |
| Web search: "Godot 4.7 release notes shader baker physics interpolation glTF importer" | Snippets only: 4.7.1 maintenance release exists; no glTF change listed | search only |
| Web search: "Godot 4 iOS export minimum iOS version Xcode requirement docs" | Snippets only; no official iOS minimum found | search only |

Not fetched: 4.7.2 release page (task names 4.7.2; only 4.7.1 seen in search snippet). Release note pages for 4.7 are partly read (first 100k chars of 4.5 and 4.4 pages; 4.7 page fully returned).

## Feature x Renderer

| Feature | Forward+ | Mobile | Compatibility | iOS note | Tag, source |
|---|---|---|---|---|---|
| StandardMaterial3D clearcoat | Listed | Listed | Listed (per-renderer support not stated) | 4.7 improved energy conservation and probe/sky reflections | [S] material page https://docs.godotengine.org/en/stable/tutorials/3d/standard_material_3d.html ; 4.7 improvement [S] https://godotengine.org/releases/4.7/ ; Mobile support [E] |
| Subsurface scattering | Yes | No | No | Avoid for car body | [S] https://docs.godotengine.org/en/stable/tutorials/3d/standard_material_3d.html |
| Particle trails (material) | Yes | Yes | No | Usable on Mobile | [S] same page |
| Refraction, anisotropy, detail maps | Listed | Listed | Not stated | Test on device | [E] material page lists them without renderer split |
| Reflection probes per mesh | Unlimited | 8 per mesh | 2 per mesh | Cap probe count per object | [S] https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html |
| LightmapGI (baked) | Yes | Yes | Rendering only, baking needs RD hardware | Baked GI is the cheapest mobile GI | [S] renderers page |
| VoxelGI | Yes | No | No | Not on iOS Mobile | [S] renderers page |
| SDFGI | Yes | No | No | Not on iOS Mobile | [S] renderers page |
| SSIL | Yes | No | No | None | [S] renderers page; env page https://docs.godotengine.org/en/stable/tutorials/3d/environment_and_post_processing.html |
| SSR | Yes | No | No | Fake wet road with decals/cubemaps instead | [S] env page |
| SSAO | Yes | No | Yes ("lighter" and 4.6+ not verified [E]) | Skip on Mobile | [S] env page |
| Volumetric fog | Yes | No | No | Use fake fog cards or fog | [S] renderers page |
| Non-volumetric fog | Not stated | Not stated | Not stated | Test on device | [E] env page does not state renderers |
| Decals | Yes | Yes | No | Wet puddle or light decals | [S] renderers page |
| Decal count limit | Shared 512 clustered-element default | Not stated | Not stated | Keep decal count low | [S] F+ limit https://docs.godotengine.org/en/stable/tutorials/3d/lights_and_shadows.html ; Mobile limit unknown |
| Glow / bloom | Yes | Yes | Simplified | Mobile default upscale bilinear | [S] env page and renderers page |
| MSAA 3D | Yes | Yes | Yes | Usable on Mobile | [S] renderers page |
| MSAA 2D | Yes | Yes | No | None | [S] renderers page |
| TAA | Yes | No | No | Use MSAA or SMAA | [S] renderers page |
| FXAA | Not confirmed | Not confirmed | Not confirmed | Not in docs fetched | [E] |
| SMAA 1x | Built in (4.5+) | Built in (4.5+) | Not stated | Cheap AA option | [S] https://godotengine.org/releases/4.5/ (renderer split not stated) |
| FSR2 | Yes | No | No | Not on Mobile | [S] renderers page |
| FSR1 | Not confirmed | Not confirmed | Not confirmed | Not in docs fetched | [E] |
| scaling_3d_scale | Not confirmed | Not confirmed | Not confirmed | Lower render scale is the main GPU lever | [E] page not read |
| Directional shadows | Yes | Up to 8 visible; PSSM with 4 splits default | Yes | Shared atlas, extra shadowed lights reduce resolution | [S] https://docs.godotengine.org/en/stable/tutorials/3d/lights_and_shadows.html |
| Omni/spot shadow atlas | Yes | Default allocation supports 88 shadowed lights in view (generic, not Mobile-specific) | Yes | Keep few shadowed lights | [S] lights page |
| Shadow filter | Soft Low default | Soft Low default | Soft Low default | Soft Very Low to Ultra options | [S] lights page |
| Light count per mesh | Clustered, 512 elements default | 8 Omni + 8 Spot per mesh resource; 256 + 256 visible | 8 Omni + 8 Spot per mesh (adjustable, costs perf) | Hard cap on Mobile | [S] lights page |
| Occlusion culling (OccluderInstance3D) | Helps less (depth prepass) | Largest gain (no prepass) | Not covered | Bake walls, buildings | [S] https://docs.godotengine.org/en/stable/tutorials/3d/occlusion_culling.html |
| Occlusion bake exclusions | Excludes MultiMeshInstance3D, GPUParticles3D, CPUParticles3D; CSG only if converted (4.4+) | same | same | Place manual occluders for MultiMesh | [S] occlusion page |
| MultiMesh instancing | Not confirmed | Not confirmed | Not confirmed | Use for street props; no docs read | [E] |
| Visibility ranges / HLOD | Not confirmed | Not confirmed | Not confirmed | Distance fade is "a form of LOD" [S] lights page; visibility-range page 404 | [S] lights page; rest [E] |
| Automatic mesh LOD | Not confirmed | Not confirmed | Not confirmed | Bake LODs in Blender | [E] |
| GPUParticles3D | Yes | Yes | Yes | Hardware-dependent; hundreds of thousands possible on modern GPUs | [S] https://docs.godotengine.org/en/stable/tutorials/3d/particles/index.html |
| CPUParticles3D | Yes | Yes | Yes | Wider hardware range; docs say better for older phones | [S] particles page |
| Texture: VRAM Compressed | Default | Default | Default (no High Quality option) | Mobile default is ETC2; High Quality switches to ASTC | [S] https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_images.html |
| Texture max size on mobile | Not stated | Textures above 4096x4096 may not display; use Size Limit | Same | Cap at 2048 for heavy sets | [S] importing_images page |
| Shader baker | Export option (4.5+) | Export option (4.5+) | Export option | Precompiles shaders for driver; Apple Metal case cited | [S] https://godotengine.org/releases/4.5/ ; iOS device result not confirmed [E] |
| Metal backend | Yes, Metal driver | Yes, Metal driver | No (OpenGL only) | Metal on Apple Silicon only (4.4 note) | [S] renderers page; 4.4 page https://godotengine.org/releases/4.4/ |
| Renderer fallback | F+/Mobile fall back to Compat if no Vulkan/D3D12/Metal (4.4+) | Same | n/a | Toggle-able in project settings | [S] 4.4 page |
| Physics interpolation (3D) | Yes | Yes | Yes | Added 3D in 4.4; enable in project settings | [S] https://godotengine.org/releases/4.4/ ; caveats not read [E] |
| Jolt Physics | Engine option | Engine option | n/a | 4.4 called it experimental, not default; stable Jolt doc says new projects use it | [S] https://docs.godotengine.org/en/stable/tutorials/physics/using_jolt_physics.html ; 4.4 page [S]. Conflict, verify in editor |
| HDR output | n/a | n/a | n/a | Supported on iOS in 4.7 | [S] https://godotengine.org/releases/4.7/ |
| glTF importer: KHR_materials_clearcoat | n/a | n/a | n/a | Not stated in 4.7 docs | [E] unknown; test with a sample file |
| glTF importer: KHR_materials_emissive_strength | n/a | n/a | n/a | Not stated in 4.7 docs | [E] unknown; test with a sample file |
| glTF importer: KHR_texture_transform | n/a | n/a | n/a | Not stated in 4.7 docs | [E] unknown; test with a sample file |
| iOS minimum version | n/a | n/a | n/a | Not stated in 4.7 docs | [S] negative: https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_ios.html ; value unknown |
| iOS device / architecture | n/a | n/a | n/a | Only Apple Silicon Mac host note; simulator is Compatibility only | [S] same page; device min [E] |

Export host: macOS with Xcode is required [S] https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_ios.html. Windows cannot export iOS directly [E, from that requirement].

## Recommended Mobile Presets (night racer)

All numbers are [E] starting points. Measure on a real device with the Godot profiler before locking them. Fixed limits are [S] as cited above.

| Setting | Low | Medium | High |
|---|---|---|---|
| Renderer | Mobile | Mobile | Mobile |
| 3D render scale | 0.6 to 0.75 [E] | 0.85 [E] | 1.0 [E] |
| AA | Off or SMAA [E] | SMAA [E] | MSAA 2x [E] (MSAA available on Mobile [S]) |
| Glow | On, low levels [E] | On [E] | On [E] |
| SSR / SSAO / SDFGI / VoxelGI / volumetric fog / TAA | Off (unsupported on Mobile [S]) | Off | Off |
| Directional shadow | 1 shadowed sun, 2 PSSM splits [E] | 1 sun, 4 splits [S option] | 1 sun, 4 splits [S option], Soft Medium filter [S option] |
| Shadowed omni/spot lights in view | 4 [E] (atlas holds 88 [S]) | 8 [E] | 16 [E] |
| Lights per mesh (cap) | 4 Omni + 4 Spot [E] (hard cap 8+8 [S]) | 6 + 6 [E] | 8 + 8 [S] |
| Reflection probes per mesh | 1 [E] (cap 8 [S]) | 2 to 4 [E] | 4 to 8 [E] (cap 8 [S]) |
| Decals | Off [E] | Few, wet road only [E] | Wet road and light pools [E] |
| Occlusion culling | On, bake buildings [E] (largest gain on Mobile [S]) | On [E] | On [E] |
| Particles | CPU, under 200 per emitter [E] | CPU for sparks, GPU for rain [E] | GPU rain and sparks [E] |
| Texture compression | ETC2 default [S] | ASTC via High Quality [S] | ASTC via High Quality [S] |
| Texture max size | 1024 [E] | 2048 [E] | 2048 [E] (4096 risk [S]) |
| Shader baker | On at export [E] | On [E] | On [E] |
| Physics interpolation | On [E] | On [E] | On [E] |

## Eight Findings That Drive Design

1. Mobile renderer has no SSR, SSAO, SDFGI, VoxelGI, volumetric fog, or TAA. Fake wet-road reflections and light haze must be authored [S] https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html
2. Mobile caps lights at 8 Omni + 8 Spot per mesh resource, and 256 + 256 visible in view. Night neon scenes need light budgeting [S] https://docs.godotengine.org/en/stable/tutorials/3d/lights_and_shadows.html
3. Reflection probes on Mobile cap at 8 per mesh; Compatibility at 2 [S] https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html
4. Occlusion culling gives Mobile its largest relative gain because Mobile has no depth prepass [S] https://docs.godotengine.org/en/stable/tutorials/3d/occlusion_culling.html
5. iOS Simulator runs only Compatibility, so real-device testing is required for Mobile features [S] https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_ios.html
6. The 4.7 docs give no iOS minimum version and no device list. Check the export template and preset before release [S negative] https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_ios.html
7. glTF importer support for clearcoat, emissive_strength, and texture_transform is not stated in the docs read. Assume unsupported until tested with a real export from Blender [S negative] https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html
8. Jolt is described as default for new projects in the stable docs, but 4.4 called it experimental. Verify project settings on creation [S] https://docs.godotengine.org/en/stable/tutorials/physics/using_jolt_physics.html

## Summary (6 lines)

1. Mobile renderer is the right iOS target. Forward+ features (SSR, SDFGI, VoxelGI, TAA, volumetric fog) are off there [S].
2. Light and probe caps are hard limits on Mobile: 8+8 lights and 8 probes per mesh [S].
3. Real-device testing is required: iOS Simulator is Compatibility only [S].
4. Export needs a macOS host with Xcode [S]. iOS minimum version is not in the 4.7 docs [S negative].
5. Glow, MSAA, decals, shadows (1 sun, 4 PSSM splits), and occlusion culling are available on Mobile [S].
6. Glb assets: test clearcoat and emissive in a sample file before committing to the material plan [E].

## Failed or Unreached Sources

- https://docs.godotengine.org/en/stable/tutorials/3d/3d_rendering_limits.html: 404
- https://docs.godotengine.org/en/stable/tutorials/shaders/shader_baker.html: 404
- https://docs.godotengine.org/en/stable/tutorials/physics/physics_interpolation.html: 404
- https://docs.godotengine.org/en/stable/tutorials/rendering/visibility_ranges.html: 404
- https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html: 404 (4.7 path read instead)
- Not read: scaling_3d_scale, FSR1, MultiMesh, automatic mesh LOD, HLOD, and the 4.7.2 release page.

## Verification pass

Checked 2026-11-24 by an independent fact checker. Each claim below was read in the cited page (WebFetch of the page text). Verdicts: confirmed, corrected (edited in place above), wrong (none found).

1. Mobile: 8 Omni + 8 Spot per mesh resource; 256 Omni + 256 Spot visible in camera view. Confirmed. https://docs.godotengine.org/en/stable/tutorials/3d/lights_and_shadows.html
2. Reflection probes per mesh: Forward+ unlimited, Mobile 8, Compatibility 2. Confirmed. https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html
3. Mobile lacks SSR, SSAO, SSIL, SDFGI, VoxelGI, volumetric fog, TAA. Confirmed. https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html
4. SSAO Compatibility support: "Yes" confirmed; "lighter" and "4.6+" not in the page. Corrected: row SSAO now marks them unverified [E]. https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html
5. Omni/spot shadow atlas 88 lights: the figure is the default positional allocation, not Mobile-specific. Corrected: row now says so. https://docs.godotengine.org/en/stable/tutorials/3d/lights_and_shadows.html
6. iOS Simulator supports only the Compatibility renderer. Confirmed. https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_ios.html
7. Export requires macOS with Xcode. Confirmed (no Xcode version stated). https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_ios.html
8. Jolt is the default physics engine for new projects (stable docs). Confirmed. The stable page applies "experimental" only to Jolt thread safety; 4.4 called Jolt experimental overall. https://docs.godotengine.org/en/stable/tutorials/physics/using_jolt_physics.html ; https://godotengine.org/releases/4.4/
9. Metal backend limited to Apple Silicon (4.4 release page). Confirmed. The renderers page only names Metal as a driver. https://godotengine.org/releases/4.4/ ; https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html
10. 3D physics interpolation added in 4.4, enabled in project settings. Confirmed. https://godotengine.org/releases/4.4/

Not re-verified: iOS minimum version (page silent, as stated above, still true), Metal default status (page silent), glTF importer extensions, decal limit for Mobile (lights page gives none, as stated).

Counts: checked 8 core claims (items 1, 2, 3, 6, 7, 8, 9, 10 cover them; items 4 and 5 are sub-corrections). Confirmed 8, corrected 2, wrong 0, unverifiable 0 after retag.
