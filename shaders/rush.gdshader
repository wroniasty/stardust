shader_type canvas_item;
/// Rush through air: directional blur, and streaks at the edges.
///
/// The counterpart to `transit.gdshader` and deliberately unlike it. A
/// jump is an event that takes the screen away; this is a condition the
/// pilot flies in, so it has to be readable **through**. Everything
/// here is weighted by how far out from the middle a pixel is: the ship
/// and the instruments around it stay sharp and the world tears past
/// them, which is the only arrangement that is both legible and fast.
///
/// At zero strength this must be exactly the screen it was handed, or
/// an atmosphere would be a permanent filter.

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;

/// How hard it is going, 0..1. Air density times speed, decided in the
/// script; this shader has no opinion about what counts as fast.
uniform float strength : hint_range(0.0, 1.0) = 0.0;

/// Which way the view is travelling, as a unit vector in screen space.
/// The smear runs against it, because the world moves backwards past a
/// ship going forwards.
uniform vec2 drift = vec2(0.0, -1.0);

/// How far the smear reaches at the edge of the frame, as a fraction of
/// the screen. Small: this is a condition, not an event.
uniform float smear : hint_range(0.0, 0.3) = 0.16;

/// How hard the streaks come in on top.
uniform float streak_gain : hint_range(0.0, 2.0) = 1.0;

const int SAMPLES = 12;


/// One value per lane across the direction of travel, constant along
/// it. Constant along the travel is what makes a streak a streak.
float lane(float across) {
	return fract(sin(across * 311.7) * 43758.5453);
}


/// A different number for every pixel, used to jitter where each
/// sample of the smear is taken.
///
/// This is the difference between a blur and a row of ghosts. Twelve
/// samples spread over a hundred pixels put a copy every eight, and a
/// star is one bright pixel on black -- so every copy is a separate
/// star and the field reads as double. Offsetting each pixel's samples
/// by a fraction of the step turns that banding into noise, which at
/// this strength is invisible.
float dither(vec2 at) {
	return fract(sin(dot(at, vec2(12.9898, 78.233))) * 43758.5453);
}


void fragment() {
	vec3 flat_colour = texture(screen, SCREEN_UV).rgb;
	if (strength <= 0.001) {
		COLOR = vec4(flat_colour, 1.0);
	} else {
		vec2 from_middle = SCREEN_UV - vec2(0.5);
		// Nothing at the centre, everything at the edge. The ship sits
		// in the middle of the frame and has to stay sharp: a pilot
		// cannot fly through a blur of their own hull.
		float out_from = clamp(length(from_middle) * 2.0, 0.0, 1.0);
		float weight = out_from * out_from;

		vec3 sum = vec3(0.0);
		float total = 0.0;
		float jitter = dither(SCREEN_UV * 1024.0) / float(SAMPLES - 1);
		for (int i = 0; i < SAMPLES; i++) {
			float along = float(i) / float(SAMPLES - 1) + jitter;
			float w = 1.0 - along * 0.6;
			sum += texture(
				screen, SCREEN_UV - drift * smear * strength * weight * along
			).rgb * w;
			total += w;
		}
		vec3 smeared = sum / total;

		// Streaks parallel to the travel: the lane is sampled across
		// it, so the value holds all the way along a line of motion.
		float across = dot(from_middle, vec2(-drift.y, drift.x));
		float streak = lane(floor(across * 700.0)) * weight;
		smeared += vec3(streak * streak_gain * strength * 0.12);

		COLOR = vec4(mix(flat_colour, smeared, weight * strength), 1.0);
	}
}
