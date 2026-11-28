# Motion LOD review, 2026-11-28

Machine: Windows 11 dev PC, NVIDIA RTX 5060 Ti 8 GB, Godot 4.7.2, Mobile renderer. Not a phone. No number here is a phone number.

## Status: partial. No pop is confirmed in frames.

What was done:
- Chase and side reels recorded for bogaz, city and maslak, day and night (`gameplay_reel --tod`, 8 fps, 20 s).
  The side reels barely show traffic, so the chase reels are the ones used for judgement.
- Code review of every LOD switch in the owned files. Fades were added where a switch was hard or where the
  two sides of a switch did not share a fade band.
- Tests extended. Targeted runs (car asset, landmarks, greenery, event dressing): 0 failed.

What was NOT done:
- Frame-by-frame pop hunt in motion. The before and after reels are not frame-aligned (the runs are not
  deterministic after about frame 10), so a same-index before/after comparison is not usable. No pop was
  confirmed with a frame number, and no before/after crop shows a pop disappearing. The pop list below is
  therefore code-review candidates only.
- Dithering of the ShaderMaterial surfaces (greenery foliage, landmarks, event boards) is not proven. The
  greenery comment says the fade needs a dither shader, and the foliage and landmark shaders have no fade code.
  If those surfaces do not dither, the margins added there are harmless no-ops and the hard pops remain.
- `game/world/street_fronts/**` was not touched (lead area). Not checked there.

## Changes (owned files)

| File | Before | After | Why |
|---|---|---|---|
| `game/vehicles/noctra_sable/car_lod.gd` | LOD0 faded out over 22-24 m, LOD1 starts hard at 22 m; LOD1 and LOD2 had no begin fade | LOD1 and LOD2 begin margin = `fade_margin_m` (2 m) | The next LOD must fade in over the band the last one fades out. Mirror copies stay hard by design. |
| `game/world/landmarks/landmarks.gd` | LOD switches at 120 m and 320 m hard; photo wall ends hard at 320 m | 6 m fade band at both switches (`LOD_FADE_M`); photo wall fades out over 6 m | Hard switch at a visible silhouette change. |
| `game/world/greenery/greenery.gd` | Hard LOD switches at 60, 150, 320 m; blobs end hard at 220 m; photo multimesh hard end | 6 m fade band (`FADE_M`) on every LOD, blob and photo node | Same reason. Unverified on ShaderMaterial, see above. |
| `game/world/event_dressing/event_dressing.gd` | Hard end at 260, 300, 220 m | 6 m fade-out (`FADE_M`) on each multimesh | Same reason. Cable lines not changed. |

Owned but unchanged: `game/traffic/**` (already has 30/80/170 m with a 4 m fade band on each switch, paired
correctly), `game/world/city_01/parked_cars.gd` (has no visibility setting; parked cars use city_builder's
`_make_mmi`, which already fades, and city_builder is not in the owned set).

## Pop candidates (code review, not frame-confirmed)

1. Car LOD0 to LOD1 at 22 m and LOD1 to LOD2 at 70 m (fixed by the begin margin). Confirmed by code only.
2. Landmark LOD switches at 120 m and 320 m, and the photo wall end at 320 m (fixed with the 6 m band).
3. Greenery switches at 60, 150, 320 m and blob end at 220 m (margins added; dither unverified).
4. Event dressing ends at 220, 260, 300 m (fade-out added).
5. Parked cars: switch at the city cell range. Not changed. city_builder is not owned.

## Evidence

Reels (not committed, too large): `evidence/screens/gameplay_reel/` in the scratchpad copies, six chase reels before
and six after. Viewed: `bogaz_chase_day` before and after frames 60-75 at 400 px. Both look the same; no pop
seen at this resolution. The frame strips are not committed.

## Checks

- Targeted tests: `test_car_asset` 12/0, `test_landmarks` 7/0, `test_greenery` 6/0, `test_event_dressing` 7/0.
- Full suite (`run_tests.gd`, no filter): 546 tests, 0 failed, exit 0.
