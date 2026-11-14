// The giant clam's mantle (ClamModel): a frilled lip lining each valve's
// edge, which spreads and ripples as the valves part (the top one swung
// open with its hinge), and the bed inside. Teal to violet as the angle
// changes, mottled gold-brown and freckled with bright blue-green spots; it
// glows when open. UV.x: how far up the gap between the valves a point is
// (0 on the bottom valve, 1 on the top); UV.y: how far round; COLOR.a: how
// far out from the edge it is attached to; CUSTOM0.xyz: where it sits while
// shut.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

#include "res://src/fx/shaders/sonar.gdshaderinc"

// The hinge (in the clam's space) and how far the top valve has swung.
uniform vec3 hinge = vec3(-1.35, 0.0, 0.0);
uniform float gape = 0.0;
// 0 shut to 1 wide open: how far the mantle has swelled out.
uniform float open = 0.0;
uniform float glow = 0.0;
uniform vec3 deep : source_color = vec3(0.03, 0.3, 0.42);
uniform vec3 sheen : source_color = vec3(0.24, 0.2, 0.62);
uniform vec3 mottle : source_color = vec3(0.45, 0.33, 0.12);
uniform vec3 spot : source_color = vec3(0.35, 0.95, 0.9);

varying vec3 world_pos;
varying vec3 obj_pos;
varying vec2 uv;
varying float free_edge;

void vertex() {
	uv = UV;
	float s = UV.x;
	vec3 top = CUSTOM0.xyz - hinge;
	float c = cos(gape);
	float sn = sin(gape);
	vec3 swung = hinge + vec3(top.x * c - top.y * sn, top.x * sn + top.y * c, top.z);
	vec3 out_dir = normalize(vec3(VERTEX.x, 0.0, VERTEX.z) + vec3(0.0001));
	free_edge = COLOR.a;
	// Spread out over the shell's edge, its free edge frilled and rippling.
	float e = COLOR.a;
	float frill = (0.05 * sin(UV.y * 70.0 + TIME * 1.2) + 0.03 * sin(UV.y * 23.0 - TIME * 0.7)) * e;
	float spread = (0.12 * e + frill) * open;
	VERTEX = mix(VERTEX, swung, s) + out_dir * spread;
	obj_pos = VERTEX;
	if (e > 0.0) {
		NORMAL = normalize(out_dir * 0.6 + vec3(0.0, s < 0.5 ? 1.0 : -1.0, 0.0));
	}
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float mantle_noise(vec3 p) {
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

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 1.5);
	// Wavy streaks, gold-brown mottling, and freckles of bright spots.
	vec3 p = obj_pos * 6.0;
	float wave = 0.5 + 0.5 * sin(p.x * 3.0 + sin(p.z * 2.1 + p.x) * 2.5 + free_edge * 4.0);
	float m = mantle_noise(p * 0.8);
	float freckle = smoothstep(0.74, 0.86, mantle_noise(p * 2.6 + 3.0));
	vec3 base = mix(deep, sheen, clamp(fres * 0.9 + wave * 0.3, 0.0, 1.0)) * (0.7 + 0.4 * wave);
	base = mix(base, mottle, smoothstep(0.55, 0.8, m) * 0.6);
	base = mix(base, spot, freckle * 0.85);
	// The very edge of the frill a paler band.
	base = mix(base, base * 1.4 + vec3(0.05), smoothstep(0.8, 1.0, free_edge) * 0.5);
	float eyes = freckle;
	float streak = wave;
	ALBEDO = base * COLOR.rgb;
	ROUGHNESS = 0.3;
	SPECULAR = 0.6;
	vec2 sonar = sonar_sample(world_pos.xy);
	EMISSION = (base * (0.35 + 0.65 * streak) + spot * eyes) * glow * COLOR.rgb
		+ sonar_hue(world_pos.xy) * (sonar.x * 2.0 + sonar.y * 0.4) * 0.3;
}
