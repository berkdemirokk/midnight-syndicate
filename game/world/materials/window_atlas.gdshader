shader_type spatial;
// Window and shop-interior atlas. The emissive atlas is bright across the whole facade (dark
// windows still carry a grey value), so only the part above glow_threshold emits: lit windows
// bloom, unlit windows and wall stay dark. Output is HDR (EMISSION above 1 feeds the glow).

render_mode depth_draw_opaque, cull_back, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D emissive_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float roughness_value : hint_range(0.0, 1.0) = 0.6;
uniform float glow_energy : hint_range(0.0, 16.0) = 3.0;
uniform float glow_threshold : hint_range(0.0, 0.99) = 0.5;
// 0 = grey glow, 1 = raw atlas colour. The raw atlas blues and reds are too saturated to read as lamps.
uniform float glow_saturation : hint_range(0.0, 1.0) = 0.5;

void fragment() {
	ALBEDO = texture(albedo_tex, UV).rgb * tint.rgb;
	ROUGHNESS = roughness_value;
	METALLIC = 0.0;
	vec3 e = texture(emissive_tex, UV).rgb;
	vec3 lit = max(e - vec3(glow_threshold), vec3(0.0)) / (1.0 - glow_threshold);
	float lum = dot(lit, vec3(0.3, 0.59, 0.11));
	EMISSION = mix(vec3(lum), lit, glow_saturation) * glow_energy;
}
