// Hagfish at a whale fall: pale, slimy, eyeless eels, one MultiMesh
// instance each, the body along +x (head at +x). They wriggle in a wave
// that runs back along the body and grows towards the tail.
// INSTANCE_CUSTOM: x = phase, y = how fast it is wriggling.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

#include "res://src/fx/shaders/sonar.gdshaderinc"

uniform vec3 skin : source_color = vec3(0.86, 0.7, 0.72);
uniform float body_length = 1.1;

varying vec3 world_pos;

void vertex() {
	float phase = INSTANCE_CUSTOM.x * 6.2831;
	float beat = 4.0 + INSTANCE_CUSTOM.y * 4.0;
	float back = clamp(0.5 - VERTEX.x / body_length, 0.0, 1.0);
	VERTEX.z += sin(VERTEX.x / body_length * 7.0 + TIME * beat + phase) * (0.02 + 0.1 * back * back);
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Darker along the back, a pale belly, and a wet sheen.
	ALBEDO = skin * mix(0.7, 1.1, COLOR.g);
	ROUGHNESS = 0.28;
	SPECULAR = 0.6;
	vec2 sonar = sonar_sample(world_pos.xy);
	EMISSION = sonar_color.rgb * (sonar.x * 2.0 + sonar.y * 0.4) * 0.3;
}
