// Instanced cave decoration (kelp, coral, crystals...), built by PropModels.
// COLOR: rgb albedo, a glow mask. UV: x how far the current bends the point,
// y how far along its frond or tentacle it is. UV2: x the part's phase, y how
// far it pulls in when the sub is near. CUSTOM0: xyz the part's root, w its
// surface (PropModels' KIND constants).
// CUSTOM1: xyz how far the point moves when the prop shuts.
// INSTANCE_CUSTOM: x = sway phase, y = tint blend, z = brightness, w = the
// state PropLife keeps: how far it has shut (props that retract) or how far
// it leans across its stalk out of the sub's way (props with a wake).
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

#include "res://src/fx/shaders/sonar.gdshaderinc"

uniform vec3 tint_a : source_color = vec3(1.0);
uniform vec3 tint_b : source_color = vec3(1.0);
uniform vec4 glow_color : source_color = vec4(0.3, 1.0, 0.9, 1.0);
uniform float glow_strength = 0.0;
uniform float glow_pulse = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.8;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
// How far the current bends the top of the prop, and how fast it swells.
uniform float sway = 0.0;
uniform float sway_speed = 0.6;
// How far fronds, tentacles and plumes stir on their own, at their tips.
uniform float flutter = 0.0;
uniform float flutter_speed = 0.9;
// 1 = it shuts (anemones, tubeworms) as far as its state says.
uniform float retract = 0.0;
// How far (in metres, at its top) a stalk leans at full lean.
uniform float wake = 0.0;
// Light let through thin fronds and nets from behind.
uniform float translucency = 0.0;
// Strength of the surface patterns and their relief.
uniform float detail = 1.0;
uniform float bump = 1.0;
// 1 = crystal: faces lit and glowing each in their own way, so a strongly
// emissive gem still reads as a faceted solid rather than a flat silhouette.
uniform float facet = 0.0;
uniform float net_scale = 22.0;
uniform float net_width = 0.1;

varying vec3 world_pos;
varying vec3 obj_pos;
varying vec4 custom;
varying vec4 part;
varying float phase;

void vertex() {
	custom = INSTANCE_CUSTOM;
	part = CUSTOM0;
	phase = INSTANCE_CUSTOM.x * 6.2831;
	obj_pos = VERTEX;
	vec3 v = VERTEX;
	float ph = UV2.x * 6.2831;
	float shut = 0.0;
	if (retract > 0.0) {
		// Eased between its open shape and its shut one, both built in.
		shut = smoothstep(0.0, 1.0, clamp(INSTANCE_CUSTOM.w, 0.0, 1.0)) * retract;
		v += CUSTOM1.xyz * shut;
	}
	float f = UV.y;
	if (flutter > 0.0 && f > 0.0) {
		// A slow stir of its own, stilled as it shuts.
		float tt = TIME * flutter_speed + ph;
		v += vec3(sin(tt + f * 1.4), 0.0, cos(tt * 0.8 + ph + f * 1.1)) * flutter * f * f * (1.0 - shut);
	}
	// The current: one long, slow swell rolling along the zone, so a whole
	// bed of kelp leans together, with a slower one under it.
	float s = sway * UV.x;
	if (s > 0.0) {
		vec3 origin = MODEL_MATRIX[3].xyz;
		float w = TIME * sway_speed - origin.x * 0.08 + phase * 0.2;
		v.x += (sin(w - v.y * 0.12) * 0.75 + sin(w * 0.57 + 2.1 + phase * 0.3) * 0.25) * s;
		v.z += sin(w * 0.43 + phase) * s * 0.3;
	}
	if (wake > 0.0 && INSTANCE_CUSTOM.w != 0.0) {
		// Bent from its foot across itself, out of the hull's way.
		vec3 up = normalize(MODEL_MATRIX[1].xyz);
		vec3 side = normalize(vec3(up.y, -up.x, 0.0));
		float scale2 = dot(MODEL_MATRIX[0].xyz, MODEL_MATRIX[0].xyz);
		v += transpose(mat3(MODEL_MATRIX)) * side / scale2 * INSTANCE_CUSTOM.w * wake * UV.x;
	}
	VERTEX = v;
	world_pos = (MODEL_MATRIX * vec4(v, 1.0)).xyz;
}

float prop_hash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float prop_noise(vec3 p) {
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

// The distances to the nearest two cell centres (F1, F2), searching only
// the eight cells on the near side: cheap, and plenty for small detail.
vec2 prop_cells(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 o = step(0.5, f) - 1.0;
	float d1 = 8.0;
	float d2 = 8.0;
	for (int z = 0; z <= 1; z++) {
		for (int y = 0; y <= 1; y++) {
			for (int x = 0; x <= 1; x++) {
				vec3 g = o + vec3(float(x), float(y), float(z));
				vec3 h = vec3(prop_hash(i + g), prop_hash(i + g + 19.1), prop_hash(i + g + 47.7));
				vec3 r = g + 0.15 + h * 0.7 - f;
				float d = dot(r, r);
				if (d < d1) {
					d2 = d1;
					d1 = d;
				} else if (d < d2) {
					d2 = d;
				}
			}
		}
	}
	return sqrt(vec2(d1, d2));
}

// Bends the normal by the screen-space slope of a height field h.
vec3 prop_bumped(vec3 n, vec3 view_pos, float h) {
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

void fragment() {
	vec3 n = NORMAL;
	float kind = floor(part.w + 0.5);
	// Rock the props grow from keeps its own colour.
	vec3 tint = kind == 10.0 ? vec3(0.9) : mix(tint_a, tint_b, custom.y);
	vec3 albedo = COLOR.rgb * tint * custom.z;
	float glow = COLOR.a;
	float rough = roughness;
	float h = 0.0;
	float face_light = 1.0;
	// Broad blotches over everything.
	float m = prop_noise(obj_pos * 2.1 + custom.x * 17.0);
	albedo *= 1.0 + (m - 0.5) * 0.4 * detail;
	if (kind == 1.0) {
		// Polyps: a little round cup for each, its centre alight.
		vec2 c = prop_cells(obj_pos * 34.0);
		float cup = 1.0 - smoothstep(0.1, 0.3, c.x);
		h = -cup * 0.005;
		albedo *= mix(1.0, 1.0 - cup * 0.4, detail);
		glow *= 0.25 + 0.75 * cup;
	} else if (kind == 2.0) {
		// Brain coral: rounded ridges winding side by side, dark grooves
		// between them.
		float warp = prop_noise(obj_pos * 2.6 + 3.1) * 15.0 + prop_noise(obj_pos * 6.5) * 4.0;
		float ridge = 0.5 + 0.5 * sin(dot(obj_pos, vec3(62.0, 18.0, 47.0)) + warp * 1.6);
		float groove = 1.0 - smoothstep(0.0, 0.3, ridge);
		h = sqrt(ridge) * 0.01;
		albedo *= mix(1.0, (0.75 + 0.25 * ridge) * (1.0 - groove * 0.5), detail);
		glow *= groove * 0.8 + 0.2 * ridge;
	} else if (kind == 3.0) {
		// Growth rings up a tube.
		float d = length(obj_pos - part.xyz);
		float ring = sin(d * 150.0 + prop_noise(obj_pos * 9.0) * 4.0);
		h = ring * 0.0012;
		albedo *= 0.94 + 0.08 * ring * detail;
		rough = clamp(rough - ring * 0.1, 0.0, 1.0);
	} else if (kind == 4.0) {
		// Bone: pitted, stained darker where it lies in the silt.
		float pits = prop_noise(obj_pos * 14.0);
		float stain = smoothstep(0.6, 0.15, obj_pos.y) * 0.35;
		h = -smoothstep(0.62, 0.8, pits) * 0.01;
		albedo *= (1.0 - stain) * (1.0 - smoothstep(0.62, 0.8, pits) * 0.35 * detail);
		albedo = mix(albedo, albedo * vec3(0.85, 0.9, 0.75), smoothstep(0.4, 0.7, m) * 0.6);
	} else if (kind == 6.0) {
		// Gills: fine radial pleats under a cap, each one glowing.
		vec3 r = obj_pos - part.xyz;
		float a = atan(r.z, r.x);
		float pleat = 0.5 + 0.5 * cos(a * 54.0);
		albedo *= 0.7 + 0.3 * pleat;
		glow *= 0.25 + 0.75 * pleat;
		h = pleat * 0.004;
	} else if (kind == 7.0) {
		// A cap freckled with glowing spots.
		float spot = smoothstep(0.6, 0.72, prop_noise(obj_pos * 9.0 + part.xyz * 3.0));
		albedo = mix(albedo, albedo * 1.25, spot);
		glow *= 0.04 + spot;
		h = spot * 0.006;
	} else if (kind == 9.0) {
		// Mineral crust: lumpy, with hot cracks where it is still growing.
		vec2 c = prop_cells(obj_pos * vec3(2.2, 1.3, 2.2));
		float crack = 1.0 - smoothstep(0.0, 0.05, c.y - c.x);
		float lump = prop_noise(obj_pos * 6.0) * 0.6 + prop_noise(obj_pos * 17.0) * 0.4;
		h = lump * 0.03 - crack * 0.015;
		albedo *= (0.75 + lump * 0.5) * (1.0 - crack * 0.4 * glow);
		glow *= crack * 1.6 * smoothstep(0.15, 0.6, glow) + 0.06;
		rough = clamp(rough + lump * 0.1, 0.0, 1.0);
	} else if (kind == 11.0) {
		// Sponge: pocked with pores.
		vec2 c = prop_cells(obj_pos * 16.0);
		float pore = 1.0 - smoothstep(0.1, 0.2, c.x);
		h = -pore * 0.008;
		albedo *= 1.0 - pore * 0.7 * detail;
		rough = clamp(rough + 0.15, 0.0, 1.0);
	} else if (kind == 10.0) {
		float lump = prop_noise(obj_pos * 7.0);
		h = lump * 0.02;
		albedo *= 0.75 + lump * 0.5;
	}
	if (h != 0.0 && bump > 0.0) {
		n = prop_bumped(n, VERTEX, h * bump);
	}
#ifdef NET
	// The fan's net: holes between its threads. Seen from far off, where the
	// threads are finer than a pixel, a dim solid lace instead.
	if (kind == 5.0) {
		float spoke = length(obj_pos.xy);
		// Cells drawn out along the fan's spokes, as its branchlets run.
		vec2 q = vec2(atan(obj_pos.x, obj_pos.y) * spoke * net_scale, spoke * net_scale * 0.6);
		vec2 c2 = prop_cells(vec3(q, 0.37));
		float edge = c2.y - c2.x;
		float fw = max(fwidth(edge), 1e-4);
		float thread = 1.0 - smoothstep(net_width - fw, net_width + fw, edge);
		float fine = clamp(length(fwidth(q)) * 2.0 - 0.6, 0.0, 1.0);
		ALPHA = mix(thread, 1.0, fine);
		albedo *= mix(1.0, 0.3, fine);
		glow *= mix(0.4 + 0.6 * thread, 0.3, fine);
	} else {
		ALPHA = 1.0;
	}
	ALPHA_SCISSOR_THRESHOLD = 0.5;
#endif
	if (facet > 0.0) {
		face_light = mix(1.0, 0.25 + 0.9 * abs(dot(n, normalize(vec3(0.45, 0.8, 0.4)))), facet);
	}
	NORMAL = n;
	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = metallic;
	BACKLIGHT = albedo * translucency;
	float pulse = 1.0 + glow_pulse * sin(TIME * 1.7 + phase + part.x * 3.0);
	float fres = pow(1.0 - clamp(dot(n, VIEW), 0.0, 1.0), 2.0);
	float glow_mult = 0.6 + 0.6 * fract(custom.x * 13.7);
	vec3 emission = glow_color.rgb * glow * glow_strength * glow_mult * pulse;
	emission *= mix(1.0, face_light + fres * 0.8, facet);
	vec2 sonar = sonar_sample(world_pos.xy);
	emission += sonar_color.rgb * (sonar.x * 2.0 + sonar.y * 0.4) * (0.3 + fres);
	EMISSION = emission;
}
