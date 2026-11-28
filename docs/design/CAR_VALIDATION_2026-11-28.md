# Car validation 2026-11-28

Scope: the 11 catalog cars in game/vehicles/car_catalog.gd. Branch wp/cars, base 8f44660 (release/rc-2026-11-28 before the reviewfix merge).

Verdict: spec, studio visual, wheel arches, race night and race day pass for all 11 cars. The LOD0 render budget (20 objects/draw calls) fails for all 11 cars, and that fix is out of scope. LOD pops cannot be judged from still frames.

## Automated checks (game/tests/test_car_validation.gd, 4 tests, all PASS)

- Scene loads, LOD0/LOD1/LOD2 present, all required nodes present: PASS for all 11.
- Spec sanity (mass, wheel radii, track, wheelbase, body width, top speed, engine, brake, grip, display_name), and rivals >= 252 km/h track speed: PASS for all 11.
- Wheel centres at spec radius (+-0.03 m) at LOD0, so wheels touch the ground: PASS for all 11.
- LOD0 visible mesh nodes <= 20: PASS (17 each). This guards the node count only. It is not the render budget (see below). Surfaces per car are recorded as metrics: 25 to 27.
- Full headless suite on wp/cars: 461 tests, 0 failed (base 8f44660 has 457, plus these 4). The 463 on the RC commit a0155a5 includes 6 reviewfix tests that are not on this branch.

## Per-car table

Studio = car_studio_<id> scenario (front34, rear34, side, wheel_closeup, lights_on, paint_variants; Atmaca: modified_*, stock_*, taxi_*, paint_row). Race = `--capture=ortakoy_benchmark --tod=night|day --car=<id>` (car34, hero, gameplay, mosque, street shots).

| Car | Spec + wheels (test) | Studio visual | Wheels in arches | Object budget LOD0 | Race night | Race day | LOD pops | Studio PNG |
|---|---|---|---|---|---|---|---|---|
| noctra_tayfun (street) | PASS | PASS | PASS | FAIL (59 objects, 59 draw calls; empty studio 20) | PASS | PASS | not evaluable | evidence/screens/car_studio_tayfun/front34.png |
| noctra_sable (street) | PASS | PASS | PASS | FAIL (59 objects, 59 draw calls; empty studio 20) | PASS | PASS | not evaluable | evidence/screens/car_studio/front34.png |
| atmaca_modified (classic) | PASS | PASS | PASS | FAIL (59 objects, 59 draw calls; empty studio 20) | PASS | PASS | not evaluable | evidence/screens/car_studio_atmaca/modified_front34.png |
| noctra_vela (hatch) | PASS | PASS | PASS | FAIL (59 objects, 59 draw calls; empty studio 20) | PASS | PASS | not evaluable | evidence/screens/car_studio_vela/front34.png |
| arden_bruiser (muscle) | PASS | PASS | PASS | FAIL (59 objects, 59 draw calls; empty studio 20) | PASS | PASS | not evaluable | evidence/screens/car_studio_bruiser/front34.png |
| kestrel_gtr (gt) | PASS | PASS | PASS | FAIL (59 objects, 59 draw calls; empty studio 20) | PASS | PASS | not evaluable | evidence/screens/car_studio_kestrel/front34.png |
| kestrel_vanta (super) | PASS | PASS | PASS | FAIL (59 objects, 59 draw calls; empty studio 20) | PASS | PASS | not evaluable | evidence/screens/car_studio_vanta/front34.png |
| arden_havoc (muscle) | PASS | PASS | PASS | FAIL (59 objects, 59 draw calls; empty studio 20) | PASS | PASS | not evaluable | evidence/screens/car_studio_havoc/front34.png |
| kestrel_marten (sport) | PASS | PASS | PASS | FAIL (59 objects, 59 draw calls; empty studio 20) | PASS | PASS | not evaluable | evidence/screens/car_studio_marten/front34.png |
| noctra_meridian (gt) | PASS | PASS | PASS | FAIL (59 objects, 59 draw calls; empty studio 20) | PASS | PASS | not evaluable | evidence/screens/car_studio_meridian/front34.png |
| bosfor_yildirim (hyper) | PASS | PASS | PASS | FAIL (59 objects, 59 draw calls; empty studio 20) | PASS | PASS | not evaluable | evidence/screens/car_studio_yildirim/front34.png |

Studio visual PASS covers: no missing, pink or white materials; tail lamps red; brake glow in lights_on; glass not opaque black; plate readable; paint reflection sane; no floating parts. The red ring at the Atmaca modified front and rear bumpers is a tow hook, part of the model, not a floating part.

Wheels in arches: judged on side.png of each studio dir (Atmaca: modified_side.png) and on the race car34 shots.

Race PASS covers: wheels on the ground, red tail lamps, readable plate, nitro flames, no missing materials, for night and day.

## Object budget (FAIL for all 11)

- Studio perf JSON (front34.json; Atmaca modified_front34.json): objects 59 and draw_calls 59 for every car. The empty studio (empty_studio.json, every dir except Atmaca, which has none) is 20, so each car adds 39 at LOD0, about twice the 20 budget.
- Mesh surfaces at LOD0: 25 to 27 per car (test metrics). Each material surface is its own draw.
- Fix: merge meshes or materials per car (atlas the trim, lamp and interior materials). That is bigger than a small defect and is not done here.

## LOD pops

Every capture is a still frame, so a pop between frames cannot be seen. No LOD artefact shows in any race still. A moving-camera capture would be needed to judge this.

## Evidence

- Studio: evidence/screens/car_studio*/ (11 dirs, re-captured on this branch).
- Race contact sheets (11 cars, order as the table, 480 px tiles): evidence/screens/car_studio_race/race_{night,day}_{car34,hero,gameplay}.jpg.
- Race full-size PNG and perf JSON: evidence/screens/ortakoy_benchmark/bench_<tod>_<shot>_<id>.png. About 2.4 MB each (106 MB for car34 and gameplay alone), so they are not committed. Re-create them with the race command above.

## Caveats

- Studio and race checks were made on contact sheets (480 to 960 px tiles), with spot checks at full size for tayfun lights_on and the tayfun race car34 shot.
- The lod2 studio shots at 100 m are almost black in the dark studio and were not judged.
- No small defects were found, so game/vehicles/** is unchanged.

## Draw-call pass (carmerge, 2026-11-28): status and blocker

Result: the render budget is NOT met. No model was rebuilt, no material was merged, no capture was made, so there is no before/after and no visual change. The budget stays an open FAIL. The test now ratchets the surface count so it cannot grow.

Measured (existing studio perf JSON, RTX 5060 Ti, Vulkan, Mobile, 1920x1061; dev PC, not phone):

| Car | LOD0 surfaces (prepare stats) | Wheel surfaces (4 wheels) | Brake surfaces (4 discs) | Studio objects, car | Studio objects, empty | Incremental |
|---|---|---|---|---|---|---|
| noctra_tayfun | 27 | 8 | 8 | 59 | 20 | 39 |
| noctra_sable | 27 | 8 | 8 | 59 | 20 | 39 |
| atmaca_modified | 27 | 8 | 8 | 59 | 20 | 39 |
| noctra_vela | 26 | 8 | 8 | 59 | 20 | 39 |
| arden_bruiser | 25 | 8 | 8 | 59 | 20 | 39 |
| kestrel_gtr | 27 | 8 | 8 | 59 | 20 | 39 |
| kestrel_vanta | 27 | 8 | 8 | 59 | 20 | 39 |
| arden_havoc | 26 | 8 | 8 | 59 | 20 | 39 |
| kestrel_marten | 26 | 8 | 8 | 59 | 20 | 39 |
| noctra_meridian | 27 | 8 | 8 | 59 | 20 | 39 |
| bosfor_yildirim | 27 | 8 | 8 | 59 | 20 | 39 |

Source: game/assets/vehicles/<car>/<car>_prepare_stats.json (lod0.surfaces, slots_by_node), except atmaca_modified, whose stats are game/assets/vehicles/bosfor_atmaca/atmaca_modified_prepare_stats.json (27 surfaces). Studio JSON: evidence/screens/car_studio*/front34.json (atmaca: evidence/screens/car_studio_atmaca/modified_front34.json, 59 objects). car_studio_atmaca has no empty_studio.json, so its 20-object baseline is borrowed from the shared evidence/screens/car_studio/empty_studio.json (same scene, same resolution). Target was <= 20 incremental.

Why the target is not reached by a small change:
- Wheels and brakes alone are 16 of the 27 surfaces. Each wheel carries M_Rim and M_Tire, each brake carries M_BrakeDisc and M_Caliper. Keeping one surface per wheel and per brake (8 draws) would need those pairs merged into one material each.
- The pairs differ in metallic and roughness (rim: metal 0.75, anisotropic; tyre: rubber, matte, tyre picture by projection). A vertex colour cannot carry those, so a merge needs a baked or packed material per wheel. That is a visible material change and needs a before/after review.
- Even with wheels and brakes at one surface each, the body side (paint, glass, rear lamps, front lamps and lens, plate, trim, chrome, interior, underbody) has about 12 surfaces. That is 20 only if every part of that list merges as well.
- The studio gap is 39 objects but the stats name 27 surfaces. The other 12 draws are not explained by the surface list. This was not traced; it needs a draw breakdown per node before any merge is planned.

Owner decision needed: approve a material-merge pass for the car model (wheel material set per wheel with packed metal/rubber channels, brake disc and caliper as one material, body trim/chrome/underbody as one vertex-coloured material with packed roughness and metal). Estimated work: one Blender bake per car and a visual review of 4 cars. Until then the budget stays a known FAIL.

Test: game/tests/test_car_validation.gd now asserts LOD0_SURFACES_MAX per car (the current counts above). It is a ratchet, not the target. Full suite: 467 tests, 0 failed.

### Round 2 (carmerge re-review, 2026-11-28): still blocked, re-scope requested

Status: the merge pass is not delivered in this round either. No car was rebuilt, no material or mesh was merged, no Blender bake was run, and no before/after render exists. The owner decision above still stands, and the budget is still a known FAIL.

What this round did:
- Test renamed to test_every_car_lod0_nodes_and_surfaces_within_limits, because it checks both the node limit (20) and the surface ratchet. The surface check is still a ratchet on the current counts, not a budget.
- Stats path and baseline source corrected for atmaca_modified (see Source line above).
- The 12 extra studio draws are NOT traced. Hypothesis, unverified: the studio objects and draw counts (RenderingServer totals in game/devtools/perf_probe.gd) include the car's shadow-pass instances, not only its main-pass surfaces. Confirm with one GPU capture of car_studio front34 with the directional shadow turned off in a throwaway script. This needs a GPU run through the lock and was not done in this round.

Re-scope requested from the owner before any merge work:
1. Approve a material merge that changes the look: wheel rim+tyre as one surface per wheel (packed metal/rubber in one baked material), brake disc+caliper as one surface per brake, and body trim/chrome/underbody/interior merged into one vertex-coloured or atlased material.
2. Approve the Blender bake cost: about 11 bakes plus a visual review of at least 4 cars, one GPU run per studio shot.
3. Decide on the 12-draw gap first (shadow pass test above). If it is shadow-pass, the budget may be reached by reducing shadow casters on wheels and brakes, which costs no look change; this is cheaper than the material merge and should be tried first.

Sharing materials between the four wheels does not reduce draws: Godot issues one draw per surface whatever the material, so only mesh merging lowers the count.
