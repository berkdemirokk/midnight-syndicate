extends "res://tests/test_case.gd"
## Probe only, no gameplay change. Which rule does Jolt use to combine a wall's friction with the body's friction?
## A box hits a wall at 15 deg glancing and 120 km/h. Body and wall friction are swept as pairs, so the result shows which
## of the two values wins (equal values cannot tell the rules apart). Kept speed per case goes to evidence/handling/wall_rule.json.

const HZ: float = 60.0
const V0: float = 120.0 / 3.6
const GLANCE_DEG: float = 15.0
const TICKS: int = 120  ## 2 s: contact at about 0.25 s, then the body slides along the wall
const CASES: Array = [
	{"name": "body1_wall1", "body": 1.0, "wall": 1.0},
	{"name": "body1_wall005", "body": 1.0, "wall": 0.05},
	{"name": "body005_wall1", "body": 0.05, "wall": 1.0},
	{"name": "body005_wall005", "body": 0.05, "wall": 0.05},
	{"name": "body1_wall1_rough_wall", "body": 1.0, "wall": 1.0, "rough": true},
]


func _run_case(wall_friction: float, body_friction: float, wall_rough: bool) -> Dictionary:
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var mat := PhysicsMaterial.new()
	mat.friction = wall_friction
	mat.rough = wall_rough
	wall.physics_material_override = mat
	var ws := BoxShape3D.new()
	ws.size = Vector3(0.5, 6.0, 300.0)
	var wcs := CollisionShape3D.new()
	wcs.shape = ws
	wall.add_child(wcs)
	wall.position = Vector3(3.25, 3.0, 0.0)  # wall face at x = 3
	add(wall)

	var body := RigidBody3D.new()
	body.gravity_scale = 0.0
	body.lock_rotation = true
	body.mass = 1200.0
	var bmat := PhysicsMaterial.new()
	bmat.friction = body_friction
	body.physics_material_override = bmat
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.0, 1.0, 4.0)
	var bcs := CollisionShape3D.new()
	bcs.shape = bs
	body.add_child(bcs)
	body.position = Vector3(0.0, 0.5, 0.0)
	add(body)
	var rad: float = deg_to_rad(GLANCE_DEG)
	body.linear_velocity = Vector3(V0 * sin(rad), 0.0, V0 * cos(rad))  # into the wall, and along it

	await frames(TICKS)
	var v: Vector3 = body.linear_velocity
	var kept: float = v.length() / V0
	var along: float = v.z / (V0 * cos(rad))
	var into: float = absf(v.x) / (V0 * sin(rad))
	await cleanup([body, wall])
	return {"kept_speed": kept, "along_wall_ratio": along, "into_wall_residual": into, "end_speed_kmh": v.length() * 3.6}


func test_wall_friction_rule_lowest_wins() -> void:
	var results: Array = []
	for c: Dictionary in CASES:
		var r: Dictionary = await _run_case(c["wall"], c["body"], c.get("rough", false))
		r["case"] = c["name"]
		r["wall_friction"] = c["wall"]
		r["body_friction"] = c["body"]
		r["wall_rough"] = c.get("rough", false)
		results.append(r)
		metric(c["name"] + "_kept_speed", r["kept_speed"])
		metric(c["name"] + "_along_wall_ratio", r["along_wall_ratio"])
		print("WALLRULE %s kept %.4f along %.4f into %.4f" % [c["name"], r["kept_speed"], r["along_wall_ratio"], r["into_wall_residual"]])
		check(not is_nan(r["kept_speed"]) and r["kept_speed"] >= 0.0 and r["kept_speed"] <= 1.05, "%s kept speed out of range" % c["name"])

	var dir: String = ProjectSettings.globalize_path("res://").path_join("../evidence/handling").simplify_path()
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join("wall_rule.json"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"glance_deg": GLANCE_DEG, "speed_kmh": 120.0, "hz": HZ, "ticks": TICKS, "engine": "Jolt Physics, Godot 4.7.2, headless 60 Hz", "cases": results}, "\t"))
		f.close()
	else:
		check(false, "could not write evidence/handling/wall_rule.json")
	# Jolt combines the pair by the lower friction: any pair with a 0.05 side gives the same kept speed (to 0.01),
	# and the 1.0 / 1.0 pair keeps much less. Highest-wins or a geometric mean would fail these checks.
	var k: Dictionary = {}
	for r: Dictionary in results:
		k[r["case"]] = r["kept_speed"]
	var low: float = k["body005_wall1"]
	check(absf(low - k["body1_wall005"]) < 0.01, "body 1.0 / wall 0.05 (%.4f) should match body 0.05 / wall 1.0 (%.4f)" % [k["body1_wall005"], low])
	check(absf(low - k["body005_wall005"]) < 0.01, "body 0.05 / wall 0.05 (%.4f) should match body 0.05 / wall 1.0 (%.4f)" % [k["body005_wall005"], low])
	check(k["body1_wall1"] < low - 0.1, "body 1.0 / wall 1.0 should keep less speed than any 0.05 pair")
