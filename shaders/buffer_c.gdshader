shader_type canvas_item;

/* Buffer C — Horizontal Gaussian blur on bloom mipmap tree. */

uniform sampler2D source_tex : filter_linear, repeat_disable;
uniform vec2 resolution = vec2(1920.0, 1080.0);

void fragment() {
	vec2 uv = UV;
	vec3 color = vec3(0.0);
	float wsum = 0.0;

	float w[5] = {0.19638062, 0.29675293, 0.09442139, 0.01037598, 0.00025940};
	float o[5] = {0.0, 1.41176471, 3.29411765, 5.17647059, 7.05882353};

	if (uv.x < 0.52) {
		color += texture(source_tex, uv).rgb * w[0];
		wsum += w[0];
		for (int i = 1; i < 5; i++) {
			vec2 off = vec2(o[i], 0.0) / resolution * 0.5;
			color += texture(source_tex, uv + off).rgb * w[i];
			color += texture(source_tex, uv - off).rgb * w[i];
			wsum += w[i] * 2.0;
		}
		color /= wsum;
	}
	COLOR = vec4(color, 1.0);
}
