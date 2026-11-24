# Recon map: MIDNIGHT SYNDICATE genre study (arcade street racer, iOS first, offline)

Scope: core loop of a single-player arcade street racer: career map, race events, garage, tuning, cosmetic customization, police pursuit, results and rewards.
For: internal design of an original game. Date: 2026-11-24. Clean-room: patterns and rules only, nothing copied from any reference.
References studied: Need for Speed No Limits (NFSNL), Asphalt 9 / Asphalt Legends (A9), CSR Racing 2 (CSR2), CarX Street (CarX), Need for Speed Underground 2 (NFSU2).
Tags: [S] = read in a source, [E] = estimate or inference. Every reference fact carries its URL on the same line. Unknowns are listed in section "Gaps".

## Sources

| # | source | URL | status |
| --- | --- | --- | --- |
| 1 | NFSNL wiki | https://en.wikipedia.org/wiki/Need_for_Speed:_No_Limits | [S] read |
| 2 | NFSNL review | https://www.pocketgamer.com/need-for-speed-no-limits/review/ | [S] read |
| 3 | A9 wiki | https://en.wikipedia.org/wiki/Asphalt_9:_Legends | [S] read |
| 4 | A9 TouchDrive critique | https://www.pocketgamer.com/articles/076788/r/ | [S] read |
| 5 | CSR2 GDC 2016 abstract | https://gdcvault.com/play/1022998/Delivering-Console-Car-Visuals-on | [S] abstract only |
| 6 | CSR2 development | https://www.pocketgamer.biz/the-making-of-csr-racing-2/ | [S] read |
| 7 | CSR2 start and shifts | https://www.pocketgamer.com/csr-racing-2/how-to-accelerate-and-change-gears-optimally-in-csr-racing-2 | [S] read |
| 8 | CSR2 tuning | https://www.pocketgamer.com/csr-racing-2/how-to-tune-your-car-in-csr-racing-2-tires-nitro-and-final-drive | [S] read |
| 9 | CSR2 monetisation (2016) | https://www.pocketgamer.biz/how-does-csr-racing-2-monetise/ | [S] read, 2016 data |
| 10 | CarX App Store listing | https://apps.apple.com/app/id1458863319 | [S] read |
| 11 | CarX Steam listing | https://store.steampowered.com/app/1114150/CarX_Street/ | [S] read |
| 12 | CarX iOS review (2022) | https://traxion.gg/carx-street-review-ios-leads-the-way-for-carxs-move-to-open-world/ | [S] read |
| 13 | CarX review | https://www.thexboxhub.com/carx-street-review/ | [S] read |
| 14 | CarX complaints tally | https://www.sikayetvar.com/en/carx-street-us | [S] read, rough count |
| 15 | NFSU2 wiki | https://en.wikipedia.org/wiki/Need_for_Speed:_Underground_2 | [S] read |
| 16 | NFSU2 market context | https://www.thedrive.com/news/need-for-speed-underground-changed-racing-games-20-years-ago.md | [S] partial |

Failed, not retried: GameSpot CSR2 (HTTP 403), Gamezebo NFSNL and A9 (HTTP 403), NFSU2 fandom wiki (HTTP 402), TweakTown NFSU2 (HTTP 403). No Reddit thread was reachable.

## Core loop

[E] Pick a race on a stage map, win it by drift and nitro skill, spend the reward on a performance part or paint, and unlock the next stage. Basis: stage map [S https://en.wikipedia.org/wiki/Need_for_Speed:_Underground_2] and blueprint unlocks [S https://en.wikipedia.org/wiki/Asphalt_9:_Legends].

## Screens

Target screens are our design [E]. "Basis" gives the reference that shows the pattern. Target has 15 rows: the 13 requested, with tuning split out of Garage and Map split from Race select.

| ID | screen | route / how reached | purpose | key components | states to build | basis |
| --- | --- | --- | --- | --- | --- | --- |
| S01 | Main menu | app launch | enter Play, Garage, Map, Store, Settings | career tile, currency chip, car preview | first launch, returning, save unreadable | [S https://en.wikipedia.org/wiki/Need_for_Speed:_No_Limits] menu hub |
| S02 | Garage | menu tab | list owned cars, set active car | car carousel, stat card (power, grip, weight), class badge | empty (starter only), filled, locked car | [S https://en.wikipedia.org/wiki/Asphalt_9:_Legends] starter car class D |
| S03 | Car select (event) | from S08 or S09 | pick a car that fits event rules | filtered car cards, rule badge, lock icon | rule-blocked car, locked car | [S https://en.wikipedia.org/wiki/Need_for_Speed:_No_Limits] car series entry limits |
| S04 | Customization | Garage > car > Paint | visual change only, no handling effect | swatches, wheel and body-kit picker, wrap, turntable preview | owned part, locked part, event-only car | [S https://en.wikipedia.org/wiki/Need_for_Speed:_Underground_2] cosmetics have no effect; [S https://en.wikipedia.org/wiki/Need_for_Speed:_No_Limits] event-only cars cannot be visually customized |
| S05 | Upgrade | Garage > car > Upgrade | buy and level performance parts per slot | slot grid (engine, tyres, brakes, nitro, drivetrain), stat delta preview | slot locked, maxed, funds short | [S https://www.pocketgamer.com/need-for-speed-no-limits/review/] upgrades are bolt-ons |
| S06 | Tuning and dyno | Garage > car > Tune | set nitro, final drive, tyre pressure | sliders with live delta, dyno graph, wheelspin icon | default, custom, edited since last race | [S https://www.pocketgamer.com/csr-racing-2/how-to-tune-your-car-in-csr-racing-2-tires-nitro-and-final-drive] sliders with stat indicator |
| S07 | Career map | menu > Map | show five stages and event pins | pins, stage banner, boss node, hidden-race marker | stage locked, pin done, boss ready | [S https://en.wikipedia.org/wiki/Need_for_Speed:_Underground_2] five stages with world map |
| S08 | Race select (event card) | tap a pin | show event type, laps, car cap, nitro rule, reward, level gate | event card, level banner, reward preview, best time | locked by level, available, completed | [S https://en.wikipedia.org/wiki/Need_for_Speed:_Underground_2] mode rule sets |
| S09 | Pre-race | after S08 | confirm car, read controls, run countdown | countdown lights, start gauge, ghost toggle | car rule violation, under-level warning | [S https://www.pocketgamer.com/csr-racing-2/how-to-accelerate-and-change-gears-optimally-in-csr-racing-2] start gauge |
| S10 | Race HUD | race start | steer, drift, nitro, read position and laps | nitro meter with perfect window, drift charge bar, speed, position, lap or checkpoint, minimap | normal, drifting, nitro active, wall hit, police nearby, final lap | [S https://www.pocketgamer.com/need-for-speed-no-limits/review/] swipe controls; [S https://www.pocketgamer.com/articles/076788/r/] tilt trap |
| S11 | Pause | HUD pause button | resume, restart, settings, quit | three buttons, quit confirm | confirm quit open | [E] standard |
| S12 | Results | race end | show place, time, reward, unlock | podium, reward list, next-event button, retry | win, lose, new unlock, part reward | [S https://en.wikipedia.org/wiki/Need_for_Speed:_No_Limits] visible reward per race is a pattern [E] |
| S13 | Pursuit HUD | police triggered in a pursuit event | show heat level, escape progress, police distance | heat meter, escape bar, police marker, roadblock marker | pursuit start, escaping, busted, escaped | [S https://www.pocketgamer.com/need-for-speed-no-limits/review/] police ramp behaviour |
| S14 | Store | menu > Store | optional cosmetic or currency bundles | bundle tiles, price, restore purchases | empty, item owned, store offline | [S https://apps.apple.com/app/id1458863319] CarX IAP range; [S https://www.pocketgamer.biz/how-does-csr-racing-2-monetise/] bundle tiers |
| S15 | Settings | menu > Settings | steering mode, assist, camera, quality tier, frame cap | toggles, segmented control, quality tier picker | tilt unavailable, low-power mode on | [S https://www.pocketgamer.com/articles/076788/r/] tilt needs smoothing; [S https://apps.apple.com/app/id1458863319] heat and frame reports |

## Flows

Taps are happy-path counts [E]. Each flow is our target; clicks are the number to beat.

```
F01 First launch to first race
    S01 -> S07 -> S08 -> S09 -> S10 -> S12 -> S07
    happy path taps: 5 (Play, pin, Start, Go, Continue)
    edge: starter car forced, tutorial can be skipped, no network needed

F02 Start a race from the map
    S07 -> S08 -> S09 -> S10
    happy path taps: 3 (pin, Start, Go)
    edge: event locked by level (show gate), car rule blocks (swap car in S03)

F03 Buy and fit a performance part
    S01 -> S02 -> S05 -> slot -> Buy -> Confirm
    happy path taps: 5
    edge: insufficient funds (show earn route), part not for this car class

F04 Paint a car
    S01 -> S02 -> S04 -> swatch -> Back
    happy path taps: 4
    edge: event-only car cannot be painted, show lock reason

F05 Tune for an event
    S02 -> S06 -> drag slider -> test drive -> Save
    happy path taps: 4 plus one drag
    edge: tune changes after an event start are not applied to that race

F06 Drift, charge, fire nitro (in race)
    S10: swipe down to drift, hold drift, swipe up to fire nitro
    happy path taps: 0 menu taps; 2 gestures per boost
    edge: nitro banned in drift and Street X style rules (rule flag)

F07 Pursuit and escape
    S10 -> S13 -> escape bar full -> S12
    happy path taps: 0 extra
    edge: busted -> S12 with penalty; roadblock blocks the route

F08 Earn or buy a car
    earn: S12 unlock notice -> S02 (2 taps); buy: S14 -> car -> Buy -> Confirm (4 taps)
    edge: store offline shows cached prices or hides the bundle

F09 Change steering assist
    S01 -> S15 -> steering mode -> Back
    happy path taps: 3
    edge: tilt needs a calibration tap, otherwise falls back to tap steering

F10 Pause and quit
    S10 -> S11 -> Quit -> Confirm -> S07
    happy path taps: 3
    edge: quit mid-pursuit keeps the event open for retry (decision open)

F11 Unlock the next stage
    S12 (last event of stage) -> S07 stage banner -> Continue
    happy path taps: 2
    edge: boss needs a minimum car rating; show it before the race

F12 Cold open with no network
    S01 loads from local save with no login, no connect screen
    happy path taps: 0
    edge: save fails checksum -> offer restore from backup slot, else new career
```

## Components

| component | variants | states | used on |
| --- | --- | --- | --- |
| Button | primary, secondary, ghost, danger | default, pressed, disabled, loading | S01 to S15 |
| Car card | compact, full, locked | default, selected, locked, rule-blocked | S02, S03, S14 |
| Stat bar | single, delta | value, positive delta, negative delta | S02, S05, S06 |
| Slider with delta | horizontal | default, dragging, at limit | S06 |
| Dyno graph | power, torque | default, updating | S06 |
| Stage map pin | event, boss, hidden, cash-info | locked, available, done | S07 |
| Event card | race, drift, sprint, circuit, drag, pursuit | locked, available, completed | S08 |
| Countdown and start gauge | lights, two-zone dial | waiting, orange, green, stall | S09 |
| Nitro meter | three tiers, perfect window | empty, charging, ready, active | S10 |
| Drift charge bar | single | idle, charging, capped | S10 |
| Heat meter | pursuit levels | none, rising, max, escape | S13 |
| Modal confirm and currency chip | danger, neutral; cash, premium | open, low, animating | S01, S05, S11, S14 |

## Inferred data model

Confidence: high = shown in a source; medium = pattern in several sources; guess = our design.

```
Car          id, class (D..S), power, grip, weight, handling, rating, series_tag,
             visual_slots[], event_only (bool)
             evidence: class ladder [S https://en.wikipedia.org/wiki/Asphalt_9:_Legends];
                       event-only cars not customizable [S https://en.wikipedia.org/wiki/Need_for_Speed:_No_Limits]
             confidence: class high; stat fields medium

Part         id, slot (engine, tyres, brakes, nitro, drivetrain, body, wheel, paint),
             tier, stat_delta{}, visual_only (bool), price_cash
             evidence: cosmetics separate from performance [S https://en.wikipedia.org/wiki/Need_for_Speed:_Underground_2]
             confidence: medium

CarPart      car_id, slot, part_id, level
             evidence: bolt-on upgrades [S https://www.pocketgamer.com/need-for-speed-no-limits/review/]
             confidence: guess (shape)

TuneSetting  car_id, nitro_slider, final_drive, tyre_pressure (0..1 each)
             evidence: sliders trade burst vs power, acceleration vs top speed [S https://www.pocketgamer.com/csr-racing-2/how-to-tune-your-car-in-csr-racing-2-tires-nitro-and-final-drive]
             confidence: high (trade-off), guess (ranges)

Event        id, stage_id, type (circuit, sprint, drag, drift, outrun, pursuit, rival),
             laps, car_cap, nitro_allowed, shift_mode (auto or manual), level_req, reward, best_time
             evidence: mode rule sets [S https://en.wikipedia.org/wiki/Need_for_Speed:_Underground_2]
             confidence: high (types), medium (fields)

Stage        id, order, event_ids[], unlock_rule
             evidence: five stages, 11 sponsor races per stage, 3 run [S https://en.wikipedia.org/wiki/Need_for_Speed:_Underground_2]
             confidence: high

Rival        id, event_id, ghost_ref (saved run), car_id, tier
             evidence: ghost-based rival races [S https://en.wikipedia.org/wiki/Need_for_Speed:_No_Limits]
             confidence: high

Wallet       cash, premium
             evidence: CSR2 used three currencies (cash, gold, keys) [S https://www.pocketgamer.biz/how-does-csr-racing-2-monetise/]
             confidence: high for existence; our choice of two currencies is [E]

SaveGame     version, wallet, owned_cars[], parts[], tunes[], stage_progress,
             best_times, rival_ghosts[], settings, checksum
             evidence: offline requirement [E; CarX needs a stable connection, S https://apps.apple.com/app/id1458863319]
             confidence: guess
```

Relationships: Stage 1-n Event; Event n-n Car (filtered by car_cap and series_tag); Car 1-n CarPart; CarPart n-1 Part; Car 1-1 TuneSetting; Event 1-1 Rival (optional); Wallet 1-1 SaveGame.

## What cannot be cloned (or should not be)

- Licensed cars, makes and models, badges, liveries, and tuner brand logos [S https://en.wikipedia.org/wiki/Need_for_Speed:_Underground_2 for the fictional-city and franchise context; legal status [E]].
- Licensed music and any real artist recording, including the NFSU2 soundtrack [S https://worthplaying.com/article/2004/10/28/news/20203-need-for-speed-underground-2-gbangcps2xboxpc-soundtrack/].
- Real city layouts and landmarks. NFSU2's city is fictional but based on real cities [S https://en.wikipedia.org/wiki/Need_for_Speed:_Underground_2]; ours must be original [E].
- Online ranked play, matchmaking, team pursuit, crews and live events. Reference complaints about these exist, but they need servers [E; Asphalt Unite review https://gamingbolt.com/asphalt-legends-unite-review-united-we-fall, search excerpt only].
- Random-price tests and gacha keys with opaque odds. CSR2 apologised for a per-player price test [E; https://www.mcvuk.com, snippet only]. We do not build them [E].
- Proprietary physics and asset pipelines (CarX Technology claim, CSR2 shader and car-model work). We build our own physics and assets [S claim https://store.steampowered.com/app/1114150/CarX_Street/, not verified].
- Reference UI layouts, icons, copy and HUD art. We copy patterns only [E].

## Gaps (not verified)

- Chase camera, FOV, shake, takedown cams, HUD and garage layout (A9, NFSNL): not found in any opened source [gap]. CSR2 monetisation data is 2016 only [S https://www.pocketgamer.biz/how-does-csr-racing-2-monetise/].
- Rival AI behaviour and rubber-banding: not verified for any reference, except that CarX rivals ram near the finish [S https://www.thexboxhub.com/carx-street-review/].

## Design rules drawn from the references

- Assist on by default with a manual toggle. Tilt steering only with heavy smoothing [S https://www.pocketgamer.com/articles/076788/r/].
- Countersteer must let a player catch a slide; a snap-straight response drew "a little weird" [S https://www.thexboxhub.com/carx-street-review/].
- Drift charges nitro; cap it so it cannot be farmed [E; Asphalt drift-to-nitro, https://afkgaming.com/gaming/general/asphalt-9-legends-guide-the-most-efficient-ways-to-use-nitro, search excerpt].
- Races 60 to 120 seconds with a reward each [S https://www.pocketgamer.com/need-for-speed-no-limits/review/ for the short-race criticism; length choice [E]].
- No energy meter gating races in an offline premium game [E; energy caps criticised, S https://en.wikipedia.org/wiki/Asphalt_9:_Legends].
- Frame cap and thermal-aware quality drop; heat and battery drain are repeated complaints [S https://traxion.gg/carx-street-review-ios-leads-the-way-for-carxs-move-to-open-world/; S https://apps.apple.com/app/id1458863319 for 3 GB RAM and iOS 15 minimum].
- Police must use terrain and need an end state; ramp-jumping police and endless chases are criticised [S https://www.pocketgamer.com/need-for-speed-no-limits/review/].
- Skip-to-race early; fast travel was a criticism [S https://en.wikipedia.org/wiki/Need_for_Speed:_Underground_2].

## Size

Screens 15 (13 requested, plus tuning and a split of map and event card). Flows 12. Entities 9 (Car, Part, CarPart, TuneSetting, Event, Stage, Rival, Wallet, SaveGame). Hard parts: (1) terrain-aware pursuit AI with a clear end state; (2) wet-road night reflections inside an iOS thermal and battery budget [S https://traxion.gg/carx-street-review-ios-leads-the-way-for-carxs-move-to-open-world/]; (3) drift physics that a player can catch [S https://www.thexboxhub.com/carx-street-review/]; (4) ghost storage and save integrity offline; (5) dyno and tuning readability on a phone.

Size: M for a vertical slice (one stage, three cars, one pursuit event). L for the full five-stage career. [E]

Feature matrix: `replica/features.csv`, 92 rows from the five references, clone = no for all. Must 35, should 26, could 31.
