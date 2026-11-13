// Volcanic glass (the Abyssal Vents' singing glass): near-black, mirror-
// glossy, its fracture facets crisp (normals from the screen, so each face
// is flat), faint flow bands drawn through it, a violet glow where the glass
// is thin at its edges. Ringing ([code]ringing[/code], at its
// [code]note[/code]: 1, 2, 3) it lights in a standing wave: glowing nodal
// lines that grow finer with each higher note and shimmer at its pitch;
// [code]crack[/code] runs glowing fractures through it; [code]ring[/code]
// lights it from within. UV: where on the seam (-1..1 across and along).
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://src/fx/shaders/sonar.gdshaderinc"

uniform vec4 glow_color : source_color = vec4(0.72, 0.55, 1.0, 1.0);
uniform float ring = 0.0;
uniform float ringing = 0.0;
uniform float note = 1.0;
uniform float crack = 0.0;

varying vec3 world_pos;
varying vec3 obj_pos;

void vertex() {
	obj_pos = VERTEX;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec3 obsidian_hash(vec3 p) {
	p = vec3(dot(p, vec3(127.1, 311.7, 74.7)), dot(p, vec3(269.5, 183.3, 246.1)), dot(p, vec3(113.5, 271.9, 124.6)));
	return fract(sin(p) * 43758.5453123);
}

// Distance to the nearest crack: the edges between cells of a 2D cell noise.
float obsidian_cracks(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = obsidian_hash(vec3(i + g, 3.7)).xy;
			float d = length(g + o - f);
			if (d < d1) {
				d2 = d1;
				d1 = d;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return d2 - d1;
}

void fragment() {
	// Flat facets: the face's own normal, from the screen.
	vec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	n = dot(n, VIEW) < 0.0 ? -n : n;
	NORMAL = n;
	float facing = clamp(dot(n, VIEW), 0.0, 1.0);
	float edge = pow(1.0 - facing, 5.0);
	vec2 uv = UV;
	float r = length(uv);
	// Flow bands: the lava's layers, frozen.
	float band = 0.5 + 0.5 * sin(obj_pos.x * 3.1 + obj_pos.y * 4.3 + sin(obj_pos.x * 1.7 - obj_pos.y) * 2.0);
	ALBEDO = vec3(0.022, 0.018, 0.03) * (0.85 + 0.3 * band);
	// Glossy, but black: only the sharpest highlights come back off it.
	ROUGHNESS = 0.1 + 0.05 * band;
	SPECULAR = 0.12;
	// Thin at the rim: the light comes through violet.
	float thin = smoothstep(0.65, 1.0, r);
	// At rest only a faint violet at its thinnest edges; ringing, it lights.
	vec3 glow = glow_color.rgb * (edge * (0.01 + 1.2 * ring) + thin * 0.006 + ring * (0.05 + 0.25 * facing));
	// The standing wave: nodal lines across the glass, finer with each note,
	// pulsing at its pitch.
	float k = 2.0 + 2.5 * note;
	float wave = abs(sin(uv.x * k * 1.6 + 0.4) * sin(uv.y * k + 0.9) + 0.3 * sin(r * k * 2.2));
	float nodes = 1.0 - smoothstep(0.0, 0.12, wave);
	float pulse = 0.65 + 0.35 * sin(TIME * (30.0 + 18.0 * note));
	glow += glow_color.rgb * nodes * ringing * pulse * (1.2 + 0.6 * note);
	// Cracks running through it, white-hot violet.
	float c = obsidian_cracks(uv * 3.2);
	float reach = smoothstep(1.1, 0.0, r / max(crack * 1.6, 0.001));
	float fracture = (1.0 - smoothstep(0.0, 0.05, c)) * step(0.01, crack) * reach;
	glow += mix(glow_color.rgb, vec3(1.0), 0.4) * fracture * (0.8 + 2.0 * ring);
	vec2 sonar = sonar_sample(world_pos.xy);
	EMISSION = glow + sonar_color.rgb * (sonar.x * 2.0 + sonar.y * 0.4) * (0.3 + edge);
}
