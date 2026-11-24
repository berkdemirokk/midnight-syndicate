shader_type canvas_item;
// Animated neon lines over the menu backdrop. Original work, no textures.

uniform vec4 line_a : source_color = vec4(0.098, 0.902, 1.0, 1.0);
uniform vec4 line_b : source_color = vec4(1.0, 0.169, 0.839, 1.0);
uniform float speed = 0.35;
uniform float glow = 0.006;
uniform float intensity = 0.42;
uniform float aspect = 1.78;

void fragment() {
	vec2 p = vec2(SCREEN_UV.x * aspect, SCREEN_UV.y);
	vec3 col = vec3(0.0);
	float acc = 0.0;
	for (int i = 0; i < 5; i++) {
		float fi = float(i);
		float yc = 0.22 + fi * 0.16 + 0.07 * sin(p.x * 2.4 + TIME * speed + fi * 1.7);
		float dist = abs(p.y - yc);
		float line = smoothstep(glow, 0.0, dist);
		float halo = smoothstep(glow * 8.0, 0.0, dist) * 0.22;
		vec3 c = mix(line_a.rgb, line_b.rgb, fi / 4.0);
		col += c * (line + halo);
		acc += line + halo;
	}
	COLOR = vec4(col, clamp(acc * intensity, 0.0, 1.0));
}
