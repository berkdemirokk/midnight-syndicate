extends SceneTree
## Launcher for hitch_probe_run.gd (see that file). Loaded as a -s script like drive_telemetry.gd.

func _initialize() -> void:
	await process_frame
	var runner: Node = load("res://devtools/scenarios/hitch_probe_run.gd").new() as Node
	root.add_child(runner)
