extends "res://tests/test_case.gd"
## Tests for the FX pack (game/fx, game/shaders). Run at --fixed-fps 60.

const SPEC_PATH: String = "res://vehicles/specs/noctra_sable.tres"
const FlatWorld = preload("res://tests/helpers/flat_world.gd")
const START_H: float = 0.47  ## body origin height above flat ground at rest (as in test_vehicle)
const SCENES: Array[String] = [
	"res://fx/rain.tscn", "res://fx/nitro_flame.tscn", "res://fx/tire_smoke.tscn",
	"res://fx/sparks.tscn", "res://fx/speed_lines.tscn", "res://fx/headlights.tscn", "res://fx/car_fx.tscn",
]
const SHADERS: Array[String] = [
	"res://shaders/wet_asphalt.gdshader", "res://shaders/neon.gdshader", "res://shaders/speed_lines.gdshader",
]
## Uniform that must exist once each shader has compiled (a failed compile lists no uniforms).
const SHADER_PROBE_UNIFORM: Dictionary = {
	"res://shaders/wet_asphalt.gdshader": "planar_vp",
	"res://shaders/neon.gdshader": "energy",
	"res://shaders/speed_lines.gdshader": "intensity",
}


func test_scenes_instantiate() -> void:
	for path: String in SCENES:
		var packed := load(path) as PackedScene
		check(packed != null, "cannot load " + path)
		if packed == null:
			continue
		var n: Node = packed.instantiate()
		check(n != null, "cannot instantiate " + path)
		if n != null:
			n.free()
	await frames(1)


func test_shaders_compile_on_mesh() -> void:
	var holder := Node3D.new()
	add(holder)
	var mats: Array[ShaderMaterial] = []
	for path: String in SHADERS:
		var shader := load(path) as Shader
		check(shader != null, "cannot load " + path)
		if shader == null:
			continue
		# A shader that fails to compile exposes no uniforms: the probe uniform is the compile check.
		var names: Array[String] = []
		for u: Dictionary in shader.get_shader_uniform_list():
			names.append(str(u["name"]))
		check(names.has(SHADER_PROBE_UNIFORM[path]), "shader did not compile (no uniform %s): %s" % [SHADER_PROBE_UNIFORM[path], path])
		var mat := ShaderMaterial.new()
		mat.shader = shader
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(2, 2)
		mi.mesh = pm
		mi.material_override = mat
		holder.add_child(mi)
		mats.append(mat)
	await frames(4)
	for mat: ShaderMaterial in mats:
		check(mat.shader != null, "shader lost after frames")
	await cleanup([holder])


func test_planar_reflection_keeps_default_layer_and_feeds_material() -> void:
	var holder := Node3D.new()
	add(holder)
	var road := MeshInstance3D.new()
	road.mesh = PlaneMesh.new()
	road.layers = 1 << 1
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/wet_asphalt.gdshader") as Shader
	road.material_override = mat
	holder.add_child(road)
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 1.5, 10.0)
	holder.add_child(cam)
	cam.current = true
	var pr := PlanarReflection.new()
	holder.add_child(pr)
	pr.add_target_material(mat)
	# Default layer must be visible to the mirror, or the reflection is empty (the old bug).
	var mirror_cam: Camera3D = pr.get_child(0).get_child(0) as Camera3D
	check(mirror_cam != null, "mirror camera missing")
	if mirror_cam != null:
		check(mirror_cam.cull_mask & 1 != 0, "mirror camera culls the default layer")
		check(mirror_cam.cull_mask & (1 << 1) == 0, "mirror camera does not exclude the road layer")
	pr.set_enabled(true)
	await frames(3)
	check(mat.get_shader_parameter("planar_enabled") == 1.0, "planar_enabled not set on material")
	check(mat.get_shader_parameter("planar_reflection") != null, "planar texture not set on material")
	var vp: Variant = mat.get_shader_parameter("planar_vp")
	check(vp is Projection, "planar_vp not set on material")
	if vp is Projection:
		check((vp as Projection) != Projection.IDENTITY, "planar_vp is still identity")
	pr.set_enabled(false)
	check(mat.get_shader_parameter("planar_enabled") == 0.0, "planar_enabled not cleared")
	await cleanup([holder])


func test_car_fx_follows_nitro_signals() -> void:
	var spec := load(SPEC_PATH) as CarSpec
	var car := ArcadeCar.new()
	car.spec = spec
	add(car)
	var fx := load("res://fx/car_fx.tscn").instantiate() as CarFx
	car.add_child(fx)
	await frames(3)
	check(fx.flames != null, "flames not built")
	car.nitro_started.emit()
	await frames(2)
	check(_any_emitting(fx.flames), "nitro_started did not turn flames on")
	check(fx.flames.visible, "flame root hidden")
	car.nitro_ended.emit()
	await frames(2)
	check(not _any_emitting(fx.flames), "nitro_ended did not turn flames off")
	await cleanup([car])


func test_hit_above_threshold_triggers_sparks() -> void:
	var car := ArcadeCar.new()
	car.spec = load(SPEC_PATH) as CarSpec
	add(car)
	var fx := load("res://fx/car_fx.tscn").instantiate() as CarFx
	fx.spark_min_impulse = 1000.0
	car.add_child(fx)
	await frames(2)
	var before: int = fx.sparks.burst_count
	car.hit.emit(500.0, Vector3.ZERO)
	check(fx.sparks.burst_count == before, "sub-threshold hit must not spark")
	car.hit.emit(2000.0, Vector3(1, 0, 0))
	check(fx.sparks.burst_count == before + 1, "hit above threshold did not spark")
	await cleanup([car])


func test_default_car_fx_has_no_speed_lines_overlay() -> void:
	# race_scene gives every car a CarFx; an opponent must not draw a full-screen overlay.
	var car := ArcadeCar.new()
	car.spec = load(SPEC_PATH) as CarSpec
	add(car)
	var fx := load("res://fx/car_fx.tscn").instantiate() as CarFx
	car.add_child(fx)
	await frames(2)
	check(fx.speed_lines == null, "default CarFx built a speed-lines overlay")
	await cleanup([car])


func test_freeing_car_leaves_no_orphans() -> void:
	var before: int = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var car := ArcadeCar.new()
	car.spec = load(SPEC_PATH) as CarSpec
	add(car)
	car.add_child(load("res://fx/car_fx.tscn").instantiate())
	await frames(3)
	car.queue_free()
	await frames(4)
	var after: int = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	metric("node_delta_after_free", after - before)
	check(after <= before, "node count grew by %d after freeing the car" % (after - before))


func test_speed_lines_intensity_clamps() -> void:
	var sl := load("res://fx/speed_lines.tscn").instantiate() as SpeedLines
	add(sl)
	sl.set_intensity(5.0)
	check_range(sl.get_intensity(), 1.0, 1.0, "intensity above 1")
	sl.set_intensity(-3.0)
	check_range(sl.get_intensity(), 0.0, 0.0, "intensity below 0")
	sl.set_intensity(0.4)
	check_range(sl.get_intensity(), 0.4, 0.4, "intensity 0.4")
	sl.queue_free()
	await frames(1)


func test_tyre_smoke_silent_on_straight_acceleration_above_40() -> void:
	var ground: StaticBody3D = FlatWorld.make_ground(0.0)
	add(ground)
	var car := ArcadeCar.new()
	car.spec = load(SPEC_PATH) as CarSpec
	add(car)
	car.reset_to(Transform3D(Basis.IDENTITY, Vector3(0.0, START_H, 0.0)))
	var fx := load("res://fx/car_fx.tscn").instantiate() as CarFx
	car.add_child(fx)
	await frames(120)
	check(car.wheel_contact[2] and car.wheel_contact[3], "car not on the ground before the run")
	# Start at 60 km/h, straight, then floor it until 150 km/h.
	car.linear_velocity = Vector3(0.0, 0.0, -60.0 / 3.6)
	car.input.throttle = 1.0
	var reached: float = 0.0
	var smoke_frames: int = 0
	var max_frames: int = 60 * 90
	for f: int in max_frames:
		await frames(1)
		reached = maxf(reached, car.speed_kmh)
		if car.speed_kmh >= 40.0 and car.speed_kmh <= 150.0 and _smoke_emitting(fx):
			smoke_frames += 1
		if car.speed_kmh >= 150.0:
			break
	metric("straight_accel_top_kmh", reached)
	metric("straight_accel_smoke_frames", smoke_frames)
	check(reached >= 150.0, "car did not reach 150 km/h (top %.1f)" % reached)
	check(smoke_frames == 0, "straight acceleration above 40 km/h emitted smoke on %d frames" % smoke_frames)
	await cleanup([car, ground])


func test_drifting_car_emits_tyre_smoke() -> void:
	var ground: StaticBody3D = FlatWorld.make_ground(0.0)
	add(ground)
	var car := ArcadeCar.new()
	car.spec = load(SPEC_PATH) as CarSpec
	add(car)
	car.reset_to(Transform3D(Basis.IDENTITY, Vector3(0.0, START_H, 0.0)))
	var fx := load("res://fx/car_fx.tscn").instantiate() as CarFx
	car.add_child(fx)
	await frames(120)
	car.linear_velocity = Vector3(0.0, 0.0, -80.0 / 3.6)
	car.is_drifting = true
	await frames(1)
	check(car.is_drifting, "drift ended on the first tick; test needs a drift")
	check(_smoke_emitting(fx), "drifting car emitted no tyre smoke")
	await cleanup([car, ground])


func _smoke_emitting(fx: CarFx) -> bool:
	for e: GPUParticles3D in fx.smoke._emitters:
		if e.emitting:
			return true
	return false


func _any_emitting(node: Node) -> bool:
	for c: Node in node.get_children():
		if c is GPUParticles3D and (c as GPUParticles3D).emitting and not (c as GPUParticles3D).one_shot:
			return true
		if _any_emitting(c):
			return true
	return false
