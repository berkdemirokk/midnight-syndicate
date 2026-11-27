shader_type spatial;
// Paving slabs (M_Paving) and kerb stones (M_Curb). No textures: the stone grid, per-stone tone,
// dirty joints and chipped arrises are all hashed in world metres, so nothing tiles visibly.
// Boxes use world XZ on top faces and world XY / ZY on the sides.

render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

uniform vec4 base_colour : source_color = vec4(0.44, 0.45, 0.48, 1.0);
// Stone size in metres. Kerbs use one large block with no joints.
uniform float stone_m : hint_range(0.2, 2.0) = 0.4;
// 1 = joints between stones (paving), 0 = none (kerb).
uniform float joints : hint_range(0.0, 1.0) = 1.0;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.7;
// Share of the stock specular (0.35); TimeOfDay lowers it by day (dry kerbs mirrored the blue sky).
uniform float specular_scale : hint_range(0.0, 1.0) = 1.0;
// Wet film: darker stone, glossier, joints hold water. 0.8 is the authored night value.
uniform float wetness : hint_range(0.0, 1.0) = 0.0;

varying vec3 world_pos;
varying vec3 world_nrm;

// Cheap 2D hash, no sin(): stable on Mobile GPUs.
float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0)), f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 wn = normalize(world_nrm);
	vec2 uv = abs(wn.y) > 0.5 ? world_pos.xz : (abs(wn.x) > abs(wn.z) ? world_pos.zy : world_pos.xy);

	vec2 sc = uv / stone_m;
	vec2 cell = floor(sc);
	vec2 f = fract(sc);
	float h = hash12(cell);
	// Distance to the nearest stone edge, metres.
	float j = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)) * stone_m;
	float joint = (1.0 - smoothstep(0.006, 0.02, j)) * joints;
	// Worn edge: a darker bevel on the outer 4 cm, bitten where the grain is high.
	float bevel = (1.0 - smoothstep(0.015, 0.04, j)) * (1.0 - joint);
	bevel *= mix(0.6, 1.0, step(0.45, vnoise(uv * 38.0)));

	// Per-stone tone, slow grime from the macro noise, fine grit on every stone.
	float stone_tone = 0.84 + 0.3 * hash12(cell + 7.0);
	float grime = 0.9 + 0.2 * (vnoise(uv / 9.0) * 0.5 + vnoise(uv / 2.5) * 0.5);
	float grit = 0.94 + 0.12 * vnoise(uv * 14.0);

	vec3 col = base_colour.rgb * stone_tone * grime * grit;
	// Joints hold dirt: darker and a little lighter at the top.
	col = mix(col, col * 0.55 * (0.8 + 0.4 * vnoise(uv * 22.0)), joint);
	col *= 1.0 - 0.12 * bevel;

	col *= mix(1.0, 0.55, wetness * (0.6 + 0.4 * joint));
	ALBEDO = col;
	ROUGHNESS = clamp(mix(roughness_value, 0.28, wetness) + joint * 0.2, 0.0, 1.0);
	SPECULAR = 0.35 * specular_scale;
	METALLIC = 0.0;
}
