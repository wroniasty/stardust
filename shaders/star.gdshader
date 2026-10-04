shader_type canvas_item;
render_mode unshaded;
// Nothing lights a star. It is the thing doing the lighting.
// The face of a star: granulation that boils, limb darkening, and an edge.
//
// It replaces a flat filled circle, which was honest about the physics and
// useless to look at. The star is two to five thousand pixels of radius and
// the screen is 640 across, so the pilot never sees the disc -- only a piece
// of its surface filling the view. A flat fill therefore reads as the render
// having broken, and there is nothing in it to tell you whether you are
// moving. Texture at the scale of a screen is the whole job here; the shape
// of the disc barely matters, because you can only ever see a sliver of it.
//
// The first version drifted a single noise field past the window, slowly,
// on the argument that something that big should not look like it is
// moving. That was the wrong argument twice over. A translating texture
// does not read as "too big to move", it reads as a texture being pulled
// past -- the one thing that gives a flat image away -- and a star is not
// still: it is the most violent thing in the system. What makes this boil
// instead of slide is that the field is sampled through a warp that is
// itself moving, so a granule swells, splits and dies where it stands.

uniform vec3 core_color : source_color = vec3(1.0, 0.89, 0.60);

/// The colour down in the lanes between the granules, where the plasma
/// is a thousand degrees cooler.
///
/// Handed in rather than derived here, and that is the fix for a real
/// mistake: the first version took `core_color` and multiplied it by a
/// red-biased vector, which works for a yellow star and turns a blue
/// giant brown. Multiplying a blue by a red gives mud. `Star.COLOURS`
/// is ordered coolest first and already knows what one class cooler
/// looks like, so the answer comes from there.
uniform vec3 lane_color : source_color = vec3(0.92, 0.34, 0.07);

/// How many convection cells across the disc. Set from the radius so a cell
/// is the same size in world pixels whatever the star, which is what keeps a
/// small star from looking like a close-up of a big one.
uniform float cells = 32.0;

/// Bulk drift, in cells per second. Almost nothing: this is the star
/// turning, not the surface churning, and the two want wildly different
/// speeds.
uniform float churn = 0.015;

/// How fast the warp field evolves. This is the boil, and it is the one
/// number to turn if the surface looks dead or looks like soup.
uniform float boil = 0.30;

/// How far the warp pushes the granulation, in cells. Past about two the
/// cells stop being cells and the surface turns to marble.
uniform float warp_reach : hint_range(0.0, 3.0) = 1.0;

/// How much darker the limb is than the middle. Real, and the one cue that
/// says "this is a sphere" when all you can see is a wall of light.
uniform float limb : hint_range(0.0, 1.0) = 0.28;

/// Half-width of the band of noise that gets stretched across the whole
/// temperature range. Smaller is more contrast. Value noise clusters hard
/// around its middle, so without this stretch the entire surface sits in
/// one narrow band and reads as stone rather than as plasma.
uniform float grain : hint_range(0.02, 0.5) = 0.30;

/// How hard the bright spots burn through. Granulation says the surface is
/// moving; this says it is burning.
uniform float flare : hint_range(0.0, 1.0) = 0.70;

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

	vec2 p = centered * cells;
	float t = TIME * boil;

	// The warp. Two fields rather than one, fed different offsets and
	// pulled in different directions, so the distortion has no grain of
	// its own for the granulation to line up with.
	vec2 warp = vec2(
		fbm(p * 0.45 + vec2(0.0, t * 0.7)),
		fbm(p * 0.45 + vec2(5.2, 1.3) - vec2(t * 0.6, 0.0))
	) - vec2(0.5);

	// And the granulation through it, with a slow bulk drift on top for
	// the star's own turning.
	vec2 drift = vec2(TIME * churn, TIME * churn * 0.62);
	// Two scales, because one is a cloud and two is a surface. The
	// coarse layer is the convection cell the world-pixel size was
	// chosen for; the fine one, nearly three times the frequency and
	// drifting the other way, is what keeps a cell from being a smooth
	// blob when the pilot is close enough to fill the screen with it.
	float coarse = fbm(p + warp * warp_reach + drift + vec2(0.0, t * 0.12));
	float fine = fbm(p * 2.7 + warp * warp_reach * 0.5 - drift * 1.6 + vec2(t * 0.19, 0.0));
	float granulation = coarse * 0.66 + fine * 0.34;

	// Stretched, and then biased hot. A star's face is mostly bright
	// with a **network of thin cooler lanes** through it, not an even
	// split: without the bias this came out as continents of orange on
	// cream, which reads as lava rather than as plasma.
	float heat = pow(smoothstep(0.5 - grain, 0.5 + grain, granulation), 0.72);

	// The bright spots, on a coarser field and their own clock. Squared
	// so only the peaks show: a star that glowed evenly brighter all over
	// would just be a brighter star.
	float burn = clamp(
		(fbm(p * 0.30 - vec2(t * 0.22, t * 0.09)) - 0.42) / 0.58, 0.0, 1.0
	);
	heat += burn * burn * flare;

	// Limb darkening is a line-of-sight effect: straight down you see deep
	// into the hot interior, at the edge you only graze the cool outside.
	// `depth` is how far through the sphere the sight line goes.
	float depth = sqrt(max(1.0 - radius * radius, 0.0));
	heat *= mix(1.0 - limb, 1.0, depth);

	// Temperature, not brightness, and that is the whole difference
	// between this and the cream-coloured marble it replaced. The lanes
	// between granules are a thousand degrees cooler than the cells, and
	// on a star that is a difference in **colour**: deep orange down in
	// the lanes, the star's own hue in the middle of the range, white
	// where you are looking straight into the furnace. Taking one cream
	// and multiplying it by a number only ever gives beige in the
	// shadows, which is what stone looks like.
	vec3 blaze = vec3(1.0);
	vec3 color = heat < 0.5
		? mix(lane_color, core_color, heat * 2.0)
		: mix(core_color, blaze, clamp((heat - 0.5) * 2.0, 0.0, 1.0));
	// And the very top blows out past white, which is the one cue that
	// says the thing is brighter than the screen can be.
	color = mix(color, blaze, clamp(heat - 1.0, 0.0, 1.0));
	COLOR = vec4(color, 1.0 - smoothstep(1.0 - fwidth(radius) * 1.5, 1.0, radius));
}
