# Stage 1 notes: Noctra Sable R body (body.py)

Status: four build-render-look rounds (round 1 from the earlier pass, rounds 2-4 this pass). Not signed off.

## Probe results (Blender 5.3.0)
- Engine id BLENDER_EEVEE. Principled BSDF has Coat Weight / Coat Roughness, Emission Color / Emission Strength.
- shade_smooth_by_angle and WEIGHTED_NORMAL exist. EXACT boolean per cylinder works. bmesh.ops.bevel works.

## Checks (all pass, body.py prints them)
length 4.45, width 1.96, height 1.19, shoulders 0.772 / 0.888, bonnet 0.670. Mesh length 4.512 (+1.4%, nose and tail rings).

## Round 1 (earlier pass)
Tail flat and black; glass rectangles; A-pillar 120 mm; side glass a sliver. Only one round done.

## Round 2: glazing, tail, pillars
- Defect: A-pillar about 125 mm in x (spec formula x_g - 0.07). Fix: windscreen edge at xs-0.14, side glass outer edge at xs-0.07, so the pillar is 70 mm. Deviation from literal formula, stated intent kept.
- Defect: side glass sliver. Fix: side panes s 2.02-2.62 between x 0.42 and xs-0.07. Paint strip s 1.98-2.02 separates windscreen from side panes. Quarter (x 0.5025..) and rear (x<=0.42) split by a paint rail.
- Defect: glass read as black slabs. Fix: tint lifted from #0A0F12 to #1B2A33, alpha 0.5. Deviation.
- Defect: tail a black box. Fix: M_LightRear claws (3 per side, spec sizes), bar at z 0.80, plate block, rear fill light. Tail reads better; still a flat slab (spec-literal fascia).

## Round 3: arches
- Defect: holes through the fender top in the top view. Cause: arch cylinder started at x 0.50, but the front fender top is about 0.70 at x 0.50-0.59, below the arch crown 0.718. Fix: front arch starts at x 0.66. Rear keeps 0.50 (no breakthrough). Deviation from spec for the front only.
- Zoom render front_arch_zoom.png: no black tear visible at the lip. Lip sliver not fully verified at pixel level.

## Round 4: interior, lighting, zoom
- Defect: red inner shell seen through glass. Fix: placeholder interior (two seats, dash, M_Interior). Not a real interior.
- Defect: bonnet hot spot near white. Fix: key light 420 -> 330, top light 180 -> 120. Still bright on the bonnet.
- Clay views checked: shoulder line and fender crest read; cabin reads as a bubble.

## Known defects remaining
1. Cabin is a bubble: z_top 1.19 with n_top 3.6 is spec-literal. Needs an Art Director ruling, not a generator change.
2. Tail is a flat 0.58 m slab: z_bot rises to 0.30 at s 4.45 and the fascia is flat by spec. No ducktail lip or wing (wing is trim, later stage).
3. Paint has no flake or coat texture; the bonnet highlight still blows out.
4. Nose: wide bulb, no light blade or splitter (later stage).
5. Glass is still flat and dark from above; reflections are only the light streaks.
6. Bonnet shut line starts at s 0.22 where it collapses to one point (pwa under bonnet line, s < 0.28).
7. Contact sheet cells are not aligned to the 800x450 grid in the saved sheet (dark bands); the individual PNGs are correct.
8. Plate has no NOCTRA text yet; wheels are dummy cylinders (allowed for stage 1).
9. Groove bevel is 3-5 grid rows, not a 2-segment bevel.
