shader_type spatial;
render_mode cull_disabled, specular_disabled, diffuse_lambert;
// Leaf cards for the tree kit (game/world/greenery). Alpha scissor, two-sided, wrap/backlit translucency,
// wind sway from TIME and world position. Vertex colour RGB is baked ambient occlusion (dark inside and underneath).

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.5;
uniform vec3 tint : source_color = vec3(1.0);
uniform float translucency : hint_range(0.0, 2.0) = 0.7;
uniform vec3 translucent_colour : source_color = vec3(0.75, 0.95, 0.4);
uniform float sway_amp_m : hint_range(0.0, 0.5) = 0.12;  // leaf displacement at sway_height_m
uniform float sway_speed : hint_range(0.0, 4.0) = 1.1;
uniform float sway_height_m : hint_range(1.0, 20.0) = 9.0;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.75;
// Sky light scattered inside the crown: without it a tree in a building's shadow is a black scribble by day. 0 at night.
uniform float shade_fill : hint_range(0.0, 1.0) = 0.0;

varying float v_sway_weight;

void vertex() {
	// Sway grows with height above the ground (VERTEX.y, Godot up). Phase depends on world position so
	// neighbouring trees do not move in step; the sway is a sum of two sines, a cheap gust.
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float phase = TIME * sway_speed + world_pos.x * 0.37 + world_pos.z * 0.29;
	float gust = sin(phase) * 0.65 + sin(phase * 2.3 + 1.7) * 0.35;
	float height_k = clamp(VERTEX.y / sway_height_m, 0.0, 1.0);
	float push = gust * sway_amp_m * height_k;
	VERTEX.x += push;
	VERTEX.z += push * 0.6;
	v_sway_weight = height_k;
}

void fragment() {
	vec4 t = texture(albedo_tex, UV);
	if (t.a < alpha_cut) {
		discard;
	}
	ALBEDO = t.rgb * COLOR.rgb * tint;
	ROUGHNESS = roughness_value;
	EMISSION = ALBEDO * shade_fill;
}

void light() {
	// Lambert with a wrap term so leaves are not black on the shaded side, plus backlit translucency:
	// when the sun is behind the crown the light comes through the leaves.
	float wrap = clamp(dot(NORMAL, LIGHT) * 0.5 + 0.5, 0.0, 1.0);
	float back = pow(clamp(dot(-VIEW, LIGHT), 0.0, 1.0), 3.0) * translucency;
	// A crown shadows itself almost everywhere: leaves let about half the sun through, or the tree reads as a black scribble.
	float att = LIGHT_IS_DIRECTIONAL ? mix(0.5, 1.0, ATTENUATION) : ATTENUATION;
	vec3 lit = ALBEDO * LIGHT_COLOR * att * (wrap * 0.85 + 0.15);
	vec3 thru = ALBEDO * translucent_colour * LIGHT_COLOR * att * back;
	DIFFUSE_LIGHT += lit + thru;
}
