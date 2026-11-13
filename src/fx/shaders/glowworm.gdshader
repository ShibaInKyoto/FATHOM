// The glow-worm grotto: the worms on the ceiling (kind 0), the silk snares
// they let down (kind 1) and the sticky droplets strung along them (kind 2),
// all glowing in the worm's light and added over the dark. Each worm's
// brightness sits in lit_texture (one texel per worm), so the grotto dims
// worm by worm as sound ripples through it. INSTANCE_CUSTOM: x = which
// worm, y = its sway phase, z = how far down its snare a droplet hangs.
// Worms and droplets face the camera; snares and droplets sway slowly in
// the current, the further down, the more.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D lit_texture : filter_nearest;
uniform vec4 glow_color : source_color = vec4(0.45, 1.0, 0.85, 1.0);
uniform float energy = 3.0;
uniform int kind = 0;

varying float bright;
varying vec2 quad_uv;

vec3 sway(float d, float phase) {
	float k = pow(max(d, 0.0), 1.5);
	return vec3(sin(TIME * 0.45 + phase) * 0.06 * k, 0.0, cos(TIME * 0.33 + phase * 1.3) * 0.03 * k);
}

void vertex() {
	float worm = INSTANCE_CUSTOM.x;
	float phase = INSTANCE_CUSTOM.y;
	float lit = texelFetch(lit_texture, ivec2(int(worm + 0.5), 0), 0).r;
	// Each worm's light breathes a little on its own, like a star.
	float twinkle = 0.8 + 0.2 * sin(TIME * 0.6 + worm * 2.39);
	quad_uv = UV;
	if (kind == 1) {
		float length_m = length(MODEL_MATRIX[1].xyz);
		float d = -VERTEX.y * length_m;
		VERTEX.xz += sway(d, phase).xz;
		bright = lit * twinkle * exp(-d * 0.9);
	} else {
		float d = kind == 2 ? INSTANCE_CUSTOM.z : 0.0;
		float s = length(MODEL_MATRIX[0].xyz);
		vec3 centre = MODEL_MATRIX[3].xyz + sway(d, phase);
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(INV_VIEW_MATRIX[0].xyz * s, 0.0),
			vec4(INV_VIEW_MATRIX[1].xyz * s, 0.0), vec4(INV_VIEW_MATRIX[2].xyz * s, 0.0), vec4(centre, 1.0));
		bright = kind == 0 ? lit * twinkle : lit * twinkle * (0.3 + 0.7 * exp(-d * 0.55));
	}
}

void fragment() {
	vec3 light = glow_color.rgb * bright * energy;
	if (kind == 1) {
		ALBEDO = light;
	} else {
		vec2 c = quad_uv * 2.0 - 1.0;
		float r2 = dot(c, c);
		if (kind == 0) {
			// A hot core in a soft halo.
			ALBEDO = light * (exp(-r2 * 40.0) * 2.5 + exp(-r2 * 5.0) * 0.4);
		} else {
			// A droplet: clear in the middle, bright at its rim, a glint
			// where it catches the light.
			float r = sqrt(r2);
			float disc = 1.0 - smoothstep(0.75, 1.0, r);
			float rim = smoothstep(0.5, 0.85, r) * disc;
			float glint = exp(-dot(c - vec2(-0.3, 0.35), c - vec2(-0.3, 0.35)) * 30.0);
			ALBEDO = light * (disc * 0.3 + rim * 0.7 + glint * 1.3);
		}
	}
}
