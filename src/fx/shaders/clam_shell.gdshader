// The giant clam's valves (ClamModel). Outside: chalky shell ribbed with
// growth lines (UV.x is how far out to the lip a point is), whiter at the
// newest growth by the lip, crusted with pink coralline algae and a little
// green, dusted with silt on top; barnacles (COLOR.a) a dull grey. Inside
// (seen through the gape): glossy porcelain, faintly violet at the lip.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

#include "res://src/fx/shaders/sonar.gdshaderinc"

uniform vec3 shell : source_color = vec3(0.84, 0.8, 0.72);
uniform vec3 inside : source_color = vec3(0.95, 0.94, 0.97);
uniform vec3 crust : source_color = vec3(0.72, 0.4, 0.52);
uniform vec3 sediment_tint : source_color = vec3(0.4, 0.38, 0.34);

varying vec3 obj_pos;
varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	obj_pos = VERTEX;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float clam_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n = i.x + i.y * 57.0 + i.z * 113.0;
	vec4 a = fract(sin(vec4(n, n + 1.0, n + 57.0, n + 58.0)) * 43758.5453);
	vec4 b = fract(sin(vec4(n + 113.0, n + 114.0, n + 170.0, n + 171.0)) * 43758.5453);
	vec4 z = mix(a, b, f.z);
	vec2 y = mix(z.xy, z.zw, f.y);
	return mix(y.x, y.y, f.x);
}

void fragment() {
	float r = UV.x;
	vec2 sonar = sonar_sample(world_pos.xy);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	if (FRONT_FACING) {
		// Growth lines ring the hinge, the newest out at the lip.
		float wobble = clam_noise(obj_pos * 6.0) * 1.5;
		float from_hinge = length(vec2(obj_pos.x + 1.35, obj_pos.z));
		float growth = smoothstep(0.55, 1.0, sin(from_hinge * 26.0 + wobble));
		float m = clam_noise(obj_pos * 3.0);
		vec3 base = COLOR.rgb * shell * (0.85 + 0.25 * m);
		base = mix(base, base * 1.12, smoothstep(0.75, 1.0, r));
		base *= 1.0 - growth * 0.25;
		float pink = smoothstep(0.62, 0.8, clam_noise(obj_pos * 2.6 + 5.0)) * (1.0 - COLOR.a);
		pink *= 0.6 + 0.4 * clam_noise(obj_pos * 14.0);
		base = mix(base, crust * (0.8 + 0.3 * m), pink * 0.6);
		base = mix(base, base * vec3(0.75, 0.85, 0.65), smoothstep(0.62, 0.8, clam_noise(obj_pos * 4.0 + 9.0)) * 0.5);
		base = mix(base, vec3(0.55, 0.53, 0.5), COLOR.a * 0.6);
		float silt = smoothstep(0.6, 0.95, world_normal.y) * 0.45;
		ALBEDO = mix(base, sediment_tint, silt);
		ROUGHNESS = 0.8 - growth * 0.1;
	} else {
		ALBEDO = mix(inside, vec3(0.78, 0.72, 0.92), smoothstep(0.82, 1.0, r) * 0.5);
		ROUGHNESS = 0.18;
		SPECULAR = 0.7;
	}
	EMISSION = sonar_color.rgb * (sonar.x * 2.0 + sonar.y * 0.4) * (0.3 + fres);
}
