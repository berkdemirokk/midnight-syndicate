class_name CaptureScenario
extends RefCounted
## Base for capture scenarios in devtools/scenarios/. A scenario subclasses this by path:
##   extends "res://devtools/capture_scenario.gd"
## and overrides run(). Use cap.load_scene, cap.wait_frames, cap.wait_seconds, cap.shot, cap.measure, cap.set_size, cap.fail.

var cap: CaptureHarness
var tree: SceneTree


func run() -> void:
	cap.fail("scenario did not override run()")
