# Master completion checklist (owner's full-game scope, 2026-11-28 02:40)

Status words: DONE (verified tonight or earlier with evidence), PARTIAL, MISSING, BLOCKED (needs the owner or a device).
"Verified" means a test or a harness capture, named in the evidence column.

| # | item | status | evidence / blocker |
|---|---|---|---|
| 1 | AAA-level graphics on the flagship Ortakoy segment | PARTIAL | big day/night/sunset improvement (before_after_2026-11-28); not equal to the references: stylised licensed cars, flat photo rows at grazing angles, simple bridge |
| 2 | 30 distinct premium vehicles | BLOCKED | 11 licensed CC BY cars ship. More need the owner's yes to download licensed models (CLAUDE.md rule) or many days of modelling; generating low-quality cars to fill a count is ruled out by the brief |
| 3 | Detailed Istanbul environments | PARTIAL | Ortakoy/Bosphorus, Maslak, Neon Wharf tracks exist; quality gate passed only partly (Ortakoy best) |
| 4 | Career, >= 30 events | DONE | PR #8: 30 events, TR/EN names (test_events) |
| 5 | Sprint, circuit, time trial | DONE | events.gd, race tests |
| 6 | Drift mode | MISSING | next package |
| 7 | Elimination mode | MISSING | next package |
| 8 | Police pursuit / escape mode | PARTIAL | opt-in mode built and tested (15 tests, pursuit_demo captures), flag off; not in the career |
| 9 | Online multiplayer with real clients | PARTIAL | LAN/loopback: lobby, ready, countdown, sync, server results, disconnect, Bosphorus, live standings; verified with real processes and a rendered client. Not internet: no free authorised hosting exists (brief: no paid servers) |
| 10 | Private lobbies | MISSING | next package (join code) |
| 11 | Competitive rankings | PARTIAL | personal results stored (GameState.record_result); no online ranking backend (none allowed); local records screen to check |
| 12 | Garage, customisation, upgrades | DONE | garage, paint, rims, upgrades applied to the race car (PR #8) |
| 13 | Balanced economy | PARTIAL | PR #8 time-trial economy; ROADMAP step 9 rebalance not done |
| 14 | Vehicle physics | DONE | arcade model, tests; unchanged tonight by design |
| 15 | Intelligent opponents | PARTIAL | AI churn fix tonight (stuck -42 %, teleports -61 %); overtaking not tuned |
| 16 | Traffic | DONE | TrafficSystem (earlier session) |
| 17 | Sound design | PARTIAL | 25 synthesised sounds; never judged by ear |
| 18 | Menus and HUD | PARTIAL | UX package running |
| 19 | TR/EN localisation | PARTIAL | i18n exists; completeness test in the UX package |
| 20 | Onboarding | PARTIAL | hints exist; first-run flow to check |
| 21 | Persistent progression across restarts | PARTIAL | save v2, backup, PR #8 save safety; cross-process restart test to add |
| 22 | Offline play | DONE | the game needs no network; online is opt-in |
| 23 | Mobile performance | PARTIAL | budgets met on the dev PC; no phone number exists (B2) |
| 24 | iOS build compiles | IN PROGRESS | tag ios-check-5 (build only, no upload) on the RC |
| 25 | Real-device test | BLOCKED | needs the owner's iPhone (B1/B2) |
| 26 | App Store readiness | BLOCKED | needs device numbers, owner decisions (price, bundle id, age rating) and owner-only submission |
| 27 | Race-start hitch | MISSING | warm-up attempt gave no measurable gain (START_HITCH.md) |
| 28 | No unauthorised assets | DONE | asset manifest validate (657 records, 0 failing); nothing downloaded tonight |
