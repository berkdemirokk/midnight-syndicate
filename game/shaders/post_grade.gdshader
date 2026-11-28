shader_type canvas_item;
// Full-screen finishing pass under the HUD: radial motion blur that grows with speed (the centre, where the car
// is, stays sharp), a film-like grade (contrast, saturation, cool shadows) and a vignette. One screen copy and
// up to five taps (blur_taps); off on the Low preset.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float blur : hint_range(0.0, 1.0) = 0.0;
uniform vec2 blur_centre = vec2(0.5, 0.44);
uniform float saturation : hint_range(0.0, 2.0) = 1.1;
uniform float contrast : hint_range(0.5, 1.6) = 1.06;
uniform vec3 shadow_tint : source_color = vec3(0.92, 0.96, 1.08);
uniform vec3 highlight_tint : source_color = vec3(1.04, 1.0, 0.95);
uniform float vignette : hint_range(0.0, 1.0) = 0.32;
uniform int blur_taps : hint_range(0, 5) = 5;  // extra samples per pixel; 0 turns the blur off

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - blur_centre;
	float r = length(d * vec2(1.0, 0.8));
	vec3 c = texture(screen_tex, uv).rgb;
	if (blur_taps > 0 && blur > 0.001) {
		// Weak above the horizon: the skyline, the bridge lights and the far shore must stay readable at speed.
		float amt = blur * 0.024 * smoothstep(0.28, 0.85, r) * mix(0.3, 1.0, smoothstep(-0.2, 0.15, d.y));
		if (amt > 0.0004) {
			vec3 acc = c;
			float n = 1.0;
			for (int i = 1; i < 6; i++) {
				if (i > blur_taps) {
					break;
				}
				acc += texture(screen_tex, uv - d * amt * float(i)).rgb;
				n += 1.0;
			}
			c = acc / n;
		}
	}
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, saturation);
	c = (c - 0.5) * contrast + 0.5;
	c *= mix(shadow_tint, highlight_tint, smoothstep(0.05, 0.7, l));
	c *= 1.0 - vignette * smoothstep(0.42, 1.0, r * 1.25);
	COLOR = vec4(max(c, vec3(0.0)), 1.0);
}
