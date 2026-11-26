shader_type spatial;
render_mode cull_disabled;
// Sponsor boards on the barrier banner. The atlas (assets/world/kits/event_photo/sponsor_boards_atlas.jpg) holds four
// boards in cells 512 x 256, left to right: MIDNIGHT SYNDICATE, ISTANBUL STREET RACING, NOCTRA, BOGAZ GP. A barrier
// segment is 4 m long: each quarter of its banner carries one board, in the order that starts at INSTANCE_CUSTOM.r * 4
// (so neighbouring segments show the boards in different orders). The banner band is v 0.25 .. 0.75 of the kit UV;
// the base and cap of the barrier stay concrete grey.
uniform sampler2D boards : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 concrete = vec3(0.42, 0.42, 0.40);
uniform vec3 tone = vec3(1.0);

varying flat float board_start;

void vertex() {
	board_start = floor(INSTANCE_CUSTOM.r * 4.0 + 0.5);
}

void fragment() {
	float along = UV.x * 4.0;
	float cell = mod(floor(along) + board_start, 4.0);
	float local_u = fract(along);
	float band_v = (UV.y - 0.25) * 2.0;
	bool in_band = band_v >= 0.0 && band_v <= 1.0;
	vec3 board = texture(boards, vec2((cell + local_u) / 4.0, clamp(band_v, 0.0, 1.0))).rgb;
	ALBEDO = (in_band ? board : concrete) * tone;
	ROUGHNESS = in_band ? 0.3 : 0.8;  // printed vinyl is glossy
	SPECULAR = in_band ? 0.6 : 0.3;
}
