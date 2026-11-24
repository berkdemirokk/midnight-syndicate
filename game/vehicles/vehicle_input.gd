class_name VehicleInput
extends RefCounted
## The only thing a driver (player, AI, police) writes and the only thing ArcadeCar reads.

var throttle: float = 0.0  ## 0..1
var brake: float = 0.0  ## 0..1, also reverse when nearly stopped
var steer: float = 0.0  ## -1 left .. +1 right
var handbrake: bool = false
var nitro: bool = false


func clear() -> void:
	throttle = 0.0
	brake = 0.0
	steer = 0.0
	handbrake = false
	nitro = false
