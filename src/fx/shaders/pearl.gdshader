// A pearl: white nacre shimmering pink and green as it turns from the eye,
// glowing from within.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform float glow = 0.0;

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 1.6);
	vec3 nacre = mix(vec3(1.0, 0.97, 0.98), mix(vec3(1.0, 0.8, 0.9), vec3(0.8, 1.0, 0.92), NORMAL.y * 0.5 + 0.5), fres);
	ALBEDO = nacre;
	ROUGHNESS = 0.12;
	SPECULAR = 0.8;
	EMISSION = nacre * glow * (0.6 + 0.4 * (1.0 - fres));
}
