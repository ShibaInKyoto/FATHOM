// The creature material for something that fades into and out of the blue
// (a whale passing far behind the playfield): the same body, swim and skin
// as creature.gdshader, drawn with an instance's fade as its opacity.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, blend_mix, depth_prepass_alpha, cull_back;

#define FADE
#include "res://src/fx/shaders/creature.gdshaderinc"
