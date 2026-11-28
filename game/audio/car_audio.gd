class_name CarAudio
extends Node3D
## Engine, tyre, nitro and impact audio for one ArcadeCar. Add as a child of the car (or call bind()).
## Reads car state only (rpm_norm, gear, input.throttle, wheel_slip, speed_kmh, nitro_active, hit).
## Player: layered engine (EngineLayers: 2 adjacent bands x on/off load = 4 voices, pitch per band) + squeal +
## wet hiss + nitro + scrape + turbo/blow-off/backfire/impacts. Fallback when layered_engine is false or a loop is
## missing: the old 3 single engine loops.
## Opponent (is_player = false): 1 engine loop (voice budget) + squeal, positional with Doppler, quieter.

const SHIFT_TIME := 0.20  ## seconds of rpm dip + level dip after an upshift
const SHIFT_RPM_DIP := 0.16
const SHIFT_CUT_TIME := 0.06  ## upshift cut: throttle dip and volume duck, seconds
const SHIFT_CUT_THROTTLE := 0.4  ## throttle multiplier during the cut
const SHIFT_CUT_GAIN := 0.3  ## volume multiplier during the cut
const LIMITER_RPM_NORM := 0.98  ## limiter bounce starts at this rpm_norm with throttle on
const LIMITER_HZ := 16.0
const LIMITER_DEPTH := 0.45  ## bounce dips the engine gain by this fraction
const LAYER_DB := -2.0
const LAYER_GAIN := 0.8  ## linear, same level as LAYER_DB for the layered voices
const OPPONENT_DB := -10.0
const RIVAL_MID_FLOOR := 0.5  ## rival level floor (-6 dB): the mid weight is zero at redline
const HEAVY_HIT_IMPULSE := 6000.0
const MIN_HIT_IMPULSE := 700.0
const AUDIBLE_FLOOR := 0.0001  ## band weight below this counts as silent
const STEAL_GAIN := 0.1  ## a silent band's slot may be taken by a new band once its voices are below this (-20 dB)
const VOICE_FADE := 40.0  ## 1/s, layered voice gain smoothing (about 25 ms time constant)

@export var is_player: bool = true
@export_range(0.0, 1.0) var wetness: float = 0.0  ## set by the weather system; scales tyre hiss on wet road
@export var layered_engine: bool = true  ## player only: false keeps the old single-loop engine
var scrape_level: float = 0.0  ## 0..1, set by whoever knows about wall contact

var car: ArcadeCar
var enabled: bool = true
var rpm_smooth: float = 0.0
var shift_timer: float = 0.0
var layered: bool = false  ## true while the player engine uses the layered bands
var engine_index: int = 2  ## EngineLayers.ENGINE_NAMES index for this car

var low: AudioStreamPlayer3D
var mid: AudioStreamPlayer3D
var high: AudioStreamPlayer3D
var squeal: AudioStreamPlayer3D
var hiss: AudioStreamPlayer3D
var nitro: AudioStreamPlayer3D
var scrape: AudioStreamPlayer3D

var _lv: Array[AudioStreamPlayer3D] = []  ## layered voices, index slot * 2 + load (load 0 off, 1 on)
var _slot_band := PackedInt32Array([-1, -1])  ## band held by each slot, -1 free
var _vgain := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])  ## smoothed linear gain per voice
var _vpitch := PackedFloat32Array([1.0, 1.0, 1.0, 1.0])
var _amp := PackedFloat32Array()  ## per-band audible amplitude, reused every frame
var _rpm_abs: float = 0.0
var _thr_eff: float = 0.0
var _cut_t: float = 0.0
var _duck: float = 1.0
var _limit_t: float = 0.0
var _bounce: float = 1.0
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
var tyre: TyreAudio  ## player only: 4 per-wheel sliding voices; they replace the squeal loop's sound


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
	layered = is_player and layered_engine and EngineLayers.loops_ready()
	if layered:
		for i: int in 4:
			_lv.append(_make_player(true))
	else:
		low = _loop_player(&"engine_low_loop", LAYER_DB, near) if is_player else null
		mid = _loop_player(&"engine_mid_loop", LAYER_DB, near)
		high = _loop_player(&"engine_high_loop", LAYER_DB - 2.0, near) if is_player else null
	squeal = _loop_player(&"tyre_squeal_loop", -80.0, near)
	if is_player:
		hiss = _loop_player(&"tyre_hiss_wet_loop", -80.0, true)
		tyre = TyreAudio.new()
		tyre.setup(AudioLib.get_stream(&"tyre_squeal_loop"), _make_player.bind(true))
		nitro = _loop_player(&"nitro_loop", -80.0, true)
		scrape = _loop_player(&"scrape_loop", -80.0, true)
		for i: int in 4:
			var p := _make_player(true)
			p.max_polyphony = 2
			_shots.append(p)
	# Engine layers on the Engine bus (its own volume slider in Settings) when it exists.
	if AudioServer.get_bus_index(&"Engine") >= 0:
		for p: AudioStreamPlayer3D in _engine_players():
			p.bus = &"Engine"
	for p: AudioStreamPlayer3D in [low, mid, high, squeal, hiss, nitro, scrape]:
		if p != null and p.stream != null and p.is_inside_tree():
			p.play()


func _engine_players() -> Array[AudioStreamPlayer3D]:
	var out: Array[AudioStreamPlayer3D] = []
	for p: AudioStreamPlayer3D in [low, mid, high]:
		if p != null:
			out.append(p)
	out.append_array(_lv)
	return out


func _all_players() -> Array[AudioStreamPlayer3D]:
	var out: Array[AudioStreamPlayer3D] = []
	for p: AudioStreamPlayer3D in [low, mid, high, squeal, hiss, nitro, scrape]:
		if p != null:
			out.append(p)
	out.append_array(_lv)
	out.append_array(_shots)
	if tyre != null:
		out.append_array(tyre.players)
	return out


## Engine voices that are playing now: 4 at most for the player, 1 for an opponent.
func engine_voices_playing() -> int:
	var n: int = 0
	for p: AudioStreamPlayer3D in _engine_players():
		if p.playing:
			n += 1
	return n


## Band held by each layered slot (-1 free). For tests and the evidence log.
func slot_bands() -> PackedInt32Array:
	return _slot_band


## Per-voice state for the evidence log, voice index slot * 2 + load.
func voice_gain(v: int) -> float:
	return _vgain[v]


func voice_pitch(v: int) -> float:
	return _vpitch[v]


func throttle_effective() -> float:
	return _thr_eff


func rpm_abs() -> float:
	return _rpm_abs


func duck() -> float:
	return _duck


func bounce() -> float:
	return _bounce


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
		_cut_t = SHIFT_CUT_TIME
		if is_player and thr > 0.7 and car.rpm_norm > 0.55 and _rng.randf() < 0.35:
			_pops.append(_rng.randf_range(0.04, 0.12))
	_last_gear = gear_now
	shift_timer = maxf(0.0, shift_timer - delta)
	_cut_t = maxf(0.0, _cut_t - delta)

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

	if layered:
		_update_layers(thr, delta)
	else:
		_update_engine(thr)
	_update_tyres(delta)
	if is_player:
		_update_nitro(delta)
		_update_turbo(thr, delta)
		_update_hiss()
		var sc: float = clampf(scrape_level, 0.0, 1.0)
		_set_loop(scrape, _db(sc * 0.8) if sc > 0.01 else -80.0)
	_last_throttle = thr


## Layered player engine: at most two adjacent bands (4 voices) at once, each with its own on/off pair.
func _update_layers(thr: float, delta: float) -> void:
	var sp: CarSpec = car.spec
	var idle: float = sp.idle_rpm if sp != null else 1000.0
	var redline: float = sp.redline_rpm if sp != null else 7500.0
	var eng: int = EngineLayers.engine_for_spec(sp)
	if eng != engine_index:
		engine_index = eng
		for s: int in 2:
			_free_slot(s)
	_rpm_abs = idle + clampf(rpm_smooth, 0.0, 1.0) * (redline - idle)
	_thr_eff = thr * (SHIFT_CUT_THROTTLE if _cut_t > 0.0 else 1.0)
	var duck_t: float = SHIFT_CUT_GAIN if _cut_t > 0.0 else 1.0
	_duck = lerpf(_duck, duck_t, 1.0 - exp(-120.0 * delta))
	_limit_t += delta
	var bounce_t: float = 1.0
	if car.rpm_norm >= LIMITER_RPM_NORM and thr > 0.5:
		bounce_t = 1.0 - LIMITER_DEPTH * (0.5 - 0.5 * cos(TAU * LIMITER_HZ * _limit_t))
	_bounce = lerpf(_bounce, bounce_t, 1.0 - exp(-200.0 * delta))  ## fast enough to keep the 16 Hz bounce in its shape

	var w: PackedFloat32Array = EngineLayers.band_weights(_rpm_abs, _thr_eff)
	_assign_slots(w)
	var k: float = 1.0 - exp(-VOICE_FADE * delta)
	for s: int in 2:
		var b: int = _slot_band[s]
		for l: int in 2:
			var v: int = s * 2 + l
			var target: float = 0.0
			if b >= 0:
				target = w[b * 2 + l] * EngineLayers.loop_norm(eng, b, l) * LAYER_GAIN * _duck * _bounce * _shift_gain
				_vpitch[v] = EngineLayers.band_pitch(_rpm_abs, b)
				_lv[v].pitch_scale = _vpitch[v]
			_vgain[v] = lerpf(_vgain[v], target, k)
			_lv[v].volume_db = _db(_vgain[v])


## Frees slots whose band has gone quiet and faded out, then gives a slot to each newly audible band.
func _assign_slots(w: PackedFloat32Array) -> void:
	if _amp.size() != EngineLayers.BANDS:
		_amp.resize(EngineLayers.BANDS)
	for b: int in EngineLayers.BANDS:
		_amp[b] = maxf(w[b * 2], w[b * 2 + 1])
	for s: int in 2:
		var b: int = _slot_band[s]
		if b >= 0 and _amp[b] <= AUDIBLE_FLOOR and _vgain[s * 2] < 0.001 and _vgain[s * 2 + 1] < 0.001:
			_free_slot(s)
	for b: int in EngineLayers.BANDS:
		if _amp[b] <= AUDIBLE_FLOOR or _slot_band.find(b) >= 0:
			continue
		var s: int = _slot_band.find(-1)
		if s < 0:
			s = _steal_slot()
		if s < 0:
			break  # two adjacent bands at most; a band that finds no free slot waits until one frees
		_slot_band[s] = b
		for l: int in 2:
			var v: int = s * 2 + l
			_lv[v].stream = AudioLib.get_stream(EngineLayers.loop_id(engine_index, b, l))
			_vgain[v] = 0.0
			_lv[v].volume_db = -80.0
			_lv[v].play()


## After a fast rpm drop (upshift) both slots can still hold fading bands of the old rpm while the new band
## waits, which left the engine near silent for about 150 ms. Take the quieter slot whose band is silent once
## it is below STEAL_GAIN; -1 when no slot qualifies.
func _steal_slot() -> int:
	var best: int = -1
	var best_g: float = STEAL_GAIN
	for s: int in 2:
		var g: float = maxf(_vgain[s * 2], _vgain[s * 2 + 1])
		if _amp[_slot_band[s]] <= AUDIBLE_FLOOR and g < best_g:
			best = s
			best_g = g
	if best >= 0:
		_free_slot(best)
	return best


func _free_slot(s: int) -> void:
	_slot_band[s] = -1
	for l: int in 2:
		var v: int = s * 2 + l
		_vgain[v] = 0.0
		if _lv[v].playing:
			_lv[v].stop()


func _update_engine(thr: float) -> void:
	var g: Vector3 = layer_gains(rpm_smooth)
	var pit: Vector3 = layer_pitches(rpm_smooth)
	var drive: float = lerpf(0.5, 1.0, thr) * _shift_gain
	if is_player:
		low.pitch_scale = pit.x
		low.volume_db = _db(g.x * drive) + LAYER_DB
		mid.pitch_scale = pit.y
		mid.volume_db = _db(g.y * drive) + LAYER_DB
		high.pitch_scale = pit.z
		high.volume_db = _db(g.z * drive * lerpf(0.65, 1.0, thr)) + LAYER_DB - 2.0
	else:
		# Opponents: one loop (the old engine_mid_loop) at the mid pitch, quieter; no separate high layer.
		# Level follows rpm as the old path did (low+mid share), floored so the rival is not silent at redline.
		mid.pitch_scale = pit.y
		mid.volume_db = _db(maxf(sqrt(g.x * g.x + g.y * g.y), RIVAL_MID_FLOOR) * drive) + LAYER_DB + OPPONENT_DB


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
	if tyre != null:
		# Wheel voices carry the sound. The squeal loop stays silent; its level is still set for the tests.
		tyre.update(car.wheel_slip, car.speed_kmh, car.is_grounded, delta)
		squeal.volume_db = db if _squeal_gain > 0.005 else -80.0
		if squeal.playing:
			squeal.stop()
		return
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
