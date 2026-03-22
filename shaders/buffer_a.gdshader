shader_type canvas_item;

/*
	Buffer A - Main black hole render.
	Ray marching with gravitational lensing, accretion disc, and haze.
	Temporal AA accumulation for smooth image.
*/

// ============ Uniforms ============
uniform vec2 resolution = vec2(1920.0, 1080.0);
uniform vec2 mouse_pos = vec2(0.35, 0.5);
uniform bool mouse_pressed = false;
uniform sampler2D noise_texture : filter_linear, repeat_enable;
uniform sampler2D disc_texture : filter_linear, repeat_enable;
uniform sampler2D prev_frame : filter_linear;  // Previous frame for temporal AA

// ============ Constants ============
const int ITERATIONS = 200;
const vec3 MainColor = vec3(1.0);
const float pi = 3.14159265;

// ============ Noise using texture lookup (faithful to original) ============
float noise(vec3 x) {
	vec3 p = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	vec2 uv = (p.xy + vec2(37.0, 17.0) * p.z) + f.xy;
	vec2 rg = textureLod(noise_texture, (uv + 0.5) / 256.0, 0.0).yx;
	return -1.0 + 2.0 * mix(rg.x, rg.y, f.z);
}

// ============ Utility functions ============
float saturate_f(float x) { return clamp(x, 0.0, 1.0); }
vec3 saturate_v3(vec3 x) { return clamp(x, vec3(0.0), vec3(1.0)); }

float rand(vec2 coord) {
	return saturate_f(fract(sin(dot(coord, vec2(12.9898, 78.223))) * 43758.5453));
}

float pcurve(float x, float a, float b) {
	float k = pow(a + b, a + b) / (pow(a, a) * pow(b, b));
	return k * pow(x, a) * pow(1.0 - x, b);
}

float atan2_custom(float y, float x) {
	if (x > 0.0) {
		return atan(y, x);
	} else if (x == 0.0) {
		if (y > 0.0) return pi / 2.0;
		else if (y < 0.0) return -(pi / 2.0);
		else return 0.0;
	} else {
		if (y >= 0.0) return atan(y, x) + pi;
		else return atan(y, x) - pi;
	}
}

// ============ SDF ============
float sdTorus(vec3 p, vec2 t) {
	vec2 q = vec2(length(p.xz) - t.x, p.y);
	return length(q) - t.y;
}

// ============ Haze ============
void Haze(inout vec3 color, vec3 pos, float alpha) {
	vec2 t = vec2(1.0, 0.01);
	float torusDist = abs(sdTorus(pos + vec3(0.0, -0.05, 0.0), t));
	float bloomDisc = 1.0 / (pow(torusDist, 2.0) + 0.001);
	vec3 col = MainColor;
	bloomDisc *= length(pos) < 0.5 ? 0.0 : 1.0;
	color += col * bloomDisc * (2.9 / float(ITERATIONS)) * (1.0 - alpha * 1.0);
}

// ============ Gas Disc ============
void GasDisc(inout vec3 color, inout float alpha, vec3 pos, float time_val) {
	float discRadius = 3.2;
	float discWidth = 5.3;
	float discInner = discRadius - discWidth * 0.5;

	vec3 origin = vec3(0.0);
	vec3 discNormal = normalize(vec3(0.0, 1.0, 0.0));
	float discThickness = 0.1;

	float distFromCenter = distance(pos, origin);
	float distFromDisc = dot(discNormal, pos - origin);

	float radialGradient = 1.0 - saturate_f((distFromCenter - discInner) / discWidth * 0.5);
	float coverage = pcurve(radialGradient, 4.0, 0.9);

	discThickness *= radialGradient;
	coverage *= saturate_f(1.0 - abs(distFromDisc) / max(discThickness, 0.0001));

	vec3 dustColorLit = MainColor;
	float dustGlow = 1.0 / (pow(1.0 - radialGradient, 2.0) * 290.0 + 0.002);
	vec3 dustColor = dustColorLit * dustGlow * 8.2;
	coverage = saturate_f(coverage * 0.7);

	float fade = pow((abs(distFromCenter - discInner) + 0.4), 4.0) * 0.04;
	float bloomFactor = 1.0 / (pow(distFromDisc, 2.0) * 40.0 + fade + 0.00002);
	vec3 b = dustColorLit * pow(bloomFactor, 1.5);
	b *= mix(vec3(1.7, 1.1, 1.0), vec3(0.5, 0.6, 1.0), vec3(pow(radialGradient, 2.0)));
	b *= mix(vec3(1.7, 0.5, 0.1), vec3(1.0), vec3(pow(radialGradient, 0.5)));

	dustColor = mix(dustColor, b * 150.0, saturate_f(1.0 - coverage * 1.0));
	coverage = saturate_f(coverage + bloomFactor * bloomFactor * 0.1);

	if (coverage < 0.01) { return; }

	vec3 radialCoords;
	radialCoords.x = distFromCenter * 1.5 + 0.55;
	radialCoords.y = atan2_custom(-pos.x, -pos.z) * 1.5;
	radialCoords.z = distFromDisc * 1.5;
	radialCoords *= 0.95;

	float speed = 0.06;

	float noise1 = 1.0;
	vec3 rc = radialCoords + 0.0;
	rc.y += time_val * speed;
	noise1 *= noise(rc * 3.0) * 0.5 + 0.5;    rc.y -= time_val * speed;
	noise1 *= noise(rc * 6.0) * 0.5 + 0.5;    rc.y += time_val * speed;
	noise1 *= noise(rc * 12.0) * 0.5 + 0.5;   rc.y -= time_val * speed;
	noise1 *= noise(rc * 24.0) * 0.5 + 0.5;   rc.y += time_val * speed;

	float noise2 = 2.0;
	rc = radialCoords + 30.0;
	noise2 *= noise(rc * 3.0) * 0.5 + 0.5;    rc.y += time_val * speed;
	noise2 *= noise(rc * 6.0) * 0.5 + 0.5;    rc.y -= time_val * speed;
	noise2 *= noise(rc * 12.0) * 0.5 + 0.5;   rc.y += time_val * speed;
	noise2 *= noise(rc * 24.0) * 0.5 + 0.5;   rc.y -= time_val * speed;
	noise2 *= noise(rc * 48.0) * 0.5 + 0.5;   rc.y += time_val * speed;
	noise2 *= noise(rc * 92.0) * 0.5 + 0.5;   rc.y -= time_val * speed;

	dustColor *= noise1 * 0.998 + 0.002;
	coverage *= noise2;

	radialCoords.y += time_val * speed * 0.5;

	// Disc texture sampling (iChannel1 equivalent)
	dustColor *= pow(texture(disc_texture, radialCoords.yx * vec2(0.15, 0.27)).rgb, vec3(2.0)) * 4.0;

	coverage = saturate_f(coverage * 1200.0 / float(ITERATIONS));
	dustColor = max(vec3(0.0), dustColor);
	coverage *= pcurve(radialGradient, 4.0, 0.9);

	color = (1.0 - alpha) * dustColor * coverage + color;
	alpha = (1.0 - alpha) * coverage + alpha;
}

// ============ Rotation ============
vec3 rotate_pos(vec3 p, float x, float y, float z) {
	mat3 matx = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, cos(x), sin(x)), vec3(0.0, -sin(x), cos(x)));
	mat3 maty = mat3(vec3(cos(y), 0.0, -sin(y)), vec3(0.0, 1.0, 0.0), vec3(sin(y), 0.0, cos(y)));
	mat3 matz = mat3(vec3(cos(z), sin(z), 0.0), vec3(-sin(z), cos(z), 0.0), vec3(0.0, 0.0, 1.0));
	p = matx * p;
	p = matz * p;
	p = maty * p;
	return p;
}

void RotateCamera(inout vec3 eyevec, inout vec3 eyepos) {
	vec3 angle = vec3(mouse_pos.y * 0.05 + 0.05, 1.0 + mouse_pos.x * 1.0, -0.45);
	eyevec = rotate_pos(eyevec, angle.x, angle.y, angle.z);
	eyepos = rotate_pos(eyepos, angle.x, angle.y, angle.z);
}

// ============ Gravitational lensing ============
void WarpSpace(inout vec3 eyevec, inout vec3 raypos) {
	float singularityDist = distance(raypos, vec3(0.0));
	float warpFactor = 1.0 / (pow(singularityDist, 2.0) + 0.000001);
	vec3 singularityVector = normalize(vec3(0.0) - raypos);
	eyevec = normalize(eyevec + singularityVector * warpFactor * 5.0 / float(ITERATIONS));
}

// ============ Main fragment ============
void fragment() {
	vec2 fragCoord = FRAGCOORD.xy;
	vec2 uv = fragCoord / resolution;
	float aspect = resolution.x / resolution.y;

	vec2 uveye = uv;

	// Temporal AA jitter (disabled when mouse pressed)
	float jitter_enable = mouse_pressed ? 0.0 : 1.0;
	uveye.x += (rand(uv + sin(TIME * 1.0)) / resolution.x) * jitter_enable;
	uveye.y += (rand(uv + 1.0 + sin(TIME * 1.0)) / resolution.y) * jitter_enable;

	vec3 eyevec = normalize(vec3((uveye * 2.0 - 1.0) * vec2(aspect, 1.0), 6.0));
	vec3 eyepos = vec3(0.0, 0.0, -10.0);

	vec2 mpos = mouse_pos;
	if (mpos.x == 0.0) { mpos.x = 0.35; }
	eyepos.x += mpos.x * 3.0 - 1.5;

	const float far_dist = 15.0;
	RotateCamera(eyevec, eyepos);

	vec3 color = vec3(0.0);
	float dither = rand(uv + sin(TIME * 1.0) * jitter_enable) * 2.0;

	float alpha = 0.0;
	vec3 raypos = eyepos + eyevec * dither * far_dist / float(ITERATIONS);
	for (int i = 0; i < ITERATIONS; i++) {
		WarpSpace(eyevec, raypos);
		raypos += eyevec * far_dist / float(ITERATIONS);
		GasDisc(color, alpha, raypos, TIME);
		Haze(color, raypos, alpha);
	}

	color *= 0.0001;

	// Temporal AA blending with previous frame
	const float p = 1.0;
	vec3 previous = pow(texture(prev_frame, uv).rgb, vec3(1.0 / p));
	color = pow(color, vec3(1.0 / p));
	float blendWeight = 0.9 * jitter_enable;
	color = mix(color, previous, blendWeight);
	color = pow(color, vec3(p));

	COLOR = vec4(saturate_v3(color), 1.0);
}
