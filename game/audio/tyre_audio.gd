class_name TyreAudio
extends RefCounted
## Per-wheel tyre sliding voices for the player: one AudioStreamPlayer3D per wheel (4 voices, max_polyphony 1).
## Gain follows each wheel's slip. ArcadeCar exposes only lateral saturation (wheel_slip), not longitudinal slip
## ratio, so there is no separate rolling layer yet. shortcut: add rolling vs sliding when slip ratio is exposed.
## The three slip ranges are one equal-power crossfade of low/mid/high pitch on the same voice, because the budget
## is 4 voices. shortcut: three looped streams per wheel when the voice budget allows it.

const VOICES := 4
const SLIP_LO := 0.3  ## below this the tyre is silent
const SLIP_HI := 0.9  ## full sliding gain
const SPEED_LO_KMH := 8.0
const SPEED_HI_KMH := 40.0
const PITCH_LOW := 0.92
const PITCH_MID := 1.0
const PITCH_HIGH := 1.08  ## high slip sits +8 % above mid
## Same stream, same position: 4 voices at 0.4 with staggered starts sum (in power) to the old single squeal's 0.8.
## At 0.8 each, voices started in one frame summed coherently to 3.2 linear.
const GAIN_SCALE := 0.4
const AUDIBLE_GAIN := 0.005

var players: Array[AudioStreamPlayer3D] = []
var _gain := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])


## Sliding gain 0..1 for one wheel's slip. Monotonic, exactly 0 below SLIP_LO.
static func sliding_gain(slip: float) -> float:
	return clampf(smoothstep(SLIP_LO, SLIP_HI, slip), 0.0, 1.0)


## Equal-power weights (low, mid, high) over the slip ranges: the sum of squares is 1 at every slip.
static func range_weights(slip: float) -> Vector3:
	var p: float = clampf((slip - SLIP_LO) / (SLIP_HI - SLIP_LO), 0.0, 1.0) * 2.0  # 0 low, 1 mid, 2 high
	if p <= 1.0:
		return Vector3(cos(PI * 0.5 * p), sin(PI * 0.5 * p), 0.0)
	var q: float = p - 1.0
	return Vector3(0.0, cos(PI * 0.5 * q), sin(PI * 0.5 * q))


## Pitch multiplier for the slip range.
static func range_pitch(slip: float) -> float:
	var w: Vector3 = range_weights(slip)
	return w.x * PITCH_LOW + w.y * PITCH_MID + w.z * PITCH_HIGH


## Creates the 4 voices with the given stream. `make` returns a player already added under the car.
func setup(stream: AudioStream, make: Callable) -> void:
	for i: int in VOICES:
		var p: AudioStreamPlayer3D = make.call()
		p.stream = stream
		p.max_polyphony = 1
		players.append(p)


## Per frame. slip is wheel_slip (FL, FR, RL, RR); speed in km/h.
func update(slip: PackedFloat32Array, speed_kmh: float, grounded: bool, delta: float) -> void:
	var speed_f: float = smoothstep(SPEED_LO_KMH, SPEED_HI_KMH, speed_kmh)
	var pitch_base: float = 0.88 + 0.15 * clampf(speed_kmh / 250.0, 0.0, 1.0)
	for i: int in mini(VOICES, slip.size()):
		var s: float = slip[i] * (0.8 if i < 2 else 1.0)  # front tyres sit lower, as in CarAudio
		var target: float = sliding_gain(s) * speed_f if grounded else 0.0
		_gain[i] = move_toward(_gain[i], target, (6.0 if target > _gain[i] else 4.0) * delta)
		var p: AudioStreamPlayer3D = players[i]
		p.pitch_scale = pitch_base * range_pitch(s)
		if _gain[i] > AUDIBLE_GAIN:
			p.volume_db = linear_to_db(maxf(_gain[i] * GAIN_SCALE, 0.00003))
			if not p.playing and p.stream != null and p.is_inside_tree():
				p.play(p.stream.get_length() * 0.25 * i)  # stagger the loop so wheels do not add sample-aligned
		else:
			p.volume_db = -80.0
			if p.playing:
				p.stop()


func gain(wheel: int) -> float:
	return _gain[wheel]
