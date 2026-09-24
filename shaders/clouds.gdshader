shader_type canvas_item;
// A cloud deck: weather sitting high above the surface, turning slowly around
// the planet.
//
// Entirely independent of the ground. Clouds are up in the sky; what the
// terrain is doing underneath them, including being blown apart, is none of
// their business. Everything about a deck is rolled from the planet seed, so
// weather is part of what makes a world recognisable.
//
// The parameters are deliberately shaped so that one shader covers several
// kinds of sky rather than one look with a colour knob: see the archetypes in
// planet.gd and IDEAS.md section 5.

uniform vec3 cloud_color : source_color = vec3(1.0, 0.97, 0.95);

/// Colour of the underside. Cloud tops catch the light, bottoms do not, and
/// that difference is most of what makes a puff read as having volume.
uniform vec3 shade_color : source_color = vec3(0.55, 0.55, 0.66);

/// Inner and outer edge of the deck, as fractions of this quad's radius.
uniform float base_ratio = 0.80;
uniform float top_ratio = 0.92;

/// How much of the sky has cloud in it, 0 clear to 1 overcast.
uniform float coverage : hint_range(0.0, 1.0) = 0.45;

/// Width of the transition between clear and cloud. Small is crisp and
/// cumulus-like, large is a smeared overcast.
uniform float edge_softness : hint_range(0.01, 0.5) = 0.12;

/// Peak opacity of a fully formed cloud.
uniform float opacity : hint_range(0.0, 1.0) = 0.6;

/// Radians per second the deck turns, signed.
uniform float scroll_speed = 0.02;

/// Width of one cloud, measured in deck thicknesses. 1.0 is as wide as the deck
/// is tall.
///
/// It is deliberately relative. An absolute frequency cannot work: the deck is
/// a hundred-odd pixels thick and several thousand long, so any fixed number of
/// cells around the circumference smears every cloud into a streak on one
/// planet and dices it on the next.
uniform float puff_size : hint_range(0.3, 8.0) = 1.2;

/// How much flatter than round a cloud is. 1.0 is square, above that gives
/// layered sheets and bands, below it gives towers.
uniform float flatten : hint_range(0.2, 6.0) = 1.0;

/// Domain warp. Zero is round and blobby, high is drawn out and wispy.
uniform float warp_strength : hint_range(0.0, 1.0) = 0.3;

/// How much the top of the deck varies from angle to angle. Zero is a flat
/// stratus lid, high gives towering heaps with gaps of clear sky between them.
uniform float height_variation : hint_range(0.0, 0.9) = 0.5;

/// Difference in rotation speed between the bottom and the top of the deck.
/// Large values shear the noise into latitude bands, the gas giant look.
uniform float shear : hint_range(-2.0, 2.0) = 0.0;

/// Strength of the top-lit shading between shade_color and cloud_color.
uniform float shading : hint_range(0.0, 1.0) = 0.35;

/// Octaves of detail. Few is soft and rolling, many is broken and fluffy.
uniform int octaves : hint_range(1, 6) = 4;

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

float fbm(vec2 p, int steps) {
	float total = 0.0;
	float amplitude = 0.5;
	float normalisation = 0.0;
	for (int i = 0; i < 6; i++) {
		if (i >= steps) {
			break;
		}
		total += value_noise(p) * amplitude;
		normalisation += amplitude;
		p *= 2.03;
		amplitude *= 0.5;
	}
	return total / max(normalisation, 0.001);
}

vec2 turn(vec2 v, float angle) {
	float c = cos(angle);
	float s = sin(angle);
	return vec2(v.x * c - v.y * s, v.x * s + v.y * c);
}

void fragment() {
	vec2 centered = UV - vec2(0.5);
	float radius = length(centered) * 2.0;
	if (radius < base_ratio || radius > top_ratio) {
		discard;
	}

	// 0 at the base of the deck, 1 at the top.
	float band = (radius - base_ratio) / max(top_ratio - base_ratio, 0.001);
	vec2 direction = centered / max(length(centered), 0.0001);

	// Sampled on the circle rather than on an unwrapped angle, so the deck
	// turns without a seam at angle zero. Shear makes the upper deck run ahead
	// of the lower one.
	float spin = TIME * scroll_speed * (1.0 + shear * (band - 0.5));
	vec2 turned = turn(direction, spin);

	// Noise cells are kept square by construction, which is the whole trick.
	// Sampling on a circle of radius `scale` puts `scale` cells in a radian, so
	// an arc as long as the deck is thick covers scale * thickness / mid cells;
	// widening that circle with altitude by exactly the same amount makes one
	// cell as tall as it is wide, whatever the planet's proportions.
	float thickness = max(top_ratio - base_ratio, 0.001);
	float mid = 0.5 * (base_ratio + top_ratio);
	float scale = mid / (thickness * max(puff_size, 0.05));
	float spread = (thickness / mid) * flatten;
	vec2 point = turned * scale * (1.0 + spread * (band - 0.5));

	// Warping the sample point before reading the shape is what turns smooth
	// noise into something with wisps and torn edges.
	// Warped well below the cloud frequency: a warp as fine as the shape itself
	// frays every edge into hair instead of bending the cloud.
	vec2 warp = vec2(
		fbm(point * 0.35 + vec2(3.7, 9.1), 2),
		fbm(point * 0.35 + vec2(11.3, 5.9), 2)
	) - vec2(0.5);
	// Value noise clusters hard around its own mean, so without stretching the
	// contrast the coverage knob spends most of its range doing nothing.
	float shape = clamp((fbm(point + warp * warp_strength * 1.6, octaves) - 0.5) * 1.8 + 0.5, 0.0, 1.0);

	// The deck does not have a constant thickness: a separate low frequency
	// field lifts its top, so heaps and gaps replace a uniform lid.
	float lump = fbm(turned * scale * 0.3 + vec2(19.0, 27.0), 3);
	float local_top = mix(1.0 - height_variation, 1.0, lump);
	float height = band / max(local_top, 0.05);
	if (height > 1.0) {
		discard;
	}
	// Folding the vertical profile into the field before the threshold, rather
	// than fading the result afterwards, is what rounds the tops and bottoms
	// off. Fading afterwards only makes the same ring more transparent.
	float profile = sin(clamp(height, 0.0, 1.0) * PI_C);
	float field = shape * mix(0.45, 1.0, profile);

	// Mapped across the range the field actually occupies, so 0.2 is a few
	// scattered clouds and 0.8 is a solid lid.
	float threshold = mix(0.78, 0.22, coverage);
	float cloud = smoothstep(threshold - edge_softness, threshold + edge_softness, field);
	if (cloud <= 0.0) {
		discard;
	}

	vec3 lit = mix(shade_color, cloud_color, smoothstep(0.0, 0.8, height));
	COLOR = vec4(mix(cloud_color, lit, shading), cloud * opacity);
}
