class_name FxUtil
extends RefCounted
## Shared builders for the FX scripts: particle emitters and materials, so each effect stays short.


static var _soft: GradientTexture2D = null


## Soft round sprite shared by all particle materials; soft = false for hard streaks (rain).
static func soft_sprite() -> GradientTexture2D:
	if _soft == null:
		var g := Gradient.new()
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
		_soft = GradientTexture2D.new()
		_soft.gradient = g
		_soft.fill = GradientTexture2D.FILL_RADIAL
		_soft.fill_from = Vector2(0.5, 0.5)
		_soft.fill_to = Vector2(1.0, 0.5)
		_soft.width = 64
		_soft.height = 64
	return _soft


static func billboard_material(additive: bool, color: Color, soft: bool = true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	if soft:
		m.albedo_texture = soft_sprite()
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.albedo_color = color
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	return m


static func emitter(amount: int, lifetime: float, process: ParticleProcessMaterial, mat: Material, quad_size: Vector2) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.process_material = process
	var quad := QuadMesh.new()
	quad.size = quad_size
	quad.material = mat
	p.draw_pass_1 = quad
	p.emitting = false
	return p


## Colour ramp from one colour through another to transparent, for ParticleProcessMaterial.
static func ramp(stops: PackedColorArray) -> GradientTexture1D:
	var g := Gradient.new()
	g.colors = stops
	var offsets := PackedFloat32Array()
	for i: int in stops.size():
		offsets.append(float(i) / float(maxi(stops.size() - 1, 1)))
	g.offsets = offsets
	var t := GradientTexture1D.new()
	t.gradient = g
	return t
