shader_type spatial;
render_mode cull_disabled;
// Photo lining for the garage room: a straight-on workshop picture (generated, see ASSET_MANIFEST.json) laid a few cm in
// front of a room wall or the ceiling. The lamps-on picture is the glow map. The edges fade out over `feather` (UV units)
// so the flat room geometry behind shows through instead of a hard poster edge.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D night_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float night = 0.0;
uniform vec3 tint = vec3(1.0);
uniform vec2 feather = vec2(0.05, 0.0);
// The pictures are 3:2 (1536 x 1024) stored in a power-of-two 2048 x 1024 file: only the left pic_scale part is picture.
uniform vec2 pic_scale = vec2(0.75, 1.0);

void fragment() {
	vec2 puv = UV * pic_scale;
	vec2 edge = min(puv, pic_scale - puv);
	vec2 k = smoothstep(vec2(0.0), max(feather, vec2(0.0001)), edge);
	ALBEDO = texture(albedo_tex, puv).rgb * tint;
	ROUGHNESS = 0.75;
	SPECULAR = 0.35;
	EMISSION = texture(night_tex, puv).rgb * night;
	ALPHA = k.x * k.y;
}
