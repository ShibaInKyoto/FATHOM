// Flakes of obsidian (the singing glass as it bursts): glossy black glass,
// faintly rippled where it broke away, its knife edges thin enough to let
// light through. [code]ring[/code] lights those edges violet, so a fresh
// shard flashes and cools to black as it tumbles. UV.x: how far out to the
// edge a point is.
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 glow_color : source_color = vec4(0.72, 0.55, 1.0, 1.0);
uniform float ring = 0.0;

varying vec3 obj_pos;

void vertex() {
	obj_pos = VERTEX;
}

void fragment() {
	float rd = length(obj_pos.xy - vec2(-0.7, 0.1));
	vec2 dir = (obj_pos.xy - vec2(-0.7, 0.1)) / max(rd, 0.001);
	float ripple = cos(rd * 26.0) * 0.04 * exp(-rd);
	vec3 tx = normalize((VIEW_MATRIX * vec4(MODEL_MATRIX[0].xyz, 0.0)).xyz);
	vec3 ty = normalize((VIEW_MATRIX * vec4(MODEL_MATRIX[1].xyz, 0.0)).xyz);
	vec3 n = normalize(NORMAL + (tx * dir.x + ty * dir.y) * ripple);
	NORMAL = n;
	float facing = clamp(dot(n, VIEW), 0.0, 1.0);
	float fres = pow(1.0 - facing, 4.0);
	float edge = smoothstep(0.6, 1.0, UV.x);
	ALBEDO = mix(vec3(0.008, 0.0075, 0.009), vec3(0.05, 0.042, 0.04), edge * 0.5);
	ROUGHNESS = 0.04;
	SPECULAR = 0.35;
	EMISSION = glow_color.rgb * ring * (0.06 + edge * 1.4) + vec3(0.05, 0.03, 0.02) * fres;
}
