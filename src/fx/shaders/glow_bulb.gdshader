// A glow bulb (GlowBulb). COLOR.a is each part's material: 0 flesh (the
// roots and stalk; COLOR.r how near the bulb), 1 a sac. A sac is a fake
// translucent membrane: its light comes from the core within, brightest
// looking straight in, a bright rim where the membrane is seen edge on, dark
// veins over it; it breathes with [pulse]. [charge] (1 ripe, near 0 spent)
// dims and deflates it.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://src/fx/shaders/sonar.gdshaderinc"

uniform vec3 glow : source_color = vec3(0.4, 1.0, 0.8);
uniform vec3 flesh : source_color = vec3(0.22, 0.24, 0.2);
uniform float charge = 1.0;
uniform float pulse = 1.0;

varying vec3 obj_pos;
varying vec3 world_pos;

float gn(vec3 p) {
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
	if (COLOR.a > 0.5) {
		// Breathing, and deflating when spent.
		float swell = (pulse - 1.0) * 0.6 - (1.0 - charge) * 0.3;
		VERTEX += NORMAL * swell * COLOR.g;
	}
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float m = gn(obj_pos * 6.0);
	float into = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = pow(1.0 - into, 2.5);
	vec3 emission = vec3(0.0);
	if (COLOR.a < 0.5) {
		// Flesh: dark, wet, its veins carrying a little light up to the bulb.
		ALBEDO = flesh * (0.75 + 0.45 * m);
		ROUGHNESS = 0.35;
		float vein = 1.0 - smoothstep(0.0, 0.06, abs(gn(vec3(obj_pos.x * 9.0, obj_pos.y * 2.0, obj_pos.z * 9.0)) - 0.5));
		emission += glow * vein * COLOR.r * 0.6 * charge;
		emission += glow * fres * 0.05 * charge;
	} else {
		// A sac: the core's light through the membrane, veins dark over it.
		float veins = 1.0 - smoothstep(0.0, 0.03, abs(gn(obj_pos * 7.0) - 0.5)) * 0.75;
		float lobes = 0.85 + 0.15 * sin(atan(obj_pos.z, obj_pos.x) * 6.0 + obj_pos.y * 8.0);
		// The core: a hot heart deep inside, seen most looking straight in;
		// the membrane round it dimmer, its veins dark against the light.
		float heart = pow(into, 6.0);
		float body = mix(0.3, 0.9, into * into) * lobes;
		ALBEDO = glow * 0.08;
		ROUGHNESS = 0.3;
		SPECULAR = 0.35;
		float light = (0.15 + 2.4 * charge) * pulse;
		emission += glow * (body * veins * light + fres * (0.25 + 0.8 * charge));
		emission += mix(glow, vec3(1.0), 0.55) * heart * light * 1.4;
	}
	vec2 sonar = sonar_sample(world_pos.xy);
	EMISSION = emission + sonar_hue(world_pos.xy) * (sonar.x * 2.0 + sonar.y * 0.4) * (0.3 + fres);
}
