# Garage room (Environment Agent)

Source: `build_garage.py`. Deterministic. Blender 5.3, metres, Z-up in Blender, glTF export converts to Y-up.

Run (build + renders):
`"C:\Program Files\Blender Foundation\Blender 5.3\blender.exe" --background --factory-startup --python assets_src/world/garage/build_garage.py -- all --samples 96`
Modes: `build` (GLB, json, report, pegboard png), `render` (6 PNGs), `all`. Optional `--only wide,turntable`.

## Layout
- Room X[-8,8] Y[-6,6] Z[0,4.6]. Turntable centre at origin, radius 2.45 m. Car nose toward -Y.
- Roll-up door on the back wall (y = -6): 19 slats raised to z 2.0, opening 0 to 2.0 m shows the ramp outside (ramp runs out and down to z -3).
- Front wall (y = +6) carries the "BAY 01" stencil. Right wall (x = +8) carries "NOCTRA" over the workbench end. Left wall carries the tool chest, shelf, lift and cable run.
- Dressing kept to |x| > 5.8 so the centre stays clear. Columns at x +/-7.5, y -5.4 / 0 / 5.4 (keep the camera out of them).

## Outputs (out/)
- `garage_room.glb`: 305 mesh objects, about 31 400 triangles (budget 60 000), 16 material slots (budget 16). No embedded images. Every primitive has TEXCOORD_0 (world-metre projection).
- `materials.json`: slot name, CC0 texture id (or null), generated texture (pegboard), linear base colour, roughness, metallic, emission colour and strength, UV tiling in metres.
- `textures/pegboard_holes.png`: project-owned 512 x 512 generated texture, bound to `M_Pegboard_Tan` (0.5 m tile).
- `garage_layout.json`: Godot coordinates (`godot = (bx, bz, -by)`). 12 light fixtures (strips, warm tubes, neon sign, work lamp), reflection probe, turntable centre and radius, camera orbit limits.
- `report.json`: counts, GLB checks (images 0, textures 0), primitives without UV (0), exported bounds.
- `renders/`: wide, turntable (grey stand-in block only, render-only, not exported), back_wall, dressing_left, dressing_right, ceiling_lights. 1600x900, Cycles OPTIX, 96 samples, denoised.

## Lighting
- Renders use only the GLB emissive fixtures. There are no render-only fill lights. The fixture emission is set in `MATS` (`M_Light_Emit` 20, `M_Warm_Emit` 8, neon 9 and 7), and the same values are in materials.json.
- The engine still needs its own bloom to make the strips glow. The renders show the strips without a bloom pass.

## Engine notes
- UVs are world metres (box projection). Engine should repeat by `1 / uv_tiling_m` from materials.json.
- `floor-colonly` is a slab whose top sits 2 mm below the visible floor. Use it for collision only; it is still exported.
- `turntable` has two material slots: steel base ring (index 0) and dark plate (index 1). Its origin is the rotation axis.
- Maps are bound by name by the engine. The GLB carries flat colours only.

## Known gaps
- The floor is a flat polished epoxy (no CC0 map). The earlier concrete map showed joints and pebbling, so it was dropped.
- The ramp outside the door is dark. It reads as a sloped surface with a yellow lip, lit only by the room. It is not lit from outside.
- The pegboard holes are visible in close views only; at room scale the board reads as a tan panel with tool silhouettes.
- Stand-in car in turntable.png is a grey block for scale only.
