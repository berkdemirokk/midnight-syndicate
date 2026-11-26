shader_type spatial;
render_mode cull_disabled;
// Spectator cards from the photo atlas (assets/world/kits/event_photo/crowd_cards_atlas.png, 8 x 4 cells). Each card
// turns about the vertical axis only, to face the camera. The front cell (INSTANCE_CUSTOM.r = cell / 32) shows when the
// camera is on the road side of the spectator, the back cell (cell + 16) when it is behind. INSTANCE_CUSTOM.g = scale.
// Alpha scissor, no blending. Lit like the scene, with the small warm fill that crowd_figure.gdshader uses after dark.
uniform sampler2D cards : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 tone = vec3(1.0);
uniform float fill = 0.0;
uniform vec3 fill_tint : source_color = vec3(1.0, 0.86, 0.72);
uniform float card_w = 0.875;  // metres: a 256 x 512 cell at 1.75 m tall
uniform float card_h = 1.75;

varying flat float cell_index;

void vertex() {
	float s = INSTANCE_CUSTOM.g;
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	// The spectator's front points to the road: -Z of the instance basis.
	vec3 facing = -normalize(vec3(MODEL_MATRIX[2].x, 0.0, MODEL_MATRIX[2].z));
	vec3 to_cam = normalize(vec3(CAMERA_POSITION_WORLD.x - origin.x, 0.0, CAMERA_POSITION_WORLD.z - origin.z));
	bool front = dot(facing, to_cam) >= 0.0;
	float k = floor(INSTANCE_CUSTOM.r * 32.0 + 0.5);
	cell_index = front ? k : k + 16.0;
	// Cylindrical billboard: the card plane faces the camera, rotated about Y only.
	vec3 z_axis = to_cam;
	vec3 x_axis = normalize(cross(vec3(0.0, 1.0, 0.0), z_axis));
	vec3 y_axis = vec3(0.0, 1.0, 0.0);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(x_axis, 0.0), vec4(y_axis, 0.0), vec4(z_axis, 0.0), vec4(origin, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(VIEW_MATRIX) * mat3(x_axis, y_axis, z_axis);
	VERTEX.x *= card_w * s;
	VERTEX.y = (VERTEX.y + 0.5) * card_h * s;  // the quad is centred: feet at y = 0
	VERTEX.z = 0.0;
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	vec2 cell = vec2(mod(cell_index, 8.0), floor(cell_index / 8.0));
	vec4 c = texture(cards, (cell + UV) / vec2(8.0, 4.0));
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALPHA = c.a;
	ALBEDO = c.rgb * tone;
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
	EMISSION = c.rgb * fill_tint * fill;
}
