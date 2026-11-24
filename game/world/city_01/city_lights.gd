class_name CityLights
extends RefCounted
## Light budget for the Mobile renderer: at most 8 omni and 8 spot lights may touch one mesh.
## Checked per volume: the AABB of each mesh that can be lit up close (road piece, building LOD0, prop MultiMesh).
## A light counts where its range sphere meets the volume. A volume over the limit keeps the PER_TYPE_LIMIT
## lights nearest its centre and drops the rest. A light dropped in any volume is dropped from the scene.
## Stateless helpers.

const PER_TYPE_LIMIT: int = 8


## lights: Array of Dictionary {type: "omni" | "spot", pos: Vector3, range: float}.
## volumes: Array of AABB; names: one label per volume for the log.
## Returns {keep: Array[bool], dropped: int, worst_all, worst_kept, over_volumes: int, log: PackedStringArray}.
## worst_* hold the largest count per type (keys omni, spot) and the volume index.
static func budget(lights: Array, volumes: Array, names: PackedStringArray) -> Dictionary:
	var keep: Array[bool] = []
	keep.resize(lights.size())
	keep.fill(true)
	var worst_all: Dictionary = {"omni": 0, "spot": 0, "volume": -1}
	var over: Array = []  # [volume, type, Array of light indices sorted nearest first]
	var log: PackedStringArray = PackedStringArray()
	for v: int in volumes.size():
		var box: AABB = volumes[v]
		var hits: Dictionary = {"omni": [], "spot": []}
		for i: int in lights.size():
			var l: Dictionary = lights[i]
			if sphere_hits_box(_pos(l), float(l["range"]), box):
				(hits[String(l["type"])] as Array).append(i)
		var centre: Vector3 = box.get_center()
		for t: String in ["omni", "spot"]:
			var idx: Array = hits[t]
			if idx.size() > int(worst_all[t]):
				worst_all[t] = idx.size()
				worst_all["volume"] = v
			if idx.size() > PER_TYPE_LIMIT:
				idx.sort_custom(func(a: int, b: int) -> bool: return _pos(lights[a]).distance_squared_to(centre) < _pos(lights[b]).distance_squared_to(centre))
				over.append([v, t, idx])
				log.append("%s: %s %d lights, keeping %d nearest" % [names[v], t, idx.size(), PER_TYPE_LIMIT])
	var dropped: int = 0
	for entry: Array in over:
		var idx: Array = entry[2]
		for k: int in range(PER_TYPE_LIMIT, idx.size()):
			var di: int = idx[k]
			if keep[di]:
				keep[di] = false
				dropped += 1
	var worst_kept: Dictionary = {"omni": 0, "spot": 0, "volume": -1}
	for v: int in volumes.size():
		var box2: AABB = volumes[v]
		var kept_hits: Dictionary = {"omni": 0, "spot": 0}
		for i: int in lights.size():
			var l2: Dictionary = lights[i]
			if keep[i] and sphere_hits_box(_pos(l2), float(l2["range"]), box2):
				kept_hits[String(l2["type"])] = int(kept_hits[String(l2["type"])]) + 1
		for t2: String in ["omni", "spot"]:
			if int(kept_hits[t2]) > int(worst_kept[t2]):
				worst_kept[t2] = kept_hits[t2]
				worst_kept["volume"] = v
	return {"keep": keep, "dropped": dropped, "worst_all": worst_all, "worst_kept": worst_kept,
		"over_volumes": over.size(), "log": log}


## Largest number of lights of each type whose range touches one volume (for the tests and reports).
static func worst_per_volume(lights: Array, volumes: Array) -> Dictionary:
	var worst: Dictionary = {"omni": 0, "spot": 0}
	for v: AABB in volumes:
		var n: Dictionary = {"omni": 0, "spot": 0}
		for l: Dictionary in lights:
			if sphere_hits_box(_pos(l), float(l["range"]), v):
				n[String(l["type"])] = int(n[String(l["type"])]) + 1
		for t: String in ["omni", "spot"]:
			worst[t] = maxi(int(worst[t]), int(n[t]))
	return worst


static func sphere_hits_box(c: Vector3, r: float, box: AABB) -> bool:
	var q: Vector3 = c.clamp(box.position, box.end)
	return q.distance_squared_to(c) <= r * r


static func _pos(l: Variant) -> Vector3:
	return (l as Dictionary)["pos"]
