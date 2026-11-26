# Graphics rescue progress (max 30 lines)

- HEAD: 8041f78 (code) on feature/vertical-slice (last pushed c191d50; no push since the rescue package arrived). Main untouched.
- Engine: Godot 4.7.2 stable, Mobile renderer. Device: Windows 11, RTX 5060 Ti 8 GB. No Mac, no iPhone test.
- Play: double-click `Oyunu_Baslat.bat` in the repo root. Career opens on the always-open "Ortakoy Night" race.
- Run the benchmark: `godot --audio-driver Dummy --path game --resolution 1920x1080 --position 20000,0 res://devtools/capture_boot.tscn -- --capture=ortakoy_benchmark [--tod=day|sunset|night]`
- Last valid state: 320 tests, 0 failed (evidence/test.log); asset manifest 609 records, 0 failing; third_party_assets.json 30 sources, 0 errors.
- Evidence (real engine captures): evidence/before.png, after_day.png, after_night.png, gameplay.png, before_after_day.png; all 15 benchmark shots in evidence/screens/ortakoy_benchmark/.
- Performance, night gameplay shot (3 licensed rivals): 368 fps, 2.72 ms avg, 3.29 ms p95, 422 draws, 410k primitives; peak of all shots 421k primitives of 450k (desktop, uncapped, not iPhone).

## Gates (MIDNIGHT_RESCUE/03_QUALITY_GATE.md)
- G0 baseline: done. G1 car: six licensed CC BY 4.0 cars in the game, rain beads on wet paint, credits shown in settings.
- G2 landmark: mosque pass 3, bridge, far shore, licensed ferry. Land side: licensed shop houses with Turkish signs. Partly met (shops are generic, not Ottoman).
- G3 night: lit shop glass, pavement light pools, local reflections, spectators. Met by the lead's eye; owner to confirm.
- G4 gameplay: real race, live HUD, 320 regression tests green. G5: desktop numbers only. G6: waiting for the owner's review.

## Three open flaws
1. Shop houses are generic two-storey fronts, lower than the old row; by day their street side is in shade and reads flat. Mansions are rare.
2. Spectators are stylised faceless figures in an idle pose; plane trees are rare (their crown does not fit most spots).
3. Sea-side wall and kerb are plain; amber indicators on the licensed cars do not glow.

## Next single task
Owner review of the captures (gate G6). Then: taller Istanbul-style upper floors for the shop row, road edge, posed spectators.

## Blockers
B1/B2 no Mac or iPhone; B9 unsigned exe blocked by Smart App Control; B10 Blender MCP not connected (headless scripts used);
B11 no licence-clean Ottoman house, Ortakoy mosque or bridge model found; B12 Forward+ renderer breaks the scene.
