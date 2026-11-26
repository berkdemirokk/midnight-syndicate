shader_type spatial;
// Spectator cards behind the race barriers (event_dressing). A MultiMesh instance picks one of the 16 figures of
// crowd_atlas.png (4 x 4 cells) and carries a hue shift and a bob phase in its custom data:
//   INSTANCE_CUSTOM.x = cell index 0..15, .y = hue shift in turns (-0.5..0.5), .z = bob phase 0..1.
// Unshaded with a dim tone: the street lamps do not light a card well at this distance, and a plain tone reads
// better at night than a lit card with no normal.
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform sampler2D crowd_atlas : source_color, filter_nearest_mipmap, repeat_disable;
uniform vec3 tone : source_color = vec3(0.62, 0.58, 0.52);
uniform float bob_m : hint_range(0.0, 0.05) = 0.012;
uniform float bob_speed : hint_range(0.0, 4.0) = 1.4;
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.5;

varying float v_cell;
varying float v_hue;

vec3 hue_rotate(vec3 c, float turns) {
	float a = turns * 6.2831853;
	float cs = cos(a);
	float sn = sin(a);
	mat3 m = mat3(
		vec3(0.299 + 0.701 * cs + 0.168 * sn, 0.587 - 0.587 * cs + 0.330 * sn, 0.114 - 0.114 * cs - 0.497 * sn),
		vec3(0.299 - 0.299 * cs - 0.328 * sn, 0.587 + 0.413 * cs + 0.035 * sn, 0.114 - 0.114 * cs + 0.292 * sn),
		vec3(0.299 - 0.300 * cs + 1.250 * sn, 0.587 - 0.588 * cs - 1.050 * sn, 0.114 + 0.886 * cs - 0.203 * sn));
	return clamp(m * c, 0.0, 1.0);
}

void vertex() {
	v_cell = INSTANCE_CUSTOM.x;
	v_hue = INSTANCE_CUSTOM.y;
	VERTEX.y += sin(TIME * bob_speed + INSTANCE_CUSTOM.z * 6.2831853) * bob_m;  // sub-centimetre, reads as breathing
}

void fragment() {
	vec2 cell = vec2(mod(v_cell, 4.0), floor(v_cell / 4.0));
	vec4 c = texture(crowd_atlas, (cell + vec2(UV.x, UV.y)) * 0.25);
	if (c.a < alpha_cut) {
		discard;
	}
	ALBEDO = hue_rotate(c.rgb, v_hue) * tone;
}
