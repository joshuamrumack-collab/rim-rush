shader_type spatial;
uniform vec3 brick : source_color = vec3(0.55, 0.22, 0.16);
uniform vec3 mortar : source_color = vec3(0.75, 0.72, 0.66);
varying vec3 wpos;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = vec2(wpos.x + wpos.z, wpos.y) / vec2(0.5, 0.2);
	float row = floor(p.y);
	p.x += mod(row, 2.0) * 0.5;
	vec2 c = floor(p);
	vec2 f = fract(p);
	float m = step(0.06, f.x) * step(f.x, 0.94) * step(0.1, f.y) * step(f.y, 0.9);
	vec3 b = brick * (0.8 + hash(c) * 0.4);
	ALBEDO = mix(mortar, b, m);
	ROUGHNESS = 0.85;
}
