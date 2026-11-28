class_name Storefront
extends RefCounted
## A 3D ground-floor shop front for one building of a photo row (PhotoFronts). It replaces the shop band of the facade
## picture, which read as a flat, blurred, glowing poster at the chase camera: stone pilasters at both ends, a cornice,
## a protruding sign fascia that keeps the picture's own sign strip, a window opening recessed into the wall with stone
## reveals, a stall riser and sill, a glazed door, metal frames and mullions, and recessed glass with a room behind it
## (storefront_glass.gdshader shows the picture's shop interior as the back wall of that room).
## Built in house space as PhotoFronts._house_mesh: street face at z = 0 facing -Z, the body toward +Z, +X on the
## viewer's left. All sizes are metres after the slot scale; xf places the house in the row.

const PILASTER_W: float = 0.34
const PILASTER_OUT: float = 0.08
const CORNICE_H: float = 0.16
const CORNICE_OUT: float = 0.2
const FASCIA_OUT: float = 0.07
const RECESS: float = 0.3  ## glass this far behind the wall face
const RISER_H: float = 0.5
const BAR: float = 0.06  ## frame and mullion width
const MULLION_MAX_GAP: float = 1.7
const STONE_UV_M: float = 1.6
const METALS: Array[Color] = [Color(0.035, 0.032, 0.03), Color(0.06, 0.045, 0.03), Color(0.025, 0.06, 0.045), Color(0.1, 0.028, 0.026), Color(0.11, 0.11, 0.115)]


## Adds one shop front. trim: stone and metal surface; glass: the glass surface of this picture; face: the picture surface
## (the fascia front carries the picture's sign strip). u0/u1: the house columns in the picture, frac: the shop band
## height as a share of the picture height, h: the house height in metres (picture height after the slot scale).
static func build(trim: SurfaceTool, glass: SurfaceTool, face: SurfaceTool, xf: Transform3D, w: float, h: float,
		u0: float, u1: float, frac: float, rng: RandomNumberGenerator, stone: Color) -> void:
	var sh: float = frac * h
	var hw: float = w / 2.0
	var fh: float = clampf(sh * 0.22, 0.45, 1.1)
	var top_open: float = sh - CORNICE_H - fh  # top of the window opening
	var ox: float = hw - PILASTER_W  # opening half width
	var metal: Color = METALS[rng.randi() % METALS.size()]
	var st_c := Color(stone, 1.0)
	var mt_c := Color(metal, 0.0)
	# pilasters: front and the two outer faces (the inner faces are the reveals below)
	for s: float in [1.0, -1.0]:
		var xa: float = s * hw
		var xb: float = s * ox
		_box(trim, xf, Vector3(minf(xa, xb), 0.0, -PILASTER_OUT), Vector3(maxf(xa, xb), sh - CORNICE_H, 0.0), st_c, [true, true, true, false, false, false])
	# cornice: a ledge along the whole house
	_box(trim, xf, Vector3(-hw - 0.05, sh - CORNICE_H, -CORNICE_OUT), Vector3(hw + 0.05, sh, 0.0), st_c, [true, true, true, true, true, false])
	# fascia: the sign board; its front is the picture's sign strip
	var vf_top: float = 1.0 - frac
	var vf_bot: float = 1.0 - frac + frac * ((CORNICE_H + fh) / sh)
	_box(trim, xf, Vector3(-ox, top_open, -FASCIA_OUT), Vector3(ox, top_open + fh, 0.0), mt_c, [false, true, true, true, false, false])
	var fu0: float = lerpf(u0, u1, (hw - ox) / w)
	var fu1: float = lerpf(u0, u1, (hw + ox) / w)
	_quad(face, xf, [Vector3(ox, top_open + fh, -FASCIA_OUT), Vector3(-ox, top_open + fh, -FASCIA_OUT), Vector3(-ox, top_open, -FASCIA_OUT), Vector3(ox, top_open, -FASCIA_OUT)],
			[Vector2(fu0, vf_top + frac * (CORNICE_H / sh)), Vector2(fu1, vf_top + frac * (CORNICE_H / sh)), Vector2(fu1, vf_bot), Vector2(fu0, vf_bot)],
			Vector3(0.0, 0.0, -1.0), Color.WHITE)
	# reveals: the opening's inner faces from the wall face back to the glass, stone
	_quad(trim, xf, [Vector3(ox, top_open, 0.0), Vector3(ox, top_open, RECESS), Vector3(ox, 0.0, RECESS), Vector3(ox, 0.0, 0.0)], _suv_z([Vector3(ox, top_open, 0.0), Vector3(ox, top_open, RECESS), Vector3(ox, 0.0, RECESS), Vector3(ox, 0.0, 0.0)]), Vector3(-1.0, 0.0, 0.0), st_c)
	_quad(trim, xf, [Vector3(-ox, top_open, RECESS), Vector3(-ox, top_open, 0.0), Vector3(-ox, 0.0, 0.0), Vector3(-ox, 0.0, RECESS)], _suv_z([Vector3(-ox, top_open, RECESS), Vector3(-ox, top_open, 0.0), Vector3(-ox, 0.0, 0.0), Vector3(-ox, 0.0, RECESS)]), Vector3(1.0, 0.0, 0.0), st_c)
	var soffit: Array = [Vector3(ox, top_open, 0.0), Vector3(-ox, top_open, 0.0), Vector3(-ox, top_open, RECESS), Vector3(ox, top_open, RECESS)]
	_quad(trim, xf, soffit, _suv_y(soffit), Vector3(0.0, -1.0, 0.0), Color(stone * 0.7, 1.0))
	# door on one side, the rest is the display window over a stall riser
	var open_w: float = 2.0 * ox
	var dw: float = clampf(open_w * 0.3, 0.9, 1.2)
	var has_door: bool = open_w > 2.2
	var door_left: bool = rng.randf() < 0.5
	var dx0: float = (ox - dw) if door_left else -ox  # door x range (house space, +X = viewer left)
	var dx1: float = ox if door_left else (-ox + dw)
	var wx0: float = -ox  # display window x range
	var wx1: float = ox
	if has_door:
		if door_left:
			wx1 = dx0
		else:
			wx0 = dx1
	# stall riser and sill under the window
	_box(trim, xf, Vector3(wx0, 0.0, RECESS - 0.12), Vector3(wx1, RISER_H, RECESS), st_c, [true, true, false, false, false, false])
	# glass: one window frame for the whole opening, so the room behind spans door and window
	var gsize := Vector2(open_w, top_open)
	var col := Color(u0, u1, 1.0 - frac + frac * ((CORNICE_H + fh) / sh), 1.0 - frac * 0.03)
	_glass_quad(glass, xf, wx0, wx1, RISER_H, top_open, ox, gsize, col)
	if has_door:
		_glass_quad(glass, xf, dx0, dx1, 0.0, top_open, ox, gsize, col)
	# frames: around the opening, the door, a transom and mullions, in front of the glass
	var zf: float = RECESS - 0.03
	_bar_h(trim, xf, -ox, ox, top_open - BAR, top_open, zf, mt_c)
	_bar_h(trim, xf, wx0, wx1, RISER_H, RISER_H + BAR, zf, mt_c)
	_bar_v(trim, xf, ox - BAR, ox, 0.0, top_open, zf, mt_c)
	_bar_v(trim, xf, -ox, -ox + BAR, 0.0, top_open, zf, mt_c)
	var transom: float = minf(top_open - 0.45, 2.3)
	if transom > RISER_H + 1.0:
		_bar_h(trim, xf, -ox, ox, transom - BAR * 0.5, transom + BAR * 0.5, zf, mt_c)
	if has_door:
		var jamb: float = dx0 if door_left else dx1
		_bar_v(trim, xf, jamb - BAR, jamb + BAR, 0.0, top_open, zf - 0.01, mt_c)
		var mid: float = (dx0 + dx1) / 2.0  # double-door meeting stiles and a push bar
		_bar_v(trim, xf, mid - BAR * 0.5, mid + BAR * 0.5, 0.0, transom, zf - 0.01, mt_c)
		_bar_h(trim, xf, dx0 + BAR, dx1 - BAR, 1.0, 1.04, zf - 0.04, Color(0.55, 0.52, 0.45, 0.0))
	var span: float = wx1 - wx0
	var n: int = maxi(1, ceili(span / MULLION_MAX_GAP))
	for i: int in range(1, n):
		var mx: float = wx0 + span * float(i) / float(n)
		_bar_v(trim, xf, mx - BAR * 0.5, mx + BAR * 0.5, RISER_H, top_open, zf, mt_c)


static func _glass_quad(glass: SurfaceTool, xf: Transform3D, x0: float, x1: float, y0: float, y1: float, ox: float, size: Vector2, col: Color) -> void:
	var pts: Array = [Vector3(x1, y1, RECESS), Vector3(x0, y1, RECESS), Vector3(x0, y0, RECESS), Vector3(x1, y0, RECESS)]
	var nrm: Vector3 = xf.basis * Vector3(0.0, 0.0, -1.0)
	for i: int in [0, 1, 2, 0, 2, 3]:
		var p: Vector3 = pts[i]
		glass.set_normal(nrm)
		glass.set_color(col)
		glass.set_uv(Vector2((ox - p.x) / size.x, p.y / size.y))
		glass.set_uv2(size)
		glass.add_vertex(xf * p)


static func _bar_v(st: SurfaceTool, xf: Transform3D, x0: float, x1: float, y0: float, y1: float, z: float, c: Color) -> void:
	_box(st, xf, Vector3(x0, y0, z - 0.05), Vector3(x1, y1, z), c, [true, true, true, false, false, false])


static func _bar_h(st: SurfaceTool, xf: Transform3D, x0: float, x1: float, y0: float, y1: float, z: float, c: Color) -> void:
	_box(st, xf, Vector3(x0, y0, z - 0.05), Vector3(x1, y1, z), c, [true, false, false, true, true, false])


## An axis-aligned box in house space; faces = [front -Z, +X, -X, top, bottom, back +Z].
static func _box(st: SurfaceTool, xf: Transform3D, a: Vector3, b: Vector3, c: Color, faces: Array) -> void:
	if faces[0]:
		var f: Array = [Vector3(b.x, b.y, a.z), Vector3(a.x, b.y, a.z), Vector3(a.x, a.y, a.z), Vector3(b.x, a.y, a.z)]
		_quad(st, xf, f, _suv_xy(f), Vector3(0.0, 0.0, -1.0), c)
	if faces[1]:
		var r: Array = [Vector3(b.x, b.y, b.z), Vector3(b.x, b.y, a.z), Vector3(b.x, a.y, a.z), Vector3(b.x, a.y, b.z)]
		_quad(st, xf, r, _suv_z(r), Vector3(1.0, 0.0, 0.0), c)
	if faces[2]:
		var l: Array = [Vector3(a.x, b.y, a.z), Vector3(a.x, b.y, b.z), Vector3(a.x, a.y, b.z), Vector3(a.x, a.y, a.z)]
		_quad(st, xf, l, _suv_z(l), Vector3(-1.0, 0.0, 0.0), c)
	if faces[3]:
		var t: Array = [Vector3(b.x, b.y, b.z), Vector3(a.x, b.y, b.z), Vector3(a.x, b.y, a.z), Vector3(b.x, b.y, a.z)]
		_quad(st, xf, t, _suv_y(t), Vector3(0.0, 1.0, 0.0), c)
	if faces[4]:
		var u: Array = [Vector3(b.x, a.y, a.z), Vector3(a.x, a.y, a.z), Vector3(a.x, a.y, b.z), Vector3(b.x, a.y, b.z)]
		_quad(st, xf, u, _suv_y(u), Vector3(0.0, -1.0, 0.0), c)


static func _suv_xy(p: Array) -> Array:
	return p.map(func(v: Vector3) -> Vector2: return Vector2(-v.x, -v.y) / STONE_UV_M)


static func _suv_z(p: Array) -> Array:
	return p.map(func(v: Vector3) -> Vector2: return Vector2(v.z, -v.y) / STONE_UV_M)


static func _suv_y(p: Array) -> Array:
	return p.map(func(v: Vector3) -> Vector2: return Vector2(-v.x, v.z) / STONE_UV_M)


static func _quad(st: SurfaceTool, xf: Transform3D, p: Array, uv: Array, normal: Vector3, colour: Color) -> void:
	var n: Vector3 = (xf.basis * normal).normalized()
	for i: int in [0, 1, 2, 0, 2, 3]:
		st.set_normal(n)
		st.set_color(colour)
		st.set_uv(uv[i])
		st.add_vertex(xf * (p[i] as Vector3))
