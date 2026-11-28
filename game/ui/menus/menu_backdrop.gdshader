shader_type canvas_item;
// STREET EMPIRE studio backdrop for menus without a 3D scene: a graphite cyclorama lit by one soft overhead key,
// a faint racing-red floor bounce on the right, a horizon line where wall meets floor, fine grain and a vignette.
// No neon, no skyline, no textures. One full-screen quad; cost is a handful of ALU per pixel.

uniform float aspect = 1.78;
uniform float horizon = 0.64;    // wall/floor seam, 0 = top
uniform float dim_left = 0.55;   // darkens the left side where a menu column sits
uniform float intensity = 1.0;

const vec3 GRAPHITE = vec3(0.063, 0.071, 0.086);
const vec3 DEEP = vec3(0.027, 0.031, 0.039);
const vec3 TITANIUM = vec3(0.769, 0.784, 0.808);
const vec3 RED = vec3(0.941, 0.267, 0.196);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	vec2 p = vec2(uv.x * aspect, uv.y);
	float t = TIME;

	// Wall: dark at the top, lifting toward the seam. Floor: lit pool under the key, falling off to the front.
	float wall = smoothstep(0.0, horizon, uv.y);
	vec3 col = mix(DEEP, GRAPHITE * 1.25, wall * wall);
	float key_x = aspect * (0.66 + 0.015 * sin(t * 0.07));
	float d_key = length((p - vec2(key_x, horizon - 0.10)) * vec2(0.55, 1.4));
	col += TITANIUM * 0.10 * exp(-d_key * d_key * 3.2);
	if (uv.y > horizon) {
		float fy = (uv.y - horizon) / (1.0 - horizon);
		float pool = exp(-pow((p.x - key_x) * 0.9, 2.0) * 2.2) * exp(-fy * 2.4);
		col = mix(GRAPHITE * 1.05, DEEP, fy * 0.7);
		col += TITANIUM * 0.085 * pool;
		// soft red bounce from off-screen tail lights, right edge, low on the floor
		col += RED * 0.07 * smoothstep(0.35, 1.0, uv.x) * smoothstep(0.2, 1.0, fy) * (0.85 + 0.15 * sin(t * 0.4));
	}
	// Cove seam: a soft highlight line, not a hard edge.
	col += TITANIUM * 0.05 * exp(-pow((uv.y - horizon) * 90.0, 2.0)) * smoothstep(0.0, 0.5, uv.x);

	// Left dim for a menu column, vignette, grain.
	col *= 1.0 - dim_left * 0.65 * (1.0 - smoothstep(0.0, 0.62, uv.x));
	vec2 v = uv - vec2(0.55, 0.45);
	col *= 1.0 - 0.55 * dot(v * vec2(1.1, 1.4), v * vec2(1.1, 1.4));
	col += (hash(floor(FRAGCOORD.xy) + fract(t) * 37.0) - 0.5) * 0.012;
	COLOR = vec4(max(col * intensity, vec3(0.0)), 1.0);
}
