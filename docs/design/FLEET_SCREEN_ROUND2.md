# Fleet screen round 2: vinish.dev car bodies

Date: 2026-11-28. Machine: Windows 11, Python 3.10 with numpy 2.2.6 (CPU only). Scripts and raw output live in the lead's scratchpad (fleet_screen.py, fleet_screen_out.json).

## Method

- Candidates: 35 car GLBs from the vinish.dev category pages (sports-cars, electric-cars, classic-cars, muscle-cars, taxis, vans, emergency-vehicles), downloaded to `assets_src/third_party/vinish_cars/incoming3/` with `source.json`. Racing, sports and low-poly-cars pages list no GLBs. Skipped as non-cars: chargers, charging parts, taxi signs/shelters/meter/call box, `ev-battery-chassis`, `motorhome`, `vintage-delivery-truck`, fire engines, ladder/rescue trucks, water tender, airport fire truck, police command truck.
- Geometry: parse GLB JSON and BIN directly, apply node transforms, keep primitives whose material name matches `Paint` or `Body` (interiors, wheels and trim excluded). Each model is centred on its painted-vertex bounding box and scaled so its long axis is 4.6 m.
- Test: share of candidate painted vertices with an exact reference vertex within 1 cm (1 cm grid cells, 27-cell neighbourhood, exact distance check). A candidate is DISTINCT when below 35% against all references and all kept candidates. Candidates are processed in file order; a DISTINCT one joins the kept set.
- References: the 41 vinish car GLBs already downloaded (vinish_cars/ and incoming2/). This is a superset of the 18 shipped bodies, so DISTINCT verdicts are conservative. Downloaded-but-unshipped incoming2 cars were used as references only and not re-screened as candidates.
- Self-check: a model against itself gives 100%; a 2 cm shift of the same model gives 4.8%.

## Results

Nearest-body share is the best single reference match. Verdict follows the 35% rule only; it says nothing about how the car looks or plays.

| slug | url | tris (all prims) | class guess | nearest downloaded body | within 1 cm vs all refs, % | verdict | notes |
|---|---|---|---|---|---|---|---|
| ambulance | https://vinish-models.pages.dev/emergency/ambulance.glb | 112,819 | ambulance (van class) | panel-van | 7.8 | DISTINCT | Under 35% overlap with all downloaded bodies; highest overlap with a kept candidate: n/a. |
| crew-van | https://vinish-models.pages.dev/vans/crew-van.glb | 108,224 | van | panel-van | 15.2 | DISTINCT | Under 35% overlap with all downloaded bodies; highest overlap with a kept candidate: 0.34%. |
| electric-van | https://vinish-models.pages.dev/vans/electric-van.glb | 114,770 | EV van | panel-van | 11.3 | DISTINCT | Under 35% overlap with all downloaded bodies; highest overlap with a kept candidate: 1.38%. |
| fire-command-car | https://vinish-models.pages.dev/emergency/fire-command-car.glb | 190,518 | command SUV/van | gt-race-supercar | 9.4 | DISTINCT | Under 35% overlap with all downloaded bodies; highest overlap with a kept candidate: 1.21%. |
| high-roof-van | https://vinish-models.pages.dev/vans/high-roof-van.glb | 125,998 | high-roof van | panel-van | 9.3 | DISTINCT | Under 35% overlap with all downloaded bodies; highest overlap with a kept candidate: 2.72%. |
| luton-van | https://vinish-models.pages.dev/vans/luton-van.glb | 115,804 | Luton box van | panel-van | 0.9 | DISTINCT | Under 35% overlap with all downloaded bodies; highest overlap with a kept candidate: 0.61%. |
| muscle-wagon | https://vinish-models.pages.dev/muscle-cars/muscle-wagon.glb | 151,385 | muscle wagon | police-car | 32.2 | DISTINCT | Under 35% overlap with all downloaded bodies; highest overlap with a kept candidate: 2.62%. |
| passenger-van | https://vinish-models.pages.dev/vans/passenger-van.glb | 121,301 | minibus / passenger van | panel-van | 9.7 | DISTINCT | Under 35% overlap with all downloaded bodies; highest overlap with a kept candidate: 6.25%. |
| refrigerated-van | https://vinish-models.pages.dev/vans/refrigerated-van.glb | 122,985 | van (box) | panel-van | 12.9 | DISTINCT | Under 35% overlap with all downloaded bodies; highest overlap with a kept candidate: 14.64%. |
| retro-camper | https://vinish-models.pages.dev/vans/retro-camper.glb | 108,535 | camper van | panel-van | 7.2 | DISTINCT | Under 35% overlap with all downloaded bodies; highest overlap with a kept candidate: 5.19%. |
| step-van | https://vinish-models.pages.dev/vans/step-van.glb | 120,981 | step van | panel-van | 12.0 | DISTINCT | Under 35% overlap with all downloaded bodies; highest overlap with a kept candidate: 8.2%. |
| touring-car | https://vinish-models.pages.dev/classic-cars/touring-car.glb | 48,634 | classic touring car | boattail-speedster | 15.3 | DISTINCT | Under 35% overlap with all downloaded bodies; highest overlap with a kept candidate: 5.69%. |
| tradesman-van | https://vinish-models.pages.dev/vans/tradesman-van.glb | 113,317 | van | panel-van | 14.7 | DISTINCT | Under 35% overlap with all downloaded bodies; highest overlap with a kept candidate: 15.66%. |
| vintage-convertible | https://vinish-models.pages.dev/classic-cars/vintage-convertible.glb | 50,917 | classic convertible | boattail-speedster | 18.4 | DISTINCT | Under 35% overlap with all downloaded bodies; highest overlap with a kept candidate: 7.24%. |
| vintage-coupe | https://vinish-models.pages.dev/classic-cars/vintage-coupe.glb | 53,967 | classic coupe | streamline-coupe | 13.4 | DISTINCT | Under 35% overlap with all downloaded bodies; highest overlap with a kept candidate: 9.09%. |
| vintage-limousine | https://vinish-models.pages.dev/classic-cars/vintage-limousine.glb | 62,074 | classic limousine | streamline-coupe | 10.6 | DISTINCT | Under 35% overlap with all downloaded bodies; highest overlap with a kept candidate: 11.28%. |
| vintage-pickup | https://vinish-models.pages.dev/classic-cars/vintage-pickup.glb | 42,510 | classic pickup | streamline-coupe | 11.4 | DISTINCT | Under 35% overlap with all downloaded bodies; highest overlap with a kept candidate: 11.01%. |
| vintage-roadster | https://vinish-models.pages.dev/classic-cars/vintage-roadster.glb | 50,903 | classic roadster | boattail-speedster | 12.9 | DISTINCT | Under 35% overlap with all downloaded bodies; highest overlap with a kept candidate: 12.21%. |
| vintage-sedan | https://vinish-models.pages.dev/classic-cars/vintage-sedan.glb | 59,104 | classic saloon | streamline-coupe | 12.7 | DISTINCT | Under 35% overlap with all downloaded bodies; highest overlap with a kept candidate: 12.62%. |
| vintage-taxi | https://vinish-models.pages.dev/classic-cars/vintage-taxi.glb | 50,122 | classic taxi | drag-ready-coupe | 11.2 | DISTINCT | Under 35% overlap with all downloaded bodies; highest overlap with a kept candidate: 20.86%. |
| woodie-wagon | https://vinish-models.pages.dev/classic-cars/woodie-wagon.glb | 53,252 | classic woodie wagon | boattail-speedster | 13.0 | DISTINCT | Under 35% overlap with all downloaded bodies; highest overlap with a kept candidate: 21.5%. |
| black-suv-cab | https://vinish-models.pages.dev/taxis/black-suv-cab.glb | 160,536 | SUV taxi | super-suv | 95.3 | NOT_DISTINCT | 95.3% overlap with the downloaded set (closest single body super-suv at 93.49%); reject as shared or near-shared body. |
| bumblebee-stripe-coupe | https://vinish-models.pages.dev/muscle-cars/bumblebee-stripe-coupe.glb | 128,454 | muscle coupe | pursuit-coupe | 37.8 | NOT_DISTINCT | 37.8% overlap with the downloaded set (closest single body pursuit-coupe at 12.94%); reject as shared or near-shared body. |
| crossover-taxi | https://vinish-models.pages.dev/taxis/crossover-taxi.glb | 157,333 | crossover taxi | super-suv | 99.0 | NOT_DISTINCT | 99.0% overlap with the downloaded set (closest single body super-suv at 98.01%); reject as shared or near-shared body. |
| electric-taxi | https://vinish-models.pages.dev/taxis/electric-taxi.glb | 138,246 | EV saloon taxi | ev-hatchback | 97.9 | NOT_DISTINCT | 97.9% overlap with the downloaded set (closest single body ev-hatchback at 96.42%); reject as shared or near-shared body. |
| ev-city-car | https://vinish-models.pages.dev/electric-cars-and-chargers/ev-city-car.glb | 111,047 | EV city hatch | pocket-rocket-hatch | 97.1 | NOT_DISTINCT | 97.1% overlap with the downloaded set (closest single body pocket-rocket-hatch at 96.9%); reject as shared or near-shared body. |
| ev-crossover | https://vinish-models.pages.dev/electric-cars-and-chargers/ev-crossover.glb | 156,116 | EV crossover SUV | super-suv | 99.4 | NOT_DISTINCT | 99.4% overlap with the downloaded set (closest single body super-suv at 98.34%); reject as shared or near-shared body. |
| hybrid-taxi | https://vinish-models.pages.dev/taxis/hybrid-taxi.glb | 132,086 | hybrid saloon taxi | electric-super-gt | 95.1 | NOT_DISTINCT | 95.1% overlap with the downloaded set (closest single body electric-super-gt at 93.76%); reject as shared or near-shared body. |
| mid-engine-sports-coupe | https://vinish-models.pages.dev/sports-cars/mid-engine-sports-coupe.glb | 129,121 | sports coupe (mid-engine) | gt-race-supercar | 93.2 | NOT_DISTINCT | 93.2% overlap with the downloaded set (closest single body gt-race-supercar at 90.86%); reject as shared or near-shared body. |
| muscle-convertible | https://vinish-models.pages.dev/muscle-cars/muscle-convertible.glb | 129,454 | muscle convertible | pursuit-coupe | 49.3 | NOT_DISTINCT | 49.3% overlap with the downloaded set (closest single body pursuit-coupe at 16.56%); reject as shared or near-shared body. |
| muscle-hardtop | https://vinish-models.pages.dev/muscle-cars/muscle-hardtop.glb | 131,749 | muscle hardtop | drag-ready-coupe | 94.7 | NOT_DISTINCT | 94.7% overlap with the downloaded set (closest single body drag-ready-coupe at 93.05%); reject as shared or near-shared body. |
| muscle-sedan | https://vinish-models.pages.dev/muscle-cars/muscle-sedan.glb | 145,151 | muscle saloon | supercharged-street-machine | 44.4 | NOT_DISTINCT | 44.4% overlap with the downloaded set (closest single body supercharged-street-machine at 19.0%); reject as shared or near-shared body. |
| rapid-response-car | https://vinish-models.pages.dev/emergency/rapid-response-car.glb | 154,236 | response car | rally-hatchback | 93.1 | NOT_DISTINCT | 93.1% overlap with the downloaded set (closest single body rally-hatchback at 90.42%); reject as shared or near-shared body. |
| two-tone-hardtop | https://vinish-models.pages.dev/muscle-cars/two-tone-hardtop.glb | 132,233 | muscle hardtop | supercharged-street-machine | 82.3 | NOT_DISTINCT | 82.3% overlap with the downloaded set (closest single body supercharged-street-machine at 79.3%); reject as shared or near-shared body. |
| vinyl-top-coupe | https://vinish-models.pages.dev/muscle-cars/vinyl-top-coupe.glb | 128,312 | muscle coupe | pursuit-coupe | 48.9 | NOT_DISTINCT | 48.9% overlap with the downloaded set (closest single body pursuit-coupe at 17.77%); reject as shared or near-shared body. |

Totals: 35 candidates, 21 DISTINCT, 14 NOT_DISTINCT.

## Notes for the lead

- Many DISTINCT verdicts are vans and classic cars. The 35% rule passes them, but several share a family look (the vintage group, the vans), so check them visually before adding to the roster.
- The `nearest downloaded body` column uses the reference set above, not the shipped list. A NOT_DISTINCT with a shipped body as nearest is a clear re-skin.
- Interiors and wheels are excluded, so two cars with different bodies but shared wheels still screen by body only.
- No render was made. Geometry only; graphics review is still needed for each car the lead keeps.
