extends Node
## Main scene of a capture run. Puts the harness under the root, where it outlives scene changes.
## The harness was the autoload "Capture" until 2026-11-27. The iOS export leaves devtools/ out, so every launch on a
## phone logged a failed autoload; nothing outside devtools/ needs it.


func _ready() -> void:
	var harness := CaptureHarness.new()
	harness.name = "Capture"
	get_tree().root.add_child.call_deferred(harness)
