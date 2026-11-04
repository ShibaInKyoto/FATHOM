// Soft additive light cone for the submarine's lamp. It leaves the lamp's
// glass at the glass's own width, hottest in the throat just off the lens,
// and fades along its length, towards its silhouette edges and where it meets
// scene geometry, so it reads as light scattering in water rather than a
// solid cone.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;
uniform vec4 beam_color : source_color = vec4(1.0, 0.96, 0.88, 1.0);
uniform float intensity = 0.045;
// The cone's length and the glass's radius, in metres.
uniform float beam_length = 12.0;
uniform float glass_radius = 0.065;
// How much brighter the throat just off the glass is, and how far it runs.
uniform float throat = 2.5;
uniform float throat_reach = 1.2;
uniform sampler2D noise_tex : filter_linear, repeat_enable;

varying float along;
varying vec3 local_pos;

void vertex() {
	// CylinderMesh UV.y runs from 0 at the narrow top (the lamp) to 1 at the far end.
	along = UV.y;
	local_pos = VERTEX;
}

void fragment() {
	float edge = pow(clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.5);
	float metres = clamp(along, 0.0, 1.0) * beam_length;
	// Light concentrated in the narrow throat glows brighter, easing in over
	// the first few centimetres so the cone's mouth sits on the glass.
	float mouth = smoothstep(0.0, glass_radius * 1.5, metres);
	float hot = 1.0 + throat * exp(-metres / throat_reach);
	float fall = pow(1.0 - clamp(along, 0.0, 1.0), 2.2) * mouth * hot;
	float depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	vec4 world = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float scene_z = -world.z / world.w;
	float soft = clamp((scene_z - (-VERTEX.z)) / 2.5, 0.0, 1.0);
	float dust = 0.85 + 0.3 * texture(noise_tex, local_pos.xz * 0.15 + vec2(TIME * 0.02, TIME * 0.03)).r;
	ALBEDO = beam_color.rgb;
	ALPHA = clamp(edge * fall * soft * intensity * dust, 0.0, 1.0);
}
