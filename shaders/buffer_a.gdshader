shader_type canvas_item;

/*
	Buffer A — Main black hole render.
	Gravitational lensing ray march + accretion disc + haze.
	NO temporal AA (handled separately if needed).
	Output: raw color * 0.0001 (very small values, tonemapped in Image pass).
*/

uniform vec2 resolution = vec2(1920.0, 1080.0);
uniform vec2 mouse_pos = vec2(0.35, 0.5);
uniform bool mouse_pressed = false;
uniform sampler2D noise_tex : filter_linear, repeat_enable;
uniform sampler2D disc_tex : filter_linear, repeat_enable;
uniform sampler2D prev_frame : filter_linear, repeat_disable;  // Ping-pong temporal AA

const int ITERATIONS = 200;
const vec3 MainColor = vec3(1.0);
// PI is a built-in constant in Godot shaders

// Noise via texture lookup (faithful to original iChannel0 usage)
float noise(vec3 x) {
	vec3 p = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	vec2 uv_n = (p.xy + vec2(37.0, 17.0) * p.z) + f.xy;
	vec2 rg = textureLod(noise_tex, (uv_n + 0.5) / 256.0, 0.0).yx;
	return -1.0 + 2.0 * mix(rg.x, rg.y, f.z);
}

float saturate_f(float x) { return clamp(x, 0.0, 1.0); }
vec3 saturate_v(vec3 x) { return clamp(x, vec3(0.0), vec3(1.0)); }

float rand(vec2 c) {
	return saturate_f(fract(sin(dot(c, vec2(12.9898, 78.223))) * 43758.5453));
}

float pcurve(float x, float a, float b) {
	float k = pow(a + b, a + b) / (pow(a, a) * pow(b, b));
	return k * pow(x, a) * pow(1.0 - x, b);
}

float atan2_f(float y, float x) {
	if (x > 0.0) return atan(y, x);
	else if (x == 0.0) {
		if (y > 0.0) return PI / 2.0;
		else if (y < 0.0) return -PI / 2.0;
		else return 0.0;
	} else {
		if (y >= 0.0) return atan(y, x) + PI;
		else return atan(y, x) - PI;
	}
}

float sdTorus(vec3 p, vec2 t) {
	vec2 q = vec2(length(p.xz) - t.x, p.y);
	return length(q) - t.y;
}

void Haze(inout vec3 color, vec3 pos, float alpha) {
	float d = abs(sdTorus(pos + vec3(0.0, -0.05, 0.0), vec2(1.0, 0.01)));
	float bloom = 1.0 / (d * d + 0.001);
	bloom *= length(pos) < 0.5 ? 0.0 : 1.0;
	color += MainColor * bloom * (2.9 / float(ITERATIONS)) * (1.0 - alpha);
}

void GasDisc(inout vec3 color, inout float alpha, vec3 pos) {
	float discInner = 3.2 - 5.3 * 0.5;
	float distC = distance(pos, vec3(0.0));
	float distD = pos.y;

	float rg = 1.0 - saturate_f((distC - discInner) / 5.3 * 0.5);
	float cov = pcurve(rg, 4.0, 0.9);
	float thick = 0.1 * rg;
	cov *= saturate_f(1.0 - abs(distD) / max(thick, 0.0001));

	float dustGlow = 1.0 / (pow(1.0 - rg, 2.0) * 290.0 + 0.002);
	vec3 dustColor = MainColor * dustGlow * 8.2;
	cov = saturate_f(cov * 0.7);

	float fade = pow(abs(distC - discInner) + 0.4, 4.0) * 0.04;
	float bf = 1.0 / (distD * distD * 40.0 + fade + 0.00002);
	vec3 b = MainColor * pow(bf, 1.5);
	b *= mix(vec3(1.7, 1.1, 1.0), vec3(0.5, 0.6, 1.0), vec3(pow(rg, 2.0)));
	b *= mix(vec3(1.7, 0.5, 0.1), vec3(1.0), vec3(pow(rg, 0.5)));

	dustColor = mix(dustColor, b * 150.0, saturate_f(1.0 - cov));
	cov = saturate_f(cov + bf * bf * 0.1);
	if (cov < 0.01) return;

	vec3 rc = vec3(distC * 1.5 + 0.55, atan2_f(-pos.x, -pos.z) * 1.5, distD * 1.5) * 0.95;
	float spd = 0.06;

	float n1 = 1.0;
	vec3 r = rc;
	r.y += TIME * spd; n1 *= noise(r * 3.0) * 0.5 + 0.5;
	r.y -= TIME * spd; n1 *= noise(r * 6.0) * 0.5 + 0.5;
	r.y += TIME * spd; n1 *= noise(r * 12.0) * 0.5 + 0.5;
	r.y -= TIME * spd; n1 *= noise(r * 24.0) * 0.5 + 0.5;
	r.y += TIME * spd;

	float n2 = 2.0;
	r = rc + 30.0;
	n2 *= noise(r * 3.0) * 0.5 + 0.5; r.y += TIME * spd;
	n2 *= noise(r * 6.0) * 0.5 + 0.5; r.y -= TIME * spd;
	n2 *= noise(r * 12.0) * 0.5 + 0.5; r.y += TIME * spd;
	n2 *= noise(r * 24.0) * 0.5 + 0.5; r.y -= TIME * spd;
	n2 *= noise(r * 48.0) * 0.5 + 0.5; r.y += TIME * spd;
	n2 *= noise(r * 92.0) * 0.5 + 0.5;

	dustColor *= n1 * 0.998 + 0.002;
	cov *= n2;
	rc.y += TIME * spd * 0.5;
	dustColor *= pow(texture(disc_tex, rc.yx * vec2(0.15, 0.27)).rgb, vec3(2.0)) * 4.0;
	cov = saturate_f(cov * 1200.0 / float(ITERATIONS));
	dustColor = max(vec3(0.0), dustColor);
	cov *= pcurve(rg, 4.0, 0.9);

	color = (1.0 - alpha) * dustColor * cov + color;
	alpha = (1.0 - alpha) * cov + alpha;
}

vec3 rot(vec3 p, float x, float y, float z) {
	mat3 mx = mat3(vec3(1,0,0), vec3(0,cos(x),sin(x)), vec3(0,-sin(x),cos(x)));
	mat3 my = mat3(vec3(cos(y),0,-sin(y)), vec3(0,1,0), vec3(sin(y),0,cos(y)));
	mat3 mz = mat3(vec3(cos(z),sin(z),0), vec3(-sin(z),cos(z),0), vec3(0,0,1));
	return my * mz * mx * p;
}

void fragment() {
	vec2 uv = FRAGCOORD.xy / resolution;
	float aspect = resolution.x / resolution.y;

	// Temporal AA: jitter UV slightly each frame (disabled when mouse pressed)
	vec2 uveye = uv;
	float jitter = mouse_pressed ? 0.0 : 1.0;
	uveye.x += (rand(uv + sin(TIME)) / resolution.x) * jitter;
	uveye.y += (rand(uv + 1.0 + sin(TIME)) / resolution.y) * jitter;

	vec3 eyevec = normalize(vec3((uveye * 2.0 - 1.0) * vec2(aspect, 1.0), 6.0));
	vec3 eyepos = vec3(0.0, 0.0, -10.0);

	vec2 mp = mouse_pos;
	if (mp.x == 0.0) mp.x = 0.35;
	eyepos.x += mp.x * 3.0 - 1.5;

	vec3 ang = vec3(mp.y * 0.05 + 0.05, 1.0 + mp.x, -0.45);
	eyevec = rot(eyevec, ang.x, ang.y, ang.z);
	eyepos = rot(eyepos, ang.x, ang.y, ang.z);

	vec3 color = vec3(0.0);
	float dither = rand(uv + sin(TIME) * jitter) * 2.0;
	float alpha = 0.0;
	float step_size = 15.0 / float(ITERATIONS);

	vec3 raypos = eyepos + eyevec * dither * step_size;
	for (int i = 0; i < ITERATIONS; i++) {
		float sd = distance(raypos, vec3(0.0));
		float wf = 1.0 / (sd * sd + 0.000001);
		eyevec = normalize(eyevec + normalize(vec3(0.0) - raypos) * wf * 5.0 / float(ITERATIONS));
		raypos += eyevec * step_size;
		GasDisc(color, alpha, raypos);
		Haze(color, raypos, alpha);
	}

	color *= 0.0001;

	// Temporal AA: blend 90% previous + 10% current (faithful to original)
	vec3 previous = texture(prev_frame, uv).rgb;
	float blendWeight = 0.9 * jitter;
	color = mix(color, previous, blendWeight);

	COLOR = vec4(saturate_v(color), 1.0);
}
