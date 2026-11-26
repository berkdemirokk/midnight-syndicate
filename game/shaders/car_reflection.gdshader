shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never;
// Second pass over the car paint: a street panorama mirrored in the clear coat (strongest at grazing angles). The
// Mobile renderer has no screen-space reflections, so this is what makes the paint show the lit street.
uniform sampler2D pano : source_color, filter_linear_mipmap, repeat_enable;
uniform float strength = 0.5;

void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	vec3 r = (INV_VIEW_MATRIX * vec4(reflect(-v, n), 0.0)).xyz;
	vec2 uv = vec2(atan(r.x, r.z) / 6.2831853 + 0.5, acos(clamp(r.y, -1.0, 1.0)) / 3.1415927);
	float fresnel = 0.12 + 0.88 * pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 3.0);
	ALBEDO = texture(pano, uv).rgb * strength * fresnel;
}
