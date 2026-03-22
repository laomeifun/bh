shader_type canvas_item;

/*
	Black Hole shader - ported from Shadertoy
	Original: 5-pass (Buffer A-D + Image)
	Godot port: single-pass with procedural noise, inline bloom approximation & tonemapping
*/

// ============ Uniforms ============
uniform vec2 resolution = vec2(1920.0, 1080.0);
uniform vec2 mouse_pos = vec2(0.35, 0.5);  // normalized 0-1
uniform bool mouse_pressed = false;

// ============ Constants ============
const int ITERATIONS = 200;
const vec3 MainColor = vec3(1.0);
const float pi = 3.14159265;

// ============ Hash-based noise (replaces texture noise) ============
float hash(float n) {
	return fract(sin(n) * 43758.5453123);
}

float hash2d(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float hash3d(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 45.164))) * 43758.5453);
}

// Value noise (replaces textureLod noise lookup)
float noise(vec3 x) {
	vec3 p = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);

	float n = p.x + p.y * 57.0 + 113.0 * p.z;

	float res = mix(
		mix(mix(hash(n + 0.0), hash(n + 1.0), f.x),
			mix(hash(n + 57.0), hash(n + 58.0), f.x), f.y),
		mix(mix(hash(n + 113.0), hash(n + 114.0), f.x),
			mix(hash(n + 170.0), hash(n + 171.0), f.x), f.y),
		f.z);

	return -1.0 + 2.0 * res;
}

// ============ Utility functions ============
float saturate_f(float x) {
	return clamp(x, 0.0, 1.0);
}

vec3 saturate_v3(vec3 x) {
	return clamp(x, vec3(0.0), vec3(1.0));
}

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
		if (y > 0.0) {
			return pi / 2.0;
		} else if (y < 0.0) {
			return -(pi / 2.0);
		} else {
			return 0.0;
		}
	} else {
		if (y >= 0.0) {
			return atan(y, x) + pi;
		} else {
			return atan(y, x) - pi;
		}
	}
}

// ============ Procedural disc texture (replaces iChannel1) ============
vec3 disc_texture(vec2 uv) {
	// Generates a swirly procedural texture for the accretion disc
	float n1 = noise(vec3(uv * 8.0, 0.0)) * 0.5 + 0.5;
	float n2 = noise(vec3(uv * 16.0, 1.0)) * 0.5 + 0.5;
	float n3 = noise(vec3(uv * 32.0, 2.0)) * 0.5 + 0.5;
	float val = n1 * n2 * n3;
	return vec3(val * val);
}

// ============ SDF functions ============
float sdTorus(vec3 p, vec2 t) {
	vec2 q = vec2(length(p.xz) - t.x, p.y);
	return length(q) - t.y;
}

// ============ Haze (glow around the black hole) ============
void Haze(inout vec3 color, vec3 pos, float alpha) {
	vec2 t = vec2(1.0, 0.01);

	float torusDist = abs(sdTorus(pos + vec3(0.0, -0.05, 0.0), t));

	float bloomDisc = 1.0 / (pow(torusDist, 2.0) + 0.001);
	vec3 col = MainColor;
	bloomDisc *= length(pos) < 0.5 ? 0.0 : 1.0;

	color += col * bloomDisc * (2.9 / float(ITERATIONS)) * (1.0 - alpha * 1.0);
}

// ============ Gas Disc (accretion disc) ============
void GasDisc(inout vec3 color, inout float alpha, vec3 pos, float time_val) {
	float discRadius = 3.2;
	float discWidth = 5.3;
	float discInner = discRadius - discWidth * 0.5;
	float discOuter = discRadius + discWidth * 0.5;

	vec3 origin = vec3(0.0, 0.0, 0.0);
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

	if (coverage < 0.01) {
		return;
	}

	vec3 radialCoords;
	radialCoords.x = distFromCenter * 1.5 + 0.55;
	radialCoords.y = atan2_custom(-pos.x, -pos.z) * 1.5;
	radialCoords.z = distFromDisc * 1.5;

	radialCoords *= 0.95;

	float speed = 0.06;

	float noise1 = 1.0;
	vec3 rc = radialCoords + 0.0;
	rc.y += time_val * speed;
	noise1 *= noise(rc * 3.0) * 0.5 + 0.5;
	rc.y -= time_val * speed;
	noise1 *= noise(rc * 6.0) * 0.5 + 0.5;
	rc.y += time_val * speed;
	noise1 *= noise(rc * 12.0) * 0.5 + 0.5;
	rc.y -= time_val * speed;
	noise1 *= noise(rc * 24.0) * 0.5 + 0.5;
	rc.y += time_val * speed;

	float noise2 = 2.0;
	rc = radialCoords + 30.0;
	noise2 *= noise(rc * 3.0) * 0.5 + 0.5;
	rc.y += time_val * speed;
	noise2 *= noise(rc * 6.0) * 0.5 + 0.5;
	rc.y -= time_val * speed;
	noise2 *= noise(rc * 12.0) * 0.5 + 0.5;
	rc.y += time_val * speed;
	noise2 *= noise(rc * 24.0) * 0.5 + 0.5;
	rc.y -= time_val * speed;
	noise2 *= noise(rc * 48.0) * 0.5 + 0.5;
	rc.y += time_val * speed;
	noise2 *= noise(rc * 92.0) * 0.5 + 0.5;
	rc.y -= time_val * speed;

	dustColor *= noise1 * 0.998 + 0.002;
	coverage *= noise2;

	radialCoords.y += time_val * speed * 0.5;

	// Procedural texture instead of iChannel1
	dustColor *= pow(disc_texture(radialCoords.yx * vec2(0.15, 0.27)), vec3(2.0)) * 4.0;

	coverage = saturate_f(coverage * 1200.0 / float(ITERATIONS));
	dustColor = max(vec3(0.0), dustColor);

	coverage *= pcurve(radialGradient, 4.0, 0.9);

	color = (1.0 - alpha) * dustColor * coverage + color;

	alpha = (1.0 - alpha) * coverage + alpha;
}

// ============ Rotation ============
vec3 rotate_pos(vec3 p, float x, float y, float z) {
	mat3 matx = mat3(
		vec3(1.0, 0.0, 0.0),
		vec3(0.0, cos(x), sin(x)),
		vec3(0.0, -sin(x), cos(x))
	);

	mat3 maty = mat3(
		vec3(cos(y), 0.0, -sin(y)),
		vec3(0.0, 1.0, 0.0),
		vec3(sin(y), 0.0, cos(y))
	);

	mat3 matz = mat3(
		vec3(cos(z), sin(z), 0.0),
		vec3(-sin(z), cos(z), 0.0),
		vec3(0.0, 0.0, 1.0)
	);

	p = matx * p;
	p = matz * p;
	p = maty * p;

	return p;
}

void RotateCamera(inout vec3 eyevec, inout vec3 eyepos) {
	float mousePosY = mouse_pos.y;
	float mousePosX = mouse_pos.x;

	vec3 angle = vec3(mousePosY * 0.05 + 0.05, 1.0 + mousePosX * 1.0, -0.45);

	eyevec = rotate_pos(eyevec, angle.x, angle.y, angle.z);
	eyepos = rotate_pos(eyepos, angle.x, angle.y, angle.z);
}

// ============ Gravitational lensing ============
void WarpSpace(inout vec3 eyevec, inout vec3 raypos) {
	vec3 origin = vec3(0.0, 0.0, 0.0);

	float singularityDist = distance(raypos, origin);
	float warpFactor = 1.0 / (pow(singularityDist, 2.0) + 0.000001);

	vec3 singularityVector = normalize(origin - raypos);

	float warpAmount = 5.0;

	eyevec = normalize(eyevec + singularityVector * warpFactor * warpAmount / float(ITERATIONS));
}

// ============ Main fragment ============
void fragment() {
	vec2 fragCoord = FRAGCOORD.xy;
	vec2 uv = fragCoord / resolution;

	float aspect = resolution.x / resolution.y;

	vec2 uveye = uv;

	vec3 eyevec = normalize(vec3((uveye * 2.0 - 1.0) * vec2(aspect, 1.0), 6.0));
	vec3 eyepos = vec3(0.0, 0.0, -10.0);

	vec2 mpos = mouse_pos;
	if (mpos.x == 0.0) {
		mpos.x = 0.35;
	}
	eyepos.x += mpos.x * 3.0 - 1.5;

	const float far_dist = 15.0;

	RotateCamera(eyevec, eyepos);

	vec3 color = vec3(0.0, 0.0, 0.0);

	float dither = rand(uv) * 2.0;

	float alpha = 0.0;
	vec3 raypos = eyepos + eyevec * dither * far_dist / float(ITERATIONS);
	for (int i = 0; i < ITERATIONS; i++) {
		WarpSpace(eyevec, raypos);
		raypos += eyevec * far_dist / float(ITERATIONS);
		GasDisc(color, alpha, raypos, TIME);
		Haze(color, raypos, alpha);
	}

	color *= 0.0001;

	// ============ Tonemapping & color grading (from Image pass) ============
	color *= 200.0;

	// Tonemapping
	color = pow(color, vec3(1.5));
	color = color / (1.0 + color);
	color = pow(color, vec3(1.0 / 1.5));

	// Color grading
	color = mix(color, color * color * (3.0 - 2.0 * color), vec3(1.0));
	color = pow(color, vec3(1.3, 1.20, 1.0));

	color = saturate_v3(color * 1.01);

	// Gamma
	color = pow(color, vec3(0.7 / 2.2));

	COLOR = vec4(color, 1.0);
}
