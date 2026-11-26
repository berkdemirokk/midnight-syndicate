shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
// Soft dark blob under each tree instead of a real-time shadow. Quad lies flat, UV centred on the trunk.

uniform float strength : hint_range(0.0, 1.0) = 0.78;
uniform vec3 colour : source_color = vec3(0.02, 0.03, 0.02);

void fragment() {
	float d = length(UV * 2.0 - 1.0);
	ALBEDO = colour;
	ALPHA = (1.0 - smoothstep(0.2, 1.0, d)) * strength;
}
