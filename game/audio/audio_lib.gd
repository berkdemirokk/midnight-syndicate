class_name AudioLib
extends RefCounted
## Audio catalogue: stream ids -> generated WAV files (tools/audio_synth.py), bus names, bus helpers.
## Loops are also forced to loop at load time, so they loop even if an .import lost its smpl flag.

const BUS_MASTER := &"Master"
const BUS_MUSIC := &"Music"
const BUS_SFX := &"SFX"
const BUS_UI := &"UI"

const DIR := "res://assets/audio/"

## id -> [relative path, is_loop]
const FILES: Dictionary = {
	&"engine_low_loop": ["sfx/engine_low_loop.wav", true],
	&"engine_mid_loop": ["sfx/engine_mid_loop.wav", true],
	&"engine_high_loop": ["sfx/engine_high_loop.wav", true],
	&"eng_i4_b1_on": ["engine/i4_b1_on.wav", true],
	&"eng_i4_b1_off": ["engine/i4_b1_off.wav", true],
	&"eng_i4_b2_on": ["engine/i4_b2_on.wav", true],
	&"eng_i4_b2_off": ["engine/i4_b2_off.wav", true],
	&"eng_i4_b3_on": ["engine/i4_b3_on.wav", true],
	&"eng_i4_b3_off": ["engine/i4_b3_off.wav", true],
	&"eng_i4_b4_on": ["engine/i4_b4_on.wav", true],
	&"eng_i4_b4_off": ["engine/i4_b4_off.wav", true],
	&"eng_i4_b5_on": ["engine/i4_b5_on.wav", true],
	&"eng_i4_b5_off": ["engine/i4_b5_off.wav", true],
	&"eng_i4_b6_on": ["engine/i4_b6_on.wav", true],
	&"eng_i4_b6_off": ["engine/i4_b6_off.wav", true],
	&"eng_v6_b1_on": ["engine/v6_b1_on.wav", true],
	&"eng_v6_b1_off": ["engine/v6_b1_off.wav", true],
	&"eng_v6_b2_on": ["engine/v6_b2_on.wav", true],
	&"eng_v6_b2_off": ["engine/v6_b2_off.wav", true],
	&"eng_v6_b3_on": ["engine/v6_b3_on.wav", true],
	&"eng_v6_b3_off": ["engine/v6_b3_off.wav", true],
	&"eng_v6_b4_on": ["engine/v6_b4_on.wav", true],
	&"eng_v6_b4_off": ["engine/v6_b4_off.wav", true],
	&"eng_v6_b5_on": ["engine/v6_b5_on.wav", true],
	&"eng_v6_b5_off": ["engine/v6_b5_off.wav", true],
	&"eng_v6_b6_on": ["engine/v6_b6_on.wav", true],
	&"eng_v6_b6_off": ["engine/v6_b6_off.wav", true],
	&"eng_v8_b1_on": ["engine/v8_b1_on.wav", true],
	&"eng_v8_b1_off": ["engine/v8_b1_off.wav", true],
	&"eng_v8_b2_on": ["engine/v8_b2_on.wav", true],
	&"eng_v8_b2_off": ["engine/v8_b2_off.wav", true],
	&"eng_v8_b3_on": ["engine/v8_b3_on.wav", true],
	&"eng_v8_b3_off": ["engine/v8_b3_off.wav", true],
	&"eng_v8_b4_on": ["engine/v8_b4_on.wav", true],
	&"eng_v8_b4_off": ["engine/v8_b4_off.wav", true],
	&"eng_v8_b5_on": ["engine/v8_b5_on.wav", true],
	&"eng_v8_b5_off": ["engine/v8_b5_off.wav", true],
	&"eng_v8_b6_on": ["engine/v8_b6_on.wav", true],
	&"eng_v8_b6_off": ["engine/v8_b6_off.wav", true],
	&"eng_hy_b1_on": ["engine/hy_b1_on.wav", true],
	&"eng_hy_b1_off": ["engine/hy_b1_off.wav", true],
	&"eng_hy_b2_on": ["engine/hy_b2_on.wav", true],
	&"eng_hy_b2_off": ["engine/hy_b2_off.wav", true],
	&"eng_hy_b3_on": ["engine/hy_b3_on.wav", true],
	&"eng_hy_b3_off": ["engine/hy_b3_off.wav", true],
	&"eng_hy_b4_on": ["engine/hy_b4_on.wav", true],
	&"eng_hy_b4_off": ["engine/hy_b4_off.wav", true],
	&"eng_hy_b5_on": ["engine/hy_b5_on.wav", true],
	&"eng_hy_b5_off": ["engine/hy_b5_off.wav", true],
	&"eng_hy_b6_on": ["engine/hy_b6_on.wav", true],
	&"eng_hy_b6_off": ["engine/hy_b6_off.wav", true],
	&"turbo_whoosh": ["sfx/turbo_whoosh.wav", false],
	&"blowoff": ["sfx/blowoff.wav", false],
	&"backfire_1": ["sfx/backfire_1.wav", false],
	&"backfire_2": ["sfx/backfire_2.wav", false],
	&"backfire_3": ["sfx/backfire_3.wav", false],
	&"tyre_squeal_loop": ["sfx/tyre_squeal_loop.wav", true],
	&"tyre_hiss_wet_loop": ["sfx/tyre_hiss_wet_loop.wav", true],
	&"nitro_ignite": ["sfx/nitro_ignite.wav", false],
	&"nitro_loop": ["sfx/nitro_loop.wav", true],
	&"impact_light": ["sfx/impact_light.wav", false],
	&"impact_heavy": ["sfx/impact_heavy.wav", false],
	&"scrape_loop": ["sfx/scrape_loop.wav", true],
	&"rain_loop": ["sfx/rain_loop.wav", true],
	&"ui_click": ["ui/ui_click.wav", false],
	&"ui_confirm": ["ui/ui_confirm.wav", false],
	&"ui_back": ["ui/ui_back.wav", false],
	&"countdown_beep": ["ui/countdown_beep.wav", false],
	&"countdown_go": ["ui/countdown_go.wav", false],
	&"race_finish_sting": ["ui/race_finish_sting.wav", false],
	&"cash_tick": ["ui/cash_tick.wav", false],
	&"music_race_loop": ["music/music_race_loop.wav", true],
	&"music_menu_loop": ["music/music_menu_loop.wav", true],
}

static var _cache: Dictionary = {}


static func has_id(id: StringName) -> bool:
	return FILES.has(id)


static func is_loop(id: StringName) -> bool:
	return FILES.has(id) and (FILES[id] as Array)[1]


## Returns the (cached) stream or null with a warning when the id or file is missing.
static func get_stream(id: StringName) -> AudioStream:
	if _cache.has(id):
		return _cache[id]
	if not FILES.has(id):
		push_warning("AudioLib: unknown sound id '%s'" % id)
		return null
	var entry: Array = FILES[id]
	var s := load(DIR + (entry[0] as String)) as AudioStream
	if s == null:
		push_warning("AudioLib: cannot load %s" % entry[0])
		return null
	var wav := s as AudioStreamWAV
	if wav != null:
		if entry[1]:
			# The importer already reads the smpl chunk; this only repairs a lost flag.
			# (data may be QOA/ADPCM compressed, so derive the end from the length, not the byte count.)
			if wav.loop_mode == AudioStreamWAV.LOOP_DISABLED:
				wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
				wav.loop_begin = 0
				wav.loop_end = int(wav.get_length() * wav.mix_rate) - 1
		else:
			wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
	_cache[id] = s
	return s


## Create Music/SFX/UI buses when the project's bus layout did not load (idempotent).
static func ensure_buses() -> void:
	for b: StringName in [BUS_MUSIC, BUS_SFX, BUS_UI]:
		if AudioServer.get_bus_index(b) == -1:
			AudioServer.add_bus()
			var i: int = AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, BUS_MASTER)


static func set_bus_linear(bus: StringName, linear: float) -> void:
	var i: int = AudioServer.get_bus_index(bus)
	if i == -1:
		return
	var l: float = clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_mute(i, l <= 0.0001)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(l, 0.0001)))


static func get_bus_linear(bus: StringName) -> float:
	var i: int = AudioServer.get_bus_index(bus)
	if i == -1:
		return 1.0
	return 0.0 if AudioServer.is_bus_mute(i) else db_to_linear(AudioServer.get_bus_volume_db(i))
