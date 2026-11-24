# 06 Arcade Vehicle Physics and AI (Godot 4 focus)

Date: 2026-11-24. Tags: [S] = read in the source during this run. [E] = estimate, inference, or claim from a search snippet / unread source (unverified). Ranges marked [E] are starting points to tune, not facts.

## Sources

| URL | What it gave | Loaded |
|---|---|---|
| https://docs.godotengine.org/en/stable/classes/class_vehiclewheel3d.html | VehicleWheel3D defaults (stiffness 5.88, max force 6000, friction slip 10.5, roll influence 0.1, damping 0.83/0.88, radius 0.5), N/mm units, realism warning | yes |
| https://docs.godotengine.org/en/4.2/classes/class_vehiclewheel3d.html | Older page: wheel_friction_slip 1.0 = normal grip guidance | no (search snippet only) |
| https://docs.godotengine.org/en/stable/tutorials/physics/using_jolt_physics.html | Jolt added as opt-in in 4.4; "new projects will use it by default"; kinematic contact caveat; RigidBody3D limits | yes |
| https://github.com/Dechode/Godot-AdvancedVehicle | MIT license; custom RigidBody3D car controller, self-described as more realistic than built-in VehicleBody | yes |
| https://godotengine.org/asset-library/asset/2558 | Godot Easy Vehicle Physics: MIT, v1.0.9, arcade-leaning demos, keyboard-friendly | no (search snippet only) |
| https://doc.photonengine.com/quantum/v2/game-samples/arcade-racing/ai | "Chase the rabbit" AI: target on baked line, runs at max speed, line points carry speed multiplier | yes |
| https://www.gameaipro.com/GameAIPro/GameAIPro_Chapter38_An_Architecture_Overview_for_AI_in_Racing_Games.pdf | GameAIPro ch.38 racing AI architecture | attempted, failed (binary PDF, no text extracted) |
| https://gamedeveloper.com/design/the-pure-advantage-advanced-racing-game-ai | Black Rock Pure AI: skills in [0..1], DCB, rejected rubber banding, target-point offsets, last-20% modifier fade, lap bonuses | yes |
| https://gamedeveloper.com/design/rubber-banding-as-a-design-requirement | Rubber banding as core-mechanic design (Split/Second, Mario Kart contrast) | yes |
| https://www.mcvuk.com/development-news/black-rock-studio-blasts-arubber-bandinga/ | Black Rock criticism of rubber banding | no (search snippet only) |
| https://publications.ri.cmu.edu/implementation-of-the-pure-pursuit-path-tracking-algorithm | Coulter 1992 CMU-RI-TR-92-01, pure pursuit implementation and parameter insights | no (search snippet only; copyright notice, do not repost PDF) |
| https://gamedeveloper.com/programming/video-sprucing-up-cameras-with-math | Summary of Eiserloh GDC 2016 camera-math talk; no shake formula on page | yes |
| https://gdcvault.com/play/1023146/Math-for-Game-Programmers-Juicing | Eiserloh GDC 2016 "Juicing Your Cameras With Math" (trauma/shake content) | no (login notice; not read) |
| https://en.wikipedia.org/wiki/Need_for_Speed:_Most_Wanted_(2005_video_game) | Heat escalation (roadblocks, spikes, helicopters), backup delay, Pursuit Breakers, cooldown with no duration | yes |
| https://www.unrealengine.com/developer-interviews/three-fields-entertainment-explains-how-they-evolved-burnout-arcade-racing-formula-dangerous-driving | Drift design in Dangerous Driving (not Burnout Paradise) | no (search snippet only) |
| https://www.researchgate.net/profile/Muhammad-Suhaib-6/publication/328127724_Tilt_or_Touch_An_Evaluation_of_Steering_Control_of_Racing_Game_on_Tablet_or_Smartphone | "Tilt or Touch" steering study on tablet/phone | no (search snippet only) |
| https://www.droidgamers.com/news/poll-do-you-prefer-using-tilt-to-steer-or-on-screen-navigation-buttons-for-racing-titles/ | Informal reader poll tilt vs on-screen | no (search snippet only) |
| https://toucharcade.com/community/threads/how-do-you-prefer-to-steer-in-a-car-game.173404/ | Forum discussion: tilt preferred for behind-car view, dpad/wheel for top-down | no (search snippet only) |
| https://docs.godotengine.org/en/stable/classes/class_path3d.html | Path3D owns Curve3D; curve should start at origin; curve_changed signal | yes |
| https://github.com/Janorico/Vehicle | Open-source vehicle project (license not verified) | no (search snippet only) |
| https://en.wikipedia.org/wiki/Magic_formula | Wrong page (disambiguation, no tire formula) | yes (useless) |
| https://en.wikipedia.org/wiki/Pacejka%27s_Magic_Formula | Pacejka tire model | failed (HTTP 404) |

Failed or unusable: GameAIPro ch.38 PDF (no text extracted); Pacejka Wikipedia page (404; the "Magic formula" page was a disambiguation); GDC Vault pages (login notice). Not retried.

## Architecture choice: VehicleBody3D vs custom RigidBody3D vs kinematic

1. Godot's VehicleWheel3D docs warn the class "has known issues" and is not designed for realistic vehicle physics; the docs suggest your own integration with another PhysicsBody3D when you need more. [S] https://docs.godotengine.org/en/stable/classes/class_vehiclewheel3d.html
2. Recommended for this project: RigidBody3D with your own raycast suspension, tire forces applied via apply_force/apply_torque at each contact. Gives control over grip, drift and anti-roll without fighting the built-in wheel model. [E] Community example of this approach: Dechode AdvancedVehicle (MIT, RigidBody3D). [S] https://github.com/Dechode/Godot-AdvancedVehicle
3. Fully kinematic car (CharacterBody3D / manual integration): cheapest and most predictable on iPhone and easiest to tune for arcade feel; loses rigid-body interactions (crashes, impulses). [E] Pick this if crash physics is not core.
4. Jolt: opt-in in 4.4, and the stable docs say new projects use it by default. The page does not name the release for the switch; check your project's Physics > 3D > Physics Engine setting on 4.7.2. [S] https://docs.godotengine.org/en/stable/tutorials/physics/using_jolt_physics.html
5. Jolt caveat: a RigidBody3D frozen with FREEZE_MODE_KINEMATIC does not report contacts with static/kinematic bodies by default (performance). Enable "Generate All Kinematic Contacts" if you rely on it. Contact impulses are estimates. [S] same URL
6. Mobile cost [E]: keep the physics body count low (one car body plus AI bodies only in view), 4 raycasts per car, physics tick 60 Hz, and drop AI to kinematic beyond a distance.

## Suspension (spring-damper)

Force per wheel: F = k·x + c·v, with x = compression (m), v = compression rate (m/s), k = stiffness, c = damping. Clamp F to >= 0 and to a max force. [E]

Godot values (VehicleWheel3D, but usable as reference for your own raycast suspension):
- suspension_stiffness default 5.88, unit N/mm. Guidance: under 50 off-road, 50–100 race cars, about 200 for F1-style. [S] https://docs.godotengine.org/en/stable/classes/class_vehiclewheel3d.html
- suspension_max_force default 6000; should exceed a quarter of vehicle mass, often 3–4x that. [S] same URL
- damping_compression: about 0.3 normal car, 0.5 race car; damping_relaxation slightly higher than compression. [S] same URL
- Arcade starting point [E]: stiffness 60–90 N/mm equivalent, damping ratio 0.6–0.8 (critical damping = 1.0), ride height 0.12–0.20 m, spring rest length 0.3–0.4 m. Tune by feel.

Damping ratio: zeta = c / (2·sqrt(k·m)). Compute c from zeta, k and per-corner mass to avoid bouncing on iPhone frame jitter. [E]

## Tire grip (simplified)

Per wheel, compute slip angle alpha = atan2(v_lat, |v_long|) (speed in wheel frame). Lateral force Fy = -mu · Fz · f(alpha), where f is a bounded curve that rises, peaks, then falls slightly (a Pacejka-like shape). [E] Pacejka magic formula (not verified from a source this run): y = D·sin(C·atan(B·x − E·(B·x − atan(B·x)))). [E]

Arcade simplification [E]:
- Peak slip angle 6–10 degrees, falloff to 70–80% of peak at 2x peak.
- mu about 1.0–1.3 on asphalt, 0.6–0.7 when drifting or on wet tiles.
- Longitudinal force from throttle capped by available friction: F_long² + F_lat² <= (mu·Fz)² (friction circle).
- Grip multiplier applies per surface; Godot's wheel_friction_slip (default 10.5 in stable docs) combines with surface friction [E]. [S] VehicleWheel3D docs. The 4.2 docs say 0.0 = no grip, 1.0 = normal grip, and suggest starting at 1.0, yet also list default 10.5 [S, 4.2 page: https://docs.godotengine.org/en/4.2/classes/class_vehiclewheel3d.html]. The stable description text was not read, so a version conflict is [E]. Verify on 4.7.2 by test.

## Arcade drift model

Standard arcade approach [E] (no source read for this run; Burnout Paradise drift scoring not found):
- Handbrake or steer+brake: rear lateral grip multiplier drops to 0.3–0.5 for the drift window; front grip stays near 0.9–1.0 so steering still bites.
- Counter-steer assist: yaw rate target blended toward angle-to-velocity; assist strength 0.2–0.5.
- Drift angle clamp: cap body slip angle at 45–60 degrees; beyond that, add yaw damping.
- Drift scoring: score rate = |slip angle| · speed_factor · (time in drift); bank on exit when slip below 15 degrees and speed above 40 km/h, lose combo on wall hit or grip recovery under 5 s.
- Speed-sensitive steering: max steer angle = base · lerp(1.0, 0.35, speed / v_max), v_max about 300 km/h. [E]

Burnout-style boost/drift design: no verified public numbers this run; the Three Fields interview snippet covers Dangerous Driving only. [E]

## Speed-sensitive steering and downforce/anti-roll

- Steering: steer_angle = max_angle · (1 − 0.65 · t) with t = clamp(speed / v_max, 0, 1). Rate limit 3–6 rad/s with a touch-input smoothing of 0.1 s. [E]
- Downforce: F_down = 0.5 · rho · Cd_lift · A · v² with arcade multiplier; use 0.3–1.0 of real value. Apply at car center of mass. [E]
- Anti-roll: per axle, spring force difference between left and right wheels, k_arb about 0.5–2x suspension stiffness. Bars keep the body flat in corners. [E]

## Nitro

- Force boost: add forward force F = m · a_boost with a_boost 4–8 m/s² for 1.5–3 s, capped at a top speed that rises by 10–20%. [E]
- FOV kick: fov tween from base 70 deg to base + 8–12 over 0.2 s, return over 0.6 s. [E]
- Refill rules: drift-score or near-miss gains charge; charge caps at 1.0; no refill while braking. [E]

## Chase camera

- Spring arm: follow position with critically damped spring (smooth time 0.15–0.3 s). Look-ahead: target = car_pos + car_vel · 0.3 s, clamped to 4 m. [E]
- Dynamic FOV: fov = base + k·max(0, speed − v0), k about 0.04–0.08 deg per km/h. [E]
- Trauma shake (Eiserloh GDC 2016 talk, formula not read this run): shake = trauma²; roll and offset = max · shake · noise(t); trauma decays linearly at 1.0–1.5 per s; add on crash and nitro. [E] Talk: https://gdcvault.com/play/1023146/Math-for-Game-Programmers-Juicing (not read). Summary page: https://gamedeveloper.com/programming/video-sprucing-up-cameras-with-math [S] (confirms topic only, no formula).

## Touch controls

- Schemes to offer [E]: tilt (accelerometer), tap-steer (left/right zones), slider steer with auto-accelerate, and a virtual wheel. Default to auto-accelerate; brake and nitro are separate buttons.
- Preference evidence [E, snippets only, not opened]: small lab studies found tilt scored higher on immersion and natural mapping; a 2013 forum poll gave tilt 60% (12 votes); top-down or isometric players preferred dpad or wheel. Treat as directional only.
- Design rule [E]: ship at least two steering modes and a steering sensitivity slider; add dead zone 3–5 degrees on tilt.

## Racing AI: path following

- Path3D with Curve3D: the curve should start at (0,0,0) relative to its PathFollow3D children. [S] https://docs.godotengine.org/en/stable/classes/class_path3d.html
- Curve3D lookup helpers (get_closest_offset, sample_baked) are documented on the Curve3D page, not read this run. [E]
- Racing line: store per-node speed multiplier and difficulty. Photon's arcade sample attaches both to line points on a baked line; its rabbit offset comes from AIConfig, not a per-node lateral offset (the −1..1 range is not in the source). [S] https://doc.photonengine.com/quantum/v2/game-samples/arcade-racing/ai
- Pure pursuit steering [E, Coulter 1992]: delta = atan(2·L·sin(alpha) / Ld), L = wheelbase, alpha = angle from car heading to look-ahead point, Ld = look-ahead distance. Ld = clamp(k·speed, 6, 30) m with k about 0.5 s. Coulter's report discusses the parameter effects (not read). https://publications.ri.cmu.edu/implementation-of-the-pure-pursuit-path-tracking-algorithm (snippet only)
- Chase-the-rabbit variant: invisible target snapped ahead of car when too far; target speed = max speed, slowed when car is close to it. [S] Photon page above.

## Racing AI: target speed, overtaking, avoidance

- Target speed per node [E]: v_target = min(v_curve, v_max_ai), v_curve = sqrt(a_lat_max · R), a_lat_max about 0.8·mu·g (about 7–9 m/s² for arcade). Add braking lookahead of 40–80 m.
- Overtaking [S, Pure]: AI pass the player early, then deliberately give up the lead so the player seems to earn passes. Passing needs a side-lane offset of 2–4 m and an obstacle-avoid steer (soft repulsion from nearby cars). [E] for the numbers.
- Avoidance [E]: raycast or sphere cast ahead; if blocked, shift lateral offset away from obstacle; brake if closing speed above threshold.

## Rubber band and fairness

- Pure's developers rejected classic rubber banding because the speed changes are easy to spot and make the unfairness obvious. [S] https://gamedeveloper.com/design/the-pure-advantage-advanced-racing-game-ai
- Instead, Pure used skills in [0..1] (clamped), a race-state offset per AI, and a dynamic competition model with target offsets to the player (for example, a middle group that is +250 m at race start and −250 m at the end; capped shift of 150 m per update). [S] same URL
- Lap bonus: +0.05 in lap 1, +0.025 in lap 2, 0 in lap 3. [S] same URL; the article gives these as a three-lap example, not fixed Pure settings.
- Last 20% of race: skill modifier shrinks to 0 by finish; AI recover less from mistakes. [S] same URL
- Rubber band fairness rule [E]: adjust AI top speed by ±3–5% and only when the gap is above 4 s; never boost AI on a mistake the player made in front; never rubber-band the player directly. Split/Second used a "power play" design where the leader is pulled back. [S] https://gamedeveloper.com/design/rubber-banding-as-a-design-requirement
- Black Rock criticised rubber banding publicly and avoided the term. [S/E] Search snippet only: https://www.mcvuk.com/development-news/black-rock-studio-blasts-arubber-bandinga/ ([E])

## Police pursuit AI

- Heat rises from offences and repeated evasion; escalation adds roadblocks, spike strips, helicopters, then SUVs and federal units. Backup can arrive after a delay when only one car chases. [S] https://en.wikipedia.org/wiki/Need_for_Speed:_Most_Wanted_(2005_video_game)
- Losing pursuit: evade, disable (ram), or trigger pursuit breakers; once no active pursuers remain, a cooldown runs while the player stays unseen. Cooldown is longer at higher heat and shorter when hiding in marked spots. No duration given. [S] same URL
- State machine [E]: Patrol -> Suspect (sight cone, 3 s) -> Pursue (chase within 150 m) -> Intercept (PIT/ram, aim at predicted position 0.5–1.5 s ahead) -> Roadblock (triggered at heat >= 3, spawn 2–3 units across lane) -> Escape (no sight 10–15 s, cooldown 20–40 s) -> Busted (speed below 15 km/h and surrounded, or damage threshold).
- Bust meter [E]: fills 0–100 while in pursuit with contact and proximity to units; decays when out of sight. Bust at 100; fill rate 10–25/s when surrounded.
- Heat levels [E]: 5 tiers, tier thresholds 20/40/60/80 points; each tier adds one unit type. Numbers from the 2005 game are not verified here.
- PIT and ram [E]: PIT needs the target side-on at below 80 km/h; cars take a lateral impulse; ram only when relative speed is above 30 km/h.

## Priority for this project (decisions)

1. Build the car on RigidBody3D with custom raycast suspension, not VehicleBody3D. [S]+[E]
2. Test wheel_friction_slip on 4.7.2 by a short sweep; do not trust either default. [S]
3. Start arcade grip with the friction-circle model and drift as rear-grip scale; tune by feel. [E]
4. Use Path3D/baked lines with per-node speed and chase-rabbit steering; expose lookahead as a tuning value. [S]+[E]
5. Build rubber band as skill offsets capped per update, no direct speed boost on the player. [S]
6. Ship two touch steering modes minimum (tilt and slider). [E]
7. Use bust meter and cooldown as state machine; heat tiers tuned by playtest. [S]+[E]
8. Confirm Jolt setting in project; enable kinematic contacts only if needed. [S]

Open gaps: Burnout Paradise drift scoring not found; Pacejka source not loaded; GameAIPro ch.38 not extracted; GDC Pure talk and Eiserloh trauma formula not read; Godot Easy Vehicle Physics and Janorico repo licences unverified.

## Verification pass

Checker: independent re-read of the cited sources on 2026-11-24. Eight high-cost claims selected; a ninth (Photon line) was added because it was wrong and found during the check. Verdict key: confirmed = read in source; corrected = fixed in place; unverifiable = retagged [E].

| # | Claim (line) | Verdict | Source |
|---|---|---|---|
| 1 | VehicleWheel3D defaults: stiffness 5.88, max force 6000, friction slip 10.5, damping 0.83/0.88 (L47, L63) | confirmed [S] | https://docs.godotengine.org/en/stable/classes/class_vehiclewheel3d.html |
| 2 | Stiffness in N/mm; under 50 off-road, 50–100 race, about 200 F1 (L48) | confirmed [S] | https://docs.godotengine.org/en/stable/classes/class_vehiclewheel3d.html |
| 3 | Max force above a quarter of mass, often 3–4x (L49) | confirmed [S] | https://docs.godotengine.org/en/stable/classes/class_vehiclewheel3d.html |
| 4 | Damping about 0.3 normal, 0.5 race; relaxation higher than compression (L50) | confirmed [S] | https://docs.godotengine.org/en/stable/classes/class_vehiclewheel3d.html |
| 5 | Jolt opt-in in 4.4; new projects use it by default (L4, L39) | confirmed [S]; source says "will use" | https://docs.godotengine.org/en/stable/tutorials/physics/using_jolt_physics.html |
| 6 | Dechode AdvancedVehicle is MIT and more realistic than built-in VehicleBody (L37) | confirmed [S]; README says "rigidbody controller", RigidBody3D not named | https://github.com/Dechode/Godot-AdvancedVehicle |
| 7 | Pure lap bonus +0.05 / +0.025 / 0 (L118) | corrected: article gives it as a three-lap example, not fixed settings; framing fixed in place | https://gamedeveloper.com/design/the-pure-advantage-advanced-racing-game-ai |
| 8 | wheel_friction_slip: 1.0 = normal grip, start at 1.0 (L63) | 1.0 guidance confirmed [S] on 4.2 page, which also lists default 10.5; "scale conflicts between versions" unverified, retagged [E]. Stable description text not read | https://docs.godotengine.org/en/4.2/classes/class_vehiclewheel3d.html |
| 9 | Extra: Photon sample does per-node lateral offset (−1..1) and "exactly this" (L104) | corrected: source has per-point speed multiplier and difficulty; rabbit offset comes from AIConfig | https://doc.photonengine.com/quantum/v2/game-samples/arcade-racing/ai |

Counts: checked 9, confirmed 6, corrected 2, unverifiable 1.

Corrections:
- L63: 4.2 page read directly, tagged [S]; version-conflict claim retagged [E].
- L104: removed per-node lateral offset and "does exactly this"; restated to what the source says.
- L118: lap bonus marked as a three-lap example, not Pure's fixed settings.

Not checked this pass: all other [S] and [E] claims, including Path3D, Jolt kinematic contacts, Pure middle-group offsets (+/-250 m, 150 m cap), and the Need for Speed heat tiers.
