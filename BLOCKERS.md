# Blockers and owner decisions

| id | what | why it blocks | who can clear it | status |
|---|---|---|---|---|
| B1 | No macOS/Xcode machine | iOS export, signing, simulator and device builds need macOS + Xcode (Godot docs) | Owner: choose free-quota cloud Mac CI (private-repo macOS minutes are multiplied) or provide a Mac | open |
| B2 | No iPhone test yet | No frame-time, thermal or touch evidence on a device; no iOS performance claim can be made | Follows B1 | open |
| B3 | Godot export templates not installed (1.28 GB) | Needed for a Windows .exe build and for exporting the Xcode project | Owner approval for the download | open |
| B4 | No licensed display font | HUD uses the engine's built-in font styled with FontVariation; a racing display face (OFL) would lift the UI | Owner approval to download an OFL font, or keep built-in | open, not critical |
| B5 | Audio assets | No engine/tyre/ambience sounds yet; CC0 sources identified in docs/research/05 | Scheduled for M2; downloads need approval | open |
| B6 | glTF material extensions in Godot | Whether the importer reads KHR clearcoat / emissive strength is not confirmed in docs | Test with our own exported car GLB | to verify in M1 |
| B7 | Bundle identifier, developer team id | Must be chosen by the account owner | Owner | open |

Rules: a blocker is recorded here the moment it is found, work continues on everything that does
not depend on it, and it is removed only with evidence.
