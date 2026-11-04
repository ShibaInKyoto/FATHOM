shader_type canvas_item;
// The splash's rising water: a dark sea climbing the screen from below. Above
// its wavy surface nothing is drawn but the bright line where water meets air;
// below it, whatever was drawn first is seen through the water, wavering,
// tinted and dimmed with depth.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
// Height of the surface, 0 at the top of the screen and 1 at the bottom.
uniform float level = 1.1;
// How much warm flame light glances off the surface, and where.
uniform float warm = 0.0;
uniform float flame_x = 0.5;
// Rings spreading from the flame where the water put it out.
uniform float stir = 0.0;
uniform vec3 shallow : source_color = vec3(0.02, 0.075, 0.1);
uniform vec3 deep : source_color = vec3(0.003, 0.013, 0.022);

void fragment() {
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float px = SCREEN_PIXEL_SIZE.y;
	float x = UV.x * aspect;
	float dx = (UV.x - flame_x) * aspect;
	float surf = level
		+ 0.006 * sin(x * 7.0 + TIME * 1.9)
		+ 0.003 * sin(x * 17.0 - TIME * 2.7)
		+ 0.0015 * sin(x * 41.0 + TIME * 4.3)
		+ stir * 0.012 * exp(-abs(dx) * 4.0) * sin(abs(dx) * 70.0 - TIME * 13.0);
	float d = UV.y - surf;
	float edge = 1.0 - smoothstep(0.0, px * 3.0, abs(d));
	float flare = clamp(warm * exp(-dx * dx * 30.0), 0.0, 1.0);
	vec3 edge_col = mix(vec3(0.5, 0.75, 0.88), vec3(1.0, 0.8, 0.52), flare);
	if (d < 0.0) {
		COLOR = vec4(edge_col, edge * (0.6 + 0.4 * flare));
	} else {
		vec2 wob = vec2(sin(UV.y * 60.0 + TIME * 2.3), sin(x * 40.0 + TIME * 1.7)) * px * 4.0;
		vec3 seen = textureLod(screen_tex, SCREEN_UV + wob, clamp(d * 6.0, 0.0, 1.2)).rgb;
		float depth = clamp(d * 2.4, 0.0, 1.0);
		vec3 col = mix(shallow, deep, depth) + seen * mix(vec3(0.36, 0.56, 0.66), vec3(0.17, 0.3, 0.38), depth);
		// Light shimmering just under the surface.
		float c = sin(x * 23.0 + TIME * 1.3 + sin(UV.y * 31.0 - TIME)) * sin(x * 13.0 - TIME * 0.9 + UV.y * 19.0);
		col += vec3(0.22, 0.42, 0.52) * pow(abs(c), 6.0) * exp(-d * 18.0) * 0.5;
		// The flame's glow caught in the water beneath it.
		col += vec3(1.0, 0.72, 0.42) * flare * exp(-d * 14.0) * 0.22;
		col = mix(col, edge_col, edge * 0.8);
		COLOR = vec4(col, 1.0);
	}
}
