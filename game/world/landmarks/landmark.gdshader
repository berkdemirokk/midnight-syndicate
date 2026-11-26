shader_type spatial;
// Landmark surfaces (waterfront mosque). Day: lit stone, dark glass. Night: the stone is washed warm from the
// ground up (a faked floodlight: brightest at the base, fading with height in metres) and windows and lamps glow.
// `night` is set by Landmarks.set_night; the light stays a plain albedo below the glow.

uniform vec4 base_color : source_color = vec4(0.88, 0.85, 0.79, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.5;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform vec4 glow_color : source_color = vec4(1.0, 0.72, 0.42, 1.0);
uniform float glow : hint_range(0.0, 20.0) = 0.0;
uniform float flood : hint_range(0.0, 4.0) = 0.0;
uniform float flood_height_m : hint_range(1.0, 40.0) = 9.0;
uniform float night : hint_range(0.0, 1.0) = 1.0;

varying float height_m;

void vertex() {
	height_m = max(VERTEX.y, 0.0);
}

void fragment() {
	ALBEDO = base_color.rgb * COLOR.rgb;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	float fl = flood * exp(-height_m / flood_height_m);
	EMISSION = glow_color.rgb * (glow + fl) * night;
}
