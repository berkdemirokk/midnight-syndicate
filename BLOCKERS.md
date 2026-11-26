# Blockers and owner decisions

| id | what | why it blocks | who can clear it | status |
|---|---|---|---|---|
| B1 | No macOS/Xcode machine | iOS export, signing, simulator and device builds need macOS + Xcode (Godot docs) | Owner: choose free-quota cloud Mac CI (private-repo macOS minutes are multiplied) or provide a Mac | open |
| B2 | No iPhone test yet | No frame-time, thermal or touch evidence on a device; no iOS performance claim can be made | Follows B1 | open |
| B3 | Godot export templates not installed (1.28 GB) | Needed for a Windows .exe build and for exporting the Xcode project | Owner approval for the download | cleared 2026-11-25: owner approved; official 4.7.2 templates downloaded, SHA512 verified, Windows + iOS templates installed |
| B4 | No licensed display font | HUD uses the engine's built-in font styled with FontVariation; a racing display face (OFL) would lift the UI | Owner approval to download an OFL font, or keep built-in | open, not critical |
| B5 | Audio assets | No engine/tyre/ambience sounds yet; CC0 sources identified in docs/research/05 | Scheduled for M2; downloads need approval | cleared 2026-11-25: 25 original procedurally synthesised sounds (tools/audio_synth.py), no download; subjective sound quality not yet judged by ear |
| B6 | glTF material extensions in Godot | Whether the importer reads KHR clearcoat / emissive strength is not confirmed in docs | Test with our own exported car GLB | to verify in M1 |
| B7 | Bundle identifier, developer team id | Must be chosen by the account owner | Owner | open |
| B8 | GitHub Actions jobs do not start on the private repo (github.com/berkdemirokk/midnight-syndicate) | Run 45446375128: "The job was not started because recent account payments have failed or your spending limit needs to be increased." CI (headless tests, asset validation) cannot run in the cloud; tests run locally instead | Owner: GitHub Billing & plans (fix the payment method or spending limit), or make the repo public (public repos get free minutes). Nothing was changed on the account | worked around: owner made the repo public on 2026-11-24 |
| B9 | Windows Smart App Control blocks the exported .exe on the dev PC ("Uygulama Denetimi ilkesi bu dosyayi engelledi") | Godot's Windows templates are unsigned; any new unsigned exe without reputation is blocked where Smart App Control is on, so players on such PCs would be blocked too. The exported .pck runs with the allowed Godot binary (menu 900 frames, race 1500 frames, no errors) | Owner: a code-signing certificate (paid) or SmartScreen reputation for a store/itch build; Smart App Control cannot be re-enabled once turned off, so do not disable it to test | open |

Rules: a blocker is recorded here the moment it is found, work continues on everything that does
not depend on it, and it is removed only with evidence.
