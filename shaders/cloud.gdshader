shader_type canvas_item;
// ONE cloud, drawn into its own quad. A CloudField draws a few hundred of them
// in a single batch, each with its own seed in INSTANCE_CUSTOM.
//
// This replaces an earlier shader that filled a whole ring around the planet
// with noise. That could never work up close, whatever its parameters: the
// camera flies *inside* the ring, so every cloud was a slice of one continuous
// field bent along the horizon, and the sky read as a doughnut the planet was
// wearing. Clouds have to be objects with edges, placed in the world.
//
// The field orients each quad so that UV y = 0 is the top of the cloud, away
// from the planet, and y = 1 is below its flat base.

uniform vec3 cloud_color : source_color = vec3(1.0, 0.97, 0.95);

/// Colour of the base. Tops catch the light and bottoms do not, and that
/// difference is most of what makes a puff read as having volume.
uniform vec3 shade_color : source_color = vec3(0.55, 0.55, 0.66);
uniform float shading : hint_range(0.0, 1.0) = 0.4;

/// Width of the fade at the cloud's edge, in units of the cloud's height.
/// Small is a crisp cumulus, large is a veil with no silhouette at all.
uniform float softness : hint_range(0.02, 0.8) = 0.15;

/// How hard the noise bites into the outline. Zero is a row of smooth bubbles.
uniform float detail : hint_range(0.0, 1.0) = 0.5;

/// How tall the lobes pile up.
uniform float pile : hint_range(0.2, 1.2) = 0.7;

/// How level the underside is. Cumulus bases are famously flat, because they
/// all condense at the same altitude; a cirrus wisp has no base at all.
uniform float flat_base : hint_range(0.0, 1.0) = 0.7;

/// Where that base sits in the quad.
uniform float base_line : hint_range(0.3, 1.0) = 0.86;

varying vec4 cloud_data;

float hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453123);
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 local = fract(p);
	vec2 smoothed = local * local * (3.0 - 2.0 * local);
	float a = hash2(cell);
	float b = hash2(cell + vec2(1.0, 0.0));
	float c = hash2(cell + vec2(0.0, 1.0));
	float d = hash2(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, smoothed.x), mix(c, d, smoothed.x), smoothed.y);
}

float fbm(vec2 p) {
	float total = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 3; i++) {
		total += value_noise(p) * amplitude;
		p *= 2.07;
		amplitude *= 0.5;
	}
	return total / 0.875;
}

/// Distance from a point to a horizontal segment, in the same units.
float segment_distance(vec2 p, vec2 a, vec2 b) {
	vec2 along = b - a;
	float t = clamp(dot(p - a, along) / dot(along, along), 0.0, 1.0);
	return distance(p, a + along * t);
}

void vertex() {
	cloud_data = INSTANCE_CUSTOM;
}

void fragment() {
	// x: this cloud's seed, y: its opacity, z: its own share of `pile`,
	// w: the quad's width over its height.
	float seed = cloud_data.x * 97.0;
	float alpha_scale = cloud_data.y;
	float heap = cloud_data.z;
	float aspect = max(cloud_data.w, 0.2);

	// Everything below is measured in units of the cloud's HEIGHT, not in UV.
	// That correction is the whole difference between clouds and lozenges: a
	// quad is two to twenty times wider than it is tall, so a circle drawn in
	// raw UV comes out flattened by exactly that factor.
	vec2 point = vec2(UV.x * aspect, UV.y);

	// Lobes are chained along the length, as many as the length has room for,
	// so one shader draws a squat cumulus and a cirrus streak twenty times its
	// own height long without either being stretched.
	int count = clamp(int(aspect * 1.7) + 1, 1, 14);
	float spacing = aspect / float(count);

	// One continuous body first, with rounded ends. Without it a long cloud is
	// a row of separate circles -- a caterpillar, not a cloud -- because every
	// lobe has to reach the base on its own.
	float body = 0.30 * pile * heap;
	float field = 1.0 - segment_distance(
		point,
		vec2(aspect * 0.14, base_line - body),
		vec2(aspect * 0.86, base_line - body)
	) / max(body, 0.01);

	for (int i = 0; i < 14; i++) {
		if (i >= count) {
			break;
		}
		float fi = float(i);
		// Kept inside the body's span, or the end lobes hang off it as
		// detached bubbles.
		float along = 0.12 + 0.76 * (fi + 0.5) / float(count);
		// The end lobes are smaller, which gives the cloud ends instead of a
		// silhouette that stops wherever its quad does.
		float taper = mix(0.45, 1.0, pow(sin(along * PI), 0.45));
		float lobe = spacing * 0.78 * taper * mix(0.65, 1.55, hash(seed + fi * 3.13));
		vec2 centre = vec2(
			(along + (hash(seed + fi * 7.71) - 0.5) * 0.35 / float(count)) * aspect,
			base_line - lobe * mix(0.30, 1.30, hash(seed + fi * 11.37)) * pile * heap
		);
		field = max(field, 1.0 - distance(point, centre) / max(lobe, 0.01));
	}

	// Cut the underside off level with the condensation line, sharply for a
	// cumulus and hardly at all for a wisp.
	float base_soft = mix(0.30, 0.02, flat_base);
	field -= smoothstep(base_line - base_soft, base_line + base_soft * 0.5 + 0.02, UV.y) * flat_base * 1.5;
	// Chew the outline up so it is not a row of circles.
	field += (fbm(point * 3.4 + vec2(seed, seed * 0.7)) - 0.5) * detail * 0.55;

	float alpha = smoothstep(0.0, softness, field);
	if (alpha <= 0.002) {
		discard;
	}
	// Thin the body unevenly, so a cloud is not a solid cutout.
	alpha *= 0.84 + 0.16 * fbm(point * 5.0 + vec2(0.0, seed));

	vec3 lit = mix(shade_color, cloud_color, smoothstep(base_line, base_line * 0.25, UV.y));
	COLOR = vec4(mix(cloud_color, lit, shading), alpha * alpha_scale);
}
