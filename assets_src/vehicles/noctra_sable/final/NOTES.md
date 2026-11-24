# Noctra Sable R, stage 2B: wheels, materials, export

## Built
- `build_car.py` is the entry point: body.py + details.py (stage 2A, unchanged) -> `wheels.py` -> `textures.py` -> materials wired -> UVs -> LOD0 check -> `out/noctra_sable.blend` -> LOD1/LOD2 -> three GLBs.
- Wheels: revolved tyre (64 segments, 4 grooves 9 mm x 6 mm, 22 mm shoulders, sidewall bulge, lettering in the normal and base maps). Rim: barrel with 14 mm lips, 5 twin spokes (10 concave blades, 2 mm chamfer), hub 0.150 m, centre cap, 5 lug nuts on 0.112 m. Rear rim 10% deeper. Canonical wheel is mirrored for right-hand wheels; origins at wheel centres.
- Brakes: ventilated disc (0.38 front / 0.36 rear, 30 mm, 8 mm vent gap, 36 vanes), hat, yellow caliper (0.22 m, trailing upper side). Separate objects `brake_FL..RR`.
- Positions per R4: wheel centre x 0.815 front, 0.800 rear.
- Textures (out/textures, PNG via stdlib zlib): paint_flake_normal 512, carbon_base 512, carbon_normal 512, tyre_normal 1024, tyre_base 1024, brake_roughness 512, brake_normal 512, lens_normal 256, plate_base 512x128.
- Plate: the geometry letters from 2A were removed; the text now lives in the M_Plate texture (reads NOCTRA from behind).

## Triangles (visible objects, col_body excluded)
- LOD0 84 189 (45k-90k), LOD1 27 498 (<=28k), LOD2 6 776 (<=7k; interior and brakes dropped).
- Objects at LOD0: 17 draw objects (limit 20). Materials used: 14 (limit 14).
- GLB sizes: LOD0 7.48 MB, LOD1 4.94 MB, LOD2 3.68 MB.

## Render rounds (build -> render -> look -> fix)
1. EEVEE first look. Paint flake invisible at render scale; rims read as black; tyre lettering faint; closeup showed the spoke and disc depth. Fix: flake tile 0.06 -> 0.20 m, stronger flakes; rim colour lighter; tyre base colour added for the lettering.
2. Flake now too strong (sandpaper look in the closeup). Lettering reads backwards on the canonical (left, +X) tyres. Fix: flake strength 0.30 -> 0.12; U flipped on canonical wheels.
3. After the flip the lettering moved out of frame. Fix: start U moved to 0.56 so it lands at 0.14-0.44 on the outboard face. Closeup camera raised to show tread grooves.
4. Lettering reads correctly on all tyres; the closeup camera was behind the fender. Fix: camera moved to (2.7, -3.3, 0.85).
5. Closeup shows spoke depth, disc, yellow caliper, tyre grooves and sidewall lettering. Accepted. Final Cycles renders.

## Final renders
- renders/: Cycles, OPTIX GPU (RTX 5060 Ti), 96 samples, denoise, 1600x900. The six views plus rear_low and wheel_closeup. contact_sheet.png 2400x1350 (2x3, 800x450 cells).
- renders_iter/r1..r5: EEVEE iteration rounds (48 samples).

## Known defects (still visible; the lead should judge)
- Cabin is still tall and bubble-like (2A, R3 applied only in the numbers).
- Front light blade stops at the shoulder; does not wrap the nose corner (2A).
- Side intake pocket floor and slats read as flat mid grey under the strip light (2A rig question).
- Carbon weave on the wing and uprights is not inspected at close range.
- Wing uprights and end plates read as blocks; brake ducts are angular notches (2A).
- Antenna fin on the roof tops out at 1.2435 m; the body alone is 1.19 m. The height check fails at 1.2286 m (+3.2%). Not fixed: it is 2A trim and removing it would change 2A's work.
- col_body is exported as a 33-vertex mesh. It is hidden only in renders; the engine must skip it.
- Rear wheels sit about 22 mm inside the body width; front about 8 mm inside the fender lip at hub height.
- Track widths are 1.63 / 1.60 m against 1.66 / 1.64 (within 3%: 1.8% and 2.4%).
- Tyre widths measure 0.252 / 0.310 against 0.255 / 0.315 (within tolerance).

## Next fixes
- Rework the cabin greenhouse (the bubble) and the nose blade wrap.
- Lift the side intake floor so it reads as a dark recess, not a grey panel.
- Give the wing uprights a proper section.

## Files
- build_car.py, body.py, details.py (2A), wheels.py, textures.py, render_car.py, validate_car.py, report.json.
- Registered in the asset factory: noctra_sable_lod0 / lod1 / lod2 (model, generated:blender, project-owned, pass).

## Round 6: reviewer findings (independent review scored 4/5/7/3)
Checked each finding against renders. All real. Changes:
- Height 1.2286 (+3.2%, fail): roof fin rebuilt as a low rounded dome (top 8 mm above roof). Height now 1.1899. validate_car: all checks pass.
- Antenna, wing end plates, wing uprights, mirror arms: boxes replaced by lofts (add_loft, ell_ring). End plates squircle.
- Dark wedges at nose corners: cause was the brake-duct pocket (p_brake) cut at x 0.6..0.8. Removed. Splitter end boxes removed, splitter span 0.80 m.
- Light blade: now wraps the nose corner from the notch (x 0.16 on top) down to 0.10 m below the shoulder (light_band, v_grid).
- Interior: seats, seat backs, headrests, dash top are rounded (add_ell), not boxes.
- Glass alpha 0.5 -> 0.35 (brief value).
- Diffuser strakes 12 -> 22 mm wide.
- col_body: extras collision_only=1, export_extras on. Engine must skip by that flag or by name.
- Report: tris_incl_col_body added (GLB totals). LOD0 visible 86821 vs 86883 incl col.
- Rig: key 200->55, top 70->14, strip 900->520. Bonnet highlight STILL a hot streak. Lowering each light alone did not remove it. Not solved.

Not fixed / still open:
- Cabin still a tall bubble (spec roof data unchanged). Major, not solved.
- Tail: flat fascia, ducktail lip weak.
- Side intake floor still grey.
- Floor glare at frame left.
- Stage 2A closeups (cabin, tail, nose, intake) not regenerated.

## Files this round
- build_car.py (brake pocket removed, export_extras), details.py (lofts, light wrap, interior, fin), body.py (rig, glass), validate_car.py (report fields, honest scores).
- Renders: renders/ Cycles OPTIX 96 samples. Iteration: renders_iter/r6 to r10 (EEVEE).
- Manifest entries noctra_sable_lod0/1/2 updated (sha256, bytes, tris visible).
