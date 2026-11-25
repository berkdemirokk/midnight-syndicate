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
	if mirror_cam != null:
		check(mirror_cam.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF, "mirror camera interpolates physics (warning source)")
	pr.set_enabled(true)
	await frames(3)
	if mirror_cam != null:
		check(is_equal_approx(mirror_cam.far, minf(cam.far, pr.max_distance_m)), "mirror far plane %f, not the capped distance" % mirror_cam.far)
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
	check(fx.flames.is_emitting(), "nitro_started did not turn flames on")
	check(fx.flames.visible, "flame root hidden")
	car.nitro_ended.emit()
	await frames(2)
	check(not fx.flames.is_emitting(), "nitro_ended did not turn flames off")
	await cleanup([car])


func test_nitro_flames_are_unshaded_additive_and_only_on_nitro() -> void:
	var fl := load("res://fx/nitro_flame.tscn").instantiate() as NitroFlame
	add(fl)
	await frames(2)
	var meshes: Array[MeshInstance3D] = _flame_meshes(fl)
	check(meshes.size() == 4, "expected 2 flames x (core + halo), got %d meshes" % meshes.size())
	for mi: MeshInstance3D in meshes:
		var m := mi.material_override as StandardMaterial3D
		check(m != null and m.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, "flame material is lit")
		check(m != null and m.blend_mode == BaseMaterial3D.BLEND_MODE_ADD, "flame material is not additive")
		check(not mi.is_visible_in_tree(), "flame visible while nitro is off")
	fl.set_strength(1.0)
	fl.set_active(true)
	fl.pop()
	await frames(3)
	check(fl.is_emitting(), "set_active(true) did not start the flames")
	for mi: MeshInstance3D in meshes:
		check(mi.is_visible_in_tree(), "flame hidden while nitro is on")
	fl.set_active(false)
	await frames(2)
	check(not fl.is_emitting(), "set_active(false) did not stop the flames")
	for mi: MeshInstance3D in meshes:
		check(not mi.is_visible_in_tree(), "flame still visible after nitro ended")
	await cleanup([fl])


func test_nitro_start_at_rest_does_not_start_tyre_smoke() -> void:
	# The flames are the nitro effect. Tyre smoke comes only from slip, drift or launch wheelspin.
	var car := ArcadeCar.new()
	car.spec = load(SPEC_PATH) as CarSpec
	add(car)
	var fx := load("res://fx/car_fx.tscn").instantiate() as CarFx
	car.add_child(fx)
	await frames(3)
	car.nitro_started.emit()
	await frames(3)
	check(not _smoke_emitting(fx), "nitro start emitted tyre smoke")
	car.nitro_ended.emit()
	await cleanup([car])


func test_speed_lines_schedule() -> void:
	var sl := load("res://fx/speed_lines.tscn").instantiate() as SpeedLines
	add(sl)
	await frames(1)
	check_range(sl.intensity_for(140.0, true), 0.0, 0.0, "speed lines show below 150 km/h with nitro")
	check_range(sl.intensity_for(120.0, false), 0.0, 0.0, "speed lines show at 120 km/h")
	check(sl.intensity_for(200.0, true) > 0.5, "speed lines weak at 200 km/h with nitro")
	check(sl.intensity_for(180.0, false) > 0.5, "speed lines not clearly visible at 180 km/h")
	check(sl.intensity_for(200.0, true) > sl.intensity_for(200.0, false), "nitro does not strengthen speed lines")
	sl.set_speed(200.0, true)
	check(sl.get_intensity() > 0.5, "set_speed did not reach the shader")
	sl.queue_free()
	await frames(1)


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


## Static box with its centre at pos (default collision layer 1, the world mask rain.gd probes).
func _box_body(size: Vector3, pos: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = pos
	return body


func test_rain_shelter_fades_out_and_back() -> void:
	var holder := Node3D.new()
	add(holder)
	holder.add_child(_box_body(Vector3(20, 0.5, 20), Vector3(0, 6, 0)))  # roof 4.5 m above the camera
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.5, 0)
	holder.add_child(cam)
	cam.current = true
	var rain := load("res://fx/rain.tscn").instantiate() as RainFx
	holder.add_child(rain)
	await frames(40)
	check(rain.is_covered(), "roof 4.5 m above the camera not seen as cover")
	check(rain.rain_factor() < 0.01, "rain still at %.2f under cover after 0.67 s" % rain.rain_factor())
	check(not rain.is_raining(), "streaks still emitting or visible under cover")
	cam.position = Vector3(40, 1.5, 0)  # clear of the roof (x -10..10)
	await frames(40)
	check(not rain.is_covered(), "open sky reported as cover")
	check(rain.rain_factor() > 0.99, "rain did not come back in the open (%.2f)" % rain.rain_factor())
	check(rain.is_raining(), "streaks not emitting or visible in the open")
	await cleanup([holder])


func test_rain_splash_follows_road_height() -> void:
	var holder := Node3D.new()
	add(holder)
	holder.add_child(FlatWorld.make_ground(0.0))
	holder.add_child(FlatWorld.make_drop_platform(Vector2(10, 10), 2.0, Vector2(80, 0)))  # road top at y = 2
	var cam := Camera3D.new()
	cam.position = Vector3(0, 4, 0)
	holder.add_child(cam)
	cam.current = true
	var rain := load("res://fx/rain.tscn").instantiate() as RainFx
	holder.add_child(rain)
	await frames(10)
	check(absf(rain.ground_height() - 0.0) < 0.01, "splash height %.3f over flat ground, expected 0" % rain.ground_height())
	cam.position = Vector3(80, 4, 0)
	await frames(10)
	check(absf(rain.ground_height() - 2.0) < 0.01, "splash height %.3f over the platform, expected 2" % rain.ground_height())
	check(not rain.is_covered(), "platform top reported as cover")
	await cleanup([holder])


func _smoke_emitting(fx: CarFx) -> bool:
	for e: GPUParticles3D in fx.smoke._emitters:
		if e.emitting:
			return true
	return false


func _flame_meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for c: Node in node.find_children("*", "MeshInstance3D", true, false):
		out.append(c as MeshInstance3D)
	return out
