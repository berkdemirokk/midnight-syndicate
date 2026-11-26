shader_type spatial;
// Race flag on a pole (event_dressing): a vertex wave along the cloth normal. UV.x is 0 at the pole and 1 at the
// fly, so the cloth is pinned at the hoist and the wave grows towards the fly. The phase comes from the world
// position, so flags on one line do not move in step. Alpha-free: the flag is opaque and never torn.
render_mode cull_disabled, specular_schlick_ggx;

uniform sampler2D flag_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform float amplitude_m : hint_range(0.0, 0.3) = 0.10;
uniform float waves : hint_range(1.0, 12.0) = 5.0;
uniform float speed : hint_range(0.0, 12.0) = 4.5;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.7;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float pin = UV.x * UV.x;  // 0 at the pole, full amplitude at the fly
	float phase = world.x * 0.7 + world.z * 0.9;
	float wave = sin(UV.x * waves - TIME * speed + phase) * amplitude_m * pin;
	float ripple = sin(UV.y * 9.0 + TIME * speed * 1.7 + phase) * amplitude_m * 0.25 * pin;
	VERTEX.z += wave;
	VERTEX.y += ripple;
}

void fragment() {
	vec4 c = texture(flag_tex, UV);
	ALBEDO = c.rgb;
	ROUGHNESS = roughness_value;
	METALLIC = 0.0;
}
