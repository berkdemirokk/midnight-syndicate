# Graphics rescue progress (max 30 lines)

- HEAD: 3ca478f on feature/vertical-slice (last pushed c191d50; no push since the rescue package arrived). Main untouched.
- Engine: Godot 4.7.2 stable, Mobile renderer. Device: Windows 11, RTX 5060 Ti 8 GB. No Mac, no iPhone test.
- Run the benchmark: `godot --audio-driver Dummy --path game --resolution 1920x1080 --position 20000,0 res://devtools/capture_boot.tscn -- --capture=ortakoy_benchmark [--tod=day|sunset|night]`
- Last valid state: 309 tests, 0 failed (evidence/test.log); asset manifest 534 records, 0 failing; third_party_assets.json 0 errors.
- Evidence (real engine captures): evidence/before.png, after_day.png, after_night.png, gameplay.png; all 15 benchmark shots in evidence/screens/ortakoy_benchmark/; Blender previews in evidence/car_preview/ and assets_src/third_party/vinish_cars/renders/.
- Performance, night gameplay shot (3 licensed rivals): 320 fps, 3.13 ms avg, 4.07 ms p95, 395 draws, 416k primitives; peak of all shots 431k primitives of 450k (desktop, uncapped, not iPhone).

## Gates (MIDNIGHT_RESCUE/03_QUALITY_GATE.md)
- G0 baseline: done. G1 car: six licensed CC BY 4.0 cars in the game (starter Noctra Tayfun; rivals drawn from them), credits shown in settings.
- G2 landmark: mosque, bridge and far shore recognisable by day; houses improved but still plain. Partly met.
- G3 night: local reflections, paint highlights, warm/cool balance. Met by the lead's eye; owner to confirm.
- G4 gameplay: real race, live HUD, 306 regression tests green. G5: desktop numbers only. G6: waiting for the owner's review.

## Three open flaws
1. House fronts and roofs are still simple from the road; primitive headroom is 4 %, so more geometry needs cuts elsewhere (mirror pass, LOD ranges).
2. Mosque stone is flat cream by day; amber indicators on the licensed cars do not glow; old saves keep the Sable until the free Tayfun is picked in the garage.
3. Trees are dark card clusters; no spectators; no rain beads on paint.

## Next single task
Owner review of the captures (gate G6). Then: house roofs and facade depth, or spectators, by the owner's choice.

## Blockers
B1/B2 no Mac or iPhone; B9 unsigned exe blocked by Smart App Control; B10 Blender MCP not connected (headless scripts used);
B11 no licence-clean Ottoman house, Ortakoy mosque or bridge model found; B12 Forward+ renderer breaks the scene.
