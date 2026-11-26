# Photo-texture pipeline (generated pictures on simple geometry)

Owner decision, night of 2026-11-26: move the look from low-poly stylised to photo-like, at zero cost. What works:
a picture made by ChatGPT image generation (owner's Plus account) is mapped on very simple geometry, and a second
picture of the same thing at night is its glow map. First use: `game/world/street_fronts/photo_fronts.gd`,
`game/world/street_fronts/photo_facade.gdshader`, `game/tests/test_photo_fronts.gd` (commit 077a3db). Read those three
files before writing code and copy their pattern.

## Getting a picture
1. Chrome is reached with the `mcp__claude-in-chrome__*` tools. Open your OWN new tab (`tabs_create_mcp`), go to
   https://chatgpt.com/ and start a NEW chat. Never reuse another session's chat or tab.
2. Type the request, press Return, wait 60 to 120 s (check that no stop button is shown).
3. Save it by running this in the page (the file lands in `C:\Users\berk\Downloads`):
   `const imgs=[...document.querySelectorAll('main img[alt^="Oluşturulan"]')]; const b=await fetch(imgs.at(-1).src).then(r=>r.blob()); const a=document.createElement('a'); a.href=URL.createObjectURL(b); a.download='<name>.png'; document.body.appendChild(a); a.click(); a.remove();`
4. Copy it to `assets_src/ai_generated/chatgpt/<name>.png` (the source is kept). Write the shipped texture as JPG (PNG
   when it needs alpha) with power-of-two sides, for example 2048x1024, under `game/assets/...`.
5. Run `--import` once, set `mipmaps/generate=true` in the new `.import` file, run `--import` again.
6. Night version: in the same chat ask "Edit the image you just made, pixel-aligned, same framing and size; everything
   nearly black, only the lights glow". It is used as the emission map.
If Chrome or ChatGPT cannot be reached after three tries, stop and say so in the report. Never fake a texture.

## Prompt rules for every picture
- Orthographic straight-on view, zero perspective, the subject fills the frame edge to edge, flat even light, no cast
  shadows, photorealistic materials.
- No real brand names, no logos, no real car makes, no recognisable real people, no copyrighted characters.
- No text unless the brief lists the game's own words; then check every word letter by letter.
- Never upload an image to ChatGPT. Never use the owner's concept pictures as textures or backgrounds.

## Records
One record per shipped texture in `ASSET_MANIFEST.json`: `"source": "generated:ai"`, `"license": "project-owned"`, a
note that says it was generated with ChatGPT image generation from a text prompt for this project and names the source
PNG. Pattern: the `photo_front_facade_row_01*` records. `py -3.10 tools/asset_factory.py validate` must end with
`0 failing`.

## Rules for a parallel session
- Work only in your worktree and only in the files your task names. Commit on your own branch; messages end with
  `Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>`. Never push, never merge, never touch `main`, never delete
  other people's files.
- Do not edit `game/project.godot`, `game/tests/run_tests.gd`, `game/race/race_scene.gd`, or anything under
  `evidence/screens/ortakoy_benchmark/` (after a benchmark capture copy the shots you need into your own
  `evidence/screens/<name>/` folder and restore that folder with `git checkout -- evidence/screens/ortakoy_benchmark`).
- Do not loosen an existing test to make it pass.
- Godot: `C:\Users\berk\tools\godot\Godot_v4.7.2-stable_win64_console.exe`. Every run uses `--audio-driver Dummy` and a
  shell `timeout`. A new worktree has no `.godot` folder: run
  `godot --headless --audio-driver Dummy --path game --import` once first (several minutes).
- Frame budget: at most 500 draw calls and 450000 primitives (read `perf` in the capture JSON).
- Tokens: the owner is short on usage. Read only the files you need, never dump whole logs, look at no more than six
  images in total and prefer cropped or half-size views, start no subagents. Final report under 200 words: branch,
  commit SHAs, what changed, capture paths, draw calls and primitives, what is still weak.
