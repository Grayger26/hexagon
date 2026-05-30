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

	// Dense, heavy fog — deep blue-grey that feels thick and solid.
	// Very tightly compressed noise range (0.37–0.63) so the colour is
	// almost uniform — the fog reads as a single dense mass with just
	// a whisper of organic texture to avoid a flat look.
	const vec3 FOG_DARK  = vec3(0.10, 0.12, 0.22);
	const vec3 FOG_LIGHT = vec3(0.18, 0.20, 0.30);
	// Minimal noise influence: the fog stays nearly the same colour
	// everywhere, making it feel consistently filled and substantial.
	t.rgb = mix(FOG_DARK, FOG_LIGHT, n.r * 0.26 + 0.37);

	COLOR = t;
}
