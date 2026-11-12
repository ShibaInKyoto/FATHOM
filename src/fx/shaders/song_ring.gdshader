// An expanding wave of the Choir's song: a bright band on a quad, its front
// at UV radius [member front] (1.0 the quad's edge), [member band] wide
// either side (the same width in metres whatever the wave's size), a faint
// wash behind it.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 ring_color : source_color = vec4(1.0, 0.3, 0.9, 1.0);
uniform float intensity = 2.0;
uniform float front = 0.9;
uniform float band = 0.03;

void fragment() {
	float r = length(UV * 2.0 - 1.0);
	float ring = exp(-pow((r - front) / band, 2.0));
	float inner = smoothstep(front * 0.6, front, r) * (1.0 - smoothstep(front, front + band, r)) * 0.12;
	float ripple = 0.75 + 0.25 * sin(atan(UV.y - 0.5, UV.x - 0.5) * 24.0 + TIME * 3.0);
	ALBEDO = ring_color.rgb;
	float outside = 1.0 - smoothstep(front + band * 1.6, front + band * 2.2, r);
	ALPHA = clamp((ring * ripple + inner) * intensity * ring_color.a * outside, 0.0, 1.0);
}
