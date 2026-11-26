shader_type spatial;
// Tyre spray droplet: a lit, camera-facing ribbon along streak_dir (world space, set per frame by WheelSpray),
// the same construction as rain_streak.gdshader. The particle transform gives the origin and the scale;
// streak_len grows with speed. Lit, not unshaded, so street lights and the car fill light shade it,
// with a low alpha that fades out near the lens and far away.
render_mode cull_disabled, depth_draw_never, specular_disabled, shadows_disabled;

uniform vec4 spray_color : source_color = vec4(0.7, 0.74, 0.8, 0.5);
uniform vec3 streak_dir = vec3(0.0, 0.5, -1.0);
uniform float streak_len = 0.6;
uniform float alpha_max = 0.2;

varying float v_alpha;
varying vec3 v_to_cam;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float s = length(MODEL_MATRIX[1].xyz);
	vec3 to_cam = CAMERA_POSITION_WORLD - origin;
	float d = length(to_cam);
	vec3 axis = normalize(streak_dir);
	vec3 side = cross(axis, to_cam);
	float sl = length(side);
	side = (sl > 0.0001) ? side / sl : vec3(1.0, 0.0, 0.0);
	vec3 world = origin + side * VERTEX.x * s + axis * VERTEX.y * s * streak_len;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
	float far_t = 1.0 - smoothstep(30.0, 60.0, d);
	float near_t = smoothstep(2.5, 8.0, d);
	v_alpha = far_t * near_t * COLOR.a * alpha_max;
	v_to_cam = to_cam / max(d, 0.0001);
}

void fragment() {
	ALBEDO = spray_color.rgb;
	ALPHA = spray_color.a * v_alpha;
	NORMAL = normalize(mat3(VIEW_MATRIX) * v_to_cam);
}
