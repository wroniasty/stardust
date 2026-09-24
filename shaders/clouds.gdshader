shader_type canvas_item;
// A cloud deck: a ring of weather sitting high above the surface, rolling
// slowly around the planet.
//
// Entirely independent of the ground. Clouds are up in the sky; what the
// terrain is doing underneath them, including being blown apart, is none of
// their business. Everything about a deck — where it sits, how thick, how much
// sky it covers, its colour and how fast it turns — is rolled from the planet
// seed, so weather is part of what makes a world recognisable.

uniform vec3 cloud_color : source_color = vec3(1.0, 0.97, 0.95);

/// Inner and outer edge of the deck, as fractions of this quad's radius.
uniform float base_ratio = 0.80;
uniform float top_ratio = 0.92;

/// How much of the sky has cloud in it, 0 clear to 1 overcast.
uniform float coverage : hint_range(0.0, 1.0) = 0.45;

/// Width of the transition between clear and cloud. Small is crisp and
/// cumulus-like, large is a smeared overcast.
uniform float edge_softness : hint_range(0.01, 0.5) = 0.18;

/// Peak opacity in the middle of the deck.
uniform float opacity : hint_range(0.0, 1.0) = 0.6;

/// Radians per second the deck turns, signed.
uniform float scroll_speed = 0.02;

/// Feature size: low is a few continents of cloud, high is broken and speckled.
uniform float feature_scale = 3.5;

const float PI_C = 3.14159265358979;

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
	if (radius < base_ratio || radius > top_ratio) {
		discard;
	}

	// 0 at the base, 1 at the top. A sine across it fades both edges, so the
	// deck has no rim to give away that it is a ring.
	float band = (radius - base_ratio) / max(top_ratio - base_ratio, 0.001);
	float profile = sin(band * PI_C);

	// Sampled on the circle rather than on an unwrapped angle, so the deck
	// turns without a seam at angle zero.
	float spin = TIME * scroll_speed;
	vec2 direction = centered / max(length(centered), 0.0001);
	vec2 turned = vec2(
		direction.x * cos(spin) - direction.y * sin(spin),
		direction.x * sin(spin) + direction.y * cos(spin)
	);
	// A little variation across the deck's thickness, kept small: a large
	// radial term stretches the noise into beams pointing out of the planet.
	float shape = fbm(turned * feature_scale + vec2(band * 0.5, 0.0));

	float threshold = 1.0 - coverage;
	float cloud = smoothstep(threshold - edge_softness, threshold + edge_softness, shape);

	COLOR = vec4(cloud_color, cloud * profile * opacity);
}
