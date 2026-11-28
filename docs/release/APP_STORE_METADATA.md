# App Store Connect fields: Midnight Syndicate Street (1.0)

Status: DRAFT for owner approval. Nothing is entered in App Store Connect, published or submitted.
The full store texts (description, promotional text, keywords, "what's new") in English and Turkish live in
docs/store/APP_STORE_METADATA.md. This file does not copy them. It holds the fields that file lacks and the
corrections found while checking the build.

## 1. Names and categories

| Field | English (en-US) | Turkish (tr) | Limit | Note |
|---|---|---|---|---|
| App name | Midnight Syndicate Street | Midnight Syndicate Street | 30 | Trademark and availability check not done (RELEASE_CHECKLIST.md step 3). |
| Subtitle | Offline night street racing | Çevrimdışı gece sokak yarışı | 30 | Text in docs/store/APP_STORE_METADATA.md. |
| Primary category | Games > Racing | same | | |
| Secondary category | Games > Action | same | | |

Platform: iPhone, landscape only (`UISupportedInterfaceOrientations` = LandscapeLeft, LandscapeRight, verified in the
dry export). iPad is not decided (RELEASE_CHECKLIST.md step 27).

## 2. URLs (owner fills in; nothing is hosted by this repository)

- Support URL: `TODO(owner): public support page or contact page`
- Marketing URL (optional): `TODO(owner): URL or leave empty`
- Privacy policy URL: `TODO(owner): public URL that hosts the policy text in docs/store/PRIVACY.md, section 2`
- Copyright line: `TODO(owner): 2026 <legal name of the copyright holder>`

## 3. Age rating questionnaire: corrections to docs/store/AGE_RATING.md

docs/store/AGE_RATING.md says "No police pursuit is in the 1.0 feature list". That is wrong for this build:

- The main menu shows a POLICE PURSUIT button (`menu.pursuit`, ui/menus/main_menu.gd).
- Career events with `"pursuit": true` run police cars and roadblocks (race/events.gd, race/race_scene.gd line 301:
  pursuit runs when the event opts in, even with `PursuitMode.ENABLED` false).
- Answer the questionnaire with police chases included: fictional police cars chase the player, and a bust ends
  the race with no reward. No weapons and no injury are shown.

Suggested answers (owner confirms each in App Store Connect; the form wording may differ):

| Question | Answer | Basis |
|---|---|---|
| Realistic or cartoon violence | Infrequent or mild | Car collisions and police chases only. No people shown hurt, no blood, no weapons. |
| Prolonged graphic or sadistic violence | None | No gore. |
| Fear or horror themes | None | Night setting is atmosphere only. |
| Simulated gambling, real gambling, contests | None | No wagers, no real-money play. Cash is earned by racing. |
| Unrestricted web access | No | No network code runs in the 1.0 build (LAN online is off by default, net/net_config.gd). |
| User-generated content, messaging, ads, IAP, loot boxes | No | None in 1.0. |
| Profanity, sexual content, alcohol, tobacco, drugs, medical | None | None found in i18n strings or assets. Owner confirms. |

Expected tier: the result shown by App Store Connect after the owner answers is the only one that counts.
Record it: `TODO(owner): resulting tier and date answered`. The tier names used in AGE_RATING.md are from memory and
unverified.

## 4. App Privacy ("nutrition label")

Answer: Data Not Collected. Tracking: No. Full reasons and conditions are in docs/store/PRIVACY.md, section 1.

Additional facts from the dry export (see docs/release/IOS_EXPORT_NOTES.md, section 7):
- The generated PrivacyInfo.xcprivacy says `NSPrivacyTracking` = false.
- Required-reason API declarations are file timestamp, system boot time and disk space (engine defaults). None is a
  data collection item, so the label is unaffected.
- LAN online is OFF in 1.0. If `NetConfig.ENABLED` is turned on, the label, the policy and
  NSLocalNetworkUsageDescription must all change before that build is submitted.

## 5. Export compliance

`ITSAppUsesNonExemptEncryption` = false is written by the Godot template in the exported Info.plist (verified in the
dry export). The game has no network code and no custom cryptography, so it uses no non-exempt encryption (verify on the exported project). Owner confirms this in App Store
Connect's export compliance questions (RELEASE_CHECKLIST.md step 32).

## 6. Owner checks before any of this is entered

- Store copy does not mention police chases. Add one honest line to the description (EN and TR) or the owner
  accepts the omission. Apple expects the description to match the game.
- Bundle ID in game/export_presets.cfg is `com.berkdemirok.midnightsyndicate`. RELEASE_CHECKLIST.md still shows the
  placeholder `com.example.midnightsyndicate`. Pick one and make both match before App Store Connect records it.
- Team ID (`application/app_store_team_id`) is empty. The Godot editor refuses to export the iOS preset until it is
  set, even for an Xcode-project-only export. Owner sets it; it is not a secret, but keep signing files out of git.
