# tools/ README (asset factory)

Python 3.10, standard library only. Run from the repo root with `py -3.10 tools/<script>`.

## Registering assets

- Generated assets (Blender or script output): after the build writes files under `game/assets/`,
  run
  `py -3.10 tools/asset_factory.py register --id <id> --kind <texture|model|hdri|audio|generated> --path <repo-relative path> --source generated:blender --license project-owned --tris <n> --materials <n> --notes "<where used>"`
  then `validate`.
- Third-party assets: only through `tools/fetch_cc0.py` (pinned in `tools/cc0_assets.json`) or with
  `--source cc0:polyhaven|cc0:ambientcg`, `--license CC0-1.0` and an https `--source-url`.
- `validate` checks files, sha256, licence allow-list, GLB magic and JSON chunk, power-of-two
  textures, and writes `test_result` per record. Exit code 1 on any failure.
- `licenses` regenerates `THIRD_PARTY_LICENSES.md` (third-party rows only).
- `selftest` runs the built-in checks in a temp folder.

## Re-fetching CC0 textures

- `py -3.10 tools/fetch_cc0.py pin` re-queries the Poly Haven API and rewrites URLs and md5 in
  `tools/cc0_assets.json`. Only needed when changing the asset list.
- `py -3.10 tools/fetch_cc0.py all` downloads into `assets_src/textures/cc0/<id>/` (git-ignored),
  checks md5 and size, copies shipping files to `game/assets/textures/cc0/<id>/`, and registers them.
- Textures ship as `basecolor.jpg`, `normal.jpg` (OpenGL convention), `roughness.jpg`. HDRIs ship as
  `environment.hdr`.

## Contact sheet

- `"C:\Program Files\Blender Foundation\Blender 5.3\blender.exe" --background --factory-startup --python assets_src/textures/build_contact_sheet.py`
  writes `assets_src/textures/contact_sheet.png`.

## Rules

- Never hand-edit `ASSET_MANIFEST.json` or `THIRD_PARTY_LICENSES.md`.
- Do not create Godot `.import` files by hand.
- Downloads go only through the pinned Poly Haven URLs. The User-Agent is `asset-fetch/1.0`.
