extends SceneTree

func _init() -> void:
	var spec: Resource = load("res://vehicles/specs/noctra_sable.tres")
	print("PROBE spec_class=", spec.get_class(), " is_carspec=", spec is CarSpec)
	var s: CarSpec = spec as CarSpec
	if s == null:
		print("PROBE spec cast FAILED")
	else:
		var c: Curve = s.engine_force_curve
		print("PROBE curve_null=", c == null)
		if c != null:
			print("PROBE point_count=", c.point_count, " s0=", c.sample(0.0), " s0.2=", c.sample(0.2), " s0.5=", c.sample(0.5), " s1=", c.sample(1.0))
		print("PROBE top=", s.top_speed_kmh, " nitro_cap=", s.nitro_capacity_s, " anti_roll=", s.anti_roll)
	quit(0)
