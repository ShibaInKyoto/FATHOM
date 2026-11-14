// Bone-eating worms on a whale fall: tufts of blood-red plumes on pale
// stalks, growing out of the bone (one MultiMesh instance per tuft). UV.y is
// how far along its plume a point is. Each tuft stirs and breathes on its
// own (INSTANCE_CUSTOM.x its phase).
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

#include "res://src/fx/shaders/sonar.gdshaderinc"

uniform vec3 plume : source_color = vec3(0.92, 0.12, 0.1);
uniform vec3 stalk : source_color = vec3(0.85, 0.66, 0.6);
uniform float glow = 1.4;
uniform float stir = 0.025;

varying float phase;
varying float tip;
varying vec3 world_pos;

void vertex() {
	phase = INSTANCE_CUSTOM.x * 6.2831;
	tip = UV.y;
	float t = TIME * 0.7 + phase;
	VERTEX.x += sin(t + VERTEX.y * 9.0) * stir * tip * tip;
	VERTEX.z += cos(t * 0.8 + phase) * stir * tip * tip;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float red = smoothstep(0.35, 0.65, tip);
	ALBEDO = mix(stalk, plume, red);
	ROUGHNESS = 0.5;
	float breathe = 0.8 + 0.2 * sin(TIME * 1.1 + phase);
	vec2 sonar = sonar_sample(world_pos.xy);
	EMISSION = plume * glow * red * breathe + sonar_hue(world_pos.xy) * (sonar.x * 2.0 + sonar.y * 0.4) * 0.3;
}
