// Shared sonar ping evaluation. Pings are pushed by SonarSystem into global
// uniforms: xy = origin (world), z = start time (sonar_time clock), w = range.
global uniform vec4 sonar_ping0;
global uniform vec4 sonar_ping1;
global uniform vec4 sonar_ping2;
global uniform vec4 sonar_ping3;
global uniform float sonar_time;
global uniform vec4 sonar_color : source_color;
// The Hadal Trench's echo (ChoirEcho): the sub's ping coming back from far
// below. xy = origin, z = start time (sonar_time), w = range (0: none).
global uniform vec4 echo_ping;
global uniform vec4 echo_color : source_color;

const float SONAR_SPEED = 42.0;
const float SONAR_LIFE = 6.0;
// The echo comes back slowed down.
const float ECHO_SPEED = 16.0;

// Returns (wavefront, lingering reveal) for one ping at world point p.
vec2 sonar_eval(vec4 ping, vec2 p) {
	float age = sonar_time - ping.z;
	if (age < 0.0 || age > SONAR_LIFE) {
		return vec2(0.0);
	}
	float d = distance(p, ping.xy);
	float radius = age * SONAR_SPEED;
	float range_fade = 1.0 - smoothstep(ping.w * 0.7, ping.w, d);
	float front = exp(-pow((d - radius) / 1.1, 2.0)) * range_fade;
	float since = age - d / SONAR_SPEED;
	float reveal = step(0.0, since) * range_fade * exp(-since * 0.7);
	return vec2(front, reveal) * (1.0 - age / SONAR_LIFE);
}

// The echo at world point p: (wavefront, lingering reveal). Stretched into
// something like a word: a cluster of uneven bands behind its front, like
// syllables, the whole front wavering round its circle as a voice does.
vec2 echo_eval(vec2 p) {
	if (echo_ping.w <= 0.0) {
		return vec2(0.0);
	}
	float age = sonar_time - echo_ping.z;
	float life = echo_ping.w / ECHO_SPEED + 3.0;
	if (age < 0.0 || age > life) {
		return vec2(0.0);
	}
	vec2 d = p - echo_ping.xy;
	float r = length(d);
	float ang = atan(d.y, d.x);
	float waver = sin(ang * 7.0 + age * 2.3) * 0.45 + sin(ang * 13.0 - age * 3.1) * 0.2;
	// How far behind the leading front the point is.
	float x = age * ECHO_SPEED - r + waver;
	float front = exp(-pow(x / 0.7, 2.0))
		+ exp(-pow((x - 1.8) / 0.5, 2.0)) * 0.55
		+ exp(-pow((x - 2.9) / 0.9, 2.0)) * 0.85
		+ exp(-pow((x - 5.2) / 0.6, 2.0)) * 0.4
		+ exp(-pow((x - 6.4) / 1.1, 2.0)) * 0.6;
	float range_fade = 1.0 - smoothstep(echo_ping.w * 0.75, echo_ping.w, r);
	float since = age - r / ECHO_SPEED;
	float reveal = step(0.0, since) * range_fade * exp(-since * 0.45) * 0.6;
	return vec2(front * range_fade, reveal) * (1.0 - age / life);
}

vec2 sonar_sample(vec2 p) {
	return sonar_eval(sonar_ping0, p) + sonar_eval(sonar_ping1, p)
		+ sonar_eval(sonar_ping2, p) + sonar_eval(sonar_ping3, p) + echo_eval(p);
}

// The colour sonar light takes at world point p: the sub's own pings in
// sonar_color, the echo in its own colour, blended where both are.
vec3 sonar_hue(vec2 p) {
	vec2 e = echo_eval(p);
	if (e.x + e.y <= 0.0001) {
		return sonar_color.rgb;
	}
	vec2 s = sonar_eval(sonar_ping0, p) + sonar_eval(sonar_ping1, p)
		+ sonar_eval(sonar_ping2, p) + sonar_eval(sonar_ping3, p);
	float we = e.x * 2.0 + e.y * 0.4;
	float ws = s.x * 2.0 + s.y * 0.4;
	return mix(sonar_color.rgb, echo_color.rgb, we / max(we + ws, 1e-4));
}
