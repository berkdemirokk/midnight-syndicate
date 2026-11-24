# CITY 01 — "Arden Bay / Neon Wharf Loop" track brief

Owner: Art Director (Fable). Acceptance contract for the first night city circuit.
Everything is original: fictional city, fictional shop names, fictional adverts. No real brands,
logos, landmarks or copied signage.

## Read in 5 seconds
Rain-soaked street circuit at 1 a.m. Wet asphalt mirrors neon. Cyan and magenta signage against
warm sodium street lamps and deep blue-black sky. Dense, tall, close: the city is a canyon, then
it opens to the bay for one breath, dives into a lit underpass, and squeezes through an old
market hairpin back to the start.

Palette: sky `#070A14`, fog `#101A2E`, sodium lamp `#FFB36B`, cool lamp `#BFD8FF`,
neon cyan `#19E6FF`, neon magenta `#FF2BD6`, neon amber `#FFC23D`, accent red `#FF3B30`.

## Circuit (Blender coords: X east, Y north, Z up, metres). Clockwise. Closed loop.
Centreline control points, smoothed with a closed centripetal Catmull-Rom spline and resampled
every 2 m. Road width 14 m (4 lanes) unless stated.

| # | x | y | z | note |
|---|---|---|---|---|
| 0 | 0 | -150 | 0 | main straight begins (Neon Strip) |
| 1 | 0 | 0 | 0 | START/FINISH, race direction +Y |
| 2 | 0 | 250 | 0 | end of straight, braking zone |
| 3 | 60 | 330 | 0 | T1, 90 degree right |
| 4 | 160 | 340 | 0 | Downtown canyon |
| 5 | 260 | 300 | 1.5 | S-curve part 1, climbing |
| 6 | 330 | 340 | 3 | S-curve part 2, on the overpass |
| 7 | 430 | 330 | 3 | overpass crest |
| 8 | 500 | 250 | 1.5 | fast right sweep, descending |
| 9 | 510 | 120 | 0 | Waterfront straight (bay on the east side) |
| 10 | 510 | -80 | 0 | end of waterfront |
| 11 | 480 | -200 | -2.5 | right turn, descending into the underpass |
| 12 | 380 | -250 | -4 | Underpass (covered, 5.2 m clear height) |
| 13 | 240 | -250 | -4 | Underpass |
| 14 | 150 | -230 | -2 | exit ramp, climbing |
| 15 | 90 | -300 | 0 | Old Market, road 16 m wide from here to point 17 |
| 16 | 20 | -330 | 0 | hairpin entry |
| 17 | -40 | -270 | 0 | hairpin exit (radius at least 28 m on the centreline) |
| 18 | -25 | -200 | 0 | kink back onto the main straight |

Checks the generator must print: lap length (expected 2200 to 2500 m), minimum centreline radius
(at least 28 m), maximum gradient (at most 6%), no two non-adjacent centreline samples closer
than 45 m in plan except where the underpass exit runs near the hairpin (report the value).

## Districts
| district | span | buildings | light character |
|---|---|---|---|
| Neon Strip | points 18-2 | 8 to 20 storeys, shops at street level, both sides, continuous street wall | heaviest neon, big vertical signs, video billboards, cool lamps |
| Downtown canyon | 3-8 | 25 to 45 storey towers, glass and concrete, overpass with parapets and columns | cool office windows, red aircraft lights, few signs |
| Waterfront | 8-11 | street wall on the west side only; east side railing, promenade, bay, far skyline and crane silhouettes | sodium lamps in a long row, reflections on water |
| Underpass | 11-14 | concrete walls, columns between carriageways removed (single tube), ceiling strip lights, ventilation fans, wall stripe | continuous cool strip light rhythm, amber warning lights at portals |
| Old Market | 14-18 | 2 to 5 storey brick and plaster shop houses, awnings, roller shutters, hanging signs, string lights across the street | warm, lanterns, amber and red neon |

## Road and street section
- Asphalt carriageway with 1.5% crown, lane lines (dashed white, worn), solid edge lines,
  start/finish band, grid boxes for 8 cars, arrows before T1, zebra crossings at 4 places.
- Kerb 0.15 m high, 0.3 m wide. Sidewalk 3.5 m (paving slab material), building line behind it.
- Drain grates and manhole covers as mesh decals. Puddle mask painted along the gutters and in
  random low patches (vertex colour R channel on the road mesh: 0 dry-ish wet, 1 standing water).
- Barriers: concrete jersey barriers on the outside of every corner and along the waterfront
  railing base, steel guardrail on the overpass. Chevron boards at T1, the sweep and the hairpin.
- Collision: road + sidewalk as trimesh; continuous invisible wall 3 m high along both
  building lines; barriers as boxes. A car must not be able to leave the circuit anywhere.
- UVs in metres: U across the road, V along it. Vertex colours as above. Chunked every ~120 m
  (about 20 chunks) so culling and LOD work.

## Building kit (no bare boxes)
Each building is assembled from facade modules, so every wall has depth:
- ground floor: shopfront with recessed glazing, door, stall riser, fascia sign band, awning or canopy;
- upper floors: window bays with reveals at least 0.12 m deep, frames, sills, some balconies or AC
  boxes, pilasters or mullions, floor bands;
- top: cornice or parapet, rooftop plant (AC units, tanks, antennas, ladders), some billboard frames.
At least 10 building types (3 Neon Strip, 3 Downtown towers, 2 Old Market, 1 waterfront warehouse,
1 parking structure), each with 2 material variants. Windows use an emissive atlas: per-window
random choice of dark / warm lit / cool lit / blinds / TV flicker tint, about 35% lit.
Triangle budget per building LOD0: 3 000 to 12 000; LOD1 at most 30%; LOD2 is a box with a baked
or atlas facade (allowed ONLY for LOD2 and the far skyline).

## Props kit
Street lamp (two variants: sodium arm lamp, cool double LED), traffic light, neon sign boards
(12 designs: vertical blade signs, box signs, arrow signs, one large animated-style billboard
frame), 6 billboard poster textures, bus shelter, bollard, bin, bench, planter, newspaper box,
fire hydrant, utility box, overhead cable spans, string lights, market awning stalls, railing,
jersey barrier, guardrail, chevron board, traffic cone, container stack and crane silhouette for
the bay, parked-car slots (filled later with car LOD2).

Fictional sign names to use (original): `KOI NOODLE BAR`, `HOTEL ARDEN`, `PIXEL ARCADE`,
`MOTO GARAGE 24H`, `BLUE HERON SUSHI`, `LUMEN CINEMA`, `ORBIT RECORDS`, `NIGHT OWL DINER`,
`AMPERE ENERGY`, `HARBOR PAWN`, `ZENITH TOWER`, `SYNDICATE CLUB`, `KAPI DONER`, `EGE TEA HOUSE`.
(Lead correction: KIRIN, EFES and VOLT were dropped because they collide with real drink brands.)
Typeface: any font shipped with Windows that allows embedding in rendered images, or shapes
drawn by script. Never a traced logo.

## Materials and textures
- Third-party PBR textures: CC0 only (ambientCG, Poly Haven), 1K for props and facades, 2K for the
  road. Each download is recorded in THIRD_PARTY_LICENSES.md and ASSET_MANIFEST.json with URL,
  asset id, licence and resolution at the moment it is downloaded.
- Generated textures (window atlas, signs, posters, road markings, puddle mask) are made by script
  and recorded as "generated, project-owned".
- Neon and windows are emissive with HDR strength so the engine glow picks them up.

## Lighting data handed to the engine
`city_01_layout.json` lists every instance (asset id, position, rotation, scale, district) and
every light (type, position, direction, colour, energy, range, casts_shadow false by default),
plus reflection probe boxes (one per ~60 m of road, extents matching the street canyon) and the
racing line / grid / checkpoint transforms. The engine builds the scene from this file with
MultiMesh for repeated props.

## Budgets (whole visible frame, High preset on mobile)
At most 450 000 triangles and 350 draw calls in any view from the road; at most 24 dynamic lights
affecting a frame, 8 per mesh (Mobile renderer limit, confirm in research file 04).

## Required evidence
Blender renders (real, not viewport grabs): top-down layout map with labels, and street-level
views in each of the five districts (1600x900, night lighting, wet road look approximated).
Then in-engine screenshots from the capture harness. A district passes only when the street view
does not read as "boxes on a plane": there must be facade depth, signage, street furniture,
light rhythm and a readable road edge.
