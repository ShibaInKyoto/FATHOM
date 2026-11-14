// Meridian Deep (StationModel). COLOR.a is each part's material: 0 paint
// (COLOR.rgb its colour; UV past 100 where it lies on its hull), 0.2 frame
// steel (COLOR.rgb a tint), 0.3 dark fittings and rubber, 0.6 a viewport
// (COLOR.r 1 lit, 0.5 failing, 0 dead; COLOR.g which room; UV across the
// pane in metres), 0.8 a floodlight's lens (COLOR.r 1 if it still works), 1
// the beacon's lens. Years on the trench floor: paint chipped, grimed and
// bled with rust down from its seams, frames rusted through, growth crusting
// everything low down, silt on every face turned up. Behind each viewport
// its room, drawn in perspective as if the pane looked into it, lit, failing
// or dark.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

#include "res://src/fx/shaders/sonar.gdshaderinc"

uniform vec3 sediment_tint : source_color = vec3(0.4, 0.38, 0.34);
uniform vec3 window_color : source_color = vec3(1.0, 0.86, 0.66);
uniform vec3 beacon_color : source_color = vec3(0.4, 1.0, 0.6);
uniform vec3 lamp_color : source_color = vec3(1.0, 0.82, 0.55);
uniform float steady_energy = 1.6;
uniform float failing_energy = 1.6;
// The beacon's flash (0..1) as it pings.
uniform float beacon = 0.0;
// How much further gone it is (0 the station; 1 a wreck decades down):
// more rust, more chips, growth higher up.
uniform float decay = 0.0;

varying vec3 obj_pos;
varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	obj_pos = VERTEX;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float st_noise(vec3 p) {
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

// The room behind a pane, seen along [rd] (pane space: x across, y up, z
// out of the room) from [o] on the pane; [seed] picks its furnishing.
// Returns the light it sends out through the pane, for a lamp of 1.
vec3 room(vec3 o, vec3 rd, float seed) {
	bool big = seed > 0.9;
	vec3 size = big ? vec3(1.5, 0.95, 2.6) : vec3(0.95, 0.62, 1.35);
	rd.z = min(rd.z, -0.04);
	rd.x = abs(rd.x) < 1e-4 ? 1e-4 : rd.x;
	rd.y = abs(rd.y) < 1e-4 ? 1e-4 : rd.y;
	float tx = (sign(rd.x) * size.x - o.x) / rd.x;
	float ty = (sign(rd.y) * size.y - o.y) / rd.y;
	float tz = (-size.z - o.z) / rd.z;
	float t = min(min(tx, ty), tz);
	vec3 h = o + rd * t;
	// The light strip along the ceiling, and how it falls on each surface.
	vec3 lamp = vec3(0.0, size.y - 0.05, -size.z * 0.45);
	float lit = 0.12 + 0.85 / (1.0 + 2.5 * dot(h - lamp, h - lamp));
	// Darker into every corner.
	vec3 rel = abs(h / size);
	float corner = max(max(rel.x * step(t, tx - 1e-4), rel.y * step(t, ty - 1e-4)), rel.z * step(t, tz - 1e-4));
	lit *= 1.0 - 0.45 * pow(corner, 3.0);
	// Painted walls, a pale institutional green.
	vec3 wall = vec3(0.55, 0.6, 0.55);
	float shade = 1.0;
	vec3 glow = vec3(0.0);
	if (t == tz) {
		// The back wall: lockers or a bunk, shelves, a screen still on.
		float x = h.x / size.x;
		float y = h.y / size.y;
		float split = fract(seed * 7.13) * 0.8 - 0.4;
		float lockers = step(abs(x - split - 0.45), 0.32) * step(y, 0.5);
		float doors = step(abs(fract((x - split - 0.13) * 3.2) - 0.5), 0.46) * lockers;
		float bunk = step(x, split) * step(abs(y + 0.55), 0.17);
		float blanket = step(x, split - 0.05) * step(abs(y + 0.45), 0.07);
		float shelf = step(abs(y - 0.6), 0.03) + step(abs(y - 0.25), 0.025) * step(x, split - 0.1);
		wall = mix(wall, vec3(0.42, 0.44, 0.46), lockers);
		shade *= 1.0 - 0.45 * lockers * (1.0 - doors) - 0.65 * clamp(bunk + shelf, 0.0, 1.0);
		wall = mix(wall, vec3(0.5, 0.18, 0.14), blanket);
		float screen = step(abs(x + split * 0.6 + 0.15), 0.12) * step(abs(y), 0.1) * step(0.35, fract(seed * 3.7));
		glow = vec3(0.25, 0.75, 0.9) * screen * 1.5;
	} else if (t == ty) {
		if (rd.y < 0.0) {
			// The deck, its plates.
			wall = vec3(0.35, 0.34, 0.32);
			shade *= 0.8 + 0.2 * step(0.08, fract(h.x * 1.6)) * step(0.08, fract(h.z * 1.6));
		} else {
			// The ceiling, its light strip glaring.
			shade *= 0.7;
			glow = vec3(2.5) * step(abs(h.z - lamp.z), 0.07) * step(abs(h.x), size.x * 0.7);
		}
	} else {
		// A side wall, a pipe run along it.
		shade *= 0.9 - 0.5 * step(abs(h.y - size.y * 0.55), 0.04);
	}
	return wall * shade * lit + glow;
}

void fragment() {
	float kind = COLOR.a;
	vec3 p = obj_pos;
	vec3 wn = FRONT_FACING ? world_normal : -world_normal;
	float m = st_noise(p * 2.3);
	float fine = st_noise(p * 13.0);
	vec3 albedo = vec3(0.5);
	float rough = 0.6;
	float metal = 0.0;
	float spec = 0.5;
	vec3 emission = vec3(0.0);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	// How much of the floor's crust and silt it can carry.
	float crusts = 1.0;
	if (kind < 0.1) {
		vec3 c = COLOR.rgb;
		float seam = 0.0;
		float rivets = 0.0;
		if (UV.y > 50.0) {
			// Welded plates: rings every metre, strakes round the hull,
			// rivets along each.
			vec2 h = UV - 100.0;
			float along = abs(fract(h.x + 0.5) - 0.5);
			float around = abs(fract(h.y / 1.14) - 0.5) * 1.14;
			seam = 1.0 - smoothstep(0.004, 0.011, min(along, around));
			vec2 r1 = vec2(along, fract(h.y * 9.0) - 0.5);
			vec2 r2 = vec2(around, fract(h.x * 9.0) - 0.5);
			rivets = 1.0 - smoothstep(0.012, 0.02, min(length(vec2(r1.x - 0.03, r1.y / 9.0)),
				length(vec2(r2.x - 0.03, r2.y / 9.0))));
		}
		// Rust bleeding down from the seams and fittings, grime running
		// down the plates in streaks.
		float bleed = smoothstep(0.5, 0.85, st_noise(vec3(p.x * 11.0, p.y * 0.8, p.z * 11.0)));
		bleed *= smoothstep(0.35 - decay * 0.2, 0.75, m) * (0.4 + 0.6 * seam + 0.3 * smoothstep(0.8, 0.95, fine))
			* (1.0 + decay);
		c = mix(c, vec3(0.38, 0.17, 0.06), clamp(bleed * 0.75 + seam * 0.25, 0.0, 1.0));
		float streaks = st_noise(vec3(p.x * 23.0, p.y * 1.2, p.z * 23.0)) * 0.6 + st_noise(p * 4.0) * 0.4;
		c *= 1.0 - 0.3 * smoothstep(0.45, 0.8, streaks);
		c *= 1.0 - seam * 0.35 - rivets * 0.25;
		// Small chips, mostly along the seams, down to the grey primer.
		float chips = smoothstep(0.8 - decay * 0.12, 0.84 - decay * 0.1,
			st_noise(p * 21.0) * 0.55 + fine * 0.25 + seam * 0.25 + m * 0.15);
		c = mix(c, vec3(0.23, 0.21, 0.2), chips);
		// A film of the floor's life over everything, thickest low down.
		c = mix(c, vec3(0.3, 0.29, 0.22), 0.25 * (1.0 - smoothstep(0.5, 4.0, p.y)) + 0.1 * m);
		c *= (0.8 + 0.25 * m) * mix(0.6, 1.0, smoothstep(-0.2, 3.2, p.y));
		albedo = c;
		rough = mix(0.55, 0.85, clamp(chips + bleed * 0.5, 0.0, 1.0));
	} else if (kind < 0.25) {
		// Frame steel, its paint mostly gone to rust.
		float rust = smoothstep(0.35, 0.75, m * 0.6 + fine * 0.4);
		albedo = mix(vec3(0.17, 0.18, 0.19) * COLOR.rgb * 1.7, vec3(0.32, 0.14, 0.05), rust);
		rough = mix(0.45, 0.92, rust);
		metal = mix(0.55, 0.0, rust);
	} else if (kind < 0.45) {
		albedo = COLOR.rgb * (0.8 + 0.4 * m) + vec3(0.015);
		rough = 0.7;
	} else if (kind < 0.7) {
		// A viewport: dark glass, its room behind it.
		vec3 n = NORMAL;
		vec3 t = normalize(mat3(VIEW_MATRIX) * MODEL_MATRIX[0].xyz);
		t = normalize(t - n * dot(t, n));
		vec3 bt = cross(n, t);
		vec3 r = -VIEW;
		vec3 rd = vec3(dot(r, t), dot(r, bt), dot(r, n));
		float state = COLOR.r;
		float energy = state > 0.75 ? steady_energy : (state > 0.25 ? failing_energy : 0.02);
		vec3 inside = room(vec3(UV, 0.0), rd, COLOR.g) * window_color * energy;
		// Growth filming the glass in a little from its frame.
		float edge = max(abs(UV.x) / 0.25, abs(UV.y) / 0.18);
		edge = COLOR.g > 0.9 ? length(UV) / 0.44 : (COLOR.g > 0.25 && COLOR.g < 0.35 ? length(UV) / 0.26 : edge);
		float film = smoothstep(0.86, 1.0, edge + (fine - 0.5) * 0.12) * 0.8;
		emission += inside * (1.0 - film * 0.7) * (1.0 - fres * 0.6);
		albedo = mix(vec3(0.012, 0.014, 0.016), vec3(0.12, 0.13, 0.1), film);
		rough = mix(0.04, 0.5, film);
		spec = 0.7;
		emission += vec3(0.2, 0.25, 0.3) * fres * 0.15;
		crusts = 0.0;
	} else if (kind < 0.9) {
		albedo = vec3(0.5, 0.48, 0.42);
		rough = 0.12;
		emission += lamp_color * COLOR.r * 3.0;
		crusts = 0.0;
	} else {
		albedo = vec3(0.08, 0.2, 0.12);
		rough = 0.1;
		emission += beacon_color * (0.3 + beacon * 7.0);
		crusts = 0.0;
	}
	// The floor's life crusting the lower parts: dark mats, pale specks of
	// tube worms through them.
	float low = 1.0 - smoothstep(0.5 + decay * 1.2, 2.2 + decay * 1.5, p.y + (m - 0.5) * 1.4);
	float crust = low * smoothstep(0.38, 0.62, st_noise(p * (3.7 + decay * 5.0) + 3.1)) * crusts * (1.0 - decay * 0.8);
	vec3 crust_col = mix(vec3(0.1, 0.09, 0.08), vec3(0.6, 0.55, 0.46), step(0.82, fine));
	albedo = mix(albedo, crust_col, crust * 0.85);
	rough = mix(rough, 0.9, crust);
	metal *= 1.0 - crust;
	// Silt on every face turned up.
	float silt = smoothstep(0.55, 0.9, wn.y + (m - 0.5) * 0.4) * crusts;
	albedo = mix(albedo, sediment_tint * (0.7 + 0.3 * fine), silt * 0.75);
	ALBEDO = albedo;
	ROUGHNESS = mix(rough, 0.95, silt);
	METALLIC = metal * (1.0 - silt);
	SPECULAR = spec;
	vec2 sonar = sonar_sample(world_pos.xy);
	EMISSION = emission + sonar_hue(world_pos.xy) * (sonar.x * 2.0 + sonar.y * 0.4) * (0.3 + fres);
}
