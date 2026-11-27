# Bosfor Atmaca build notes

Spec: `docs/art/CAR_ATMACA_BRIEF.md`.

Rebuild everything (Blender 5.3, deterministic):

    blender --background --factory-startup --python build_atmaca.py -- stock|modified|taxi
    blender --background --factory-startup --python render_atmaca.py -- <variant> cycles <abs outdir> front34,rear34,side,wheel 128

Outputs in `out/` (GLBs, summary_<variant>.json; the .blend files are rebuilt, not committed). Ship the stock and
taxi variants by copying their GLBs to `game/assets/vehicles/bosfor_atmaca/` and registering them with
`tools/asset_factory.py register`. Do not copy `atmaca_modified_*.glb`: since 2026-11-27 the game's modified car is a
licensed CC BY model built by `assets_src/pipeline/rebuild_vehicles.py`; the copy would overwrite it.

Method (differs from the hero body.py on purpose): a boxy car does not want the hero's smooth PCHIP loft, which
melts flat panels (see the arden_civic renders). Instead: lower body = ring sections along Y with quarter-circle
end rounding and one crease; cabin = trapezoid sections whose roof line is a rounded polyline; windows = prisms
cut out of the cabin (so every window edge is straight and the pocket reads as an interior), glass recessed 12 mm;
arches = exact boolean with cylinders; flares, bumpers, lamps, grille, wheels are bmesh builders.
LODs by bisected collapse decimation per object (LOD1 <= 12k, LOD2 <= 5k, no brakes or interior at LOD2), followed by
a degenerate-face clean (dissolve_degenerate, zero-area faces and loose vertices removed); LOD0 is cleaned too.

Measured (LOD0 / LOD1 / LOD2 triangles): stock 33.1k / 12.0k / 5.0k, modified 37.2k / 12.0k / 5.0k,
taxi 33.9k / 12.0k / 5.0k. Dimensions: stock 1.65 x 1.355 x 4.31, modified 1.77 x 1.305 x 4.31, taxi height 1.46.
Premium pass: shut lines, louvres, lamp / grille / plate pockets are exact booleans (surface found by ray casts on the
built shell, see body_cut_details and cabin_cut_details); render_atmaca.py also has `hood` and `boot` close-ups.

Known limits: LOD1 sits at its budget; one zero-area face may remain at LOD0 (text mesh); no textures (flat PBR colours), the engine adds clearcoat and metallic flakes to M_Paint at runtime.
