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

varying vec3 world_pos;
varying vec3 world_normal;
varying float sdf_value;

float field(vec2 wp) {
	vec2 uv = vec2(wp.x, -wp.y) / field_size;
	uv = uv * (texel_count - 1.0) / texel_count + 0.5 / texel_count;
	return textureLod(sdf_tex, uv, 0.0).r;
}

float relief(vec2 wp) {
	float s = field(wp);
	float n = textureLod(detail_noise, wp * 0.021, 0.0).r - 0.5;
	float n2 = textureLod(detail_noise, wp * 0.083 + vec2(0.37, 0.71), 0.0).r - 0.5;
	if (s < 0.0) {
		float t = tanh(-s / 2.0);
		return t * (rock_height + (n * 4.0 + n2 * 0.8) * t * t);
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
		emission += vein_color * (crack + halo) * near_edge * facing_cam * vein_strength * pulse * 1.7;
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
		emission += sonar_color.rgb * (sonar.x * (0.35 + lines * 1.1) + sonar.y * lines * 0.22);
	}
	EMISSION = emission;
}
