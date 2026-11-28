class_name PursuitState
extends RefCounted
## Deterministic, opt-in pursuit rules. No scene, AI driver, reward or UI side effects.
## A future police controller supplies the distance to the nearest active police vehicle.
## Distances in metres, player speed in km/h, elapsed time in seconds.
## Two goals: escape (survive_s == 0: a full cooldown ends in ESCAPED) or survive (survive_s > 0: that much chase
## time without a bust ends in ESCAPED, shown as SURVIVED by the HUD). A bust always wins.

enum Phase { INACTIVE, CHASE, COOLDOWN, ESCAPED, BUSTED }

const MAX_HEAT: int = 5
const ESCAPE_DISTANCE_M: float = 90.0
const REACQUIRE_DISTANCE_M: float = 65.0
const BUST_DISTANCE_M: float = 8.0
const BUST_SPEED_KMH: float = 10.0
const BUST_TIME_S: float = 4.0
const ESCAPE_TIME_S: float = 8.0
const HEAT_INTERVAL_S: float = 25.0
const ROADBLOCK_HEAT: int = 3

var phase: Phase = Phase.INACTIVE
var heat: int = 0
var chase_s: float = 0.0  ## chase time since the last heat step (resets at each step and at max heat)
var total_s: float = 0.0  ## chase time in total, cooldown excluded: the survive goal reads this
var cooldown_s: float = 0.0
var bust_s: float = 0.0
var survive_s: float = 0.0  ## 0 = escape goal; > 0 = survive this many seconds of chase

func start(initial_heat: int = 1, survive_for_s: float = 0.0) -> void:
	reset()
	heat = clampi(initial_heat, 1, MAX_HEAT)
	survive_s = maxf(survive_for_s, 0.0)
	phase = Phase.CHASE

func reset() -> void:
	phase = Phase.INACTIVE
	heat = 0
	chase_s = 0.0
	total_s = 0.0
	cooldown_s = 0.0
	bust_s = 0.0
	survive_s = 0.0

## Negative or invalid distance is ignored, not treated as a nearby officer.
## INF means no active police is within sensing range.
func tick(delta: float, nearest_police_m: float, player_speed_kmh: float, cooldown_mult: float = 1.0) -> void:
	if phase != Phase.CHASE and phase != Phase.COOLDOWN:
		return
	if not is_finite(delta) or delta <= 0.0 or is_nan(nearest_police_m) or nearest_police_m < 0.0 or not is_finite(player_speed_kmh):
		return
	if phase == Phase.CHASE and nearest_police_m >= ESCAPE_DISTANCE_M:
		phase = Phase.COOLDOWN
		cooldown_s = 0.0
		bust_s = 0.0
	elif phase == Phase.COOLDOWN and nearest_police_m <= REACQUIRE_DISTANCE_M:
		phase = Phase.CHASE
		cooldown_s = 0.0
	if phase == Phase.COOLDOWN:
		cooldown_s += delta * maxf(cooldown_mult, 0.0)  ## a hiding spot fills the escape gauge faster
		if cooldown_s >= ESCAPE_TIME_S:
			phase = Phase.ESCAPED
		return
	chase_s += delta
	total_s += delta
	while chase_s >= HEAT_INTERVAL_S and heat < MAX_HEAT:
		chase_s -= HEAT_INTERVAL_S
		heat += 1
	if heat == MAX_HEAT:
		chase_s = 0.0
	if nearest_police_m <= BUST_DISTANCE_M and absf(player_speed_kmh) <= BUST_SPEED_KMH:
		bust_s += delta
		if bust_s >= BUST_TIME_S:
			phase = Phase.BUSTED
	else:
		bust_s = 0.0
	if phase == Phase.CHASE and survive_s > 0.0 and total_s >= survive_s:
		phase = Phase.ESCAPED

## This is eligibility only. No roadblock is spawned by the rule model.
func can_request_roadblock() -> bool:
	return phase == Phase.CHASE and heat >= ROADBLOCK_HEAT
