shader_type spatial;
// Court floor: procedural surface + court markings, no textures needed.
// style: 0 parquet, 1 neon (dark glossy grid), 2 sport (blue rubber), 3 retro wood, 4 ice

uniform int style = 0;
uniform vec3 team_a : source_color = vec3(0.2, 0.5, 1.0);
uniform vec3 team_b : source_color = vec3(1.0, 0.35, 0.25);
uniform vec3 line_col : source_color = vec3(0.95, 0.95, 1.0);
uniform float line_glow = 0.0;
uniform float half_x = 14.0;
uniform float half_z = 8.0;
uniform float blackout = 0.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
	return v;
}
float sd_box(vec2 p, vec2 b) {
	vec2 d = abs(p) - b;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}
float lmask(float d, float w) {
	float aa = fwidth(d) * 1.2;
	return 1.0 - smoothstep(w * 0.5, w * 0.5 + aa, abs(d));
}

void fragment() {
	vec2 p = wpos.xz;
	vec3 col;
	float rough = 0.3;
	float metal = 0.0;
	float coat = 0.0;
	bool inside = abs(p.x) < half_x && abs(p.y) < half_z;

	if (style == 0 || style == 3) {
		float pw = 0.16;
		float pl = 1.6;
		float row = floor(p.y / pw);
		float offs = hash(vec2(row, 3.0)) * pl;
		float ci = floor((p.x + offs) / pl);
		float h = hash(vec2(row, ci));
		vec2 lc = vec2(fract((p.x + offs) / pl), fract(p.y / pw));
		float grain = fbm(vec2(p.x * 1.2 + h * 20.0, p.y * 45.0));
		float fine = noise(vec2(p.x * 30.0, p.y * 300.0));
		vec3 wa = style == 0 ? vec3(0.80, 0.56, 0.32) : vec3(0.62, 0.43, 0.25);
		vec3 wb = style == 0 ? vec3(0.64, 0.40, 0.21) : vec3(0.45, 0.30, 0.17);
		col = mix(wa, wb, clamp(h * 0.7 + grain * 0.6 - 0.2, 0.0, 1.0));
		col *= 0.92 + 0.12 * fine;
		float seam = min(min(lc.x, 1.0 - lc.x) * pl, min(lc.y, 1.0 - lc.y) * pw);
		col *= mix(0.6, 1.0, smoothstep(0.0, 0.005, seam));
		rough = style == 0 ? 0.22 + grain * 0.1 : 0.45 + grain * 0.15;
		coat = style == 0 ? 0.8 : 0.3;
		if (style == 3) { col = mix(col, vec3(0.35, 0.3, 0.25), fbm(p * 0.6) * 0.3); }
		if (!inside) { col *= 0.55; }
	} else if (style == 1) {
		col = vec3(0.025, 0.025, 0.04) + fbm(p * 3.0) * 0.02;
		vec2 g = abs(fract(p / 2.0) - 0.5);
		float grid = 1.0 - smoothstep(0.47, 0.49, max(g.x, g.y));
		EMISSION = vec3(0.1, 0.5, 1.0) * (1.0 - grid) * 0.6 * (1.0 - blackout * 0.5);
		rough = 0.08;
		metal = 0.4;
	} else if (style == 2) {
		col = inside ? vec3(0.10, 0.32, 0.62) : vec3(0.12, 0.42, 0.25);
		col += (fbm(p * 9.0) - 0.5) * 0.04;
		rough = 0.6;
	} else {
		float scratch = fbm(vec2(p.x * 3.0 + p.y * 7.0, p.y * 0.5) * 2.0);
		col = vec3(0.82, 0.9, 0.97) - scratch * 0.12;
		rough = 0.04 + scratch * 0.35;
		coat = 1.0;
	}

	// Goal areas tinted in the colour of the team that defends them.
	float ga = step(sd_box(p - vec2(-half_x + 2.0, 0.0), vec2(2.0, 3.5)), 0.0);
	float gb = step(sd_box(p - vec2(half_x - 2.0, 0.0), vec2(2.0, 3.5)), 0.0);
	col = mix(col, team_a, ga * 0.22);
	col = mix(col, team_b, gb * 0.22);

	// Markings
	float lw = 0.08;
	float m = lmask(sd_box(p, vec2(half_x - 0.15, half_z - 0.15)), lw);
	m = max(m, lmask(p.x, lw) * step(abs(p.y), half_z - 0.15));
	m = max(m, lmask(length(p) - 3.0, lw));
	m = max(m, 1.0 - smoothstep(0.12, 0.14, length(p)));
	m = max(m, lmask(sd_box(p - vec2(-half_x + 2.0, 0.0), vec2(2.0, 3.5)), lw) * step(p.x, -half_x + 4.1));
	m = max(m, lmask(sd_box(p - vec2(half_x - 2.0, 0.0), vec2(2.0, 3.5)), lw) * step(half_x - 4.1, p.x));
	m = max(m, 1.0 - smoothstep(0.1, 0.12, length(p - vec2(-half_x + 5.5, 0.0))));
	m = max(m, 1.0 - smoothstep(0.1, 0.12, length(p - vec2(half_x - 5.5, 0.0))));
	if (!inside && abs(p.x) > half_x) { m = 0.0; }
	vec3 lc2 = line_col;
	col = mix(col, lc2, m);
	EMISSION += lc2 * m * (line_glow + blackout * 1.5);
	col *= 1.0 - blackout * 0.85;

	ALBEDO = col;
	ROUGHNESS = mix(rough, 0.5, m);
	METALLIC = metal;
	CLEARCOAT = coat;
	CLEARCOAT_ROUGHNESS = 0.08;
	SPECULAR = 0.5;
}
