# Store screenshot plan (iPhone, landscape)

Status: PLAN ONLY. No screenshot for the store has been captured or approved by this document.

## Rules

- Every store screenshot must be a real capture from the game, taken with the project's capture harness (game/devtools/capture.gd). Mock scenes (ui_results_mock, ui_hud_mock, ui_mock_race, ui_mock_track) show fake data and are not used for the store.
- Each capture is looked at before it is used. A screenshot is not accepted on size alone.
- Captures show what the build renders on the dev PC. They say nothing about how the game looks or runs on an iPhone. Replace them with device captures if the device shows a difference, and say so in the store notes.
- No debug overlays, FPS counters, dev menus or test profile names in the frame. Check each frame for these before approval.
- Captions must describe only what is on screen and only features in the 1.0 list. No claims about performance, graphics quality rankings or "realistic" rendering.
- The owner approves every frame and caption before upload (RELEASE_CHECKLIST.md step 26).

## Sizes

| Device class (App Store Connect) | Pixel size, landscape | Harness argument |
|---|---|---|
| 6.9-inch iPhone | 2868 x 1320 | `--size=2868x1320` |
| 6.5-inch iPhone | 2778 x 1284 | `--size=2778x1284` |

These two sizes are the ones named in the brief. Check them against the sizes App Store Connect accepts on the day of upload. The accepted sizes are not verified here.

Older checklist note: RELEASE_CHECKLIST.md step 26 lists 1179 x 2556 and 1206 x 2622, which are portrait sizes. This plan is landscape, so that step must be updated to landscape sizes before upload.

## Command

Run from the repository root. Use the Godot binary outside the repo, as CLAUDE.md says. The harness opens off-screen and silent.

```
C:\Users\berk\tools\godot\Godot_v4.7.2-stable_win64_console.exe --path game --audio-driver Dummy --resolution 1920x1080 --position 20000,0 res://devtools/capture_boot.tscn -- --capture=<scenario> --size=2868x1320 --preset=high
```

Repeat with `--size=2778x1284` for the 6.5-inch set. The harness writes PNGs to `evidence/screens/<scenario>/`. Copy approved frames into a store folder only after the owner approves them.

Before each scenario, check that the time of day and track in the output match the caption. Scenario defaults are not confirmed here: the time of day each race scenario uses must be read from its script (for example in game/devtools/scenarios/race_bogaz.gd) or from the event data in game/race/events.gd.

## Shot list

Six shots per device size, which fits Apple's 1 to 10 limit (RELEASE_CHECKLIST.md step 26 [S]). Order matters: the first two are what most people see.

| # | Shot | Scene and capture | What to check before approval | EN caption | TR caption |
|---|---|---|---|---|---|
| 1 | Night race on the Bogaz coast road | `race_bogaz`, shot `racing_10s_high` (or the night capture in `tod_tracks`, shot `bogaz_night`) | Night lighting, car and coast road in frame, HUD readable, no debug text. Confirm the scene is night. | Night race on the Bogaz coast road. | Boğaz sahil yolunda gece yarışı. |
| 2 | Daytime race through Maslak | `race_maslak`, shot `racing_10s_high` (or `tod_tracks`, shot `maslak_day`) | Daylight, towers in frame, the car is not clipped. Confirm the scene is day. | Daytime race through the Maslak towers. | Maslak kulelerinin arasında gündüz yarışı. |
| 3 | Drift and nitro in Arden Bay | `race_city`, shots `drift` and `racing_nitro` | Drift smoke and nitro flame visible, car not clipped into the road. | Drift to fill the nitro, then burst ahead. | Drift yap, nitroyu doldur, öne geç. |
| 4 | Garage: paint, rims and upgrades | `garage` (paint tab), and a rims or upgrades tab shot if the scenario provides one | The car is the one the game names, the tab labels are in the chosen language, no empty prices. | Paint, rims and upgrades in the garage. | Garajda boya, jant ve yükseltmeler. |
| 5 | Career: ten events in two places | `ui_event_select` | Real event select screen on a test save. Event names and star display match the game. The profile name is not visible. | Career: ten events in Arden Bay and Istanbul. | Kariyer: Arden Bay ve İstanbul'da on etkinlik. |
| 6 | Results with stars | `race_city`, shot `results`, from a real finish | Results table and stars come from a real race, not `ui_results_mock`. Stars match the rule for the position. | Results: stars for position and for time. | Sonuçlar: konuma ve süreye göre yıldız. |

Notes on the list:

- Shot 6 must come from a real race. The current scenario list has `ui_results_mock`, which uses fake names and is not allowed for the store.
- Shot 5 uses a test save, which is fine. The frame must not show a test name, a debug label or a stale cash figure.
- If a shot shows a time of day or track that does not match its caption, change the caption or the scene. Do not keep both.
- An optional seventh shot (main menu, `ui_main_menu`) can show the Turkish or English language choice. It is not in the plan because it is a menu, not gameplay. Add it only if the owner wants it.

## Caption rules

- EN and TR captions are one line each, about 40 characters or fewer, so they fit on a store frame.
- Both captions must describe the same thing. If the Turkish caption needs a different wording, keep the meaning, not the words.
- Captions do not name real brands, real cars or real places beyond the fictional Istanbul-inspired circuits and the Bosphorus-inspired Bogaz road.

## Still open

- The exact time of day and rain state of each race scenario is not confirmed here.
- The accepted App Store Connect sizes are not verified here.
- No device capture exists yet. Store frames come from the dev PC capture harness, and that is stated in the store notes.
- RELEASE_CHECKLIST.md step 26 needs its portrait sizes changed to landscape before use.
