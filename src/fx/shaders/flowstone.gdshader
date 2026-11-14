// The rock that flowed over Vasquez's drone like wax: the cave wall's own
// texture (mapped as terrain.gdshader maps it, so it runs on into the wall
// without a seam), going smooth, glossy and faintly banded where it has
// poured over the drone (COLOR.r: how much it has).
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://src/fx/shaders/sonar.gdshaderinc"

uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_rough : hint_roughness_r, filter_linear_mipmap, repeat_enable;
uniform vec3 rock_tint : source_color = vec3(0.5);
uniform vec3 rock_tint_deep : source_color = vec3(0.3);
uniform vec3 sediment_tint : source_color = vec3(0.4, 0.38, 0.34);
uniform float back_depth = 10.0;
uniform float tex_scale = 0.11;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(world_normal);
	vec3 w = pow(abs(n), vec3(4.0));
	w /= w.x + w.y + w.z;
	vec3 p = world_pos * tex_scale;
	vec3 tex = (texture(rock_albedo, p.zy) * w.x + texture(rock_albedo, p.xz) * w.y
		+ texture(rock_albedo, p.xy) * w.z).rgb;
	float rough = texture(rock_rough, p.zy).r * w.x + texture(rock_rough, p.xz).r * w.y + texture(rock_rough, p.xy).r * w.z;
	float lum = dot(tex, vec3(0.299, 0.587, 0.114));
	float front = smoothstep(-back_depth * 0.8, 1.0, world_pos.z);
	vec3 base = mix(vec3(lum), tex, 0.25) * 2.0 * mix(rock_tint_deep, rock_tint, front);
	// Where it has poured over the drone: smoothed out, a little paler, its
	// flow banded across it, and wet-looking.
	float wax = COLOR.r;
	float bands = 0.5 + 0.5 * sin(world_pos.z * 9.0 + lum * 6.0 + world_pos.x * 0.7);
	vec3 smooth_rock = mix(vec3(dot(base, vec3(0.333))), base, 0.6) * (1.12 + 0.12 * bands);
	vec3 albedo = mix(base, smooth_rock, smoothstep(0.0, 0.6, wax));
	float silt = smoothstep(0.6, 0.95, n.y + (lum - 0.4) * 0.6);
	albedo = mix(albedo, sediment_tint * (0.5 + lum * 0.6), silt * 0.45);
	ALBEDO = albedo;
	ROUGHNESS = mix(clamp(rough * 1.1, 0.55, 1.0), 0.32, smoothstep(0.0, 0.6, wax) * (1.0 - silt));
	SPECULAR = mix(0.35, 0.5, wax);
	vec2 sonar = sonar_sample(world_pos.xy);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	EMISSION = sonar_hue(world_pos.xy) * (sonar.x * 2.0 + sonar.y * 0.4) * (0.3 + fres);
}
