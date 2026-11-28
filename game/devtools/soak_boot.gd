extends Node
## Main scene of a soak run (see soak.gd). The soak script is loaded here, at run time: under `-s` the autoloads
## are not registered in time, so the race scripts it needs would not compile.


func _ready() -> void:
	var soak: Node = load("res://devtools/soak.gd").new()
	get_tree().root.add_child.call_deferred(soak)
