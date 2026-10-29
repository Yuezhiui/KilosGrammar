shader_type canvas_item;

// Only applies to collected APPLE HALF sprites. A basket texture contains
// opaque uniform pixels immediately ABOVE the painted wooden rim; those pixels
// used to conceal the apple's red bottom and leave a visible green/blue gap.
// Draw the fruit in front of the uniform, but NEVER over the wicker artwork.
uniform float wicker_top_uv = 1.0;

void fragment() {
	if (UV.y >= wicker_top_uv) {
		discard;
	}
}
