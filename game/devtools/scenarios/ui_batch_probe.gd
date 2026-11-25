extends "res://devtools/capture_scenario.gd"
## Learns what breaks 2D batching in this renderer: draws per variant, each shown alone.
## Run: capture_boot.tscn -- --capture=ui_batch_probe

const SAMPLE_FRAMES: int = 12


class Probe:
	extends Control
	var kind: String = ""

	func _draw() -> void:
		var f: Font = MSTheme.font("digits")
		var f2: Font = MSTheme.font("tracked")
		var col := Color(1, 1, 1, 1)
		match kind:
			"str_same":
				for i: int in 10:
					draw_string(f, Vector2(20, 60 + i * 40), "%d" % i, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, col)
			"str_outline_same":
				for i: int in 10:
					draw_string_outline(f, Vector2(20, 60 + i * 40), "%d" % i, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, 4, Color.BLACK)
					draw_string(f, Vector2(20, 60 + i * 40), "%d" % i, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, col)
			"str_outline_grouped":
				for i: int in 10:
					draw_string_outline(f, Vector2(20, 60 + i * 40), "%d" % i, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, 4, Color.BLACK)
				for i: int in 10:
					draw_string(f, Vector2(20, 60 + i * 40), "%d" % i, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, col)
			"str_sizes":
				for i: int in 10:
					draw_string(f, Vector2(20, 60 + i * 40), "%d" % i, HORIZONTAL_ALIGNMENT_LEFT, -1, 20 + i, col)
			"str_two_fonts_alt":
				for i: int in 10:
					draw_string(f if i % 2 == 0 else f2, Vector2(20, 60 + i * 40), "%d" % i, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, col)
			"rect_fill":
				for i: int in 12:
					draw_rect(Rect2(20 + i * 30, 20, 20, 20), Color(1, 0, 0, 0.1 + i * 0.05))
			"rect_outline":
				for i: int in 12:
					draw_rect(Rect2(20 + i * 30, 20, 20, 20), Color(1, 0, 0), false, 2.0)
			"line":
				for i: int in 9:
					draw_line(Vector2(20 + i * 30, 20), Vector2(20 + i * 30, 60), col, 2.0, true)
			"line_noaa":
				for i: int in 9:
					draw_line(Vector2(20 + i * 30, 20), Vector2(20 + i * 30, 60), col, 2.0, false)
			"arc":
				for i: int in 4:
					draw_arc(Vector2(200, 200), 100 + i, 0.0, 3.0, 32, col, 12.0, true)
			"circle":
				for i: int in 6:
					draw_circle(Vector2(100 + i * 30, 100), 7.0, col)
			"polygon":
				draw_colored_polygon(PackedVector2Array([Vector2(24, 0), Vector2(200, 0), Vector2(176, 100), Vector2(0, 100)]), col)
			"polyline":
				draw_polyline(PackedVector2Array([Vector2(24, 0), Vector2(200, 0), Vector2(176, 100), Vector2(0, 100)]), col, 2.0, true)
			"tex_same":
				var t: Texture2D = MSTheme.disc_texture(16, Color.WHITE)
				for i: int in 12:
					draw_texture_rect(t, Rect2(20 + i * 30, 20, 16, 16), false, Color(1, i / 12.0, 0))
			"tex_two":
				var t1: Texture2D = MSTheme.disc_texture(16, Color.WHITE)
				var t2: Texture2D = MSTheme.disc_texture(18, Color.WHITE)
				for i: int in 12:
					draw_texture_rect(t1 if i % 2 == 0 else t2, Rect2(20 + i * 30, 20, 16, 16), false)
			"mix_shapes_nonaa":
				for i: int in 3:
					draw_rect(Rect2(20 + i * 30, 20, 20, 20), Color(1, 0, 0, 0.5))
				for i: int in 3:
					draw_line(Vector2(20 + i * 30, 60), Vector2(40 + i * 30, 100), col, 2.0, false)
				draw_colored_polygon(PackedVector2Array([Vector2(24, 120), Vector2(200, 120), Vector2(176, 200), Vector2(0, 200)]), Color(0, 0, 1, 0.5))
				draw_polyline(PackedVector2Array([Vector2(24, 220), Vector2(200, 220), Vector2(176, 300), Vector2(0, 300)]), col, 3.0, false)
				draw_circle(Vector2(300, 300), 7.0, col)
			"arc_noaa":
				for i: int in 4:
					draw_arc(Vector2(200, 200), 100 + i, 0.0, 3.0, 32, col, 12.0, false)
			"polyline_noaa":
				draw_polyline(PackedVector2Array([Vector2(24, 0), Vector2(200, 0), Vector2(176, 100), Vector2(0, 100)]), col, 2.0, false)
			"multiline":
				draw_multiline(PackedVector2Array([Vector2(20, 20), Vector2(20, 60), Vector2(50, 20), Vector2(50, 60), Vector2(80, 20), Vector2(80, 60)]), col, 2.0, true)
			"poly_tex_uv":
				var tp: Texture2D = MSTheme.disc_texture(16, Color.WHITE)
				for i: int in 3:
					draw_colored_polygon(PackedVector2Array([Vector2(20 + i * 40, 20), Vector2(50 + i * 40, 20), Vector2(50 + i * 40, 60), Vector2(20 + i * 40, 60)]), col,
						PackedVector2Array([Vector2(0, 0), Vector2(16, 0), Vector2(16, 16), Vector2(0, 16)]), tp)
			"colored_strip":
				var pts := PackedVector2Array()
				var cols := PackedColorArray()
				for i: int in 20:
					var a: float = i * 0.15
					pts.append(Vector2(200, 200) + Vector2(cos(a), sin(a)) * 100.0)
					pts.append(Vector2(200, 200) + Vector2(cos(a), sin(a)) * 112.0)
					cols.append(Color.CYAN)
					cols.append(Color.CYAN)
				draw_polygon(pts, cols)
			"scaled_str":
				draw_set_transform(Vector2(100, 100), 0.0, Vector2(1.5, 1.5))
				for i: int in 4:
					draw_string(f, Vector2(0, i * 30), "%d" % i, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, col)
				draw_set_transform(Vector2.ZERO)
				for i: int in 4:
					draw_string(f, Vector2(300, 30 + i * 30), "%d" % i, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, col)
			"rect_then_str_then_rect":
				for i: int in 6:
					draw_rect(Rect2(20, 20 + i * 40, 20, 20), Color(1, 0, 0))
					draw_string(f, Vector2(60, 40 + i * 40), "%d" % i, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, col)


func _draws() -> int:
	var peak: int = 0
	for i: int in SAMPLE_FRAMES:
		await tree.process_frame
		peak = maxi(peak, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	return peak


func _label_variant(count: int, outline: int, sizes: bool, font_kind: String = "digits") -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for i: int in count:
		var l := MSTheme.make_label("%d" % i, font_kind, 24 + (i if sizes else 0), MSTheme.TEXT, outline > 0)
		l.position = Vector2(20, 20 + i * 40)
		root.add_child(l)
	return root


func run() -> void:
	cap.set_size(1920, 1080)
	var layer := CanvasLayer.new()
	tree.root.add_child(layer)
	var variants: Dictionary = {}
	variants["label_x10_same_noOutline"] = _label_variant(10, 0, false)
	variants["label_x10_same_outline4"] = _label_variant(10, 4, false)
	variants["label_x10_sizes_noOutline"] = _label_variant(10, 0, true)
	variants["label_x10_sizes_outline4"] = _label_variant(10, 4, true)
	for k: String in ["str_same", "str_outline_same", "str_outline_grouped", "str_sizes", "str_two_fonts_alt", "rect_fill", "rect_outline",
			"line", "line_noaa", "arc", "circle", "polygon", "polyline", "tex_same", "tex_two", "rect_then_str_then_rect",
			"mix_shapes_nonaa", "arc_noaa", "polyline_noaa", "multiline", "poly_tex_uv", "colored_strip", "scaled_str"]:
		var p := Probe.new()
		p.kind = k
		p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		variants[k] = p
	var sib_a := Control.new()
	var sib_b := Control.new()
	for k2: String in ["str_same", "str_same"]:
		var q := Probe.new()
		q.kind = k2
		sib_a.add_child(q)
	for k3: String in ["rect_fill", "str_same", "rect_fill"]:
		var q2 := Probe.new()
		q2.kind = k3
		sib_b.add_child(q2)
	variants["sib_str_x2"] = sib_a
	variants["sib_rect_str_rect"] = sib_b
	var panel := PanelContainer.new()
	panel.theme = MSTheme.build()
	var pl := Label.new()
	pl.text = "x"
	panel.add_child(pl)
	variants["panel_container_x1"] = panel
	var many := Control.new()
	for i: int in 5:
		var pc := PanelContainer.new()
		pc.theme = MSTheme.build()
		pc.position = Vector2(20, 20 + i * 80)
		many.add_child(pc)
		var l2 := Label.new()
		l2.text = "x"
		pc.add_child(l2)
	variants["panel_container_x5"] = many
	var tr := TextureRect.new()
	tr.texture = MSTheme.disc_texture(32, Color.WHITE)
	variants["texturerect_x1"] = tr
	for k: String in variants:
		var n: Control = variants[k]
		n.visible = false
		layer.add_child(n)
	await cap.wait_frames(20)
	var base: int = await _draws()
	print("[BATCH] baseline=%d" % base)
	for k: String in variants:
		var n2: Control = variants[k]
		n2.visible = true
		var d: int = await _draws()
		n2.visible = false
		print("[BATCH] %s delta=%d" % [k, d - base])
