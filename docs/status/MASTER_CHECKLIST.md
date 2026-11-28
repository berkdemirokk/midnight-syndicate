# Master completion checklist (owner's full-game scope) — final state 2026-11-28 05:35

Status: DONE (verified by a test or a harness capture tonight or earlier), PARTIAL, BLOCKED (needs the owner or a device).
Branch release/rc-2026-11-28, PR https://github.com/berkdemirokk/midnight-syndicate/pull/9. Dev PC numbers only.

| # | item | status | evidence / blocker |
|---|---|---|---|
| 1 | AAA-level graphics on the flagship Ortakoy segment | PARTIAL (much improved) | before_after_2026-11-28 sheets; still behind the references: stylised licensed cars, photo facades flat at grazing angles, no GI |
| 2 | 30 distinct premium vehicles | BLOCKED | 11 licensed CC BY cars ship and all 11 pass the race visual checks (CAR_VALIDATION_2026-11-28.md). More need the owner's yes to download licensed models, or days of modelling |
| 2b | Car draw-call budget | PARTIAL | every car is 59 objects at LOD0 vs a 20-object budget (25-27 surfaces); needs a mesh/material merge pass in assets_src/pipeline |
| 3 | Detailed Istanbul environments | PARTIAL | Ortakoy best (stone plinth, textured party walls, eaves, smooth dome); Maslak and Neon Wharf not reworked tonight |
| 4 | Career, >= 30 events | DONE (35) | test_events, test_modes |
| 5 | Sprint, circuit, time trial | DONE | events.gd, race tests |
| 6 | Drift mode | DONE | 2 events, HUD, score stars (test_modes, captures); thresholds need a playtest |
| 7 | Elimination mode | DONE | 2 events (test_modes, captures); placed after the championship |
| 8 | Police pursuit / escape | DONE (one career event) | bogaz_escape end to end (test_escape_event); chase stops at the finish; no pause after bust; flag off for other races |
| 9 | Online multiplayer with real clients | PARTIAL | LAN/loopback race verified with real processes and a rendered client on the final RC (smoke PASS; both cars finished). Not internet: no free authorised hosting |
| 10 | Private lobbies | DONE (LAN) | join code, rate limit, hello deadline, reject recovery (test_net_join, test_net_reject) |
| 11 | Competitive rankings | PARTIAL | local records screen (test_records_screen); no online ranking backend (none allowed) |
| 12 | Garage, customisation, upgrades | DONE | upgrades apply to the race car (PR #8); 88 px touch targets |
| 13 | Balanced economy | DONE (sim), playtest pending | economy_sim: everything = 1.79 full 3-star careers |
| 14 | Vehicle physics | DONE | unchanged by design |
| 15 | Intelligent opponents | PARTIAL | churn fix (stuck -42 %, teleports -61 %, unfinished 11 -> 2); overtaking not tuned |
| 16 | Traffic | DONE | TrafficSystem |
| 17 | Sound design | PARTIAL | 25 synthesised sounds; never judged by ear |
| 18 | Menus and HUD | DONE (reviewed captures) | UX + polish passes; lobby buttons small (experimental screen) |
| 19 | TR/EN localisation | DONE | 257 keys, no duplicates; TR touch labels; first-run language from the OS |
| 20 | Onboarding | DONE | first-run flow + 3 hints (test_onboarding); no real-device first launch |
| 21 | Persistent progression across restarts | DONE | restart_check.py 21/21 incl. crash during save; backup failure no longer drops a save |
| 22 | Offline play | DONE | online is opt-in |
| 23 | Mobile performance | PARTIAL | budgets met on the dev PC (night gameplay ~409 draws / 441k primitives); soak flat; no phone number (B2) |
| 24 | iOS build compiles | DONE | ios-check-5 and ios-check-6 (final RC 84bf82c, run 46098658715) green on GitHub Actions macOS; build only, no upload |
| 25 | Real-device test | BLOCKED | owner's iPhone needed (B1/B2) |
| 26 | App Store readiness | BLOCKED | device numbers, owner decisions (price, bundle id, age rating), owner-only submission |
| 27 | Race-start / periodic frame spikes | PARTIAL | 0 frames > 25 ms in the 5 s after GO in 19 runs; a ~40 s spike in some runs is unexplained (START_HITCH.md attempts 1-3) |
| 28 | No unauthorised assets | DONE | asset manifest 657 records, 0 failing; nothing downloaded tonight |
| 29 | Asphalt-style chase framing | DONE | NIGHT_DIET_2026-11-28.md |
| 30 | Regression tests | DONE | 467 tests, 0 failed at 84bf82c |
