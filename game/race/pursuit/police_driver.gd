class_name PoliceDriver
extends AIDriver
## AIDriver for a police car. It follows the track like a racer, but its lane is the player's lateral offset, so it
## closes on the player instead of racing its own line, and its speed gets a catch-up gain that grows with heat.
## PursuitMode sets heat and player_s every step.

const CATCH_UP_PER_HEAT: float = 0.02  ## speed gain per heat level: heat 5 drives about 10 % over the track target

var player: ArcadeCar = null
var heat: int = 1
var player_s: float = -1.0  ## track progress of the player, search hint for the lateral lookup


func _drive(pos: Vector3, s: float, v: float, lane: float) -> void:
	if player == null or _track == null:
		super._drive(pos, s, v, lane)
		return
	var target: float = _track.get_lateral_offset(player.global_position, player_s)
	super._drive(pos, s, v, _clamp_lane(target))


func get_rubber_band() -> float:
	return 1.0 + CATCH_UP_PER_HEAT * float(heat)
