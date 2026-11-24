# MIDNIGHT SYNDICATE: Game Design Document

Version 0.1, 2026-11-24. Godot 4.7.2, GDScript, Mobile renderer, iOS first, offline.
Sources: REA_ANALYSIS.md (REA §n), COMPETITOR_ANALYSIS.md (CA), replica/recon.md (recon), replica/features.csv (FEAT), ARCHITECTURE.md (ARCH), docs/art/CAR_01_BRIEF.md (CAR), docs/art/CITY_01_BRIEF.md (CITY).
FP = first-pass number, to be tuned by simulation or on device. Unmarked numbers come from REA or ARCH.

## 1. Pillars and pitch

Pitch: MIDNIGHT SYNDICATE is an offline, one-price arcade street racer in a rain-soaked night city, where you climb an underground racing ladder through short readable races, drift for nitro, and lose the police for real.

Pillars, in priority order:
1. Fair money, always. One price up front; optional cosmetics and car packs only. No timers, energy, fuel, loot boxes or paid random items (REA §13).
2. A night you can read. Hazards, wet patches, rivals and police read on a phone at speed (CITY "read in 5 seconds"; REA §12).
3. Skill beats stats. A well-driven Sable R beats a stronger car driven badly. Assist is on by default; the manual path is real.
4. A city that pushes back. Crews and police change where you must be. They never get extra speed.

## 2. World and fiction

Arden Bay is a fictional port city in five districts (CITY): Neon Strip, Downtown Canyon, Waterfront, Underpass, Old Market. Rain is a city rule.

The Syndicate is an underground racing organisation. It sets race terms, sanctions official races and keeps standings in one book, the Ledger. Its keeper, Ines Calder, never races and appears in person only in Act 3. The Syndicate's cut is flavour text, never a deduction from purses.

| Crew | Leader | Identity |
|---|---|---|
| Copperline | Idris Vale | Never lifts. Full throttle, late braking. Owns straights and drag starts. |
| Tidewater Loop | Nell Ardoin | Owns the wet bends. Deliberate drifters who know the waterfront. |
| Hollow Ninety | Juno Marrow | Runs the police scanner. Traps, roadblocks, cat-and-mouse. |
| Brass Lantern | Hana Quill | Old Market hairpin specialists. Strict, physical, enforce the track rules. |

Player arc:
- Act 1, "Cold Start": a newcomer, with a callsign chosen on first launch, is lent a Sable R by garage owner Odile Park for one job.
- Act 2, "Heat": crews compete for the Ledger's favour; police start to recognise the player's car.
- Act 3, "Last Lap Over the Bay": Ines Calder offers a line in the Ledger. The final race runs at night with heat on. The epilogue depends on which crew the player backed in M28.

Fiction rules: no real cities, landmarks, brands, car makes or licensed music. Police are patrol units. No weapons, injuries or drugs.

## 3. Core loop and session shape

Lengths (FP): circuit 2 to 4 laps on Neon Wharf Loop, 2 to 4 minutes; sprint 60 to 120 s; drag 9 to 14 s; time trial one lap or run. A 10 to 15 minute session holds three to five races plus garage time.

```
[Career map: pick pin] -> [Race card: mode, laps, car rule, purse, tier gate]
  -> [Pre-race: car check, countdown] -> [Race: drive, drift, nitro, evade]
  -> [Results: place, purse, reputation, unlock notice] -> [Garage: upgrade, paint, tune]
  -> back to [Career map]
```

Each session opens with one story mission and two or three Street Jobs. Autosave runs on every results screen (ARCH: versioned save with backup).

## 4. Driving model (as the player feels it)

Steering and grip
- Steer angle narrows with speed: max angle = base x (1 - 0.65 t), t = speed / v_max, v_max about 300 km/h. Steering rate 3 to 6 rad/s (REA §2).
- Suspension: spring 60 to 90 N/mm, damping ratio 0.6 to 0.8, ride height 0.12 to 0.20 m (REA §1). Crests and the underpass ramp must feel different from flat road.
- Friction 1.0 to 1.3 on dry asphalt, 0.6 to 0.7 wet or drift. Wet is the default feel, not an event.

Drift
- Swipe down starts a drift (FEAT). Rear grip drops to 0.3 to 0.5 in the drift window; front stays at 0.9 to 1.0.
- Slip is clamped at 45 to 60 degrees, with extra yaw damping beyond the clamp.
- Counter-steer assist 0.2 to 0.5, applied gradually. A snap-straight response is a defect (CA complaint 6).
- Score = abs(slip) x speed factor x time. Bank on exit when slip is under 15 degrees and speed is above 40 km/h. A wall hit or grip recovery over 5 s loses the combo (REA §3).
- Drift charges nitro, capped at 1.0.

Nitro
- Fires from the Nitro button or swipe up (FEAT). Burst 4 to 8 m/s2 for 1.5 to 3 s; top speed +10 to 20% (REA §4). FOV kick 8 to 12 degrees over 0.2 s.
- Charges from drift score, near misses and stunts. No charge while braking.
- Optional timed-hit layer: one readable window for a fuller burst. Window size is an M2 item (REA §4 gap).
- Each event sets a nitro-allowed flag. Drift events allow nitro, because drift charges it.

Drafting
- A car directly behind another, inside a rear cone, gets a reduced drag term. Drafting does not charge nitro.
- Magnitude is not set by REA. It is an M2 decision, tested on device. This document commits no number.

Damage feedback
- No mechanical damage, repair cost or pit stop.
- A hit above an impulse threshold (set in M1) gives sparks, camera trauma (trauma squared, decay 1.0 to 1.5/s, REA §5), a short steering pull and a combo loss.
- Light scrapes give cosmetic decals only. Decals never alter physics (REA §9).

Controls
- Touch default: tap-steer (tap a side of the screen, hold to hold angle), automatic throttle and braking. Brake and Nitro are movable buttons saved per device (REA §2, CA).
- Tilt option: dead zone 3 to 5 degrees, 0.1 s smoothing, calibration tap. Calibration failure falls back to tap-steer (recon F09).
- Swipe down drifts, swipe up fires nitro. Auto-throttle and auto-brake can each be turned off.
- Keyboard (dev and iPad keyboard): accelerate, brake, steer_left, steer_right, handbrake, nitro, pause, reset_car, camera_toggle (ARCH).
- Controller: not in v1 unless it works on device (REA §2). M3 stretch.
- Touch-to-steer latency under one frame plus 50 ms at 60 fps (REA §2).

## 5. Race modes

Every event is one record with rule flags: laps, car cap, nitro, shift mode, drift scoring, heat, route type (REA §8).

- Circuit (M1). 2 to 4 laps on Neon Wharf Loop, grid of four (player plus three rivals). Win: first across the line after the last lap. Flags: drift scoring, heat. The core mode that carries most of the career.
- Sprint (M2). One-way run, no laps, 60 to 120 s, on a loop segment in Act 1 and on Quarry Spiral from Act 2. Win: first to the finish. Routes are fixed in v1; no route choice.
- Drag (M2). 400 m on Pier Mile, one versus one (FP). Start gauge with two colour zones and a shift cue (recon S09). Win: lower time with no early start; an early start forfeits. No nitro at the start (FEAT). The only mode that tests the start and shift.
- Time trial (M2). Solo, one lap or one run, no rivals, no heat, no purse penalty for retries. Win: beat the designer ghost for gold. Offline ghost replay (FEAT). The teaching mode.
- Pursuit (basic M2, full M3). A circuit or sprint with police active. M2 uses Suspect and Pursue only. Win: Escape, with the escape bar full and no unit in sight, or the 90 s cap reached with bust meter below 100 (REA §7). Lose: Busted at bust meter 100, which costs cash and never reputation. The only mode with live police.
- Heat flag (not a mode). Any circuit may set heat on. Used in M20, M27 and M30.

Police appear only in pursuit and heat-flagged events, never in ordinary races, so the police stay readable.

## 6. Rival AI and police

Rival states (ARCH ai/ai_driver.gd; REA §6)
- Grid: waits for countdown, launch error set by tier.
- Line: pure pursuit on the baked racing line. Look-ahead clamp(0.5 s x speed, 6, 30) m.
- Brake: target speed = min(sqrt(a_lat x R), v_max_ai), a_lat 7 to 9 m/s2; braking look-ahead 40 to 80 m.
- Overtake: side offset 2 to 4 m, only when clear of walls.
- Recover: after a hit or spin, rejoin the line within 2 s. No teleport.
- Drift line (drift events only): follows the drift window, never exceeds the slip clamp.

Rival tiers: three per crew. Tiers differ in line error, braking variance, launch error and drift score. Never in top speed.

Fairness
- Rubber band uses skill offsets only, capped per update. AI top speed moves plus or minus 3 to 5%, and only when the gap is over 4 s (REA §6).
- The rubber band never writes to the player's car (assert in the AI system). AI speed changes under 5% between updates.
- Rivals see positions, never player inputs. Rivals never deliberately ram; contact is physical only.
- Conflict with ARCH's plus or minus 8% engine force. See §13.

Police states (REA §7)
- Patrol: active only in pursuit and heat events.
- Suspect: player in sight for 3 s; units call backup.
- Pursue: player within 150 m; units chase.
- Intercept (M3): PIT side-on below 80 km/h; ram above 30 km/h relative speed.
- Roadblock (M3, heat tier 3+): fixed barriers on the route, visible in time to brake.
- Escape: no sight for 10 to 15 s; escape bar fills; 20 to 40 s cooldown before re-suspect.
- Busted: bust meter reaches 100.
- Ramps block units. Units route around ramp meshes and never pass through them (REA §7).

Bust and heat
- Bust meter 0 to 100, fills 10 to 25 per s while surrounded by three or more units within 20 m (FP); drains when the player breaks surround.
- Heat meter 0 to 100, rises with pursuit time and visible units, drops during escape. Tiers H1 to H5 step at 20, 40, 60 and 80 (REA §7).
- H2 adds Intercept; H3 adds Roadblock; H4 and H5 add units (counts FP, tuned in M3).

## 7. Progression

Three acts, 10 story missions each, plus up to 8 optional Street Jobs per act (24 in total, FP). Map pins: story (gold), Street Jobs (silver), time trials (ghost mark), act boss (crown). Acts open with a stage banner (recon F11).

- Story missions open in order. No timer, no energy gate (REA §8, §13).
- Street Jobs open by reputation: 300 for Act 2, 800 for Act 3 (FP).
- Race cards show the required car tier before the start (CA complaint 3). A tier gate blocks the start button, never the map.
- Tracks: Act 1 uses Neon Wharf Loop and Pier Mile. Act 2 adds Quarry Spiral. Act 3 uses all three.

Unlock column: the car or feature a mission opens. (G) marks a car granted on that mission; other cars are bought at the §8 price after their unlock.

| ID | Title | Mode | Track | Crew | One-line beat | Unlock |
|---|---|---|---|---|---|---|
| M01 | Borrowed Keys | Circuit, 2 laps | Neon Wharf Loop | Copperline | Odile Park lends you the Sable R for one job. You finish last and she says that is not nothing. | Sable R (G, starter) |
| M02 | Waterline Dash | Sprint | Neon Wharf Loop, harbour segment | Tidewater Loop | Nell Ardoin challenges you on the waterfront. The wet bends teach the drift swipe. | Sprint mode |
| M03 | Pier Start | Drag | Pier Mile | Copperline | Idris Vale tests your launch. The start gauge teaches the two zones and the cost of an early go. | Drag mode |
| M04 | Sunday Laps | Circuit, 3 laps, drift | Neon Wharf Loop | Tidewater Loop | Nell says you lift too early in the drift. Your first combo banks. | Halvard Ember 2 (buy) |
| M05 | Car Park Clock | Time trial | Pier Mile drift yard | none, ghost | An old champion's ghost sits on the car park board. Beat it to learn the drift lines. | Ghost: Odile's run |
| M06 | Hairpin Toll | Sprint | Neon Wharf Loop, Old Market | Brass Lantern | Hana Quill's crew blocks the hairpin for a toll race. You win clean and learn their rules. | Brass Lantern events |
| M07 | Hollow Signal | Pursuit, basic | Neon Wharf Loop | Hollow Ninety | Juno Marrow's scanner picks you up. One patrol unit follows; breaking line of sight starts the escape. | Pursuit mode |
| M08 | Night Tax | Circuit, 3 laps, wet | Neon Wharf Loop | Brass Lantern | Brass Lantern collects entry in favours. The fee sheet carries the Ledger's name. | Wet-track tune preset |
| M09 | Ledger Page One | Circuit, 3 laps, drift | Pier Mile drift yard | Copperline | A sealed envelope from Ines Calder sets the terms. You are now written in the book. | Mirell Lumen 4 (buy) |
| M10 | First Entry | Circuit, 4 laps | Neon Wharf Loop | all four crews | The Ledger's first sanctioned race. A win opens the road up Quarry Spiral. | Act 2 (Quarry Spiral) |
| M11 | Quarry Climb | Sprint | Quarry Spiral | Copperline | Idris reroutes you up the switchbacks. The climb shows the city from above. | Street Jobs, Act 2 |
| M12 | Gravel Bait | Sprint | Quarry Spiral | Hollow Ninety | Juno fakes a breakdown on the switchbacks. Reading her brake lights wins it. | Pursuit warning cue |
| M13 | Cop Radio | Pursuit, full | Quarry Spiral | Hollow Ninety | The first full pursuit with heat tiers. A roadblock forces a choice at the overpass. | Ostrel Grail (G) |
| M14 | Waterfront Slide | Circuit, drift | Neon Wharf Loop, waterfront | Tidewater Loop | Nell wants proof you can catch a slide in rain. Counter-steer assist is tested here. | Drift bonus objectives |
| M15 | Widebody Dare | Circuit, 3 laps, drift | Pier Mile drift yard | Tidewater Loop | Nell's widebody is on the line if you beat her line through the yard. | Kessa Rook (buy) |
| M16 | Fast Money | Drag | Pier Mile | Copperline | Idris runs a side bet on the strip. The Tavrin Arc EV and its clean launch are on the line. | Tavrin Arc EV (buy) |
| M17 | Overpass Trap | Pursuit, full | Neon Wharf Loop, overpass | Hollow Ninety | Juno sets a roadblock trap on the overpass. Survive it and the scanner goes quiet. | Intercept (M3) |
| M18 | Lantern Shopfront | Circuit, 4 laps | Neon Wharf Loop, Old Market | Brass Lantern | Brass Lantern demands a clean race through the market. You refuse a shove and they respect it. | Brass Lantern shop |
| M19 | Dead Reckoning | Time trial | Quarry Spiral | none, ghost | A dead driver's ghost still holds the Quarry board. Beat it to prove the old rules. | Vorn Bastion (buy) |
| M20 | Ledger Page Two | Circuit, 5 laps, heat | Neon Wharf Loop | Hollow Ninety, Brass Lantern | Ines Calder's second page asks you to fix a race. You run it clean and the Ledger notices. | Act 3 (all tracks) |
| M21 | Drevik Straight | Drag | Pier Mile | Copperline | Copperline brings in the Drevik Serpent Z for a straight-line challenge. The straight is the whole test. | Drevik Serpent Z (buy) |
| M22 | Crown Corner | Circuit, 3 laps, drift | Quarry Spiral | Tidewater Loop | Nell's crew sets a prize drift on the switchbacks at speed. The line must hold to bank. | Drift tier 2 bonus |
| M23 | Patrol Hour | Pursuit, full | Quarry Spiral | Hollow Ninety | Juno pushes heat to five tiers on the Quarry road. The cooldown is the only way out. | Heat tiers H4, H5 |
| M24 | Underpass Wall | Sprint | Neon Wharf Loop, underpass | Brass Lantern | Brass Lantern stages a wall of cars in the tube. You pick a gap, not a fight. | Underpass Street Job |
| M25 | Shutter Down | Time trial | Pier Mile | none, ghost | The Ledger's terms need a clean gold run: no contact, no combo loss. | Gold ghost pack (cosmetic) |
| M26 | Vesper Hour | Circuit, 4 laps | Neon Wharf Loop | Copperline | Idris offers the Noctra Vesper if you beat his champion's line by two seconds. | Noctra Vesper (G) |
| M27 | The Ledger's Test | Pursuit, full, heat | Neon Wharf Loop | Hollow Ninety | The Ledger sends police to the waterfront to test your loyalty. A lost pursuit costs cash, not reputation. | Finale gate (800 rep) |
| M28 | Old Market Truce | Circuit, 3 laps, 3 cars | Neon Wharf Loop, Old Market | Brass Lantern, Tidewater Loop | Two crews want different outcomes. The race you run decides which epilogue opens. | Epilogue choice |
| M29 | Tessera Rumour | Time trial | Neon Wharf Loop, full lap | none, ghost | A builder's sealed ghost points at the Auric Tessera, a car nobody has tuned to the limit. | Tessera preview |
| M30 | Last Lap Over the Bay | Circuit, 5 laps, heat | Neon Wharf Loop, night | all crews | The Ledger's final race. The win grants the Auric Tessera and one of two epilogues. | Auric Tessera (G), ending |

## 8. Garage

Ten fictional cars for R1. Prices are FP (§9).

| Maker | Model | Tier | Price | Unlock | Character |
|---|---|---|---|---|---|
| Noctra | Sable R | 1 | start | M01 (G) | Mid-engine two-seat wedge. Low, wide, loud at the rear. |
| Halvard | Ember 2 | 1 | 4,000 | M04 | Light front-drive hatch. Forgives mistakes, rewards clean lines. |
| Mirell | Lumen 4 | 2 | 12,000 | M09 | Four-door, long-wheelbase sedan. The family car that learns to drift. |
| Ostrel | Grail | 2 | 14,000 | M13 (G) | Heavy rear-drive grand tourer. Slow to turn, hard to beat at steady speed. |
| Kessa | Rook | 3 | 28,000 | M15 | Widebody coupe built for drift lines. The car Tidewater Loop trusts. |
| Tavrin | Arc EV | 3 | 30,000 | M16 | Electric, instant torque, cleanest launch. No gears; the shift cue stays on launch. |
| Vorn | Bastion | 4 | 52,000 | M19 | Tall four-wheel-drive SUV. Slows police more than it slows you. |
| Drevik | Serpent Z | 4 | 58,000 | M21 | Front-engine V8. Straight-line brute, hard to hold through corners. |
| Noctra | Vesper | 5 | 95,000 | M26 (G) | Light rear-engine GT. The Noctra answer to the Sable R, tuned for tight circuits. |
| Auric | Tessera | 6 | 170,000 | M30 (G) | Mid-engine apex car. Very hard to tune; the reward for the last lap. |

- Visual customisation (cosmetic data separate from handling data, REA §9): paint as a shader palette with 12 shared swatches and per-car accents; three wheel designs per car; two body kits per car that never change aero; six wrap presets; callsign on the rear plate only.
- Cut from v1: interiors, underglow, free text, cosmetic-only widebody.
- Rule: a cosmetic change never changes physics. Unit test: physics output identical before and after any cosmetic change.
- Performance upgrades: four parts (Engine, Tyres, Nitro, Chassis), five levels each. Engine sets the power and top-speed band; Tyres sets friction; Nitro sets burst and capacity inside the REA ranges; Chassis sets spring and weight inside the tier band.
- Fairness: a fully upgraded Tier 2 car cannot beat a stock Tier 3 car on top speed. Band values are set on the dyno in M2.
- Tuning, saved per car: three sliders with live delta (Gearing, Nitro balance, Tyre pressure) and a dyno graph (power, torque). Redraw under 100 ms (REA §9). Two taps from the garage. Locked during races; free to change.

## 9. Economy

Currencies: Cash (spent on cars, parts, cosmetics) and Reputation (never spent; it opens Street Jobs). No premium currency.

Start (FP): 15,000 cash, 0 reputation, Sable R owned.

- Sources, race purses (FP base): circuit win 1,500; circuit podium 800; sprint win 1,200; drag win 900; time-trial gold 600; pursuit escape 2,000; Street Job 800. Event tier multiplier: Act 1 1.0, Act 2 1.6, Act 3 2.4.
- Story completion (FP): 3,000 at M01, rising to 40,000 at M30. Bonus objectives: 200 to 600 each.
- Reputation (FP): win 20, podium 10, escape 30, bonus objective 5. A bust gives 0 and takes nothing.
- Sinks: cars (§8), parts (FP per part, levels 1 to 5: 1,000; 2,500; 6,000; 12,000; 22,000; full set 43,500), paint 800, premium paint 2,000, wheels 1,500 to 4,000, kits 3,000 to 6,000, wraps 1,000. No recurring fee, no timer, no roll.
- Target (FP, check in simulation): about 700,000 cash earnable in the release, enough for all nine non-starter cars (463,000) plus full parts on three cars. Full garage by play alone in roughly 25 to 35 hours.

Rule set, non-negotiable
- No energy, fuel, stamina or race-count gates. No timers that stop play (REA §13).
- No loot boxes, gacha, random paid items or random prices. Every price is the same for all players.
- No pay-to-win. Every car is earnable by play. No store item beats a play-earned item.
- Optional purchases only: cosmetic packs and car packs. A car pack sells a car at its normal price and adds no performance.
- Premium: one price up front. FP $6.99 USD, test $4.99 to $7.99. No ads in v1. Any future ad is rewarded and optional (REA §13).
- Purchases never expire. Restore purchases works on a fresh install. Fully offline: no login, no account, no server.

## 10. UI flow

| ID | Screen | Route | Notes |
|---|---|---|---|
| S01 | Title and main menu | launch | Play, Garage, Map, Store, Settings. Save-recovery prompt on checksum failure. |
| S02 | Garage | menu | Car carousel, stat card (power, grip, weight), tier badge. |
| S03 | Car select | from S08 or S09 | Only when an event restricts cars. Lock reason shown. |
| S04 | Customisation | Garage, car, Paint | Paint, wheels, kits, wraps. Locked items show their unlock mission. |
| S05 | Upgrade | Garage, car, Upgrade | Four-slot grid, stat delta preview, funds-short state. |
| S06 | Tuning and dyno | Garage, car, Tune | Three sliders with live delta, dyno graph. |
| S07 | Career map | Map | Pins, Street Jobs, time trials, act boss, stage banner. |
| S08 | Race card | tap a pin | Mode, laps, car rule, purse, tier gate, best time. |
| S09 | Pre-race | after S08 | Car check, countdown, start gauge (drag only). |
| S10 | Race HUD | race start | Speed, position, lap, minimap, nitro meter with timed-hit window, drift bar. |
| S11 | Pause | HUD pause | Resume, restart, settings, quit with confirm. |
| S12 | Results | race end | Place, time, purse, reputation, unlock notice. |
| S13 | Pursuit HUD | pursuit or heat race | Heat tier, escape bar, unit and roadblock markers. |
| S14 | Store | menu | Premium price, cosmetic and car packs, restore purchases. |
| S15 | Settings | menu | Steering mode, sensitivity, assists, camera, quality tier, frame cap, language (English, Turkish). |

Happy-path taps
- Launch to first race: Play (1), Start race on the auto-opened M01 card (2). Countdown is automatic. Total 2. Intro cards are skippable with one tap, and cost 0 when unused.
- Race from the map: pin (1), Start (2). Buy a part: Garage, car, Upgrade, slot, Buy, Confirm (5). Paint: Garage, car, Customise, swatch, Back (4). Tune: Garage, car, Tune, slider, Save (4 plus one drag).
- In-race: 0 menu taps; swipe down drift, swipe up nitro. Pursuit: 0 extra taps. Pause and quit: 3.
- Earn or buy a car: result notice to S02 (2); buy via the car card (4). Steering change: 3. Stage banner: 2.
- Cold open with no network: loads from the local save with no login screen.

## 11. Audio direction

- Engine: per-car layered loop (idle, on-throttle, off-throttle overrun, limiter), crossfaded on rpm_norm and throttle (ARCH). Each car has its own layers, never a pitch-shifted copy.
- Tyres: slip layer driven by slip angle; pitch rises with slip; wet hiss on wet surfaces; scrape on wall contact.
- Nitro: pressure whoosh and intake roar with a release tail, synced to the FOV kick.
- City: continuous rain bed, distant traffic, bay horns on the Waterfront, neon hum near signage, sodium-lamp buzz in Old Market (CITY).
- Police and music: siren lines only in pursuit and heat events. Music is original night electronic: analog pads, sparse percussion, 95 to 115 BPM (FP), no vocals, layers rising with heat and stage. Music ducks briefly on a hit.
- Sources: CC0 or project-owned audio only, each logged in the attribution file (REA §sourcing).

## 12. Scope by milestone

- M1, vertical slice: one car (Sable R), one track (Neon Wharf Loop), circuit mode 2 to 4 laps. Driving model, drift, nitro, tap-steer and tilt, assist toggles. AI with one tier and a bounded rubber band. HUD subset (S10), chase camera (REA §5), minimal results, garage view with paint, settings subset. Exit: REA §1 to §6 acceptance passes on device.
- M2, Act 1 playable: three cars (Sable R, Ember 2, Lumen 4). Act 1 (10 missions) and Act 1 Street Jobs. Pier Mile added. Modes: circuit, sprint, drag, time trial, basic pursuit. Upgrades, tuning and dyno, career map, race card, store scaffold with no sales. Full settings, tilt calibration, save with backup, English strings, Turkish scaffold.
- M3, Act 2 and full pursuit: seven cars (adds Grail, Rook, Arc EV, Bastion). Act 2 (20 missions). Quarry Spiral added. Full pursuit with Intercept, Roadblock and heat H1 to H5. Rival tiers 1 to 3. Device performance pass: frame cap and thermal-aware quality drop (REA §14). Turkish first pass.
- R1, first commercial release: ten cars, three tracks, 30 missions, 24 Street Jobs, five modes, Act 3 and two epilogues, final heat race. Turkish and English complete. Store live with premium, cosmetic and car packs, and restore purchases. App Store assets, age rating review, privacy manifest, TestFlight restore test.
- Cut order (counts before quality): Street Jobs down to 12; cars down to 8 (one per tier minimum); Act 3 optional missions down to 8; third track, if drag and sprint run on the other two. Never cut: handling acceptance, fair-money rules, the pursuit end rule, the Medium 60 fps floor, Turkish and English strings.

## 13. Open questions and risks

Open questions
1. Race length. The brief says 2 to 4 minute races; REA §8 acceptance says median 60 to 120 s. This document uses 2 to 4 minutes for circuits and 60 to 120 s for sprints. Restate REA §8 before M1 testing.
2. Rubber band bound. REA §6 says plus or minus 3 to 5% top speed; ARCH says plus or minus 8% engine force. This document uses REA. ARCH needs an update after a decision; it was not edited here.
3. Heat metric. REA gives a 0 to 100 bust meter and five heat tiers at 20, 40, 60 and 80. This document uses one bust meter and one heat meter. Confirm.
4. Drafting magnitude: no REA source; set by one M2 test.
5. Damage: no mechanical damage proposed; confirm after the first playtest.
6. Controller in v1, timed-hit nitro in v1, iPad support, and a manual save export. Decide after device tests.
7. Price: FP $6.99, range $4.99 to $7.99.
8. Drag length (400 m) and finish band (9 to 14 s) are FP. Test on device.
9. Pursuit surround (three units within 20 m) and unit counts per heat tier are FP.
10. Callsign on first launch, or a silent protagonist.

Risks
- Device floor: REA §14 gives 3 GB RAM and a 1.5 GB budget. iOS minimum version and device list are not in the Godot 4.7 docs (REA gap). Test on real hardware early.
- Build chain: Godot's iOS export needs macOS with Xcode. CI cost and Apple Developer enrolment are needed before any device test (REA §14).
- Mobile renderer: no SSR, SSAO or TAA. The wet look relies on authored roughness, decals and probes; 8 omni and 8 spot lights per mesh (REA §11). Test clearcoat and emissive in one real export before locking materials.
- Physics: custom suspension at 60 Hz with Jolt must settle and hold ground contact (REA §1).
- Theme and rating: crime theme with police. Mitigated by no violence, no weapons, no drugs, and no human victims. Age rating review before R1.
- Economy: earn curve is untested; simulate before M2 playtests. Turkish quality needs a native reviewer at M3.
- Evidence gaps: no film source read; chase camera, rival tuning and HUD layouts for reference titles not found; Reddit unreachable (REA gaps). Dependent numbers are marked FP or REA gap.
