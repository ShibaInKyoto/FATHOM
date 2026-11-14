// The Hadal Trench's echo seen crossing open water: a sheet in the play
// plane lit along the echo's wavefront (echo_eval in sonar.gdshaderinc), so
// the slowed, word-like wave can be watched rising through the water and
// not only on the walls it charts. [code]stir[/code] is the glow welling up
// from far below before it comes.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

#include "res://src/fx/shaders/sonar.gdshaderinc"

uniform float strength = 0.22;
// 0..1: the deep stirring before the answer, a violet light welling up.
uniform float stir = 0.0;
uniform vec2 stir_from = vec2(0.0, 0.0);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 e = echo_eval(world_pos.xy);
	vec3 col = echo_color.rgb * e.x * strength;
	// The deep stirring: light welling up from below, rising in slow veils.
	if (stir > 0.0) {
		vec2 d = world_pos.xy - stir_from;
		// Strongest far below, fading out well before it reaches the sub.
		float below = exp(-length(d * vec2(0.028, 0.085)));
		float veils = 0.55 + 0.45 * sin(d.y * 0.35 - TIME * 1.2 + sin(d.x * 0.12) * 2.0);
		col += echo_color.rgb * below * veils * stir * 0.38;
	}
	ALBEDO = col;
}
