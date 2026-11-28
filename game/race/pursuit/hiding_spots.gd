class_name HidingSpots
extends RefCounted
## Hiding spots: track stretches where the escape cooldown fills MULT times faster while no police car is in view.
## Stretches are fractions of the track length (0 = start line, 1 = one lap), so they need no geometry: the tracks have
## no side-street data yet. shortcut: rule zones, not built side streets; a real side road would need its own mesh.

const MULT: float = 2.0
const SPOTS: Dictionary = {
	"res://world/city_01/city_01.tscn": [Vector2(0.10, 0.16), Vector2(0.38, 0.44), Vector2(0.62, 0.68), Vector2(0.86, 0.92)],
	"res://world/istanbul_bogaz/istanbul_bogaz.tscn": [Vector2(0.12, 0.19), Vector2(0.41, 0.47), Vector2(0.68, 0.74), Vector2(0.88, 0.93)],
	"res://world/istanbul_maslak/istanbul_maslak.tscn": [Vector2(0.08, 0.14), Vector2(0.33, 0.40), Vector2(0.57, 0.63), Vector2(0.80, 0.86)],
}


## The fraction ranges of one track. Empty for a track with no spots (the dev circuit, tests).
static func spots_for(track_scene: String) -> Array:
	return SPOTS.get(track_scene, [])


## Index of the spot the progress (metres along the track) is in, or -1.
static func index_at(track_scene: String, progress_m: float, lap_m: float) -> int:
	if lap_m <= 0.0:
		return -1
	var f: float = fposmod(progress_m, lap_m) / lap_m
	var spots: Array = spots_for(track_scene)
	for i: int in spots.size():
		var r: Vector2 = spots[i]
		if f >= r.x and f < r.y:
			return i
	return -1


## Cooldown rate: MULT while in a spot and no police car is in view, else 1.
static func cooldown_mult(in_spot: bool, police_in_view: bool) -> float:
	return MULT if in_spot and not police_in_view else 1.0
