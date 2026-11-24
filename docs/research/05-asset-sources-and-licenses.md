# 05 Asset sources, licenses and local image-to-3D tools

Scope: free, commercially usable 3D/texture/HDRI/audio sources for a rainy night city street racer (iOS, offline), plus local image-to-3D tools for an 8 GB RTX 5060 Ti.
Date of research: 2026-11-24. Tags: [S] = read in the source during this session; [E] = estimate or inference, or only seen in a search snippet. Anything not loaded is marked as such.

## Sources

| URL | What it gave | Loaded |
|---|---|---|
| https://polyhaven.com/license | All assets CC0; no credit needed; website content restricted | yes |
| https://polyhaven.com/our-api | API base, no key, User-Agent header required, free incl. commercial | yes |
| https://api.polyhaven.com/assets?type=textures&category=asphalt-bitumen/asphalt | Endpoint named on the textures page (listing itself not rendered) | no (URL seen on page) |
| https://github.com/Poly-Haven/Poly-Haven-API | HTTP 404 | no |
| https://docs.ambientcg.com/api/v2/ | v2 endpoints; v2 deprecated, v3 recommended | yes |
| https://docs.ambientcg.com/license/ | CC0 1.0, no attribution, commercial and game use allowed | yes |
| https://ambientcg.com/ | Points to license page; CC0 statement | yes |
| https://ambientcg.com/view?id=Asphalt031 | Asphalt PBR set, JPG/PNG 1K-8K, CC0 (site FAQ) | yes |
| https://ambientcg.com/list?type=material&q=asphalt | Category labels only; no asset rows rendered | yes (empty) |
| https://polyhaven.com/a/asphalt_02 | Asphalt 02: dry matte, CC0, 8K | yes |
| https://polyhaven.com/textures/asphalt | Asset grid not rendered; API link only | yes (partial) |
| https://polyhaven.com/hdris?c=urban | Only canary_wharf visible; time of day not stated | yes (partial) |
| https://quaternius.com/ | Pack names/paths; license NOT stated on home page | yes |
| https://quaternius.com/packs/cars.html | CC0, 8 car models, "Made possible by Patreon supporters" | yes |
| https://kenney.nl/support | Assets CC0; credit optional; logo not to be used separately | yes |
| https://kenney.nl/assets/car-kit | Car Kit, CC0 (model count and formats not shown) | yes |
| https://kenney.nl/assets/racing-kit | Racing Kit, CC0; tags suggest track tiles and cars | yes |
| https://sketchfab.com/licenses | Only Editorial and Standard types described | yes |
| https://opengameart.org/content/faq | HTTP 403 | no |
| https://opengameart.org/ | HTTP 403 | no |
| https://freesound.org/help/faq/ | CC0, CC-BY, CC-BY-NC, legacy Sampling+; NC and AI-training limits | yes |
| https://freesound.org/search/?q=car+engine+loop&f=license:"Creative+Commons+0" | CC0-filtered engine-loop hits (per-sound license not shown) | yes |
| https://github.com/VAST-AI-Research/TripoSR | MIT code and weights; about 6 GB VRAM default | yes |
| https://github.com/microsoft/TRELLIS | MIT code; at least 16 GB VRAM | yes |
| https://github.com/Tencent-Hunyuan/Hunyuan3D-2 | 6 GB shape-only, 16 GB shape+texture | yes |
| https://huggingface.co/tencent/Hunyuan3D-2 | License tag tencent-hunyuan-community | yes |
| https://github.com/Tencent-Hunyuan/Hunyuan3D-2/blob/main/LICENSE | EU/UK/South Korea excluded; >1M MAU needs Tencent license | yes |
| https://github.com/TencentARC/InstantMesh | Code Apache-2.0; VRAM not stated | yes |
| https://huggingface.co/TencentARC/InstantMesh | Weights tag apache-2.0 | yes |
| https://github.com/TencentARC/InstantMesh/blob/main/LICENSE | Apache-2.0 text; no commercial restriction | yes |
| https://github.com/Stability-AI/stable-fast-3d | About 6 GB VRAM (text fetched; ambiguous, verify); license not read | yes (partial) |
| https://huggingface.co/stabilityai/stable-fast-3d | Stability AI Community License; $1M annual revenue cap; gated | yes |
| https://arxiv.org/pdf/2606.25300 (HiFiVe) | Snippet only: native 3D generators miss fine surface detail | no (snippet) |
| https://arxiv.org/pdf/2608.28080 (Cyc3D) | Snippet only: smoothness and tessellation criteria | no (snippet) |
| https://arxiv.org/pdf/2410.08181 (RGM) | Snippet only: car single-image metrics (Chamfer, F-score) | no (snippet) |
| https://freesound.org/s/614627/ | Snippet only: a comment calls it CC0; license field not seen | no (snippet) |
| https://opengameart.org/content/car-tire-squeal-skid-loop | Snippet only: listed as CC-BY 3.0 | no (snippet) |

## 1. License facts per source

**Poly Haven** (textures, HDRIs, models)
- CC0, no attribution required; assets may be redistributed. [S] https://polyhaven.com/license
- API: base https://api.polyhaven.com, no key for default endpoints, unique User-Agent header required. [S] https://polyhaven.com/our-api
- Endpoints documented: GET /assets (object keyed by ID; `type` 0=HDRI, 1=Texture, 2=Model), GET /files/{id} (download URLs by format and resolution with md5). [S] https://polyhaven.com/our-api
- Filter form `?type=textures&category=asphalt-bitumen/asphalt` appears on the textures page. [S] https://polyhaven.com/textures/asphalt ; exact filter syntax on /assets not confirmed in docs. [E]
- Rate limits not documented; "best effort" stability; page asks you to credit Poly Haven in live API tools. [S] https://polyhaven.com/our-api
- Attribution is not a license requirement but the API page asks for it in user-facing tools. [S] https://polyhaven.com/our-api

**ambientCG** (PBR materials)
- CC0 1.0 for all assets, including raw files in games; no restriction listed. [S] https://docs.ambientcg.com/license/
- API v2 is deprecated ("does not receive updates anymore"); v3 recommended. [S] https://docs.ambientcg.com/api/v2/
- v2 endpoints: /categories-json, /downloads_csv, /full_json, /releases_rss; all GET; `downloadLink` (logs stats, redirects) and `rawLink` (direct). No findAssets endpoint in the v2 page. [S] https://docs.ambientcg.com/api/v2/
- v3 URL pattern not loaded. Use v3 docs before scripting. [E] (not fetched)
- No API key or rate limit mentioned on v2 page. [S] https://docs.ambientcg.com/api/v2/

**Quaternius** (low-poly models, city/vehicle packs)
- Pack pages show CC0 (Cars pack links to the CC0 1.0 page). [S] https://quaternius.com/packs/cars.html
- Home page does not state the license. [S] https://quaternius.com/ ; treat each pack page as the source of truth. [E]
- Pack names seen: Downtown City MegaKit (/packs/downtowncitymegakit.html), Modular Streets Pack (/packs/modularstreets.html), Cars Pack (/packs/cars.html). [S] https://quaternius.com/
- No API. Manual download. [E]

**Kenney** (game assets: vehicles, roads, UI)
- CC0 (described as public-domain). Commercial use allowed. Credit optional. [S] https://kenney.nl/support
- Per-asset license file ships inside each download; check it. [S] https://kenney.nl/support
- Car Kit and Racing Kit both CC0. [S] https://kenney.nl/assets/car-kit ; https://kenney.nl/assets/racing-kit
- No API. Manual download. [E]

**Sketchfab** (per-model)
- License set per model, not site-wide. [S] https://sketchfab.com/licenses (fetched page showed Editorial and Standard types only).
- Editorial: no commercial use, no advertising or merchandise. [S] https://sketchfab.com/licenses
- Standard: commercial use not barred by type; sublicensing and standalone distribution barred; some content categories barred. [S] https://sketchfab.com/licenses
- Per-model Creative Commons types (CC0, CC-BY, CC-BY-NC, etc.) exist on the site from memory, but were NOT confirmed in this session. [E]
- Rule for us: only use models whose page shows CC0 or CC-BY (or Standard with commercial-friendly terms), and record the author credit for CC-BY. [E]
- API: Sketchfab Data API exists (v3) but was not loaded; treat scripted download as not verified. [E]

**OpenGameArt** (mixed-license community site)
- Site pages returned HTTP 403 twice. License rules NOT verified. [S: failed]
- Search snippet lists a car tire squeal skid loop as CC-BY 3.0 (attribution required). [E] https://opengameart.org/content/car-tire-squeal-skid-loop
- Rule: every asset must be checked per page; GPL and CC-BY-NC are common and must be filtered out. [E]
- No API used. [E]

**Freesound** (audio)
- License types: CC0 (sell, remix, no authorship claim); CC-BY (credit); CC-BY-NC (credit, no earning from the work); legacy Sampling+ being retired. [S] https://freesound.org/help/faq/
- Attribution list: credit title, uploader, sound link, license. [S] https://freesound.org/help/faq/
- NC clips may not be used in commercial products. Do not use NC or Sampling+ sounds in a paid iOS game. [S] https://freesound.org/help/faq/ (+ E for the app-store interpretation)
- AI training with CC-BY-NC sounds is restricted in commercial settings. [S] https://freesound.org/help/faq/
- API: the FAQ mentions an API exists but gives no key/endpoint. Freesound API v2 normally needs a token from the account page. Pattern not verified this session. [E]
- Per-sound license is shown on each sound page; the search filter result is only a hint. [S] https://freesound.org/search/?q=car+engine+loop&f=license:"Creative+Commons+0"

**CC0 engine and tire sound candidates (verify license on each page)**
- Engine loop candidates from a CC0-filtered search: https://freesound.org/s/369053/ ; https://freesound.org/s/843123/ ; https://freesound.org/s/748027/ ; https://freesound.org/s/594215/ ; https://freesound.org/s/325810/ [S for listing; license of each [E] until opened]
- Tire squeal: https://freesound.org/s/614627/ is a possible CC0 by comment only. [E] Not loaded.
- Tire-skid pack on Unity Asset Store is paid; not usable as "free". [E] https://assetstore.unity.com/packages/audio/sound-fx/tire-skids-and-screeches-145886

## 2. Concrete candidate assets (rainy night street)

Only pages marked [S] were opened. Everything else is a slug to check on the site before use.

**Asphalt / road textures (need 4; wet-capable)**
1. https://polyhaven.com/a/asphalt_02 : CC0, dry matte, 8K. [S] Wet only via roughness/puddle maps in the engine. [E]
2. https://ambientcg.com/view?id=Asphalt031 : CC0, PBR JPG/PNG 1K-8K, no wet description. [S] Wet look via shader. [E]
3. Poly Haven asphalt category (list via https://api.polyhaven.com/assets?type=textures&category=asphalt-bitumen/asphalt): pick 2 more by slug; not opened. [E]
4. ambientCG Asphalt category (list via https://ambientcg.com/list?type=material&q=asphalt): pick 1 more with wet-looking albedo; not opened. [E]

**Concrete / sidewalk (need 3)**
- Poly Haven concrete category: search https://polyhaven.com/textures/concrete ; pick 3 by slug. Not opened. [E]
- ambientCG concrete category: https://ambientcg.com/list?type=material&q=concrete . Not opened. [E]

**Building facade / wall materials (need 4)**
- Poly Haven brick and plaster listing: https://polyhaven.com/textures/brick (not opened). [E]
- ambientCG brick/plaster/concrete wall: https://ambientcg.com/list?type=material&q=brick (not opened). [E]
- Take two brick, one plaster, one painted concrete with a tile or shopfront feel. [E]

**Metal (need 2)**
- Poly Haven metal listing: https://polyhaven.com/textures/metal (not opened). Pick corrugated/rust sheet and painted steel. [E]

**Night urban HDRIs (need 2)**
1. https://polyhaven.com/a/canary_wharf : urban HDRI, time of day not confirmed. [S exists] Night? [E: unverified]
2. Second HDRI: not found in this session. Browse https://polyhaven.com/hdris/streets-town or query https://api.polyhaven.com/assets?type=hdris . [E]

**Vehicle sources (for reference, not requested but relevant)**
- Kenney Car Kit (CC0): https://kenney.nl/assets/car-kit [S]
- Kenney Racing Kit (CC0, track and car tags): https://kenney.nl/assets/racing-kit [S]
- Quaternius Cars pack (CC0, 8 cars): https://quaternius.com/packs/cars.html [S]

## 3. Local image-to-3D tools (8 GB RTX 5060 Ti)

| Tool | Code license | Weights license | VRAM (reported) | Commercial verdict |
|---|---|---|---|---|
| TripoSR | MIT [S] https://github.com/VAST-AI-Research/TripoSR | MIT, README says covers models [S] | about 6 GB, default, single image [S] | Yes under MIT [E] |
| TRELLIS | MIT (submodules separate) [S] https://github.com/microsoft/TRELLIS | not separately named [S] | at least 16 GB [S] | Does NOT fit 8 GB [S/E] |
| Hunyuan3D-2 | Tencent Hunyuan license tag [S] https://huggingface.co/tencent/Hunyuan3D-2 | tencent-hunyuan-community [S] | 6 GB shape only; 16 GB shape+texture [S] https://github.com/Tencent-Hunyuan/Hunyuan3D-2 | NO for EU, UK, South Korea; >1M MAU needs Tencent license [S] https://github.com/Tencent-Hunyuan/Hunyuan3D-2/blob/main/LICENSE |
| InstantMesh | Apache-2.0 [S] https://github.com/TencentARC/InstantMesh/blob/main/LICENSE | apache-2.0 [S] https://huggingface.co/TencentARC/InstantMesh | not stated [S] | Yes (license-wise) [E] |
| SF3D (Stable Fast 3D) | not read (LICENSE.md not loaded) [S: failed] | Stability AI Community License; free up to $1M annual revenue; gated [S] https://huggingface.co/stabilityai/stable-fast-3d | about 6 GB per README text [S, verify] | Only under $1M revenue; needs Stability enterprise license above [S] |

Notes:
- Hunyuan3D-2 territory and MAU clauses come from the LICENSE file fetched on GitHub; they bar use in the EU, which matters for an EU-based dev. [S]
- SF3D's 6 GB figure appeared in the fetched text for that repo; the same line also appeared for TripoSR. Treat as unverified until the SF3D README is checked locally. [E]
- Community license terms can change; re-check before shipping. [E]

## 4. Mesh quality for hard-surface vehicles

- No public benchmark specifically on hard-surface car panels was found. [S: search summary of arXiv results, none dedicated]
- Car single-image papers use Chamfer distance and F-score, which measure overall shape, not panel sharpness. [S] https://arxiv.org/pdf/2410.08181
- HiFiVe reports native 3D generators (incl. TRELLIS) recover structure but miss fine surface detail and high-frequency texture. [S: snippet] https://arxiv.org/pdf/2606.25300
- Cyc3D proposes smoothness and tessellation-efficiency checks for generated meshes. [S: snippet] https://arxiv.org/pdf/2608.28080
- Wheels, glass and panel gaps are the usual weak points in generated cars. [E]

Verdict: generated car meshes are usable as blockout and proportion reference only, not final game assets. [E] Reasons: no published evidence of clean panel edges or wheel geometry (above), low triangle hygiene needing retopology, and texture detail below an iOS-ready bar. Final cars should come from CC0 kits (Kenney, Quaternius) or a paid/commissioned model with a written license.

## 5. Design and engineering consequences

1. Use CC0 sources only for shipped assets (Poly Haven, ambientCG, Kenney, Quaternius). Avoid Sketchfab per-model and OpenGameArt unless each asset is checked and credited. [E]
2. Keep an attribution file anyway: Poly Haven asks for credit in API tools; CC-BY assets need it. [S/E]
3. Do not ship Freesound NC or Sampling+ audio in a paid iOS build. [S + E]
4. Do not use Hunyuan3D-2 for an app distributed in the EU or UK. [S]
5. TRELLIS does not run on 8 GB. Plan TripoSR or InstantMesh for blockouts only. [S/E]
6. Prefer ambientCG v3 or Poly Haven API for scripted import; v2 is deprecated. [S]
7. Wet asphalt needs roughness and puddle masks authored in-engine; source sets are dry. [S for asphalt_02 dry; E for approach]

## 6. Top findings (tagged)

1. Poly Haven and ambientCG assets are CC0 with no credit required; both are safe to ship in a paid iOS game. [S] https://polyhaven.com/license ; https://docs.ambientcg.com/license/
2. ambientCG API v2 is deprecated; script against v3. [S] https://docs.ambientcg.com/api/v2/
3. Poly Haven API needs no key but requires a unique User-Agent header; base https://api.polyhaven.com. [S] https://polyhaven.com/our-api
4. Freesound NC licenses forbid commercial use of the work; use CC0 only for a paid app. [S] https://freesound.org/help/faq/
5. Hunyuan3D-2 license excludes the EU, UK and South Korea and requires a Tencent grant above 1M MAU. [S] https://github.com/Tencent-Hunyuan/Hunyuan3D-2/blob/main/LICENSE
6. TRELLIS needs at least 16 GB VRAM, so it will not run on the 8 GB card. [S] https://github.com/microsoft/TRELLIS
7. TripoSR (MIT, about 6 GB) and InstantMesh (Apache-2.0) are the license-clean local options for blockouts. [S] https://github.com/VAST-AI-Research/TripoSR ; https://github.com/TencentARC/InstantMesh/blob/main/LICENSE
8. Generated car meshes are blockout reference only; no public evidence they reach clean hard-surface quality. [E] (supported by [S] snippets https://arxiv.org/pdf/2606.25300)

## 7. Failed or incomplete sources

- https://github.com/Poly-Haven/Poly-Haven-API : HTTP 404. Use https://polyhaven.com/our-api instead.
- https://opengameart.org/ and https://opengameart.org/content/faq : HTTP 403 (both). OpenGameArt license rules are unverified.
- https://github.com/Stability-AI/stable-fast-3d LICENSE.md : not read; code license for SF3D unverified.
- https://polyhaven.com/textures/asphalt and https://ambientcg.com/list?type=material&q=asphalt : asset grids did not render; candidate slugs unverified.
- https://polyhaven.com/hdris?c=urban : only one HDRI visible.
- Freesound API docs and ambientCG v3 docs: not fetched.
- Sketchfab per-model CC license pages: not fetched.

## Verification pass

Date: 2026-11-24. Eight highest-cost claims re-opened with WebFetch. WebFetch returns a model summary, so quoted wording is as the summary returned it. Verdicts: confirmed, wrong, unverifiable.

1. Poly Haven assets are CC0, no credit required, commercial use allowed: confirmed. https://polyhaven.com/license
2. ambientCG assets are CC0 1.0, no credit, commercial and game use allowed: confirmed. https://docs.ambientcg.com/license/
3. ambientCG v2 API "does not receive updates anymore", v3 recommended: confirmed. The page does not use the word "deprecated"; the file's "deprecated" is a paraphrase. https://docs.ambientcg.com/api/v2/
4. Poly Haven API: no key for default endpoints, unique User-Agent required, base https://api.polyhaven.com: confirmed. https://polyhaven.com/our-api
5. Freesound CC-BY-NC: no earning from the work; not for commercial AI training: confirmed. https://freesound.org/help/faq/
6. Hunyuan3D-2 license excludes EU, UK and South Korea; above 1M MAU needs a Tencent grant: confirmed. https://github.com/Tencent-Hunyuan/Hunyuan3D-2/blob/main/LICENSE
7. TRELLIS needs at least 16 GB VRAM ("at least 16GB of memory"); code MIT: confirmed. https://github.com/microsoft/TRELLIS
8. SF3D Community License: free up to US $1,000,000 annual revenue, Enterprise License above, gated: confirmed. https://huggingface.co/stabilityai/stable-fast-3d

Result: 8 checked, 8 confirmed, 0 wrong, 0 unverifiable. No tags changed.
