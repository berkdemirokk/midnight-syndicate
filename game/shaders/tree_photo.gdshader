shader_type spatial;
render_mode cull_disabled, specular_disabled, diffuse_lambert;
// Photo tree cards (game/world/greenery, photo species). Crossed alpha-scissor cards: the albedo is a straight-on
// photo of the tree (alpha = leaves and trunk), the night picture of the same tree is the glow map. INSTANCE_CUSTOM.r
// picks the left or right half of a two-tree atlas (planes). By day the crown is the photo; at night it blends to the
// night picture, driven by the same value Greenery.set_shade_fill receives (0.5 day, 0.2 dusk, 0 night).

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D night_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.35;  // low: thin far crowns keep their leaves through mip averaging
uniform float atlas_halves = 1.0;  // 2.0 when the texture holds two trees side by side
uniform vec3 tint : source_color = vec3(1.0);
uniform float night_dim : hint_range(0.0, 1.0) = 0.3;  // albedo left at night (0 = black, 1 = unchanged)
uniform float night_glow : hint_range(0.0, 4.0) = 1.5;
uniform float shade_fill : hint_range(0.0, 1.0) = 0.0;  // sky light in the crown by day, 0 at night
uniform float translucency : hint_range(0.0, 2.0) = 0.6;
uniform vec3 translucent_colour : source_color = vec3(0.75, 0.95, 0.4);
uniform float sway_amp_m : hint_range(0.0, 0.5) = 0.1;
uniform float sway_speed : hint_range(0.0, 4.0) = 1.1;
uniform float sway_height_m : hint_range(1.0, 20.0) = 10.0;

void vertex() {
	// Sway from TIME and world position, grows with height above the ground (as foliage.gdshader).
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float phase = TIME * sway_speed + world_pos.x * 0.37 + world_pos.z * 0.29;
	float gust = sin(phase) * 0.65 + sin(phase * 2.3 + 1.7) * 0.35;
	float height_k = clamp(VERTEX.y / sway_height_m, 0.0, 1.0);
	float push = gust * sway_amp_m * height_k;
	VERTEX.x += push;
	VERTEX.z += push * 0.6;
	// Atlas: the card covers one tree; INSTANCE_CUSTOM.r moves it to the right half when the atlas holds two.
	UV = vec2(UV.x / atlas_halves + INSTANCE_CUSTOM.r, UV.y);
}

void fragment() {
	vec4 t = texture(albedo_tex, UV);
	if (t.a < alpha_cut) {
		discard;
	}
	float night = 1.0 - clamp(shade_fill * 2.0, 0.0, 1.0);
	vec3 glow = texture(night_tex, UV).rgb * night * night_glow;
	ALBEDO = t.rgb * tint * mix(1.0, night_dim, night);
	EMISSION = ALBEDO * shade_fill + glow;
	ROUGHNESS = 0.8;
}

void light() {
	// Same lighting as foliage.gdshader: wrap lambert plus backlit translucency, leaves let about half the sun through.
	float wrap = clamp(dot(NORMAL, LIGHT) * 0.5 + 0.5, 0.0, 1.0);
	float back = pow(clamp(dot(-VIEW, LIGHT), 0.0, 1.0), 3.0) * translucency;
	float att = LIGHT_IS_DIRECTIONAL ? mix(0.5, 1.0, ATTENUATION) : ATTENUATION;
	vec3 lit = ALBEDO * LIGHT_COLOR * att * (wrap * 0.85 + 0.15);
	vec3 thru = ALBEDO * translucent_colour * LIGHT_COLOR * att * back;
	DIFFUSE_LIGHT += lit + thru;
}
