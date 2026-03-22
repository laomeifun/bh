shader_type canvas_item;

/*
	Buffer D - Vertical Gaussian blur.
	Leverages hardware filtering for fewer texture lookups.
*/

uniform sampler2D source_texture : filter_linear, repeat_disable;
uniform vec2 resolution = vec2(1920.0, 1080.0);

vec3 ColorFetch(vec2 coord) { return texture(source_texture, coord).rgb; }

void fragment() {
	float weights_arr[5];
	float offsets_arr[5];

	weights_arr[0] = 0.19638062;
	weights_arr[1] = 0.29675293;
	weights_arr[2] = 0.09442139;
	weights_arr[3] = 0.01037598;
	weights_arr[4] = 0.00025940;

	offsets_arr[0] = 0.00000000;
	offsets_arr[1] = 1.41176471;
	offsets_arr[2] = 3.29411765;
	offsets_arr[3] = 5.17647059;
	offsets_arr[4] = 7.05882353;

	vec2 uv = UV;

	vec3 color = vec3(0.0);
	float weightSum = 0.0;

	if (uv.x < 0.52) {
		color += ColorFetch(uv) * weights_arr[0];
		weightSum += weights_arr[0];

		for (int i = 1; i < 5; i++) {
			vec2 offset = vec2(offsets_arr[i]) / resolution;
			color += ColorFetch(uv + offset * vec2(0.0, 0.5)) * weights_arr[i];
			color += ColorFetch(uv - offset * vec2(0.0, 0.5)) * weights_arr[i];
			weightSum += weights_arr[i] * 2.0;
		}

		color /= weightSum;
	}

	COLOR = vec4(color, 1.0);
}
