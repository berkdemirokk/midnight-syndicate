# iOS export notes (MIDNIGHT SYNDICATE)

Tags: [S] = in the fetched text of docs/research/07-ios-release-and-ci.md. [E] = estimate or search snippet.
"unverified" = not in that research file. Nothing here is verified on a real Mac or device yet.

## 1. What can and cannot be done from Windows

| Task | From Windows 11 | Status |
|---|---|---|
| Edit the game, run headless logic tests | yes | works today (run_tests.gd) |
| Export the iOS Xcode project | no. Godot's iOS page says export must run on macOS with Xcode [S] | needs cloud macOS or a borrowed Mac |
| Create the iOS preset in the Godot editor on Windows | unverified | test it; if it works, the preset is portable |
| Build, sign, archive | no. Needs Xcode on macOS [S] | cloud macOS (build-ios.yml) |
| Upload to TestFlight | no, unless the upload is done from the macOS job [E] | owner step |
| Real-device test | no. Needs an iPhone [owner] | owner step |
| Simulator | no. Godot does not support iOS simulator export [S] | out of scope |

Templates: export templates come from the editor (Manage Export Templates) and CI must install them.
Pin them to the engine version 4.7.x [S].

Mac options: GitHub macOS runner, macOS minutes about 10x the Linux rate [E], about 190 macOS min/mo on the
free $12 allowance for a private repo [E]. Codemagic free tier: 500 Mac M2 min/mo, 1 concurrent build [S][E]
(no date shown on page). A borrowed Mac: no cost, owner's time.

Renderer note: the iOS target is Metal on device [ARCHITECTURE.md]. Simulator uses Compatibility only [S].

## 2. Privacy manifest (PrivacyInfo.xcprivacy), draft for an offline game

Draft facts: no tracking, no tracking domains, no collected data types, no third-party SDKs [ARCHITECTURE.md:
offline only, no network code, no SDKs in the vertical slice].

```xml
<key>NSPrivacyTracking</key>
<false/>
<key>NSPrivacyTrackingDomains</key>
<array/>
<key>NSPrivacyCollectedDataTypes</key>
<array/>
<key>NSPrivacyAccessedAPITypes</key>
<array>
  <!-- Add one dict per category the exported bundle actually uses. Candidates below are NOT confirmed. -->
  <dict>
    <key>NSPrivacyAccessedAPIType</key>
    <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
    <key>NSPrivacyAccessedAPITypeReasons</key>
    <array><string>REASON-CODE-TO-LOOK-UP</string></array>
  </dict>
</array>
```

Candidate required-reason categories (to verify against the exported Xcode project, do not assert):
- UserDefaults: Godot may read or write preferences through NSUserDefaults. Unverified.
- FileTimestamp: save file and cache checks, if Godot or GameState reads file dates. Unverified.
- SystemBootTime: timers, if Godot reads uptime. Unverified.
- DiskSpace: only if the game checks free space. Unverified.
- ActiveKeyboards: only with custom keyboard input. Likely not needed. Unverified.

Reason codes are NOT in the research file. Look each one up in Apple's current list before writing them in.
Apple's required-reason rules also apply to third-party SDK bundles [E]. The app has none today.

Godot preset keys: `privacy/tracking_enabled`, `privacy/tracking_domains`, five `*_access_reasons` keys and
`privacy/collected_data/*` [S]. Whether Godot writes PrivacyInfo.xcprivacy itself is NOT confirmed [E].
Check the exported project for the file. If absent, add it in the post-export step or the Xcode project.

## 3. Export compliance

- Info.plist key `ITSAppUsesNonExemptEncryption` = NO is expected for an app that uses only OS encryption
  or exempt encryption [E: help.apple.com snippet].
- The Godot preset has no encryption key [S]. Inject it through custom Info.plist handling or a post-export
  edit. Unverified until tested.
- App Store Connect export-compliance documentation depends on the encryption type [S].
- Owner answers the App Store Connect questions. Do not set the key without confirming the app uses no non-exempt
  encryption.

## 4. Icon and launch screen asset list

Icons (Godot `icons/` groups, each with `_dark` and `_tinted` variants; empty fields fall back to the project
icon) [S]: App Store, iPhone, iPad, notification, settings, spotlight.

| Asset | Pixel size | Source | Status |
|---|---|---|---|
| App Store master icon | 1024 x 1024, square, no transparency, system masks corners | [E] (HIG page loaded title only) | unverified in detail |
| Other icon sizes | not in the research file | Xcode AppIcon template after export | unverified; do not hand-size |
| Launch screen background colour | `storyboard/custom_bg_color` | Godot preset [S] | owner picks colour |
| Launch screen image @2x, @3x | `storyboard/custom_image@2x`, `@3x` | Godot preset [S] | pixel sizes unverified |
| Launch image scale mode | `storyboard/image_scale_mode` | Godot preset [S] | choose in preset |
| Use custom bg colour flag | `storyboard/use_custom_bg_color` | Godot preset [S] | set in preset |

Art is owned by the owner. Do not use third-party art without a licence record (THIRD_PARTY_LICENSES.md).

## 5. In-app purchase architecture (sketch, cosmetic packs only)

Scope: cosmetic and car packs only. No pay-to-win. Owner decides whether IAP exists at all. Offline game: IAP is
optional [E]. A no-IAP build avoids StoreKit entirely.

- Library: built-in `InAppStore` singleton (methods: purchase, request_product_info, restore_purchases,
  pop_pending_event; finish_transaction or set_auto_finish_transaction) [E: from 4.3 doc snippet, 4.4 pages say
  "not yet updated"]. Verify on 4.7 before use. Third-party StoreKit plugins exist [E]: check licence and version.
- Product IDs (placeholders, owner chooses): `com.example.midnightsyndicate.cosmetic.pack01`,
  `com.example.midnightsyndicate.car.pack01`. Non-consumable for packs unless the owner decides otherwise.
- Receipt handling on device: validate the transaction on device with StoreKit before granting content.
  No server exists, so entitlement is on device only. [unverified: StoreKit 2 details not in research]
- Restore flow: a visible "Restore purchases" button in settings calls restore_purchases and re-grants
  non-consumables. Apple's expectation for restore is not in the research file. [unverified]
- Offline behaviour: the game runs offline. Purchase needs network to the App Store. Owned items are cached
  locally and must work offline after purchase. Re-check entitlements when online. [unverified]
- Loot rule: if any paid random item appears, disclose item odds (guidelines 3.1.1 [S, partial read]).
  IAP currency may not expire (3.1.1 [S, partial read]). Content unlocked with currency must go through IAP
  (3.1.1 [S/E, partial read]). Energy or timer systems: no explicit rule read; design them so no IAP is needed
  to unlock content [E].
- Testing: sandbox accounts in App Store Connect (owner). Needs macOS or a real iPhone [E].

## 6. Open items

- Confirm Xcode version for the Godot 4.7 export. Not in the research [E].
- Confirm `ITSAppUsesNonExemptEncryption` on the first exported project.
- Confirm whether Godot writes the privacy manifest.
- Verify InAppStore on Godot 4.7 before any IAP work.

## 7. Verified 2026-11-28: dry export on Windows (supersedes the unverified notes in sections 2 and 3)

Method: `Godot_v4.7.2-stable_win64_console.exe --headless --export-debug "iOS" <scratch>/MidnightSyndicate.ipa` with the
installed iOS export template (ios.zip). Post-fix run: scratch ios_export2 (ios_export1 is the pre-fix run with the duplicate key). `application/export_project_only=true`, so no signing and no .ipa. The
temporary Team ID used for the dry run was reverted; the committed preset keeps it empty.

Results:
- Export runs on Windows and writes the Xcode project (MidnightSyndicate.xcodeproj, MidnightSyndicate.pck, storyboard,
  Info.plist, Images.xcassets). The .ipa step is skipped with a warning: it needs macOS.
- Refusal without a Team ID: "App Store Ekip Kimliği belirtilmemiş" (Team ID not set). Owner must set it before export.
- Godot writes PrivacyInfo.xcprivacy itself from the preset. No hand-written file is added. Generated content:
  - NSPrivacyTracking = false
  - NSPrivacyAccessedAPICategoryFileTimestamp: DDA9.1, C617.1 (engine defaults; stat-based file checks, Godot FileAccess)
  - NSPrivacyAccessedAPICategorySystemBootTime: 35F9.1 (engine default; Time.get_ticks_usec / msec are used by the game)
  - NSPrivacyAccessedAPICategoryDiskSpace: E174.1, 85F4.1 (engine defaults; no game code calls get_space_left)
  - No UserDefaults or ActiveKeyboards entry: the preset does not ask for them.
  - Not emitted, but Apple's schema expects them: NSPrivacyTrackingDomains and NSPrivacyCollectedDataTypes. Check on a
    Mac; if missing, add `<key>...</key><array/>` for both in a post-export step, or fix the preset (see the checklist).
- Info.plist: the template already writes ITSAppUsesNonExemptEncryption = false. The duplicate line from
  `application/additional_plist_content` was removed from the preset (duplicate plist keys are an upload risk).
- Icons: Godot builds the whole AppIcon set (Icon-40 ... Icon-1024) from `icons/icon_1024x1024`. The 1024 master is RGB,
  no alpha. No icon sizes were generated by hand.
- Launch screen: LaunchScreen storyboard background 0.012, 0.016, 0.035 (same as the boot splash). SplashImage uses the
  boot splash images.
- Orientation: landscape left and right only, from `display/window/handheld/orientation` = sensor landscape.
- Permission strings: NSCameraUsageDescription, NSMicrophoneUsageDescription and NSPhotoLibraryUsageDescription are
  written EMPTY by Godot. The game uses none of those APIs. Whether App Store validation accepts empty strings for unused APIs is
  unverified; check on the Mac and remove the three keys there if validation complains. Do not invent usage text.
- UIRequiredDeviceCapabilities = iphone-ipad-minimum-performance-a12 is written even though the preset flag
  `capabilities/performance_a12` is false. The owner must confirm the minimum device class (A12 = iPhone XS and later).
- Engine warning: "Property not found: application/boot_splash/fullsize" (project.godot). Harmless; lead to clean up.
- LAN online: off by default (net/net_config.gd: `ENABLED` false; the `--experimental-online` launch flag also turns it on,
  which an iOS user cannot pass). The shipped build has no local-network UI, so no
  NSLocalNetworkUsageDescription is set. Add it when NetConfig.ENABLED becomes true.

Reason codes: taken from the engine's option list (present in the Godot 4.7.2 binary) and written into the export as shown
above. They were NOT checked against Apple's current list (no Apple page was read here). Check them there before submission.
The engine defaults stay on because the engine calls those APIs. Declaring an unused reason is harmless; leaving out a used
one is what Apple rejects.
