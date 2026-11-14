// Crystals coating the singing glass (GlassCrystals): dark violet quartz,
// glossy and flat-faced, their bevels and edges catching the light, each
// lit from a glowing core along its axis that shifts as the view moves, its
// tip brightest. Ringing, they light up (a ripple of light running out from
// the strike); cracked, fractures glow inside them.
// UV.x: how far up the crystal (0 base, 1 tip); UV.y: 1 on a bevel;
// CUSTOM0: base xyz, radius; CUSTOM1: axis xyz, length.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_back;

#include "res://src/fx/shaders/sonar.gdshaderinc"

uniform vec3 glow_color : source_color = vec3(0.72, 0.55, 1.0);
// The light within at rest, and as it rings.
uniform float rest_glow = 0.25;
uniform float ring = 0.0;
uniform float ringing = 0.0;
uniform float note = 1.0;
// xyz: where the last note struck (world), w: when (sonar_time).
uniform vec4 strike = vec4(0.0, 0.0, 0.0, -100.0);
// When it cracked (sonar_time), or -1.
uniform float crack_time = -1.0;

varying vec3 world_pos;
varying vec3 world_n;
varying vec4 base;
varying vec4 axis;
varying vec2 uv;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// (Through the model's transform, so a flying shard's core moves with it.)
	float scale = length(MODEL_MATRIX[0].xyz);
	base = vec4((MODEL_MATRIX * vec4(CUSTOM0.xyz, 1.0)).xyz, CUSTOM0.w * scale);
	axis = vec4(normalize(mat3(MODEL_MATRIX) * CUSTOM1.xyz), CUSTOM1.w * scale);
	uv = UV;
}

float crystal_hash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

void fragment() {
	vec3 view_w = normalize(CAMERA_POSITION_WORLD - world_pos);
	vec3 n = normalize(world_n);
	float facing = clamp(dot(n, view_w), 0.0, 1.0);
	float fres = pow(1.0 - facing, 3.0);
	float h = uv.x;
	float own = crystal_hash(base.xyz);
	// The core: how near the eye's ray through the crystal passes its axis.
	vec3 d = -view_w;
	vec3 a = normalize(axis.xyz);
	vec3 w0 = world_pos - base.xyz;
	float b = dot(d, a);
	float denom = max(1.0 - b * b, 1e-4);
	float t = max((b * dot(a, w0) - dot(d, w0)) / denom, 0.0);
	float s = clamp((dot(a, w0) - b * dot(d, w0)) / denom, 0.0, axis.w);
	float dist = length(world_pos + d * t - (base.xyz + a * s));
	float core = exp(-pow(dist / (base.w * 0.6), 2.0));
	float along = s / axis.w;
	// Dark violet quartz, paler towards the tip, each crystal its own shade.
	// Dark at the root, where they crowd each other; clearer to the tip.
	float root = 0.2 + 0.8 * smoothstep(0.0, 0.55, h);
	vec3 albedo = mix(vec3(0.02, 0.01, 0.035), vec3(0.16, 0.1, 0.26), h * h) * (0.6 + 0.7 * own) * root;
	// Each face its own brightness, as if lit from one side within, so the
	// facets read crisp even in the dark.
	float face = 0.3 + 0.95 * pow(max(dot(n, normalize(vec3(-0.45, 0.6, 0.65))), 0.0), 2.0);
	ALBEDO = albedo * (0.6 + 0.6 * face);
	ROUGHNESS = mix(0.05, 0.025, uv.y);
	SPECULAR = 0.6;
	// Faint growth lines across its faces.
	float lines = smoothstep(0.85, 1.0, sin(h * axis.w * 70.0 + own * 6.0));
	float lit = rest_glow * (0.6 + 0.8 * own) + ring;
	// The light gathers in the tip.
	vec3 glow = glow_color * core * (0.06 + 1.2 * along * along * along) * lit * face;
	glow += glow_color * face * h * h * 0.06 * lit;
	glow += glow_color * fres * (0.05 + 0.6 * ring) * h * root;
	glow += mix(glow_color, vec3(1.0), 0.5) * uv.y * fres * 0.25 * root;
	glow += glow_color * lines * 0.04 * lit;
	// Struck: a ripple of light runs out across them from the strike.
	float age = sonar_time - strike.w;
	if (age > 0.0 && age < 1.6) {
		float rr = length(world_pos.xy - strike.xy);
		float front = exp(-pow((rr - age * 5.5) / 0.35, 2.0));
		glow += glow_color * front * (1.0 - age / 1.6) * (1.5 + h);
	}
	// Ringing: they shimmer at the note.
	glow *= 1.0 + ringing * 0.35 * sin(TIME * (22.0 + 14.0 * note) + own * 6.28);
	// Cracked: a fracture runs through each, glowing white-violet.
	if (crack_time > 0.0) {
		float grow = smoothstep(0.0, 0.35, sonar_time - crack_time - own * 0.2);
		vec3 pn = normalize(vec3(crystal_hash(base.xyz + 1.0), crystal_hash(base.xyz + 2.0), 0.5) - 0.5);
		float plane = abs(dot(world_pos - base.xyz - a * axis.w * 0.5, pn));
		float crack = (1.0 - smoothstep(0.004, 0.012, plane)) * grow;
		glow += mix(glow_color, vec3(1.0), 0.6) * crack * (1.5 + 2.0 * ring);
	}
	vec2 sonar = sonar_sample(world_pos.xy);
	EMISSION = glow + sonar_hue(world_pos.xy) * (sonar.x * 2.0 + sonar.y * 0.4) * (0.3 + fres);
}
