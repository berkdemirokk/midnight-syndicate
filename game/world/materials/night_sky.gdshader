// Night sky over Arden Bay: near-black zenith, a city light-pollution glow along the horizon, a faint band of
// low broken cloud lit from below, and a full moon with a soft halo. Static (no per-frame input), so the radiance map is drawn once.
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
// moon: world direction towards the moon (y up), angular radius in radians, brightness, cloud cover 0..1
uniform vec3 moon_dir = vec3(0.95, 0.27, -0.14);
uniform float moon_size : hint_range(0.005, 0.2) = 0.035;
uniform float moon_energy : hint_range(0.0, 8.0) = 2.5;
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.45;
uniform vec3 moon_colour : source_color = vec3(0.86, 0.91, 1.0);

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
		// broken cloud deck: stretched noise on a plane above the city; cover moves the threshold
		vec2 uv = EYEDIR.xz / max(up + 0.12, 0.02) * 1.6;
		float n = noise2(uv) * 0.6 + noise2(uv * 2.7 + 7.0) * 0.4;
		float thr = mix(0.72, 0.42, cloud_cover);
		float cloud = smoothstep(thr, thr + 0.22, n) * smoothstep(0.02, 0.12, up) * (1.0 - smoothstep(0.35, 0.8, up));
		c += glow_colour * glow_energy * cloud * cloud_strength * (0.4 + glow);
		// moon: disc, soft halo, and clouds lit silver-blue on the side that faces it
		vec3 md = normalize(moon_dir);
		float toward = max(dot(EYEDIR, md), 0.0);
		float edge = cos(moon_size);
		float disc = smoothstep(edge, edge + (1.0 - edge) * 0.35, dot(EYEDIR, md));
		float halo = pow(toward, 48.0) * 0.55 + pow(toward, 14.0) * 0.08;
		c += moon_colour * 0.05 * cloud * (0.3 + pow(toward, 3.0)) * moon_energy;
		disc *= 1.0 - cloud * 0.85;  // a cloud in front of the moon dims its disc
		c += moon_colour * (disc * moon_energy + halo * moon_energy * 0.6) * smoothstep(0.0, 0.1, up);
		COLOR = c;
	}
}
