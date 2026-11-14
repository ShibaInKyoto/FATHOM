// MD-02, Vasquez's drone (DroneModel). COLOR.a is each part's material:
// 0 orange-painted syntactic foam, 0.2 metal, 0.3 dark metal and plastic,
// 0.4 rubber hose, 0.6 the pilot's acrylic sphere, 0.8 a lamp lens, 1 the
// status lamp; COLOR.rgb a value of each part's own (a lens: 1 if it still
// works; metal and rubber: a tint). Painted faces are chipped, scraped and
// grimed; hazard stripes run across the float's nose; silt dusts the faces
// turned up. Behind the sphere's acrylic a console still glows faintly red.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://src/fx/shaders/sonar.gdshaderinc"

uniform vec3 sediment_tint : source_color = vec3(0.4, 0.38, 0.34);
uniform vec3 paint : source_color = vec3(0.86, 0.43, 0.07);
uniform vec3 work_light : source_color = vec3(1.0, 0.86, 0.6);
uniform vec3 status_light : source_color = vec3(1.0, 0.18, 0.1);
// How bright the guttering work lamp, the status lamp and the console are.
uniform float work = 1.0;
uniform float status = 0.0;
uniform float console = 1.0;

varying vec3 obj_pos;
varying vec3 obj_n;
varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	obj_pos = VERTEX;
	obj_n = NORMAL;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float drone_noise(vec3 p) {
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

void fragment() {
	float kind = COLOR.a;
	vec3 p = obj_pos;
	float m = drone_noise(p * 3.0);
	float fine = drone_noise(p * 17.0);
	vec3 albedo;
	float rough;
	float metal = 0.0;
	vec3 emission = vec3(0.0);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	if (kind < 0.1) {
		// Painted foam: chipped to grey primer at its edges and corners,
		// scraped along its length, grimed low down.
		// Chips mostly where it has been knocked: its edges and corners.
		vec3 an = abs(normalize(obj_n));
		float edge = 1.0 - max(an.x, max(an.y, an.z));
		float chips = smoothstep(0.7, 0.76, drone_noise(p * 11.0) * 0.6 + fine * 0.4 + edge * 0.5 - 0.12);
		float scrape = smoothstep(0.75, 0.95, drone_noise(vec3(p.x * 1.5, p.y * 24.0, p.z * 24.0)));
		vec3 c = paint * (0.75 + 0.35 * m);
		c = mix(c, vec3(0.22, 0.21, 0.2), chips);
		// Panel seams and rows of bolts on the float's flat faces.
		if (p.y > 0.12) {
			float seam = 1.0 - smoothstep(0.004, 0.012, abs(fract(p.x * 1.6 + 0.3) - 0.5) * 0.625);
			float mid = 1.0 - smoothstep(0.004, 0.01, abs(p.y - 0.42));
			float bolts = (1.0 - smoothstep(0.012, 0.02, length(vec2(fract(p.x * 8.0) - 0.5, (p.y - 0.62) * 8.0) / 8.0)));
			float side_face = step(0.9, an.z);
			c *= 1.0 - (max(seam, mid) * 0.55 + bolts * 0.4) * side_face;
		}
		c = mix(c, c * 0.55, scrape * 0.6);
		// Hazard stripes across the nose.
		if (obj_n.x > 0.6 && p.y > 0.2) {
			float stripe = step(0.5, fract((p.y + p.z) * 3.2));
			c = mix(c, vec3(0.04), stripe * (1.0 - chips));
		}
		c *= mix(0.55, 1.0, smoothstep(-0.7, 0.4, p.y));
		albedo = c;
		rough = mix(0.62, 0.85, chips);
	} else if (kind < 0.25) {
		// Metal: anodised grey, scratched, a little brighter where the tint asks.
		float scratch = smoothstep(0.82, 0.95, drone_noise(vec3(p.x * 30.0, p.y * 2.0, p.z * 30.0)));
		albedo = vec3(0.4, 0.42, 0.44) * COLOR.r * (0.8 + 0.3 * m) + scratch * 0.15;
		rough = 0.35 + 0.2 * m;
		metal = 0.75;
	} else if (kind < 0.35) {
		albedo = vec3(0.05, 0.05, 0.055) * (0.8 + 0.4 * m) + COLOR.rgb * 0.15;
		rough = 0.55;
		metal = 0.3;
	} else if (kind < 0.5) {
		albedo = mix(vec3(0.03), vec3(0.75, 0.6, 0.08), COLOR.r) * (0.8 + 0.3 * m);
		rough = 0.75;
	} else if (kind < 0.7) {
		// The acrylic sphere: dark and glossy, a dim red console glowing
		// within, seen most where the view looks straight in.
		albedo = vec3(0.015, 0.018, 0.022);
		rough = 0.04;
		float into = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
		float panel = smoothstep(0.1, -0.4, obj_n.y) * smoothstep(-0.3, 0.6, obj_n.x);
		emission += status_light * into * into * panel * 0.07 * console;
		emission += vec3(0.25, 0.3, 0.35) * fres * 0.25;
	} else if (kind < 0.9) {
		albedo = vec3(0.6, 0.58, 0.5);
		rough = 0.1;
		emission += work_light * COLOR.r * work * 3.0;
	} else {
		albedo = vec3(0.3, 0.05, 0.04);
		rough = 0.2;
		emission += status_light * (0.2 + status * 5.0);
	}
	// Silt on the faces turned up.
	float silt = smoothstep(0.55, 0.9, world_normal.y + (m - 0.5) * 0.4) * step(kind, 0.5);
	albedo = mix(albedo, sediment_tint * (0.7 + 0.3 * fine), silt * 0.7);
	ALBEDO = albedo;
	ROUGHNESS = mix(rough, 0.95, silt);
	METALLIC = metal * (1.0 - silt);
	vec2 sonar = sonar_sample(world_pos.xy);
	EMISSION = emission + sonar_hue(world_pos.xy) * (sonar.x * 2.0 + sonar.y * 0.4) * (0.3 + fres);
}
