shader_type canvas_item;
render_mode blend_add;

/*
	Bloom overlay pass (additive blending).
	Reads the already-tonemapped screen at multiple mipmap LODs
	to create a soft glow / bloom effect around bright areas.
*/

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float bloom_strength : hint_range(0.0, 1.0) = 0.12;

void fragment() {
	vec2 uv = SCREEN_UV;

	// Sample screen texture at increasing LODs for progressively blurred versions
	vec3 bloom = vec3(0.0);
	bloom += textureLod(screen_texture, uv, 1.0).rgb * 1.0;
	bloom += textureLod(screen_texture, uv, 2.0).rgb * 1.5;
	bloom += textureLod(screen_texture, uv, 3.0).rgb * 1.0;
	bloom += textureLod(screen_texture, uv, 4.0).rgb * 1.5;
	bloom += textureLod(screen_texture, uv, 5.0).rgb * 1.8;
	bloom += textureLod(screen_texture, uv, 6.0).rgb * 1.0;
	bloom += textureLod(screen_texture, uv, 7.0).rgb * 1.0;
	bloom += textureLod(screen_texture, uv, 8.0).rgb * 1.0;

	// Output bloom only - blend_add will add it to the existing screen content
	COLOR = vec4(bloom * bloom_strength, 1.0);
}
