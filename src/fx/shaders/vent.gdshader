// A thermal vent (VentModel). COLOR.a is each part's material: 0 the mound
// of sulfide rock, 0.2 a chimney (COLOR.r how far up it), 0.4 a glowing
// throat (COLOR.r how near its mouth), 0.6 a worm's tube, 0.8 a worm's
// plume. The rock is the cave's own (mapped as terrain.gdshader maps it, so
// the mound runs on into the floor), blackened by sulfide, crusted yellow
// with sulfur and stained rust-orange round the chimneys, white with
// bacterial mats in patches; veins of heat glow through the mound and up
// the chimneys, brightening with [heat] as it builds to an eruption.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://src/fx/shaders/sonar.gdshaderinc"

uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 rock_tint : source_color = vec3(0.5);
uniform vec3 sediment_tint : source_color = vec3(0.4, 0.38, 0.34);
uniform vec3 heat_color : source_color = vec3(1.0, 0.42, 0.12);
uniform float tex_scale = 0.11;
// 0 cool, about 0.25 at rest, 1 erupting.
uniform float heat = 0.25;

varying vec3 world_pos;
varying vec3 world_normal;
varying vec3 obj_pos;

float vn(vec3 p) {
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

void vertex() {
	obj_pos = VERTEX;
	// The plumes flutter in the warm current.
	if (COLOR.a > 0.7) {
		float ph = COLOR.r * 6.28 + TIME * 3.1;
		VERTEX.x += sin(ph + VERTEX.y * 20.0) * 0.012;
		VERTEX.z += cos(ph * 1.3 + VERTEX.y * 17.0) * 0.01;
	}
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float kind = COLOR.a;
	vec3 n = normalize(world_normal);
	vec3 w = pow(abs(n), vec3(4.0));
	w /= w.x + w.y + w.z;
	vec3 tp = world_pos * tex_scale;
	vec3 tex = (texture(rock_albedo, tp.zy) * w.x + texture(rock_albedo, tp.xz) * w.y
		+ texture(rock_albedo, tp.xy) * w.z).rgb;
	float lum = dot(tex, vec3(0.299, 0.587, 0.114));
	float m = vn(obj_pos * 3.0);
	float fine = vn(obj_pos * 14.0);
	vec3 albedo;
	float rough = 0.8;
	vec3 emission = vec3(0.0);
	float flicker = 0.85 + 0.15 * sin(TIME * 23.0 + obj_pos.x * 9.0) * sin(TIME * 7.0);
	if (kind < 0.1) {
		// The mound: the floor's rock, blackening towards the chimneys.
		vec3 rock = mix(vec3(lum), tex, 0.3) * 1.8 * rock_tint;
		float dist = length(obj_pos.xz * vec2(0.8, 1.0));
		float near = 1.0 - smoothstep(0.3, 1.5, dist);
		vec3 sulfide = vec3(0.075, 0.07, 0.065) * (0.7 + 0.6 * lum);
		albedo = mix(rock, sulfide, near * 0.85);
		// Mineral staining round the chimneys: rust browns, a little sulfur.
		float stain = vn(obj_pos * 2.5 + 7.0) * 0.6 + fine * 0.4;
		albedo = mix(albedo, vec3(0.28, 0.16, 0.08), smoothstep(0.5, 0.8, stain) * near * 0.5);
		albedo = mix(albedo, vec3(0.55, 0.47, 0.16), smoothstep(0.7, 0.9, stain) * (1.0 - smoothstep(0.15, 0.6, dist)) * 0.4);
		float mat = 0.0;
		// Hairline cracks of heat near the chimneys.
		float vein = 1.0 - smoothstep(0.0, 0.025, abs(vn(obj_pos * 6.0) - 0.5));
		emission += heat_color * vein * (1.0 - smoothstep(0.1, 0.9, dist)) * (0.15 + 3.0 * heat) * flicker;
		rough = mix(0.85, 0.95, mat);
	} else if (kind < 0.3) {
		// A chimney: black sulfide streaked down from its lip with rust and
		// sulfur, white anhydrite crusting the lip where it grew last.
		float up = COLOR.r;
		vec3 c = vec3(0.065, 0.06, 0.055) * (0.75 + 0.6 * lum + 0.3 * m);
		float streak = vn(vec3(obj_pos.x * 18.0, obj_pos.y * 1.5, obj_pos.z * 18.0));
		c = mix(c, vec3(0.3, 0.15, 0.06), smoothstep(0.55, 0.85, streak) * 0.55 * smoothstep(0.2, 0.9, up));
		c = mix(c, vec3(0.6, 0.5, 0.14), smoothstep(0.75, 0.95, streak) * 0.45 * smoothstep(0.6, 1.0, up));
		float anhydrite = smoothstep(0.93, 1.0, up) * smoothstep(0.35, 0.6, fine);
		c = mix(c, vec3(0.8, 0.78, 0.72), anhydrite * 0.6);
		albedo = c;
		rough = 0.75;
		// Heat glowing through its cracks, rising up it.
		float crack = 1.0 - smoothstep(0.0, 0.025, abs(vn(vec3(obj_pos.x * 9.0, obj_pos.y * 3.0, obj_pos.z * 9.0)) - 0.5));
		emission += heat_color * crack * (0.15 + 2.5 * heat) * smoothstep(0.1, 0.9, up) * flicker;
	} else if (kind < 0.5) {
		// The throat: incandescent, flickering.
		albedo = vec3(0.1, 0.03, 0.01);
		emission += heat_color * (0.8 + 7.0 * heat) * (0.4 + 0.6 * COLOR.r) * flicker;
	} else if (kind < 0.7) {
		// A worm's tube: chitin, white, ringed.
		float rings = 0.85 + 0.15 * sin(obj_pos.y * 120.0);
		albedo = vec3(0.84, 0.82, 0.76) * rings * (0.85 + 0.15 * COLOR.r);
		rough = 0.5;
	} else {
		// A plume: blood red.
		albedo = vec3(0.75, 0.05, 0.06);
		emission += vec3(0.6, 0.02, 0.04) * 0.08;
		rough = 0.45;
	}
	// Silt where it lies flat and cool.
	float silt = smoothstep(0.7, 0.95, n.y) * step(kind, 0.1) * (1.0 - heat) * 0.4;
	albedo = mix(albedo, sediment_tint * (0.6 + 0.4 * lum), silt);
	ALBEDO = albedo;
	ROUGHNESS = rough;
	vec2 sonar = sonar_sample(world_pos.xy);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	EMISSION = emission + sonar_hue(world_pos.xy) * (sonar.x * 2.0 + sonar.y * 0.4) * (0.3 + fres);
}
