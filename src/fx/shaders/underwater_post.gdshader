// Full-screen underwater pass drawn under the HUD: gentle refraction wobble,
// chromatic fringing towards the edges, a soft vignette and film grain.
shader_type canvas_item;

// Plain linear filtering: the pass only ever reads the full-size image, and
// asking for mipmaps would make the renderer build a whole mip chain of the
// screen every frame (costly at 4K) for nothing.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform float wobble = 0.0012;
uniform float aberration = 0.0022;
uniform float grain = 0.035;
uniform float vignette = 0.2;
uniform float damage = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 n = texture(noise_tex, uv * 1.6 + vec2(TIME * 0.025, TIME * 0.018)).rg - 0.5;
	uv += n * wobble * (1.0 + damage * 4.0);
	vec2 from_center = uv - 0.5;
	float edge = dot(from_center, from_center);
	vec2 shift = from_center * aberration * (edge * 4.0 + damage * 2.0);
	vec3 col;
	col.r = texture(screen_tex, uv + shift).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - shift).b;
	float v = 1.0 - smoothstep(0.25, 0.95, edge * 2.4) * vignette;
	float g = fract(sin(dot(uv * 1000.0 + TIME * 13.7, vec2(12.9898, 78.233))) * 43758.5453);
	col = col * v + (g - 0.5) * grain;
	COLOR = vec4(col, 1.0);
}
