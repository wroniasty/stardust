shader_type canvas_item;
render_mode blend_add;
// The glow around a star, added rather than laid over.
//
// The first corona was four translucent circles drawn over the starfield in
// the ordinary way. Alpha-blending a bright colour onto black gives a dim
// version of that colour, so a white star came out wearing a grey smudge --
// it read as smoke, not as light. Light adds; `blend_add` is the whole fix,
// and it is also why the stars behind still shine through the halo instead
// of being wiped out by it.

uniform vec3 glow_color : source_color = vec3(1.0, 0.80, 0.50);

/// Where the star's own disc ends, as a fraction of this quad's radius.
/// Inside it the surface is drawn over the top, so what happens there only
/// has to avoid leaving a dark seam at the limb.
uniform float disc : hint_range(0.0, 0.95) = 0.45;

uniform float strength : hint_range(0.0, 2.0) = 0.55;

/// How quickly the glow gives up with distance. Three is roughly what a
/// hazy atmosphere does to a bright light, and more importantly it keeps
/// the halo close enough to the star to read as belonging to it.
uniform float falloff : hint_range(1.0, 6.0) = 3.0;

/// Faint angular structure, so the halo is not a perfect ring. Few and
/// weak: a star with obvious spikes looks like a lens, not like a star.
uniform float rays = 7.0;
uniform float ray_depth : hint_range(0.0, 0.5) = 0.13;

void fragment() {
	vec2 centered = (UV - vec2(0.5)) * 2.0;
	float radius = length(centered);
	if (radius > 1.0) {
		discard;
	}

	float beyond = clamp((radius - disc) / max(1.0 - disc, 0.001), 0.0, 1.0);
	float ray = 1.0 - ray_depth + ray_depth * sin(atan(centered.y, centered.x) * rays + TIME * 0.04);
	// Full strength inside the disc, so the surface quad's antialiased rim
	// has something bright behind it rather than a step down to nothing.
	float glow = mix(1.0, pow(1.0 - beyond, falloff) * ray, step(disc, radius));
	COLOR = vec4(glow_color * glow * strength, 1.0);
}
