shader_type canvas_item;

/*
	Buffer B — Bloom mipmap tree with oversampling.
	Packs multiple downsampled octaves into one texture with padding.
*/

uniform sampler2D source_tex : filter_linear, repeat_disable;
uniform vec2 resolution = vec2(1920.0, 1080.0);

vec3 Fetch(vec2 c) { return texture(source_tex, c).rgb; }

vec3 Grab(vec2 coord, float octave, vec2 offset, int samples) {
	float scale = exp2(octave);
	coord = (coord + offset) * scale;
	if (coord.x < 0.0 || coord.x > 1.0 || coord.y < 0.0 || coord.y > 1.0) return vec3(0.0);
	if (samples <= 1) return Fetch(coord);

	vec3 col = vec3(0.0);
	float w = 0.0;
	float inv_s = 1.0 / float(samples);
	for (int i = 0; i < samples; i++) {
		for (int j = 0; j < samples; j++) {
			col += Fetch(coord + vec2(float(i), float(j)) / resolution * scale * inv_s);
			w += 1.0;
		}
	}
	return col / w;
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
	vec3 color = vec3(0.0);
	color += Grab(uv, 1.0, vec2(0.0), 1);
	color += Grab(uv, 2.0, CalcOffset(1.0), 4);
	color += Grab(uv, 3.0, CalcOffset(2.0), 8);
	color += Grab(uv, 4.0, CalcOffset(3.0), 16);
	color += Grab(uv, 5.0, CalcOffset(4.0), 16);
	color += Grab(uv, 6.0, CalcOffset(5.0), 16);
	color += Grab(uv, 7.0, CalcOffset(6.0), 16);
	color += Grab(uv, 8.0, CalcOffset(7.0), 16);
	COLOR = vec4(color, 1.0);
}
