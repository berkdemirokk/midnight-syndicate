shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
// Dark glossy showroom floor. The planar mirror (PlanarReflection) is added as emission with a fresnel
// weight, blurred along the mirror image's vertical axis and faded with distance from the car so the
// floor melts into the backdrop. A faint cool pool under the car keeps the floor from reading flat.

uniform vec3 albedo_dark : source_color = vec3(0.012, 0.013, 0.018);
uniform vec3 pool_colour : source_color = vec3(0.10, 0.12, 0.2);
uniform float pool_radius = 4.5;
uniform float roughness_base = 0.2;
uniform sampler2D planar_reflection : source_color, filter_linear_mipmap, repeat_disable;
uniform float planar_enabled : hint_range(0.0, 1.0) = 0.0;
uniform mat4 planar_vp;
uniform float reflection_strength = 1.0;
uniform float reflection_floor = 0.22;  // reflectance at normal incidence, lifted above real 0.04 for a showroom gloss
uniform float light_specular = 0.3;
uniform float reflection_cap = 1.0;  // ceiling strips mirror at HDR 20: capped so they never read as solid white
uniform float reflection_smear = 0.006;
uniform float fade_start = 5.0;
uniform float fade_end = 22.0;
uniform vec3 fade_colour : source_color = vec3(0.02, 0.016, 0.04);
// Garage only: a generated concrete picture replaces the dark albedo, repeated every concrete_tile_m metres (no mirroring).
uniform sampler2D concrete_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float concrete_on = 0.0;
uniform float concrete_tile_m = 5.0;
uniform float concrete_gain = 0.3;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	float d = length(world_pos.xz);
	float pool = exp(-pow(d / pool_radius, 2.0));
	// Fine polished-concrete mottling: breaks the albedo flatness.
	float mott = hash(floor(world_pos.xz * 0.9));  // large, faint slab-to-slab variation
	vec3 base = albedo_dark * (0.9 + 0.2 * mott) + pool_colour * pool * 0.12;
	if (concrete_on > 0.5) {
		base = texture(concrete_tex, world_pos.xz / concrete_tile_m).rgb * concrete_gain * (0.9 + 0.2 * mott) + pool_colour * pool * 0.12;
	}
	float fade = smoothstep(fade_start, fade_end, d);
	ALBEDO = mix(base, fade_colour, fade);
	ROUGHNESS = roughness_base + 0.02 * mott;
	SPECULAR = light_specular;  // the mirror below carries the reflection; this only keeps light highlights
	METALLIC = 0.0;
	vec3 emit = pool_colour * pool * 0.05;
	if (planar_enabled > 0.5) {
		vec4 c = planar_vp * vec4(world_pos, 1.0);
		vec2 suv = c.xy / c.w * 0.5 + 0.5;
		suv.y = 1.0 - suv.y;
		float jit = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715)))) - 0.5;
		vec3 refl = vec3(0.0);
		float wsum = 0.0;
		for (int i = -3; i <= 3; i++) {
			float fi = float(i) + jit;
			float w = exp(-fi * fi * 0.2);
			refl += texture(planar_reflection, suv + vec2(0.0, fi * reflection_smear)).rgb * w;
			wsum += w;
		}
		refl /= wsum;
		float ndv = clamp(dot(normalize(VIEW), NORMAL), 0.0, 1.0);
		float fres = reflection_floor + (1.0 - reflection_floor) * pow(1.0 - ndv, 5.0);
		// Soft-clip so softboxes mirror as bright but never as solid white slabs.
		refl = refl / (1.0 + refl * 0.35);
		refl = min(refl, vec3(reflection_cap));
		emit += refl * fres * reflection_strength * (1.0 - fade);
	}
	EMISSION = emit;
}
