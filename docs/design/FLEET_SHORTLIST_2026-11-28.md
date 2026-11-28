# Fleet shortlist, 2026-11-28 (research only, nothing downloaded)

Scope: CC BY 4.0 car models for the mobile racer fleet. Owner downloads everything with their own Sketchfab login.
Status: 10 candidates verified on the model page (licence, Download 3D Model button, triangle count, real-make check). The brief asked for 24, so this is short by 14 and the 30-car roster target is not met.
Method: page fetch of each model URL on 2026-11-28 (WebFetch). Later fetches returned empty pages, so no further rows were added after that. Search snippets alone are not verified and are listed as leads only.
Carried forward from commit 39c5dc9 (marie645 x2, olliej08, Genbrugge): not re-fetched in this pass, marked below.
Real-make models are excluded by the no-real-make rule (see Excluded).

## Ranked shortlist (verified on page)

Triangle counts are the Sketchfab listing figures (before decimation). Licence = "Creative Commons Attribution" (CC BY 4.0) as shown on the page.

| Rank | Slug (suggested) | Title | Author (display / handle) | URL | Licence (page) | Tris | Class | Why it fits | Risks |
|---|---|---|---|---|---|---|---|---|---|
| 1 | donnichols_lowpoly_sports_car | Low-Poly Sports Car Free | donnichols / donnichols | https://sketchfab.com/3d-models/low-poly-sports-car-free-2b23201839fb43049454f431752073bb | CC Attribution | 5k (2.8k verts) | sport | Page says fully UV unwrapped and PBR textured (BaseColor, Metallic, Roughness, AO, MetallicSmoothness); generic, no make named | Low-poly stylised, not a realistic body; file format not listed on page (textures PNG 512-4096) |
| 2 | jerrydani_sports_car | sports car | JerryDani / JerryDani | https://sketchfab.com/3d-models/sports-car-8fab7c53472e41ea9f48110412a36566 | CC Attribution | 4.3k (2.6k verts) | sport | PBR textures stated (1024 PNG: base colour, metallic, roughness, normal, AO); generic tags | Format not listed on page; low poly |
| 3 | andrej_police_car | Low Poly Police Car | Andrew / @andrej.latisevfl | https://sketchfab.com/3d-models/low-poly-police-car-b6be4819db7e448d81816e5143389558 | CC Attribution | 11.2k (6.3k verts) | police | Police, no make named, textured in Maya | PBR not stated; formats not listed; creator asks for credit |
| 4 | sentientsundae_police_car | Low Poly Police Car | SentientSundae / SentientSundae | https://sketchfab.com/3d-models/low-poly-police-car-4f4cfeb02c384de89baddbee1ea4e28c | CC Attribution | 4.6k (3k verts) | police | Police, obj and fbx listed; model and texture created in Blender | PBR not stated; description signed -PK, which does not match the handle, so confirm the author before the credit line; reads low-poly |
| 5 | dz_canyon75_taxi | Canyon 75 Taxi (low poly model) | Daniel Zhabotinsky / @DanielZhabotinsky | https://sketchfab.com/3d-models/canyon-75-taxi-low-poly-model-9e8f92a215784f3d8aaaaeab1bef54c4 | CC Attribution | 20k (12.1k verts) | taxi | Taxi, textured interior, no make named (Canyon 75 is the model name); author states unconditional permission to use | Dense for mobile (decimate); PBR not stated; check the Canyon 75 name is not a brand |
| 6 | lexyc16_classic_muscle | Classic Muscle car | Lexyc16 / Lexyc16 | https://sketchfab.com/3d-models/classic-muscle-car-641efc889e5f4543bae51d0922e6f4b3 | CC Attribution | 5.6k (3.4k verts) | muscle | Muscle class; no make named on page | PBR not mentioned; reads generic low poly, check the shape is not a recognisable make |
| 7 | marie645_lowpoly_car | Low poly car (757 tris) | marie645 | https://sketchfab.com/3d-models/low-poly-car-f631273b65f740c2952ed6c7b7f7d570 | CC Attribution | 757 | hatch/street | Lightest candidate; already coloured | Carried forward from 39c5dc9, not re-fetched; low-poly, fallback only |
| 8 | olliej08_lowpoly_car | Low poly car, untextured, separate wheel material | olliej08 | https://sketchfab.com/3d-models/low-poly-car-1d04ecda030944b78a4445bcafbd6c25 | CC Attribution | 3400 | street | Wheels separate so they can spin; repaintable | Carried forward from 39c5dc9, not re-fetched; no PBR |
| 9 | genbrugge_ringland_car | Car (Ringland) | Bastien Genbrugge / @bastienBGR | https://sketchfab.com/3d-models/car-ringland-ecc2f9e9e9c840bf92ada8ca14b89a03 | CC Attribution | 2300 | street | Used in an animation (per 39c5dc9) | Carried forward, not re-fetched; PBR not stated |
| 10 | marie645_cabriolet | Low poly cabriolet car | marie645 | https://sketchfab.com/3d-models/low-poly-cabrioletcar-25f212fc4bc04bac8a4318d553b04089 | CC Attribution | 950 | classic/convertible | Adds a convertible | Carried forward, not re-fetched; low-poly, no PBR |

Rank 1 and 2 are the best verified fits: CC BY, downloadable, PBR stated, no make named.
Rank 7 to 10 are carried forward and are fallbacks only.

## Removed or downgraded in this pass

- Leoskateman "Old car toy" (previously rank 6): removed. The author string mixed two names and the title and tags point at a Chevrolet toy. Re-add only after the page is opened and the exact author name is copied.
- Rysky "Low Poly Sports Car" (previously rank 3): removed from the shortlist. The toy-like pixel look fails the realistic-proportions rule, and the NoAI notice forbids AI-dataset use, which the owner must decide on. Kept as a lead only.

## Excluded (checked, do not download)

- solid3DDD "Taxi 2" (https://sketchfab.com/3d-models/taxi-2-0b5310fbf2c14b3e807c63f2ee1ca7bf): CC BY and PBR, but the page says inspired by Dacia/Renault Logan and tags name renault and logan. Brand look-alike, excluded. "Taxi 1" by the same author is inspired by a Ford Crown Victoria, excluded.
- Miguel Vega "Free Delivery Truck" (1991 Chevrolet inspired) and similar real-make-inspired vans: excluded.
- Wardster "70 muscle car": based on a 1968 Plymouth Barracuda, excluded.
- ViktorKom "Muscle Car Concept": references Camaro, Challenger, Nissan GT-R and Mustang, excluded.
- American muscle car, massive-graphisme (https://sketchfab.com/3d-models/american-muscle-car-35d0e4c2310344f88823d7dbf955af26): an attempt to make a 1970 Dodge Challenger, excluded.
- Lexyc16 "Nissan Skyline R32 GT-R", klikker228666 "Toyota GT 86", Nieve5677 "Mercedes-Benz AMG GT43", MGB GT, Alpine A480, Porsche 963, NIO EP9, Toyota Supra low poly, Subaru Impreza: real makes, excluded.
- Ddiaz "2024 Nilu 27 Concept" and "2018 Inferno Settimo Cerchio": CC BY-NC-SA (non-commercial and share-alike), excluded.
- Polyjo "Yellow low poly sedan", "Police chase": CC BY-NC, excluded.
- Mattias.Lindblad "Sports Car": CC BY-NC, excluded.
- Veaceslav Condraciuc "American muscle car": Sketchfab Store royalty-free, not CC BY, excluded.
- rpalomino "Generic Sport Car Rusty Black": Store royalty-free, not CC BY, excluded.
- Mona x Supercars "Generic Supercar": CC BY, but about 300k triangles, too heavy to decimate sensibly, excluded.
- toddeppe "Race Car 01" / LMGT3: about 610k triangles, excluded.
- memoov DHL and FedEx vans: about 780k to 790k triangles, excluded.
- All CGTrader results (police, taxi, van, hypercar, muscle): royalty-free or paid licence, not CC BY, excluded.

## Unverified leads (search snippet only, page not fetched, need a page check before any use)

- Sba Stuff "Mini Van" (https://sketchfab.com/3d-models/mini-van-50fd1fa9a1084733b2792816a4c8ac0f): snippet says CC Attribution, about 1.7k tris, usable as road traffic. Best traffic-van lead. Fetch failed in this pass.
- Daniel Zhabotinsky "French delivery van" (https://sketchfab.com/3d-models/french-delivery-van-low-poly-model-a350a422d200485ea57778dc42139edc): snippet says CC Attribution, about 7k tris, permissive creator note. Check for a real French make look-alike before use.
- Comrade1280 "Generic passenger car pack" (https://sketchfab.com/3d-models/generic-passenger-car-pack-20f9af9b8a404d5cb022ac6fe87f21f5): snippet says CC Attribution, hatch and coupe variants about 6.8k tris, creator says no real-car resemblance. Hatch and GT lead. Fetch failed.
- Daniel Zhabotinsky "Cheetah 84" (https://sketchfab.com/3d-models/cheetah-84-low-poly-model-c967ab4abbc54ae4b7933fd81a86c99c): snippet says original design, CC Attribution. GT or sport lead. Fetch failed.
- Daniel Zhabotinsky "Negotiator 80 Taxi" (https://sketchfab.com/3d-models/80-american-taxi-sedan-low-poly-model-436ee962d7ff4397ba1c2d0c7ce998d5): snippet CC Attribution, second taxi. Fetch failed.
- Han66st "Generic Sport Car Low Poly" (https://sketchfab.com/3d-models/generic-sport-car-low-poly-7ad3bfb2bd7449c19698fc7d0592a601): snippet CC Attribution, 15.7k tris, but tags include mclaren, so check for McLaren styling. Fetch failed.
- Han66st "Super Car" (https://sketchfab.com/3d-models/super-car-c104a0a24ccf4bb7a3f589cc091c4ae0): snippet CC BY, super class lead, shape and tags unknown. Fetch failed.
- "low poly supercar" by the_86_guy: description says inspired by a 2011 Lamborghini Aventador, so excluded unless the page says otherwise.
- MZdesignart "Electric hypercar exterior design" (https://sketchfab.com/3d-models/electric-hypercar-exterior-design-3201809631a64f31a6166e548fccf6f2): snippet CC BY, bodywork only, full car about 200 MB. Hyper lead, probably too heavy.
- Builder "Hypercar" (https://sketchfab.com/3d-models/hypercar-ca175d53bdbd4ce997c03b18d0179523): snippet CC BY, credits a Bonfiredeveloper base model, base licence not checked. Hyper lead, check the base model.
- WhySoloco "80s Retro Hatchback Car" (https://sketchfab.com/3d-models/80s-retro-hatchback-car-free-1161aa5946124595bfcc271175fbc82d): snippet shows a CC label but a custom licence in the description, PBR tagged, about 15.9k tris. Read LICENSE.txt before use.
- Iron Howl V8, Piotr Kupsc future car, cyberpunk car: leads from the earlier pass, sci-fi or stylised, probably out of scope.
- German 70s hatchback, lowpoly (https://opengameart.org/content/german-70s-hatchback-lowpoly): CC-BY 4.0 on OpenGameArt, not Sketchfab. Hatch lead. Check the licence line and that it is not a real make.

## Gaps (classes with no verified candidate)

- Police (2): 2 verified (Andrew, SentientSundae). Covered.
- Taxi/van (traffic): taxi 1 verified (Canyon 75). Van: none verified. Mini Van (Sba Stuff) and the French delivery van are leads.
- Muscle: 1 verified (Lexyc16). Covered at minimum.
- GT: none verified. Cheetah 84 and the Comrade1280 coupe are leads.
- Super: none verified. Han66st Super Car is a lead.
- Hyper: none verified. Builder Hypercar and MZdesignart are leads, both heavy or base-licence unknown.
- Hatch: marie645 (carried forward). Comrade1280 and the German 70s hatch are leads.

To reach 24, a second pass is needed, with the Creative Commons Attribution and Downloadable filters on and each page fetched in a session where page content returns. Mark any class still empty as a gap.

## Owner download steps (Sketchfab account needed; Sketchfab requires login for downloads)

1. Open each verified URL above while logged in to Sketchfab.
2. Confirm the licence line reads "Creative Commons Attribution" and the page shows "Download 3D Model".
3. Click Download 3D Model. Choose "glTF (Original format)" or "glb". Do not pick FBX, OBJ or USDZ for the pipeline.
4. Unzip into a new folder: assets_src/vehicles/incoming/<slug>/ (slug from the table, e.g. donnichols_lowpoly_sports_car).
5. Keep the licence text and author line from the page and send them back with the folder, so the lead can record them in ASSET_MANIFEST.json and THIRD_PARTY_LICENSES.md and add the credit line to game/ui/credits_third_party.txt.
6. Do not run any script on the downloaded files until the lead has reviewed them.

## Attribution and licence notes

- Every model above is CC BY 4.0, so the author credit is required in game/ui/credits_third_party.txt. Use the display name and handle shown on the page.
- SentientSundae: confirm the author on the page before writing the credit line (the -PK signature).
- Triangle counts are the listing counts; decimation targets are set by the lead, not here.
