class_name PerfCard
extends CanvasLayer
## On-screen frame-time card for device sessions: mean and p95 frame time, draw calls and primitives, minutes since the
## race started. Keeps the last 10 minutes of frames in a ring buffer and prints one summary line when the race scene ends.
## Shown only when Settings.perf_card is on: TestFlight builds default on, every other build off. Never created headless.

const RING_CAP: int = 36000  ## 10 minutes at 60 Hz
const REFRESH_FRAMES: int = 60
const P95_EVERY: int = 600  ## the p95 sorts the whole ring, so it runs every 10 s, not on every refresh
const LAYER: int = 90
const TEXT_PX: int = 20
const MS_PER_MIN: float = 60000.0
const P95: float = 0.95

static var _inst: PerfCard = null

var _ring: PackedFloat32Array = PackedFloat32Array()
var _count: int = 0  ## valid samples in the ring, up to RING_CAP
var _next: int = 0  ## ring write index
var _sum: float = 0.0  ## running sum of the valid samples, so the mean costs O(1) per refresh
var _p95: float = 0.0  ## last sorted p95, refreshed every P95_EVERY frames and at finish
var _frames: int = 0
var _draws: int = 0
var _draw_min: int = 2147483647
var _draw_peak: int = 0
var _prims: int = 0
var _started_ms: int = 0
var _active: bool = false
var _seen_race: bool = false
var _since_refresh: int = 0
var _label: Label = null


func _init() -> void:
	layer = LAYER
	_ring.resize(RING_CAP)


func _ready() -> void:
	var ins: Vector4 = MSTheme.safe_insets()
	_label = MSTheme.make_label("", "digits", MSTheme.px(TEXT_PX), MSTheme.CYAN, true)
	_label.position = Vector2(ins.x + 16.0, ins.y + 8.0)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.visible = false
	add_child(_label)


## Starts a session, or restarts it. The card appears at once; the ring buffer starts empty.
static func begin_session(tree: SceneTree) -> void:
	if not Settings.perf_card or DisplayServer.get_name() == "headless":
		return
	if _inst == null or not is_instance_valid(_inst):
		_inst = PerfCard.new()
		tree.root.add_child(_inst)
	_inst.reset()


static func end_session() -> void:
	if _inst != null and is_instance_valid(_inst):
		_inst.finish()


func reset() -> void:
	_count = 0
	_next = 0
	_sum = 0.0
	_p95 = 0.0
	_frames = 0
	_draw_min = 2147483647
	_draw_peak = 0
	_started_ms = Time.get_ticks_msec()
	_active = true
	_seen_race = false
	_since_refresh = 0
	_label.visible = true


## Adds one frame time sample in milliseconds. Keeps only the newest RING_CAP samples.
func record(frame_ms: float) -> void:
	if _count == RING_CAP:
		_sum -= _ring[_next]  # the slot about to be overwritten leaves the running sum
	_ring[_next] = frame_ms
	_sum += frame_ms
	_next = (_next + 1) % RING_CAP
	_count = mini(_count + 1, RING_CAP)


func sample_count() -> int:
	return _count


## Exact p95 right now. Sorts the ring, so it is for finish() and tests, not for every frame.
func stats() -> Dictionary:
	return _summary(_p95_now())


func _p95_now() -> float:
	if _count == 0:
		return 0.0
	var sorted: PackedFloat32Array = _ring.slice(0, _count)
	sorted.sort()
	return sorted[int(floorf(P95 * float(_count - 1)))]


func _summary(p95: float) -> Dictionary:
	return {
		"frames": _frames,
		"mean_ms": _sum / float(_count) if _count > 0 else 0.0,
		"p95_ms": p95,
		"draws": _draws,
		"draw_min": 0 if _frames == 0 else _draw_min,
		"draw_peak": _draw_peak,
		"prims": _prims,
		"minutes": float(Time.get_ticks_msec() - _started_ms) / MS_PER_MIN,
	}


func _process(delta: float) -> void:
	if not _active:
		return
	var tree: SceneTree = get_tree()
	if tree.current_scene is RaceScene:
		_seen_race = true
	elif _seen_race and tree.current_scene != null:
		finish()  # the race scene has gone: the session is over
		return
	record(delta * 1000.0)
	_frames += 1
	_draws = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	_prims = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	_draw_min = mini(_draw_min, _draws)
	_draw_peak = maxi(_draw_peak, _draws)
	_since_refresh += 1
	if _since_refresh >= REFRESH_FRAMES or _frames == 120:
		_since_refresh = 0
		# Refresh frames are multiples of 60 from the session start, so the P95_EVERY frames land on one of them.
		_refresh(_frames == 120 or _frames % P95_EVERY == 0)


## Updates the label. The p95 sort runs only when full is true; otherwise the last p95 stays on the label.
func _refresh(full: bool) -> void:
	if full:
		_p95 = _p95_now()
	var s: Dictionary = _summary(_p95)
	_label.text = "%.1f ms mean  %.1f ms p95  %d draws (min %d, peak %d)  %.1f min" % [
		s.mean_ms, s.p95_ms, s.draws, s.draw_min, s.draw_peak, s.minutes]


## Prints the session summary once, then hides the card.
func finish() -> void:
	if not _active:
		return
	_refresh(true)
	var s: Dictionary = stats()
	print("PERF session frames=%d mean_ms=%.2f p95_ms=%.2f draws_min=%d draws_peak=%d prims=%d minutes=%.2f" % [
		s.frames, s.mean_ms, s.p95_ms, s.draw_min, s.draw_peak, _prims, s.minutes])
	_active = false
	_label.visible = false
