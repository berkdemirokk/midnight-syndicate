class_name PerfProbe
extends RefCounted
## Frame time and render counters over N frames. Turns vsync and the fps cap off for the run and restores them after.

const WARMUP_FRAMES: int = 10
const PCT_P95: float = 0.95
const PCT_P99: float = 0.99
const BYTES_PER_MB: float = 1048576.0


func measure(tree: SceneTree, frames: int) -> Dictionary:
	frames = maxi(frames, 1)
	var prev_max_fps: int = Engine.max_fps
	var prev_vsync: DisplayServer.VSyncMode = DisplayServer.window_get_vsync_mode()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	for i: int in WARMUP_FRAMES:
		await tree.process_frame
	var times := PackedFloat64Array()
	times.resize(frames)
	var last_us: int = Time.get_ticks_usec()
	for i: int in frames:
		await tree.process_frame
		var now_us: int = Time.get_ticks_usec()
		times[i] = (now_us - last_us) / 1000.0
		last_us = now_us
	Engine.max_fps = prev_max_fps
	DisplayServer.window_set_vsync_mode(prev_vsync)

	var sorted: PackedFloat64Array = times.duplicate()
	sorted.sort()
	var total: float = 0.0
	for t: float in times:
		total += t
	var mean: float = total / frames
	return {
		"frames": frames,
		"frame_ms_avg": _round3(mean),
		"frame_ms_p95": _round3(_percentile(sorted, PCT_P95)),
		"frame_ms_p99": _round3(_percentile(sorted, PCT_P99)),
		"fps": _round3(1000.0 / mean) if mean > 0.0 else 0.0,
		"draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		"objects": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		"video_mem_mb": _round3(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / BYTES_PER_MB),
		"adapter": RenderingServer.get_video_adapter_name(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"driver": RenderingServer.get_current_rendering_driver_name(),
		"os": OS.get_name(),
		"viewport_size": [tree.root.size.x, tree.root.size.y],
		"scaling_3d_scale": snappedf(tree.root.scaling_3d_scale, 0.001),
	}


func _percentile(sorted: PackedFloat64Array, p: float) -> float:
	var idx: int = clampi(int(ceil(p * sorted.size())) - 1, 0, sorted.size() - 1)
	return sorted[idx]


func _round3(v: float) -> float:
	return snappedf(v, 0.001)
