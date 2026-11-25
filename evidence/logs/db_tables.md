
#### grid_intro / high

| category | draws peak (delta) | draws min (delta) | prims peak (delta) |
|---|---:|---:|---:|
| **BASELINE** | **500** | **294** | **476,531** |
| cars: all rivals (not player) | -184 | -92 | -207,782 |
| cars: player | -22 | -12 | -59,400 |
| car LOD LOD0 (all cars incl. player) | -70 | -36 | -144,546 |
| car LOD LOD1 (all cars incl. player) | -136 | -68 | -122,636 |
| city: road + start grid | -25 | -16 | -21,104 |
| city: ALL building geometry (FirstRow+SecondRow) | -66 | -40 | -119,828 |
| city: FirstRow buildings LOD0 | -17 | -9 | -94,530 |
| city: FirstRow buildings LOD1 | -27 | -15 | -32,170 |
| city: FirstRow buildings LOD2 | -21 | -21 | -210 |
| city: SecondRow skyline/impostor MultiMeshes | -14 | -8 | -580 |
| props: layout prop MultiMeshes (Props) | -134 | -65 | -53,567 |
| signs/neon (name contains sign|neon|billboard; overlaps props/dressing) | -121 | -58 | -49,689 |
| rain (RainFx) | -3 | -3 | -2,440 |
| speed lines (SpeedLines) | -1 | -1 | -2 |
| HUD (RaceHUD CanvasLayer) | -51 | -51 | -4,744 |
| ALL CanvasLayers + replay UI (2D off) | -53 | -53 | -4,748 |
| planar reflection: disabled (mirror pass off) | -206 | -0 | -206,556 |
| 2D only remainder (absolute, 3D off; peak includes the mirror SubViewport) | 259 | 53 | 211,304 |

No change when hidden: car LOD LOD2 (all cars incl. player); car FX (CarFx particles/smoke/sparks/flame); car lights (headlights etc, all cars); dressing props (Dressing); parked cars (ParkedCars); lights: city (Lighting, non-directional); lights: ALL Light3D in scene (incl. moon, cars, cam fill/rim); lights: camera fill/rim only; lights: moon (directional) hidden; reflection probes; overlay (pause + results CanvasLayer); env: glow off; env: sky off (background -> colour); env: fog off.

#### grid_intro / low

| category | draws peak (delta) | draws min (delta) | prims peak (delta) |
|---|---:|---:|---:|
| **BASELINE** | **291** | **291** | **267,535** |
| cars: all rivals (not player) | -92 | -92 | -118,425 |
| cars: player | -12 | -12 | -35,509 |
| car LOD LOD0 (all cars incl. player) | -36 | -36 | -83,232 |
| car LOD LOD1 (all cars incl. player) | -68 | -68 | -70,702 |
| city: road + start grid | -16 | -16 | -12,918 |
| city: ALL building geometry (FirstRow+SecondRow) | -40 | -40 | -61,248 |
| city: FirstRow buildings LOD0 | -9 | -9 | -51,026 |
| city: FirstRow buildings LOD1 | -15 | -15 | -17,354 |
| city: FirstRow buildings LOD2 | -21 | -21 | -210 |
| city: SecondRow skyline/impostor MultiMeshes | -8 | -8 | -320 |
| props: layout prop MultiMeshes (Props) | -65 | -65 | -27,025 |
| signs/neon (name contains sign|neon|billboard; overlaps props/dressing) | -58 | -58 | -24,793 |
| speed lines (SpeedLines) | -1 | -1 | -2 |
| HUD (RaceHUD CanvasLayer) | -51 | -51 | -4,744 |
| ALL CanvasLayers + replay UI (2D off) | -53 | -53 | -4,748 |
| 2D only remainder (absolute, 3D off; peak includes the mirror SubViewport) | 53 | 53 | 4,748 |

No change when hidden: car LOD LOD2 (all cars incl. player); car FX (CarFx particles/smoke/sparks/flame); car lights (headlights etc, all cars); dressing props (Dressing); parked cars (ParkedCars); lights: city (Lighting, non-directional); lights: ALL Light3D in scene (incl. moon, cars, cam fill/rim); lights: camera fill/rim only; lights: moon (directional) hidden; reflection probes; overlay (pause + results CanvasLayer); env: glow off; env: sky off (background -> colour); env: fog off.

#### grid / high

| category | draws peak (delta) | draws min (delta) | prims peak (delta) |
|---|---:|---:|---:|
| **BASELINE** | **489** | **284** | **483,344** |
| cars: all rivals (not player) | -171 | -87 | -262,327 |
| car LOD LOD0 (all cars incl. player) | -79 | -41 | -169,567 |
| car LOD LOD1 (all cars incl. player) | -92 | -46 | -92,760 |
| city: road + start grid | -25 | -16 | -21,104 |
| city: ALL building geometry (FirstRow+SecondRow) | -73 | -40 | -129,506 |
| city: FirstRow buildings LOD0 | -17 | -9 | -98,554 |
| city: FirstRow buildings LOD1 | -29 | -14 | -33,766 |
| city: FirstRow buildings LOD2 | -19 | -18 | -190 |
| city: SecondRow skyline/impostor MultiMeshes | -17 | -8 | -670 |
| props: layout prop MultiMeshes (Props) | -155 | -76 | -59,545 |
| signs/neon (name contains sign|neon|billboard; overlaps props/dressing) | -143 | -70 | -55,747 |
| rain (RainFx) | -3 | -3 | -2,440 |
| speed lines (SpeedLines) | -1 | -1 | -2 |
| HUD (RaceHUD CanvasLayer) | -51 | -51 | -4,744 |
| ALL CanvasLayers + replay UI (2D off) | -53 | -53 | -4,748 |
| planar reflection: disabled (mirror pass off) | -205 | -0 | -215,585 |
| 2D only remainder (absolute, 3D off; peak includes the mirror SubViewport) | 258 | 53 | 220,333 |

No change when hidden: cars: player; car LOD LOD2 (all cars incl. player); car FX (CarFx particles/smoke/sparks/flame); car lights (headlights etc, all cars); dressing props (Dressing); parked cars (ParkedCars); lights: city (Lighting, non-directional); lights: ALL Light3D in scene (incl. moon, cars, cam fill/rim); lights: camera fill/rim only; lights: moon (directional) hidden; reflection probes; overlay (pause + results CanvasLayer); env: glow off; env: sky off (background -> colour); env: fog off.

#### grid / low

| category | draws peak (delta) | draws min (delta) | prims peak (delta) |
|---|---:|---:|---:|
| **BASELINE** | **281** | **281** | **265,319** |
| cars: all rivals (not player) | -87 | -87 | -147,671 |
| car LOD LOD0 (all cars incl. player) | -41 | -41 | -95,283 |
| car LOD LOD1 (all cars incl. player) | -46 | -46 | -52,388 |
| city: road + start grid | -16 | -16 | -12,918 |
| city: ALL building geometry (FirstRow+SecondRow) | -40 | -40 | -66,200 |
| city: FirstRow buildings LOD0 | -9 | -9 | -53,362 |
| city: FirstRow buildings LOD1 | -14 | -14 | -16,012 |
| city: FirstRow buildings LOD2 | -18 | -18 | -180 |
| city: SecondRow skyline/impostor MultiMeshes | -8 | -8 | -320 |
| props: layout prop MultiMeshes (Props) | -76 | -76 | -30,108 |
| signs/neon (name contains sign|neon|billboard; overlaps props/dressing) | -70 | -70 | -27,956 |
| speed lines (SpeedLines) | -1 | -1 | -2 |
| HUD (RaceHUD CanvasLayer) | -51 | -51 | -4,744 |
| ALL CanvasLayers + replay UI (2D off) | -53 | -53 | -4,748 |
| 2D only remainder (absolute, 3D off; peak includes the mirror SubViewport) | 53 | 53 | 4,748 |

No change when hidden: cars: player; car LOD LOD2 (all cars incl. player); car FX (CarFx particles/smoke/sparks/flame); car lights (headlights etc, all cars); dressing props (Dressing); parked cars (ParkedCars); lights: city (Lighting, non-directional); lights: ALL Light3D in scene (incl. moon, cars, cam fill/rim); lights: camera fill/rim only; lights: moon (directional) hidden; reflection probes; overlay (pause + results CanvasLayer); env: glow off; env: sky off (background -> colour); env: fog off.

#### pack / high

| category | draws peak (delta) | draws min (delta) | prims peak (delta) |
|---|---:|---:|---:|
| **BASELINE** | **502** | **308** | **427,500** |
| cars: all rivals (not player) | -140 | -70 | -119,196 |
| cars: player | -37 | -21 | -91,550 |
| car LOD LOD0 (all cars incl. player) | -51 | -27 | -144,426 |
| car LOD LOD1 (all cars incl. player) | -68 | -34 | -47,872 |
| car LOD LOD2 (all cars incl. player) | -48 | -24 | -17,984 |
| car FX (CarFx particles/smoke/sparks/flame) | -10 | -6 | -464 |
| city: road + start grid | -38 | -30 | -52,714 |
| city: ALL building geometry (FirstRow+SecondRow) | -64 | -39 | -98,663 |
| city: FirstRow buildings LOD0 | -14 | -6 | -73,338 |
| city: FirstRow buildings LOD1 | -19 | -9 | -24,314 |
| city: FirstRow buildings LOD2 | -32 | -31 | -898 |
| city: SecondRow skyline/impostor MultiMeshes | -13 | -7 | -530 |
| props: layout prop MultiMeshes (Props) | -146 | -74 | -54,166 |
| parked cars (ParkedCars) | -6 | -3 | -3,028 |
| signs/neon (name contains sign|neon|billboard; overlaps props/dressing) | -122 | -60 | -48,677 |
| rain (RainFx) | -3 | -3 | -2,440 |
| speed lines (SpeedLines) | -1 | -1 | -2 |
| HUD (RaceHUD CanvasLayer) | -52 | -52 | -5,322 |
| ALL CanvasLayers + replay UI (2D off) | -54 | -54 | -5,326 |
| planar reflection: disabled (mirror pass off) | -194 | -0 | -185,973 |
| 2D only remainder (absolute, 3D off; peak includes the mirror SubViewport) | 248 | 54 | 191,299 |

No change when hidden: car lights (headlights etc, all cars); dressing props (Dressing); lights: city (Lighting, non-directional); lights: ALL Light3D in scene (incl. moon, cars, cam fill/rim); lights: camera fill/rim only; lights: moon (directional) hidden; reflection probes; overlay (pause + results CanvasLayer); env: glow off; env: sky off (background -> colour); env: fog off.

#### pack / medium

| category | draws peak (delta) | draws min (delta) | prims peak (delta) |
|---|---:|---:|---:|
| **BASELINE** | **309** | **309** | **240,875** |
| cars: all rivals (not player) | -70 | -70 | -69,640 |
| cars: player | -21 | -21 | -52,493 |
| car LOD LOD0 (all cars incl. player) | -27 | -27 | -81,534 |
| car LOD LOD1 (all cars incl. player) | -34 | -34 | -29,330 |
| car LOD LOD2 (all cars incl. player) | -24 | -24 | -10,917 |
| car FX (CarFx particles/smoke/sparks/flame) | -6 | -6 | -352 |
| city: road + start grid | -30 | -30 | -39,704 |
| city: ALL building geometry (FirstRow+SecondRow) | -40 | -40 | -41,739 |
| city: FirstRow buildings LOD0 | -6 | -6 | -29,442 |
| city: FirstRow buildings LOD1 | -9 | -9 | -11,486 |
| city: FirstRow buildings LOD2 | -31 | -31 | -868 |
| city: SecondRow skyline/impostor MultiMeshes | -7 | -7 | -280 |
| props: layout prop MultiMeshes (Props) | -75 | -75 | -28,414 |
| parked cars (ParkedCars) | -3 | -3 | -1,514 |
| signs/neon (name contains sign|neon|billboard; overlaps props/dressing) | -61 | -61 | -25,003 |
| rain (RainFx) | -3 | -3 | -1,708 |
| speed lines (SpeedLines) | -1 | -1 | -2 |
| HUD (RaceHUD CanvasLayer) | -52 | -52 | -5,322 |
| ALL CanvasLayers + replay UI (2D off) | -54 | -54 | -5,326 |
| 2D only remainder (absolute, 3D off; peak includes the mirror SubViewport) | 54 | 54 | 5,326 |

No change when hidden: car lights (headlights etc, all cars); dressing props (Dressing); lights: city (Lighting, non-directional); lights: ALL Light3D in scene (incl. moon, cars, cam fill/rim); lights: camera fill/rim only; lights: moon (directional) hidden; reflection probes; overlay (pause + results CanvasLayer); env: glow off; env: sky off (background -> colour); env: fog off.

#### pack / low

| category | draws peak (delta) | draws min (delta) | prims peak (delta) |
|---|---:|---:|---:|
| **BASELINE** | **306** | **306** | **239,167** |
| cars: all rivals (not player) | -70 | -70 | -69,640 |
| cars: player | -21 | -21 | -52,493 |
| car LOD LOD0 (all cars incl. player) | -27 | -27 | -81,534 |
| car LOD LOD1 (all cars incl. player) | -34 | -34 | -29,330 |
| car LOD LOD2 (all cars incl. player) | -24 | -24 | -10,917 |
| car FX (CarFx particles/smoke/sparks/flame) | -6 | -6 | -352 |
| city: road + start grid | -30 | -30 | -39,704 |
| city: ALL building geometry (FirstRow+SecondRow) | -40 | -40 | -41,739 |
| city: FirstRow buildings LOD0 | -6 | -6 | -29,442 |
| city: FirstRow buildings LOD1 | -9 | -9 | -11,486 |
| city: FirstRow buildings LOD2 | -31 | -31 | -868 |
| city: SecondRow skyline/impostor MultiMeshes | -7 | -7 | -280 |
| props: layout prop MultiMeshes (Props) | -75 | -75 | -28,414 |
| parked cars (ParkedCars) | -3 | -3 | -1,514 |
| signs/neon (name contains sign|neon|billboard; overlaps props/dressing) | -61 | -61 | -25,003 |
| speed lines (SpeedLines) | -1 | -1 | -2 |
| HUD (RaceHUD CanvasLayer) | -52 | -52 | -5,322 |
| ALL CanvasLayers + replay UI (2D off) | -54 | -54 | -5,326 |
| 2D only remainder (absolute, 3D off; peak includes the mirror SubViewport) | 54 | 54 | 5,326 |

No change when hidden: car lights (headlights etc, all cars); dressing props (Dressing); lights: city (Lighting, non-directional); lights: ALL Light3D in scene (incl. moon, cars, cam fill/rim); lights: camera fill/rim only; lights: moon (directional) hidden; reflection probes; overlay (pause + results CanvasLayer); env: glow off; env: sky off (background -> colour); env: fog off.

#### results / high

| category | draws peak (delta) | draws min (delta) | prims peak (delta) |
|---|---:|---:|---:|
| **BASELINE** | **463** | **288** | **500,809** |
| cars: all rivals (not player) | -120 | -60 | -224,058 |
| cars: player | -34 | -17 | -75,056 |
| car LOD LOD0 (all cars incl. player) | -134 | -67 | -273,092 |
| car LOD LOD1 (all cars incl. player) | -20 | -10 | -26,022 |
| city: road + start grid | -25 | -16 | -37,422 |
| city: ALL building geometry (FirstRow+SecondRow) | -87 | -53 | -111,894 |
| city: FirstRow buildings LOD0 | -14 | -6 | -73,480 |
| city: FirstRow buildings LOD1 | -31 | -15 | -37,634 |
| city: FirstRow buildings LOD2 | -32 | -27 | -320 |
| city: SecondRow skyline/impostor MultiMeshes | -10 | -5 | -460 |
| props: layout prop MultiMeshes (Props) | -106 | -51 | -43,395 |
| signs/neon (name contains sign|neon|billboard; overlaps props/dressing) | -98 | -47 | -40,163 |
| rain (RainFx) | -3 | -3 | -2,440 |
| speed lines (SpeedLines) | -1 | -1 | -2 |
| HUD (RaceHUD CanvasLayer) | -54 | -54 | -5,336 |
| overlay (pause + results CanvasLayer) | -32 | -32 | -1,204 |
| ALL CanvasLayers + replay UI (2D off) | -88 | -88 | -6,544 |
| planar reflection: disabled (mirror pass off) | -176 | -1 | -227,766 |
| env: glow off | -1 | -1 | -48 |
| env: sky off (background -> colour) | -1 | -1 | -48 |
| env: fog off | -1 | -1 | -48 |
| 2D only remainder (absolute, 3D off; peak includes the mirror SubViewport) | 262 | 87 | 234,214 |

No change when hidden: car LOD LOD2 (all cars incl. player); car FX (CarFx particles/smoke/sparks/flame); car lights (headlights etc, all cars); dressing props (Dressing); parked cars (ParkedCars); lights: city (Lighting, non-directional); lights: ALL Light3D in scene (incl. moon, cars, cam fill/rim); lights: camera fill/rim only; lights: moon (directional) hidden; reflection probes.

#### results / low

| category | draws peak (delta) | draws min (delta) | prims peak (delta) |
|---|---:|---:|---:|
| **BASELINE** | **183** | **183** | **120,946** |
| cars: player | -17 | -17 | -40,307 |
| car LOD LOD0 (all cars incl. player) | -17 | -17 | -40,307 |
| city: road + start grid | -9 | -9 | -15,008 |
| city: ALL building geometry (FirstRow+SecondRow) | -14 | -14 | -38,064 |
| city: FirstRow buildings LOD0 | -4 | -4 | -30,204 |
| city: FirstRow buildings LOD1 | -6 | -6 | -7,660 |
| city: SecondRow skyline/impostor MultiMeshes | -4 | -4 | -200 |
| props: layout prop MultiMeshes (Props) | -52 | -52 | -20,809 |
| signs/neon (name contains sign|neon|billboard; overlaps props/dressing) | -43 | -43 | -19,083 |
| speed lines (SpeedLines) | -1 | -1 | -2 |
| HUD (RaceHUD CanvasLayer) | -57 | -57 | -5,544 |
| overlay (pause + results CanvasLayer) | -32 | -32 | -1,210 |
| ALL CanvasLayers + replay UI (2D off) | -91 | -91 | -6,758 |
| env: glow off | -1 | -1 | -48 |
| env: sky off (background -> colour) | -1 | -1 | -48 |
| env: fog off | -1 | -1 | -48 |
| 2D only remainder (absolute, 3D off; peak includes the mirror SubViewport) | 90 | 90 | 6,710 |

No change when hidden: cars: all rivals (not player); car LOD LOD1 (all cars incl. player); car LOD LOD2 (all cars incl. player); car FX (CarFx particles/smoke/sparks/flame); car lights (headlights etc, all cars); city: FirstRow buildings LOD2; dressing props (Dressing); parked cars (ParkedCars); lights: city (Lighting, non-directional); lights: ALL Light3D in scene (incl. moon, cars, cam fill/rim); lights: camera fill/rim only; lights: moon (directional) hidden; reflection probes.

#### replay_orbit / high

| category | draws peak (delta) | draws min (delta) | prims peak (delta) |
|---|---:|---:|---:|
| **BASELINE** | **277** | **144** | **426,184** |
| cars: all rivals (not player) | -106 | -52 | -213,076 |
| cars: player | -42 | -21 | -78,022 |
| car LOD LOD0 (all cars incl. player) | -136 | -68 | -288,164 |
| car LOD LOD1 (all cars incl. player) | -4 | -1 | -2,166 |
| car FX (CarFx particles/smoke/sparks/flame) | -8 | -4 | -768 |
| city: road + start grid | -9 | -5 | -35,366 |
| city: ALL building geometry (FirstRow+SecondRow) | -20 | -9 | -59,630 |
| city: FirstRow buildings LOD0 | -10 | -4 | -59,150 |
| city: SecondRow skyline/impostor MultiMeshes | -10 | -5 | -480 |
| props: layout prop MultiMeshes (Props) | -86 | -43 | -37,342 |
| signs/neon (name contains sign|neon|billboard; overlaps props/dressing) | -80 | -40 | -34,334 |
| rain (RainFx) | -3 | -3 | -2,440 |
| speed lines (SpeedLines) | -1 | -1 | -2 |
| ALL CanvasLayers + replay UI (2D off) | -11 | -11 | -308 |
| planar reflection: disabled (mirror pass off) | -133 | -0 | -197,133 |
| 2D only remainder (absolute, 3D off; peak includes the mirror SubViewport) | 144 | 11 | 197,441 |

No change when hidden: car LOD LOD2 (all cars incl. player); car lights (headlights etc, all cars); city: FirstRow buildings LOD1; city: FirstRow buildings LOD2; dressing props (Dressing); parked cars (ParkedCars); lights: city (Lighting, non-directional); lights: ALL Light3D in scene (incl. moon, cars, cam fill/rim); lights: camera fill/rim only; lights: moon (directional) hidden; reflection probes; overlay (pause + results CanvasLayer); env: glow off; env: sky off (background -> colour); env: fog off.

#### replay_orbit / low

| category | draws peak (delta) | draws min (delta) | prims peak (delta) |
|---|---:|---:|---:|
| **BASELINE** | **90** | **90** | **126,329** |
| cars: player | -21 | -21 | -42,989 |
| car LOD LOD0 (all cars incl. player) | -17 | -17 | -42,605 |
| car FX (CarFx particles/smoke/sparks/flame) | -4 | -4 | -384 |
| city: road + start grid | -7 | -7 | -25,596 |
| city: ALL building geometry (FirstRow+SecondRow) | -12 | -12 | -36,192 |
| city: FirstRow buildings LOD0 | -6 | -6 | -35,932 |
| city: SecondRow skyline/impostor MultiMeshes | -6 | -6 | -260 |
| props: layout prop MultiMeshes (Props) | -39 | -39 | -21,244 |
| signs/neon (name contains sign|neon|billboard; overlaps props/dressing) | -37 | -37 | -19,600 |
| speed lines (SpeedLines) | -1 | -1 | -2 |
| ALL CanvasLayers + replay UI (2D off) | -11 | -11 | -308 |
| 2D only remainder (absolute, 3D off; peak includes the mirror SubViewport) | 11 | 11 | 308 |

No change when hidden: cars: all rivals (not player); car LOD LOD1 (all cars incl. player); car LOD LOD2 (all cars incl. player); car lights (headlights etc, all cars); city: FirstRow buildings LOD1; city: FirstRow buildings LOD2; dressing props (Dressing); parked cars (ParkedCars); lights: city (Lighting, non-directional); lights: ALL Light3D in scene (incl. moon, cars, cam fill/rim); lights: camera fill/rim only; lights: moon (directional) hidden; reflection probes; overlay (pause + results CanvasLayer); env: glow off; env: sky off (background -> colour); env: fog off.
