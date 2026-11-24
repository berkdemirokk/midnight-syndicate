shader_type spatial;
// Underpass ceiling fixture. Unshaded HDR strip, broken into separate fixtures by a world-space dash:
// lit for lit_m metres, dark for the rest of period_m. World space, so every strip shares one material.
// shortcut: one fixed run direction for the whole tunnel, fine while the underpass is straight, upgrade per strip if it bends.
render_mode unshaded, blend_mix, cull_disabled;

uniform vec4 base_color : source_color = vec4(0.75, 0.85, 1.0, 1.0);
uniform float energy : hint_range(0.0, 16.0) = 3.0;
uniform vec3 run_dir = vec3(-0.985, 0.0, 0.17);
uniform float lit_m : hint_range(0.1, 10.0) = 1.2;
uniform float period_m : hint_range(0.2, 20.0) = 1.8;

varying float along;

void vertex() {
	along = dot((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz, normalize(run_dir));
}

void fragment() {
	float phase = mod(along, period_m);
	float on = 1.0 - smoothstep(lit_m - 0.08, lit_m, phase);
	ALBEDO = base_color.rgb * energy * on;
	ALPHA = base_color.a;
}
