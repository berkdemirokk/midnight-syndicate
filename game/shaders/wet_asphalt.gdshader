shader_type spatial;
// Wet asphalt for the Mobile renderer. No SSR: the wet look comes from roughness, darkening,
// rain ripple normals in puddles and an optional mirrored-camera texture (planar_reflection).
// Vertex colour: R = puddle mask (1 = standing water), G = wear (1 = racing groove).
// UV is world XZ in metres, so the texture scale is the same on every road piece.

render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roughness_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D planar_reflection : source_color, filter_linear_mipmap, repeat_disable;

// One texture tile per this many metres.
uniform float tile_metres : hint_range(0.5, 20.0) = 4.0;
uniform float wetness : hint_range(0.0, 1.0) = 0.0;
// Scales how much of the vertex puddle mask becomes standing water.
uniform float puddle_level : hint_range(0.0, 1.0) = 0.5;
// Rain makes the ripples stronger and the damp sheen a little rougher.
uniform float rain_intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// 0 = off. Set by PlanarReflection when it is attached and turned on.
uniform float planar_enabled : hint_range(0.0, 1.0) = 0.0;
// World -> mirror-camera clip space (projection * view of the mirror camera). Set by PlanarReflection.
uniform mat4 planar_vp;
// The mirror texture is tonemapped (lights clip at 1), so the reflection is boosted to read as light.
uniform float reflection_strength : hint_range(0.0, 6.0) = 2.4;
// Vertical blur step in mirror-texture UV. Larger = longer light streaks.
uniform float reflection_smear : hint_range(0.0, 0.05) = 0.012;
// How far the asphalt grain pushes the reflection around on damp (not flooded) road.
uniform float reflection_grain : hint_range(0.0, 0.1) = 0.012;
// Share of the mirror that damp asphalt shows compared with standing water.
uniform float damp_reflectivity : hint_range(0.0, 1.0) = 0.55;
// Daylight wear: macro tone, repair patches, drain grates, oil band and surface grain. 0 = flat.
uniform float dry_detail : hint_range(0.0, 1.0) = 1.0;

varying vec3 world_pos;

// Cheap 2D hash, no sin(): stable on Mobile GPUs.
float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Smooth value noise in [0,1] for the daylight variation.
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0)), f.x), f.y);
}

// One layer of rain ripples: hashed cells, each with one expanding ring. Returns the
// normal offset (xy) for the layer at scale p. The ring fades to zero at the cell border and
// at its own centre, so neighbouring cells do not cut the rings (that cut was the sparkle).
vec2 ripple_offset(vec2 p, float t) {
	vec2 cell = floor(p);
	vec2 f = fract(p) - 0.5;
	float h = hash12(cell);
	float phase = fract(t * (0.5 + 0.5 * h) + h);
	vec2 centre = (vec2(hash12(cell + 7.1), hash12(cell + 3.7)) - 0.5) * 0.4;
	vec2 d = f - centre;
	float dist = length(d);
	float r = phase * 0.45;
	float x = (dist - r) * 14.0;
	// Ring profile: derivative of a damped sine, fades out as the ring grows.
	float g = cos(x) * exp(-abs(dist - r) * 8.0) * (1.0 - phase);
	float edge = 1.0 - smoothstep(0.3, 0.5, max(abs(f.x), abs(f.y)));
	float core = smoothstep(0.0, 0.04, dist);
	return normalize(d + vec2(1e-4)) * g * edge * core * 0.12;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world_pos.xz / tile_metres;
	float puddle = clamp(COLOR.r * puddle_level * 2.0, 0.0, 1.0) * wetness;
	float wear = COLOR.g;

	vec4 alb = texture(albedo_tex, uv);
	vec3 base_n = texture(normal_tex, uv).rgb;
	float base_r = texture(roughness_tex, uv).r;

	// Daylight detail in world metres, so it never tiles visibly.
	vec2 wp = world_pos.xz;
	// Wet roads (night, rain) keep the mirror look: the dry detail fades with wetness.
	float dd = dry_detail * (1.0 - 0.6 * wetness);
	float macro = vnoise(wp / 14.0) * 0.6 + vnoise(wp / 4.5) * 0.3 + vnoise(wp / 1.3) * 0.1 - 0.5;
	float tone = 1.0 + macro * 0.24 * dd;
	// Repair patches: one hashed rectangle per 8 m cell, about a third of the cells, tone shifted.
	vec2 pc = wp / 8.0;
	vec2 pcell = floor(pc);
	vec2 pl = fract(pc) - 0.5 - (vec2(hash12(pcell + 2.3), hash12(pcell + 9.1)) - 0.5) * 0.4;
	vec2 psz = vec2(0.14, 0.1) + vec2(hash12(pcell + 4.4), hash12(pcell + 6.6)) * 0.22;
	vec2 pe = 1.0 - smoothstep(psz, psz + 0.02, abs(pl));
	float patch = step(hash12(pcell), 0.3) * pe.x * pe.y * dd;
	tone *= 1.0 + (hash12(pcell + 11.0) - 0.5) * 0.18 * patch;
	// Drain grates: about one per 24 m cell, random turn, dark disc with bars and a rim.
	vec2 gcell = floor(wp / 24.0);
	vec2 gd = (fract(wp / 24.0) - 0.5) * 24.0 - (vec2(hash12(gcell + 17.0), hash12(gcell + 19.0)) - 0.5) * 14.0;
	float ga = hash12(gcell + 23.0) * 6.2832;
	vec2 gq = mat2(vec2(cos(ga), sin(ga)), vec2(-sin(ga), cos(ga))) * gd;
	float gl = length(gd);
	float disc = 1.0 - smoothstep(0.36, 0.40, gl);
	float rim = smoothstep(0.34, 0.38, gl) * (1.0 - smoothstep(0.42, 0.46, gl));
	float bars = max(smoothstep(0.35, 0.5, abs(fract(gq.x * 9.0) - 0.5)), smoothstep(0.35, 0.5, abs(fract(gq.y * 9.0) - 0.5)));
	float grate = step(hash12(gcell + 29.0), 0.15) * dd;
	tone *= 1.0 - grate * (disc * (0.55 - 0.3 * bars) + 0.3 * rim);

	// Damp asphalt: darker, a little glossy. Groove: darker and smoother.
	float damp = wetness * (1.0 - puddle * 0.5);
	vec3 col = alb.rgb * tint.rgb * mix(1.0, 0.3, damp);
	// Rubber laid on the racing groove (was a 7 % tint: invisible) and oil stains in the lanes.
	float rubber = wear * (0.17 + 0.11 * vnoise(wp * 2.5)) * dd;
	float oil = smoothstep(0.64, 0.82, vnoise(wp / 3.1 + 40.0)) * dd;
	col *= tone * (1.0 - rubber) * (1.0 - 0.13 * oil);
	col *= mix(vec3(1.0), vec3(0.96, 0.97, 1.02), patch);
	col *= mix(1.0, 0.72, wear * wetness);
	col = mix(col, col * 0.15, puddle);

	float rough = mix(base_r, 0.2, damp);
	rough = mix(rough, 0.08, puddle);
	rough *= mix(1.0, 0.6, wear * wetness);
	rough *= (1.0 - 0.18 * rubber * 4.0) * (1.0 - 0.3 * oil);  // polished rubber and oil are smoother than the stone

	// World-space normal for a flat road: texture x -> world X, texture y -> world Z, up = Y.
	// Puddles flatten it to up and carry ripples.
	vec2 tn = base_n.xy * 2.0 - 1.0;
	vec3 wn = normalize(vec3(tn.x * 0.5, 1.0, tn.y * 0.5));
	// Damp asphalt keeps its grain: that grain is what breaks the mirror into wet glitter.
	// Only standing water goes flat.
	wn = normalize(mix(wn, vec3(0.0, 1.0, 0.0), clamp(puddle + damp * 0.3, 0.0, 1.0)));
	// Fine grain tilt: the low sun shows it as a fine speckle on dry road.
	vec2 gr = vec2(vnoise(wp * 7.0 + vec2(0.5, 0.0)) - vnoise(wp * 7.0 - vec2(0.5, 0.0)), vnoise(wp * 7.0 + vec2(0.0, 0.5)) - vnoise(wp * 7.0 - vec2(0.0, 0.5)));
	wn = normalize(wn + vec3(gr.x, 0.0, gr.y) * 0.35 * dd * (1.0 - puddle));
	if (puddle > 0.001) {
		float t = TIME * (0.8 + 1.2 * rain_intensity);
		vec2 r1 = ripple_offset(world_pos.xz * 1.5, t);
		vec2 r2 = ripple_offset(world_pos.xz * 2.7 + 0.37, t * 1.31);
		vec2 rip = (r1 + r2) * rain_intensity * puddle;
		wn = normalize(wn + vec3(rip.x, 0.0, rip.y));
	}

	ALBEDO = col;
	ROUGHNESS = rough;
	// Specular is left on: real lamp lights give long GGX streaks on the low-roughness puddles.
	SPECULAR = 0.5;
	METALLIC = 0.0;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);

	if (planar_enabled > 0.5) {
		// Project this road point into the mirror camera: the texel it hits is the reflected scene
		// seen from the mirrored viewpoint.
		vec4 c = planar_vp * vec4(world_pos, 1.0);
		vec2 suv = c.xy / c.w * 0.5 + 0.5;
		suv.y = 1.0 - suv.y;
		// Grain breaks the mirror on damp asphalt; puddles stay almost clean.
		suv += wn.xz * mix(reflection_grain, reflection_grain * 0.12, puddle);
		// Wet roads smear lights toward the viewer: blur along the mirror image's vertical axis.
		float smear = reflection_smear * mix(1.0, 0.3, puddle);
		vec3 refl = vec3(0.0);
		float wsum = 0.0;
		// Per-pixel jitter of the taps (interleaved gradient noise): turns the visible stack of
		// discrete copies into fine grain, which reads as wet asphalt texture.
		float jit = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715)))) - 0.5;
		for (int i = -4; i <= 4; i++) {
			float fi = float(i) + jit;
			float w = exp(-fi * fi * 0.18);
			refl += texture(planar_reflection, suv + vec2(0.0, fi * smear)).rgb * w;
			wsum += w;
		}
		refl /= wsum;
		float ndv = clamp(dot(normalize(VIEW), NORMAL), 0.0, 1.0);
		float fres = 0.04 + 0.96 * pow(1.0 - ndv, 5.0);
		// The whole wet road reflects, puddles most. Dry road: nothing.
		float amount = mix(damp_reflectivity, 1.0, puddle) * wetness;
		EMISSION = refl * fres * amount * reflection_strength;
	}
}
