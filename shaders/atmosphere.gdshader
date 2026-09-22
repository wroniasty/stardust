shader_type canvas_item;
// Atmosphere drawn on a quad that covers the whole planet plus its air.
//
// The quad's UV is all the geometry there is: radius 1.0 at the top of the
// atmosphere, `surface_ratio` at the ground. Over the disc this paints the
// haze and the clouds; above the limb it paints the halo that fades into
// space.
//
// Clouds are sampled on the circle rather than on an unwrapped angle, so the
// pattern rotates around the planet without a seam.

uniform float surface_ratio = 0.85;
uniform vec3 atmosphere_color : source_color = vec3(0.45, 0.62, 0.95);
uniform float density : hint_range(0.0, 1.0) = 1.0;
uniform float cloud_scale = 3.5;
uniform float cloud_speed = 0.03;
uniform float haze_strength = 0.28;
uniform float rim_strength = 0.85;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 local = fract(p);
	vec2 smoothed = local * local * (3.0 - 2.0 * local);
	float a = hash(cell);
	float b = hash(cell + vec2(1.0, 0.0));
	float c = hash(cell + vec2(0.0, 1.0));
	float d = hash(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, smoothed.x), mix(c, d, smoothed.x), smoothed.y);
}

float fbm(vec2 p) {
	float total = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 4; i++) {
		total += value_noise(p) * amplitude;
		p *= 2.03;
		amplitude *= 0.5;
	}
	return total;
}

void fragment() {
	vec2 centered = UV - vec2(0.5);
	float radius = length(centered) * 2.0;
	if (radius > 1.0) {
		discard;
	}

	// 0 at the ground, 1 at the top of the atmosphere. Negative over the disc.
	float altitude = (radius - surface_ratio) / max(1.0 - surface_ratio, 0.001);
	float air = 1.0 - clamp(altitude, 0.0, 1.0);

	// Rotate the sample direction instead of scrolling an angle: no seam.
	float spin = TIME * cloud_speed;
	vec2 direction = centered / max(length(centered), 0.0001);
	vec2 turned = vec2(
		direction.x * cos(spin) - direction.y * sin(spin),
		direction.x * sin(spin) + direction.y * cos(spin)
	);
	float clouds = fbm(turned * cloud_scale + vec2(radius * 2.0, 0.0));
	clouds = smoothstep(0.45, 0.85, clouds);

	float over_disc = step(radius, surface_ratio);

	// Haze and clouds sit on the planet, the halo hangs above the limb.
	float alpha = over_disc * (haze_strength + clouds * 0.45);
	alpha += (1.0 - over_disc) * air * air * haze_strength * 1.6;

	// Rim light: a bright band just above the ground, fading outwards.
	float rim = smoothstep(0.0, 0.08, altitude) * (1.0 - smoothstep(0.08, 0.7, altitude));
	alpha += rim * rim_strength;

	vec3 color = mix(atmosphere_color, vec3(1.0), clouds * over_disc * 0.5 + rim * 0.35);
	COLOR = vec4(color, clamp(alpha, 0.0, 1.0) * density);
}
