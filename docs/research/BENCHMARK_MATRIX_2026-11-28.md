# Benchmark matrix, 2026-11-28 (overnight)

Reference: the owner's target sheet (chat, 2026-11-27): four public gameplay frames of the big mobile racers (a
daytime chase-camera drift frame on a blossom-lined coast road, a wet neon night chase frame, a showroom line-up).
They are the quality bar, not a source: no asset, code, name or layout of those games is used. Our side is only
harness captures (`evidence/screens/...`) from the same camera type: third-person chase, HUD on, in a race.
Promotional key art is excluded on both sides. Methodology note: the installed R.E.A. and Replica skills are for
reverse-engineering apps from public material; no binary or asset of a competitor was opened (clean-room, CLAUDE.md).

Scale used: "gap" = what a player sees missing in a side-by-side of comparable frames. No numeric quality scores.

| criterion | reference frames show | our capture (path) | gap today | what this night changed |
|---|---|---|---|---|
| Vehicle realism | real licensed cars, deep clearcoat, detailed lamps, drift smoke | `ortakoy_benchmark/bench_day_car34.png`, `bench_night_gameplay.png` | large: licensed stylised low-poly models (CC BY), no real makes allowed | neutral rims, street in the day paint, tyre sheen, warm car fill/rim |
| Architectural realism | dense modelled trees, stone walls, real street depth | `bench_day_street.png`, `bench_day_hero.png` | large near the road edge (flat photo rows, bare barrier), small at 50 m+ | see arch package |
| Lighting and shadows | strong low sun, long soft shadows, warm/cool split | `bench_day_hero.png` | was large (flat noon, blue cast); now medium | ACES white 6, afternoon sun, 2-split shadows, real depth fog, warm fill |
| Asphalt and rain | dusty dry asphalt with tyre marks; wet night mirror with neon | `bench_day_gameplay.png`, `bench_night_gameplay.png` | day was blue sheen (fixed); night is close | per-hour specular, dry roughness, patchy wet mirror |
| Camera motion | low chase, wide lens at speed, drift swing | `bench_*_gameplay.png` | medium | see camera package |
| Speed sensation | speed lines, blur, FOV | gameplay captures | medium; not judgeable from stills | see camera package (nitro punch) |
| Drift satisfaction | drift counter, smoke | n/a in stills | unmeasured | telemetry package |
| Nitro response | flame, blur burst | `bench_night_gameplay_<car>.png` | medium | camera package |
| AI intelligence | n/a in stills | telemetry report | unmeasured until telemetry | telemetry package |
| Audio | n/a | synthesised sounds | unjudged by ear | none tonight |
| Menu quality | showroom line-up | `garage/*.png` | medium | none tonight |
| Progression | n/a | 30-event career (PR #8) | n/a | PR #8 merged |
| Multiplayer | online lobbies | LAN slice, disabled by default | large (no internet play) | online package |
| Mobile frame pacing | n/a | no iPhone measurement exists | unknown | none: no device |

Final before/after pairs (same camera, same preset): `evidence/screens/before_after_2026-11-28/`.
