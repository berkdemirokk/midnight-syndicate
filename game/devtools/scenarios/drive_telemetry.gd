extends SceneTree
## Launcher for drive_telemetry_run.gd. The runner is loaded after the first frame, when the autoloads exist
## (a -s script is compiled before them, so it cannot reference GameState or Settings directly).
## Usage and flags: see drive_telemetry_run.gd.


func _initialize() -> void:
	await process_frame
	var runner: Node = load("res://devtools/scenarios/drive_telemetry_run.gd").new() as Node
	root.add_child(runner)
