shader_type canvas_item;

/*
	Buffer B - Bloom mipmap tree.
	Creates a mipmap-like downsampled tree with padding to prevent bloom leaking.
	Uses oversampling for proper results without real mipmaps.
*/

uniform sampler2D source_texture : filter_linear, repeat_disable;
uniform vec2 resolution = vec2(1920.0, 1080.0);

vec3 ColorFetch(vec2 coord) { return texture(source_texture, coord).rgb; }

vec3 Grab1(vec2 coord, float octave, vec2 offset) {
	float scale = exp2(octave);
	coord += offset;
	coord *= scale;
	if (coord.x < 0.0 || coord.x > 1.0 || coord.y < 0.0 || coord.y > 1.0) return vec3(0.0);
	return ColorFetch(coord);
}

vec3 Grab4(vec2 coord, float octave, vec2 offset) {
	float scale = exp2(octave);
	coord += offset;
	coord *= scale;
	if (coord.x < 0.0 || coord.x > 1.0 || coord.y < 0.0 || coord.y > 1.0) return vec3(0.0);

	vec3 color = vec3(0.0);
	float weights = 0.0;
	for (int i = 0; i < 4; i++) {
		for (int j = 0; j < 4; j++) {
			vec2 off = (vec2(float(i), float(j)) / resolution) * scale / 4.0;
			color += ColorFetch(coord + off);
			weights += 1.0;
		}
	}
	return color / weights;
}

vec3 Grab8(vec2 coord, float octave, vec2 offset) {
	float scale = exp2(octave);
	coord += offset;
	coord *= scale;
	if (coord.x < 0.0 || coord.x > 1.0 || coord.y < 0.0 || coord.y > 1.0) return vec3(0.0);

	vec3 color = vec3(0.0);
	float weights = 0.0;
	for (int i = 0; i < 8; i++) {
		for (int j = 0; j < 8; j++) {
			vec2 off = (vec2(float(i), float(j)) / resolution) * scale / 8.0;
			color += ColorFetch(coord + off);
			weights += 1.0;
		}
	}
	return color / weights;
}

vec3 Grab16(vec2 coord, float octave, vec2 offset) {
	float scale = exp2(octave);
	coord += offset;
	coord *= scale;
	if (coord.x < 0.0 || coord.x > 1.0 || coord.y < 0.0 || coord.y > 1.0) return vec3(0.0);

	vec3 color = vec3(0.0);
	float weights = 0.0;
	for (int i = 0; i < 16; i++) {
		for (int j = 0; j < 16; j++) {
			vec2 off = (vec2(float(i), float(j)) / resolution) * scale / 16.0;
			color += ColorFetch(coord + off);
			weights += 1.0;
		}
	}
	return color / weights;
}

vec2 CalcOffset(float octave) {
	vec2 offset = vec2(0.0);
	vec2 padding = vec2(10.0) / resolution;
	offset.x = -min(1.0, floor(octave / 3.0)) * (0.25 + padding.x);
	offset.y = -(1.0 - (1.0 / exp2(octave))) - padding.y * octave;
	offset.y += min(1.0, floor(octave / 3.0)) * 0.35;
	return offset;
}

void fragment() {
	vec2 uv = UV;

	vec3 color = vec3(0.0);
	color += Grab1(uv, 1.0, vec2(0.0, 0.0));
	color += Grab4(uv, 2.0, CalcOffset(1.0));
	color += Grab8(uv, 3.0, CalcOffset(2.0));
	color += Grab16(uv, 4.0, CalcOffset(3.0));
	color += Grab16(uv, 5.0, CalcOffset(4.0));
	color += Grab16(uv, 6.0, CalcOffset(5.0));
	color += Grab16(uv, 7.0, CalcOffset(6.0));
	color += Grab16(uv, 8.0, CalcOffset(7.0));

	COLOR = vec4(color, 1.0);
}
