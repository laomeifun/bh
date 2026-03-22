shader_type canvas_item;

/*
	Image (Final) — Bloom reconstruction + tonemapping + color grading.
	Reads Buffer A (raw) + Buffer D (blurred bloom).
	Faithful port of original Shadertoy Image pass.
*/

uniform sampler2D buffer_a_tex : filter_linear, repeat_disable;
uniform sampler2D bloom_tex : filter_linear, repeat_disable;
uniform vec2 resolution = vec2(1920.0, 1080.0);

vec4 cubic(float x) {
	float x2 = x * x, x3 = x2 * x;
	vec4 w;
	w.x = -x3 + 3.0*x2 - 3.0*x + 1.0;
	w.y = 3.0*x3 - 6.0*x2 + 4.0;
	w.z = -3.0*x3 + 3.0*x2 + 3.0*x + 1.0;
	w.w = x3;
	return w / 6.0;
}

vec4 BicubicSample(vec2 coord) {
	coord *= resolution;
	float fx = fract(coord.x), fy = fract(coord.y);
	coord.x -= fx; coord.y -= fy;
	fx -= 0.5; fy -= 0.5;

	vec4 xc = cubic(fx), yc = cubic(fy);
	vec4 c = vec4(coord.x - 0.5, coord.x + 1.5, coord.y - 0.5, coord.y + 1.5);
	vec4 s = vec4(xc.x + xc.y, xc.z + xc.w, yc.x + yc.y, yc.z + yc.w);
	vec4 o = c + vec4(xc.y, xc.w, yc.y, yc.w) / s;

	vec4 s0 = texture(bloom_tex, vec2(o.x, o.z) / resolution);
	vec4 s1 = texture(bloom_tex, vec2(o.y, o.z) / resolution);
	vec4 s2 = texture(bloom_tex, vec2(o.x, o.w) / resolution);
	vec4 s3 = texture(bloom_tex, vec2(o.y, o.w) / resolution);

	return mix(mix(s3, s2, s.x/(s.x+s.y)), mix(s1, s0, s.x/(s.x+s.y)), s.z/(s.z+s.w));
}

vec3 GrabBloom(vec2 coord, float octave, vec2 offset) {
	float scale = exp2(octave);
	return BicubicSample(coord / scale - offset).rgb;
}

vec2 CalcOffset(float octave) {
	vec2 pad = vec2(10.0) / resolution;
	vec2 off = vec2(0.0);
	off.x = -min(1.0, floor(octave / 3.0)) * (0.25 + pad.x);
	off.y = -(1.0 - 1.0 / exp2(octave)) - pad.y * octave;
	off.y += min(1.0, floor(octave / 3.0)) * 0.35;
	return off;
}

void fragment() {
	vec2 uv = UV;

	vec3 color = texture(buffer_a_tex, uv).rgb;

	// Reconstruct bloom from multiple blurred octaves
	vec3 bloom = vec3(0.0);
	bloom += GrabBloom(uv, 1.0, CalcOffset(0.0)) * 1.0;
	bloom += GrabBloom(uv, 2.0, CalcOffset(1.0)) * 1.5;
	bloom += GrabBloom(uv, 3.0, CalcOffset(2.0)) * 1.0;
	bloom += GrabBloom(uv, 4.0, CalcOffset(3.0)) * 1.5;
	bloom += GrabBloom(uv, 5.0, CalcOffset(4.0)) * 1.8;
	bloom += GrabBloom(uv, 6.0, CalcOffset(5.0)) * 1.0;
	bloom += GrabBloom(uv, 7.0, CalcOffset(6.0)) * 1.0;
	bloom += GrabBloom(uv, 8.0, CalcOffset(7.0)) * 1.0;

	color += bloom * 0.08;
	color *= 200.0;

	// Tonemapping
	color = pow(color, vec3(1.5));
	color = color / (1.0 + color);
	color = pow(color, vec3(1.0 / 1.5));

	// Color grading — warm golden/amber tones (Interstellar style)
	color = mix(color, color * color * (3.0 - 2.0 * color), vec3(1.0));
	color = pow(color, vec3(1.0, 1.15, 1.6));  // Suppress blue, preserve red → warm amber
	color = clamp(color * 1.01, vec3(0.0), vec3(1.0));

	// Gamma
	color = pow(color, vec3(0.7 / 2.2));

	COLOR = vec4(color, 1.0);
}
