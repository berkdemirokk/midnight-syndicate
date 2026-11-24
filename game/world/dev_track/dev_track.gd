class_name DevTrack
extends RefCounted
## Development circuit built in code. Used only when the track scene is missing. Not final art:
## a dark road strip, kerbs, a ground plane, light posts and unlit blocks as orientation marks.
## The node tree follows the Track contract: RacingLine (closed Path3D, forward = race direction)
## and StartGrid (Marker3D Grid0..Grid7, -Z = race direction). Length is scaled to TARGET_LENGTH_M.

const TARGET_LENGTH_M: float = 1300.0
const POINT_COUNT: int = 24
const RADIUS_M: float = 200.0
const WOBBLE_M: float = 45.0
const ASPECT: float = 0.62  ## z squash, the loop is an irregular oval
const ROAD_WIDTH_M: float = 14.0  ## same as the Track default width
const KERB_WIDTH_M: float = 0.9
const KERB_STRIPE_SAMPLES: int = 2  ## samples per red or white kerb stripe
const ROAD_Y: float = 0.02
const SAMPLE_M: float = 4.0
const GRID_Y: float = 0.47
const GRID_FIRST_M: float = 8.0
const GRID_ROW_M: float = 9.0
const GRID_COLUMN_M: float = 3.5
const GRID_COUNT: int = 8
const POST_EVERY: int = 32  ## samples between light posts
const POST_OFFSET_M: float = 3.0
const POST_HEIGHT_M: float = 8.0
const LAMP_RANGE_M: float = 30.0
const LAMP_ENERGY: float = 1.5
const BLOCK_EVERY: int = 12  ## samples between blocks
const BLOCK_NEAR_M: float = 35.0
const BLOCK_FAR_M: float = 90.0
const BLOCK_CLEAR_M: float = 6.0  ## gap between a block's near face and the kerb
const BLOCK_HALF_MIN_M: float = 14.0
const BLOCK_HALF_MAX_M: float = 30.0
const BLOCK_HEIGHT_MIN_M: float = 10.0
const BLOCK_HEIGHT_MAX_M: float = 36.0
const GROUND_SIZE_M: float = 6000.0
const GROUND_THICK_M: float = 2.0
const SEED: int = 7
const ROAD_COLOUR: Color = Color(0.12, 0.13, 0.15)
const KERB_RED: Color = Color(0.72, 0.08, 0.12)
const KERB_WHITE: Color = Color(0.86, 0.87, 0.9)
const GROUND_COLOUR: Color = Color(0.06, 0.08, 0.07)
const BLOCK_COLOUR: Color = Color(0.1, 0.11, 0.14)
const POST_COLOUR: Color = Color(0.22, 0.24, 0.27)
const LAMP_COLOUR: Color = Color(1.0, 0.8, 0.45)


static func build() -> Track:
	var track := Track.new()
	track.name = "DevTrack"
	var unit: Curve3D = _make_curve(1.0)
	var curve: Curve3D = _make_curve(TARGET_LENGTH_M / unit.get_baked_length())
	var frames: Array[Transform3D] = _frames(curve)
	track.add_child(_ground())
	var path := Path3D.new()
	path.name = "RacingLine"
	path.curve = curve
	track.add_child(path)
	track.add_child(_road(frames))
	track.add_child(_kerbs(frames))
	track.add_child(_posts(frames))
	track.add_child(_blocks(frames))
	track.add_child(_start_grid(frames))
	return track


## Closed Catmull-Rom loop through points on a wobbly oval, heading -Z at the start (point 0). Last point repeats the first.
static func _make_curve(scale: float) -> Curve3D:
	var pts: Array[Vector3] = []
	for k: int in POINT_COUNT:
		var th: float = -TAU * float(k) / float(POINT_COUNT)
		var r: float = RADIUS_M + WOBBLE_M * sin(3.0 * th)
		pts.append(Vector3(r * cos(th), 0.0, r * sin(th) * ASPECT) * scale)
	var curve := Curve3D.new()
	for k: int in POINT_COUNT + 1:
		var c: int = k % POINT_COUNT
		var prev: Vector3 = pts[(c - 1 + POINT_COUNT) % POINT_COUNT]
		var nxt: Vector3 = pts[(c + 1) % POINT_COUNT]
		var handle: Vector3 = (nxt - prev) / 6.0
		curve.add_point(pts[c], -handle, handle)
	return curve


## Samples along the line. Each frame: origin on the line, basis.x = right of the race direction, -basis.z = forward.
static func _frames(curve: Curve3D) -> Array[Transform3D]:
	var length: float = curve.get_baked_length()
	var n: int = maxi(3, roundi(length / SAMPLE_M))
	var out: Array[Transform3D] = []
	for i: int in n:
		var off: float = float(i) * length / float(n)
		var p: Vector3 = curve.sample_baked(off, true)
		var a: Vector3 = curve.sample_baked(fposmod(off - 0.5, length), true)
		var b: Vector3 = curve.sample_baked(fposmod(off + 0.5, length), true)
		var t: Vector3 = b - a
		t.y = 0.0
		t = t.normalized()
		out.append(Transform3D(Basis.looking_at(t, Vector3.UP), p))
	return out


static func _road(frames: Array[Transform3D]) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half: float = ROAD_WIDTH_M * 0.5
	var n: int = frames.size()
	for i: int in n:
		_quad(st, frames[i], frames[(i + 1) % n], -half, half, ROAD_Y)
	st.generate_normals()
	return _mesh_node("Road", st.commit(), _mat(ROAD_COLOUR, 0.92))


static func _kerbs(frames: Array[Transform3D]) -> Node3D:
	var red := SurfaceTool.new()
	var white := SurfaceTool.new()
	red.begin(Mesh.PRIMITIVE_TRIANGLES)
	white.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half: float = ROAD_WIDTH_M * 0.5
	var n: int = frames.size()
	for i: int in n:
		var st: SurfaceTool = red if (i / KERB_STRIPE_SAMPLES) % 2 == 0 else white
		var fa: Transform3D = frames[i]
		var fb: Transform3D = frames[(i + 1) % n]
		_quad(st, fa, fb, -half - KERB_WIDTH_M, -half, ROAD_Y + 0.01)
		_quad(st, fa, fb, half, half + KERB_WIDTH_M, ROAD_Y + 0.01)
	red.generate_normals()
	white.generate_normals()
	var root := Node3D.new()
	root.name = "Kerbs"
	root.add_child(_mesh_node("KerbRed", red.commit(), _mat(KERB_RED, 0.7)))
	root.add_child(_mesh_node("KerbWhite", white.commit(), _mat(KERB_WHITE, 0.7)))
	return root


static func _ground() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = Vector3(GROUND_SIZE_M, GROUND_THICK_M, GROUND_SIZE_M)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0.0, -GROUND_THICK_M * 0.5, 0.0)
	body.add_child(cs)
	var plane := PlaneMesh.new()
	plane.size = Vector2(GROUND_SIZE_M, GROUND_SIZE_M)
	body.add_child(_mesh_node("GroundMesh", plane, _mat(GROUND_COLOUR, 0.95)))
	return body


static func _posts(frames: Array[Transform3D]) -> Node3D:
	var root := Node3D.new()
	root.name = "LightPosts"
	var pole := CylinderMesh.new()
	pole.top_radius = 0.12
	pole.bottom_radius = 0.18
	pole.height = POST_HEIGHT_M
	var pole_mat: StandardMaterial3D = _mat(POST_COLOUR, 0.6)
	var k: int = 0
	for i: int in range(0, frames.size(), POST_EVERY):
		var f: Transform3D = frames[i]
		var at: Vector3 = f.origin + f.basis.x * (ROAD_WIDTH_M * 0.5 + POST_OFFSET_M)
		var post := Node3D.new()
		post.name = "LightPost%d" % k
		post.position = at
		var mi := MeshInstance3D.new()
		mi.mesh = pole
		mi.position = Vector3(0.0, POST_HEIGHT_M * 0.5, 0.0)
		mi.material_override = pole_mat
		post.add_child(mi)
		var lamp := OmniLight3D.new()
		lamp.name = "Lamp"
		lamp.position = Vector3(0.0, POST_HEIGHT_M, 0.0)
		lamp.light_color = LAMP_COLOUR
		lamp.light_energy = LAMP_ENERGY
		lamp.omni_range = LAMP_RANGE_M
		lamp.shadow_enabled = false
		post.add_child(lamp)
		root.add_child(post)
		k += 1
	return root


## Unlit dark blocks beside the road. No collision: they only give the eye a sense of speed and place.
static func _blocks(frames: Array[Transform3D]) -> Node3D:
	var root := Node3D.new()
	root.name = "Blocks"
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var mat := _mat(BLOCK_COLOUR, 1.0)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var k: int = 0
	for i: int in range(0, frames.size(), BLOCK_EVERY):
		var f: Transform3D = frames[i]
		var side: float = 1.0 if k % 2 == 0 else -1.0
		var dist: float = rng.randf_range(BLOCK_NEAR_M, BLOCK_FAR_M)
		var half: float = rng.randf_range(BLOCK_HALF_MIN_M, BLOCK_HALF_MAX_M)
		var height: float = rng.randf_range(BLOCK_HEIGHT_MIN_M, BLOCK_HEIGHT_MAX_M)
		# Near face (dist - half) clears the road edge, kerb and BLOCK_CLEAR_M.
		dist = maxf(dist, ROAD_WIDTH_M * 0.5 + KERB_WIDTH_M + BLOCK_CLEAR_M + half)
		var box := BoxMesh.new()
		box.size = Vector3(half * 2.0, height, half * 1.6)
		var mi := MeshInstance3D.new()
		mi.name = "Block%d" % k
		mi.mesh = box
		mi.material_override = mat
		mi.transform = Transform3D(f.basis, f.origin + f.basis.x * side * dist + Vector3(0.0, height * 0.5, 0.0))
		root.add_child(mi)
		k += 1
	return root


static func _start_grid(frames: Array[Transform3D]) -> Node3D:
	var root := Node3D.new()
	root.name = "StartGrid"
	var f0: Transform3D = frames[0]
	var fwd: Vector3 = -f0.basis.z
	var right: Vector3 = f0.basis.x
	for i: int in GRID_COUNT:
		var row: int = i / 2
		var col: float = -GRID_COLUMN_M if i % 2 == 0 else GRID_COLUMN_M
		var pos: Vector3 = f0.origin - fwd * (GRID_FIRST_M + GRID_ROW_M * float(row)) + right * col
		pos.y = GRID_Y
		var m := Marker3D.new()
		m.name = "Grid%d" % i
		m.transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), pos)
		root.add_child(m)
	return root


## One quad between two samples, from lateral offset lo to hi (metres right of the line), at height y.
static func _quad(st: SurfaceTool, fa: Transform3D, fb: Transform3D, lo: float, hi: float, y: float) -> void:
	var up: Vector3 = Vector3(0.0, y, 0.0)
	var a_lo: Vector3 = fa.origin + fa.basis.x * lo + up
	var a_hi: Vector3 = fa.origin + fa.basis.x * hi + up
	var b_lo: Vector3 = fb.origin + fb.basis.x * lo + up
	var b_hi: Vector3 = fb.origin + fb.basis.x * hi + up
	st.add_vertex(a_lo)
	st.add_vertex(a_hi)
	st.add_vertex(b_lo)
	st.add_vertex(a_hi)
	st.add_vertex(b_hi)
	st.add_vertex(b_lo)


static func _mesh_node(node_name: String, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	return mi


static func _mat(colour: Color, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = roughness
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat
