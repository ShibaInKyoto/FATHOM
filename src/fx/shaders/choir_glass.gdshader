// The Choir's see-through flesh (its heart's skin), blended over the glowing
// chambers inside it: see choir.gdshaderinc.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, blend_mix, depth_draw_always, cull_back;

#define GLASS
#include "res://src/fx/shaders/choir.gdshaderinc"
