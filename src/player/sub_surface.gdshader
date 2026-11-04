shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
// Paint and metal for the submarines. A livery pattern (projected three ways
// in the model's own space, so it needs no UVs), optional paint-shop maps on
// the hull's UVs (seams, rivets, grime and lettering, with their bumps), and
// wear: bare metal shows through on edges and dirt gathers in crevices, both
// marked in the vertex color (R paint left, G clean) of meshes built for it.

uniform vec3 paint : source_color = vec3(1.0, 0.6, 0.1);
uniform float metallic = 0.1;
uniform float roughness = 0.42;
// A clear coat over the paint: a second, sharper highlight.
uniform float coat = 0.0;
uniform float rim = 0.25;
// The livery's pattern (its colors, multiplied over the paint) and glow.
uniform bool use_pattern = false;
uniform sampler2D pattern_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D glow_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float glow_energy = 0.0;
uniform float pattern_scale = 0.9;
// Paint-shop maps: an RGB multiply (its alpha the paint left: below 1 the
// paint has flaked off to rust) and a normal map.
uniform bool use_maps = false;
uniform sampler2D paint_map : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;
uniform float normal_depth = 1.0;
uniform vec3 rust : source_color = vec3(0.42, 0.22, 0.11);
// Wear read from the vertex color; off for meshes that don't carry it.
uniform bool vertex_wear = false;
uniform float wear = 0.6;
uniform vec3 bare : source_color = vec3(0.6, 0.61, 0.62);
// Mottled roughness, so broad faces don't read as plastic.
uniform float mottle = 0.12;
// Wrecks and derelicts: everything darker and the glow dimmed.
uniform float darken = 0.0;
// Round holes cut through the skin (centre and radius, in the model's own
// space), where a port looks in through it.
uniform vec4 holes[4];
uniform int hole_count = 0;

varying vec3 obj_pos;
varying vec3 obj_nrm;

void vertex() {
	obj_pos = VERTEX;
	obj_nrm = NORMAL;
}

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

vec3 triplanar(sampler2D tex, vec3 p, vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	p *= pattern_scale;
	return texture(tex, p.zy).rgb * w.x + texture(tex, p.xz).rgb * w.y + texture(tex, p.xy).rgb * w.z;
}

void fragment() {
	for (int i = 0; i < hole_count; i++) {
		if (distance(obj_pos, holes[i].xyz) < holes[i].w) {
			discard;
		}
	}
	vec3 col = paint;
	if (use_pattern) {
		col *= triplanar(pattern_tex, obj_pos, obj_nrm);
	}
	float rough = roughness;
	float metal = metallic;
	float grime = 0.0;
	float rusted = 0.0;
	if (use_maps) {
		vec4 m = texture(paint_map, UV);
		col *= m.rgb;
		// Grime and lettering are matte.
		rough = mix(rough, 0.75, clamp(1.0 - m.g, 0.0, 1.0));
		rusted = 1.0 - m.a;
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = normal_depth;
	}
	float n1 = noise(obj_pos * 7.0);
	float n2 = noise(obj_pos * 31.0);
	float worn = 0.0;
	if (vertex_wear) {
		float edge = 1.0 - COLOR.r;
		// Chipped, not a clean band: the noise breaks the worn edge up.
		worn = smoothstep(0.62, 0.8, edge * wear + (n1 * 0.6 + n2 * 0.4) * 0.5);
		grime = (1.0 - COLOR.g) * (0.5 + 0.5 * n1);
	}
	col = mix(col, bare * (0.8 + 0.3 * n2), worn);
	col = mix(col, rust * (0.65 + 0.7 * n2) * mix(vec3(1.0), vec3(0.85, 1.0, 1.15), n1), rusted);
	col *= 1.0 - grime * 0.55;
	metal = mix(metal, 0.9, worn);
	rough = mix(rough, 0.38, worn) + (n1 - 0.5) * mottle;
	ALBEDO = col * (1.0 - darken);
	METALLIC = metal;
	metal = mix(metal, 0.25, rusted);
	ROUGHNESS = clamp(mix(rough + grime * 0.3, 0.85, rusted), 0.04, 1.0);
	CLEARCOAT = coat * (1.0 - worn) * (1.0 - rusted);
	CLEARCOAT_ROUGHNESS = 0.18;
	RIM = rim;
	RIM_TINT = 0.6;
	if (glow_energy > 0.0) {
		EMISSION = triplanar(glow_tex, obj_pos, obj_nrm) * glow_energy * (1.0 - darken);
	}
}
