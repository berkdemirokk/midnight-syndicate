# Privacy: App Privacy label, policy text and privacy manifest

Status: DRAFT for owner approval. Nothing is published. The privacy policy must be hosted at a public URL by the owner (RELEASE_CHECKLIST.md step 30).

## 1. App Privacy "nutrition label" answers

Answer for App Store Connect: **Data Not Collected**. Tracking: **No**.

Reasons, from the code as it stands (a code search, not a network capture):

- No network code in game/. A search of game/ for HTTPRequest, HTTPClient, WebSocket, ENet, TCP and UDP peers, OS.shell_open and "analytics" found no matches in the game scripts or scenes.
- No accounts, sign-in, ads or in-app purchases in the 1.0 feature list.
- Save and settings data stay on the device. game/core/game_state.gd and game/core/settings.gd write local files; they do not send anything.
- Apple's "collect" means sending data off the device in a way the developer or a third party can access. Local-only save data is not collected under that definition.

Conditions for keeping this answer:

- The owner must confirm it, because App Store Connect answers are the owner's responsibility (RELEASE_CHECKLIST.md step 31).
- The answer changes if any of these are added later: a crash reporter, analytics or ad SDK, a cloud save, a leaderboard, a sign-in, or an in-app purchase. Re-answer the label before each such release.
- The code search is not a device test. Confirm with a network trace on a real iPhone build once one exists (RELEASE_CHECKLIST.md step 23).

## 2. Privacy policy text (for the owner to host)

Owner: publish these two texts at one public URL, for example as one page with an English and a Turkish section. Replace the contact placeholder before publishing.

### English

Midnight Syndicate Street does not collect, transmit, share or sell any personal data. The game works fully offline. It has no accounts, no advertising, no analytics and no in-app purchases.

Your progress (career results, cash, garage choices and settings) is saved only on your device, in the app's own storage. We cannot see that data, and deleting the app deletes it.

Questions about this policy: `TODO(owner): contact e-mail address`.

Last updated: `TODO(owner): date`.

### Turkish

Midnight Syndicate Street hiçbir kişisel veriyi toplamaz, iletmez, paylaşmaz veya satmaz. Oyun tamamen çevrimdışı çalışır. Hesap, reklam, analitik veya uygulama içi satın alma yoktur.

İlerlemeniz (kariyer sonuçları, nakit, garaj seçimleri ve ayarlar) yalnızca cihazınızda, uygulamanın kendi depolama alanında saklanır. Bu verilere biz erişemeyiz; uygulamayı silmek bu verileri de siler.

Bu politika hakkında sorularınız için: `TODO(owner): iletişim e-posta adresi`.

Son güncelleme: `TODO(owner): tarih`.

## 3. Privacy manifest (PrivacyInfo.xcprivacy): what is checked and what is not verified

### What game/export_presets.cfg contains now (checked by reading the file)

The file has two presets: "Windows Desktop" and "iOS" (preset.1). The checklist (step 13) says the iOS preset is "not started", but it exists in the file. The owner should treat the preset as drafted and check it on the Mac.

The iOS preset's privacy block holds only:

- `privacy/camera_usage_description=""`
- `privacy/microphone_usage_description=""`
- `privacy/photolibrary_usage_description=""`

All three are empty. The game requests no camera, microphone or photo library access, so empty strings match.

Searching the file for "privacy" finds nothing else. The preset does not set:

- `privacy/tracking_enabled`
- `privacy/tracking_domains`
- `privacy/collected_data/*`
- any `*_access_reasons` key

Other iOS preset values present in the file, for reference: bundle identifier `com.berkdemirok.midnightsyndicate`, minimum iOS 16.0, arm64, `application/app_store_team_id=""` (empty, owner must fill it), and `additional_plist_content` with `ITSAppUsesNonExemptEncryption` set to false. The export path is `../build/ios/MidnightSyndicate.ipa`.

### What Godot iOS exports typically need (not verified here)

docs/research/07-ios-release-and-ci.md records that Godot 4.7 exposes `privacy/` keys for tracking, tracking domains, collected data and five required-reason API groups. The five groups are believed to be: file timestamp, system boot time, disk space, active keyboard, and user defaults. The exact key names and which of them the engine itself needs must be read from the Godot 4.7 iOS preset UI. The research file says it could not confirm whether Godot writes PrivacyInfo.xcprivacy itself.

Reason codes for each group come from Apple's required-reason API list. They were not checked in this work because the Apple page could not be read.

### Owner or lead to verify in the exported Xcode project (NOT verified here)

1. Export the iOS project on a Mac (RELEASE_CHECKLIST.md step 18). Check the file list for PrivacyInfo.xcprivacy.
2. If the file exists, read its contents: the declared tracking flag (expected No), the collected data types (expected none), and the required-reason API entries.
3. If the file is missing, decide whether to add it by hand or set the `privacy/` keys in the preset so Godot writes it. Do not assume either.
4. Compare the declared reason codes with what the engine and game actually call. Apple rejects uploads that use a listed API category without a declared reason.
5. Check the exported Info.plist for `ITSAppUsesNonExemptEncryption` = NO (the preset sets it through additional_plist_content; confirm it reaches the plist).
6. Note: the Xcode build and upload checks are the real test. Nothing in this document is an upload result.

No claim is made here that the privacy manifest is complete or correct. Status: not verified.
