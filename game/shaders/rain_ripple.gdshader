shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add;

// Splash ripple: a flat ring on the road. rain.gd's particle scale curve grows the quad over the
// particle lifetime and the colour ramp (COLOR.a) fades it, so the ring expands and dies.
uniform vec4 ring_color : source_color = vec4(0.6, 0.75, 1.0, 0.6);
uniform float rain_alpha = 1.0;

void vertex() {
	VERTEX = vec3(VERTEX.x, 0.0, VERTEX.y);
}

void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	float ring = 1.0 - smoothstep(0.0, 0.06, abs(r - 0.75));
	// a faint second ring inside the first, like a real drop ripple
	ring += 0.4 * (1.0 - smoothstep(0.0, 0.05, abs(r - 0.45)));
	ALBEDO = ring_color.rgb;
	ALPHA = ring * ring_color.a * COLOR.a * rain_alpha;
}
