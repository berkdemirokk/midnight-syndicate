# MIDNIGHT SYNDICATE - iOS release checklist

Status key: **not started** | **drafted** (file exists, never run) | **done** (evidence exists).
Cost key: **free** | **paid** (Apple program $99/yr [S]) | **uses free quota** (GitHub Actions or Codemagic minutes).
macOS: needs macOS for the step (yes/no). Export needs macOS [S]. Preset creation on Windows is unverified.
Tags: [S] = in docs/research/07-ios-release-and-ci.md. [E] = estimate or search snippet. unverified = not in that file.
Bundle identifier placeholder: `com.example.midnightsyndicate` (**owner must choose**).

## Steps only the account owner can do

- Choose repo visibility (public or private). It changes Actions cost [E].
- Choose the Mac path: GitHub macOS runner, Codemagic (500 min/mo [S]), or a borrowed Mac.
- Choose the bundle identifier and app name. Run the trademark and name check (not done, unverified).
- Enroll in the Apple Developer Program ($99/yr [S]) and accept the agreement [S].
- Create the App Store Connect app record, API keys and any sandbox testers.
- Create the distribution certificate, App Store provisioning profile and GitHub repository secrets [E].
- Approve the roughly 1.28 GB export template download before any CI run that downloads it.
- Trigger every manual workflow run (build-windows, build-ios). Push to the repo.
- Answer the age rating questionnaire, privacy labels and export compliance in App Store Connect [S][E].
- Publish the privacy policy at a public URL (hosting choice is owner's).
- Run the real iPhone tests and the 20+ minute thermal sessions. Decide on any IAP products.
- Invite TestFlight testers, approve each build for external testing, submit for review, press publish [E].

## Ordered steps (each step blocks the ones below it)

| # | step | owner | needs macOS | cost | status | evidence required to tick |
|---|---|---|---|---|---|---|
| 1 | Decide repo visibility (public or private) | owner | no | free | not started | owner note in writing; sets Actions cost [E] |
| 2 | Choose bundle identifier (placeholder com.example.midnightsyndicate) | owner | no | free | not started | final ID typed into iOS preset and App Store Connect |
| 3 | Choose app name; trademark and name check | owner | no | free | not started | search record (unverified check) |
| 4 | Decide Mac path: GitHub macOS (private: about 10x minutes [E]), Codemagic 500 min/mo [S], or borrowed Mac | owner | yes | uses free quota or free | not started | written decision |
| 5 | Enroll in Apple Developer Program and accept agreement | owner | no | paid | not started | Apple membership confirmation [S] |
| 6 | Create App Store Connect app record for the bundle ID | owner | no | free | not started | app record ID saved in owner notes |
| 7 | ci.yml logic-tests job (Godot 4.7.2 Linux, SHA512 check, headless tests) | agent (drafted) | no | uses free quota | drafted | green Actions run link and test-results artifact |
| 8 | Owner pushes branch so ci.yml runs; fix first-run failures | owner (push) | no | uses free quota | not started | passing run with test_results.json |
| 9 | ci.yml asset-validation job: tools/asset_factory.py is missing | agent | no | free | not started | job log shows validate ran, not the skip notice |
| 10 | Owner approves about 1.28 GB export template download | owner | no | free (download bandwidth unverified) | not started | written approval in owner notes |
| 11 | Create game/export_presets.cfg with "Windows Desktop" preset in the Godot editor | owner or lead | no | free | not started | preset file exists in repo |
| 12 | build-windows.yml manual run (exits 0 with a notice if no preset) | owner (trigger) | no | uses free quota | drafted | windows-build artifact, or the notice log while preset is absent |
| 13 | Create iOS preset (name "iOS") with bundle ID, Team ID, privacy block, icons, launch storyboard | lead or owner | no (creation on Windows unverified; export needs macOS [S]) | free | not started | game/export_presets.cfg has name="iOS" |
| 14 | Icon set: 1024x1024 master, square, no transparency [E] | agent drafts art, owner approves | no | free | not started | icon files and Xcode AppIcon output |
| 15 | Launch screen: custom background colour and @2x/@3x image | agent drafts, owner approves | no | free | not started | exported storyboard shows correctly on iPhone |
| 16 | Confirm privacy manifest: does Godot write PrivacyInfo.xcprivacy? | agent | yes | uses free quota | not started | exported project file list and contents |
| 17 | Set ITSAppUsesNonExemptEncryption = NO after confirming encryption use [E] | owner confirms, agent edits | yes (verify in exported plist) | free | not started | Info.plist key in exported project |
| 18 | build-ios.yml unsigned archive (manual, owner confirms each run) | owner (trigger) | yes | uses free quota (macOS about 10x [E]) | drafted | ios-build artifact and xcodebuild log with archive SUCCEEDED |
| 19 | Confirm runner Xcode version meets the upload rule (Xcode 26 / iOS 26 SDK [E]) | owner | yes | free | not started | xcodebuild -version log line |
| 20 | Create signing secrets (APPLE_TEAM_ID, IOS_DIST_CERT_P12_BASE64, IOS_DIST_CERT_PASSWORD, IOS_PROVISIONING_PROFILE_BASE64) | owner | no | paid | not started | secret names visible in repo settings, values never committed |
| 21 | Signed archive from build-ios.yml (signing enabled) | owner (trigger) | yes | uses free quota | not started | signed archive; codesign verify log |
| 22 | Real-device test plan: list of iPhones with model and iOS version | owner | no | free | not started | device list in owner notes |
| 23 | 20+ minute thermal sessions on each device, Low and Medium presets first | owner runs, agent reads capture | no | free | not started | frame-time capture from devtools/perf_probe.gd plus device name |
| 24 | Record results in GRAPHICS_BENCHMARK.md with the device name; desktop numbers never reported as iPhone | agent | no | free | not started | GRAPHICS_BENCHMARK.md entry with device |
| 25 | Store text TR and EN (docs/release/STORE_LISTING_DRAFT.md) | agent drafted, owner approves | no | free | drafted | owner approval line in the draft |
| 26 | iPhone screenshots 1179x2556 or 1206x2622 (no alpha, 1 to 10) [S] | agent captures via harness, owner approves | no | free | not started | PNG files at those sizes plus harness log |
| 27 | iPad 13-inch screenshots 2064x2752 or 2048x2732, only if iPad is supported [S] | agent captures, owner approves | no | free | not started | PNG files; or a recorded decision not to support iPad |
| 28 | App icon in App Store Connect (1024x1024) | owner uploads | no | free | not started | ASC icon shown |
| 29 | Age rating questionnaire (13+, 16+, 18+ tiers [S]) | owner only | no | free | not started | saved ASC answers; draft in STORE_LISTING_DRAFT.md section 9 |
| 30 | Privacy policy at a public URL (offline, no data collected) | agent drafts, owner publishes | no | free (hosting unverified) | not started | live URL that loads |
| 31 | App privacy labels: data not collected (to confirm) | owner only | no | free | not started | saved ASC answers |
| 32 | Export compliance answers in App Store Connect | owner only | no | free | not started | saved ASC answers |
| 33 | IAP decision: none for v1, or cosmetic and car packs only | owner | no | free | not started | decision note |
| 34 | IAP build (only if step 33 says yes): InAppStore verified on 4.7, restore button, odds disclosure for any paid random item [S partial] | agent | yes (StoreKit test) | free | not started | sandbox purchase log and restore log |
| 35 | Sandbox tester accounts for IAP | owner only | no | free | not started | sandbox tester listed in ASC |
| 36 | Upload signed build to TestFlight | owner (or macOS job with ASC key) | yes or cloud | paid (program) | not started | build shows as processed in ASC |
| 37 | Internal TestFlight: up to 100 internal users [E] | owner | no | free | not started | tester feedback list |
| 38 | External TestFlight: up to 10,000 testers [E]; first build goes through Beta App Review [E] | owner | no | free | not started | Beta review passed |
| 39 | Watch builds: TestFlight builds expire after 90 days [E] | owner | no | free | not started | build list dates |
| 40 | Final evidence review against this checklist; go or no-go | owner | no | free | not started | signed checklist copy |
| 41 | Submit for App Review | owner only | no | free | not started | ASC submission status |
| 42 | Release to the store | owner only | no | free | not started | live store page URL |

## Claims we may NOT make yet

- "App Store ready" or "ready to submit": needs step 18 or 21 (successful archive) and step 23 (real iPhone test).
- "Builds on iOS" or "runs on iPhone": needs a real device run (step 22-23). Simulator is not supported [S].
- Any iPhone fps, frame time or battery number: needs device captures (step 23). Desktop numbers are not iPhone numbers.
- "CI passes" or "tests run on every push": needs a green run (step 8). Until then: drafted only.
- "Windows build works": needs step 12 with a real artifact.
- "Privacy: no data collected" for the store: needs step 16 confirmed and step 31 answered by the owner.
- Any age rating (13+, 16+, 18+): owner answers the questionnaire (step 29). The draft is not an answer.
- "Works offline" on iPhone: design rule only until a device test (step 23).
- "Trademark cleared" or "name available": step 3 not done.
- Any store feature claim whose milestone has not shipped (see STORE_LISTING_DRAFT.md tags).
- "Free forever" or "no cost": Apple program is paid [S]; quotas can be exceeded [S].
- "Export works from Windows": export needs macOS [S].
- "iPad supported": only after an iPad test or a recorded decision (step 27).
- "Signed" or "on TestFlight": only after steps 20, 21 and 36.
