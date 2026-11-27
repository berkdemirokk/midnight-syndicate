shader_type spatial;
render_mode cull_disabled;
// Photo-textured row-house front: the albedo is a straight-on facade picture, the night picture of the same facade is
// its glow map (lit windows and shop fronts), scaled by `night`. Vertex alpha 1 = textured street face, alpha 0 = plain
// side wall or roof in the vertex colour (same surface, one draw call a row).
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D night_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float relief = 0.0;  // 0 when no relief map is set
uniform float night = 0.0;
uniform vec3 tint = vec3(1.0);

void fragment() {
	ALBEDO = mix(COLOR.rgb, texture(albedo_tex, UV).rgb, COLOR.a) * tint;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = relief * COLOR.a;
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
	// plain side walls get a faint warm lift after dark, or the steps between rows read as black holes
	EMISSION = texture(night_tex, UV).rgb * night * COLOR.a + COLOR.rgb * vec3(1.0, 0.8, 0.6) * (1.0 - COLOR.a) * night * 0.08;
}
