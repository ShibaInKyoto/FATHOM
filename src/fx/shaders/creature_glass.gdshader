// The creature material for see-through flesh (glass fish, ghosts of the
// trench): the same body, swim and skin as creature.gdshader, blended over
// what lies behind it. Bones and organs drawn inside with the solid
// material show through it.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, blend_mix, depth_draw_always, cull_back;

#define GLASS
#include "res://src/fx/shaders/creature.gdshaderinc"
