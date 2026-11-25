# TRAFFIC CAR — "Arden Civic" (parked and traffic sedan)

Owner: Art Director (lead). Original, unbranded four-door city sedan used for parked cars (and
later traffic). It must read as a believable everyday car from 5 m to 150 m at night, cheap enough
to draw dozens. Fictional maker name on the plate only: ARDEN. No real car's silhouette, grille,
light signature or badge.

## Pipeline
Reuse the hero car's proven surface engine: copy `assets_src/vehicles/noctra_sable/final/body.py`
into `assets_src/vehicles/arden_civic/` and replace its curve data and constants with the data
below; keep the section builder, surf(), bisect-cut glazing and arch boolean. Drop everything the
sedan does not have (wing, side intakes, diffuser strakes, light blade). Write `build_traffic.py`
(deterministic) that builds body + glass + trim + lights + 4 simple wheels, then LODs and GLBs.

## Coordinates and dimensions (metres; same conventions as CAR_01_BRIEF.md: Z up, nose -Y)
length 4.60, width 1.80, height 1.45, wheelbase 2.75 (front axle s = 0.92, rear axle s = 3.67,
Y_OFFSET = 2.295), track 1.54, tyre radius 0.32, tyre width 0.205, ground clearance 0.15.

## Curve data (s = distance from the nose, PCHIP like the hero car)
| curve | control points (s, value) |
|---|---|
| z_top | (0,0.62) (0.25,0.78) (0.92,0.86) (1.55,0.98) (2.15,1.42) (2.40,1.45) (3.10,1.44) (3.40,1.38) (3.80,1.10) (4.30,1.06) (4.50,1.05) (4.60,0.98) |
| z_bot | (0,0.30) (0.40,0.18) (1.00,0.17) (4.10,0.17) (4.45,0.24) (4.60,0.32) |
| w_max (half width) | (0,0.80) (0.30,0.88) (1.00,0.90) (4.00,0.90) (4.45,0.88) (4.60,0.86) |
| z_sh (belt) | (0,0.60) (0.30,0.74) (0.92,0.82) (1.60,0.92) (2.60,0.94) (3.60,0.96) (4.40,0.98) (4.60,0.94) |
| n_top (non-cabin) | 2.2 everywhere |
| cabin | greenhouse from s 1.55 to 3.80: shoulder shelf 0.05 m, side glass 14 degrees from vertical, roof crown 0.025 |

Windows: windscreen s 1.60-2.15, front door glass s 2.20-2.95, rear door glass s 3.00-3.55 with a
painted B-pillar (black M_Trim band) at s 2.95-3.00 and a C-pillar after 3.55; rear screen s
3.45-3.80 on the top. Use the bisect-cut approach so every window edge is straight.

## Details (cheap but present)
- Front: two horizontal lamp units (M_LightFront, emissive cool white, off by default energy 0.2),
  a dark grille band between them (M_Trim), a bumper line groove.
- Rear: two wraparound tail lamps (M_LightRear, emissive red at low energy), plate recess with
  text ARDEN, bumper groove.
- Door seams on both sides (two doors per side), door handles as small trim pads, mirrors.
- Wheels: one revolved tyre profile (24 segments) + a 5-spoke rim disc with some depth (M_Rim),
  about 300 triangles per wheel at LOD0.

## Budgets (whole car, including wheels)
LOD0 at most 7 000 triangles, LOD1 at most 2 500, LOD2 at most 800. Materials: M_Paint, M_Glass,
M_Trim, M_LightFront, M_LightRear, M_Tire, M_Rim (7). One mesh per LOD (all parts merged, material
slots kept) so a MultiMesh can draw it in one go per slot.

## Outputs
`assets_src/vehicles/arden_civic/out/arden_civic_lod0.glb, _lod1.glb, _lod2.glb` (+Y up, no
embedded textures needed), `renders/` (front34, rear34, side, top in Cycles, studio rig from the
hero car's render_car.py with an absolute output path), `report.json` (dims, tris per LOD,
materials, checks), `NOTES.md`.

## Acceptance (the lead looks at the renders)
Reads as an ordinary four-door sedan, clearly a different class from the Noctra; clean
silhouette, round arches with the tyres filling them, straight window edges, no faceting visible
at 5 m in a night render. Dimensions within 3 percent. Budgets met.
