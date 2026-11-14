// Scattered boulders (and the rusted wrecks of the wreck-field event).
// Triplanar-maps the cliff texture in world space so they match the cave
// walls, and dusts upward faces with sediment. Double-sided for open hulls.
// INSTANCE_CUSTOM: y = tint blend, z = brightness.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

#include "res://src/fx/shaders/sonar.gdshaderinc"

uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_rough : hint_roughness_r, filter_linear_mipmap, repeat_enable;
uniform vec3 tint_a : source_color = vec3(1.0);
uniform vec3 tint_b : source_color = vec3(1.0);
uniform vec3 sediment_tint : source_color = vec3(0.7, 0.65, 0.5);
uniform float tex_scale = 0.35;

varying vec3 world_pos;
varying vec3 world_normal;
varying vec4 custom;

void vertex() {
	custom = INSTANCE_CUSTOM;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 triplanar_albedo(vec3 p, vec3 w) {
	return (texture(rock_albedo, p.zy) * w.x + texture(rock_albedo, p.xz) * w.y + texture(rock_albedo, p.xy) * w.z).rgb;
}

float triplanar_rough(vec3 p, vec3 w) {
	return texture(rock_rough, p.zy).r * w.x + texture(rock_rough, p.xz).r * w.y + texture(rock_rough, p.xy).r * w.z;
}

void fragment() {
	vec3 w = pow(abs(world_normal), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec3 p = world_pos * tex_scale;
	vec3 tex = triplanar_albedo(p, w);
	float rough = triplanar_rough(p, w);
	// Same desaturate-and-tint treatment as the cave walls.
	float lum = dot(tex, vec3(0.299, 0.587, 0.114));
	vec3 tint = mix(tint_a, tint_b, custom.y * 0.6);
	vec3 base = mix(vec3(lum), tex, 0.25) * 2.0 * tint * COLOR.rgb * custom.z;
	float top = smoothstep(0.6, 0.95, world_normal.y + (lum - 0.4) * 0.8);
	ALBEDO = mix(base, sediment_tint * (0.5 + lum * 0.6), top * 0.5);
	ROUGHNESS = clamp(rough + 0.15, 0.0, 1.0);
	vec2 sonar = sonar_sample(world_pos.xy);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	EMISSION = sonar_hue(world_pos.xy) * (sonar.x * 2.0 + sonar.y * 0.4) * (0.3 + fres);
}
