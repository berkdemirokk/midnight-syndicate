shader_type spatial;
render_mode cull_disabled;
// Photo-textured row-house front: the albedo is a straight-on facade picture, the night picture of the same facade is
// its glow map (lit windows and shop fronts), scaled by `night`.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D night_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float night = 0.0;
uniform vec3 tint = vec3(1.0);

void fragment() {
	ALBEDO = texture(albedo_tex, UV).rgb * tint;
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
	EMISSION = texture(night_tex, UV).rgb * night;
}
