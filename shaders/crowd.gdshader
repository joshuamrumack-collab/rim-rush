shader_type spatial;
// Crowd fans: each instance bounces with its own rhythm; "excite" makes them jump.
uniform float excite = 0.2;
uniform float darken = 0.0;
varying vec3 tint;
void vertex() {
	float id = float(INSTANCE_ID);
	float ph = fract(sin(id * 12.9898) * 43758.5453) * 6.283;
	float spd = 3.0 + fract(id * 0.618) * 4.0;
	float b = max(0.0, sin(TIME * spd + ph));
	VERTEX.y += b * (0.04 + excite * 0.35) * smoothstep(-0.4, 0.4, VERTEX.y + 0.4);
	VERTEX.x += sin(TIME * 2.0 + ph) * 0.03 * excite;
	tint = COLOR.rgb;
}
void fragment() {
	ALBEDO = tint * (1.0 - darken * 0.8);
	ROUGHNESS = 0.8;
}
