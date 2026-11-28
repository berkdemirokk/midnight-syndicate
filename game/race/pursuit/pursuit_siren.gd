class_name PursuitSiren
extends AudioStreamPlayer3D
## Looping police siren on one police car: a 3D source, so its volume falls with distance. PursuitMode attaches one to
## each car it spawns and stops them all when the chase ends. The loop is a 3.2 s wail cut from a CC0 recording.

const STREAM_PATH: String = "res://assets/audio/cc0/police_siren_wail.ogg"
const MAX_DISTANCE_M: float = 160.0  ## silent beyond this distance from the car
const UNIT_SIZE_M: float = 12.0  ## distance at which the siren is half as loud as at the car

static var _stream: AudioStreamOggVorbis = null  ## loaded once, shared by every car


## Adds a siren to car and starts it. Returns the node, silent when the file is missing (a broken build: warns).
static func attach(car: Node3D) -> PursuitSiren:
	var siren := PursuitSiren.new()
	siren.name = "Siren"
	car.add_child(siren)
	siren.setup()
	return siren


## Stops every siren under the given cars (the chase is over). Cars that were already freed are skipped.
static func stop_all(cars: Array) -> void:
	for c: Variant in cars:
		var node := c as Node
		if node == null or not is_instance_valid(node):
			continue
		for child: Node in node.get_children():
			if child is PursuitSiren:
				(child as AudioStreamPlayer3D).stop()


func setup() -> void:
	if _stream == null:
		_stream = load(STREAM_PATH) as AudioStreamOggVorbis
		if _stream == null:
			push_warning("PursuitSiren: cannot load %s" % STREAM_PATH)
			return
		_stream.loop = true
	stream = _stream
	AudioLib.ensure_buses()
	bus = AudioLib.BUS_SFX
	max_distance = MAX_DISTANCE_M
	unit_size = UNIT_SIZE_M
	if stream != null:
		play()
