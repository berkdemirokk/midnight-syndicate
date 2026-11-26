# Arden Bruiser build notes

Brief: docs/art/CAR_BRUISER_BRIEF.md. Pipeline: `blender --background --factory-startup --python build_car.py` (about 12 s),
then `validate_car.py`, `render_car.py -- cycles renders <views>`, then `py -3.10 tools/ship_bruiser.py`.

- body.py: the hero's surface engine with new curve data (long bonnet, power bulge function `bulge`, cabin set back,
  fastback, constant 585 mm roof edge so the side-glass cut is a straight x plane, length 4.80 + nose cap + tail ring).
- details.py: grille and two headlight pods are pockets cut into the body (lens and emitter are offset copies of the removed
  faces), fender vent, hood blade vents, full-width tail bar (two halves with a notch), quad exhaust, plate ARDEN.
- wheels.py: six-spoke concave rim, 19 in front / 20 in rear (rim lip radius 0.250 / 0.264), 48 segments.
- Rounds: r1 first look (interior liner plate showed through the rear wheel: liner now starts above the arch crown),
  r2 grille bars were behind the recess floor (moved forward), chin and splitter width, r3 mirror width (2.11 m to 1.92 m)
  and L_TOTAL 4.85 to 4.80, then Cycles finals in renders/.
- Known defects: see report.json known_defects.
