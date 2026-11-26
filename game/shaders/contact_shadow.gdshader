shader_type spatial;
// Soft contact shadow: black, alpha only, no depth write, so it darkens the road under a car and nothing else.
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled, specular_disabled;

uniform float strength : hint_range(0.0, 1.0) = 0.6;  // set per time of day by ContactShadow
uniform vec2 quad_half = vec2(1.25, 2.7);  // metres, half of the PlaneMesh size
uniform vec2 body_half = vec2(0.92, 2.25);  // metres, the car footprint
uniform vec2 wheel_xz = vec2(0.8, 1.4);  // metres, wheel centres from the car centre
uniform float wheel_r = 0.36;
instance uniform float lift_fade : hint_range(0.0, 1.0) = 1.0;  // 0 when the car is airborne

float rounded_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + vec2(r);
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0 * quad_half;
	float d = rounded_box(p, body_half, 0.35);
	float body = 1.0 - smoothstep(-0.15, 0.45, d);
	float core = 1.0 - smoothstep(-0.7, 0.1, d);
	float wheel = 1.0 - smoothstep(wheel_r * 0.6, wheel_r * 1.5, length(abs(p) - wheel_xz));
	float a = clamp(max(body * 0.4 + core * 0.25, wheel), 0.0, 1.0);
	ALBEDO = vec3(0.0);
	ALPHA = a * strength * lift_fade;
}
