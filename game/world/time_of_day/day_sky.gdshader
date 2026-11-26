// Day and sunset sky: gradient from a hazy horizon to a deep zenith, a sun disk with a soft halo, a sunset
// band around the sun, and soft cumulus built from a few octaves of noise on a plane above the city.
// Static (no TIME): the radiance map used for ambient and reflections is drawn once. The night sky stays
// in world/materials/night_sky.gdshader, untouched.
shader_type sky;

uniform vec3 zenith_colour : source_color = vec3(0.09, 0.26, 0.58);
uniform vec3 horizon_colour : source_color = vec3(0.62, 0.78, 0.95);
uniform vec3 ground_colour : source_color = vec3(0.50, 0.58, 0.68);
// unit vector toward the sun (world space), set from the preset
uniform vec3 sun_dir = vec3(0.0, 0.7, 0.7);
uniform vec3 sun_colour : source_color = vec3(1.0, 0.95, 0.85);
uniform float sun_disk_cos = 0.99985;     // cos of the disk angular radius
uniform float sun_disk_energy = 8.0;
uniform float halo_power = 28.0;          // higher = tighter glow around the disk
uniform float halo_energy = 0.55;
// sunset band: warm light spread along the horizon on the sun's side
uniform vec3 band_colour : source_color = vec3(1.0, 0.45, 0.2);
uniform float band_energy = 0.0;
uniform float band_height = 0.22;
uniform float band_spread = 2.0;          // exponent on the sun-side falloff
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.45;
uniform vec3 cloud_lit : source_color = vec3(1.0, 0.99, 0.97);
uniform vec3 cloud_shade : source_color = vec3(0.62, 0.70, 0.82);
uniform float cloud_scale = 1.3;

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

float fbm(vec2 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 5; i++) {
		s += a * noise2(p);
		p = p * 2.03 + vec2(17.0, 9.0);
		a *= 0.5;
	}
	return s;
}

void sky() {
	vec3 sd = normalize(sun_dir);
	float up = EYEDIR.y;
	float cs = max(dot(EYEDIR, sd), 0.0);
	vec3 c;
	if (up < 0.0) {
		c = mix(horizon_colour * 0.9, ground_colour, smoothstep(0.0, 0.1, -up));
		c += band_colour * band_energy * 0.25 * pow(cs, band_spread);
	} else {
		float t = pow(clamp(up, 0.0, 1.0), 0.45);
		c = mix(horizon_colour, zenith_colour, t);
		// sunset band along the horizon, strongest toward the sun
		float side = pow(cs, band_spread);
		c += band_colour * band_energy * exp(-up / band_height) * (0.25 + 0.75 * side);
		c += sun_colour * halo_energy * pow(cs, halo_power);
		// clouds on a plane above the city; thin out toward the horizon
		vec2 uv = EYEDIR.xz / (up + 0.18) * cloud_scale;
		float d = fbm(uv);
		float cov = smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + 0.28, d);
		float fade = smoothstep(0.02, 0.2, up);
		// self shadow: density a step toward the sun darkens the cloud belly
		float d2 = fbm(uv + sd.xz * 0.25);
		float lit = clamp(0.55 + (d - d2) * 3.0, 0.0, 1.0);
		vec3 cc = mix(cloud_shade, cloud_lit, lit);
		cc += band_colour * band_energy * 0.5 * pow(cs, band_spread) * exp(-up * 2.5);
		cc += sun_colour * 0.5 * pow(cs, 6.0);
		c = mix(c, cc, cov * fade * 0.92);
		// sun disk (HDR so the glow pass blooms it), hidden behind thick cloud
		float disk = smoothstep(sun_disk_cos - 0.00018, sun_disk_cos + 0.00006, cs);
		c += sun_colour * sun_disk_energy * disk * (1.0 - cov * fade * 0.9);
	}
	COLOR = c;
}
