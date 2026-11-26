shader_type spatial;
// Wet building facades for the Mobile renderer, one pass, three texture lookups (albedo, normal, roughness).
// Walls use a world-space projection on the dominant axis of the face (box-shaped kit buildings have no
// usable UVs in metres). Albedo and roughness are pre-scaled in MaterialLibrary (wetness, wall albedo),
// so this shader only adds the rain layers:
//  (a) a wet band at the foot of the wall (darker, glossier),
//  (b) vertical rain streaks: value noise stretched along the height, lower roughness and slight darkening,
//      stronger near the bottom of each storey where sills and ledges shed water,
//  (c) grime: darker toward the bottom of each storey band.
// Storey bands are height-periodic (facade_storey_m). The streak noise is hash based: no extra texture.

render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roughness_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;

// Metres per texture repeat (the CC0 set's uv_tile_m).
uniform float tile_m : hint_range(0.5, 20.0) = 2.0;
// Pre-scaled colour and roughness from MaterialLibrary (dry values x wetness terms).
uniform vec3 albedo_tint : source_color = vec3(1.0);
uniform float roughness_base : hint_range(0.0, 1.0) = 0.8;
uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;

// Whole-wall wetness: the rain film darkens and glosses every metre of the wall, not only the band.
uniform float wall_darken : hint_range(0.0, 1.0) = 0.2;
uniform float wall_gloss : hint_range(0.0, 1.0) = 0.35;

uniform float wet_band_m : hint_range(0.0, 3.0) = 1.2;
uniform float wet_soft_m : hint_range(0.0, 1.0) = 0.3;
uniform float wet_darken : hint_range(0.0, 1.0) = 0.35;
uniform float wet_gloss : hint_range(0.0, 1.0) = 0.6;

uniform float storey_m : hint_range(0.5, 8.0) = 3.4;
// Streaks per metre along the wall, and the vertical noise frequency (per metre; smaller = longer streaks).
uniform float streak_density : hint_range(0.0, 20.0) = 6.0;
uniform float streak_stretch : hint_range(0.0, 2.0) = 0.3;
uniform float streak_threshold : hint_range(0.0, 1.0) = 0.6;
uniform float streak_darken : hint_range(0.0, 1.0) = 0.2;
uniform float streak_gloss : hint_range(0.0, 1.0) = 0.4;
// Extra streak strength at the foot of each storey band (under sills and ledges).
uniform float sill_boost : hint_range(0.0, 2.0) = 0.6;
// Darkening at the bottom of each storey band.
uniform float grime : hint_range(0.0, 1.0) = 0.2;

// Breaks the visible texture repeat: slow tone and warmth drift over 6-25 m, plus soot under the roofline and
// a dark contact band where the wall meets the pavement (the Mobile renderer has no ambient occlusion).
uniform float macro_variation : hint_range(0.0, 1.0) = 0.35;
uniform float contact_dark : hint_range(0.0, 1.0) = 0.45;
uniform float contact_height_m : hint_range(0.05, 3.0) = 0.9;

varying vec3 w_pos;
varying vec3 w_nrm;

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
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 n = normalize(w_nrm);
	vec2 uv;
	vec3 t;
	vec3 b;
	if (abs(n.y) > max(abs(n.x), abs(n.z))) {
		// Ledges and tops: project on the ground plane.
		uv = vec2(w_pos.x, w_pos.z) / tile_m;
		t = vec3(1.0, 0.0, 0.0);
		b = vec3(0.0, 0.0, 1.0);
	} else if (abs(n.x) > abs(n.z)) {
		uv = vec2(w_pos.z, w_pos.y) / tile_m;
		t = vec3(0.0, 0.0, 1.0);
		b = vec3(0.0, 1.0, 0.0);
	} else {
		uv = vec2(w_pos.x, w_pos.y) / tile_m;
		t = vec3(1.0, 0.0, 0.0);
		b = vec3(0.0, 1.0, 0.0);
	}

	vec4 alb = texture(albedo_tex, uv);
	vec3 nt = texture(normal_tex, uv).xyz * 2.0 - 1.0;
	nt.xy *= normal_strength;
	vec3 wn = normalize(t * nt.x + b * nt.y + n * nt.z);
	float rough = roughness_base * texture(roughness_tex, uv).r;

	// (a) wet band: 1 at the ground, fading out over wet_soft_m above wet_band_m.
	float wet = 1.0 - smoothstep(wet_band_m - wet_soft_m, wet_band_m + wet_soft_m, w_pos.y);

	// (b) rain streaks along the wall. The along-wall coordinate is uv.x, in metres via tile_m.
	// Two hashes instead of value noise: one column per cell across the wall, blended vertically.
	float along = uv.x * tile_m;
	float ca = along * streak_density;
	float cx = floor(ca);
	float ys = w_pos.y * streak_stretch;
	float cy = floor(ys);
	float sn = mix(hash12(vec2(cx, cy)), hash12(vec2(cx, cy + 1.0)), smoothstep(0.0, 1.0, fract(ys)));
	float across = smoothstep(0.0, 0.6, 1.0 - abs(fract(ca) - 0.5) * 2.0);
	float streak = smoothstep(streak_threshold, 0.95, sn) * across;
	float sy = fract(w_pos.y / storey_m);  // 0 at the slab, 1 at the next slab
	streak *= 1.0 + sill_boost * (1.0 - smoothstep(0.0, 0.3, sy));

	// (c) grime at the foot of each storey band.
	float grime_term = pow(1.0 - sy, 3.0) * grime;

	float dark = clamp(1.0 - wall_darken - wet_darken * wet - streak_darken * streak - grime_term, 0.2, 1.0);
	vec3 col = albedo_tint * alb.rgb * dark;
	// macro variation in metres along the wall and up it
	vec2 mp = vec2(uv.x * tile_m, w_pos.y);
	float m1 = vnoise(mp / 13.0) * 0.6 + vnoise(mp / 4.3 + 17.0) * 0.4;
	col *= mix(1.0, 0.72 + 0.56 * m1, macro_variation);
	col = mix(col, col * vec3(1.06, 1.0, 0.92), macro_variation * (vnoise(mp / 21.0 + 5.0) - 0.5));
	// contact band at the pavement and grime creeping up from it
	float contact = 1.0 - smoothstep(0.0, contact_height_m, w_pos.y + 0.6 * vnoise(vec2(uv.x * tile_m * 0.7, 3.0)));
	col *= 1.0 - contact_dark * contact * contact;
	ALBEDO = col;

	rough *= (1.0 - wall_gloss) * (1.0 - wet_gloss * wet);
	rough -= streak_gloss * streak;
	ROUGHNESS = clamp(rough, 0.05, 1.0);
	NORMAL = normalize(mat3(VIEW_MATRIX) * wn);
}
