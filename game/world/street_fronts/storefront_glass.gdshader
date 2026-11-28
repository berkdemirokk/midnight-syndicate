shader_type spatial;
// Shop window glass of the 3D storefronts (Storefront, PhotoFronts): a room behind the glass by interior mapping.
// The back wall is the shop part of the building's own facade picture (day picture by day, night picture at night), so
// the window shows the same shop as the photo did, now with depth: it shifts with the view and the side walls, floor and
// ceiling close the box. The glass itself is black and glossy, so the engine adds the sky / reflection-probe mirror
// with its Fresnel: at the grazing chase-camera angle the window mostly reflects the street, as real shop glass does.
// Per vertex: UV = position on the window in 0..1 (x from the viewer's left, y from the floor), UV2 = window size in m,
// COLOR = (u_left, u_right, v_top, v_bottom) of the shop crop in the picture.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D night_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float room_depth_m = 2.6;
uniform float night = 0.0;  // 0 day, about 0.6 sunset, 1 night (set by PhotoFronts)
uniform float day_light = 0.42;  // a shop interior seen from a sunlit street is much darker than the street
uniform float night_light = 1.6;
uniform vec3 ceiling_lamp : source_color = vec3(1.0, 0.82, 0.6);
uniform float glass_roughness = 0.08;
uniform float engine_specular = 0.06;
uniform float closed_share = 0.2;  // shops with the shutter down after dark
uniform float cool_share = 0.25;  // shops with cool white LED light
uniform vec3 shutter_colour : source_color = vec3(0.16, 0.16, 0.17);
uniform float mirror_strength = 0.85;
uniform vec3 street_day : source_color = vec3(0.16, 0.15, 0.14);
uniform vec3 street_night : source_color = vec3(0.025, 0.02, 0.02);
uniform vec3 sky_day : source_color = vec3(0.55, 0.62, 0.72);
uniform vec3 sky_night : source_color = vec3(0.02, 0.025, 0.04);

varying vec3 world_pos;
varying vec3 world_n;
varying vec4 crop;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	crop = COLOR;
}

vec3 pic(vec2 uv01, float lod) {
	vec2 uv = vec2(mix(crop.r, crop.g, uv01.x), mix(crop.a, crop.b, uv01.y));
	vec3 d = textureLod(albedo_tex, uv, lod).rgb;
	vec3 n = textureLod(night_tex, uv, lod).rgb;
	return mix(d * day_light, n * night_light, night);
}

void fragment() {
	vec3 n = normalize(world_n);
	vec3 t = normalize(cross(vec3(0.0, 1.0, 0.0), n));  // the viewer's right on the window
	vec3 ray = normalize(world_pos - CAMERA_POSITION_WORLD);
	vec3 r = vec3(dot(ray, t), ray.y, max(dot(ray, -n), 1e-3));  // window frame: x right, y up, z into the room
	vec2 size = UV2;
	vec2 p = UV * size;
	float tx = r.x > 0.0 ? (size.x - p.x) / r.x : (r.x < 0.0 ? -p.x / r.x : 1e6);
	float ty = r.y > 0.0 ? (size.y - p.y) / r.y : (r.y < 0.0 ? -p.y / r.y : 1e6);
	float tz = room_depth_m / r.z;
	float th = min(min(tx, ty), tz);
	vec3 hit = vec3(p + r.xy * th, r.z * th);
	vec3 back = pic(clamp(hit.xy / size, 0.0, 1.0), 0.0);
	vec3 avg = pic(vec2(0.5, 0.45), 6.0);  // the room's mean colour paints walls, floor and ceiling
	float depth01 = clamp(hit.z / room_depth_m, 0.0, 1.0);
	vec3 col;
	if (th == tz) {
		col = back;
	} else if (th == ty) {
		if (r.y > 0.0) {  // ceiling: a row of lamps at night
			float lamp = smoothstep(0.42, 0.5, abs(fract(hit.z / 1.2) - 0.5)) * step(0.15, hit.x) * step(hit.x, size.x - 0.15);
			col = avg * 0.55 + ceiling_lamp * lamp * night * 1.6;
		} else {  // floor: tiles, lit from above
			float tile = step(0.5, fract(hit.x * 1.6) ) == step(0.5, fract(hit.z * 1.6)) ? 1.0 : 0.82;
			col = avg * 0.7 * tile;
		}
	} else {
		col = avg * 0.8 * mix(1.0, 0.65, depth01);  // side walls get darker toward the back
	}
	col *= mix(1.0, 0.7, depth01 * (1.0 - night));
	// Every shop is its own business after dark: a hash of the window's left edge (constant over one window) picks
	// closed (roller shutter down, a dim security light), cool white LED, or warm light at its own brightness.
	vec3 edge = world_pos - t * p.x - vec3(0.0, p.y, 0.0);  // the window's bottom-left corner
	float sh = fract(sin(dot(round(edge * 2.0) + vec3(crop.r * 37.0), vec3(12.9898, 78.233, 37.719))) * 43758.5453);
	float lit_dusk = night;
	if (sh < closed_share) {
		float slat = 0.55 + 0.45 * smoothstep(0.0, 0.5, abs(fract(p.y / 0.11) - 0.5));
		vec3 shutter = shutter_colour * slat * mix(1.0, 0.25, lit_dusk);
		col = mix(col, shutter, lit_dusk);
	} else if (sh < closed_share + cool_share) {
		float l = dot(col, vec3(0.2126, 0.7152, 0.0722));
		col = mix(col, vec3(l) * vec3(0.82, 0.92, 1.08) * 1.15, lit_dusk);
	} else {
		col *= mix(1.0, mix(0.6, 1.25, fract(sh * 9.7)), lit_dusk);
	}
	// Mirror: at the grazing chase angle shop glass reflects the far side of the street, not the sky. The probes here
	// hold mostly sky, so the engine specular is kept weak and the shader adds the street: dark facades below the
	// horizon of the reflected ray, a little sky above it.
	vec3 refl = reflect(ray, n);
	float cos_v = clamp(dot(-ray, n), 0.0, 1.0);
	float fres = 0.04 + 0.96 * pow(1.0 - cos_v, 5.0);
	vec3 street = mix(street_day, street_night, night);
	vec3 sky = mix(sky_day, sky_night, night);
	vec3 mirror = mix(street, sky, smoothstep(0.25, 0.7, refl.y));
	col = mix(col, mirror, fres * mirror_strength);
	ALBEDO = vec3(0.0);
	METALLIC = 0.0;
	SPECULAR = engine_specular;
	ROUGHNESS = glass_roughness;
	EMISSION = col;
}
