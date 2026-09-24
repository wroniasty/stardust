shader_type canvas_item;
// Atmosphere as one plain layer, drawn UNDERNEATH the terrain and reaching all
// the way to the planet's centre.
//
// It knows nothing about the surface, and that is the point. Every version that
// did — haze starting at the real per-column ground, then a smoothed envelope,
// then a morphological closing of it — produced a different artefact from the
// same mistake: haze pouring down freshly dug shafts, radial gaps punched
// through the cloud deck above craters, hard steps where the smoothing window
// met a cliff. Putting the layer behind the rock and letting it run deep means
// digging simply uncovers what was always there, and there is no per-column
// anything left to disagree with the terrain.

uniform vec3 atmosphere_color : source_color = vec3(0.45, 0.62, 0.95);
uniform float density : hint_range(0.0, 1.0) = 1.0;

/// Nominal surface radius over this quad's radius. The profile hangs off it;
/// nothing else in the shader cares where the ground actually is.
uniform float surface_ratio = 0.73;

/// Opacity of the air just above the ground, falling to nothing at the top.
uniform float shell_haze : hint_range(0.0, 1.0) = 0.80;

/// Shape of that fall. Below 1.0 it is concave, which keeps real opacity
/// through the middle of a climb instead of spending the whole atmosphere in
/// its bottom third.
uniform float shell_falloff = 0.70;

/// A thin brighter band hugging the nominal surface.
uniform float rim_strength : hint_range(0.0, 1.0) = 0.25;

/// Depth below the surface, as a fraction of this quad's radius, over which the
/// layer goes fully opaque. A hole dug past it reads as a hole in the planet
/// rather than as a window onto the starfield.
uniform float opaque_depth : hint_range(0.001, 0.5) = 0.06;

void fragment() {
	vec2 centered = UV - vec2(0.5);
	float radius = length(centered) * 2.0;
	if (radius > 1.0) {
		discard;
	}

	// Thin air is still air: a thin atmosphere reads as less opaque, but never
	// as absent, or a fifth of the planets would look airless when they are not.
	float thickness = mix(0.55, 1.0, density);
	float alpha;

	if (radius >= surface_ratio) {
		float altitude = (radius - surface_ratio) / max(1.0 - surface_ratio, 0.001);
		alpha = shell_haze * pow(1.0 - altitude, shell_falloff);
		float rim = smoothstep(0.0, 0.02, altitude) * (1.0 - smoothstep(0.02, 0.18, altitude));
		alpha = (alpha + rim * rim_strength) * thickness;
	} else {
		// Below the surface it only gets denser, so however deep the player
		// digs there is always more of it underneath.
		float depth = (surface_ratio - radius) / opaque_depth;
		alpha = mix(shell_haze * thickness, 1.0, clamp(depth, 0.0, 1.0));
	}

	COLOR = vec4(atmosphere_color, clamp(alpha, 0.0, 1.0));
}
