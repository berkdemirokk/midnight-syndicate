shader_type canvas_item;
// Full-screen radial speed streaks from the screen centre. Intensity 0..1 is set from GDScript (SpeedLines).
// Lines are thin (about 3 px), aspect-correct, start at their own radius and sit at the screen edges.
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float peak_alpha : hint_range(0.0, 1.0) = 0.35;
uniform float streak_count : hint_range(8.0, 256.0) = 90.0;
uniform float inner_radius : hint_range(0.0, 1.0) = 0.45;
uniform float half_width_px : hint_range(0.5, 4.0) = 1.6;
uniform vec4 line_color : source_color = vec4(0.8, 0.95, 1.0, 1.0);

float hash11(float p) {
	return fract(sin(p * 91.345) * 47453.5453);
}

void fragment() {
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	// Units of half the screen height, so circles stay round on wide screens.
	vec2 p = (UV * 2.0 - 1.0) * vec2(res.x / res.y, 1.0);
	float r = length(p);
	float turn = atan(p.y, p.x) / 6.2831853 + 0.5;
	float slot_f = turn * streak_count;
	float slot = floor(slot_f);
	// Distance from the streak's centre line, measured along the arc at this radius.
	float arc = r * 6.2831853 / streak_count;
	float dist = abs(fract(slot_f) - 0.5) * arc;
	float hw = half_width_px / (0.5 * res.y);
	float thin = 1.0 - smoothstep(hw * 0.5, hw, dist);
	// Each streak starts at its own radius and runs out to the edge.
	float start = mix(inner_radius, 1.2, hash11(slot));
	float along = smoothstep(start, start + 0.25, r);
	// Concentrated at the screen edges, nothing over the centre.
	float edge = smoothstep(0.5, 1.1, r);
	float on = thin * along * edge;
	COLOR = vec4(line_color.rgb, on * intensity * peak_alpha * line_color.a);
}
