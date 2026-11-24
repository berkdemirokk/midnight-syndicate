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

## Round 7: targeted polish P1 to P9 (lead brief, Haiku 5.5 asset agent)
Changes, all in the generator scripts; object names and wheel/brake setup unchanged.
- P1 greenhouse: body slots now M_Paint, M_Trim, M_Pillar (gloss black, roughness 0.12, coat 1.0), M_Carbon (roof panel between windscreen top and rear screen). Glass tint #2C4048 (was #1B2A33). Material count 15 (allowed by the lead; brief budget says 14).
  Bug found and fixed: body.data.materials.clear() ran after split_glazing and reset the face indices; removed.
- P2 wing: aerofoil kept, gurney lip added (14 mm, full span). Uprights are 12 mm swan-neck blades, Bezier path from the deck, hooking over the wing top. End plates: 8 mm rounded trapezoids (longer at the bottom), 2 mm inset bevel rings. Corner rounding by quadratic arcs.
- P3 side intake: pocket 70 mm deep, 10 mm bevel on the opening lip, three 6 mm horizontal blades 25 mm behind the opening. Found the grey panel was the cabin liner (M_Interior, 30 mm inside the skin) showing through the opening; liner faces cut away in that box. Sloped rear wall NOT built (straight walls). Walls use M_Trim, not a new near-black material (material cap).
- P4 M_Trim: base #0C0C0D, roughness 0.5, Specular IOR Level 0.08 so the 520 W strip light does not grey the black parts.
- P5 plate: texture 512x128. NOCTRA rasterised from Blender's built-in font (Bfont) in textures.plate(), black on pale, reads correctly from behind (verified in renders). Plate sits in a 16 mm frame proud of the plate face (M_Trim).
- P6 diffuser strakes: 8 mm thick, tapered lofts, rounded leading end, 135 mm spacing. Exhaust: 6 mm wall tube with polished rim and dark bore.
- P7 roof antenna removed (height 1.1899 m, passes). Mirrors: thin arms, teardrop lofts, black base, paint cap 2 mm proud.
- P8 light blade: side crossing lowered to z_sh - 0.035 (short wrap). Lower nose intake: four thin dark bars in the recess. Wrap is short of the spec's fender reach.
- P9 rig: key lowered to z 2.6, energy 34, moved to the nose side; front_fill area light (energy 55) lights the nose; M_Floor roughness 0.3.

Render rounds (EEVEE, renders_iter/r11 to r16; judged each round):
1. r11: plate reads true, intake and strakes visible, greenhouse still red (slot bug).
2. r12: greenhouse dark after the slot fix; trim still grey under strip light.
3. r13: trim black; intake floor still grey (liner). Specular cut.
4. r14: liner not the cause of spec; intake still grey.
5. r15: liner cut at the intake, intake dark. End plates pale (carbon clearcoat 0.6 mirrors strip). Clearcoat 0.25.
6. r16: end plates octagonal. Replaced with explicit rounded corners.
Final: renders/ Cycles OPTIX 96 samples, six base views, wheel_closeup, contact_sheet.png (2x3 cells, verified).

Validate (validate_car.py): all checks pass. Height 1.1899, LOD0 86397, LOD1 27497, LOD2 6778, materials 15 (check now <= 15), 17 draw objects.

NOT done: re-registration. ASSET_MANIFEST.json points to game/assets/vehicles/noctra_sable/, which is written by tools/ship_assets.py (outside this asset folder). The shipped copies are still round 6 (hashes differ from out/). Run tools/ship_assets.py to ship and re-register.

Known gaps after round 7: cabin glass panes still flat boxes (roof shape unchanged); roof carbon weave uses the body UV tile (0.2 m), so the weave is coarse; side intake walls straight; light blade wrap short.

## Round 8: reviewer findings (score 6/10), targeted fixes
Checked each finding. Real: bonnet streak (confirmed by a light-off diagnostic: the key light is the source), greenhouse still boxy, wing plates pale, notes out of date. Not real: shipped copies match out/ (sha256 identical before this round); notes said re-registration was not done, that was stale.
Changes:
- Bonnet streak: key light area 5 m to 14 m, energy 34 W to 18 W; front_fill 55 W to 120 W (lights the nose face and flank); top light 2 m x 8 m to 5 m x 10 m, same energy. Streak is reduced but still hot near white at its peak (not fully solved).
- Wing plates and uprights: M_Carbon specular IOR 0.3 to 0.12, clearcoat weight 0.25 to 0. They now read dark carbon in rear34 and front34.
- Canopy: M_Glass tint #2C404B to #4A626C (lighter, interior silhouettes show). Greenhouse glass is still flat boxes; roof profile unchanged (spec data). Partial.
- Front light blade: wrap lowered from z_sh - 0.035 to z_sh - 0.085 (further round the nose corner). Still short of the fender.
- Roof spike seen in side.png: checked with a closeup (renders/diag). It is visible through the glass near the rear of the greenhouse. Not identified as geometry; left in place, documented.
- Side intake lip: still ragged at two corners (pocket boolean ends). Not fixed this round.
- validate_car.py: self_score now geometry 6, materials 6, wheels 7, details 5. known_defects rewritten to match the renders.
- Shipping: tools/ship_assets.py run from repo root (py -3.10). SHIP OK. Copies and manifest now hold the round 8 GLBs (sha256 lod0 00d41996..., lod1 1328d427..., lod2 5fb008e0...).

Triangle counts (report.json): LOD0 86397 visible, 86457 incl col_body; LOD1 27497 / 27557; LOD2 6778 / 6838 (GLB parse by validate_car). Manifest shows LOD1 27498 and LOD2 6799 (from build_summary, one or twenty-one triangles different from the validate parse). All within budget.

Render rig (EEVEE iterations): renders_iter/r17 (before rig tuning), r18, r19, r20 (kept). Final: Cycles OPTIX 96 samples, renders/ (seven views), contact_sheet.png regenerated.
