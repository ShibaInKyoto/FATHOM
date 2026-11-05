// Shared creature material. Bodies are modelled along +X (head) with vertex
// color R as a bioluminescence mask, G as a belly/back blend and B as how
// freely a part flutters (fin membranes). The vertex stage swims the body:
// a wave of side-to-side bending runs down the spine from head to tail,
// growing as it goes, and every section of the body turns with the spine
// where it hangs, so the tail and its fin sweep through the water like a
// paddle while the head barely yaws against it. On top of that come fin
// flutter, a slight roll with each beat and a bend of the whole spine into
// the curve the creature is turning along; instance uniforms carry
// per-creature state (sonar mark, hit flash, swim phase and strength, bend)
// so one material serves a species.
// The fragment stage can add scales, laid over the skin like roof tiles:
// each lies over the front of the one behind it, so what shows is a field of
// crescent free edges facing the tail, in slightly oblique rows, every scale
// a little different in size, place and sheen; their relief is bump-mapped
// into the normal.
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
// How far the tail swings to either side at full stroke (metres).
uniform float swim_amp = 0.12;
uniform float swim_freq = 7.0;
// Radians of wave per metre of body: 2 pi / body_length puts one whole wave
// on the body, as in most fish; eels carry more.
uniform float swim_wave = 2.5;
// 0 = sideways, like a fish; 1 = up and down, like a whale's flukes.
uniform float swim_vertical = 0.25;
// How the stroke spreads along the body: the head's swing as a share of the
// tail's, and where (0 at the head, 1 at the tail) the body swings least.
// Tail-driven fish move little ahead of their rear third (0.2, 0.25); eels
// swim with all of themselves (0.5, 0.0).
uniform float swim_head = 0.2;
uniform float swim_still = 0.25;
// Roll with each beat (radians at full stroke).
uniform float swim_roll = 0.0;
// How far fin membranes (vertex color B) trail behind the stroke, as a share
// of the swing where they are fixed.
uniform float fin_lag = 0.0;

instance uniform float marked = 0.0;
instance uniform float hit_flash = 0.0;
instance uniform float phase = 0.0;
// Swim cycles so far, advanced each frame by how fast the creature swims
// (accumulated on the CPU so a change of pace never makes the stroke jump).
instance uniform float swim_clock = 0.0;
instance uniform float glow_boost = 1.0;
// Strength of the stroke: a drifting creature barely swims, one cruising
// swims fully, one bursting away swims harder still.
instance uniform float swim_power = 1.0;
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
// Where the scaleless head begins (model X).
uniform float scale_head_x = 99.0;
// Fine pitting of bare skin (the head, scaleless bodies), in metres of relief.
uniform float skin_pits = 0.0;
// Fin membranes' own color (alpha: how far it replaces the body's), darker
// towards the body, the edges lighter.
uniform vec4 fin_color : source_color = vec4(0.0, 0.0, 0.0, 0.0);
// Dark bars across the back (0 for none), so many per metre.
uniform float bars = 0.0;
uniform float bar_freq = 2.0;
// Dark spots dappling the back (0 for none), their size in metres.
uniform float spots = 0.0;
uniform float spot_size = 0.35;

varying vec3 world_pos;
varying vec3 body_pos;
// The skin's own coordinates: along the body, and round it from the back's
// midline (BodyKit's UV.y), so scales keep their size all round.
varying vec2 skin_uv;

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

// Rotates v by angle a (radians, from its first axis towards its second).
vec2 turned(vec2 v, float a) {
	float c = cos(a);
	float sn = sin(a);
	return vec2(v.x * c - v.y * sn, v.x * sn + v.y * c);
}

// The swim wave at spine point x: how far the spine stands off its line
// there (x), its slope (y) and how fast it is swinging across (z). The swing grows along the body as a parabola
// through the head's share, a quiet point and the tail; past the head and
// the tail the body carries straight on.
vec3 swim_wave_at(float x, float ph) {
	float l = max(body_length, 0.01);
	float xc = clamp(x, -0.65 * l, 0.5 * l);
	float u = 0.5 - xc / l;
	float um = min(swim_still, 0.4);
	float ea = (1.0 - swim_head) / (1.0 - 2.0 * um);
	float env = ea * (u - um) * (u - um) + swim_head - ea * um * um;
	float denv = -2.0 * ea * (u - um) / l;
	float w = ph - xc * swim_wave;
	float amp = swim_amp * swim_power;
	float d = amp * env * sin(w);
	float slope = amp * (denv * sin(w) - env * swim_wave * cos(w));
	return vec3(d + slope * (x - xc), slope, amp * env * cos(w));
}

void vertex() {
	vec3 p = VERTEX + body_offset;
	body_pos = p;
	skin_uv = vec2(p.x, UV.y);
	// The spine point this vertex hangs from.
	float ax = anchored ? UV.x + body_offset.x : p.x;
	// INSTANCE_CUSTOM.x carries a per-fish phase when drawn through a MultiMesh.
	float ph = swim_clock * swim_freq + phase + INSTANCE_CUSTOM.x * 6.28;
	p.z += sin(swim_clock * flutter_freq + phase * 2.0 - p.x * 3.0 + p.y * 2.0) * flutter_amp * COLOR.b;
	vec3 sw = swim_wave_at(ax, ph);
	// Fins trail behind the way their root is moving.
	p.z -= fin_lag * COLOR.b * sw.z;
	// A little roll with each beat, about the spine.
	float r = swim_roll * swim_power * sin(ph);
	p.yz = turned(p.yz, r);
	NORMAL.yz = turned(NORMAL.yz, r);
	// Each section turns with the spine where it hangs: sideways, then up
	// and down.
	vec3 o = p - vec3(ax, 0.0, 0.0);
	float yaw = atan(sw.y * (1.0 - swim_vertical));
	o.xz = turned(o.xz, yaw);
	NORMAL.xz = turned(NORMAL.xz, yaw);
	float pitch = atan(sw.y * swim_vertical);
	o.xy = turned(o.xy, pitch);
	NORMAL.xy = turned(NORMAL.xy, pitch);
	p = vec3(ax, sw.x * swim_vertical, sw.x * (1.0 - swim_vertical)) + o;
	// INSTANCE_CUSTOM.y carries a schooling fish's bend.
	float k = bend + INSTANCE_CUSTOM.y;
	if (abs(k) > 0.0001) {
		vec3 q = bent(ax - bend_pivot, vec2(p.x - ax, p.y), k);
		p.x = bend_pivot + q.x;
		p.y = q.y;
		NORMAL.xy = turned(NORMAL.xy, q.z);
	}
	VERTEX = p - body_offset;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec3 p) {
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

// Bends the normal by the screen-space slope of a height field [param h]
// (metres) over the surface: bump mapping with no tangents.
vec3 bumped(vec3 n, vec3 view_pos, float h) {
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

// The scale lying on top at skin point [param uv] (the head is +X): of the
// scales covering it, the one rooted furthest forward lies over the others.
// Returns its relief (rising from its root to its free rear edge), how close
// the point is to that free edge, and a random value for the scale.
vec3 scales(vec2 uv) {
	vec2 g = uv / scale_size;
	// Rows run a little obliquely, as they do on a fish.
	g.x += g.y * 0.3;
	vec2 cell = floor(g);
	float best = -1e9;
	vec3 res = vec3(0.0, 1.0, 0.5);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 c = cell + vec2(float(i), float(j));
			float h = hash2(c);
			vec2 centre = c + vec2(0.5 + mod(c.y, 2.0) * 0.5, 0.5)
				+ (vec2(hash2(c + 1.7), hash2(c + 4.3)) - 0.5) * 0.3;
			float rad = 0.74 + h * 0.18;
			vec2 d = (g - centre) * vec2(1.0, 1.12);
			float dist = length(d);
			if (dist < rad && centre.x > best) {
				best = centre.x;
				// 0 at the root (front) .. 1 at the free edge (back).
				float lift = clamp(0.5 - d.x / (2.0 * rad), 0.0, 1.0);
				float rim = smoothstep(rad * 0.72, rad, dist) * step(d.x, 0.15);
				res = vec3(lift * lift * (1.0 - smoothstep(rad * 0.72, rad, dist)), rim, h);
			}
		}
	}
	return res;
}

void fragment() {
	bool enamel = COLOR.a < 0.5;
	vec3 base = mix(back_color.rgb, belly_color.rgb, COLOR.g);
	if (enamel) {
		base = tooth_color.rgb;
	} else if (COLOR.b > 0.001 && fin_color.a > 0.0) {
		base = mix(base, fin_color.rgb * mix(0.7, 1.4, COLOR.b), fin_color.a);
	} else if (bars > 0.0 && COLOR.b < 0.001) {
		float bar = smoothstep(0.35, 0.6, abs(fract(body_pos.x * bar_freq + body_pos.y * 0.6) - 0.5) * 2.0);
		base *= 1.0 - bars * (1.0 - bar) * smoothstep(0.0, 0.6, 1.0 - COLOR.g);
	}
	if (spots > 0.0 && !enamel) {
		vec2 cell = floor(body_pos.xy / spot_size);
		vec2 f = fract(body_pos.xy / spot_size) - 0.5;
		vec2 o = vec2(hash2(cell), hash2(cell + 7.3)) - 0.5;
		float spot = 1.0 - smoothstep(0.18, 0.3, length(f - o * 0.4));
		base *= 1.0 - spot * spots * step(hash2(cell + 3.1), 0.55) * (1.0 - COLOR.g);
	}
	float hgt = 0.0;
	float bare = 1.0;
	float px = 0.5 * (length(dFdx(body_pos)) + length(dFdy(body_pos)));
	if (scale_size > 0.0 && COLOR.b < 0.001 && !enamel) {
		vec3 sc = scales(skin_uv);
		// Scales smaller than a few pixels on screen fade out rather than shimmer
		// (measured the same whichever way the body is turned), and they give
		// way to bare skin at the head along a ragged line.
		float ragged = (value_noise(body_pos * 3.0) - 0.5) * 0.4;
		bare = smoothstep(scale_head_x - 0.45, scale_head_x, body_pos.x + ragged);
		float detail = (1.0 - smoothstep(0.16, 0.42, px / scale_size)) * (1.0 - bare);
		// Each scale a shade different, its free edge darkest.
		base *= 1.0 - (sc.y * scale_shade + (sc.z - 0.5) * 0.12) * detail;
		hgt += sc.x * scale_size * scale_depth * detail;
	}
	if (skin_pits > 0.0 && !enamel && COLOR.b < 0.001) {
		// Bare skin: fine pits and wrinkles, fading out when too small to see.
		float pits = value_noise(body_pos * 22.0) * 0.6 + value_noise(body_pos * 7.0) * 0.4;
		float seen = 1.0 - smoothstep(0.012, 0.03, px);
		hgt += pits * skin_pits * bare * seen;
		base *= 1.0 - (0.5 - pits) * 0.25 * bare * seen;
	}
	if (hgt != 0.0 || scale_size > 0.0 || skin_pits > 0.0) {
		NORMAL = bumped(NORMAL, VERTEX, hgt);
	}
	ALBEDO = base;
	// Fin membranes are skin, not scale: never metallic, a little rougher.
	bool fin = COLOR.b > 0.001;
	ROUGHNESS = enamel ? 0.3 : (fin ? max(roughness, 0.55) : roughness);
	METALLIC = fin || enamel ? 0.0 : metallic;
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
