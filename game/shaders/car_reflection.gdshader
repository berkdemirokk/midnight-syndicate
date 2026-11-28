shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never;
// Second pass over the car paint: a street panorama mirrored in the clear coat (strongest at grazing angles). The
// Mobile renderer has no screen-space reflections, so this is what makes the paint show the lit street.
uniform sampler2D pano : source_color, filter_linear_mipmap, repeat_enable;
uniform float strength = 0.5;
uniform float highlight = 0.0;  // extra gain on the bright parts of the picture: lamps are far brighter than an 8-bit photo holds
uniform float blur = 2.5;  // mip level: a soft mirror hides the facets of a low-poly body (0 = sharp, for glass)
// The street slides over the paint as the car drives: the panorama turns with the car's world position, so lamps and
// shop lights stream along the body instead of sitting still on it (one turn of the panorama per slide_period_m).
uniform float slide_period_m = 120.0;

void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	vec3 r = (INV_VIEW_MATRIX * vec4(reflect(-v, n), 0.0)).xyz;
	vec2 uv = vec2(atan(r.x, r.z) / 6.2831853 + 0.5, acos(clamp(r.y, -1.0, 1.0)) / 3.1415927);
	uv.x += (NODE_POSITION_WORLD.x + NODE_POSITION_WORLD.z) / slide_period_m;
	float fresnel = 0.12 + 0.88 * pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 3.0);
	vec3 c = textureLod(pano, uv, blur).rgb;
	c *= 1.0 + highlight * smoothstep(0.55, 0.95, max(c.r, max(c.g, c.b)));
	ALBEDO = c * strength * fresnel;
}
