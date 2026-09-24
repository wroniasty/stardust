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

/// Surface radius per angular column, in pixels, one texel wide. Without it the
/// haze can only start at the nominal radius, and since the relief is centred
/// on that radius, half the planet gets a band of thin air between the ground
/// and where the atmosphere visibly begins.
uniform sampler2D ground_heights : repeat_enable, filter_linear;

/// Divisor that turns those pixels into this quad's 0..1 radius.
uniform float atmosphere_radius = 1000.0;
uniform vec3 atmosphere_color : source_color = vec3(0.45, 0.62, 0.95);
uniform float density : hint_range(0.0, 1.0) = 1.0;
uniform float cloud_scale = 3.5;
uniform float cloud_speed = 0.03;

/// Opacity over the planet itself. Deliberately the lowest figure here: the
/// terrain has to stay readable to land on.
uniform float disc_haze : hint_range(0.0, 1.0) = 0.30;

/// Opacity of the air just above the ground, falling to nothing at the top.
uniform float shell_haze : hint_range(0.0, 1.0) = 0.80;

/// Shape of that fall. Below 1.0 it is concave, which keeps real opacity
/// through the middle of the climb; the old squared falloff spent the whole
/// atmosphere in the bottom third and left the rest of the ascent empty, and
/// dropped to a tenth over the mountain tops so space showed through them.
uniform float shell_falloff = 0.70;

/// Fraction of the atmosphere height over which the disc opacity gives way to
/// the shell. Wide enough to read as a glow rather than as a ring.
uniform float limb_blend : hint_range(0.01, 0.5) = 0.15;

/// A thin bright band hugging the ground. Kept weak: this was what made the
/// surface look glaring.
uniform float rim_strength : hint_range(0.0, 1.0) = 0.25;

const float TAU_C = 6.283185307179586;

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

	float angle01 = mod(atan(centered.y, centered.x), TAU_C) / TAU_C;
	float ground = texture(ground_heights, vec2(angle01, 0.5)).r / max(atmosphere_radius, 0.001);

	// Two different heights, and the distinction is the whole point.
	//
	// The profile is measured from the nominal radius, so a peak really does
	// poke into thinner air than a valley floor sits in. Where the air STARTS
	// is the actual ground, so there is no dead band under the haze.
	float altitude = (radius - surface_ratio) / max(1.0 - surface_ratio, 0.001);
	float above_ground = (radius - ground) / max(1.0 - ground, 0.001);

	// Rotate the sample direction instead of scrolling an angle: no seam.
	float spin = TIME * cloud_speed;
	vec2 direction = centered / max(length(centered), 0.0001);
	vec2 turned = vec2(
		direction.x * cos(spin) - direction.y * sin(spin),
		direction.x * sin(spin) + direction.y * cos(spin)
	);
	float clouds = fbm(turned * cloud_scale + vec2(radius * 2.0, 0.0));
	clouds = smoothstep(0.45, 0.85, clouds);
	clouds *= 1.0 - smoothstep(0.0, 0.35, clamp(above_ground, 0.0, 1.0));

	// Thin air is still air: a thin atmosphere reads as less opaque, but never
	// as absent, or half the planets would have an invisible one.
	float thickness = mix(0.55, 1.0, density);

	float shell = shell_haze * pow(clamp(1.0 - altitude, 0.0, 1.0), shell_falloff);
	// Over rock the haze drops back, so the terrain stays readable to land on.
	// One texel of softness on the join, or the ground line gets a second edge
	// drawn over the one the terrain already has.
	float edge = 1.5 / max(atmosphere_radius, 0.001);
	float over_rock = 1.0 - smoothstep(ground - edge, ground + edge, radius);
	float alpha = mix(shell, disc_haze, over_rock) * thickness;

	// A narrow band hugging the ground itself, for the glow along the limb.
	float rim = smoothstep(0.0, 0.02, above_ground) * (1.0 - smoothstep(0.02, 0.18, above_ground));
	alpha += rim * rim_strength * thickness;
	alpha += clouds * 0.35 * thickness;

	vec3 color = mix(atmosphere_color, vec3(1.0), clouds * 0.45 + rim * 0.20);
	COLOR = vec4(color, clamp(alpha, 0.0, 1.0));
}
