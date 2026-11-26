# Graphics rescue progress (max 30 lines)

- HEAD: c81a93b (code) on feature/vertical-slice (last pushed c191d50; no push since). Main untouched.
- Engine: Godot 4.7.2 stable, Mobile renderer. Device: Windows 11, RTX 5060 Ti 8 GB. No Mac, no iPhone test.
- Play: double-click `Oyunu_Baslat.bat` in the repo root. Career opens on the always-open "Ortakoy Night" race.
- Run the benchmark: `godot --audio-driver Dummy --path game --resolution 1920x1080 --position 20000,0 res://devtools/capture_boot.tscn -- --capture=ortakoy_benchmark [--tod=day|sunset|night]`
- Last valid state: 330 tests, 0 failed (evidence/test.log); asset manifest 638 records, 0 failing.
- Evidence (real engine captures): evidence/before.png, after_day.png, after_night.png, gameplay.png, before_after_day.png; all 15 benchmark shots in evidence/screens/ortakoy_benchmark/.
- Performance, night gameplay: 266 fps, 3.76 ms avg, 399 draws, 349k primitives; worst track shot Neon Wharf night 495 draws (budget 500). Desktop, not iPhone.

## Gates (MIDNIGHT_RESCUE/03_QUALITY_GATE.md)
- G0 baseline: done. G1 car: six licensed CC BY 4.0 cars in the game, rain beads on wet paint, credits shown in settings.
- G2 landmark: mosque with photo walls, photo far shore, Istanbul row houses with photo fronts on the whole lap. Met by the lead's eye; owner to confirm.
- G3 night: lit shop glass, pavement light pools, local reflections, spectators. Met by the lead's eye; owner to confirm.
- G4 gameplay: real race, live HUD, 320 regression tests green. G5: desktop numbers only. G6: waiting for the owner's review.

## Three open flaws
1. Cars are licensed stylised models (no real makes); house fronts are flat pictures with no relief up close.
2. Day light has no global illumination; plain side walls where rows step; plane trees still few.
3. Sea-side wall and kerb are plain; amber indicators on the licensed cars do not glow.

## Next single task
Owner review of the captures (gate G6): evidence/final_grid.png. Then car paint reflections of the street and road edge.

## Blockers
B1/B2 no Mac or iPhone; B9 unsigned exe blocked by Smart App Control; B10 Blender MCP not connected (headless scripts used);
B11 no licence-clean Ottoman house, Ortakoy mosque or bridge model found; B12 Forward+ renderer breaks the scene.
