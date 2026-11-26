shader_type spatial;
// Bay / Bosphorus sea, Mobile renderer, no screen-space effects (no SSR, no depth texture).
// Two scrolling slope maps (tools/gen_water_textures.py): a broad swell and a fine chop, sampled in world XZ so the
// ripple scale is the same on every water piece. The world normal is built here and converted to view space, so no
// tangent frame is needed. Sky reflection, the sun glint and the city-light glints come from the engine's own
// specular lighting on the low-roughness normal: the sky shows in the Fresnel reflection of the day and sunset
// environment, the sun makes a glitter path where the chop faces it, and at night the street lamps and neon
// make the streaks. The sea is darker looking straight down and lighter toward the horizon (Fresnel on the albedo).
// Vertex swell is not used: the water mesh is a flat triangulation of about 1000 to 1400 vertices, too coarse to
// carry a swell without visible faceting.

render_mode depth_draw_opaque, cull_back, specular_schlick_ggx;

// Albedo: looking down (deep) to grazing (shallow). Kept dark, the sea is mostly reflection.
uniform vec4 deep_colour : source_color = vec4(0.016, 0.032, 0.040, 1.0);
uniform vec4 shallow_colour : source_color = vec4(0.085, 0.130, 0.140, 1.0);
// Sky fill for the Fresnel reflection. Set by the time of day (TimeOfDay.sky_params: zenith_colour, horizon_colour);
// 0 keeps the environment reflection alone.
uniform vec4 zenith_colour : source_color = vec4(0.14, 0.44, 1.0, 1.0);
uniform vec4 horizon_colour : source_color = vec4(0.62, 0.80, 1.0, 1.0);
uniform float sky_fill : hint_range(0.0, 1.0) = 0.0;

uniform sampler2D swell_tex : filter_linear_mipmap, repeat_enable, hint_default_black;
uniform sampler2D chop_tex : filter_linear_mipmap, repeat_enable, hint_default_black;
uniform float swell_tile_m : hint_range(2.0, 80.0) = 16.0;
uniform float chop_tile_m : hint_range(0.5, 20.0) = 4.0;
uniform vec2 swell_scroll = vec2(0.010, 0.004);  // UV per second, wind-driven direction
uniform vec2 chop_scroll = vec2(-0.030, 0.018);
uniform float swell_strength : hint_range(0.0, 2.0) = 0.22;
uniform float chop_strength : hint_range(0.0, 2.0) = 0.10;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.04;
uniform float far_roughness : hint_range(0.0, 1.0) = 0.30;  // distant sea: sky sheen, no sparkle noise
uniform float specular_value : hint_range(0.0, 1.0) = 0.55;
// Fresnel shaping: higher power keeps the horizon band narrow.
uniform float fresnel_power : hint_range(1.0, 8.0) = 4.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec2 decode_slope(vec4 t) {
	return t.rg * 2.0 - 1.0;
}

void fragment() {
	vec2 p = world_pos.xz;
	vec2 slope_swell = decode_slope(texture(swell_tex, p / swell_tile_m + swell_scroll * TIME)) * swell_strength;
	vec2 slope_chop = decode_slope(texture(chop_tex, p / chop_tile_m + chop_scroll * TIME)) * chop_strength;
	// Distance LOD: the fine chop fades out and the far sea gets rougher, so the distance does not shimmer or sparkle
	// into noise (mip filtering alone leaves moire on the grazing sea).
	float dist = length(VERTEX);
	float near = 1.0 - smoothstep(10.0, 70.0, dist);
	vec2 slope = slope_swell + slope_chop * near;
	vec3 n_world = normalize(vec3(-slope.x, 1.0, -slope.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);

	// VIEW is the direction from the surface to the eye (view space), so NdotV is 1 looking straight down.
	float ndotv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = pow(1.0 - ndotv, fresnel_power);

	ALBEDO = mix(deep_colour.rgb, shallow_colour.rgb, fres);
	ROUGHNESS = mix(roughness_value, far_roughness, smoothstep(30.0, 300.0, dist));
	SPECULAR = specular_value;
	METALLIC = 0.0;
	EMISSION = mix(zenith_colour.rgb, horizon_colour.rgb, fres) * fres * sky_fill;
}
