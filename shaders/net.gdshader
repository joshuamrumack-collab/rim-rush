shader_type spatial;
render_mode cull_disabled;
uniform vec3 col : source_color = vec3(1.0);
uniform vec2 cells = vec2(16.0, 6.0);
uniform float glow = 0.4;
void fragment() {
	vec2 g = abs(fract(UV * cells) - 0.5);
	float l = smoothstep(0.40, 0.46, max(g.x, g.y));
	ALBEDO = col;
	EMISSION = col * glow;
	ROUGHNESS = 0.7;
	ALPHA = l;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
