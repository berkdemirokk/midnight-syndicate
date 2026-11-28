class_name NetTrack
extends RefCounted
## The track of an online race. The server and every client load the same allow-listed track scene (its racing
## line and start grid decide progress and grid slots), so all of them race on the same road. Anything else, or a
## scene that fails to load, gives null and the caller falls back to the development circuit (DevTrack).


## The Track node for an allow-listed scene path, not yet in a tree. Null when the path is not allow-listed or the
## scene does not load.
static func instance(path: String) -> Track:
	if path == "" or not NetConfig.TRACK_ALLOW.has(path) or not ResourceLoader.exists(path):
		return null
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		return null
	var inst: Node = packed.instantiate()
	var t: Track = inst as Track
	if t == null:
		inst.free()
	return t
