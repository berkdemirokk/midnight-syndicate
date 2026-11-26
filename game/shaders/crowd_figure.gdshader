shader_type spatial;
// Spectator figures: albedo is the baked vertex colour (albedo x AO) times the time-of-day tone. After dark no street
// lamp reaches the pavement behind the barriers, so a small warm fill keeps clothes readable instead of black cut-outs.
uniform vec3 tone = vec3(1.0);
uniform float fill = 0.0;
uniform vec3 fill_tint : source_color = vec3(1.0, 0.86, 0.72);

void fragment() {
	ALBEDO = COLOR.rgb * tone;
	ROUGHNESS = 0.9;
	EMISSION = COLOR.rgb * fill_tint * fill;
}
