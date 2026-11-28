extends "res://devtools/capture_scenario.gd"
## Renders the garage collection thumbnails: every available car in its default paint (not the player's saved colour:
## the thumbnails are shipped files), 3/4 front, studio light, transparent background, 480x240.
## Output: res://assets/ui/car_thumbs/<id>.png (generated, project-owned; re-run after a car model changes).

const OUT_DIR: String = "res://assets/ui/car_thumbs/"
const W: int = 480
const H: int = 240
const STAGE: Script = preload("res://ui/showroom/showroom_stage.gd")


func run() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(W * 2, H * 2)  # rendered at 2x, scaled down for clean edges
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	tree.root.add_child(vp)
	var world := Node3D.new()
	vp.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.52, 0.56)
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_energy = 2.2
	key.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	world.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.9
	fill.rotation_degrees = Vector3(-20.0, -140.0, 0.0)
	world.add_child(fill)
	var cam := Camera3D.new()
	cam.fov = 26.0
	world.add_child(cam)
	cam.current = true
	var yaw: float = 0.62
	var pitch: float = deg_to_rad(9.0)
	var target := Vector3(0.0, 0.58, 0.0)
	cam.position = target + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * 7.4
	cam.look_at(target, Vector3.UP)
	var made: int = 0
	for id: String in CarCatalog.available_ids():
		var packed: PackedScene = load(CarCatalog.scene_path(id)) as PackedScene
		if packed == null:
			continue
		var car: Node3D = packed.instantiate() as Node3D
		if car is CarLod:
			(car as CarLod).force_lod0 = true
		world.add_child(car)
		CarMaterials.set_reflection(car, STAGE.studio_pano(), 0.8, 1.4, 2.2)
		await cap.wait_frames(12)
		await RenderingServer.frame_post_draw
		var img: Image = vp.get_texture().get_image()
		img.resize(W, H, Image.INTERPOLATE_LANCZOS)
		var path: String = OUT_DIR + id + ".png"
		if img.save_png(ProjectSettings.globalize_path(path)) == OK:
			made += 1
		car.queue_free()
		await cap.wait_frames(2)
	# one harness shot so the run counts: a contact sheet of the thumbnails on graphite
	var rows: int = maxi(1, ceili(float(CarCatalog.available_ids().size()) / 4.0))  # the roster grows: the sheet grows with it
	var sheet := Image.create(W * 4, H * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(MSTheme.GRAPHITE)
	var i: int = 0
	for id: String in CarCatalog.available_ids():
		var p: String = ProjectSettings.globalize_path(OUT_DIR + id + ".png")
		var t := Image.load_from_file(p)
		if t != null:
			t.convert(Image.FORMAT_RGBA8)
			sheet.blend_rect(t, Rect2i(0, 0, W, H), Vector2i((i % 4) * W, (i / 4) * H))
		i += 1
	var shot_dir: String = ProjectSettings.globalize_path("res://../evidence/screens/ui_car_thumbs/")
	DirAccess.make_dir_recursive_absolute(shot_dir)
	sheet.save_png(shot_dir + "contact_sheet.png")
	vp.queue_free()
	if made == 0:
		cap.fail("no thumbnails rendered")
		return
	print("[THUMBS] %d thumbnails in %s" % [made, OUT_DIR])
	var view := TextureRect.new()  # the harness shot shows the sheet itself
	view.texture = ImageTexture.create_from_image(sheet)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tree.root.add_child(view)
	await cap.wait_frames(5)
	await cap.shot("contact_sheet_view")
	view.queue_free()
