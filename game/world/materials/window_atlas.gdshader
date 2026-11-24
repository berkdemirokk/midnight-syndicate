shader_type spatial;
// Window panes, shop interiors and far-building impostors share this shader.
// Panes are dark glass: low albedo, glossy, a little metallic so the reflection probes and the
// street lights show in them. Only atlas texels above glow_threshold emit, so roughly a quarter
// of the windows are lit and the rest stay dark glass (the emissive atlas carries a grey value even
// in unlit cells). The threshold is soft so the detail painted inside a lit cell (ceiling grid,
// blinds, furniture) survives instead of turning into a flat slab. Lit cells take one of two
// whites, warm or cool, chosen by the cell's own hue: raw atlas blue read as neon, not as offices.
// Output is HDR: EMISSION above 1 feeds the glow.

render_mode depth_draw_opaque, cull_back, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D emissive_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// Multiplies albedo after tint. Glass panes use about 0.2, walls on impostors about 1.
uniform float albedo_scale : hint_range(0.0, 4.0) = 1.0;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.6;
uniform float metallic_value : hint_range(0.0, 1.0) = 0.0;
uniform float glow_energy : hint_range(0.0, 16.0) = 3.0;
uniform float glow_threshold : hint_range(0.0, 0.99) = 0.5;
// Width of the soft threshold band above glow_threshold.
uniform float glow_softness : hint_range(0.01, 0.5) = 0.2;
// 0 = only the warm/cool whites, 1 = raw atlas colour.
uniform float glow_saturation : hint_range(0.0, 1.0) = 0.15;
uniform vec3 glow_tint = vec3(1.0, 0.78, 0.5);
uniform vec3 glow_tint_cool = vec3(0.72, 0.84, 1.0);
// Big tower panes map one atlas cell over a whole floor, so a lit cell lit the whole floor.
// When cell_size_m > 0 the glow is split into world-space window cells of that size and only
// lit_fraction of them stay on (stable per cell). 0 = off (small panes, impostors).
uniform vec2 cell_size_m = vec2(0.0, 0.0);
uniform float lit_fraction : hint_range(0.0, 1.0) = 0.45;
// Dark gap between cells, in metres, so lit cells read as separate windows.
uniform float cell_mullion_m : hint_range(0.0, 0.5) = 0.12;

varying vec3 world_pos;

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	ALBEDO = texture(albedo_tex, UV).rgb * tint.rgb * albedo_scale;
	ROUGHNESS = roughness_value;
	METALLIC = metallic_value;
	vec3 e = texture(emissive_tex, UV).rgb;
	float peak = max(e.r, max(e.g, e.b));
	float on = smoothstep(glow_threshold, glow_threshold + glow_softness, peak);
	float lum = dot(e, vec3(0.3, 0.59, 0.11));
	float cool = clamp((e.b - e.r) * 4.0, 0.0, 1.0);
	vec3 white = mix(glow_tint, glow_tint_cool, cool);
	if (cell_size_m.x > 0.0) {
		// Horizontal coordinate along whichever facade axis this pane faces.
		vec3 n = abs((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		float h = n.x > n.z ? world_pos.z : world_pos.x;
		vec2 c = vec2(h, world_pos.y) / cell_size_m;
		vec2 cell = floor(c);
		vec2 f = fract(c) * cell_size_m;
		float gap = step(cell_mullion_m, f.x) * step(cell_mullion_m, f.y);
		float pick = step(hash13(vec3(cell, floor(n.x > n.z ? world_pos.x : world_pos.z))), lit_fraction);
		on *= pick * gap;
		lum *= mix(0.7, 1.15, hash13(vec3(cell.yx, 7.0)));
	}
	EMISSION = mix(white * lum, e, glow_saturation) * on * glow_energy;
}
