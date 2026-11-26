shader_type spatial;
// Window glass of the street-front models (M_Glass, one material for every building).
// Day: a dark pane with a greyed sky tint and a soft specular. Night and sunset: each window cell is lit or dark by a
// hash of its world-space cell (about 1.2 m wide, 1.6 m high), warm 2700 K to 4000 K. Shop glass below shop_top_m is
// always lit at night, with a warm interior gradient from the floor up.
// night and sunset are set by StreetFronts (1 or 0); both are 0 by day.

uniform float night : hint_range(0.0, 1.0) = 0.0;
uniform float sunset : hint_range(0.0, 1.0) = 0.0;
uniform float lit_night : hint_range(0.0, 1.0) = 0.55;
uniform float lit_sunset : hint_range(0.0, 1.0) = 0.35;
uniform float shop_top_m = 3.0;
uniform vec3 warm_low : source_color = vec3(1.0, 0.56, 0.24);   // about 2700 K
uniform vec3 warm_high : source_color = vec3(1.0, 0.86, 0.66);  // about 4000 K
uniform vec3 pane_day : source_color = vec3(0.09, 0.12, 0.15);
uniform vec3 sky_tint : source_color = vec3(0.42, 0.48, 0.55);
uniform float emission_gain = 1.6;  // lit pane just over the 1.05 bloom threshold; 2.4 burnt the panes to white

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float cell_hash(vec3 c) {
	return fract(sin(dot(c, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

void fragment() {
	vec3 cell = floor(world_pos / vec3(1.2, 1.6, 1.2));
	float h = cell_hash(cell);
	float lit_frac = mix(lit_sunset, lit_night, night);
	float lit = step(h, lit_frac);
	float warm_mix = fract(h * 7.31);
	vec3 warm = mix(warm_low, warm_high, warm_mix);
	bool shop = world_pos.y < shop_top_m;
	if (shop && night > 0.5) {
		lit = 1.0;
		float floor_t = clamp(world_pos.y / shop_top_m, 0.0, 1.0);
		warm = mix(warm_low, warm_high, floor_t * 0.6 + warm_mix * 0.4);
	}
	float dusk = max(night, sunset);
	ALBEDO = mix(pane_day, sky_tint * 0.25, 0.6 * (1.0 - dusk));
	ROUGHNESS = mix(0.05, 0.2, dusk);
	SPECULAR = 0.6;
	METALLIC = 0.0;
	EMISSION = warm * lit * dusk * emission_gain * mix(0.6, 1.0, night);
}
