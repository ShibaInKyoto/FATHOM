// A loose stalactite (Stalactite): wet calcite dripstone. COLOR.r is how far
// down the spike a point is (0 at the ceiling, 1 at the tip), COLOR.g a
// shade of its own. Pale banded calcite, cream to tan in the growth rings,
// stained darker down the flutes where the water ran; glossy and wet, a
// little translucent towards the tip, where the light of the drip
// ([drip_color], [drip]) glows through it; the cave's silt near the root.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://src/fx/shaders/sonar.gdshaderinc"

uniform vec3 calcite : source_color = vec3(0.78, 0.74, 0.66);
uniform vec3 rock_tint : source_color = vec3(0.5);
uniform vec3 sediment_tint : source_color = vec3(0.4, 0.38, 0.34);
uniform vec3 drip_color : source_color = vec3(0.4, 1.0, 0.8);
// How bright the drip is (it flares as the spike shakes loose).
instance uniform float drip = 1.0;

varying vec3 obj_pos;
varying vec3 world_pos;

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
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float down = COLOR.r;
	float m = dn(obj_pos * 3.0);
	float fine = dn(obj_pos * 17.0);
	// Growth rings, tan and cream.
	float bands = 0.5 + 0.5 * sin(obj_pos.y * 26.0 + m * 4.0);
	vec3 c = mix(calcite, calcite * vec3(0.86, 0.76, 0.62), bands * 0.6);
	c = mix(c, rock_tint * 1.2, (1.0 - smoothstep(0.0, 0.3, down)) * 0.5);
	// Stains run down the flutes.
	float stain = smoothstep(0.45, 0.8, dn(vec3(obj_pos.x * 9.0, obj_pos.y * 0.9, obj_pos.z * 9.0)));
	c *= 1.0 - stain * 0.35 - COLOR.g * 0.15;
	c *= 0.85 + 0.25 * fine;
	// Silt dusting the root.
	c = mix(c, sediment_tint * (0.7 + 0.3 * fine), (1.0 - smoothstep(0.05, 0.35, down)) * 0.55);
	// Popcorn calcite: a fine knobbly texture over it, in the light.
	float knobs = dn(obj_pos * 22.0);
	c *= 0.88 + 0.22 * knobs;
	// Bumped without tangents (surface gradient from screen derivatives).
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	vec3 r1 = cross(dpdy, NORMAL);
	vec3 r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dFdx(knobs) * r1 + dFdy(knobs) * r2);
	NORMAL = normalize(abs(det) * NORMAL - grad * 0.006);
	ALBEDO = c;
	ROUGHNESS = mix(0.55, 0.22, smoothstep(0.2, 0.9, down)) + fine * 0.1;
	SPECULAR = 0.6;
	// The drip's light glowing through the tip, and a wet sheen at the rim.
	float into = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = pow(1.0 - into, 3.0);
	float glow = smoothstep(0.7, 1.0, down);
	vec3 emission = drip_color * glow * glow * (0.25 + 0.6 * drip) * (0.6 + 0.4 * fres);
	emission += calcite * fres * 0.06;
	vec2 sonar = sonar_sample(world_pos.xy);
	EMISSION = emission + sonar_hue(world_pos.xy) * (sonar.x * 2.0 + sonar.y * 0.4) * (0.3 + fres);
}
