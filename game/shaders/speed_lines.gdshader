shader_type canvas_item;
// Full-screen radial speed streaks from the screen centre. Intensity 0..1 is set from GDScript.
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float streak_count : hint_range(8.0, 256.0) = 90.0;
uniform float inner_radius : hint_range(0.0, 1.0) = 0.25;
uniform vec4 line_color : source_color = vec4(0.8, 0.95, 1.0, 1.0);

float hash11(float p) {
	return fract(sin(p * 91.345) * 47453.5453);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float turn = atan(p.y, p.x) / 6.2831853 + 0.5;
	float slot = floor(turn * streak_count);
	// Thin radial line: near the centre of its angular slot.
	float thin = smoothstep(0.08, 0.0, abs(fract(turn * streak_count) - 0.5));
	// Each streak starts at its own radius and runs out to the edge.
	float start = mix(inner_radius, 1.0, hash11(slot));
	float on = thin * smoothstep(start, start + 0.15, r);
	COLOR = vec4(line_color.rgb, on * intensity * line_color.a);
}
