shader_type canvas_item;
// Parallax starfield drawn on one full-screen quad.
//
// The quad never moves. All motion comes from `world_offset`, which the script
// feeds from the camera, so there are no star nodes to stream and the field is
// infinite. Stars are hashed out of a grid, which makes them reproducible from
// position alone: fly away and back and the same stars are there.
//
// Layers are ordered far to near. Far layers move least, which is what sells
// the depth.

uniform vec2 world_offset = vec2(0.0);

// The rotation the view is currently showing. Without it the field is
// painted in screen space and simply does not turn: rotate the camera and
// the whole universe pivots around a sky nailed to the monitor.
//
// The point it turns about is taken from SCREEN_PIXEL_SIZE rather than
// passed in. FRAGCOORD is in framebuffer pixels while the game's
// `canvas_items` stretch reports a 640x360 visible rect, so a centre handed
// over from the script was half the real one and the sky pivoted about a
// point a quarter of the way in -- which changed the stars without looking
// remotely like a rotation.
uniform float view_rotation = 0.0;
uniform vec3 space_color : source_color = vec3(0.016, 0.02, 0.043);
uniform vec3 far_color : source_color = vec3(0.55, 0.60, 0.85);
uniform vec3 mid_color : source_color = vec3(0.80, 0.85, 1.0);
uniform vec3 near_color : source_color = vec3(1.0, 0.97, 0.90);

// How much of the sky is washed out by being in lit air, 0..1.
//
// The stars are **dimmed, not painted over**. Tinting the whole quad
// towards a sky colour would turn the frame blue in every direction,
// including the half of it pointing away from the planet, and would
// fight the atmosphere shader that is already drawing the real sky
// over the disc. What a pilot actually loses in daylight is the
// stars, so that is what is taken away.
uniform float daylight : hint_range(0.0, 1.0) = 0.0;

// The galactic band and the clouds hanging off it, rolled from the
// system's seed by the script. Nothing here is hand-placed; a system
// is the same sky every time you come back to it.
uniform float nebula_amount : hint_range(0.0, 1.0) = 0.0;
uniform float band_angle = 0.0;
uniform float band_width : hint_range(0.05, 1.0) = 0.25;
uniform vec3 band_color : source_color = vec3(0.70, 0.74, 0.95);
uniform vec3 nebula_color : source_color = vec3(0.55, 0.35, 0.75);
uniform vec2 sky_seed = vec2(0.0);

float hash1(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

vec2 hash2(vec2 p) {
	return vec2(hash1(p), hash1(p + vec2(17.3, 5.1)));
}

// One grid of stars. `cell` is the spacing in pixels, `fill` how many cells
// hold a star at all, `radius` the star size as a fraction of a cell.
float star_layer(vec2 pos, float cell, float fill, float radius) {
	vec2 grid = pos / cell;
	vec2 base = floor(grid);
	vec2 local = fract(grid);

	float light = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 neighbour = vec2(float(x), float(y));
			vec2 id = base + neighbour;
			if (hash1(id) > fill) {
				continue;
			}
			vec2 star = neighbour + hash2(id + vec2(3.7, 9.2));
			float dist = length(local - star);
			float magnitude = 0.35 + 0.65 * hash1(id + vec2(23.1, 41.7));
			light += smoothstep(radius, 0.0, dist) * magnitude;
		}
	}
	return clamp(light, 0.0, 1.0);
}

// Smoothed value noise, which is as much as a background needs: the
// band is a shape and the clouds are texture on it, and neither is
// being looked at closely enough to want anything better.
float value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 within = fract(p);
	within = within * within * (3.0 - 2.0 * within);
	float a = hash1(cell);
	float b = hash1(cell + vec2(1.0, 0.0));
	float c = hash1(cell + vec2(0.0, 1.0));
	float d = hash1(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, within.x), mix(c, d, within.x), within.y);
}


float fbm(vec2 p) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		sum += value_noise(p) * amp;
		// Not exactly two, or the octaves line up on the grid and the
		// clouds come out as a plaid.
		p *= 2.03;
		amp *= 0.5;
	}
	return sum;
}


vec2 turn(vec2 v, float angle) {
	float c = cos(angle);
	float s = sin(angle);
	return vec2(v.x * c - v.y * s, v.x * s + v.y * c);
}

void fragment() {
	// A screen offset of d from the centre looks along world direction
	// d turned by the camera's rotation, so the field is sampled there. Only
	// the pixel part turns: world_offset is already in the world's frame.
	vec2 screen_center = 0.5 / SCREEN_PIXEL_SIZE;
	vec2 pixel = turn(FRAGCOORD.xy - screen_center, view_rotation) + screen_center;

	float far = star_layer(pixel + world_offset * 0.10, 17.0, 0.55, 0.055);
	float mid = star_layer(pixel + world_offset * 0.30, 41.0, 0.45, 0.045);
	float near = star_layer(pixel + world_offset * 0.65, 96.0, 0.40, 0.030);

	// The band sits furthest away of anything here -- further than the
	// far stars -- which is the whole reason it reads as the galaxy
	// rather than as a cloud a few thousand pixels off the bow.
	vec2 sky = (pixel + world_offset * 0.04 + sky_seed) * 0.0016;
	float across = dot(sky, vec2(-sin(band_angle), cos(band_angle)));
	float band = exp(-across * across / max(band_width * band_width, 0.0001));
	float texture_ = fbm(sky * 3.1);
	float clouds = smoothstep(0.52, 0.95, fbm(sky * 1.7 + vec2(11.3, 4.7)));

	vec3 color = space_color;
	color += band_color * band * (0.30 + 0.70 * texture_) * nebula_amount * 0.45;
	color += nebula_color * clouds * nebula_amount * 0.40;
	color += far_color * far * 0.30;
	color += mid_color * mid * 0.60;
	color += near_color * near;

	// Washed out by daylight, down to the empty-space colour rather
	// than to black: what is left when the stars go is the sky the
	// atmosphere shader is drawing over the top, not a hole.
	COLOR = vec4(mix(color, space_color, daylight), 1.0);
}
