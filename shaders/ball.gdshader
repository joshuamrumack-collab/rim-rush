shader_type spatial;
// Soccer-style ball: 12 pentagon patches at the icosahedron vertices.
uniform vec3 base : source_color = vec3(0.97, 0.97, 0.94);
uniform vec3 accent : source_color = vec3(0.08, 0.08, 0.12);
uniform float glow = 0.25;
varying vec3 opos;
const float PHI = 1.618034;
void vertex() { opos = normalize(VERTEX); }
void fragment() {
	float d = 10.0;
	for (int i = 0; i < 4; i++) {
		float s1 = (i % 2 == 0) ? 1.0 : -1.0;
		float s2 = (i < 2) ? 1.0 : -1.0;
		d = min(d, distance(opos, normalize(vec3(0.0, s1, s2 * PHI))));
		d = min(d, distance(opos, normalize(vec3(s1, s2 * PHI, 0.0))));
		d = min(d, distance(opos, normalize(vec3(s2 * PHI, 0.0, s1))));
	}
	float spot = 1.0 - smoothstep(0.29, 0.31, d);
	float seam = smoothstep(0.0, 0.015, abs(d - 0.55)) ;
	vec3 c = mix(base, accent, spot) * mix(0.75, 1.0, seam);
	ALBEDO = c;
	ROUGHNESS = 0.32;
	CLEARCOAT = 1.0;
	CLEARCOAT_ROUGHNESS = 0.1;
	EMISSION = c * glow;
}
