shader_type spatial;
// Stone and metal of the 3D storefronts: pilasters, stall risers, cornices and reveals in stone (COLOR.a = 1, the CC0
// stone texture tinted by COLOR.rgb, UV in metres), window frames, mullions and doors in painted metal (COLOR.a = 0).

uniform sampler2D stone_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D stone_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float night = 0.0;

varying float height;

void vertex() {
	height = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y - MODEL_MATRIX[3].y;
}

void fragment() {
	float stone = step(0.5, COLOR.a);
	vec3 st = texture(stone_tex, UV).rgb;
	st = mix(vec3(dot(st, vec3(0.2126, 0.7152, 0.0722))), st, 0.4);
	float grime = mix(0.7, 1.0, smoothstep(0.0, 1.2, height));
	ALBEDO = mix(COLOR.rgb, COLOR.rgb * st * 2.2 * grime, stone);
	NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), texture(stone_nrm, UV).rgb, stone);
	ROUGHNESS = mix(0.38, 0.82, stone);
	METALLIC = mix(0.55, 0.0, stone);
	SPECULAR = 0.5;
}
