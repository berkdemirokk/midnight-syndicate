shader_type canvas_item;
// Full-screen radial speed streaks from the screen centre. Intensity 0..1 is set from GDScript (SpeedLines).
// Lines are thin (about 3 px), aspect-correct and live in the outer ring of the screen. Only some slots
// carry a streak, and each streak flows outward over time, so they read as motion, not as a grid.
// The centre (the car) and the speedometer zone at the bottom stay clear.
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float peak_alpha : hint_range(0.0, 1.0) = 0.35;
uniform float streak_count : hint_range(8.0, 256.0) = 120.0;
// Share of slots that carry a streak.
uniform float density : hint_range(0.0, 1.0) = 0.45;
uniform float inner_radius : hint_range(0.0, 1.5) = 0.8;
uniform float half_width_px : hint_range(0.5, 4.0) = 1.4;
// Outward flow speed in half-screen-heights per second at full intensity.
uniform float flow_speed : hint_range(0.0, 8.0) = 3.0;
uniform float streak_length : hint_range(0.05, 1.0) = 0.35;
// Speedometer zone (normalised screen UV rectangle: x0, y0, x1, y1) kept clear.
uniform vec4 hud_clear_rect = vec4(0.30, 0.62, 0.70, 1.0);
uniform vec4 line_color : source_color = vec4(0.8, 0.95, 1.0, 1.0);

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

void fragment() {
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	// Units of half the screen height, so circles stay round on wide screens.
	vec2 p = (UV * 2.0 - 1.0) * vec2(res.x / res.y, 1.0);
	float r = length(p);
	float turn = atan(p.y, p.x) / 6.2831853 + 0.5;
	float slot_f = turn * streak_count;
	float slot = floor(slot_f);
	float h = hash11(slot + 1.0);
	float present = step(h, density);
	float arc = r * 6.2831853 / streak_count;
	float dist = abs(fract(slot_f) - 0.5) * arc;
	float hw = half_width_px / (0.5 * res.y);
	float thin = 1.0 - smoothstep(hw * 0.5, hw, dist);
	// One dash per slot, flowing outward and wrapping; its phase differs per slot.
	float span = 1.6;
	float head = inner_radius + mod(TIME * flow_speed * (0.6 + 0.8 * h) + h * span, span);
	float dash = smoothstep(head - streak_length, head - streak_length * 0.4, r) * (1.0 - smoothstep(head - 0.02, head, r));
	float edge = smoothstep(inner_radius, inner_radius + 0.35, r);
	vec2 q = UV;
	float in_hud = step(hud_clear_rect.x, q.x) * step(q.x, hud_clear_rect.z) * step(hud_clear_rect.y, q.y) * step(q.y, hud_clear_rect.w);
	float on = thin * dash * edge * present * (1.0 - in_hud);
	COLOR = vec4(line_color.rgb, on * intensity * peak_alpha * line_color.a);
}
