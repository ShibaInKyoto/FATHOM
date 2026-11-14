// Bones lying on the sea floor (the whale fall). Vertex COLOR.rgb is the
// bone's own colour, already stained where it lay in the silt. On top of
// that: pitted and porous, blotched rust-brown and grey-green, filmed with
// pale slimy bacterial mats on its upper faces, and dusted with silt.
// Catches sonar pings like the walls.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

#include "res://src/fx/shaders/sonar.gdshaderinc"

uniform vec3 sediment_tint : source_color = vec3(0.4, 0.38, 0.34);
uniform vec3 film_color : source_color = vec3(0.93, 0.9, 0.76);
// How much of the bone the bacterial film covers, and how it glows.
uniform float film = 0.6;
uniform float film_glow = 0.05;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float bone_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n = i.x + i.y * 57.0 + i.z * 113.0;
	vec4 a = fract(sin(vec4(n, n + 1.0, n + 57.0, n + 58.0)) * 43758.5453);
	vec4 b = fract(sin(vec4(n + 113.0, n + 114.0, n + 170.0, n + 171.0)) * 43758.5453);
	vec4 z = mix(a, b, f.z);
	vec2 y = mix(z.xy, z.zw, f.y);
	return mix(y.x, y.y, f.x);
}

// Bends the normal by the screen-space slope of a height field h.
vec3 bone_bumped(vec3 n, vec3 view_pos, float h) {
	vec3 dpx = dFdx(view_pos);
	vec3 dpy = dFdy(view_pos);
	vec3 r1 = cross(dpy, n);
	vec3 r2 = cross(n, dpx);
	float det = dot(dpx, r1);
	if (abs(det) < 1e-8) {
		return n;
	}
	return normalize(n - (dFdx(h) * r1 + dFdy(h) * r2) / det);
}

void fragment() {
	vec3 p = world_pos;
	// Fine pores: two layers of noise, turned against each other so they
	// don't line up into blocks.
	vec3 q = vec3(p.x * 0.8 + p.z * 0.6, p.y, p.z * 0.8 - p.x * 0.6);
	float grain = bone_noise(p * 23.0) * 0.55 + bone_noise(q * 41.0) * 0.45;
	float pore = smoothstep(0.66, 0.8, grain);
	float blotch = bone_noise(p * 1.7 + 4.0) * 0.7 + bone_noise(q * 3.9) * 0.3;
	// Aged ivory: yellowed and browned, never clean white.
	vec3 base = COLOR.rgb * vec3(0.93, 0.88, 0.76) * (0.8 + 0.25 * bone_noise(p * 4.3));
	base = mix(base, base * vec3(0.78, 0.6, 0.42), smoothstep(0.5, 0.85, blotch) * 0.7);
	base = mix(base, base * vec3(0.72, 0.8, 0.68), smoothstep(0.6, 0.9, bone_noise(q * 2.3 + 11.0)) * 0.45);
	base *= 1.0 - pore * 0.28;
	float up = world_normal.y;
	float mats = smoothstep(0.56, 0.7, bone_noise(p * 1.25 + 7.0) * 0.7 + bone_noise(p * 5.0) * 0.3)
		* smoothstep(-0.1, 0.5, up) * film;
	float silt = smoothstep(0.55, 0.9, up + (blotch - 0.5) * 0.4) * (1.0 - mats);
	vec3 albedo = mix(base, film_color * (0.85 + 0.15 * bone_noise(p * 9.0)), mats);
	albedo = mix(albedo, sediment_tint, silt * 0.55);
	NORMAL = bone_bumped(NORMAL, VERTEX, -pore * 0.004 + mats * 0.005);
	ALBEDO = albedo;
	ROUGHNESS = mix(0.75, 0.32, mats);
	SPECULAR = 0.35;
	vec2 sonar = sonar_sample(world_pos.xy);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	EMISSION = film_color * mats * film_glow + sonar_hue(world_pos.xy) * (sonar.x * 2.0 + sonar.y * 0.4) * (0.3 + fres);
}
