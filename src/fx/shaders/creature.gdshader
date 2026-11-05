// Shared creature material. Bodies are modelled along +X (head) with vertex
// color R as a bioluminescence mask, G as a belly/back blend and B as how
// freely a part flutters (fin membranes). The vertex stage adds a travelling
// swim wave, fin flutter and a bend of the whole spine into the curve the
// creature is turning along; instance uniforms carry per-creature state
// (sonar mark, hit flash, swim phase, bend) so one material serves a species.
// The fragment stage can add scales: a staggered, overlapping pattern laid in
// the body's own space, with its relief bump-mapped into the normal.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://src/fx/shaders/sonar.gdshaderinc"

uniform vec4 back_color : source_color = vec4(0.3, 0.35, 0.4, 1.0);
uniform vec4 belly_color : source_color = vec4(0.7, 0.75, 0.8, 1.0);
uniform vec4 glow_color : source_color = vec4(0.3, 1.0, 0.9, 1.0);
uniform float glow_strength = 2.0;
uniform float glow_pulse = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.45;
uniform float metallic : hint_range(0.0, 1.0) = 0.1;
uniform float rim_strength = 0.3;
uniform float body_length = 2.0;
uniform float swim_amp = 0.12;
uniform float swim_freq = 7.0;
uniform float swim_wave = 2.5;
// 0 = wag laterally (fish), 1 = undulate vertically (rays, eels seen side-on).
uniform float swim_vertical = 0.25;

instance uniform float marked = 0.0;
instance uniform float hit_flash = 0.0;
instance uniform float phase = 0.0;
// Swim cycles so far, advanced each frame by how fast the creature swims
// (accumulated on the CPU so a change of pace never makes the stroke jump).
instance uniform float swim_clock = 0.0;
instance uniform float glow_boost = 1.0;
// Curvature of the spine (radians per metre of body; + curls the nose and
// tail towards the model's +Y), so the body follows the arc it turns along.
instance uniform float bend = 0.0;
// Where this mesh sits along the body (its node's offset in the model), so a
// separate part (a jaw) bends and swims with the body around it.
instance uniform vec3 body_offset = vec3(0.0);
// The point of the spine that stays put as the body bends.
uniform float bend_pivot = 0.0;
// Models built with BodyKit carry, in UV.x, the point of the spine each
// vertex hangs from: a fin, spine or tooth turns and sways as one rigid
// piece with the body where it is attached, rather than being bent along
// its own length.
uniform bool anchored = false;
// Fin membranes (vertex color B) ripple at their own pace.
uniform float flutter_amp = 0.0;
uniform float flutter_freq = 9.0;
// Scales: their size in metres (0 for smooth skin), relief and how much darker
// their overlapping edges are.
uniform float scale_size = 0.0;
uniform float scale_depth = 0.35;
uniform float scale_shade = 0.25;
// Teeth and claws (vertex alpha below a half) are enamel, not skin.
uniform vec4 tooth_color : source_color = vec4(0.84, 0.8, 0.7, 1.0);
// Dark spots dappling the back (0 for none), their size in metres.
uniform float spots = 0.0;
uniform float spot_size = 0.35;

varying vec3 world_pos;
varying vec3 body_pos;

// A point hanging off the spine at s metres from the pivot, offset by o
// (along and up from that spine point), with the spine bent to curvature k:
// where it lands (xy), and the angle its section turns through (z).
vec3 bent(float s, vec2 o, float k) {
	float th = k * s;
	float a = abs(th) < 0.001 ? 1.0 : sin(th) / th;
	float b = abs(th) < 0.001 ? th * 0.5 : (1.0 - cos(th)) / th;
	float c = cos(th);
	float sn = sin(th);
	return vec3(s * a + o.x * c - o.y * sn, s * b + o.x * sn + o.y * c, th);
}

void vertex() {
	vec3 p = VERTEX + body_offset;
	body_pos = p;
	// The spine point this vertex hangs from.
	float ax = anchored ? UV.x + body_offset.x : p.x;
	float x = ax / max(body_length, 0.01);
	float tail = smoothstep(0.35, -0.55, x);
	// INSTANCE_CUSTOM.x carries a per-fish phase when drawn through a MultiMesh.
	float w = sin(swim_clock * swim_freq + phase + INSTANCE_CUSTOM.x * 6.28 - ax * swim_wave);
	p.z += w * swim_amp * tail * (1.0 - swim_vertical);
	p.y += w * swim_amp * tail * swim_vertical;
	p.z += sin(swim_clock * flutter_freq + phase * 2.0 - p.x * 3.0 + p.y * 2.0) * flutter_amp * COLOR.b;
	// INSTANCE_CUSTOM.y carries a schooling fish's bend.
	float k = bend + INSTANCE_CUSTOM.y;
	if (abs(k) > 0.0001) {
		vec3 q = bent(ax - bend_pivot, vec2(p.x - ax, p.y), k);
		p.x = bend_pivot + q.x;
		p.y = q.y;
		float c = cos(q.z);
		float sn = sin(q.z);
		NORMAL.xy = vec2(NORMAL.x * c - NORMAL.y * sn, NORMAL.x * sn + NORMAL.y * c);
	}
	VERTEX = p - body_offset;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Overlapping scales in rows along the body, each a rounded plate rising
// from the one behind it (the head is +X): relief 0..1 and the edge mask.
vec2 scales(vec3 bp) {
	vec2 g = vec2(bp.x, bp.y + bp.z * 0.35) / scale_size;
	float row = floor(g.y);
	g.x += mod(row, 2.0) * 0.5;
	vec2 f = fract(g) - vec2(1.0, 0.5);
	float d = length(f * vec2(0.85, 1.0));
	float plate = 1.0 - smoothstep(0.55, 1.0, d);
	float edge = smoothstep(0.75, 1.0, d) * (1.0 - smoothstep(1.0, 1.15, d));
	return vec2(plate, edge);
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	bool enamel = COLOR.a < 0.5;
	vec3 base = mix(back_color.rgb, belly_color.rgb, COLOR.g);
	if (enamel) {
		base = tooth_color.rgb;
	} else if (spots > 0.0) {
		vec2 cell = floor(body_pos.xy / spot_size);
		vec2 f = fract(body_pos.xy / spot_size) - 0.5;
		vec2 o = vec2(hash2(cell), hash2(cell + 7.3)) - 0.5;
		float spot = 1.0 - smoothstep(0.18, 0.3, length(f - o * 0.4));
		base *= 1.0 - spot * spots * step(hash2(cell + 3.1), 0.55) * (1.0 - COLOR.g);
	}
	if (scale_size > 0.0 && COLOR.b < 0.001 && !enamel) {
		vec2 sc = scales(body_pos);
		// Scales smaller than a few pixels on screen fade out rather than shimmer
		// (measured the same whichever way the body is turned).
		float px = 0.5 * (length(dFdx(body_pos)) + length(dFdy(body_pos))) / scale_size;
		float detail = 1.0 - smoothstep(0.16, 0.42, px);
		base *= 1.0 - sc.y * scale_shade * detail;
		// Bump-map the plates' relief into the normal (no tangents needed).
		float hgt = sc.x * scale_size * scale_depth * detail;
		vec3 dpx = dFdx(VERTEX);
		vec3 dpy = dFdy(VERTEX);
		vec3 r1 = cross(dpy, NORMAL);
		vec3 r2 = cross(NORMAL, dpx);
		float det = dot(dpx, r1);
		if (abs(det) > 1e-8) {
			vec3 grad = (dFdx(hgt) * r1 + dFdy(hgt) * r2) / det;
			NORMAL = normalize(NORMAL - grad);
		}
	}
	ALBEDO = base;
	ROUGHNESS = enamel ? 0.3 : roughness;
	METALLIC = metallic;
	RIM = rim_strength;
	RIM_TINT = 0.5;
	float pulse = 1.0 + glow_pulse * sin(TIME * 2.3 + phase * 3.0);
	vec3 emission = glow_color.rgb * COLOR.r * glow_strength * pulse * glow_boost;

	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	vec2 sonar = sonar_sample(world_pos.xy);
	emission += sonar_color.rgb * (sonar.x * 4.0 * (0.4 + fres) + marked * fres * 1.6);
	emission += vec3(1.0, 0.85, 0.8) * hit_flash * 2.5;
	EMISSION = emission;
}
