extends SceneTree
## Diagnostic probe (not a test): horizontal rays across the road at a few track offsets of city_01,
## printing every hit (collider owner name, distance from the racing line, lateral position).
## godot --headless --path game -s res://ai/diag_probe_walls.gd

const SCENE_PATH: String = "res://world/city_01/city_01.tscn"
var OFFSETS: PackedFloat32Array = PackedFloat32Array([])
var SCAN_FROM: float = 1080.0
var SCAN_TO: float = 1190.0
var SCAN_STEP: float = 2.0
var SCAN_Y: float = 0.5
const RAY_Y: float = 0.5


func _initialize() -> void:
	call_deferred("_probe")


func _probe() -> void:
	var city: CityBuilder = (load(SCENE_PATH) as PackedScene).instantiate() as CityBuilder
	root.add_child(city)
	var space: PhysicsDirectSpaceState3D = city.get_world_3d().direct_space_state
	var sc: float = SCAN_FROM
	var worst: float = 99.0
	while sc <= SCAN_TO:
		var cc: Vector3 = city.get_point_at(sc)
		var tt: Vector3 = city.get_tangent_at(sc)
		var rr: Vector3 = Vector3(-tt.z, 0.0, tt.x)
		var qq := PhysicsRayQueryParameters3D.create(cc + Vector3(0.0, SCAN_Y, 0.0), cc + Vector3(0.0, SCAN_Y, 0.0) + rr * 16.0)
		var hh: Dictionary = space.intersect_ray(qq)
		if not hh.is_empty():
			var lt: float = ((hh["position"] as Vector3) - cc).dot(rr)
			print("SCAN s=%.0f right_hit_lat=%+.2f %s" % [sc, lt, str((hh["collider"] as Object).name)])
			worst = minf(worst, lt)
		sc += SCAN_STEP
	print("SCAN min right hit lateral %.2f" % worst)
	for s: float in OFFSETS:
		var c: Vector3 = city.get_point_at(s)
		var t: Vector3 = city.get_tangent_at(s)
		var rgt: Vector3 = Vector3(-t.z, 0.0, t.x)
		print("== s=%.1f centre=(%.2f, %.2f) right=(%.3f, %.3f)" % [s, c.x, c.z, rgt.x, rgt.z])
		for side: float in [1.0, -1.0]:
			var a: Vector3 = c + Vector3(0.0, RAY_Y, 0.0)
			var b: Vector3 = a + rgt * side * 16.0
			var q := PhysicsRayQueryParameters3D.create(a, b)
			var hit: Dictionary = space.intersect_ray(q)
			if hit.is_empty():
				print("   side %+.0f: no hit within 16 m" % side)
				continue
			var hp: Vector3 = hit["position"]
			var lat: float = (hp - c).dot(rgt)
			var col: Object = hit["collider"]
			print("   side %+.0f: hit at lateral %+.2f m, collider %s (%s)" % [side, lat, str(col.name), col.get_class()])
	quit(0)
