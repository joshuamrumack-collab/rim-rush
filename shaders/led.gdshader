shader_type spatial;
// Scrolling LED advertising boards.
uniform vec3 col_a : source_color = vec3(0.2, 0.5, 1.0);
uniform vec3 col_b : source_color = vec3(1.0, 0.35, 0.25);
uniform float speed = 0.15;
uniform float energy = 2.0;
uniform float flash = 0.0;
void fragment() {
	vec2 uv = UV;
	float x = uv.x * 8.0 + TIME * speed * 8.0;
	float band = step(0.5, fract(x * 0.25));
	float chev = step(0.5, fract(x + abs(uv.y - 0.5) * 1.2));
	vec3 c = mix(col_a, col_b, band) * mix(0.55, 1.0, chev);
	vec2 px = fract(uv * vec2(400.0, 24.0));
	float dots = smoothstep(0.15, 0.35, min(px.x, px.y)) * smoothstep(0.15, 0.35, min(1.0 - px.x, 1.0 - px.y));
	c = mix(c, vec3(1.0), flash * (0.5 + 0.5 * sin(TIME * 30.0)));
	ALBEDO = c * 0.2;
	EMISSION = c * energy * mix(0.4, 1.0, dots);
	ROUGHNESS = 0.3;
}
