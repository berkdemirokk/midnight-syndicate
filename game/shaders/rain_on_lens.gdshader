shader_type canvas_item;
// Rain on the lens: a few drops slide down the glass and refract the frame behind them. Each drop is a lens
// (offset toward its rim) and a short tail above it. Drops start near the left and right edges, so the centre
// (the car and the road ahead) stays clear. Drawn under the race HUD (rain_on_lens.gd sets the layer).
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform float refract_scale : hint_range(0.0, 0.2) = 0.05;
uniform float drop_radius : hint_range(0.01, 0.15) = 0.04;
uniform float highlight : hint_range(0.0, 1.0) = 0.25;

float hash1(float n) {
	return fract(sin(n) * 43758.5453123);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;  // width / height
	vec2 offset = vec2(0.0);
	float sheen = 0.0;
	for (int i = 0; i < 6; i++) {
		float fi = float(i);
		float x = hash1(fi * 12.9898 + 1.0);
		float edge_w = smoothstep(0.1, 0.45, abs(x - 0.5));
		float period = 4.0 + 3.0 * hash1(fi * 7.3 + 2.0);
		float phase = hash1(fi * 3.1 + 3.0);
		float y = 1.0 - fract(TIME / period + phase);  // falls from the top edge to the bottom
		float vis = smoothstep(0.0, 0.08, y) * smoothstep(1.0, 0.92, y) * edge_w;
		vec2 dd = (uv - vec2(x, y)) * vec2(aspect, 1.0);
		if (dd.y < 0.0) {
			dd.y *= 0.35;  // the tail above the drop: stretched, as a sliding drop leaves it
		}
		float r = length(dd);
		float mask = (1.0 - smoothstep(drop_radius * 0.6, drop_radius, r)) * vis;
		vec2 dir = (r > 0.0001) ? normalize(dd) : vec2(0.0);
		offset += vec2(dir.x / aspect, dir.y) * mask * refract_scale;
		sheen += mask * smoothstep(drop_radius * 0.5, drop_radius, r) * highlight;
	}
	vec3 col = texture(screen_tex, SCREEN_UV + offset * strength).rgb;
	col += sheen * strength * vec3(0.85, 0.9, 1.0) * 0.5;
	COLOR = vec4(col, 1.0);
}
