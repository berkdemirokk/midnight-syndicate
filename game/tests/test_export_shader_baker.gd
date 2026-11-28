extends "res://tests/test_case.gd"
## Export preset (WP-B6): the Shader Baker is on in the iOS preset and in no other preset. Reads the preset file as
## text. The key is confirmed as a string in the Godot 4.7.2 binary; the first-launch effect is not measured here.

const PRESET_PATH: String = "res://export_presets.cfg"
const KEY_ON: String = "shader_baker/enabled=true"


## Maps each section header to its non-empty lines.
func _sections() -> Dictionary:
	var out: Dictionary = {}
	var f := FileAccess.open(PRESET_PATH, FileAccess.READ)
	if f == null:
		return out
	var cur: String = ""
	while not f.eof_reached():
		var line: String = f.get_line().strip_edges()
		if line.begins_with("["):
			cur = line
			out[cur] = []
		elif cur != "" and line != "":
			out[cur].append(line)
	f.close()
	return out


func test_shader_baker_on_for_ios_only() -> void:
	var secs := _sections()
	check(secs.size() > 0, "export_presets.cfg is not readable")
	var ios_options: String = ""
	for k: String in secs.keys():
		if k.begins_with("[preset.") and not k.ends_with(".options]") and (secs[k] as Array).has("name=\"iOS\""):
			ios_options = k.trim_suffix("]") + ".options]"
	check(ios_options != "", "no iOS preset found")
	check((secs.get(ios_options, []) as Array).has(KEY_ON), "iOS preset does not enable the Shader Baker")
	for k: String in secs.keys():
		if k.ends_with(".options]") and k != ios_options:
			check(not (secs[k] as Array).has(KEY_ON), "Shader Baker enabled outside the iOS preset: " + k)
