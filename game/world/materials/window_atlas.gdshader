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

// Skyline cards: > 0 cuts the flat card into a row of tower silhouettes (this many towers across
// the card), so the far skyline does not read as a black rectangle with a straight top edge.
uniform float skyline_towers = 0.0;
uniform float skyline_min_h : hint_range(0.0, 1.0) = 0.35;
// true when UV.y = 0 is the top of the card
uniform bool skyline_v_down = true;

// Rooms behind the glass (interior mapping): 0 = flat atlas look (impostors, skyline cards), 1 = every window
// cell shows a small room with a back wall, ceiling, floor and side walls that shift with the view angle.
uniform float interior_strength : hint_range(0.0, 1.0) = 0.0;
uniform float room_depth_m : hint_range(0.5, 12.0) = 3.5;
// Room size when cell_size_m is 0 (small panes).
uniform vec2 room_size_m = vec2(2.4, 3.1);
// How bright an unlit room is in daylight (it is much darker than the street).
uniform float interior_day_light : hint_range(0.0, 1.0) = 0.22;
// Sky mirrored in the glass: analytic sky colours set per time of day (no reflection probe needed).
uniform float glass_reflect : hint_range(0.0, 2.0) = 0.0;
uniform vec3 sky_zenith : source_color = vec3(0.02, 0.035, 0.085);
uniform vec3 sky_horizon : source_color = vec3(0.10, 0.08, 0.20);
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 sun_colour : source_color = vec3(0.0, 0.0, 0.0);
// Window frame colour in the mullion gaps.
uniform vec3 frame_colour : source_color = vec3(0.10, 0.11, 0.12);

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
	if (skyline_towers > 0.0) {
		float col = floor(UV.x * skyline_towers);
		float h = mix(skyline_min_h, 1.0, hash13(vec3(col, 3.1, 7.7)));
		// a setback crown on some towers
		float sub = fract(UV.x * skyline_towers);
		if (hash13(vec3(col, 9.2, 1.3)) > 0.6 && (sub < 0.2 || sub > 0.8)) {
			h -= 0.06;
		}
		float up = skyline_v_down ? 1.0 - UV.y : UV.y;  // 0 at the bottom of the card, 1 at the top
		if (up > h) {
			discard;
		}
	}
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
		// With rooms behind the glass the atlas no longer decides which windows are lit: the cell does, so houses
		// whose panes sample dark atlas texels still get their share of warm lit rooms.
		on = mix(on * pick * gap, pick * gap, interior_strength);
		lum *= mix(0.7, 1.15, hash13(vec3(cell.yx, 7.0)));
	}
	vec3 glow = mix(white * lum, e, glow_saturation) * on * glow_energy;
	if (interior_strength > 0.0 || glass_reflect > 0.0) {
		vec3 nw = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		vec3 view = normalize(world_pos - CAMERA_POSITION_WORLD);
		bool along_z = abs(nw.x) > abs(nw.z);
		vec3 tw = along_z ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
		float hh = along_z ? world_pos.z : world_pos.x;
		float fres = 0.04 + 0.96 * pow(1.0 - clamp(dot(-view, nw), 0.0, 1.0), 5.0);
		if (interior_strength > 0.0 && abs(nw.y) < 0.5) {
			vec2 cs = cell_size_m.x > 0.0 ? cell_size_m : room_size_m;
			vec2 c = vec2(hh, world_pos.y) / cs;
			vec2 cell = floor(c);
			vec2 p = fract(c) * cs;
			// Ray into the room, in facade space: x along the wall, y up, z into the building.
			vec3 d = vec3(dot(view, tw), view.y, max(-dot(view, nw), 0.05));
			float tx = d.x > 0.0 ? (cs.x - p.x) / d.x : (d.x < 0.0 ? -p.x / d.x : 1e5);
			float ty = d.y > 0.0 ? (cs.y - p.y) / d.y : (d.y < 0.0 ? -p.y / d.y : 1e5);
			float tz = room_depth_m / d.z;
			float th = min(tz, min(tx, ty));
			float depth01 = clamp(d.z * th / room_depth_m, 0.0, 1.0);
			float rh = hash13(vec3(cell, 5.0));
			vec3 room = mix(vec3(0.58, 0.52, 0.43), vec3(0.44, 0.48, 0.55), rh);
			float shade = 0.8;  // back wall
			if (th == ty) {
				shade = d.y > 0.0 ? 1.0 : 0.42;  // ceiling, floor
			} else if (th == tx) {
				shade = 0.62;  // side walls
			} else {
				// furniture band and a door on the back wall
				vec2 hit = p + d.xy * th;
				shade *= 1.0 - 0.35 * step(hit.y, cs.y * 0.34) * step(0.35, hash13(vec3(cell, floor(hit.x * 1.3))));
			}
			vec3 interior = room * shade * mix(1.0, 0.4, depth01);
			// Blinds or a curtain close part of some windows (flat, on the glass plane).
			float blind = hash13(vec3(cell.yx, 11.0));
			float cover = step(0.62, blind) * step(1.0 - (blind - 0.62) * 2.2, fract(c).y);
			interior = mix(interior, vec3(0.62, 0.60, 0.55) * (0.7 + 0.3 * rh), cover);
			ALBEDO = mix(ALBEDO, interior * interior_day_light, interior_strength);
			// A lit room glows with its own depth instead of the flat atlas cell.
			glow = mix(glow, interior * white * on * glow_energy * 1.7, interior_strength);
			if (cell_size_m.x > 0.0) {
				float gapm = step(cell_mullion_m, p.x) * step(cell_mullion_m, p.y);
				ALBEDO = mix(frame_colour, ALBEDO, gapm);
			}
		}
		if (glass_reflect > 0.0) {
			vec3 r = reflect(view, nw);
			vec3 sky = mix(sky_horizon, sky_zenith, smoothstep(0.0, 0.65, r.y));
			sky = mix(sky_horizon * 0.35, sky, smoothstep(-0.25, 0.02, r.y));  // below the horizon: the dim street
			sky += sun_colour * pow(max(dot(r, normalize(sun_dir)), 0.0), 180.0) * 6.0;
			float amount = mix(0.3, 1.0, fres) * glass_reflect;
			ALBEDO *= 1.0 - 0.6 * clamp(amount, 0.0, 1.0);
			glow = glow * (1.0 - 0.35 * clamp(amount, 0.0, 1.0)) + sky * amount;
		}
	}
	EMISSION = glow;
}
