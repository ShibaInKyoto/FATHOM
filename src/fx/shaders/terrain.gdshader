// Cave terrain: a flat grid extruded into a relief by the level's signed
// distance field. Rock (negative distance) rises towards the camera, open
// water recedes into a deep back wall, and the boundary where the relief
// crosses z = 0 is exactly the gameplay collision surface.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://src/fx/shaders/sonar.gdshaderinc"

uniform sampler2D sdf_tex : filter_linear, repeat_disable;
uniform vec2 field_size = vec2(100.0, 200.0);
uniform vec2 texel_count = vec2(201.0, 401.0);
uniform float rock_height = 4.5;
uniform float back_depth = 10.0;
// Grid spacing of the chunk mesh; used to snap vertices onto the cave outline.
uniform float grid_step = 0.4;

uniform sampler2D detail_noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_rough : hint_roughness_r, filter_linear_mipmap, repeat_enable;
uniform sampler2D sand_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

uniform vec3 rock_tint : source_color = vec3(0.5);
uniform vec3 rock_tint_deep : source_color = vec3(0.3);
uniform vec3 sediment_tint : source_color = vec3(0.7, 0.65, 0.5);
uniform vec3 vein_color : source_color = vec3(0.0);
uniform float vein_strength = 0.0;
uniform float caustics = 0.0;
// Rock moving to the Choir's song (Hadal Trench): centre xy, radius, strength.
uniform vec4 shift_zones[2];
// 0 holds the glow steady (Reduce flashing).
uniform float shift_ripple = 1.0;
uniform float tex_scale = 0.11;
// A seam of volcanic glass in the rock (the singing glass): centre xy, half
// its width across the way in and along it (0 = none); the way across it
// (xy) and the way along it, from the tunnel into the chamber (zw).
uniform vec4 glass_seam = vec4(0.0);
uniform vec4 glass_axis = vec4(1.0, 0.0, 0.0, 1.0);
// x: light within it, y: how hard it rings (0..1), z: its note (1..3),
// w: 1 once it has shattered (only a glassy lip round the opening is left).
uniform vec4 glass_ring = vec4(0.0);
// xy: where the last note struck it (across, along, in metres from its
// centre); z: when (sonar_time); w: when it cracked (sonar_time, or -1).
uniform vec4 glass_strike = vec4(0.0, 0.0, -100.0, -1.0);
uniform vec3 glass_color : source_color = vec3(0.72, 0.55, 1.0);

varying vec3 world_pos;
varying vec3 world_normal;
varying float sdf_value;

float field(vec2 wp) {
	vec2 uv = vec2(wp.x, -wp.y) / field_size;
	uv = uv * (texel_count - 1.0) / texel_count + 0.5 / texel_count;
	return textureLod(sdf_tex, uv, 0.0).r;
}

// Where [param wp] lies on the glass seam, in metres from its centre
// (across the way in, along it).
vec2 seam_local(vec2 wp) {
	vec2 d = wp - glass_seam.xy;
	return vec2(dot(d, glass_axis.xy), dot(d, glass_axis.zw));
}

// How much of the seam's glass there is at [param wp] (0 rock .. 1 glass),
// its edge made irregular as a vein's would be; [param s] the field there.
float seam_mask(vec2 wp, float s) {
	if (glass_seam.z <= 0.0) {
		return 0.0;
	}
	vec2 q = seam_local(wp) / glass_seam.zw;
	float wobble = textureLod(detail_noise, wp * 0.19 + vec2(0.23, 0.57), 0.0).r - 0.5;
	float r = length(q) + wobble * 0.55;
	float m = 1.0 - smoothstep(0.62, 1.0, r);
	if (glass_ring.w > 0.5) {
		// Shattered: a glassy lip round the opening, on the rock's side.
		return m * (1.0 - smoothstep(0.4, 1.4, -s)) * smoothstep(-0.25, 0.05, -s);
	}
	return m * smoothstep(-0.3, 0.5, -s);
}

float relief(vec2 wp) {
	float s = field(wp);
	float n = textureLod(detail_noise, wp * 0.021, 0.0).r - 0.5;
	float n2 = textureLod(detail_noise, wp * 0.083 + vec2(0.37, 0.71), 0.0).r - 0.5;
	if (s < 0.0) {
		float t = tanh(-s / 2.0);
		// Glass sets smooth: in the seam the rock's lumps give way to one
		// gentle swell.
		float g = seam_mask(wp, s);
		float lumps = (n * 4.0 + n2 * 0.8) * (1.0 - g * 0.85);
		return t * (rock_height + lumps * t * t + g * 0.6);
	}
	float t = tanh(s / 2.4);
	float deep = back_depth + clamp(s - 4.0, 0.0, 12.0) * 0.35;
	return -t * (deep + (n * 4.0 + n2 * 0.8) * t * t);
}

vec2 field_gradient(vec2 wp) {
	float e = 0.25;
	return vec2(field(wp + vec2(e, 0.0)) - field(wp - vec2(e, 0.0)),
		field(wp + vec2(0.0, e)) - field(wp - vec2(0.0, e))) / (2.0 * e);
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Pull vertices near the outline onto it so cliffs do not staircase.
	float s0 = field(wp.xy);
	float band = grid_step * 1.6;
	if (abs(s0) < band) {
		vec2 g = field_gradient(wp.xy);
		float gl = length(g);
		if (gl > 0.2) {
			float w = 0.85 * (1.0 - smoothstep(0.0, band, abs(s0)));
			vec2 shift = -(g / gl) * (s0 / gl) * w;
			VERTEX.xy += shift;
			wp.xy += shift;
		}
	}
	float e = 0.3;
	float h = relief(wp.xy);
	float hx = relief(wp.xy + vec2(e, 0.0)) - relief(wp.xy - vec2(e, 0.0));
	float hy = relief(wp.xy + vec2(0.0, e)) - relief(wp.xy - vec2(0.0, e));
	VERTEX.z = h;
	vec3 n = normalize(vec3(-hx / (2.0 * e), -hy / (2.0 * e), 1.0));
	NORMAL = n;
	world_normal = n;
	sdf_value = field(wp.xy);
	world_pos = vec3(wp.xy, h);
}

vec3 unpack_normal(vec4 c) {
	return c.xyz * 2.0 - 1.0;
}

vec2 glass_hash(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

// Obsidian breaks in conchoidal scallops: shallow shell-shaped hollows of
// different sizes, each ringed with fine ripples spreading from the point
// it broke from, blended softly where they meet so the ridges between them
// are sharp but rounded. Returns the slope of the surface at [param q]
// (metres on the seam).
vec2 conchoidal(vec2 q) {
	vec2 cell = q * 0.95;
	vec2 i = floor(cell);
	vec2 f = fract(cell);
	float total = 0.0;
	vec2 slope = vec2(0.0);
	float best = 8.0;
	vec2 best_r = vec2(0.0);
	vec2 best_id = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 h = glass_hash(i + g);
			vec2 r = g + h * 0.8 + 0.1 - f;
			// Each hollow its own depth: a deeper bowl, a steeper wall.
			float depth = 0.6 + 0.8 * fract(h.x * 7.1 + h.y * 3.3);
			float bowl = dot(r, r) * depth;
			// Soft minimum: the hollows meet in rounded creases.
			float w = exp(-bowl * 14.0);
			total += w;
			slope += w * (-2.0 * depth) * r;
			if (bowl < best) {
				best = bowl;
				best_r = r;
				best_id = i + g;
			}
		}
	}
	slope /= max(total, 1e-5);
	// Its ripples, spreading from a point off to one side of it.
	vec2 origin = best_r + (glass_hash(best_id + 7.3) - 0.5) * 0.9;
	float rd = length(origin);
	float ripple = cos(rd * 30.0) * exp(-rd * 1.8) * 0.05;
	return (slope * 0.16 + (origin / max(rd, 0.001)) * ripple) * 0.95;
}

// The flow bands frozen through the glass, at a point within it.
float glass_bands(vec3 p) {
	float w = textureLod(detail_noise, p.xy * 0.11 + p.z * 0.07, 0.0).r;
	float w2 = textureLod(detail_noise, p.xy * 0.37 + vec2(0.3, 0.8), 0.0).r;
	float broad = 0.5 + 0.5 * sin(p.x * 2.3 + p.y * 3.1 + p.z * 4.0 + w * 9.0);
	float fine = 0.5 + 0.5 * sin(p.x * 7.1 - p.y * 5.3 + p.z * 9.0 + w2 * 12.0 + broad * 2.0);
	return broad * 0.72 + fine * broad * 0.28;
}

// Fractures running out from where the glass was struck: a star of nearly
// straight cracks, each bending gently along its length, and arcs round the
// strike. [param q] is in metres from the seam's centre, [param grow] how
// far they have run (0..1); returns how bright the crack is there.
float glass_cracks(vec2 q, float grow) {
	vec2 d = q - glass_strike.xy;
	float rad = length(d);
	float ang = atan(d.y, d.x);
	float spokes = 7.0;
	float a0 = ang / TAU * spokes;
	float k = floor(a0 + 0.5);
	vec2 h = glass_hash(vec2(k, 3.1));
	// Each crack leaves at its own angle and bends a little as it runs.
	float bend = (textureLod(detail_noise, vec2(rad * 0.08 + k * 0.37, k * 0.21), 0.0).r - 0.5) * 0.5;
	float kink = textureLod(detail_noise, vec2(rad * 0.45 + k * 0.53, k * 0.17 + 0.5), 0.0).r - 0.5;
	float off = (h.y - 0.5) * 0.35 + bend * rad * 0.18 + kink * 0.07 * min(rad, 1.5);
	float line = abs(rad * sin((a0 - k) * TAU / spokes) - off);
	float reach = (0.5 + 0.5 * h.x) * grow * 4.2;
	float w = max(fwidth(line), 0.002);
	float core = 1.0 - smoothstep(0.004, 0.004 + w * 1.2, line);
	float halo = exp(-line * 40.0) * 0.25;
	float spoke = (core + halo) * (1.0 - smoothstep(reach * 0.8, reach, rad)) * smoothstep(0.02, 0.15, rad);
	// Arcs round the strike, each running only part of the way round.
	float rings = 0.0;
	for (int j = 0; j < 2; j++) {
		float rr = 0.75 + float(j) * 0.9;
		float arc = step(0.5, glass_hash(vec2(floor(a0 * 1.5), float(j) + 5.0)).x);
		float ring_line = abs(rad - rr - bend * 0.15);
		float rw = max(fwidth(ring_line), 0.002);
		rings += (1.0 - smoothstep(0.003, 0.003 + rw * 1.2, ring_line)) * arc * step(rr + 0.25, grow * 4.2);
	}
	return clamp(spoke + rings * 0.8, 0.0, 1.0);
}

// Below this a projection's share of the triplanar blend is invisible, so its
// three texture reads are skipped (most of the screen faces the camera and
// needs only one projection). The reads use explicit gradients, taken before
// the branches, so mip selection stays exact inside them.
const float PLANE_SKIP = 0.004;

void fragment() {
	vec3 n = normalize(world_normal);
	vec3 blend = pow(abs(n), vec3(4.0));
	blend /= dot(blend, vec3(1.0));
	blend = blend * step(vec3(PLANE_SKIP), blend);
	blend /= dot(blend, vec3(1.0));
	vec2 uv_x = world_pos.zy * tex_scale;
	vec2 uv_y = world_pos.xz * tex_scale;
	vec2 uv_z = world_pos.xy * tex_scale;
	vec2 dx_x = dFdx(uv_x), dy_x = dFdy(uv_x);
	vec2 dx_y = dFdx(uv_y), dy_y = dFdy(uv_y);
	vec2 dx_z = dFdx(uv_z), dy_z = dFdy(uv_z);

	// Triplanar albedo, roughness and normal mapping (UDN blend).
	vec3 alb = vec3(0.0);
	float rough = 0.0;
	vec3 rock_n = vec3(0.0);
	if (blend.x > 0.0) {
		alb += textureGrad(rock_albedo, uv_x, dx_x, dy_x).rgb * blend.x;
		rough += textureGrad(rock_rough, uv_x, dx_x, dy_x).r * blend.x;
		vec3 t = unpack_normal(textureGrad(rock_normal, uv_x, dx_x, dy_x));
		rock_n += vec3(t.xy + n.zy, n.x).zyx * blend.x;
	}
	if (blend.y > 0.0) {
		alb += textureGrad(rock_albedo, uv_y, dx_y, dy_y).rgb * blend.y;
		rough += textureGrad(rock_rough, uv_y, dx_y, dy_y).r * blend.y;
		vec3 t = unpack_normal(textureGrad(rock_normal, uv_y, dx_y, dy_y));
		rock_n += vec3(t.xy + n.xz, n.y).xzy * blend.y;
	}
	if (blend.z > 0.0) {
		alb += textureGrad(rock_albedo, uv_z, dx_z, dy_z).rgb * blend.z;
		rough += textureGrad(rock_rough, uv_z, dx_z, dy_z).r * blend.z;
		vec3 t = unpack_normal(textureGrad(rock_normal, uv_z, dx_z, dy_z));
		rock_n += vec3(t.xy + n.xy, n.z) * blend.z;
	}
	rock_n = normalize(rock_n);

	// Desaturate the photo texture and tint it per biome; the back wall uses
	// the deep tint so the playable layer reads clearly in front of it.
	float lum = dot(alb, vec3(0.299, 0.587, 0.114));
	vec3 base = mix(vec3(lum), alb, 0.25) * 2.0;
	float front = smoothstep(-back_depth * 0.8, 1.0, world_pos.z);
	vec3 tint = mix(rock_tint_deep, rock_tint, front);
	vec3 color = base * tint;

	// Sediment settles on upward-facing slopes.
	float noise_a = texture(detail_noise, world_pos.xy * 0.05).r;
	float sediment = smoothstep(0.4, 0.75, n.y + (noise_a - 0.5) * 0.6) * smoothstep(-back_depth, -1.0, world_pos.z);
	vec3 final_n = rock_n;
	if (sediment > 0.0) {
		vec3 sand_tex = textureGrad(sand_albedo, uv_y * 1.6, dx_y * 1.6, dy_y * 1.6).rgb;
		vec3 sand = mix(vec3(dot(sand_tex, vec3(0.333))), sand_tex, 0.3) * sediment_tint * 1.2;
		vec3 sand_n = unpack_normal(textureGrad(sand_normal, uv_y * 1.6, dx_y * 1.6, dy_y * 1.6));
		sand_n = normalize(vec3(sand_n.xy + n.xz, n.y).xzy);
		color = mix(color, sand, sediment);
		final_n = normalize(mix(rock_n, sand_n, sediment));
	}

	// Cavity darkening on the back wall.
	float cavity = mix(0.45, 1.0, smoothstep(-back_depth - 2.0, 0.5, world_pos.z));
	ALBEDO = color * cavity;
	ROUGHNESS = mix(clamp(rough * 1.1, 0.55, 1.0), 0.95, sediment);
	SPECULAR = 0.35;
	NORMAL = normalize((VIEW_MATRIX * vec4(final_n, 0.0)).xyz);

	vec3 emission = vec3(0.0);

	// The singing glass: rock fused black and glossy round the seam, then
	// obsidian, its light inside it.
	// (The field read per pixel, not interpolated per triangle, so the
	// glass's edge runs smooth across the steep faces.)
	float glass = glass_seam.z > 0.0 ? seam_mask(world_pos.xy, field(world_pos.xy)) : 0.0;
	float glass_body = smoothstep(0.38, 0.72, glass);
	if (glass > 0.001) {
		vec2 q = seam_local(world_pos.xy);
		vec2 conch = conchoidal(q);
		// The surface's own frame, to tip its normal by the scallops.
		vec3 across = vec3(glass_axis.xy, 0.0) - n * dot(vec3(glass_axis.xy, 0.0), n);
		across = length(across) > 0.2 ? normalize(across) : normalize(cross(n, vec3(0.0, 0.0, 1.0)) + vec3(1e-4));
		vec3 along = normalize(cross(n, across));
		float body = glass_body;
		vec3 gn = normalize(n - (across * conch.x + along * conch.y) * body);
		vec3 view_w = normalize(CAMERA_POSITION_WORLD - world_pos);
		float fres = pow(1.0 - clamp(dot(gn, view_w), 0.0, 1.0), 4.0);
		// Inside: the flow bands, seen a little way into the glass, bent by
		// its scalloped face as light is through rippled glass.
		vec3 into = refract(-view_w, gn, 0.66);
		into = length(into) > 0.0 ? into : -n;
		float depth_cos = max(-dot(into, n), 0.35);
		float inner = 0.0;
		for (int k = 1; k <= 3; k++) {
			float dk = float(k) * 0.16;
			// (The light within drifts slowly through it.)
			inner += glass_bands(world_pos + into * dk / depth_cos + vec3(0.0, 0.0, TIME * 0.04))
				* (1.0 - float(k) * 0.22);
		}
		inner /= 2.3;
		vec3 obsidian = vec3(0.008, 0.0075, 0.009) * (0.7 + 0.8 * inner);
		// The contact: rock baked dark and smooth before it turns to glass.
		float fused = smoothstep(0.0, 0.5, glass);
		vec3 rock_baked = ALBEDO * mix(1.0, 0.25, fused);
		ALBEDO = mix(rock_baked, obsidian, body);
		ROUGHNESS = mix(mix(ROUGHNESS, 0.4, fused), 0.03, body);
		SPECULAR = mix(0.35, 0.3, body);
		NORMAL = normalize((VIEW_MATRIX * vec4(mix(final_n, gn, body), 0.0)).xyz);
		// A faint reflection of the vents' glow from below and of the dark
		// above, and a violet sheen in its flow bands at a glance, so the
		// gloss and the depth read.
		vec3 refl = reflect(-view_w, gn);
		vec3 env = mix(vec3(0.07, 0.032, 0.016), vec3(0.008, 0.01, 0.016), smoothstep(-0.4, 0.5, refl.y));
		emission += env * fres * body * 2.2;
		emission += glass_color * smoothstep(0.82, 0.97, inner) * fres * body * 0.035;
		// The chamber's light behind it shows faintly through the glass,
		// caught in its flow bands: strongest on the chamber's side, the
		// tunnel face nearly black.
		float behind = smoothstep(-glass_seam.w * 0.8, glass_seam.w * 0.9, q.y);
		float crest = smoothstep(0.55, 0.95, n.z);
		float streaks = pow(inner, 4.0);
		float through = (0.02 + 2.6 * streaks) * (0.25 + 0.75 * behind) * crest * crest;
		emission += glass_color * through * body * 0.75 * (1.0 - glass_ring.w);

		// Struck: a ripple of light spreads across it from the strike.
		float age = sonar_time - glass_strike.z;
		float rr = length(q - glass_strike.xy);
		if (age > 0.0 && age < 1.6) {
			float front = exp(-pow((rr - age * 5.5) / 0.3, 2.0));
			float wake = (0.5 + 0.5 * cos((rr - age * 5.5) * 7.0)) * step(rr, age * 5.5) * exp(-(age * 5.5 - rr) * 1.4);
			emission += glass_color * (front * 1.8 + wake * 0.35) * (1.0 - age / 1.6) * (0.4 + 0.6 * inner) * body;
		}
		// Ringing: lit from within, the light caught in the flow bands and
		// brightest about the strike, shimmering at its note.
		float shimmer = 0.8 + 0.2 * sin(TIME * (22.0 + 14.0 * glass_ring.z));
		float lit = glass_ring.x * shimmer * (0.55 + 0.45 * exp(-rr * 0.6));
		emission += glass_color * lit * (0.05 + 1.5 * inner * inner * inner) * body;
		emission += glass_color * fused * (1.0 - body) * lit * 0.12;
		// Cracked by the second note.
		if (glass_strike.w > 0.0 && glass_ring.w < 0.5) {
			float grow = smoothstep(0.0, 0.35, sonar_time - glass_strike.w);
			float crack = glass_cracks(q, grow) * body;
			emission += mix(glass_color, vec3(1.0), 0.6) * crack * (1.2 + 2.5 * glass_ring.x);
		}
	}

	// Glowing mineral veins: thin cracks that concentrate near the cave
	// outline, where heat (or something stranger) seeps out of the rock.
	if (vein_strength > 0.0) {
		float v = texture(detail_noise, world_pos.xy * 0.012 + vec2(0.13, 0.4)).r;
		float v2 = texture(detail_noise, world_pos.xy * 0.031 + vec2(0.61, 0.27)).r;
		float ridge = 1.0 - abs(v * 2.0 - 1.0);
		float ridge2 = 1.0 - abs(v2 * 2.0 - 1.0);
		float crack = smoothstep(0.972, 0.995, ridge) + smoothstep(0.978, 0.997, ridge2) * 0.35;
		float halo = smoothstep(0.9, 0.99, ridge) * 0.18;
		float near_edge = 1.0 - smoothstep(0.0, 3.5, abs(sdf_value + 1.0));
		float facing_cam = smoothstep(-1.5, 2.0, world_pos.z);
		float pulse = 0.7 + 0.3 * sin(TIME * 0.6 + world_pos.x * 0.15 + world_pos.y * 0.1);
		emission += vein_color * (crack + halo) * near_edge * facing_cam * vein_strength * pulse * 1.7
			* (1.0 - glass_body);
	}

	// Rock moving to the Choir's song: violet light rippling through it.
	for (int i = 0; i < 2; i++) {
		vec4 zone = shift_zones[i];
		if (zone.w > 0.0) {
			float d = length(world_pos.xy - zone.xy);
			float inside = 1.0 - smoothstep(zone.z * 0.55, zone.z, d);
			float ripple = mix(0.5, 0.5 + 0.5 * sin(d * 1.6 - TIME * 3.5), shift_ripple);
			// Brightest along the moving surface, seeping a little way into the rock.
			float near_surface = 1.0 - smoothstep(0.5, 4.5, abs(sdf_value + 0.5));
			float facing_cam = smoothstep(-2.0, 2.0, world_pos.z);
			emission += vein_color * inside * (0.2 + ripple * 0.8) * near_surface * facing_cam * zone.w;
		}
	}

	// Animated caustics from the surface, mostly on upward faces.
	if (caustics > 0.0) {
		vec2 cp = world_pos.xy * 0.035 + vec2(world_pos.z * 0.02, 0.0);
		float c1 = texture(detail_noise, cp + vec2(TIME * 0.011, TIME * 0.007)).r;
		float c2 = texture(detail_noise, cp * 1.21 - vec2(TIME * 0.009, -TIME * 0.01)).r;
		float web = pow(1.0 - abs(c1 - c2), 9.0);
		float facing = clamp(n.y * 0.9 + n.z * 0.3, 0.0, 1.0) * smoothstep(-4.0, 2.0, world_pos.z);
		emission += vec3(0.6, 0.9, 1.0) * web * caustics * facing * 0.35 * color;
	}

	// Sonar: a bright wavefront, then a fading contour map of the walls.
	vec2 sonar = sonar_sample(world_pos.xy);
	if (sonar.x + sonar.y > 0.001) {
		float wall = 1.0 - abs(n.z);
		float contour = smoothstep(0.82, 1.0, abs(fract(world_pos.z * 0.6) * 2.0 - 1.0));
		float grid = max(smoothstep(0.94, 1.0, abs(fract(world_pos.x * 0.25) * 2.0 - 1.0)),
			smoothstep(0.94, 1.0, abs(fract(world_pos.y * 0.25) * 2.0 - 1.0))) * step(world_pos.z, -2.0);
		float edge = smoothstep(1.5, 0.0, abs(sdf_value)) ;
		float lines = wall * 0.35 + contour * 0.3 + grid * 0.15 + edge * 1.2;
		emission += sonar_hue(world_pos.xy) * (sonar.x * (0.35 + lines * 1.1) + sonar.y * lines * 0.22);
	}
	EMISSION = emission;
}
