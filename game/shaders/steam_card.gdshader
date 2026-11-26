shader_type spatial;
// Street steam: a soft, slowly rising plume on a crossed pair of cards (kit_street, street_steam_vent).
// Unshaded alpha card, no texture: value noise scrolls up the card, the edges and the top fade out.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;

uniform vec3 tint : source_color = vec3(0.62, 0.68, 0.8);
uniform float density : hint_range(0.0, 1.0) = 0.42;
uniform float rise_speed = 0.35;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 uv = UV;
	float side = smoothstep(0.0, 0.4, uv.x) * smoothstep(1.0, 0.6, uv.x);
	float vert = smoothstep(0.0, 0.12, uv.y) * (1.0 - smoothstep(0.35, 1.0, uv.y));
	vec2 q = vec2(uv.x * 2.4 + sin(TIME * 0.5 + uv.y * 5.0) * 0.18, uv.y * 2.2 - TIME * rise_speed);
	float n = vnoise(q) * 0.6 + vnoise(q * 2.3 + 11.0) * 0.4;
	ALBEDO = tint;
	ALPHA = clamp(side * vert * n * density * 1.6, 0.0, 0.55);
}
