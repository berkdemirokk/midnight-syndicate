extends "res://tests/test_case.gd"
## Perf card: ring buffer cap, p95 order, numeric fields after 120 frames, the card stays off headless,
## and the first-use warm-up frees every node it adds.

const WARM: GDScript = preload("res://core/pipeline_warmup.gd")


func test_ring_buffer_caps_at_36000() -> void:
	var c: PerfCard = PerfCard.new()
	for i: int in 36005:
		c.record(16.0 + float(i % 3))
	check(c.sample_count() == 36000, "ring caps at 36000, got %d" % c.sample_count())
	check_range(c.stats().mean_ms, 16.0, 17.0, "mean ms of a 16-18 ms ring")
	c.free()


func test_p95_picks_the_95th_sample() -> void:
	var c: PerfCard = PerfCard.new()
	for i: int in range(1, 101):
		c.record(float(i))
	check(is_equal_approx(float(c.stats().p95_ms), 95.0), "p95 of 1..100 is 95, got %s" % str(c.stats().p95_ms))
	c.free()


func test_card_fields_are_numbers_after_120_frames() -> void:
	var c: PerfCard = PerfCard.new()
	add(c)
	c.reset()
	await frames(130)
	var s: Dictionary = c.stats()
	check(int(s.frames) >= 120, "frames counted: %s" % str(s.frames))
	for key: String in ["mean_ms", "p95_ms", "minutes"]:
		check(typeof(s[key]) == TYPE_FLOAT and not is_nan(float(s[key])), "%s is a number" % key)
	for key: String in ["draws", "draw_min", "draw_peak", "prims"]:
		check(typeof(s[key]) == TYPE_INT, "%s is an int" % key)
	check(float(s.mean_ms) > 0.0, "frame time recorded")
	check(c._label.text != "", "card text filled after the refresh")
	await cleanup([c])


func test_card_never_created_headless() -> void:
	if DisplayServer.get_name() != "headless":
		return
	var before: int = tree.root.get_child_count()
	PerfCard.begin_session(tree)
	check(tree.root.get_child_count() == before, "headless run adds no card to root")


func test_warmup_frees_its_nodes() -> void:
	var host := Node.new()
	add(host)
	WARM.run(host)
	await frames(8)
	check(host.get_child_count() == 0, "warm-up left %d node(s)" % host.get_child_count())
	await cleanup([host])
