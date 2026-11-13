shader_type spatial;
// City skyscraper windows, lit at random.
uniform vec3 tint : source_color = vec3(1.0, 0.8, 0.5);
uniform vec3 body : source_color = vec3(0.08, 0.09, 0.13);
varying vec3 wpos;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 g = vec2(wpos.x + wpos.z, wpos.y) / vec2(1.2, 1.6);
	vec2 cell = floor(g);
	vec2 f = fract(g);
	float win = step(0.2, f.x) * step(f.x, 0.8) * step(0.25, f.y) * step(f.y, 0.75);
	float lit = step(0.55, hash(cell));
	float side = 1.0 - abs(NORMAL.y);
	ALBEDO = body;
	EMISSION = tint * win * lit * side * (0.6 + hash(cell + 7.0) * 1.2);
	ROUGHNESS = 0.4;
	METALLIC = 0.3;
}
