class_name PoliceDriver
extends AIDriver
## AIDriver for a police car. It follows the track like a racer, but its lane is the player's lateral offset, so it
## closes on the player instead of racing its own line, and its speed gets a catch-up gain that grows with heat.
## PursuitMode sets heat and player_s every step. Boxing (heat 4+): box_side puts the car beside the player's lane and
## box_ahead_m holds it that far in front of the player; the speed is then pushed or held by box_throttle.

const CATCH_UP_PER_HEAT: float = 0.02  ## speed gain per heat level: heat 5 drives about 10 % over the track target
const BOX_SIDE_OFFSET_M: float = 2.5  ## a boxing car sits this far left (-1) or right (+1) of the player's lane
const BOX_TOLERANCE_M: float = 3.0  ## the gap to the box point may be this far off before the speed is pushed or held

var player: ArcadeCar = null
var heat: int = 1
var player_s: float = -1.0  ## track progress of the player, search hint for the lateral lookup
var box_side: int = 0  ## 0 = chase, -1 = box on the left, +1 = box on the right
var box_ahead_m: float = 12.0  ## m in front of the player a boxing car tries to hold


func _drive(pos: Vector3, s: float, v: float, lane: float) -> void:
	if player == null or _track == null:
		super._drive(pos, s, v, lane)
		return
	var target: float = _track.get_lateral_offset(player.global_position, player_s)
	if box_side != 0:
		target += float(box_side) * BOX_SIDE_OFFSET_M
	super._drive(pos, s, v, _clamp_lane(target))
	if box_side != 0:
		var push: float = box_throttle(box_gap_m(s, player_s, _track.length), box_ahead_m)
		if push > 0.0:
			_car.input.throttle = 1.0
			_car.input.brake = 0.0
		elif push < 0.0:
			_car.input.throttle = 0.0
			_car.input.brake = maxf(_car.input.brake, 0.5)


func get_rubber_band() -> float:
	return 1.0 + CATCH_UP_PER_HEAT * float(heat)


## Signed track gap in metres from the player to a police car, positive = the police car is ahead. Wraps half a lap.
static func box_gap_m(police_s: float, player_progress: float, lap_m: float) -> float:
	if lap_m <= 0.0:
		return 0.0
	return fposmod(police_s - player_progress + lap_m * 0.5, lap_m) - lap_m * 0.5


## Throttle override for a boxing car: 1 = push (it is behind its box point), -1 = hold back (it is past it),
## 0 = inside the tolerance, leave the driver's own speed alone.
static func box_throttle(gap_m: float, ahead_m: float) -> float:
	if gap_m < ahead_m - BOX_TOLERANCE_M:
		return 1.0
	if gap_m > ahead_m + BOX_TOLERANCE_M:
		return -1.0
	return 0.0
