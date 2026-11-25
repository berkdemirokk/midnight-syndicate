// Night sky over Arden Bay: near-black zenith, a city light-pollution glow along the horizon and a
// faint band of low cloud lit from below. Static (no TIME), so the radiance map is drawn once.
shader_type sky;

uniform vec3 zenith_colour : source_color = vec3(0.02, 0.035, 0.085);
uniform vec3 mid_colour : source_color = vec3(0.05, 0.085, 0.19);
uniform vec3 glow_colour : source_color = vec3(0.20, 0.09, 0.25);
// how far up the horizon glow reaches (0 = horizon, 1 = zenith)
uniform float glow_height : hint_range(0.01, 1.0) = 0.12;
uniform float glow_energy = 1.0;
uniform float cloud_strength : hint_range(0.0, 1.0) = 0.25;
// below the horizon (over the bay, behind the skyline cards)
uniform vec3 below_colour : source_color = vec3(0.03, 0.04, 0.08);

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x),
			mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}

void sky() {
	float up = EYEDIR.y;
	if (up < 0.0) {
		COLOR = mix(glow_colour * glow_energy * 0.5, below_colour, smoothstep(0.0, 0.08, -up));
	} else {
		vec3 c = mix(mid_colour, zenith_colour, smoothstep(0.05, 0.75, up));
		float glow = exp(-up / glow_height);
		c += glow_colour * glow_energy * glow;
		// low cloud deck: stretched noise on a plane above the city, lit by the glow
		vec2 uv = EYEDIR.xz / max(up + 0.12, 0.02) * 1.6;
		float n = noise2(uv) * 0.6 + noise2(uv * 2.7 + 7.0) * 0.4;
		float cloud = smoothstep(0.45, 0.85, n) * smoothstep(0.02, 0.12, up) * (1.0 - smoothstep(0.35, 0.8, up));
		c += glow_colour * glow_energy * cloud * cloud_strength * (0.4 + glow);
		COLOR = c;
	}
}
