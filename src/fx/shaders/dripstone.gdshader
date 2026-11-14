// A loose stalactite (StalactiteModel): COLOR.r how far down the spike a
// point is (0 at the ceiling, 1 at the tip), COLOR.g the flutes, COLOR.b
// the part (0 spike, 0.5 the plug of ceiling rock, 1 a soda straw), COLOR.a
// how near the plug's crack. The plug is the cave's own rock (mapped as the
// terrain maps it), the spike growing out of it into wet calcite: banded in
// its growth, stained with iron down its flutes, bumped with the rock's own
// grain, glossy, the light of the drip ([drip_color], [drip]) glowing
// through its translucent tip; silt on the root; the crack dark, opening
// with [crack] as it comes loose.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://src/fx/shaders/sonar.gdshaderinc"

uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 rock_tint : source_color = vec3(0.5);
uniform vec3 calcite : source_color = vec3(0.8, 0.76, 0.68);
uniform vec3 sediment_tint : source_color = vec3(0.4, 0.38, 0.34);
uniform vec3 drip_color : source_color = vec3(0.4, 1.0, 0.8);
uniform float tex_scale = 0.35;
instance uniform float drip = 1.0;
instance uniform float crack = 0.0;

varying vec3 obj_pos;
varying vec3 obj_n;
varying vec3 world_pos;
varying vec3 world_normal;

float dn(vec3 p) {
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

// The rock's grain, mapped on three planes in its own space (so it rides
// with it when it falls).
vec3 grain(vec3 p, vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= w.x + w.y + w.z;
	vec3 q = p * tex_scale;
	return (texture(rock_albedo, q.zy) * w.x + texture(rock_albedo, q.xz) * w.y + texture(rock_albedo, q.xy) * w.z).rgb;
}

void fragment() {
	float down = COLOR.r;
	float part = COLOR.b;
	vec3 tex = grain(obj_pos, normalize(obj_n));
	float lum = dot(tex, vec3(0.299, 0.587, 0.114));
	float m = dn(obj_pos * 2.5);
	float fine = dn(obj_pos * 12.0);
	vec3 rock = mix(vec3(lum), tex, 0.3) * 1.9 * rock_tint;
	vec3 c;
	float rough;
	float glossy;
	if (part > 0.25 && part < 0.75) {
		// The plug: ceiling rock, its crack dark round the rim.
		c = rock * (0.85 + 0.3 * m);
		float rim = COLOR.a;
		c *= 1.0 - smoothstep(0.75, 1.0, rim) * (0.6 + 0.35 * crack);
		c = mix(c, sediment_tint * (0.6 + 0.4 * lum), smoothstep(0.3, 0.8, m) * 0.35);
		rough = 0.9;
		glossy = 0.0;
	} else {
		// Calcite: the root still rock-coloured, growing paler and cleaner
		// towards the tip, banded with its growth.
		float bands = 0.5 + 0.5 * sin(obj_pos.y * 30.0 + lum * 5.0 + m * 3.0);
		vec3 cal = mix(calcite, calcite * vec3(0.9, 0.8, 0.66), bands * 0.45);
		cal *= 0.82 + 0.35 * lum;
		c = mix(rock * 1.1, cal, smoothstep(0.02, 0.35, down));
		// Iron staining down the flutes.
		float iron = smoothstep(0.55, 0.85, dn(vec3(obj_pos.x * 14.0, obj_pos.y * 0.8, obj_pos.z * 14.0)));
		iron *= COLOR.g * smoothstep(0.1, 0.4, down) * (1.0 - smoothstep(0.75, 0.95, down));
		c = mix(c, vec3(0.55, 0.3, 0.14), iron * 0.55);
		// Silt on the root.
		c = mix(c, sediment_tint * (0.7 + 0.3 * fine), (1.0 - smoothstep(0.0, 0.25, down)) * 0.4);
		glossy = smoothstep(0.15, 0.9, down);
		rough = mix(0.6, 0.18, glossy) + fine * 0.08;
		if (part > 0.75) {
			c = calcite * 1.05;
			glossy = 1.0;
			rough = 0.12;
		}
	}
	// The rock's grain, bumped in (without tangents: a surface gradient).
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	vec3 r1 = cross(dpdy, NORMAL);
	vec3 r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	float h = lum + fine * 0.3;
	vec3 grad = sign(det) * (dFdx(h) * r1 + dFdy(h) * r2);
	NORMAL = normalize(abs(det) * NORMAL - grad * 0.02);
	ALBEDO = c;
	ROUGHNESS = rough;
	SPECULAR = mix(0.4, 0.75, glossy);
	// Translucent towards the tip: light comes through it.
	BACKLIGHT = calcite * 0.35 * glossy;
	float into = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = pow(1.0 - into, 3.0);
	float glow = smoothstep(0.72, 1.0, down) * step(part, 0.25) + step(0.75, part) * 0.4;
	vec3 emission = drip_color * glow * glow * (0.2 + 0.7 * drip) * (0.5 + 0.5 * fres);
	vec2 sonar = sonar_sample(world_pos.xy);
	EMISSION = emission + sonar_hue(world_pos.xy) * (sonar.x * 2.0 + sonar.y * 0.4) * (0.3 + fres);
}
