shader_type spatial;
render_mode cull_disabled;
// Photo-textured row-house front: the albedo is a straight-on facade picture, the night picture of the same facade is
// its glow map (lit windows and shop fronts), scaled by `night`. Vertex alpha 1 = textured street face, 0.5 = roof,
// 0 = plain side wall, back wall, gable or eave in the vertex colour (same surface, one draw call a row). With
// textured_walls (Istanbul rows) walls and roofs take plaster and tile from their metre UVs, walls darker at the foot.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D night_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D wall_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D wall_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D roof_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool textured_walls = false;
uniform float relief = 0.0;  // 0 when no relief map is set
uniform float night = 0.0;
uniform vec3 tint = vec3(1.0);

varying float wall_height;

void vertex() {
	wall_height = VERTEX.y;
}

void fragment() {
	float face = step(0.75, COLOR.a);
	float roof = step(0.25, COLOR.a) - face;
	float wall = 1.0 - step(0.25, COLOR.a);
	vec3 photo = texture(albedo_tex, UV).rgb;
	vec3 plain = COLOR.rgb;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = relief * face;
	if (textured_walls && face < 0.5) {
		if (roof > 0.5) {
			plain = COLOR.rgb * texture(roof_tex, UV).rgb * 2.2;
			NORMAL_MAP = vec3(0.5, 0.5, 1.0);
		} else {
			float grime = mix(0.6, 1.0, smoothstep(0.0, 2.5, wall_height));  // grime and shade at the foot of a wall
			plain = COLOR.rgb * texture(wall_tex, UV).rgb * 2.2 * grime;
			NORMAL_MAP = texture(wall_nrm, UV).rgb;
			NORMAL_MAP_DEPTH = 0.8;
		}
	}
	ALBEDO = (face * photo + (1.0 - face) * plain) * tint;
	// dark glass and shop windows catch the sky at grazing angles; the lum band is linear, about sRGB 0.12 to 0.25
	float lum = dot(photo, vec3(0.2126, 0.7152, 0.0722));
	float glass = face * (1.0 - smoothstep(0.012, 0.05, lum)) * clamp(1.0 - night * 0.5, 0.0, 1.0);
	ROUGHNESS = mix(0.85, 0.3, glass);
	SPECULAR = mix(0.2, 0.5, glass);
	// the glow only on the street face (roofs never glow); plain walls get a faint warm lift after dark, or the steps between rows read as black holes
	EMISSION = texture(night_tex, UV).rgb * night * face + COLOR.rgb * vec3(1.0, 0.8, 0.6) * wall * night * 0.08;
}
