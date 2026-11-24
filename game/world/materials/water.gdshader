shader_type spatial;
// Bay water for the city: near-black, very low roughness, two slow normal layers scrolling in
// opposite directions. World-space UV so the ripple size is the same on every water piece.

render_mode depth_draw_opaque, cull_back, specular_schlick_ggx;

uniform vec4 water_color : source_color = vec4(0.04, 0.078, 0.11, 1.0);
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.05;
uniform float tile_m : hint_range(0.5, 40.0) = 6.0;
uniform vec2 scroll = vec2(0.012, 0.007);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world_pos.xz / tile_m;
	vec3 n1 = texture(normal_tex, uv + scroll * TIME).rgb * 2.0 - 1.0;
	vec3 n2 = texture(normal_tex, uv * 0.6 - scroll * TIME * 0.7).rgb * 2.0 - 1.0;
	vec3 n = normalize(vec3(n1.xy + n2.xy, 1.0));
	NORMAL_MAP = n * 0.5 + 0.5;
	ALBEDO = water_color.rgb;
	ROUGHNESS = roughness_value;
	SPECULAR = 0.6;
	METALLIC = 0.0;
}
