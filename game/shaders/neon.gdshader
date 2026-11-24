shader_type spatial;
// Unshaded emissive sign or strip. Output is HDR (energy > 1 feeds the glow). No lights needed.
render_mode unshaded, blend_mix, cull_disabled;

uniform vec4 base_color : source_color = vec4(0.0, 1.0, 1.0, 1.0);
// HDR multiplier; the Mobile glow pass turns values above 1 into bloom.
uniform float energy : hint_range(0.0, 16.0) = 4.0;
// Per-instance phase and amount set through MeshInstance3D.set_instance_shader_parameter.
instance uniform float flicker_phase : hint_range(0.0, 100.0) = 0.0;
uniform float flicker_amount : hint_range(0.0, 1.0) = 0.0;
uniform float flicker_speed : hint_range(0.0, 30.0) = 7.0;
// Scrolls the UV along x, for arrow signs. Zero for static signs.
uniform vec2 scroll_speed = vec2(0.0, 0.0);
uniform sampler2D mask_tex : filter_linear_mipmap, repeat_enable;
uniform bool use_mask = false;

void fragment() {
	vec2 uv = UV + scroll_speed * TIME;
	float flick = 1.0;
	if (flicker_amount > 0.0) {
		float s = sin(TIME * flicker_speed + flicker_phase * 12.9898);
		// Mostly steady; a short dip now and then.
		float dip = step(0.92, fract(sin(floor(TIME * 9.0 + flicker_phase) * 43.7) * 999.0));
		flick = 1.0 - flicker_amount * (0.1 * (0.5 + 0.5 * s) + 0.9 * dip);
	}
	float m = 1.0;
	if (use_mask) {
		m = texture(mask_tex, uv).r;
	}
	ALBEDO = base_color.rgb * energy * flick * m;
	ALPHA = base_color.a * m;
}
