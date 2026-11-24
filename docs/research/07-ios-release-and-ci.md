# iOS release and CI from a Windows 11 dev machine (Godot 4.7, zero extra cost)

Scope: export, CI, App Store metadata, privacy, IAP, Git LFS. Research date 2026-11-24.
Tags: [S] = read in the fetched page text (WebFetch summary). [E] = estimate, inference, or claim seen only in a search snippet. Every claim carries a URL on its line.

## Sources

| URL | What it gave | Loaded |
|---|---|---|
| https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_ios.html | macOS + Xcode required; export templates via editor; no Windows route; Team ID and bundle ID required. No Xcode version. | yes |
| https://docs.godotengine.org/en/stable/classes/class_editorexportplatformios.html | privacy/ properties, storyboard/ and icons/ properties, team ID and signing props. No encryption prop. Truncated at 100k of 148k chars. | yes (partial) |
| https://docs.github.com/en/billing/concepts/product-billing/github-actions | Dollar allowances (Free $12, Pro/Team $18), per-minute rates, storage limits, public repo note | yes |
| https://docs.github.com/en/billing/managing-billing-for-github-actions/about-billing-for-github-actions | Same dollar allowances and rates; no minute counts | yes |
| https://docs.github.com/en/get-started/learning-about-github/githubs-plans | Plan overview; Free personal package storage | yes (no LFS or minutes) |
| https://docs.github.com/en/billing/managing-billing-for-git-large-file-storage/about-billing-for-git-large-file-storage | LFS quotas per plan and overage behaviour | yes |
| https://codemagic.io/pricing/ | Free tier build minutes, paid rates (no date shown) | yes |
| https://developer.apple.com/documentation/bundleresources/privacy-manifest-files | Title only, no body | yes (no content) |
| https://developer.apple.com/documentation/bundleresources/privacy-manifest-files/describing-use-of-required-reason-api | 404 | no |
| https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api | Title only, no body | yes (no content) |
| https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications | iPhone/iPad sizes, required sets, counts | yes |
| https://developer.apple.com/help/app-store-connect/reference/age-ratings-values | Page not found | no |
| https://developer.apple.com/news/?id=ks775ehf | 2025 age-rating overhaul: 13+/16+/18+, Jan 31 2026 deadline | yes |
| https://developer.apple.com/app-store/review/guidelines/ | 3.1.1 loot-box odds, IAP currency rules; truncated at 100k of 114k chars | yes (partial) |
| https://developer.apple.com/help/app-store-connect/reference/export-compliance-documentation-for-encryption | Documents needed by encryption type | yes |
| https://developer.apple.com/design/human-interface-guidelines/app-icons | Title only | yes (no content) |
| https://developer.apple.com/programs/ | $99/yr program fee; Apple Account and agreement | yes |
| https://github.com/godotengine/godot-ios-plugins | Official iOS plugin repo: MIT, no releases, 60 commits, no StoreKit mention | yes |
| https://github.com/dulvui/godot4-ios-export | MIT; archived 2025-06-03, read-only | yes |
| https://github.com/CapsCollective/godot-actions | MIT; install-godot and build-godot; install-templates default false | yes |
| https://docs.godotengine.org/en/stable/classes/class_inappstore.html | 404 | no |
| https://developer.apple.com/news/upcoming-requirements/?id=04282026a | Xcode 26 / iOS 26 SDK rule (search snippet only) | no (snippet) |
| https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview | TestFlight tester limits, beta review (search snippet only) | no (snippet) |
| https://docs.godotengine.org/en/4.3/tutorials/platform/ios/plugins_for_ios.html | InAppStore singleton methods (search snippet only; 4.4 pages say "not yet updated") | no (snippet) |
| https://help.apple.com/xcode/mac/current/en.lproj/dev0dc15d044.html | ITSAppUsesNonExemptEncryption key (search snippet only) | no (snippet) |
| https://www.godotengine.org/asset-library/asset/5276 | Third-party StoreKit plugin listing (search snippet only) | no (snippet) |

## Summary

1. iOS export needs macOS with Xcode. Windows cannot produce the Xcode project by that rule [E]. Cloud macOS or a borrowed Mac is required. [S]
2. Free-tier cloud macOS exists two ways: GitHub Actions (public repo: standard runners free; private: plan allowance with 10x macOS multiplier) and Codemagic (500 Mac M2 min/mo). [S][E]
3. The 2025 age-rating overhaul added 13+/16+/18+; the questionnaire deadline (Jan 31 2026) has passed. [S]
4. Git LFS Free quota is 10 GiB storage and 10 GiB bandwidth per account. GLB and textures can exhaust it through CI checkouts. [S][E]
5. Godot 4.7 iOS export has a `privacy/` block that carries required-reason API reasons and tracking flags. No encryption key in the preset. [S]
6. Official Godot iOS plugin repo does not confirm StoreKit. Built-in `InAppStore` singleton exists in 4.x docs (snippet). [S][E]
7. Community GitHub export action dulvui/godot4-ios-export is archived (2025-06-03). CapsCollective/godot-actions is MIT, unclear maintenance. [S]
8. Apple Developer Program: $99/yr; enrollment and agreement need the account owner. [S]

## The 8 findings that most affect design or engineering

1. **No Windows iOS export.** Godot's iOS page says export must run on macOS with Xcode installed. [S] The page does not mention Windows; ruling Windows out is an inference. [E] Design: plan a Mac step (cloud or borrowed) for every iOS build. https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_ios.html
2. **Export templates are a separate download.** Templates come from Editor > Manage Export Templates; CI must install them. Pin the template version to the engine version (4.7.x). [S] https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_ios.html
3. **GitHub Actions macOS is expensive in minutes.** Dollar allowance is $12/mo Free and $18/mo Pro/Team; macOS rate is $0.062/min vs Linux 2-core $0.006/min (about 10x). Free allowance ≈ 200 macOS minutes/mo. [S][E] https://docs.github.com/en/billing/concepts/product-billing/github-actions
4. **GitHub public repos.** Standard hosted runners are free for public repos (per GitHub's billing summary). Repo visibility is an owner decision and is public source. [S][E] https://docs.github.com/en/billing/concepts/product-billing/github-actions
5. **Codemagic free tier.** 500 Mac mini M2 build minutes/mo, one concurrent build, individuals; no date shown on page. Good for one build per week; not for iteration. [S][E] https://codemagic.io/pricing/
6. **Git LFS quota.** Free 10 GiB storage and 10 GiB bandwidth. Every CI checkout that pulls LFS objects uses bandwidth. Use LFS only for GLB and textures, skip LFS in CI where the build doesn't need binaries (or cache), and keep the repo small. [S][E] https://docs.github.com/en/billing/managing-billing-for-git-large-file-storage/about-billing-for-git-large-file-storage
7. **Privacy manifest and export settings are in the Godot preset.** `privacy/tracking_enabled`, `privacy/tracking_domains`, five `*_access_reasons` keys, and `privacy/collected_data/*`. Whether Godot writes the PrivacyInfo.xcprivacy file itself is not confirmed by the fetched text. Verify with a test build. [S][E] https://docs.godotengine.org/en/stable/classes/class_editorexportplatformios.html
8. **Age rating and loot/energy mechanics.** 3.1.1: loot boxes with paid random items must disclose item odds; IAP currency may not expire; content unlocked with currency must go through IAP. Energy/timer systems have no explicit rule in the fetched text (truncated). Design the energy system so it does not require IAP to unlock content. [S][E] https://developer.apple.com/app-store/review/guidelines/

## Export and build requirements

- macOS with Xcode, export templates, Team ID, unique bundle ID. Xcode version not stated on the Godot page. [S] https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_ios.html
- Xcode 26 / iOS 26 SDK required for uploads since 2026-04-28. Source: search snippet only. [E] https://developer.apple.com/news/upcoming-requirements/?id=04282026a
- Next SDK step: April 2027 (iOS 27 SDK; iPhone Duo screenshots become required). [E] https://developer.apple.com/news/upcoming-requirements/?id=04282026a and https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications
- Simulator export not supported (Godot docs warning, GH-102149; from search snippet). Simulator uses Compatibility renderer only (Godot page). [S] https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_ios.html
- Launch screen: Godot exposes `storyboard/custom_bg_color`, `storyboard/custom_image@2x/@3x`, `storyboard/image_scale_mode`, `storyboard/use_custom_bg_color`. [S] https://docs.godotengine.org/en/stable/classes/class_editorexportplatformios.html
- App icons: Godot exposes `icons/` groups (App Store, iPhone, iPad, notification, settings, spotlight) with `_dark` and `_tinted` variants; empty fields fall back to the project icon. [S] https://docs.godotengine.org/en/stable/classes/class_editorexportplatformios.html
- Master icon size 1024x1024, square, no transparency, system masks corners. [E] (HIG page loaded title only) https://developer.apple.com/design/human-interface-guidelines/app-icons

## Community GitHub actions for Godot iOS export

| Action | License | Status | Notes |
|---|---|---|---|
| dulvui/godot4-ios-export | MIT [S] | Archived 2025-06-03, read-only [S] | Exports Godot 4.x project to Xcode project; signing and TestFlight upload live in the user's workflow [S]. Do not depend on it. https://github.com/dulvui/godot4-ios-export |
| CapsCollective/godot-actions | MIT [S] | No archive notice; maintenance unclear (1 open issue, 1 open PR) [S] | Provides install-godot (install-templates default false) and build-godot (macOS, Windows, Linux). Verify 4.7 support before use. https://github.com/CapsCollective/godot-actions |
| godot-ios-upload | n/a | Archived [E] (search snippet) | Superseded per its maintainer. [E] |

Recommendation: write a short workflow (~30 lines) that installs Godot 4.7.x and templates, runs `godot --export-release`, and signs with a team certificate. Fewer moving parts than a third-party action. [E]

## StoreKit and in-app purchase

- Official Godot iOS plugin repo: MIT, 60 commits, no releases, no StoreKit mention on page. [S] https://github.com/godotengine/godot-ios-plugins
- Built-in `InAppStore` singleton in Godot 4.x docs: methods purchase, request_product_info, restore_purchases, pop_pending_event; call finish_transaction or set_auto_finish_transaction. Snippet from 4.3/4.4 doc pages; 4.4 pages flag "not yet updated". Treat as [E] until verified on 4.7. https://docs.godotengine.org/en/4.3/tutorials/platform/ios/plugins_for_ios.html
- Third-party StoreKit plugins listed in Godot asset library (search snippet): hrk4649 (MIT, 4.5/4.6), atlasapplications (StoreKit 2, 4.4), thejust (4.3). Check each before use. [E] https://www.godotengine.org/asset-library/asset/5276
- Offline game: IAP is optional. If the game is fully offline, a paid-up-front or no-IAP model avoids StoreKit entirely. [E]

## Privacy manifest and encryption

- Privacy manifest (PrivacyInfo.xcprivacy): declares tracking, tracking domains, collected data types, and accessed required-reason API types with reason codes; applies to third-party SDK bundles too. [E] (page loaded title only; claims from general knowledge) https://developer.apple.com/documentation/bundleresources/privacy-manifest-files
- Likely required-reason categories for a Godot game: user defaults (settings), file timestamp (save files, cache), system boot time (timers), disk space if large downloads. Active keyboard only if custom text entry. [E] https://docs.godotengine.org/en/stable/classes/class_editorexportplatformios.html (categories listed)
- Reason codes (e.g. CA92.1 user defaults) are from memory, not verified here. [E]
- Export compliance: `ITSAppUsesNonExemptEncryption` Boolean in Info.plist. Set NO if the app only uses OS encryption or exempt encryption. The Godot preset has no encryption key, so inject it through custom Info.plist handling or post-export edit. [E] https://help.apple.com/xcode/mac/current/en.lproj/dev0dc15d044.html (snippet)
- Encryption documentation: none in App Store Connect if only Apple OS encryption; French declaration only for proprietary/non-standard algorithms and only if distributed in France. [S] https://developer.apple.com/help/app-store-connect/reference/export-compliance-documentation-for-encryption

## App Store metadata

- Screenshots (iPhone): required Dynamic Island (medium) 1179x2556 or 1206x2622 (portrait). Face ID (large) 1284x2778 or 1242x2688 required only if no Dynamic Island (large) set. 1–10 per size, JPEG or PNG, no alpha. [S] https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications
- Screenshots (iPad): 13" 2064x2752 or 2048x2732 required if the app runs on iPad; smaller sizes fall back. [S] https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications
- Age rating: 2025 overhaul adds 13+, 16+, 18+ alongside 4+ and 9+; questionnaire deadline 2026-01-31 has passed; existing ratings were reassigned. Removed tiers (12+, 17+) are from search only. [S][E] https://developer.apple.com/news/?id=ks775ehf
- Apple added new content descriptors effective 2026-11-16, with declarations due 2027-01-12 (search snippet). [E] https://developer.apple.com/news/?id=ks775ehf
- Racing with energy/loot: age rating questionnaire must reflect violence/gambling-like features honestly. Simulated gambling rules are in section 5.3, truncated and not read. [E] https://developer.apple.com/app-store/review/guidelines/

## TestFlight

- Internal testers: up to 100 App Store Connect users. External: up to 10,000. First build of a version goes through Beta App Review. Builds expire after 90 days. [E] (search snippet of Apple TestFlight help) https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview
- External testing requires a beta description and feedback email. [E] (search snippet via Expo docs) https://docs.expo.dev/submit/testflight/

## Git LFS for GLB and textures

- Free: 10 GiB storage, 10 GiB bandwidth per account. Over quota with no payment method: pushes blocked and clones give pointers only; bandwidth overage disables LFS until next month. [S] https://docs.github.com/en/billing/managing-billing-for-git-large-file-storage/about-billing-for-git-large-file-storage
- Public repos: no separate LFS quota found in the fetched page. [E] same URL
- Actions cache: 10 GB per repo. Artifacts + Packages: Free 500 MB. [S] https://docs.github.com/en/billing/concepts/product-billing/github-actions
- Implication: keep source assets small (compressed GLB, KTX/basis or PNG under budget). Do not pull LFS in CI unless the build needs it. [E]

## Owner-only steps (cannot be delegated)

- Apple Developer Program enrollment ($99/yr) and acceptance of the Apple Developer Agreement. [S] https://developer.apple.com/programs/
- Apple Account 2FA, legal name and address, tax and banking forms in App Store Connect. [E]
- Creating distribution certificate, App Store provisioning profile, and App Store Connect API key (signing). [E]
- Answering age-rating, privacy-label, export-compliance, and content-rights questions in App Store Connect. [E]
- Paying for any paid plan (GitHub Pro/Team, Codemagic). [E]
- Inviting external TestFlight testers and submitting for review. [E]

## Checklist, ordered by what blocks what

1. Confirm the repo visibility decision (public vs private): it changes Actions cost. [E]
2. Enroll in the Apple Developer Program (owner). Blocks everything below. [S]
3. Create bundle ID and App Store Connect app record (owner). [E]
4. Decide the Mac path: GitHub macOS runner (public) or Codemagic (500 min/mo) or borrowed Mac. [S][E]
5. Pin Godot 4.7.x and matching export templates in CI. [S]
6. Set up export preset: bundle ID, Team ID, icons, launch screen storyboard. [S]
7. Add `ITSAppUsesNonExemptEncryption` = NO (verify) and privacy/ block; generate PrivacyInfo.xcprivacy if not produced by Godot. [E]
8. Keep LFS small; skip LFS in CI where possible. [S][E]
9. Build a signed IPA (owner creates signing identity or API key). Upload to TestFlight. [E]
10. Internal TestFlight testing (up to 100 internal users). [E]
11. Fill age rating (13+/16+/18+ tiers), privacy labels, export compliance. [S][E]
12. Create IAP products only if the monetization needs them; verify InAppStore on 4.7 first. [E]
13. External TestFlight (Beta App Review on first build). [E]
14. Upload screenshots: iPhone Dynamic Island (medium) set and iPad 13" if iPad is supported. [S]
15. Submit for App Review. [E]

## Gaps and failed loads

- Godot export page does not state the Xcode version. Unknown from fetched sources. [E]
- Apple privacy-manifest, required-reason, app-icon HIG pages returned titles only. Reason codes and icon spec from memory. [E]
- Apple age-ratings-values page and Godot InAppStore class page returned 404.
- Apple App Review guidelines truncated; section 5.3 (gambling) not read.
- GitHub Actions minute counts are not on the fetched pages; estimates derived from dollar allowance. [E]
- Official Godot 4.7 StoreKit status not confirmed; no 4.7 plugin release seen. [E]
- No Xcode-version or macOS-version requirement for Godot 4.7 found in fetched text. [E]

## Verification pass

Checker: independent re-read of 8 high-cost claims on 2026-11-24. Counts: checked 8, confirmed 7, corrected 1, unverifiable 0.

1. Godot iOS export must run on macOS with Xcode: CONFIRMED (page quote read). Windows exclusion was not on the page; retagged to [E]. https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_ios.html
2. GitHub Free Actions allowance $12/mo; Pro and Team $18/mo: CONFIRMED (dollar amounts, not minutes). https://docs.github.com/en/billing/concepts/product-billing/github-actions
3. macOS 3/4-core $0.062/min; Linux 2-core $0.006/min: CONFIRMED. The "10x" multiplier is not on the page; ratio computes to about 10.3x [E]. "About 200 macOS min/mo" is 12 / 0.062 = about 193 [E]. https://docs.github.com/en/billing/concepts/product-billing/github-actions
4. Standard GitHub-hosted runners free in public repositories: CONFIRMED. https://docs.github.com/en/billing/concepts/product-billing/github-actions
5. Codemagic free tier 500 macOS M2 min/mo, max 1 parallel build: CONFIRMED. https://codemagic.io/pricing/
6. Git LFS Free: 10 GiB bandwidth and 10 GiB storage: CONFIRMED. https://docs.github.com/en/billing/managing-billing-for-git-large-file-storage/about-billing-for-git-large-file-storage
7. Apple Developer Program $99 annual membership: CONFIRMED. https://developer.apple.com/programs/
8. Age ratings 13+, 16+, 18+ added; questionnaire deadline January 31, 2026: CONFIRMED. https://developer.apple.com/news/?id=ks775ehf

Corrections:
- Line 39 and finding 1: Windows exclusion moved from [S] to [E]; the page only states the macOS requirement.

Not checked in this pass: summary item 6 tags the InAppStore singleton [S], but its source was a search snippet only (see Sources table, row 33). It should read [E] until the page is read. Also not checked: the Xcode 26 / iOS 26 SDK rule, TestFlight limits, and the screenshot sizes.
