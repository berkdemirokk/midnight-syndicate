class_name CarAudio
extends Node3D
## Engine, tyre, nitro and impact audio for one ArcadeCar. Add as a child of the car (or call bind()).
## Reads car state only (rpm_norm, gear, input.throttle, wheel_slip, speed_kmh, nitro_active, hit).
## Player: 3 engine layers + squeal + wet hiss + nitro + scrape + turbo/blow-off/backfire/impacts.
## Opponent (is_player = false): 2 engine layers + squeal, positional with Doppler, quieter.

const SHIFT_TIME := 0.20  ## seconds of rpm dip + level dip after an upshift
const SHIFT_RPM_DIP := 0.16
const LAYER_DB := -2.0
const OPPONENT_DB := -10.0
const HEAVY_HIT_IMPULSE := 6000.0
const MIN_HIT_IMPULSE := 700.0

@export var is_player: bool = true
@export_range(0.0, 1.0) var wetness: float = 0.0  ## set by the weather system; scales tyre hiss on wet road
var scrape_level: float = 0.0  ## 0..1, set by whoever knows about wall contact

var car: ArcadeCar
var enabled: bool = true
var rpm_smooth: float = 0.0
var shift_timer: float = 0.0

var low: AudioStreamPlayer3D
var mid: AudioStreamPlayer3D
var high: AudioStreamPlayer3D
var squeal: AudioStreamPlayer3D
var hiss: AudioStreamPlayer3D
var nitro: AudioStreamPlayer3D
var scrape: AudioStreamPlayer3D

var _shots: Array[AudioStreamPlayer3D] = []
var _shot_next: int = 0
var _last_gear: int = 1
var _last_throttle: float = 0.0
var _nitro_prev: bool = false
var _nitro_gain: float = 0.0
var _squeal_gain: float = 0.0
var _shift_gain: float = 1.0
var _first: bool = true
var _cool_turbo: float = 0.0
var _cool_bov: float = 0.0
var _pops: Array[float] = []  ## pending backfire times (seconds from now)
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 7
	AudioLib.ensure_buses()
	_build()
	if car == null:
		car = get_parent() as ArcadeCar
	bind(car)


func bind(c: ArcadeCar) -> void:
	if car != null and car.hit.is_connected(_on_car_hit):
		car.hit.disconnect(_on_car_hit)
	car = c
	_first = true
	if car != null and is_player:
		car.hit.connect(_on_car_hit)


## Normalised crossfade weights (x low, y mid, z high) for an rpm 0..1; sum of squares = 1.
static func layer_gains(rpm: float) -> Vector3:
	var r: float = clampf(rpm, 0.0, 1.0)
	var wl: float = 1.0 - smoothstep(0.0, 0.5, r)
	var wh: float = smoothstep(0.4, 0.92, r)
	var wm: float = smoothstep(0.0, 0.3, r) * (1.0 - smoothstep(0.55, 0.95, r))
	var n: float = sqrt(wl * wl + wm * wm + wh * wh)
	if n < 0.0001:
		return Vector3(1, 0, 0)
	return Vector3(wl, wm, wh) / n


## Pitch multipliers for (low, mid, high) layers at an rpm.
static func layer_pitches(rpm: float) -> Vector3:
	var r: float = clampf(rpm, 0.0, 1.0)
	return Vector3(lerpf(0.72, 1.45, r), lerpf(0.62, 1.6, r), lerpf(0.72, 1.7, r))


func set_enabled(on: bool) -> void:
	enabled = on
	for p: AudioStreamPlayer3D in _all_players():
		p.stream_paused = not on


func _build() -> void:
	var near: bool = is_player
	low = _loop_player(&"engine_low_loop", LAYER_DB, near) if is_player else null
	mid = _loop_player(&"engine_mid_loop", LAYER_DB, near)
	high = _loop_player(&"engine_high_loop", LAYER_DB - 2.0, near)
	squeal = _loop_player(&"tyre_squeal_loop", -80.0, near)
	if is_player:
		hiss = _loop_player(&"tyre_hiss_wet_loop", -80.0, true)
		nitro = _loop_player(&"nitro_loop", -80.0, true)
		scrape = _loop_player(&"scrape_loop", -80.0, true)
		for i: int in 4:
			var p := _make_player(true)
			p.max_polyphony = 2
			_shots.append(p)
	for p: AudioStreamPlayer3D in [low, mid, high, squeal, hiss, nitro, scrape]:
		if p != null and p.stream != null and p.is_inside_tree():
			p.play()


func _all_players() -> Array[AudioStreamPlayer3D]:
	var out: Array[AudioStreamPlayer3D] = []
	for p: AudioStreamPlayer3D in [low, mid, high, squeal, hiss, nitro, scrape]:
		if p != null:
			out.append(p)
	out.append_array(_shots)
	return out


func _make_player(near: bool) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.bus = AudioLib.BUS_SFX
	p.max_polyphony = 1
	if near:
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	else:
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.unit_size = 9.0
		p.max_distance = 130.0
		p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
	add_child(p)
	return p


func _loop_player(id: StringName, db: float, near: bool) -> AudioStreamPlayer3D:
	var p := _make_player(near)
	p.stream = AudioLib.get_stream(id)
	p.volume_db = db
	return p


func _db(g: float) -> float:
	return linear_to_db(maxf(g, 0.00003))


func _process(delta: float) -> void:
	update_audio(delta)


## Called every frame; public so tests can step it with their own deltas.
func update_audio(delta: float) -> void:
	if car == null or not enabled:
		return
	var thr: float = car.input.throttle if car.input != null else 0.0
	var gear_now: int = car.gear
	if gear_now > _last_gear:
		shift_timer = SHIFT_TIME
		if is_player and thr > 0.7 and car.rpm_norm > 0.55 and _rng.randf() < 0.35:
			_pops.append(_rng.randf_range(0.04, 0.12))
	_last_gear = gear_now
	shift_timer = maxf(0.0, shift_timer - delta)

	var rpm_t: float = car.rpm_norm
	if shift_timer > 0.0:
		rpm_t = maxf(0.0, rpm_t - SHIFT_RPM_DIP)
	if _first:
		rpm_smooth = rpm_t
		_last_throttle = thr
		_nitro_prev = car.nitro_active
		_first = false
	rpm_smooth = lerpf(rpm_smooth, rpm_t, 1.0 - exp(-14.0 * delta))
	_shift_gain = move_toward(_shift_gain, 0.55 if shift_timer > 0.0 else 1.0, 7.0 * delta)

	_update_engine(thr)
	_update_tyres(delta)
	if is_player:
		_update_nitro(delta)
		_update_turbo(thr, delta)
		_update_hiss()
		var sc: float = clampf(scrape_level, 0.0, 1.0)
		_set_loop(scrape, _db(sc * 0.8) if sc > 0.01 else -80.0)
	_last_throttle = thr


func _update_engine(thr: float) -> void:
	var g: Vector3 = layer_gains(rpm_smooth)
	var pit: Vector3 = layer_pitches(rpm_smooth)
	var drive: float = lerpf(0.5, 1.0, thr) * _shift_gain
	var base: float = 0.0 if is_player else OPPONENT_DB
	if is_player:
		low.pitch_scale = pit.x
		low.volume_db = _db(g.x * drive) + LAYER_DB
		mid.pitch_scale = pit.y
		mid.volume_db = _db(g.y * drive) + LAYER_DB
	else:
		# Opponents: low weight folds into the mid layer, fewer layers to mix.
		mid.pitch_scale = pit.y
		mid.volume_db = _db(sqrt(g.x * g.x + g.y * g.y) * drive) + LAYER_DB + base
	high.pitch_scale = pit.z
	high.volume_db = _db(g.z * drive * lerpf(0.65, 1.0, thr)) + LAYER_DB - 2.0 + base


func _update_tyres(delta: float) -> void:
	var slip: float = 0.0
	for i: int in car.wheel_slip.size():
		var s: float = car.wheel_slip[i] * (1.0 if i >= 2 else 0.8)
		slip = maxf(slip, s)
	var target: float = smoothstep(0.3, 0.9, slip) * smoothstep(8.0, 40.0, car.speed_kmh)
	if not car.is_grounded:
		target = 0.0
	_squeal_gain = move_toward(_squeal_gain, target, (6.0 if target > _squeal_gain else 4.0) * delta)
	squeal.pitch_scale = 0.88 + 0.3 * slip + 0.15 * clampf(car.speed_kmh / 250.0, 0.0, 1.0)
	var db: float = _db(_squeal_gain * 0.8) + (0.0 if is_player else OPPONENT_DB)
	_set_loop(squeal, db if _squeal_gain > 0.005 else -80.0)


func _update_hiss() -> void:
	var lvl: float = wetness * smoothstep(20.0, 180.0, car.speed_kmh) * (1.0 if car.is_grounded else 0.0)
	hiss.pitch_scale = 0.9 + 0.3 * clampf(car.speed_kmh / 250.0, 0.0, 1.0)
	_set_loop(hiss, _db(lvl * 0.6) if lvl > 0.01 else -80.0)


func _update_nitro(delta: float) -> void:
	var on: bool = car.nitro_active
	if on and not _nitro_prev:
		_one_shot(&"nitro_ignite", 0.0, 1.0)
	_nitro_prev = on
	_nitro_gain = move_toward(_nitro_gain, 1.0 if on else 0.0, (7.0 if on else 4.0) * delta)
	nitro.pitch_scale = 0.9 + 0.25 * clampf(car.speed_kmh / 300.0, 0.0, 1.0)
	_set_loop(nitro, _db(_nitro_gain * 0.9) if _nitro_gain > 0.005 else -80.0)


func _update_turbo(thr: float, delta: float) -> void:
	_cool_turbo = maxf(0.0, _cool_turbo - delta)
	_cool_bov = maxf(0.0, _cool_bov - delta)
	if thr > 0.8 and _last_throttle < 0.4 and car.rpm_norm > 0.25 and _cool_turbo <= 0.0:
		_one_shot(&"turbo_whoosh", -8.0, _rng.randf_range(0.95, 1.05))
		_cool_turbo = 1.5
	if thr < 0.15 and _last_throttle > 0.7 and car.rpm_norm > 0.45 and _cool_bov <= 0.0:
		_one_shot(&"blowoff", -5.0, _rng.randf_range(0.95, 1.05))
		_cool_bov = 1.0
		if car.rpm_norm > 0.65 and _rng.randf() < 0.6:
			_pops.append(_rng.randf_range(0.08, 0.2))
			if _rng.randf() < 0.5:
				_pops.append(_rng.randf_range(0.2, 0.4))
	var i: int = _pops.size() - 1
	while i >= 0:
		_pops[i] -= delta
		if _pops[i] <= 0.0:
			_one_shot(StringName("backfire_%d" % _rng.randi_range(1, 3)), -6.0, _rng.randf_range(0.9, 1.1))
			_pops.remove_at(i)
		i -= 1


func _set_loop(p: AudioStreamPlayer3D, db: float) -> void:
	p.volume_db = db
	if db > -60.0:
		if not p.playing and p.stream != null and p.is_inside_tree():
			p.play()
	elif p.playing:
		p.stop()


func _one_shot(id: StringName, db: float, pitch: float) -> void:
	if _shots.is_empty() or not is_inside_tree():
		return
	var s := AudioLib.get_stream(id)
	if s == null:
		return
	var p: AudioStreamPlayer3D = _shots[_shot_next]
	_shot_next = (_shot_next + 1) % _shots.size()
	p.stream = s
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()


func _on_car_hit(impulse: float, _world_pos: Vector3) -> void:
	if impulse < MIN_HIT_IMPULSE:
		return
	var heavy: bool = impulse >= HEAVY_HIT_IMPULSE
	var lvl: float = clampf(impulse / 20000.0, 0.15, 1.0)
	_one_shot(&"impact_heavy" if heavy else &"impact_light", linear_to_db(lvl), _rng.randf_range(0.92, 1.08))
