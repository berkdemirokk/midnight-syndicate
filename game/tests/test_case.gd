extends RefCounted
## Base for every test file. Test files start with: extends "res://tests/test_case.gd"
## and define methods named test_*. Methods may be coroutines (use await frames(n)).

var tree: SceneTree
var failures: Array[String] = []
var metrics: Dictionary = {}


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)


func check_range(value: float, lo: float, hi: float, what: String) -> void:
	if is_nan(value) or value < lo or value > hi:
		failures.append("%s = %.3f, expected %.3f..%.3f" % [what, value, lo, hi])


## Recorded into evidence/test_results.json next to the pass/fail result.
func metric(key: String, value: Variant) -> void:
	metrics[key] = value


## Wait n physics ticks. Run Godot with --fixed-fps 60 so this is fast and deterministic.
func frames(n: int) -> void:
	for i: int in n:
		await tree.physics_frame


func add(node: Node) -> Node:
	tree.root.add_child(node)
	return node


## Free everything a test added. Call at the end of each test.
func cleanup(nodes: Array[Node]) -> void:
	for n: Node in nodes:
		if is_instance_valid(n):
			n.queue_free()
	await tree.physics_frame
