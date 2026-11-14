// The Choir's hold on a member of the audience over Meridian Deep: a faint
// violet glow round it, and each time the tone shifts a ring that swells
// out through it and fades. INSTANCE_CUSTOM.r is how far the ring has
// swollen (0..1, past 1 gone), .g how strongly it is held (0..1), .b a
// steady glow round it while a pulse of the song holds it (see HushFx).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 halo_color : source_color = vec3(0.62, 0.36, 1.0);

varying vec3 pulse;

void vertex() {
	pulse = INSTANCE_CUSTOM.rgb;
}

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float t = pulse.x;
	float glow = exp(-d * d * 5.0) * 0.1;
	float ring = exp(-pow((d - t * 0.95) / (0.05 + 0.08 * t), 2.0)) * (1.0 - smoothstep(0.4, 1.0, t)) * step(t, 1.0);
	float swell = exp(-d * d * 3.0) * 0.25 * (1.0 - smoothstep(0.0, 0.5, t)) * step(t, 1.0);
	float held = exp(-d * d * 4.5) * 0.3 * pulse.z * (0.85 + 0.15 * sin(TIME * 9.0));
	ALBEDO = halo_color;
	ALPHA = clamp((glow + ring * 0.45 + swell + held) * pulse.y * (1.0 - smoothstep(0.9, 1.0, d)), 0.0, 1.0);
}
