// The Choir's flesh, drawn solid (choir.gdshader) or see-through
// (choir_glass.gdshader): deep violet, lit from within. Vertex colour R
// marks its lights (glowing a little always), G its comb rows (beating with
// a shimmer of rainbow light), B its core (always bright). UV2.x is how far
// a point lies from the heart along the body, so the light of each song
// races out from the heart along its veins and down its tentacles; UV2.y is
// how far along its comb row a comb lies.
// Its skin is a membrane of cells (in the body's own space) with grooves
// between them, webbed with branching capillaries, finely wrinkled, here and
// there a cell lit as a freckle of light, and over it all a thin film's
// rainbow sheen where the skin turns away.
#include "res://src/fx/shaders/sonar.gdshaderinc"

uniform vec4 body_color : source_color = vec4(0.1, 0.03, 0.14, 1.0);
uniform vec4 glow_color : source_color = vec4(1.0, 0.35, 0.85, 1.0);
uniform float glow_strength = 2.5;
uniform float roughness : hint_range(0.0, 1.0) = 0.3;
uniform float rim_strength = 0.8;
// See-through: how opaque it is face on and at its edges.
uniform float alpha_face = 1.0;
uniform float alpha_edge = 1.0;
// Branching veins over the skin (0 for none): their size (per metre) and
// how bright they glow.
uniform float vein_scale = 0.0;
uniform float vein_glow = 0.0;
// The membrane's cells: how many to a metre (0 for none), how deep the
// grooves between them; the share of them lit as freckles; how deep its fine
// wrinkles; how strong the thin film's sheen.
uniform float cell_scale = 0.0;
uniform float cell_relief = 0.015;
uniform float freckles = 0.0;
uniform float wrinkles = 0.0;
uniform float iridescence = 0.0;
// The comb rows' shimmer: how bright, and how fast its beat runs along them.
uniform float comb_glow = 1.5;
uniform float comb_speed = 3.0;
// How fast the light of a song runs out from the heart (metres a second),
// and how long a stretch of it is lit at once.
uniform float pulse_speed = 18.0;
uniform float pulse_width = 2.5;
// Seconds since it last sang.
instance uniform float song = 99.0;
instance uniform float glow_boost = 1.0;
// The colour its light has turned towards (rgb), and how far (a).
instance uniform vec4 tint = vec4(0.5, 1.0, 1.0, 0.0);
instance uniform float hit_flash = 0.0;
instance uniform float marked = 0.0;
// Lit all over (0 to 1): a tentacle about to strike, a throat laid open.
instance uniform float flare = 0.0;

varying vec3 obj_pos;
varying vec3 world_pos;

void vertex() {
	obj_pos = VERTEX;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float choir_noise(vec3 p) {
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

vec3 choir_hash3(vec3 p) {
	p = vec3(dot(p, vec3(127.1, 311.7, 74.7)), dot(p, vec3(269.5, 183.3, 246.1)), dot(p, vec3(113.5, 271.9, 124.6)));
	return fract(sin(p) * 43758.5453123);
}

// The distance to the nearest cell's centre and to the next (F1, F2), and a
// random value for the nearest cell.
vec3 choir_cells(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	float id = 0.0;
	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 g = vec3(float(x), float(y), float(z));
				vec3 o = choir_hash3(i + g);
				vec3 r = g + o * 0.85 - f;
				float d = dot(r, r);
				if (d < d1) {
					d2 = d1;
					d1 = d;
					id = o.y;
				} else if (d < d2) {
					d2 = d;
				}
			}
		}
	}
	return vec3(sqrt(d1), sqrt(d2), id);
}

// Bends the normal by the screen-space slope of a height field [param h].
vec3 choir_bumped(vec3 n, vec3 view_pos, float h) {
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
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	vec3 base = body_color.rgb;
	float relief = 0.0;
	float freckle = 0.0;
	// How big a pixel is here, so detail too fine to see fades rather than
	// shimmers.
	float px = 0.5 * (length(dFdx(obj_pos)) + length(dFdy(obj_pos)));
	if (cell_scale > 0.0) {
		vec3 c = choir_cells(obj_pos * cell_scale);
		float seen = 1.0 - smoothstep(0.15, 0.4, px * cell_scale);
		float wall = (1.0 - smoothstep(0.0, 0.14, c.y - c.x)) * seen;
		relief += (0.4 * (1.0 - c.x) - wall) * cell_relief;
		base *= mix(1.0, 0.7 + 0.6 * c.z, seen);
		base = mix(base, base * 0.45, wall);
		freckle = (1.0 - smoothstep(0.1, 0.2, c.x)) * step(1.0 - freckles, fract(c.z * 7.31)) * seen;
	}
	if (wrinkles > 0.0) {
		float w = choir_noise(obj_pos * vec3(9.0, 3.0, 9.0)) * 0.6 + choir_noise(obj_pos * 23.0) * 0.4;
		relief += (w - 0.5) * wrinkles * (1.0 - smoothstep(0.02, 0.06, px));
	}
	vec3 glow = mix(glow_color.rgb, tint.rgb, tint.a);
	// Each song's light: a band racing out from the heart, fading as it goes.
	float ahead = song * pulse_speed - UV2.x;
	float wave = exp(-pow(ahead / pulse_width, 2.0)) * exp(-song * 0.3);
	float veins = 0.0;
	if (vein_scale > 0.0) {
		// Ridges of noise bent by noise: trunks that wander and fork, and
		// finer capillaries between them.
		vec3 q = obj_pos * vein_scale;
		vec3 warp = vec3(choir_noise(q * 0.5), choir_noise(q * 0.5 + 3.7), choir_noise(q * 0.5 + 9.1)) - 0.5;
		q += warp * 1.6;
		float n1 = 1.0 - abs(choir_noise(q) * 2.0 - 1.0);
		float n2 = 1.0 - abs(choir_noise(q * 2.6 + 7.1) * 2.0 - 1.0);
		float n3 = 1.0 - abs(choir_noise(q * 6.1 + 2.3) * 2.0 - 1.0);
		veins = pow(n1, 16.0) + 0.55 * pow(n2, 20.0) + 0.3 * pow(n3, 24.0) * (1.0 - smoothstep(0.03, 0.08, px));
		relief += veins * 0.01;
	}
	float lights = COLOR.r + veins * vein_glow + freckle;
	// The core glows from within: brightest face on, dimmer where it turns away.
	float core = COLOR.b * (0.3 + 0.7 * (1.0 - fres));
	vec3 em = glow * glow_strength * glow_boost * (lights * (0.4 + 2.4 * wave) + core * (1.0 + 0.8 * wave));
	em += glow * glow_strength * flare * (0.3 + 0.9 * fres);
	if (COLOR.g > 0.0) {
		// Comb rows: their beat runs down them, each comb catching the light
		// in a shifting rainbow.
		float beat = pow(0.5 + 0.5 * sin(UV2.y * 14.0 - TIME * comb_speed * 6.0), 3.0);
		vec3 rainbow = 0.5 + 0.5 * cos(6.2832 * (UV2.y * 0.08 - TIME * 0.2 + vec3(0.0, 0.33, 0.67)));
		em += mix(rainbow, glow, 0.3) * COLOR.g * comb_glow * (0.25 + beat) * max(glow_boost, 0.3);
	}
	if (iridescence > 0.0) {
		// A thin film's colours, shifting with the angle it is seen at.
		vec3 film = 0.5 + 0.5 * cos(6.2832 * (fres * 1.6 + obj_pos.y * 0.05 + vec3(0.0, 0.33, 0.67)));
		em += film * fres * iridescence * max(glow_boost, 0.3);
	}
	if (relief != 0.0) {
		NORMAL = choir_bumped(NORMAL, VERTEX, relief);
	}
	vec2 sonar = sonar_sample(world_pos.xy);
	em += sonar_color.rgb * (sonar.x * 3.0 * (0.4 + fres) + marked * fres * 1.6);
	em += vec3(1.0, 0.9, 0.95) * hit_flash * 2.0;
	ALBEDO = base * (1.0 + veins * 0.6);
	ROUGHNESS = roughness;
	SPECULAR = 0.6;
	RIM = rim_strength;
	RIM_TINT = 0.6;
	EMISSION = em;
#ifdef GLASS
	ALPHA = clamp(mix(alpha_face, alpha_edge, fres) + lights * 0.25 + COLOR.g * 0.3 + COLOR.b + hit_flash
		+ marked * 0.3 + sonar.x, 0.0, 1.0);
#endif
}
