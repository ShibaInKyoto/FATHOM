// The Meridian Deep station (and the bones of a whale fall): painted surfaces
// (vertex COLOR.rgb) dulled by grime and dusted with silt on upward faces,
// with lit windows marked in COLOR.a (1 = steady, 0.5 = failing). Hull panel
// seams are drawn unless [seams] is 0. Catches sonar pings like the walls.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

#include "res://src/fx/shaders/sonar.gdshaderinc"

uniform vec3 sediment_tint : source_color = vec3(0.4, 0.38, 0.34);
uniform vec3 window_color : source_color = vec3(1.0, 0.78, 0.45);
uniform float steady_energy = 1.6;
uniform float failing_energy = 1.6;
uniform float seams = 1.0;
uniform float metal = 0.35;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash(vec3 p) {
	return fract(sin(dot(floor(p), vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void fragment() {
	// Panel seams and blotchy grime.
	vec3 q = world_pos * vec3(1.4, 1.4, 1.4);
	float panel = hash(q);
	float seam = smoothstep(0.04, 0.0, min(fract(world_pos.x * 0.7), fract(world_pos.y * 0.7 + 0.5)));
	float grime = 0.75 + panel * 0.25 - seam * 0.35 * seams;
	vec3 base = COLOR.rgb * grime;
	float top = smoothstep(0.55, 0.9, world_normal.y + (panel - 0.5) * 0.3);
	ALBEDO = mix(base, sediment_tint, top * 0.75);
	METALLIC = metal * (1.0 - top);
	ROUGHNESS = mix(0.45 + panel * 0.2, 0.95, top);
	float steady = step(0.75, COLOR.a);
	float failing = step(0.25, COLOR.a) * (1.0 - steady);
	vec2 sonar = sonar_sample(world_pos.xy);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	EMISSION = window_color * (steady * steady_energy + failing * failing_energy)
		+ sonar_hue(world_pos.xy) * (sonar.x * 2.0 + sonar.y * 0.4) * (0.3 + fres);
}
