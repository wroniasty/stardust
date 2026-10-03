shader_type canvas_item;
// Planet crust, drawn straight from the polar occupancy bitmap.
//
// The quad covers the planet out to the tallest mountain. Each fragment turns
// its position into (angle, radius) and looks the texel up: the same mapping
// the collision code uses, so what you see is exactly what you hit.
//
// Strata are read from the bitmap too, by asking whether there is rock a little
// further out. That means a fresh crater gets a crust rim for free, with no
// bookkeeping when the terrain changes.

uniform sampler2D terrain : repeat_enable, filter_nearest;

uniform float inner_radius = 400.0;
uniform float outer_radius = 500.0;

uniform vec3 crust_color : source_color = vec3(0.45, 0.55, 0.35);
uniform vec3 rock_color : source_color = vec3(0.32, 0.30, 0.28);
uniform vec3 core_color : source_color = vec3(0.18, 0.16, 0.17);

/// Depth below open sky, in pixels, at which rock stops being crust and where
/// it becomes core.
uniform float crust_depth = 7.0;
uniform float rock_depth = 30.0;

/// How wide the bright edge on a cut face is, in pixels, and how much
/// brighter it goes.
///
/// A crater floor is already darker than the ground, for free: it is
/// deeper, so the depth test above finds rock and then core under it.
/// What was missing is the **wall**, which is at the same depth as the
/// ground beside it and differs only in having nothing next to it.
///
/// So the wall is found by looking sideways rather than outwards -- two
/// samples at the same radius, a few pixels round the circle. That also
/// catches natural cliffs, which is right: a cliff face is exposed rock
/// for the same reason a crater wall is.
uniform float rim_width = 3.0;
uniform float rim_gain : hint_range(1.0, 3.0) = 1.7;

/// Direction of the star, as a unit vector in this quad's own frame, and how
/// much of a difference it makes. The planet turns under it, so the quad is
/// told afresh every frame; `sunlight` is zero for a world with no star in
/// the scene at all, which is M1's single planet and most of the tests, and
/// those stay lit all the way round rather than half-dark for no reason.
uniform vec2 sun_dir = vec2(0.0, -1.0);
uniform float sunlight : hint_range(0.0, 1.0) = 0.0;

/// How dark the night side gets. Not black, and higher than the air above
/// it, which is backwards for a real planet and right for this one: the
/// ground is the thing the pilot has to land on, and a surface that cannot
/// be read is a surface that gets crashed into. The air is free to go dark
/// because nobody lands on it.
uniform float night : hint_range(0.0, 1.0) = 0.50;

/// Half-width of the terminator, as a dot product. The band where it is
/// neither day nor night; wide enough to read as a curve rather than a cut.
///
/// A uniform rather than a constant because the ship and the crates are
/// shaded off the same rule in GDScript, and a number written down in
/// four places is a terminator that moves depending on what you look at.
/// `GravityWell.TERMINATOR` is the one that counts; this default only
/// covers a material nobody has told yet.
uniform float terminator : hint_range(0.05, 0.6) = 0.22;

/// 1.0 in full daylight, `night` on the far side.
float daylight(vec2 from_centre) {
	float facing = dot(normalize(from_centre), sun_dir);
	float lit = smoothstep(-terminator, terminator, facing);
	return mix(1.0, mix(night, 1.0, lit), sunlight);
}

const float TAU_C = 6.283185307179586;

float solid_at(float angle01, float radius) {
	if (radius < inner_radius) {
		return 1.0;
	}
	if (radius >= outer_radius) {
		return 0.0;
	}
	float band = (radius - inner_radius) / (outer_radius - inner_radius);
	return step(0.5, texture(terrain, vec2(angle01, band)).r);
}

void fragment() {
	vec2 local = (UV - vec2(0.5)) * 2.0 * outer_radius;
	float radius = length(local);
	if (radius > outer_radius) {
		discard;
	}

	float angle01 = mod(atan(local.y, local.x), TAU_C) / TAU_C;
	if (solid_at(angle01, radius) < 0.5) {
		discard;
	}

	float under_crust = solid_at(angle01, radius + crust_depth);
	float under_rock = solid_at(angle01, radius + rock_depth);

	vec3 color = core_color;
	color = mix(rock_color, color, under_rock);
	color = mix(crust_color, color, under_crust);

	// Freshly cut faces catch the light. `rim_width` pixels converted to
	// an angle at this radius, so the band is the same width on a moon
	// and on a gas giant rather than the same fraction of a turn.
	float across = rim_width / max(TAU_C * radius, 1.0);
	float exposed = clamp(
		2.0 - solid_at(angle01 - across, radius) - solid_at(angle01 + across, radius),
		0.0, 1.0
	);
	color = min(color * mix(1.0, rim_gain, exposed), vec3(1.0));

	COLOR = vec4(color * daylight(local), 1.0);
}
