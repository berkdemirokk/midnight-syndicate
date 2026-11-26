# Bosfor Atmaca build notes

Spec: `docs/art/CAR_ATMACA_BRIEF.md`.

Rebuild everything (Blender 5.3, deterministic):

    blender --background --factory-startup --python build_atmaca.py -- stock|modified|taxi
    blender --background --factory-startup --python render_atmaca.py -- <variant> cycles <abs outdir> front34,rear34,side,wheel 128

Outputs in `out/` (GLBs, summary_<variant>.json; the .blend files are rebuilt, not committed). Ship by copying the
GLBs to `game/assets/vehicles/bosfor_atmaca/` and registering them with `tools/asset_factory.py register`.

Method (differs from the hero body.py on purpose): a boxy car does not want the hero's smooth PCHIP loft, which
melts flat panels (see the arden_civic renders). Instead: lower body = ring sections along Y with quarter-circle
end rounding and one crease; cabin = trapezoid sections whose roof line is a rounded polyline; windows = prisms
cut out of the cabin (so every window edge is straight and the pocket reads as an interior), glass recessed 12 mm;
arches = exact boolean with cylinders; flares, bumpers, lamps, grille, wheels are bmesh builders.
LODs by bisected collapse decimation per object (LOD1 <= 15k, LOD2 <= 5k, no brakes or interior at LOD2).

Measured (LOD0 / LOD1 / LOD2 triangles): stock 23.5k / 15.0k / 5.0k, modified 28.0k / 15.0k / 5.0k,
taxi 24.3k / 15.0k / 5.0k. Dimensions: stock 1.66 x 1.40 x 4.30, modified 1.77 x 1.35 x 4.30, taxi height 1.51.

Known limits: LOD1 sits at its budget (not much below), decimation leaves a few degenerate faces at LOD2
(Blender warns "mesh not valid" on export, Godot imports cleanly); the 5-spoke rim is a plain tapered spoke;
no textures (flat PBR colours), the engine adds clearcoat and metallic flakes to M_Paint at runtime.
