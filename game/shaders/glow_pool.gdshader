shader_type spatial;
// Warm light pool under a lane lamp, or its wash on the wall (kit_street: street_glow_pool, street_glow_wall):
// additive radial falloff, unshaded, no lights needed (the lane lamps cost no light budget).
// Mesh space: the pool lies in XZ (radius 3.2 m), the wall wash in XY (radius 2.6 m, vertical = true).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;

uniform vec3 tint : source_color = vec3(1.0, 0.62, 0.3);
uniform float strength = 0.8;
uniform float radius_m = 3.2;
uniform bool vertical = false;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec2 p = vertical ? local_pos.xy : local_pos.xz;
	float r = clamp(length(p) / radius_m, 0.0, 1.0);
	float a = pow(1.0 - r, 2.0);
	ALBEDO = tint * strength * a;
	ALPHA = 1.0;
}
