# Garage (interactive 3D)

Owner: garage agent. Code: `game/ui/garage/`, `game/world/garage/`, `game/assets/world/garage/`, `game/tests/test_garage.gd`, `game/devtools/scenarios/garage.gd`.
Room source: `assets_src/world/garage/` (not edited here). Layout, materials and lights are read from `garage_layout.json` and `materials.json` copied into `assets/world/garage/`.

## Scene (`ui/garage/garage.tscn`, root `Garage` Node3D, script `garage.gd`)
- `Room`: `garage_room.glb`. `GarageMaterials.bind` overrides each surface by material name (CC0 maps: concrete_wall_006, corrugated_iron_03, corrugated_iron, dark_wooden_planks, blue_metal_plate; pegboard texture generated). Room meshes cast no shadow.
- `Pivot` + `turntable`: the car sits on the plate (y 0.065 m), nose toward -Z (model turned 180 deg). Both rotate together.
- `Lights`: 8 omni/spot lights at the room fixture positions (2 spots on strips y0/y4, 6 omni: ceiling centre, warm tubes, neon, work lamp), no shadows, plus one soft shadowed directional key (KEY_ENERGY 2.4, near white) and one shadowless fill from the viewer side (3.0). Spots at energy 5 (8 made hot floor pools).
- `RoomProbe`: box projected, size from `reflection_probe`, UPDATE_ONCE, intensity 3.5. The default paint is metallic and reflects only the probe, so the gain is what keeps it from reading black.
- Environment: dark background, ACES tonemap, glow on (Settings preset decides enable), fog off. `Settings.attach_viewport` and `apply_to_environment` are called; the `graphics` section re-applies them.

## Camera (`garage_orbit.gd`, no nodes)
- Yaw, pitch, distance around the layout target; limits from `camera_orbit` (distance 3.2-5.4 m, pitch -2..40 deg).
- Drag (mouse or one finger) orbits with inertia; wheel or pinch zooms; double click or double tap resets to OVERVIEW.
- Presets FRONT, SIDE, REAR 3/4, OVERVIEW: 0.9 s smoothstep transitions to fixed poses.
- Idle 4 s: the turntable (car and plate) turns slowly; the camera does not.
- Keyboard and pad: steer keys orbit, accelerate and brake zoom, only when no button has focus.
- The camera looks slightly right of the car, so the car sits left of centre beside the right panel.

## HUD (`garage_hud.gd`, `garage_stats.gd`)
- Header: BACK, car name, class, hint. Cash at top right.
- Stat bars (top speed, acceleration, handling, nitro) from `GarageStats.compute(CarSpec, upgrade levels)`.
- Right panel: PAINT (12 swatches, hue and value strips, live preview, saved on release or swatch press), RIMS (6 finishes), UPGRADES (engine, tyres, nitro, weight: one row each: name, 4 level pips (filled = owned), price in `garage.money` ($ or TL), BUY). Short cash shows a wiggle and an error line.
- Tabs: only the pressed tab is cyan; hover does not look selected. Head and panel backgrounds are near opaque so the room sign does not show through the text.
- Preset buttons at bottom centre. RACE at the foot of the panel.
- Strings: `garage.*` keys in `i18n.gd` (Turkish and English).

## Save rules
- Paint and rim go through `GameState.set_paint` and `set_rim`. Upgrades go through `GameState.upgrade`. No direct file writes.
- Tests and the capture scenario swap in a temporary save path and restore the in-memory profile.

## Tests (`test_garage.gd`, 7 tests, all pass)
Scene instantiates (<= 8 omni/spot, one shadowed key plus one fill); swatch changes paint and saved setup; upgrade spends cash only when affordable; orbit stays in limits; presets reach their poses; garage strings exist in both languages and the HUD shows no raw keys; stats rise with upgrades.

## Known limits
- Paint default `#16213e` (GameState) is dark navy; the car reads as a dark hero with highlights on hood, roof and flanks. Changing the default is GameState's call, not the garage's.
- Rear 3/4 preset is now yaw 0.3 (near rear): at 0.6 the room sign was cut by the panel.
- Turntable ring and floor show a hot glossy highlight in rear and close-up views.
- Room GLB is not registered in `ASSET_MANIFEST.json` (not owned by the garage; needs the asset owner).
- Probe is captured once; repaint does not refresh car reflections in the probe.
- 7 Texture RIDs leak at exit (not fixed). Not yet traced; the garage's own textures are per-node now, so the likely source is a shared static cache in MSTheme, which the garage does not own.
