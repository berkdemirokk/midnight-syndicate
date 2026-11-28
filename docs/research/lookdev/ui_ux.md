# Premium mobile racer UI/UX: research and recipe for Midnight Syndicate

Scope: main menu, garage and showroom, car customization, career map, event cards, HUD (speed, tach, nitro, position, minimap), results, onboarding. Godot 4.7 Mobile, iOS first.

Confidence key: [S] sourced in this session, [U] unverified or from memory, [C] checked in our code.

Honest limit: web search this session gave thin UI-specific material. The Asphalt and CSR evidence is mostly reviews, not UX teardowns. No public source gave us exact button sizes or HUD layouts for those games. Treat numbers below as targets to test on a real phone, not as facts about those games.

---

## 1. What the best mobile racers do

### 1.1 Players praise and complain (reviews, not UX studies)

- [S] Asphalt 9 reviews praise the look of the game but call it "shockingly hollow" in places. Source: https://www.pocketgamer.com/asphalt-9-legends/asphalt-9-legends-review-totally-gorgeous-shockingly-hollow/
- [S] PocketGamer praised the stripped-back two-button control scheme as the best way to play. Source: https://www.pocketgamer.com/asphalt-9-legends/asphalt-9s-stripped-back-controls-are-the-best-way-to-play-the-game-heres-five-r/
- [S] Players complained that menus, submenus and sub-submenus are hard to navigate, and that the UI was barely changed from mobile on Switch. Source: https://www.pocketgamer.com/articles/076788/r/ (menu complaint) and https://sourcegaming.info/2019/10/08/asphalt-9-legends-switch-review-burning-rubber/
- [S] A later Asphalt rebrand ("Legends Unite") got a UI upgrade in one review, but a fan-wiki page says the new UI was cluttered and less intuitive, with requests to go back to the old UI. This is a weak source (fan wiki). Source: https://shapes.inc/fandom/asphalt-legends/controversies (weak) and https://gamingonphone.com/reviews/asphalt-legends-unite-game-review
- [S] Most major complaints in reviews were about progression and monetization, not the HUD. Source: the same PocketGamer review set above.
- [S] Asphalt patch notes list fixes for overlapping icons across menus and leaderboards. That tells us icon collision is a real, recurring polish problem. Source: Nintendo eShop patch listing via search, https://www.perfectly-nintendo.com/?p=653844
- [S] The default newbie control in Asphalt hides steering behind a two-button mode. Players later asked for manual steering. Lesson: keep a simple default, but make the direct-control option visible in onboarding.
- [S] CSR Racing 2 reviewers say the garage and tuning shop carry the game, more than the races do. Source: https://androidauthority.com/csr-racing-2-now-live-globally-drag-racing-beautiful-graphics-attention-detail-701157 and https://apps.apple.com/us/app/app/id887947640
- [U] We found no public source on CSR2 button sizes or garage layout. Rule of thumb only: the garage is the screen people stay on, so its hierarchy matters most.

### 1.2 Patterns that appear across the genre (mostly [U], from general mobile UX knowledge)

These are common in the genre. Check them with the owner's reference frames and our own captures, not as sourced facts.

- [U] One dominant number on the HUD. Speed is the hero. Our visual target already says "huge italic speed number" (docs/art/VISUAL_TARGET.md). Keep everything else at a much smaller size.
- [U] Thin, colour-coded feedback: a timer badge, a drift banner with one accent colour, and a nitro bar. Avoid more than three accent colours on the HUD at once.
- [U] Full-bleed scene, UI only at the edges. Race UI lives in the top corners and along the bottom third, where thumbs rest.
- [U] Garage as a showroom. Car is the hero, big stat bars sit to the side, and the buy/upgrade button is one clear primary action.
- [U] Event cards show: track photo or colour, car class, reward, and one button. Stars or progress go in a single row.
- [U] Results: one big outcome line, one reward line, one "next" button. Keep the next button in the bottom thumb zone.

---

## 2. What this means in Godot 4.7 Mobile

### 2.1 Safe areas (iPhone)

- [S] Apple says safe areas keep content clear of the corner radius, sensor housings and system elements such as Dynamic Island and the Home indicator. In landscape the safe area is inset from both sides as well as the Home indicator. Source: Apple WWDC layout talk via https://developer.apple.com/videos/play/tech-talks/801/ and HIG layout page https://developer.apple.com/design/human-interface-guidelines/layout.md
- [S] Apple says game UIs should be full-bleed, and should work whichever way the device rotates. Same source family as above.
- [S] Godot 4 exposes `DisplayServer.get_display_safe_area()` returning a `Rect2i`. Source: https://docs.godotengine.org/en/stable/classes/class_displayserver.html
- [S] Community reports say resizing the window to the safe rect does not work on iPhone, and that a simple margin approach can push bottom items off-screen. Source: https://forum.godotengine.org/t/i-tried-to-change-the-window-size-at-runtime-but-it-didnt-work-on-my-iphone/128918 and https://forum.godotengine.org/t/simple-way-to-manage-the-notch-on-ios-and-android-mobile-devices/86971
- [C] We already use this. `game/ui/theme/ms_theme.gd` `safe_insets()` (line ~161) reads `DisplayServer.get_display_safe_area()` and returns left/top/right/bottom insets. `game/ui/hud/race_hud.gd` line ~232 uses those insets. Good. Remaining risk: the function returns zeros or the full screen on some devices, so the HUD must still look right with zero insets.

### 2.2 Touch targets

- [S/U] Apple's layout page gives 44 x 44 pt as the minimum tap target. The fetch returned only the page title, so the number comes from our search snippets and from training. Verify on the live HIG page.
- [C] `game/ui/theme/ms_theme.gd` has `PHONE_BUTTON_H = 124.0`, with a comment "44.6 pt on a 393 pt tall iPhone screen". So the team already targets 44 pt. Good. Check that the buttons in race HUD use this constant and not the desktop size.
- [U] Thumb zones: a one-hand reach zone is roughly the bottom-left and bottom-right quarter of the screen. Put steering, brake and nitro inside it. Put pause and menus at the top. Our touch control code is in `game/vehicles/touch/touch_controls.gd` (224 lines); check its button placement against this.

### 2.3 Control theme and StyleBox performance

- [S] Godot docs say mobile GPUs struggle with overdraw, so stacked UI panels cost fill rate. Source: https://docs.godotengine.org/en/stable/tutorials/performance/gpu_optimization.html
- [S] Godot docs say fewer distinct materials and shaders render faster. Reuse one StyleBox per role, not one per button instance.
- [S] A forum profile on Godot 4.4 Android showed hiding a control tree cut Render Canvas time from 12 ms to 2 ms. Measure before and after. Source: https://forum.godotengine.org/t/trying-to-improve-performance-of-2d-game-on-android/108481
- [U] StyleBoxFlat is generally cheaper than StyleBoxTexture on mobile because it has no texture sample. Not verified in this session; test it with the Godot profiler.
- [C] `game/ui/theme/ms_theme.gd` has a `box()` helper that builds StyleBoxFlat (line ~97). Good. Keep new UI on this helper. Do not add per-frame `StyleBox.new()` calls in `_process`.

### 2.4 Shaders in UI

- [U] A CanvasItem shader on a Control costs one full-rect draw. Use shaders on at most one or two items on screen (for example, the speed number glow). Do not put a blur shader on a whole panel. Blur on a panel is the most likely FPS drop, based on the forum thread about custom window background blur: https://forum.godotengine.org/t/creating-a-custom-window-with-behind-black-transparent-opacity-blurred-background-to-block-input-causing-fps-drop/38379

### 2.5 Haptics

- [U] Godot 4 has `Input.vibrate_handheld(duration_ms)`. Not checked this session against the 4.7 class reference. Check it at https://docs.godotengine.org/en/stable/classes/class_input.html before we rely on it. On iOS, light taps for drift start and nitro full, and no haptic in menus, is a common pattern.

---

## 3. Recipe for our game

Targets are for the iPhone 15-class reference device and a 1920x1080 desktop capture. Each step names the file, the target number and how to check it with the capture harness.

### Step 1. Speed number is the hero

- Files: `game/ui/hud/speed_gauge.gd` (68 lines), `game/ui/hud/race_hud.gd` (817 lines).
- Target: speed digits at least 18% of the screen height, italic (skew 0.2126, which the theme already defines as SKEW_RATIO), bold. Everything else in the HUD at most half that size.
- Check: `godot --path game --audio-driver Dummy --resolution 1920x1080 --position 20000,0 res://devtools/capture_boot.tscn -- --capture=tod_tracks` and view the frame. The speed number should be the first thing the eye lands on. Also run `gameplay_reel`.

### Step 2. One accent per panel, one plate behind every cluster

- Files: `game/ui/theme/ms_theme.gd` (`PLATE_BG`, `box()`).
- Target: each HUD cluster sits on one `PLATE_BG` plate (alpha 0.66). Only one of CYAN, MAGENTA, AMBER per cluster. Drift banner uses MAGENTA. Timer badge uses DANGER or AMBER.
- Check: the `tod_tracks` capture at day and at night (bogaz, maslak, city). Bright sky must not wash the plate out.

### Step 3. Safe frame everywhere, with a fallback

- Files: `game/ui/theme/ms_theme.gd` (`safe_insets()`), `race_hud.gd`, `main_menu.gd`, `results_screen.gd`, `garage_hud.gd`.
- Target: every screen reads insets once at start and applies them to its outer margin. With zero insets (desktop) the layout must be the same as with `SAFE_MARGIN_PX = 24`.
- Check: capture at 1920x1080 and at a phone-like size with a forced safe area (add a debug override in `safe_insets()` only if the capture harness needs it). No text under the top notch or bottom Home bar.

### Step 4. Thumb-zone controls at 44 pt minimum, measured in Godot pixels

- Files: `game/vehicles/touch/touch_controls.gd`, `game/ui/theme/ms_theme.gd` (`PHONE_BUTTON_H`, `button_h()`).
- Target: every touch button at least `PHONE_BUTTON_H` (124 px on the phone boost path, which is 44.6 pt). Steering and brake in the bottom quarters. Pause at top centre.
- Check: a unit test in `game/tests/run_tests.gd` that asserts every touch control's rect size is at least `button_h()` and sits inside the safe frame. Run with `godot --headless --fixed-fps 60 --path game -s res://tests/run_tests.gd`.

### Step 5. Garage as a showroom: hero car, one primary button, stat bars at the side

- Files: `game/ui/garage/garage.gd`, `garage_hud.gd` (684 lines), `garage_stats.gd`, `garage_orbit.gd`.
- Target: car takes at least 55% of the screen width in the three-quarter view. Stats in a single column on the right, max 4 bars. One primary button (Buy / Upgrade) in the bottom thumb zone, using `MSTheme.PRIMARY_FILL`.
- Check: `car_studio_<id>` captures for two cars, plus the garage capture. Look at the frame, do not trust the numbers alone.

### Step 6. Results and events: one outcome line, one reward, one next button

- Files: `game/ui/menus/results_screen.gd` (566 lines), `event_select.gd`.
- Target: result title at SIZE_HEAD (40), reward at SIZE_BODY (24), a single "Next" button in the bottom thumb zone. Event cards: track image or colour strip, class badge, reward, one button.
- Check: capture the results screen at 1920x1080. Count the buttons: one primary, at most one secondary.

### Step 7. Onboarding teaches the one thing that matters

- Files: `game/ui/menus/onboarding.gd`, `game/ui/hud/onboarding_hints.gd`.
- Target: three hints max in the first race: steer, brake or drift, nitro. Each hint disappears after the player does the action once. Add a visible "manual steering" hint in the first session, because Asphalt players asked for it.
- Check: a headless test that feeds the hint trigger and asserts the hint is removed after one action.

### Step 8. Measure UI cost before and after

- Target: with the HUD up, the UI should add no more than 2 ms to the Render Canvas step on the reference desktop. Record it in PROGRESS.md with the machine name. Desktop numbers are never reported as iPhone numbers.
- Check: Godot profiler (Debugger, Profiler) during `gameplay_reel`, toggling the HUD off and on.

---

## 4. Risks and what not to do

- Do not add blur or frosted-glass shaders on full panels. Overdraw on mobile is the first cost.
- Do not hard-code screen sizes. Use `safe_insets()` and `k()` (the scale helper in ms_theme.gd).
- Do not repeat the Asphalt trap: deep menus, hidden controls, and a UI redesign that removes what players already know. Keep the garage path to two taps to race.
- Do not show a feature that is not usable yet. A greyed-out button needs one line of why.
- Do not rely on `window.set_size` for iPhone safe area (the forum reports say it fails). Use the margin approach through `safe_insets()`.
- Do not put text below 18 px (SIZE_SMALL) on a HUD. It is unreadable while driving.
- Do not claim any UI number is "from Asphalt" or "from CSR". We have no sourced numbers for them.
- Do not treat the fan-wiki or Reddit claims as evidence. They are weak.
- Haptics: keep them off by default in menus. Test on a real iPhone before shipping. The desktop capture cannot show haptics.
- Do not call the UI done without a real capture from the harness that was looked at (CLAUDE.md rule).

---

## 5. Sources

- PocketGamer, Asphalt 9 Legends review (hollow): https://www.pocketgamer.com/asphalt-9-legends/asphalt-9-legends-review-totally-gorgeous-shockingly-hollow/
- PocketGamer, Asphalt 9 stripped-back controls: https://www.pocketgamer.com/asphalt-9-legends/asphalt-9s-stripped-back-controls-are-the-best-way-to-play-the-game-heres-five-r/
- PocketGamer, Asphalt 9 review (Switch menus): https://www.pocketgamer.com/articles/076788/r/
- Source Gaming, Asphalt 9 Switch review: https://sourcegaming.info/2019/10/08/asphalt-9-legends-switch-review-burning-rubber/
- GamingonPhone, Asphalt Legends Unite review: https://gamingonphone.com/reviews/asphalt-legends-unite-game-review
- Fan wiki, Asphalt Legends controversies (weak source): https://shapes.inc/fandom/asphalt-legends/controversies
- Nintendo eShop patch listing (overlapping icons): https://www.perfectly-nintendo.com/?p=653844
- Android Authority, CSR Racing 2 launch: https://androidauthority.com/csr-racing-2-now-live-globally-drag-racing-beautiful-graphics-attention-detail-701157
- Apple HIG, Layout: https://developer.apple.com/design/human-interface-guidelines/layout.md
- Apple HIG, Designing for games: https://developer.apple.com/design/human-interface-guidelines/designing-for-games
- Apple WWDC layout talk (safe areas, landscape): https://developer.apple.com/videos/play/tech-talks/801/
- Godot docs, DisplayServer: https://docs.godotengine.org/en/stable/classes/class_displayserver.html
- Godot docs, GPU optimization: https://docs.godotengine.org/en/stable/tutorials/performance/gpu_optimization.html
- Godot docs, Input (vibrate_handheld, not checked): https://docs.godotengine.org/en/stable/classes/class_input.html
- Godot forum, Android 2D profiling (12 ms to 2 ms): https://forum.godotengine.org/t/trying-to-improve-performance-of-2d-game-on-android/108481
- Godot forum, iPhone window size fails: https://forum.godotengine.org/t/i-tried-to-change-the-window-size-at-runtime-but-it-didnt-work-on-my-iphone/128918
- Godot forum, notch management: https://forum.godotengine.org/t/simple-way-to-manage-the-notch-on-ios-and-android-mobile-devices/86971
- Godot forum, custom window blur FPS drop: https://forum.godotengine.org/t/creating-a-custom-window-with-behind-black-transparent-opacity-blurred-background-to-block-input-causing-fps-drop/38379
- Local: docs/art/VISUAL_TARGET.md, game/ui/theme/ms_theme.gd, game/ui/hud/race_hud.gd, game/vehicles/touch/touch_controls.gd

Not read in full this session (time): docs/research/01..07, BENCHMARK_MATRIX_2026-11-28.md, REA_ANALYSIS.md, GRAPHICS_BENCHMARK.md. Check those before acting, in case they already settle HUD or touch sizes.
