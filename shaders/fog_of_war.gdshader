shader_type canvas_item;

uniform sampler2D noise: repeat_enable;

void fragment() {
	// Read the fog image texture — red channel encodes visibility:
	//   1.0 = fully visible  (shader makes transparent)
	//   0.0 = unseen         (shader keeps opaque)
	vec4 t = texture(TEXTURE, UV);

	// Sample the noise for organic fog appearance
	vec4 n = texture(noise, UV);

	// Red channel subtracts from alpha — reveals terrain underneath
	t.a -= t.r;

	// Dark, dense fog colour with noise-based variation
	// Darker base gives a heavier, more opaque feel
	const vec3 FOG_DARK  = vec3(0.04, 0.05, 0.08);
	const vec3 FOG_LIGHT = vec3(0.14, 0.16, 0.22);
	t.rgb = mix(FOG_DARK, FOG_LIGHT, n.r);

	COLOR = t;
}
