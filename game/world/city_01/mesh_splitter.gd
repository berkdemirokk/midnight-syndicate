class_name MeshSplitter
extends RefCounted
## Splits a MeshInstance3D whose AABB is touched by more than CityLights.PER_TYPE_LIMIT omni or spot lights into
## smaller MeshInstance3D pieces (children of the source node), so the Mobile renderer's 8-lights-per-mesh limit holds
## per piece instead of dropping lights. Triangles go to a cell by centroid; a cell is cut in half along its longest
## axis until each piece is under the limit (or cannot be cut: tiny, or one triangle). Materials, layers, shadows and
## visibility ranges are copied from the source; the source keeps its place (and any collision children) but loses its mesh.
## Stateless helpers.

const MIN_CELL_M: float = 2.0  ## a cell whose triangle centroids span less than this on every axis is not cut further
const MAX_DEPTH: int = 10


## Returns the number of pieces created (0 = left alone: under budget, not triangles, or nothing to cut).
static func split(mi: MeshInstance3D, lights: Array, min_excess: int = 0) -> int:
	var mesh: Mesh = mi.mesh
	if mesh == null or not _over(mi.global_transform * mesh.get_aabb(), lights, min_excess):
		return 0
	var ctx: Dictionary = _collect(mesh)
	if ctx.is_empty():
		return 0
	var all: PackedInt32Array = PackedInt32Array()
	for t: int in (ctx["cent"] as PackedVector3Array).size():
		all.append(t)
	var cells: Array = _cells(all, ctx, mi.global_transform, lights, 0)
	if cells.size() < 2:
		return 0
	var pieces: Array[MeshInstance3D] = []
	for c: int in cells.size():
		var piece: MeshInstance3D = _make_piece(mi, mesh, ctx, cells[c] as PackedInt32Array)
		piece.name = "%s_p%02d" % [String(mi.name), c]
		pieces.append(piece)
	mi.mesh = null
	for p: MeshInstance3D in pieces:
		mi.add_child(p)
	return pieces.size()


static func _over(box: AABB, lights: Array, excess: int = 0) -> bool:
	var n: Dictionary = {"omni": 0, "spot": 0}
	for l: Dictionary in lights:
		if CityLights.sphere_hits_box(l["pos"], float(l["range"]), box):
			var t: String = String(l["type"])
			n[t] = int(n[t]) + 1
	return int(n["omni"]) > CityLights.PER_TYPE_LIMIT + excess or int(n["spot"]) > CityLights.PER_TYPE_LIMIT + excess


## Per-triangle data over every TRIANGLES surface: surf, first index slot, centroid, local bounds.
static func _collect(mesh: Mesh) -> Dictionary:
	var surf: PackedInt32Array = PackedInt32Array()
	var slot: PackedInt32Array = PackedInt32Array()
	var cent: PackedVector3Array = PackedVector3Array()
	var tmin: PackedVector3Array = PackedVector3Array()
	var tmax: PackedVector3Array = PackedVector3Array()
	var arrays: Array = []
	var idx: Array = []
	for s: int in mesh.get_surface_count():
		var a: Array = mesh.surface_get_arrays(s)
		arrays.append(a)
		var pos: Variant = a[Mesh.ARRAY_VERTEX]
		if mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES or not pos is PackedVector3Array:
			return {}  # lines, strips, skinned data: leave the whole mesh alone
		var v: PackedVector3Array = pos
		var ix: PackedInt32Array
		if a[Mesh.ARRAY_INDEX] is PackedInt32Array:
			ix = a[Mesh.ARRAY_INDEX]
		else:
			ix = PackedInt32Array()
			for i: int in v.size():
				ix.append(i)
		idx.append(ix)
		for k: int in range(0, ix.size() - 2, 3):
			var p0: Vector3 = v[ix[k]]
			var p1: Vector3 = v[ix[k + 1]]
			var p2: Vector3 = v[ix[k + 2]]
			surf.append(s)
			slot.append(k)
			cent.append((p0 + p1 + p2) / 3.0)
			tmin.append(p0.min(p1).min(p2))
			tmax.append(p0.max(p1).max(p2))
	return {"surf": surf, "slot": slot, "cent": cent, "tmin": tmin, "tmax": tmax, "arrays": arrays, "idx": idx}


static func _cells(ids: PackedInt32Array, ctx: Dictionary, xf: Transform3D, lights: Array, depth: int) -> Array:
	var tmin: PackedVector3Array = ctx["tmin"]
	var tmax: PackedVector3Array = ctx["tmax"]
	var cent: PackedVector3Array = ctx["cent"]
	var lo: Vector3 = Vector3(INF, INF, INF)
	var hi: Vector3 = Vector3(-INF, -INF, -INF)
	var clo: Vector3 = lo
	var chi: Vector3 = hi
	for t: int in ids:
		lo = lo.min(tmin[t])
		hi = hi.max(tmax[t])
		clo = clo.min(cent[t])
		chi = chi.max(cent[t])
	if ids.size() < 2 or depth >= MAX_DEPTH or not _over(xf * AABB(lo, hi - lo), lights):
		return [ids]
	var ext: Vector3 = chi - clo
	var axis: int = ext.max_axis_index()
	if ext[axis] < MIN_CELL_M:
		return [ids]
	var mid: float = (clo[axis] + chi[axis]) * 0.5
	var a: PackedInt32Array = PackedInt32Array()
	var b: PackedInt32Array = PackedInt32Array()
	for t: int in ids:
		if cent[t][axis] < mid:
			a.append(t)
		else:
			b.append(t)
	if a.is_empty() or b.is_empty():
		return [ids]
	var out: Array = _cells(a, ctx, xf, lights, depth + 1)
	out.append_array(_cells(b, ctx, xf, lights, depth + 1))
	return out


static func _make_piece(src: MeshInstance3D, mesh: Mesh, ctx: Dictionary, ids: PackedInt32Array) -> MeshInstance3D:
	var surf: PackedInt32Array = ctx["surf"]
	var slot: PackedInt32Array = ctx["slot"]
	var per_surface: Dictionary = {}  # surface -> PackedInt32Array of index slots
	for t: int in ids:
		var s: int = surf[t]
		var lst: PackedInt32Array = per_surface.get(s, PackedInt32Array())
		lst.append(slot[t])
		per_surface[s] = lst  # packed arrays are values: write back
	var am := ArrayMesh.new()
	var piece := MeshInstance3D.new()
	var keys: Array = per_surface.keys()
	keys.sort()
	for s: int in keys:
		var j: int = am.get_surface_count()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _surface_arrays(ctx["arrays"][s], ctx["idx"][s], per_surface[s]))
		am.surface_set_material(j, src.get_active_material(s))  # override if the source has one, else the mesh's
		am.surface_set_name(j, mesh.surface_get_name(s))
	piece.mesh = am
	piece.layers = src.layers
	piece.cast_shadow = src.cast_shadow
	piece.gi_mode = src.gi_mode
	piece.visibility_range_begin = src.visibility_range_begin
	piece.visibility_range_end = src.visibility_range_end
	piece.visibility_range_begin_margin = src.visibility_range_begin_margin
	piece.visibility_range_end_margin = src.visibility_range_end_margin
	piece.visibility_range_fade_mode = src.visibility_range_fade_mode
	piece.lod_bias = src.lod_bias
	piece.extra_cull_margin = src.extra_cull_margin
	piece.ignore_occlusion_culling = src.ignore_occlusion_culling
	piece.visible = src.visible
	return piece


## Surface arrays of the triangles at the given index slots, vertices renumbered.
static func _surface_arrays(a: Array, ix: PackedInt32Array, slots: PackedInt32Array) -> Array:
	var vcount: int = (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var remap: PackedInt32Array = PackedInt32Array()
	remap.resize(vcount)
	remap.fill(-1)
	var used: PackedInt32Array = PackedInt32Array()
	var new_ix: PackedInt32Array = PackedInt32Array()
	for k: int in slots:
		for o: int in 3:
			var v: int = ix[k + o]
			if remap[v] < 0:
				remap[v] = used.size()
				used.append(v)
			new_ix.append(remap[v])
	var out: Array = []
	out.resize(Mesh.ARRAY_MAX)
	for ch: int in Mesh.ARRAY_MAX:
		if ch == Mesh.ARRAY_INDEX:
			out[ch] = new_ix
		elif a[ch] != null and (a[ch] as Variant).size() > 0:
			out[ch] = _gather(a[ch], used, vcount)
	return out


static func _gather(src: Variant, used: PackedInt32Array, vcount: int) -> Variant:
	var n: int = used.size()
	match typeof(src):
		TYPE_PACKED_VECTOR3_ARRAY:
			var s3: PackedVector3Array = src
			var r3: PackedVector3Array = PackedVector3Array()
			r3.resize(n)
			for i: int in n:
				r3[i] = s3[used[i]]
			return r3
		TYPE_PACKED_VECTOR2_ARRAY:
			var s2: PackedVector2Array = src
			var r2: PackedVector2Array = PackedVector2Array()
			r2.resize(n)
			for i: int in n:
				r2[i] = s2[used[i]]
			return r2
		TYPE_PACKED_COLOR_ARRAY:
			var sc: PackedColorArray = src
			var rc: PackedColorArray = PackedColorArray()
			rc.resize(n)
			for i: int in n:
				rc[i] = sc[used[i]]
			return rc
		TYPE_PACKED_FLOAT32_ARRAY:
			var sf: PackedFloat32Array = src
			var stride: int = sf.size() / vcount
			var rf: PackedFloat32Array = PackedFloat32Array()
			rf.resize(n * stride)
			for i: int in n:
				for k: int in stride:
					rf[i * stride + k] = sf[used[i] * stride + k]
			return rf
		TYPE_PACKED_INT32_ARRAY:
			var si: PackedInt32Array = src
			var stri: int = si.size() / vcount
			var ri: PackedInt32Array = PackedInt32Array()
			ri.resize(n * stri)
			for i: int in n:
				for k: int in stri:
					ri[i * stri + k] = si[used[i] * stri + k]
			return ri
	return null
