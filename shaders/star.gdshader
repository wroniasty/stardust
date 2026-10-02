shader_type canvas_item;
render_mode unshaded;
// Nothing lights a star. It is the thing doing the lighting.
// The face of a star: granulation, limb darkening, and an edge.
//
// It replaces a flat filled circle, which was honest about the physics and
// useless to look at. The star is two to five thousand pixels of radius and
// the screen is 640 across, so the pilot never sees the disc -- only a piece
// of its surface filling the view. A flat fill therefore reads as the render
// having broken, and there is nothing in it to tell you whether you are
// moving. Texture at the scale of a screen is the whole job here; the shape
// of the disc barely matters, because you can only ever see a sliver of it.

uniform vec3 core_color : source_color = vec3(1.0, 0.89, 0.60);

/// How many convection cells across the disc. Set from the radius so a cell
/// is the same size in world pixels whatever the star, which is what keeps a
/// small star from looking like a close-up of a big one.
uniform float cells = 32.0;

/// How fast the surface boils, in cells per second. Slow: a star that
/// visibly churns looks like a liquid, and this one is meant to look like
/// something far too big to be moving.
uniform float churn = 0.015;

/// How much darker the limb is than the middle. Real, and the one cue that
/// says "this is a sphere" when all you can see is a wall of light.
uniform float limb : hint_range(0.0, 1.0) = 0.28;

/// Contrast between the hot cells and the lanes between them.
uniform float grain : hint_range(0.0, 1.0) = 0.30;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 within = fract(p);
	// Smoothstep weights: linear interpolation leaves the cell grid visible
	// as a diamond pattern, which on a star looks like a net over it.
	vec2 blend = within * within * (3.0 - 2.0 * within);
	float a = hash(cell);
	float b = hash(cell + vec2(1.0, 0.0));
	float c = hash(cell + vec2(0.0, 1.0));
	float d = hash(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, blend.x), mix(c, d, blend.x), blend.y);
}

float fbm(vec2 p) {
	float sum = 0.0;
	float weight = 0.5;
	for (int i = 0; i < 4; i++) {
		sum += weight * value_noise(p);
		p *= 2.03;
		weight *= 0.5;
	}
	return sum;
}

void fragment() {
	vec2 centered = (UV - vec2(0.5)) * 2.0;
	float radius = length(centered);
	if (radius > 1.0) {
		discard;
	}

	// Drifting in two directions at different rates, so the pattern never
	// repeats and nothing reads as a texture sliding past.
	vec2 flow = vec2(TIME * churn, TIME * churn * 0.62);
	float granulation = fbm(centered * cells + flow);
	float hot = mix(1.0 - grain, 1.0 + grain, granulation);

	// Limb darkening is a line-of-sight effect: straight down you see deep
	// into the hot interior, at the edge you only graze the cool outside.
	// `depth` is how far through the sphere the sight line goes.
	float depth = sqrt(max(1.0 - radius * radius, 0.0));
	float bright = mix(1.0 - limb, 1.0, depth) * hot;

	// A star's face is not the colour of the star. Even a red dwarf is
	// white where you are looking straight into it, and the tint only
	// shows at the edges and in the corona -- so the hue is pulled most
	// of the way to white before the brightness is applied. Painted at
	// its nominal colour it read as a brick wall, not as something hot.
	vec3 face = mix(core_color, vec3(1.0), 0.45);
	vec3 color = mix(face * bright, vec3(1.0), clamp((bright - 1.0) * 0.9, 0.0, 0.6));
	COLOR = vec4(color, 1.0 - smoothstep(1.0 - fwidth(radius) * 1.5, 1.0, radius));
}
