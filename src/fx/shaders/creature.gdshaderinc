// Shared creature material, drawn solid (creature.gdshader) or see-through
// (creature_glass.gdshader). Bodies are modelled along +X (head) with vertex
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
// Curvature sideways, curling the nose and tail towards the model's +Z: the
// C the body makes as the creature turns round through the depth.
instance uniform float bend_side = 0.0;
// Where this mesh sits along the body (its node's offset in the model), so a
// separate part (a jaw) bends and swims with the body around it.
instance uniform vec3 body_offset = vec3(0.0);
// A jellyfish's bell (model X from its rim to its apex): squeezed (0..1),
// it narrows towards the rim and draws its rim in and down, and whatever
// hangs below the rim is carried in with it.
uniform float bell_top = 0.0;
uniform float bell_rim = 0.0;
instance uniform float bell_squeeze = 0.0;
// A body that changes shape (a puffer swelling) carries its second shape in
// CUSTOM0 (positions) and CUSTOM1 (normals): see BodyKit.morph. How far it
// has morphed towards it (may overshoot a little as it wobbles).
instance uniform float puff = 0.0;
// Walking legs (BodyKit.legged): each leg's vertices carry its hip (UV.x,
// UV.y, UV2.x) and its place in the gait (UV2.y: side times one plus its
// phase; 0 for anything not a leg). The gait clock turns them over: each
// swings fore and aft about its hip and lifts its foot as it swings
// forward, so a wave of steps runs down each side. [member stride] is the
// swing (radians; 0 for a creature with no legs), [member leg_lift] the
// lift; gait_amp scales both (0 standing), leg_tuck folds every leg in.
uniform float stride = 0.0;
uniform float leg_lift = 0.35;
instance uniform float gait = 0.0;
instance uniform float gait_amp = 0.0;
instance uniform float leg_tuck = 0.0;
// Wings that beat (a ray's), riding the swim stroke (swim_clock, swim_freq,
// swim_power): beyond [member flap_root] either side of the body, each half
// of the disc curls up and down about the body's edge as one piece, so it
// never stretches, its tip [member flap_rest] plus up to [member flap_amp]
// radians off the line; the beat runs back from the leading edge
// ([member flap_lag] radians a metre, so the wing twists as it strokes) and
// out to the tip ([member flap_tip_lag] radians behind the root).
uniform float flap_amp = 0.0;
uniform float flap_rest = 0.0;
uniform float flap_root = 0.5;
uniform float flap_span = 3.0;
uniform float flap_lag = 0.0;
uniform float flap_tip_lag = 0.0;
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
// Ripples per metre of fin (radians), running back from the head: long
// ribbon fins carry several at once.
uniform float flutter_wave = 3.0;
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
// The skin's coordinates: by default along the body (model X) and round it
// (UV.y); a body that bends and slides as a whole (an eel rebuilt every
// frame) carries its own in UV, so its skin sticks to it.
uniform bool skin_on_uv = false;
// A skin texture (a height pattern: wrinkles, pebbling), repeating this
// many times a metre over the skin's coordinates (0 for none), its relief
// in metres and how much darker its hollows are.
uniform sampler2D skin_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float skin_tex_scale = 0.0;
uniform float skin_tex_depth = 0.004;
uniform float skin_tex_shade = 0.15;
// Fin membranes' own color (alpha: how far it replaces the body's), darker
// towards the body, the edges lighter.
uniform vec4 fin_color : source_color = vec4(0.0, 0.0, 0.0, 0.0);
// Dark bars across the back (0 for none), so many per metre.
uniform float bars = 0.0;
uniform float bar_freq = 2.0;
// See-through flesh (creature_glass.gdshader only): how opaque it is seen
// face on, and where it turns away at the edges; fins thinner still.
uniform float glass_alpha = 0.12;
uniform float glass_rim = 0.7;
uniform float glass_fin = 0.6;
// Soft, blotchy variation of the skin's colour (0 for none): no two
// patches of skin quite the same shade.
uniform float mottle = 0.0;
// Dark markings: up to four soft-edged blotches in the body's own space
// (xyz its centre, mirrored on both flanks, w how dark), each this big
// (radii in metres): a band through the eye, saddles over the back.
uniform vec4 blotch_at[4];
uniform vec3 blotch_size[4];
// Dark spots dappling the back (0 for none), their size in metres.
uniform float spots = 0.0;
uniform float spot_size = 0.35;
// Skin painted over a disc (a ray's): one texture for the back, one for the
// belly, laid over the body as seen from above and from below across the
// whole span (so the two sides may differ); rgb the colour, alpha the
// relief (a half flat, [member paint_relief] metres from there to either
// end). The box they cover: x of its front edge, z of one side, its length
// back and its span (0 for none). Only the skin takes them, not fins,
// teeth or eyes.
uniform sampler2D paint_top : source_color, hint_default_black, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D paint_bottom : source_color, hint_default_black, filter_linear_mipmap_anisotropic,
	repeat_disable;
uniform vec4 paint_box = vec4(0.0);
uniform float paint_relief = 0.004;
// Or skin painted all round a body (a whale's): paint_top alone, wrapped
// round it by UV2 (x along the body, and how far round it from the back's
// midline as a share of the way to the belly, -1 on one flank to 1 on the
// other); the box is then x of the tail end, -1, the length and 2. Parts
// with UV2.y beyond 900 (jaw, flippers) keep their plain colours.
uniform bool paint_wrap = false;
// A row of glowing pores down each flank (a lateral line), for a body whose
// UV2 carries how far along it a point is (x) and how far round from the
// flank's midline (y, in the same units): how far the row is off the
// midline, how far apart the pores are, how big, and how bright (0 for
// none). They glow with the instance's glow_boost.
uniform vec4 pores = vec4(0.0);
// Light from the surface far above (0 for none): something big in the
// sunlit blue (a whale) is lit along its back and dark beneath, so it reads
// against the dark rock behind it, tinted by the water.
uniform float sky_light = 0.0;
uniform vec4 sky_tint : source_color = vec4(0.55, 0.75, 0.85, 1.0);
#ifdef FADE
// Fading into and out of the blue (1 solid).
instance uniform float fade = 1.0;
#endif

varying vec3 world_pos;
varying vec3 body_pos;
// The skin's own coordinates: along the body, and round it from the back's
// midline (BodyKit's UV.y), so scales keep their size all round.
varying vec2 skin_uv;
varying vec2 paint_uv;

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
vec3 swim_wave_at(float x, float ph, float power) {
	float l = max(body_length, 0.01);
	float xc = clamp(x, -0.65 * l, 0.5 * l);
	float u = 0.5 - xc / l;
	float um = min(swim_still, 0.4);
	float ea = (1.0 - swim_head) / (1.0 - 2.0 * um);
	float env = ea * (u - um) * (u - um) + swim_head - ea * um * um;
	float denv = -2.0 * ea * (u - um) / l;
	// + x: the wave runs from the head (+X) back to the tail.
	float w = ph + xc * swim_wave;
	float amp = swim_amp * power;
	float d = amp * env * sin(w);
	float slope = amp * (denv * sin(w) + env * swim_wave * cos(w));
	return vec3(d + slope * (x - xc), slope, amp * env * cos(w));
}

void vertex() {
	// The skin's pattern stays put on the skin as it swells.
	body_pos = VERTEX + body_offset;
	if (puff != 0.0) {
		VERTEX = mix(VERTEX, CUSTOM0.xyz, puff);
		NORMAL = normalize(mix(NORMAL, CUSTOM1.xyz, puff));
	}
	vec3 p = VERTEX + body_offset;
	if (stride > 0.0 && UV2.y != 0.0) {
		float side = sign(UV2.y);
		float ph = gait + abs(UV2.y);
		vec3 hip = vec3(UV.x, UV.y, UV2.x);
		vec3 r = p - hip;
		float swing = sin(ph) * stride * gait_amp;
		float lift = max(cos(ph), 0.0) * leg_lift * gait_amp - leg_tuck * 1.1;
		r.zy = turned(r.zy, lift * side);
		NORMAL.zy = turned(NORMAL.zy, lift * side);
		r.xz = turned(r.xz, -swing * side);
		NORMAL.xz = turned(NORMAL.xz, -swing * side);
		p = hip + r;
	}
	if (flap_amp > 0.0) {
		float s = abs(p.z) - flap_root;
		if (s > 0.0) {
			float side = sign(p.z);
			float span = max(flap_span, 0.01);
			float w = swim_clock * swim_freq + phase + p.x * flap_lag - s / span * flap_tip_lag;
			float tip = flap_rest + flap_amp * swim_power * sin(w);
			vec3 q = bent(s, vec2(0.0, p.y), tip / span);
			p.z = side * (flap_root + q.x);
			p.y = q.y;
			vec2 n = turned(vec2(NORMAL.z * side, NORMAL.y), q.z);
			NORMAL.z = n.x * side;
			NORMAL.y = n.y;
		}
	}
	if (bell_squeeze != 0.0) {
		float f = clamp((bell_top - p.x) / max(bell_top - bell_rim, 0.01), 0.0, 1.0);
		p.yz *= 1.0 - bell_squeeze * 0.3 * f * f;
		p.x -= bell_squeeze * 0.14 * (bell_top - bell_rim) * f;
	}
	skin_uv = skin_on_uv ? UV : vec2(p.x, UV.y);
	paint_uv = UV2;
	// The spine point this vertex hangs from.
	float ax = anchored ? UV.x + body_offset.x : p.x;
	// Drawn through a MultiMesh (a school), each fish carries its own stroke
	// in INSTANCE_CUSTOM: x its phase (in cycles), y its bend, z how much
	// harder than [member swim_power] it swims.
	float ph = swim_clock * swim_freq + phase + INSTANCE_CUSTOM.x * 6.28318;
	float power = swim_power * (1.0 + INSTANCE_CUSTOM.z);
	p.z += sin(swim_clock * flutter_freq + phase * 2.0 + p.x * flutter_wave + p.y * 2.0) * flutter_amp * COLOR.b;
	vec3 sw = swim_wave_at(ax, ph, power);
	// Fins trail behind the way their root is moving.
	// (Up and down for a creature that swims up and down: a whale's flukes.)
	if (swim_vertical > 0.5) {
		p.y -= fin_lag * COLOR.b * sw.z;
	} else {
		p.z -= fin_lag * COLOR.b * sw.z;
	}
	// A little roll with each beat, about the spine.
	float r = swim_roll * power * sin(ph);
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
	// Drawn through a MultiMesh, INSTANCE_CUSTOM.w carries the sideways curl.
	float ks = bend_side + INSTANCE_CUSTOM.w;
	if (abs(ks) > 0.0001) {
		vec3 q = bent(ax - bend_pivot, vec2(p.x - ax, p.z), ks);
		p.x = bend_pivot + q.x;
		p.z = q.y;
		NORMAL.xz = turned(NORMAL.xz, q.z);
	}
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
		// Round spots wherever on the body (cells in 3D, so they never smear
		// into stripes across the back or belly).
		vec3 g = body_pos / spot_size;
		vec3 cell = floor(g);
		vec3 f = fract(g) - 0.5;
		vec2 key = cell.xy + cell.z * vec2(7.13, 3.71);
		vec3 o = vec3(hash2(key), hash2(key + 7.3), hash2(key + 1.9)) - 0.5;
		// Each a different size and depth of colour, a few large, most small.
		float r = mix(0.3, 0.46, pow(hash2(key + 5.7), 1.5));
		float spot = 1.0 - smoothstep(r * 0.7, r, length(f - o * 0.35));
		float depth = mix(0.55, 1.0, hash2(key + 8.3));
		base *= 1.0 - spot * spots * depth * step(hash2(key + 3.1), 0.85) * (1.0 - COLOR.g * 0.85);
	}
	if (!enamel && COLOR.b < 0.001) {
		if (mottle > 0.0) {
			float m = value_noise(body_pos * 2.7) * 0.6 + value_noise(body_pos * 8.0 + 3.1) * 0.4;
			base *= 1.0 + (m - 0.5) * mottle;
		}
		vec3 q = vec3(body_pos.xy, abs(body_pos.z));
		// Ragged edges: markings, not shadows.
		float warp = (value_noise(body_pos * 5.0 + 1.7) - 0.5) * 0.6 + (value_noise(body_pos * 14.0) - 0.5) * 0.3;
		for (int i = 0; i < 4; i++) {
			if (blotch_at[i].w > 0.0) {
				float d = length((q - blotch_at[i].xyz) / max(blotch_size[i], vec3(0.001)));
				base *= 1.0 - blotch_at[i].w * (1.0 - smoothstep(0.86, 1.0, d + warp));
			}
		}
	}
	float hgt = 0.0;
	float bare = 1.0;
	float px = 0.5 * (length(dFdx(body_pos)) + length(dFdy(body_pos)));
	bool painted = paint_box.z > 0.0 && !enamel && COLOR.b < 0.001 && !(paint_wrap && paint_uv.y > 900.0);
	if (painted) {
		vec4 paint;
		if (paint_wrap) {
			paint = texture(paint_top, (paint_uv - paint_box.xy) / paint_box.zw);
		} else {
			vec2 puv = vec2((body_pos.z - paint_box.y) / paint_box.w, (paint_box.x - body_pos.x) / paint_box.z);
			paint = mix(texture(paint_bottom, puv), texture(paint_top, puv), smoothstep(-0.004, 0.004, body_pos.y));
		}
		base = paint.rgb;
		hgt += (paint.a - 0.5) * 2.0 * paint_relief;
	}
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
		vec3 at = skin_on_uv ? vec3(skin_uv, 0.37) : body_pos;
		float pits = value_noise(at * 22.0) * 0.6 + value_noise(at * 7.0) * 0.4;
		float seen = 1.0 - smoothstep(0.012, 0.03, px);
		hgt += pits * skin_pits * bare * seen;
		base *= 1.0 - (0.5 - pits) * 0.25 * bare * seen;
	}
	if (skin_tex_scale > 0.0 && !enamel && COLOR.b < 0.001) {
		float h = texture(skin_tex, skin_uv * skin_tex_scale).r;
		hgt += (h - 0.5) * skin_tex_depth;
		base *= 1.0 - (0.5 - h) * skin_tex_shade;
	}
	if (hgt != 0.0 || scale_size > 0.0 || skin_pits > 0.0 || skin_tex_scale > 0.0 || painted) {
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
	// (Only where the mesh says where its pores lie: UV2.x is how far along.)
	if (pores.w > 0.0 && !enamel && paint_uv.x > 0.0) {
		float da = (fract(paint_uv.x / pores.y + 0.5) - 0.5) * pores.y;
		float pore = 1.0 - smoothstep(pores.z * 0.45, pores.z, length(vec2(da, abs(paint_uv.y) - pores.x)));
		emission += glow_color.rgb * pore * pores.w * glow_boost * pulse;
	}
	if (sky_light > 0.0) {
		float up = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y;
		emission += ALBEDO * sky_tint.rgb * sky_light * (0.2 + 0.8 * smoothstep(-0.35, 1.0, up));
	}
	EMISSION = emission;
#ifdef FADE
	ALPHA = fade;
#endif
#ifdef GLASS
	// Clear seen face on, milky where the flesh turns away, fins thinner
	// still; whatever glows, or is marked or struck, shows through.
	float edge = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 1.6);
	ALPHA = clamp(mix(glass_alpha, glass_rim, edge) * (fin ? glass_fin : 1.0) + COLOR.r * 0.5
		+ hit_flash + marked * 0.4 + sonar.x, 0.0, 1.0);
#endif
}
