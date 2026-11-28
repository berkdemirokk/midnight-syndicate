# Arcade handling feel: research and recipe for Midnight Syndicate

Date: 2026-11-28. Scope: how arcade racers build handling feel, what that means in Godot 4.7.2 with Jolt, and a recipe for our car code.

Tags: [S] = read in a source during this run. [SN] = search snippet only, not opened. [E] = estimate or inference, unverified.

Numbers in section 3 that come from our own probes are dev-PC headless at 60 Hz (RTX 5060 Ti host). They are not phone numbers.

## 0. What we already have (short)

Read: `docs/design/HANDLING_2026-11-28.md`, `docs/research/06-arcade-vehicle-physics-and-ai.md`, `game/vehicles/arcade_car.gd`, `game/vehicles/player_driver.gd`, `game/vehicles/vehicle_input.gd`, `game/vehicles/specs/noctra_sable.tres`.

Already in code:
- Speed-sensitive steering lock: 32 deg at rest, 6.5 deg at top speed, exponent 0.8 (Sable).
- Turn-in rate scaled 1.35x at rest to 0.8x at top speed; centring is faster (`steer_return_speed` 11).
- Drift entry: handbrake or slip above 25 deg, above 55 km/h, grounded on 2+ wheels.
- Counter-steer assist: starts at 50 % of max drift angle, strength 1.0.
- Nitro: 3.2 s capacity, force x1.55, top speed x1.16. Refill 0.035/s passive, 0.16/s while drifting.
- Body contact friction 0.05 and bounce 0.1 (new in the handling pass). Tyres are rays, so grip is unchanged.

Not done yet (from the handling doc): drift tuning, camera FOV and shake, touch steering delay, and any real playtest.

## 1. What the best mobile and arcade racers do

### 1.1 Assisted steering is the default on phones

- Asphalt 9 Legends offers three steering schemes: TouchDrive (the game steers, the player brakes and uses nitro), Tap to Steer, and Tilt to Steer. TouchDrive is the default and the one aimed at beginners. Tilt is described as the most precise and hardest. [SN] https://www.chaptercheats.com/cheat/switch/447597/asphalt-9-legends/hint/157939 (fan guide, several years old; menu names may differ)
- Lesson: an auto-steer mode is the first thing a phone player needs. Our game has auto-accelerate, but no steer assist. [E]

### 1.2 Drift is built from brake, throttle or handbrake, and it pays on exit

- Need for Speed Unbound lets a drift start with brake taps, throttle taps, or both. The handbrake always works. [S] https://gamermatters.com/need-for-speed-unbounds-new-handling-is-steering-in-the-right-direction-again/ (critic's review) and [SN] https://www.ea.com/news/how-to-drift (returned 404 when fetched; cited from search)
- The same review says drift entry can feel sluggish and unpredictable, and that grip turns give a boost on exit "just like drifting." The author says this keeps the two modes roughly balanced. [S] same URL
- Unbound also has a handling slider that tilts the car toward drift or toward grip. [SN] https://en.wikipedia.org/wiki/Need_for_Speed_Unbound
- Lesson: drift needs a clear entry, a visible reward on exit, and a grip-turn path that pays about the same. Our code gives drift nitro refill but no exit boost. [E]

### 1.3 Burnout: the boost economy is the feel

- Burnout Takedown and Paradise fill boost by near misses, driving into oncoming traffic, jumping, and drifting. Boost turns risk into speed. [S] https://invisiblestudio.blogspot.com/2007/07/burnout-paradise-design-boost.html?m=0 (fan-era design blog about the 2007 preview)
- The same post says the handbrake (E-brake) exists because an open world needs instant direction changes. [S] same URL
- The designer's own tuning numbers (boost rates, near-miss windows) were not found. [E] Search for Criterion talks found no primary source. Treat Burnout feel as a design pattern, not as numbers.
- Lesson: link risk to reward. Near misses that pay, and a scrape that does not kill all speed, are the feel.

### 1.4 Collision forgiveness

- Playtest guidance from a small-game developer says a glancing wall hit that removes almost all speed "feels like a punishment for the track, not the player." [S] https://dev.to/juegostudiosofficial/tuning-arcade-car-handling-on-a-small-racing-game-a-playtest-checklist-5a52
- Our own probe: a glancing 15 deg wall hit at 120 km/h keeps 0.86 of its speed now (0.63 before). A head-on hit keeps 0.06. [S] docs/design/HANDLING_2026-11-28.md
- Lesson: keep glancing hits high and head-on hits low. Verify that the scrape does not feel like skating.

### 1.5 Drift assist: counter-steer and speed-sensitive assist

- Gran Turismo style assists correct oversteer automatically. The control hands back to the player over 0.4 s. Detection uses rear slip past peak, or yaw rate off a reference. [SN] https://github.com/amazing-source/drive-lab/issues/158
- Assetto Corsa gamepad assist keeps separate race and drift profiles. The drift profile uses stronger counter-steer and less speed sensitivity. [SN] https://github.com/adam10603/AC-Advanced-Gamepad-Assist/blob/release/ConfigGuide.md
- Warning from the same sources: stronger counter-steer makes it easy to over-correct and spin the other way. [SN] same URL
- Our code already has counter-steer assist. It should get a separate drift profile only if playtests show it is needed. [E]

### 1.6 Camera and shake

- Eiserloh's GDC 2016 talk gives the trauma model. Trauma is 0 to 1, rises on hits and stress, and decays linearly. Shake = trauma cubed (the slides say "trauma 2 or trauma 3", and the examples match cubed). Offsets = max value x shake x random value (Perlin noise suggested). [S] https://archive.org/stream/GDC2016Eiserloh/GDC2016-Eiserloh_djvu.txt (full talk text). Primary slides: [SN] http://www.mathforgameprogrammers.com/gdc2016/GDC2016_Eiserloh_Squirrel_JuicingYourCameras.pdf
- Examples in the talk: trauma 0.3, 0.6, 0.9 gives 3 %, 22 %, 73 % shake. [S] same archive text
- Smoothing example from the talk: `x += (target - x) * 0.1` per 60 fps frame, with time scaling. [S] same archive text
- Lesson: shake should grow fast with speed and impacts, but small values must stay near zero. Our `speed_shake_from_kmh` change (180 to 150) is in the right direction. [E]

### 1.7 Touch steering must be fast

- Good phone steering needs low lag. Ideas from developer posts: a dead zone, normalise the touch offset, and smooth against a sample from a short time ago rather than the last frame. [SN] https://inairspace.com/blogs/learn-with-inair/godot-touch-controls-for-mobile-a-complete-practical-guide-1 and https://devlog.levi.dev/2022/04/implementing-multi-touch-camera.html
- Lab evidence leans toward tilt for steering. [SN] https://www.yorku.ca/mack/ec2017.html (tilt better for path following; touch better for target selection). A small study ("Tilt or Touch?", two players, 15 trials each) reported tilt with fewer collisions. It is too small to trust. [SN] https://www.academia.edu/37542571/Tilt_or_Touch_An_Evaluation_of_Steering_Control_of_Racing_Game_on_Tablet_or_Smartphone
- Lesson: offer tilt and an auto-steer mode. Test touch lag on the phone, not on the PC.

### 1.8 Numbers that are missing

- No public 0-100 km/h or top-speed numbers for Asphalt, NFS or Burnout were found in this run. [E] Use our own spec values and the test bands in `game/tests/test_handling_feel.gd`.
- No public nitro gain formula was found. Asphalt fan wikis say drifting refills nitro and that nitro from low speed gains more time than nitro at top speed. [SN] https://asphalt.fandom.com/wiki/Nitro and https://asphalt.fandom.com/wiki/Drift (fan wikis, unverified in game)

## 2. What this means in Godot 4.7.2 (Jolt, Mobile)

### 2.1 Physics engine: Jolt is on

- `game/project.godot` sets `3d/physics_engine="Jolt Physics"`. [S] local check
- Godot's own PhysicsMaterial page: friction 0 to 1, default 1.0. `rough` (default false): if true on one body, that body's friction is used. If false on both, the lowest friction wins. If true on both, the highest wins. Bounce default 0.0. `absorbent` (default false) subtracts bounce instead of adding it. [S] https://docs.godotengine.org/en/stable/classes/class_physicsmaterial.html
- Jolt's own default is different. Its docs say friction defaults to a geometric mean, sqrt(f1 x f2), and restitution to the maximum. [SN] https://jrouwe.github.io/JoltPhysics/ . Whether Godot's Jolt integration maps Godot's `rough` rule or Jolt's default is not verified. [E]
- Godot proposal #11715 asks for material combine modes that match other engines. It is open or unmerged as far as this run shows. [SN] https://github.com/godotengine/godot-proposals/issues/11715

Why it matters: the handling pass sets body friction to 0.05. Under the Godot rule (both not rough, lowest wins) the result is 0.05. Under a geometric mean with a wall at 1.0 it is about 0.22. Either way the sweep is monotone, so the result still points the right way. But the effective value is not known yet. The handling doc already says this is not verified. The fix is a probe (see step 3 below).

### 2.2 Physics cost and layout

- Jolt is the stock 4.4+ choice and the docs say new projects use it by default. [S] https://docs.godotengine.org/en/stable/tutorials/physics/using_jolt_physics.html (cited in local note 06)
- A RigidBody3D with four rays per car is the right base. Our custom tyre model stays. [S] local note 06
- `contact_monitor = true` and `max_contacts_reported = 8` (Sable) are needed for the hit signal. The `hit_min_impulse` of 1500 is the trigger for scrape audio and VFX. [S] arcade_car.gd, noctra_sable.tres

### 2.3 Input in Godot on phones

- `PlayerDriver._update_steer` sends touch steer through the same `move_toward` ramp as the keyboard. At 60 km/h the turn rate is about 6 x lerp; full lock from centre takes about 0.17 s at standstill and about 0.45 s at top speed (`turn_rate_low` 6, `turn_rate_high` 2.2, `speed_norm_kmh` 286). [S] player_driver.gd (values from the code, timing is arithmetic) [E] for the exact numbers
- The stick bypasses the ramp. Tilt uses its own deadzone and exponent. [S] player_driver.gd
- Lesson: touch steering may feel sluggish on a phone because it is treated like a keyboard. Measure this on a phone.

### 2.4 Drift and nitro levers in our code

- Drift exit uses `drift_exit_time` (0.35 s) and `drift_min_angle_deg` (9 deg). Exit speed is not boosted. [S] arcade_car.gd, Sable spec
- Nitro refill is 4.5x faster while drifting (0.16 vs 0.035 per second). [S] Sable spec
- Nitro gain from 60 to 120 km/h fell from 0.88 s to 0.60 s after the speed-feel change (the car pulls harder now). [S] docs/design/HANDLING_2026-11-28.md

## 3. Recipe for our game

Each step names the file, the target, and the way to check it. Targets marked [proposal] are starting points for us to test, not facts.

### Step 1. Add a steer-assist mode for touch (the biggest phone win)

- Files: `game/vehicles/player_driver.gd` (add a `steering_mode` value, for example `"assist"`), `game/core/settings.gd` (the option), touch controls in `game/vehicles/touch/`.
- What: in assist mode the car follows a target heading (the next racing-line point or the road centre). The player's touch input only adds an offset. Cap the assist at a few degrees of steer. Keep the player in control of drift and nitro. This is the TouchDrive idea from Asphalt 9. [S] (scheme, fan guide) [E] (our cap)
- Target [proposal]: a player who never touches the steer zone finishes a lap of `istanbul_bogaz` within 15 % of the lap time of a full-manual run.
- Check: add a headless probe under `game/tests/` that drives the car with zero steer input in assist mode and logs wall hits and lap time. Then a blind playtest (step 5).

### Step 2. Cut touch steering lag

- Files: `game/vehicles/player_driver.gd` `_update_steer`.
- What: give touch steer its own rate (no `turn_rate_high` cap at speed) or let the touch target skip the ramp when the finger is down. Keep the keyboard ramp unchanged.
- Target [proposal]: from finger down to 90 % of full lock under 0.15 s at 60 km/h and under 0.25 s at 200 km/h.
- Check: new test in `game/tests/test_handling_feel.gd` that sets `touch_steer` to 1.0 and counts physics ticks until `steer_angle_rad` reaches 90 % of max lock. Log the number in the probe, not only in the doc.

### Step 3. Pin down the body-friction rule on Jolt before tuning any more walls

- Files: `game/vehicles/arcade_car.gd` (BODY_FRICTION, BODY_BOUNCE), a wall or prop material in the track scenes, `game/tests/test_handling_feel.gd`.
- What: run the friction sweep with the wall PhysicsMaterial set explicitly (friction 1.0 and rough false, then friction 1.0 and rough true). Record the glancing-wall speed kept for each. If the rough-true result matches friction 0.05 or 1.0, the combine rule is known.
- Why: the doc says the combine rule is unverified. The 0.86 glancing number depends on it.
- Target: the glancing-wall number is reproduced by two different wall settings that the rule predicts. Write the rule in the doc.
- Check: add the two wall cases to the probe. No change to the 0.05 value until the result is known.

### Step 4. Give drift a reward on exit that matches the grip turn

- Files: `game/vehicles/arcade_car.gd` (the drift-exit path near `_drift_exit_t`, and a new exit boost constant next to the other arcade constants), Sable and other specs only if needed.
- What: when a drift ends with speed above `drift_entry_speed_kmh`, add a short forward push (for example 0.3 s of extra engine force, about 1.1 to 1.2 x, similar to the nitro mult). Make a grip-turn exit at the same speed get a small matching push, so drift is not always the better line. This follows the Unbound balance point. [S] gamermatters review
- Target [proposal]: exit speed 2 s after a drift and after a grip turn at the same entry speed within 5 % of each other, on Sable and Vela.
- Check: a probe that runs both lines on the same corner and logs speed at 2 s. Store the result in `evidence/`. No screenshot is needed for this step.

### Step 5. Telemetry and a real blind playtest before any more tuning

- Files: `game/devtools/scenarios/` (add a `drive_telemetry` scenario if it does not exist; the handling doc says it was not run), `docs/design/HANDLING_2026-11-28.md` (playtest notes).
- What: log per run: lap time, wall hits (count, speed kept), drift count and score, nitro uses, touch steer lag, and collisions per km. Use the capture harness for the render, as required by the project rules.
- Protocol [S] from the dev.to checklist: (a) write the feel in three or four sentences first; (b) hand the phone to two or three new players with no instructions; (c) watch the first two minutes and the first ten seconds of handling; (d) note where they brake, hit walls, and find the drift; (e) freeze the profile and replay it on a greybox track (straight, hairpin, sweeper, chicane, wall).
- Target: two or three of three new players find the drift within the first two minutes without help. [proposal]
- Check: the lead reviews the log. Claims like "feels better" are not accepted without the numbers.

### Lower priority (after steps 1 to 5)

- Move `BODY_FRICTION`, `BODY_BOUNCE` and the turn-in constants into `car_spec.gd`. Known follow-up. [S] handling doc.
- Tilt: add a sensitivity slider and a 3 to 5 deg dead zone. [E] (from the general touch guide, not verified on device).
- Trauma shake: if we want shake on hits, use the Eiserloh model (trauma, cubed, linear decay). [S] archive text. Keep the speed shake as it is.

## 4. Risks and what not to do

- Do not tune drift and body friction at the same time. Step 3 must come first, or the numbers mean nothing.
- Do not make assist so strong that players stop steering. The Asphalt TouchDrive default is for beginners. A hard cap (step 1) is required.
- Do not add counter-steer strength to fix a spin. The Assetto Corsa notes say it causes over-correction. [SN]
- Do not add rubber-band speed to the player. Our research note 06 says never. [S] local note 06 (Pure developers' rule)
- Do not report desktop numbers as phone numbers. Touch lag must be measured on a phone or marked as a PC estimate.
- Do not treat fan-wiki nitro numbers as facts. They are community claims.
- Do not expand the research to Burnout's boost numbers. None were found, and guessing them would waste time.

## 5. Sources

Read in full or in part (S):
1. https://docs.godotengine.org/en/stable/classes/class_physicsmaterial.html (Godot PhysicsMaterial: friction, rough, bounce, absorbent)
2. https://docs.godotengine.org/en/stable/tutorials/physics/using_jolt_physics.html (cited via local note 06)
3. https://archive.org/stream/GDC2016Eiserloh/GDC2016-Eiserloh_djvu.txt (Eiserloh GDC 2016 full text, trauma shake)
4. https://gamermatters.com/need-for-speed-unbounds-new-handling-is-steering-in-the-right-direction-again/ (Unbound drift entry, grip-turn boost on exit)
5. https://invisiblestudio.blogspot.com/2007/07/burnout-paradise-design-boost.html?m=0 (Burnout Paradise boost and E-brake, 2007 preview blog)
6. https://dev.to/juegostudiosofficial/tuning-arcade-car-handling-on-a-small-racing-game-a-playtest-checklist-5a52 (playtest checklist, 10 items)
7. https://www.turgame.com/how-star-wars-galactic-racer-bottled-burnouts-legendary-game-feel-straight-from-ex-criterion-devs/ (only general game-feel points; too long to finish, first 100k characters read)
8. Local: docs/design/HANDLING_2026-11-28.md, docs/research/06-arcade-vehicle-physics-and-ai.md, game/vehicles/arcade_car.gd, game/vehicles/player_driver.gd, game/vehicles/vehicle_input.gd, game/vehicles/specs/noctra_sable.tres, game/project.godot

Search snippets or pages not read in full (SN):
9. https://www.chaptercheats.com/cheat/switch/447597/asphalt-9-legends/hint/157939 (Asphalt 9 control schemes, fan guide)
10. https://en.wikipedia.org/wiki/Need_for_Speed_Unbound (handling slider)
11. https://www.ea.com/news/how-to-drift (returned 404 on fetch)
12. https://github.com/amazing-source/drive-lab/issues/158 (GT counter-steer notes, 0.4 s handback)
13. https://github.com/adam10603/AC-Advanced-Gamepad-Assist/blob/release/ConfigGuide.md (AC drift and race assist profiles)
14. http://www.mathforgameprogrammers.com/gdc2016/GDC2016_Eiserloh_Squirrel_JuicingYourCameras.pdf (primary slides, not read as PDF)
15. https://inairspace.com/blogs/learn-with-inair/godot-touch-controls-for-mobile-a-complete-practical-guide-1 (Godot touch control basics)
16. https://devlog.levi.dev/2022/04/implementing-multi-touch-camera.html (touch smoothing)
17. https://www.yorku.ca/mack/ec2017.html (tilt vs touch, path following)
18. https://www.academia.edu/37542571/Tilt_or_Touch_An_Evaluation_of_Steering_Control_of_Racing_Game_on_Tablet_or_Smartphone (small tilt vs touch study)
19. https://asphalt.fandom.com/wiki/Nitro and https://asphalt.fandom.com/wiki/Drift (fan wikis, nitro and drift)
20. https://github.com/godotengine/godot-proposals/issues/11715 (Godot material combine modes proposal)
21. https://jrouwe.github.io/JoltPhysics/ (Jolt default friction geometric mean; search snippet)
22. https://odr.chalmers.se/server/api/core/bitstreams/46318a38-52af-4ee5-b33d-5d77c200e27c/content (driver assist thesis; fetch failed on size, not read)

Not found or not usable: a Criterion or Burnout GDC talk on boost and drift numbers; public 0-100 or top-speed numbers for Asphalt or NFS; a primary Asphalt or Gameloft nitro formula; the GameAIPro racing chapter (not re-tried, binary PDF).
