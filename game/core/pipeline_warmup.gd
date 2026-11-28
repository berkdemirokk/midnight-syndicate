class_name PipelineWarmup
extends RefCounted
## First-use warm-up while the loading card is up: draws the billboard FX materials, the petals, spark and tyre smoke
## nodes (their own _ready builds the exact materials and emitters), one neon material and the HUD fonts, so the first
## race frames do not compile them. Car paint is not covered: it needs a built car.
## Off-screen geometry is culled before it is drawn, so the 3D part renders in a private SubViewport with its own camera.

const FRAMES: int = 30  ## async shader compilation needs frames; loading takes far longer than this
const VIEW_PX: int = 16
const FONT_KINDS: PackedStringArray = ["body", "bold", "tracked", "digits"]
const HUD_PX: int = 20
const OFF_SCREEN_2D: Vector2 = Vector2(-5000.0, -5000.0)  ## the 2D labels are shaped at layout, not drawn on screen
const VIEW_DEPTH_M: float = 3.0  ## the camera looks down -Z from the origin

## Adds the warm-up nodes under host, waits FRAMES frames, then frees them. Call without awaiting while loading.
static func run(host: Node) -> void:
	if not is_instance_valid(host) or host.get_tree() == null:
		return
	var view := SubViewport.new()
	view.name = "PipelineWarmup3D"
	view.size = Vector2i(VIEW_PX, VIEW_PX)
	view.own_world_3d = true
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var cam := Camera3D.new()
	cam.current = true
	view.add_child(cam)
	var root := Node3D.new()
	root.position = Vector3(0.0, 0.0, -VIEW_DEPTH_M)
	view.add_child(root)
	_add_3d_nodes(root)
	host.add_child(view)
	var layer := CanvasLayer.new()
	layer.name = "PipelineWarmup2D"
	host.add_child(layer)
	for kind: String in FONT_KINDS:
		var label: Label = MSTheme.make_label("0123456789 ABCabc", kind, MSTheme.px(HUD_PX), MSTheme.CYAN, true)
		label.position = OFF_SCREEN_2D
		layer.add_child(label)
	var tree: SceneTree = host.get_tree()  ## kept: the host may be freed while we wait
	for i: int in FRAMES:
		await tree.process_frame
	if is_instance_valid(view):
		view.queue_free()
	if is_instance_valid(layer):
		layer.queue_free()


static func _add_3d_nodes(root: Node3D) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	for additive: bool in [false, true]:
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.material_override = FxUtil.billboard_material(additive, Color.WHITE)
		root.add_child(mi)
		root.add_child(FxUtil.emitter(4, 0.5, ParticleProcessMaterial.new(), FxUtil.billboard_material(additive, Color.WHITE), Vector2(0.2, 0.2)))
	var neon := MeshInstance3D.new()  # the same neon shader the city and garage use, through the library builder
	neon.mesh = quad
	neon.material_override = MaterialLibrary._neon("M_Neon_Warmup", {"emit": Color.WHITE, "colour": Color.WHITE, "emit_strength": 1.0})
	root.add_child(neon)
	for fx: Node3D in [Petals.new(), Sparks.new(), TireSmoke.new()]:
		root.add_child(fx)
