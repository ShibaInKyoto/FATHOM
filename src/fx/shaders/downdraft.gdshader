// The way down (DescentMarker): water rushing down into the fissure, seen as
// the cave behind it wavering through the moving water, faster the lower it
// goes, the column narrowing as it is drawn in, with faint streaks of silt
// pulled down through it. Worked in the quad's own space ([half_size]), +y
// up: everything in it moves down. [flow] 0 when the way is sealed (still).
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform vec3 tint : source_color = vec3(0.75, 0.86, 0.9);
uniform vec2 half_size = vec2(3.75, 7.0);
uniform float flow = 1.0;
uniform float strength = 1.0;

varying vec3 local;

float dh(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float dn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(dh(i), dh(i + vec2(1.0, 0.0)), f.x), mix(dh(i + vec2(0.0, 1.0)), dh(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	local = VERTEX;
}

void fragment() {
	// 0 at the top of the column, 1 down at the fissure.
	float down = clamp(0.5 - local.y / (2.0 * half_size.y), 0.0, 1.0);
	float width = mix(1.0, 0.28, smoothstep(0.2, 1.0, down));
	float x = local.x / half_size.x / width;
	float inside = 1.0 - smoothstep(0.45, 1.0, abs(x));
	float ends = smoothstep(0.0, 0.3, down) * (1.0 - smoothstep(0.9, 1.0, down));
	float k = inside * ends * strength;
	float t = TIME * flow;
	// The pattern scrolls down the column at a constant rate in a stretched
	// coordinate that is squeezed lower down, so it rushes faster the lower
	// it goes (about four times as fast at the fissure as at the top). The
	// stretch depends on position only, never on time, so it can only ever
	// move down.
	float drop = 2.1 * log(1.0 + 3.0 * down);
	vec2 q = vec2(x * 5.0, drop - t * 1.8);
	float n1 = dn(q) + 0.5 * dn(q * 1.9 + 3.1);
	float n2 = dn(q + vec2(7.3, 1.7)) + 0.5 * dn(q * 1.7 + 9.2);
	vec2 bend = vec2(n1 - 0.75, (n2 - 0.75) * 0.6) * 0.035 * k;
	// Drawn in towards the middle, the more so lower down.
	bend.x -= x * 0.015 * k * down;
	vec3 behind = textureLod(screen, SCREEN_UV + bend, 0.0).rgb;
	// Fine streaks of silt rushing down through it.
	float streak = pow(dn(vec2(x * 38.0, drop * 0.27 - t * 0.85)), 9.0);
	float sheen = pow(n1 / 1.5, 4.0) * 0.08;
	ALBEDO = behind + tint * (streak * 0.5 + sheen) * k;
	ALPHA = clamp(k * 1.2, 0.0, 1.0);
}
