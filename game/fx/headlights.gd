class_name Headlights
extends Node3D
## Two forward SpotLight3D with a soft cone and short range. No shadows by default.

@export var energy: float = 40.0
@export var range_m: float = 22.0
@export var cone_deg: float = 32.0
@export var cast_shadows: bool = false
@export var lamp_points: PackedVector3Array = PackedVector3Array([Vector3(-0.55, 0.45, -2.1), Vector3(0.55, 0.45, -2.1)])

var _lights: Array[SpotLight3D] = []


func _ready() -> void:
	for p: Vector3 in lamp_points:
		var s := SpotLight3D.new()
		s.light_color = Color(1.0, 0.95, 0.82)
		s.light_energy = energy
		s.spot_range = range_m
		s.spot_angle = cone_deg
		s.spot_attenuation = 1.6
		s.shadow_enabled = cast_shadows
		s.position = p
		s.rotation_degrees = Vector3(-8.0, 0.0, 0.0)  # faces -Z, the car forward, tilted down onto the road
		add_child(s)
		_lights.append(s)
	set_on(false)


func set_on(on: bool) -> void:
	for s: SpotLight3D in _lights:
		s.visible = on
