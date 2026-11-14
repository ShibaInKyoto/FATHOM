// Small Meridian Deep hardware (the log beacons, the survey probes): COLOR.a
// is each part's material: 0 paint (COLOR.rgb its colour), 0.2 bare metal
// (COLOR.r a tint), 0.3 dark plastic and rubber, 0.6 a lens (COLOR.r 1 if it
// is the lamp), 0.8 reflective tape. Years down: the paint scuffed and
// chipped at its edges, grimed in patches, rust weeping from the metal,
// silt on whatever faces up. The lamp glows [lamp_color] by [lamp].
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://src/fx/shaders/sonar.gdshaderinc"

uniform vec3 sediment_tint : source_color = vec3(0.4, 0.38, 0.34);
uniform vec3 lamp_color : source_color = vec3(0.4, 1.0, 0.6);
uniform float lamp = 0.0;
// How fine its wear is (higher for smaller things).
uniform float detail = 6.0;

varying vec3 obj_pos;
varying vec3 obj_n;
varying vec3 world_pos;
varying vec3 world_normal;

float en(vec3 p) {
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
	obj_n = NORMAL;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float kind = COLOR.a;
	vec3 p = obj_pos * detail;
	float m = en(p * 0.5);
	float fine = en(p * 3.0);
	vec3 albedo;
	float rough = 0.6;
	float metal = 0.0;
	vec3 emission = vec3(0.0);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	float dusts = 1.0;
	if (kind < 0.1) {
		vec3 c = COLOR.rgb;
		// Chips where it has been knocked: its edges, and here and there.
		vec3 an = abs(normalize(obj_n));
		float edge = 1.0 - max(an.x, max(an.y, an.z));
		float chips = smoothstep(0.72, 0.78, en(p * 2.2) * 0.6 + fine * 0.3 + edge * 0.45);
		float scuff = smoothstep(0.6, 0.9, en(vec3(p.x * 0.6, p.y * 6.0, p.z * 6.0)));
		c = mix(c, vec3(0.32, 0.31, 0.3), chips);
		c *= (0.78 + 0.3 * m) * (1.0 - scuff * 0.25);
		albedo = c;
		rough = mix(0.5, 0.8, chips + scuff * 0.4);
	} else if (kind < 0.25) {
		float rust = smoothstep(0.45, 0.8, m * 0.6 + fine * 0.4);
		albedo = mix(vec3(0.5, 0.52, 0.54) * COLOR.r, vec3(0.36, 0.16, 0.06), rust * 0.8);
		rough = mix(0.35, 0.85, rust);
		metal = 0.8 * (1.0 - rust);
	} else if (kind < 0.45) {
		albedo = vec3(0.05, 0.05, 0.055) * (0.8 + 0.4 * m);
		rough = 0.7;
	} else if (kind < 0.7) {
		albedo = vec3(0.12, 0.2, 0.15) * (0.5 + 0.5 * COLOR.r);
		rough = 0.08;
		emission += lamp_color * COLOR.r * (0.15 + 6.0 * lamp);
		emission += vec3(0.4) * fres * 0.1;
		dusts = 0.0;
	} else {
		// Reflective tape: catches the sub's lamp.
		albedo = vec3(0.85, 0.86, 0.82) * (0.85 + 0.15 * fine);
		rough = 0.25;
		metal = 0.4;
		emission += vec3(0.5) * pow(clamp(dot(NORMAL, VIEW), 0.0, 1.0), 6.0) * 0.12;
	}
	// Silt on whatever faces up, a film of growth in patches.
	float silt = smoothstep(0.5, 0.9, normalize(world_normal).y + (m - 0.5) * 0.5) * dusts;
	albedo = mix(albedo, sediment_tint * (0.7 + 0.3 * fine), silt * 0.7);
	float film = smoothstep(0.62, 0.8, en(p * 0.3 + 4.0)) * dusts;
	albedo = mix(albedo, vec3(0.22, 0.24, 0.18), film * 0.45);
	ALBEDO = albedo;
	ROUGHNESS = mix(rough, 0.95, silt);
	METALLIC = metal * (1.0 - silt);
	vec2 sonar = sonar_sample(world_pos.xy);
	EMISSION = emission + sonar_hue(world_pos.xy) * (sonar.x * 2.0 + sonar.y * 0.4) * (0.3 + fres);
}
