class_name PipelineWarmup
extends RefCounted
## First-use warm-up: draws the FX materials, particle emitters and HUD fonts once, off-screen, while the loading
## card is up, so the first race frames do not compile them. Car paint is not covered: it needs a built car.

const OFF_SCREEN: Vector3 = Vector3(0.0, -5000.0, 0.0)
const OFF_SCREEN_2D: Vector2 = Vector2(-5000.0, -5000.0)
const FRAMES: int = 3
const FONT_KINDS: PackedStringArray = ["body", "bold", "tracked", "digits"]
const HUD_PX: int = 20

## Adds the warm-up nodes under host, waits FRAMES frames, then frees them. Call without awaiting while loading.
static func run(host: Node) -> void:
	if not is_instance_valid(host) or host.get_tree() == null:
		return
	var root := Node3D.new()
	root.name = "PipelineWarmup3D"
	root.position = OFF_SCREEN
	host.add_child(root)
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	for additive: bool in [false, true]:
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.material_override = FxUtil.billboard_material(additive, Color.WHITE)
		root.add_child(mi)
		root.add_child(FxUtil.emitter(4, 0.5, ParticleProcessMaterial.new(), FxUtil.billboard_material(additive, Color.WHITE), Vector2(0.2, 0.2)))
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
	if is_instance_valid(root):
		root.queue_free()
	if is_instance_valid(layer):
		layer.queue_free()
