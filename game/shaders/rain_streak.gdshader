shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add;

// Rain streak: the quad is rebuilt in the vertex stage as a camera-facing ribbon along fall_dir
// (the streak axis = relative rain velocity, slanted by the camera's motion in rain.gd).
// Far streaks thin and fade out, near ones are a little longer, faint right at the lens.
uniform vec4 streak_color : source_color = vec4(0.42, 0.52, 0.7, 0.5);
uniform vec3 fall_dir = vec3(0.0, -1.0, 0.0);
uniform float rain_alpha = 1.0;

varying float v_alpha;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float s = length(MODEL_MATRIX[1].xyz);
	vec3 to_cam = CAMERA_POSITION_WORLD - origin;
	float d = length(to_cam);
	vec3 axis = normalize(fall_dir);
	vec3 side = cross(axis, to_cam);
	float sl = length(side);
	side = (sl > 0.0001) ? side / sl : vec3(1.0, 0.0, 0.0);
	float thin = mix(1.0, 0.45, smoothstep(4.0, 25.0, d));
	float longer = mix(1.25, 0.85, smoothstep(2.0, 20.0, d));
	vec3 world = origin + side * VERTEX.x * s * thin + axis * VERTEX.y * s * longer;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
	float far_t = 1.0 - smoothstep(25.0, 40.0, d);
	float near_t = smoothstep(3.0, 10.0, d);  // near streaks read as poles in the lens, so they fade in later
	v_alpha = far_t * near_t * COLOR.a * rain_alpha;
}

void fragment() {
	ALBEDO = streak_color.rgb;
	ALPHA = streak_color.a * v_alpha;
}
