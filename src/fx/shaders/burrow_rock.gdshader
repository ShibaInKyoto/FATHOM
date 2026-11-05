// Rock for things built into the cave face (a burrow's rim): the terrain's
// photo rock, projected from all three sides, desaturated and tinted the
// same way (see terrain.gdshader), darkened by vertex color towards a hole.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_rough : hint_roughness_r, filter_linear_mipmap, repeat_enable;
uniform vec3 rock_tint : source_color = vec3(0.5);
uniform float tex_scale = 0.11;
// A glow deep in the hole (vertex color alpha below one marks the throat).
uniform vec3 throat_glow : source_color = vec3(0.0);

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(world_normal);
	vec3 blend = pow(abs(n), vec3(4.0));
	blend /= dot(blend, vec3(1.0));
	vec3 alb = texture(rock_albedo, world_pos.zy * tex_scale).rgb * blend.x
		+ texture(rock_albedo, world_pos.xz * tex_scale).rgb * blend.y
		+ texture(rock_albedo, world_pos.xy * tex_scale).rgb * blend.z;
	float rough = texture(rock_rough, world_pos.zy * tex_scale).r * blend.x
		+ texture(rock_rough, world_pos.xz * tex_scale).r * blend.y
		+ texture(rock_rough, world_pos.xy * tex_scale).r * blend.z;
	float lum = dot(alb, vec3(0.299, 0.587, 0.114));
	ALBEDO = mix(vec3(lum), alb, 0.25) * 2.0 * rock_tint * COLOR.rgb;
	ROUGHNESS = clamp(rough * 1.1, 0.55, 1.0);
	SPECULAR = 0.35;
	EMISSION = throat_glow * (1.0 - COLOR.a);
}
