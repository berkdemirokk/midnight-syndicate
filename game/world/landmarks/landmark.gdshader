shader_type spatial;
// Landmark surfaces (waterfront mosque). Day: lit stone, dark glass. Night: the stone is washed warm from the
// ground up (a faked floodlight: brightest at the base, fading with height in metres) and windows and lamps glow.
// `night` is set by Landmarks.set_night; the light stays a plain albedo below the glow.

uniform vec4 base_color : source_color = vec4(0.88, 0.85, 0.79, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.5;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform vec4 glow_color : source_color = vec4(1.0, 0.72, 0.42, 1.0);
uniform float glow : hint_range(0.0, 20.0) = 0.0;
uniform float flood : hint_range(0.0, 4.0) = 0.0;
uniform float flood_height_m : hint_range(1.0, 40.0) = 16.0;
uniform float night : hint_range(0.0, 1.0) = 1.0;
// Photo-based stone, projected from three sides in model space (the kit has no UVs). tex_mix 0 = flat colour.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tex_mix : hint_range(0.0, 1.0) = 0.0;
uniform float tex_tile_m : hint_range(0.25, 16.0) = 2.4;
uniform float tex_gain : hint_range(0.5, 3.0) = 1.5;  // photo albedo is mid grey; base_color tints it
// Baked ambient occlusion in the vertex colour (white when absent).
uniform float ao_strength : hint_range(0.0, 1.0) = 0.9;
// Stone courses: a thin dark joint every course_m metres of height (0 = none), so big walls are not one flat sheet.
uniform float course_m : hint_range(0.0, 4.0) = 0.0;

varying float height_m;
varying vec3 m_pos;
varying vec3 m_nrm;

void vertex() {
	height_m = max(VERTEX.y, 0.0);
	m_pos = VERTEX;
	m_nrm = NORMAL;
}

void fragment() {
	float joint = 1.0;
	if (course_m > 0.0) {
		joint = 1.0 - 0.22 * smoothstep(0.9, 0.98, abs(fract(height_m / course_m) - 0.5) * 2.0);
	}
	vec3 tex = vec3(1.0);
	float rough_t = 1.0;
	if (tex_mix > 0.0) {
		vec3 w = pow(abs(normalize(m_nrm)), vec3(4.0));
		w /= (w.x + w.y + w.z);
		vec3 q = m_pos / tex_tile_m;
		vec3 tx = texture(albedo_tex, q.zy).rgb;
		vec3 ty = texture(albedo_tex, q.xz).rgb;
		vec3 tz = texture(albedo_tex, q.xy).rgb;
		tex = mix(vec3(1.0), (tx * w.x + ty * w.y + tz * w.z) * tex_gain, tex_mix);
		rough_t = mix(1.0, texture(rough_tex, q.zy).r * w.x + texture(rough_tex, q.xz).r * w.y + texture(rough_tex, q.xy).r * w.z, tex_mix);
	}
	vec3 ao = mix(vec3(1.0), COLOR.rgb, ao_strength);
	ALBEDO = base_color.rgb * tex * ao * joint;
	AO = ao.r;
	ROUGHNESS = clamp(roughness * mix(1.0, rough_t * 1.3, tex_mix), 0.05, 1.0);
	METALLIC = metallic;
	float fl = flood * exp(-height_m / flood_height_m);
	EMISSION = glow_color.rgb * (glow + fl * joint * ao.r * dot(tex, vec3(0.333))) * night;
}
