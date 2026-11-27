shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;
// Day-only fake ground occlusion: a dark gradient laid on the ground at the foot of a wall or along a kerb.
// UV.x is 0 at the wall (or kerb) and 1 at the outer edge of the strip, so the shade is darkest where wall meets ground.
uniform vec4 shade_colour : source_color = vec4(0.05, 0.055, 0.075, 1.0);
uniform float strength : hint_range(0.0, 1.0) = 0.45;
uniform float falloff = 2.0;

void fragment() {
	ALBEDO = shade_colour.rgb;
	ALPHA = shade_colour.a * strength * pow(1.0 - UV.x, falloff);
}
