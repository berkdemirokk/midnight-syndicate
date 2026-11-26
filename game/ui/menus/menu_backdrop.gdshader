shader_type canvas_item;
// Live night-city backdrop for the menus: haze, skyline in three depth layers with flickering windows,
// a wet perspective road with moving lane dashes, and head/tail light streaks. One full-screen quad, no textures.
// Original work. Cost: a single fragment pass, 3 building layers and 8 light streaks.

uniform float aspect = 1.78;
uniform float horizon = 0.60;
uniform float vanish_x = 0.70;
uniform float dim_left = 0.55;  // how much the left side (menu column) is darkened
uniform float intensity = 1.0;

const vec3 CYAN = vec3(0.098, 0.902, 1.0);
const vec3 MAGENTA = vec3(1.0, 0.169, 0.839);
const vec3 AMBER = vec3(1.0, 0.761, 0.239);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// One skyline layer. Returns rgb in .rgb, coverage in .a.
vec4 skyline(vec2 uv, float cols, float h0, float hv, float seed, vec3 body, float win_amt, float t) {
	float x = uv.x * aspect * cols;
	float id = floor(x);
	float fx = fract(x);
	float h = h0 + hv * pow(hash(vec2(id, seed)), 1.6);
	float top = horizon - h;
	if (uv.y < top || uv.y > horizon + 0.004) {
		return vec4(0.0);
	}
	vec3 col = body;
	// Slight vertical gradient: lighter at the top edge (sky haze), darker at the base.
	col += vec3(0.05, 0.02, 0.09) * smoothstep(0.10, 0.0, uv.y - top) * 0.8;
	vec2 wc = vec2(fx * 5.0, (uv.y - top) * 5.0 * cols * aspect * 0.72);
	vec2 wid = floor(wc);
	vec2 wf = fract(wc);
	float inwin = step(0.22, wf.x) * step(wf.x, 0.78) * step(0.28, wf.y) * step(wf.y, 0.72);
	inwin *= step(0.12, fx) * step(fx, 0.88);
	float lit = step(1.0 - win_amt, hash(wid + vec2(id * 7.3, seed)));
	float tw = 0.75 + 0.25 * sin(t * (0.4 + hash(wid) * 1.2) + hash(wid.yx + id) * 40.0);
	float pick = hash(wid.yx + vec2(id, seed * 3.0));
	vec3 wcol = pick < 0.55 ? AMBER * 0.9 : (pick < 0.88 ? CYAN * 0.8 : MAGENTA * 0.8);
	col += wcol * lit * inwin * tw * 0.75;
	return vec4(col, 1.0);
}

float blob(vec2 d, float s) {
	return exp(-dot(d, d) / (s * s));
}

void fragment() {
	vec2 uv = UV;
	float t = TIME;
	vec3 col = vec3(0.0);

	// Sky: deep navy to a magenta haze at the horizon, a few stars.
	float sky = clamp((horizon - uv.y) / horizon, 0.0, 1.0);
	col = mix(vec3(0.26, 0.055, 0.30), vec3(0.012, 0.018, 0.055), pow(sky, 0.55));
	col += vec3(0.05, 0.16, 0.28) * smoothstep(0.55, 0.0, abs(uv.x - vanish_x)) * smoothstep(0.4, 0.0, horizon - uv.y) * 0.5;
	vec2 sp = vec2(uv.x * aspect, uv.y) * 90.0;
	float star = step(0.992, hash(floor(sp))) * (0.5 + 0.5 * sin(t * 1.3 + hash(floor(sp)) * 20.0)) * smoothstep(0.14, 0.0, length(fract(sp) - 0.5));
	col += vec3(0.8, 0.9, 1.0) * star * smoothstep(0.55, 0.15, uv.y) * 0.8;

	if (uv.y <= horizon + 0.004) {
		// Three skyline layers, far to near; each one hides the previous.
		vec4 b = skyline(uv, 34.0, 0.05, 0.16, 1.0, vec3(0.085, 0.07, 0.17), 0.18, t);
		col = mix(col, b.rgb, b.a);
		b = skyline(uv, 18.0, 0.06, 0.26, 5.0, vec3(0.035, 0.04, 0.10), 0.26, t);
		col = mix(col, b.rgb, b.a);
		b = skyline(uv, 9.0, 0.08, 0.34, 9.0, vec3(0.016, 0.02, 0.055), 0.34, t);
		col = mix(col, b.rgb, b.a);
	} else {
		// Ground: dark city floor, then the road in perspective around the vanishing point.
		float d = uv.y - horizon;
		float cx = (uv.x - vanish_x) * aspect;
		float road_w = 0.55;
		float edge = road_w * d / 0.35;
		float on_road = 1.0 - smoothstep(edge - 0.004, edge + 0.004, abs(cx));
		vec3 ground = vec3(0.012, 0.016, 0.04) + vec3(0.2, 0.05, 0.22) * exp(-d * 18.0) * 0.6;
		vec3 road = vec3(0.020, 0.024, 0.045);
		// Wet sheen: the horizon glow and building lights stretched vertically on the asphalt.
		float z = 0.08 / max(d, 0.002);
		float streak_x = floor(cx / max(d, 0.01) * 14.0);
		float streak = hash(vec2(streak_x, 3.0));
		float refl = exp(-d * 5.5) * (0.35 + 0.65 * step(0.72, streak));
		vec3 rc = mix(CYAN, MAGENTA, hash(vec2(streak_x, 9.0)));
		road += rc * refl * 0.22 * (0.7 + 0.3 * sin(t * 0.8 + streak * 30.0));
		road += vec3(0.30, 0.08, 0.32) * exp(-d * 14.0) * 0.5;
		col = mix(ground, road, on_road);
		// Edge lines: cyan on the left, magenta on the right, with glow.
		float ed = abs(abs(cx) - edge) / (d + 0.03);
		vec3 ec = cx < 0.0 ? CYAN : MAGENTA;
		col += ec * (smoothstep(0.014, 0.0, ed) * 0.9 + smoothstep(0.12, 0.0, ed) * 0.14) * smoothstep(0.0, 0.04, d);
		// Lane dashes: two inner dividers, scrolling toward the viewer.
		for (int i = 0; i < 2; i++) {
			float lx = (float(i) * 2.0 - 1.0) * edge * 0.5;
			float ld = abs(cx - lx) / (d + 0.03);
			float dash = step(0.5, fract(z * 1.2 + t * 1.4));
			col += vec3(0.75, 0.82, 0.9) * smoothstep(0.010, 0.0, ld) * dash * 0.42 * smoothstep(0.0, 0.06, d);
		}
		// Light streaks: oncoming white-cyan on the left lanes, tail lights red on the right lanes.
		for (int k = 0; k < 8; k++) {
			float fk = float(k);
			bool oncoming = k < 4;
			float lane = oncoming ? (-0.75 + fk * 0.18) : (0.25 + (fk - 4.0) * 0.18);
			float sp2 = 0.10 + hash(vec2(fk, 2.0)) * 0.12;
			float ph = fract(t * sp2 + hash(vec2(fk, 7.0)));
			float tt = oncoming ? ph : 1.0 - ph;
			float dk = mix(0.004, 0.40, tt * tt);
			float cxk = lane * road_w * dk / 0.35;
			float s = 0.004 + 0.032 * dk;
			float gap = 0.11 * road_w * dk / 0.35;
			vec2 q = vec2(cx - cxk, (uv.y - horizon - dk) * 2.4);
			vec3 lc = oncoming ? vec3(0.85, 0.95, 1.0) : vec3(1.0, 0.12, 0.10);
			float g = blob(q + vec2(gap, 0.0), s) + blob(q - vec2(gap, 0.0), s);
			// Trail behind the car (up the road for oncoming, towards the horizon for tail lights).
			float trail = blob(vec2(q.x + gap, q.y * 0.22), s * 0.6) * 0.25;
			col += lc * (g * 0.95 + trail) * smoothstep(0.0, 0.05, dk);
		}
	}

	// Horizon bloom over the seam.
	col += vec3(0.30, 0.10, 0.34) * exp(-abs(uv.y - horizon) * 38.0) * 0.5;
	// Darken the menu column so text always has contrast; vignette the corners.
	col *= mix(1.0 - dim_left, 1.0, smoothstep(0.05, 0.62, uv.x));
	vec2 vc = uv - vec2(0.5);
	col *= 1.0 - dot(vc, vc) * 0.75;
	COLOR = vec4(col * intensity, 1.0);
}
