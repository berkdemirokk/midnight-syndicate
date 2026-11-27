# Roadmap

Counts are cut before quality is. A milestone closes only on evidence (tests, real captures,
measured numbers), never on a document.

## Road to release (strategy of 2026-11-27)

The owner's goal: a better App Store rating than Asphalt Legends ("Asphalt 4.7 almış, hedef onu geçmek").
Evidence, sources and the three full plans: `docs/research/RATING_STRATEGY_2026-11-27.md`.

### What can be won
- Not winnable, and no longer the yardstick: out-producing Asphalt or Need for Speed (licensed real cars, the
  Ferrari key art, 300 cars, a 3.9 GB install, a million ratings). The Ferrari picture is an App Store event
  card of a real car, not a race frame.
- Winnable in principle: a higher displayed average on the Turkish storefront (Asphalt: 4.70 from 148,620
  ratings there, 4.77 in the US, read 2026-11-27). A rating is per storefront and comes from a game's own
  players. Small paid or free racers hold 4.6 to 4.9 (Rush Rally 3, GRID Autosport, DATA WING).
- Honest estimate: a fair, stable first version at about 4.5 to 4.8 on tens of ratings around February to March
  2027. It is fragile (two one-stars in thirty put it back at 4.7) and depends on two things the lead does not
  control: the owner returns real phone data within a day each round, and the owner brings the first players.
- What decides a rating: not graphics. The low-star reviews of the big racers are about pay-to-win, ads and
  matchmaking; those of the small ones are about heat, frame dips, crashes and weak touch controls. So the order
  below removes one-star causes first and spends on looks only where the first 30 seconds show it.

### The twelve steps, in order
Each step closes on its acceptance line in the research file, not on this list.
1. [ ] Facts and decisions from the owner (no lead time): what happened on the iPhone with build 1 (launched,
   steered, finished a race, heat, stutter), iPhone model and iOS version, the App File Sizes screenshot; yes
   or no on: free with no ads and no purchases for 1.0, a borrowed 4 GB iPhone (11, 12, 13 or SE 3), the
   dark-studio garage, downloads of licensed traffic cars and of a separate body for the Sable R.
2. [ ] Touch survival build: pause, quit, restart and reset by touch, auto-pause when the app is interrupted, a
   touch layout that covers no gauge, Turkish on first run for a Turkish phone, device floor A12.
3. [ ] Texture memory diet: no lossless texture in the 3D asset folders (247 of 358 were lossless, 617 MB as
   RGBA8). Gate on video memory, report the pack size.
4. [ ] Performance card inside the build and the first iPhone numbers (owner's phone, then one 4 GB phone).
   One pass line: at most 3% of frames over 20 ms, minute-20 average at least 55 fps, no frame over 100 ms
   after the countdown on a second run, no memory warning. A miss drops one preset or locks 30 fps.
5. [ ] Crash, save and boot shield: old saves load, a truncated save falls back to the backup, a memory warning
   drops the mirror and one preset, an unclean exit lowers the preset once and says so.
6. [ ] Touch controls tuned by thumbs: brake assist, sensitivity, left-hand and tilt options, live sliders so
   one owner session replaces several builds.
7. [ ] First ten minutes: two taps to a short night race a newcomer can win, three hints, one guided upgrade, a
   loading card.
8. [ ] Rating request by Apple's rules (the system prompt after a win, never a custom "do you like it" card),
   plus Rate and Support rows in Settings. Start the native-build tries early: least testable item of all.
9. [ ] A fair ladder: about 30 events from the three tracks, economy rebalance (11 events pay 27,300 cash
   against 821,500 of cars and upgrades), Easy / Normal / Hard.
10. [ ] Visible quick wins, done in the gaps while the owner tests: nitro flame at the real exhausts, tail lamps
    that glow, dark-studio garage and title, low sun instead of flat noon.
11. [ ] Store pack: name check, price, privacy page, age rating, native Turkish proofread, look-alike check of
    cars and signs, six to eight harness captures at 2868x1320.
12. [ ] External TestFlight beta, release in Turkey first, then a reply to every low review within 48 hours and
    a fix build within 7 days. Other storefronts open after two crash-free weeks, not at a rating count.

### Rules for this stretch
- One build per owner round-trip: a build goes to the owner with a batch (steps 2 to 4 ride together), never
  for one change. Each round-trip costs an owner session and a 30 to 40 minute CI run.
- Stop rule: if the phone misses the pass line on Low, cutting starts before polishing (rival count, mirror,
  dressing density, then a track).
- Parked until phone numbers exist: street light through the sky radiance, puddle break-up and lamp halos,
  the surface pass on all eleven cars, facade depth. A hero render may serve icon, splash and posts only;
  store screenshots show the app in use.
- No comparison sheet against the Ferrari card. Before/after sheets compare this game with itself.
- Open contradictions that need the owner before any store text: price (free, or the design document's premium
  price), and the design rule against real cities next to the shipped Istanbul landmarks.
- Not covered by any step and needed for the goal: an audience (only the owner can bring it), sound judged by
  ear, first launch time on Metal, an iPad run, crash breadcrumbs readable without a Mac.

## Original milestones (history)
The lists below are the plan of the first sessions and are kept for history. PROGRESS.md is the record of what
is done; the section above is what is next.

## M0 — Foundations
- [x] Environment verified (Godot 4.7.2, Blender 5.3, Git, gh, GPU)
- [x] Public-source research with verification pass (docs/research, REA_ANALYSIS, COMPETITOR_ANALYSIS)
- [x] Architecture, contracts, test harness
- [ ] Asset factory (manifest, licences, CC0 fetch) validated
- [ ] CI: headless tests on GitHub Actions (free Linux runner)

## M1 — Vertical slice (quality gate before any scale-up)
- [ ] Hero car "Noctra Sable R": LOD0-2, wheels separate, PBR, passes the car brief
- [ ] Circuit "Neon Wharf Loop": road, 5 districts, building kit, props, lights
- [ ] Arcade driving: suspension, grip, drift, nitro (all vehicle tests green)
- [ ] Chase camera, player input (keyboard, controller, touch)
- [ ] Rival AI completes clean laps, race manager, results
- [ ] Race HUD, main menu, pause, results, settings (TR/EN)
- [ ] Interactive 3D garage (orbit, paint, rims)
- [ ] Wet asphalt, neon glow, rain, nitro flame, tyre smoke, sparks, speed lines
- [ ] Graphics presets Low/Medium/High + dynamic resolution, measured on the dev PC
- [ ] Visual quality gate: 8 criteria scored on real captures, two review stages, lead sign-off
- [ ] Windows build runs from an exported binary

## M2 — Game loop
Save/load career, economy, upgrades and tuning, sprint + time trial + drag modes, engine and tyre
audio (CC0), haptics, onboarding, controller polish, replay camera, damage feedback.

## M3 — Pursuit and world
Police AI (heat, roadblocks, bust/escape), traffic, second track, cars 2-4, story missions act 1.

## M4 — Content and device
Third track, cars 5-10, missions to 30, localisation pass, first iPhone build (needs macOS/Xcode
access: see BLOCKERS.md), thermal and frame-time sessions on real devices, preset tuning.

## M5 — Release
Icon, launch screen, privacy manifest, screenshots from the capture harness, store text, age
rating, TestFlight internal, external, review submission (owner decisions throughout).

## Scope guard
First commercial target: 10 cars, 3 tracks, 30 missions, 5 modes, TR + EN, offline career.
Re-evaluated at the end of M1 against the real cost of one car and one track.
