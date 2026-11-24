extends Node3D
## Stand-in track for the HUD captures: a closed rounded loop as minimap points. Not a capture scenario.

const LOOP_POINTS: int = 96
const RX: float = 420.0
const RZ: float = 260.0
const WOBBLE: float = 0.12


func get_minimap_points() -> PackedVector2Array:
	var out := PackedVector2Array()
	for i: int in LOOP_POINTS:
		var a: float = TAU * float(i) / float(LOOP_POINTS)
		var r: float = 1.0 + WOBBLE * sin(3.0 * a)
		out.append(Vector2(cos(a) * RX * r, sin(a) * RZ * r))
	return out
