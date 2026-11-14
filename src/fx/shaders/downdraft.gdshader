// The way down (DescentMarker): water rushing down into the fissure, seen as
// the cave behind it wavering through the moving water, faster the lower it
// goes, the column narrowing as it is drawn in, with faint streaks of silt
// pulled down through it. [flow] 0 when the way is sealed (still).
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform vec3 tint : source_color = vec3(0.75, 0.86, 0.9);
uniform float flow = 1.0;
uniform float strength = 1.0;

float dh(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float dn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(dh(i), dh(i + vec2(1.0, 0.0)), f.x), mix(dh(i + vec2(0.0, 1.0)), dh(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	// UV: x across the column, y from its top (0) down into the fissure (1).
	float across = abs(UV.x - 0.5) * 2.0;
	float width = mix(1.0, 0.3, smoothstep(0.25, 1.0, UV.y));
	float inside = 1.0 - smoothstep(width * 0.45, width, across);
	float ends = smoothstep(0.0, 0.3, UV.y) * (1.0 - smoothstep(0.9, 1.0, UV.y));
	float k = inside * ends * strength;
	float t = TIME * flow;
	// Drawn in towards the middle as it falls.
	float x = (UV.x - 0.5) / width;
	float speed = 1.2 + UV.y * 2.5;
	vec2 q = vec2(x * 5.0, UV.y * 3.0 - t * speed);
	float n1 = dn(q) + 0.5 * dn(q * 2.7 + 3.1);
	float n2 = dn(q + vec2(7.3, 1.7)) + 0.5 * dn(q * 2.3 + 9.2);
	vec2 bend = vec2(n1 - 0.75, (n2 - 0.75) * 0.6) * 0.035 * k;
	// Pulled inwards a touch, like water funnelling.
	bend.x -= x * 0.012 * k * UV.y;
	vec3 behind = textureLod(screen, SCREEN_UV + bend, 0.0).rgb;
	// Fine streaks of silt rushing down through it.
	float streak = pow(dn(vec2(x * 38.0, UV.y * 1.2 - t * speed * 1.6)), 9.0);
	float sheen = pow(n1 / 1.5, 4.0) * 0.08;
	ALBEDO = behind + tint * (streak * 0.5 + sheen) * k;
	ALPHA = clamp(k * 1.2, 0.0, 1.0);
}
