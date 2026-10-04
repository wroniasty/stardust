shader_type canvas_item;
/// Crossing between systems: streaks, radial blur, a shift in colour.
///
/// The one effect in the game that exists to hide something. The old
/// system is freed and the new one built halfway through the crossing,
/// and this is what is over the screen while that happens -- so its job
/// is not to be pretty, it is to be opaque enough at the middle that a
/// system vanishing and another appearing reads as one event.
///
/// Everything is driven by `strength`. At zero this must be exactly the
/// screen it was handed, or a jump drive would be a permanent filter.

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;

/// How far through the effect we are, 0..1. The only input.
uniform float strength : hint_range(0.0, 1.0) = 0.0;

/// How far the smear reaches at full strength, as a fraction of the
/// screen. Enough to pull a planet into a line and not so far that the
/// middle of the frame turns to mush.
uniform float smear : hint_range(0.0, 0.8) = 0.42;

/// Where the colour goes. Cool, because the crossing should not read as
/// damage -- the game already uses warm and red for things going wrong.
uniform vec3 shift : source_color = vec3(0.62, 0.80, 1.35);

/// How hard the radial streaks come in on top of the smear.
uniform float streak_gain : hint_range(0.0, 3.0) = 1.15;

const int SAMPLES = 12;
const float TAU_C = 6.28318530718;


/// One value per angle, held still along the radius. That is what makes
/// a streak a streak rather than noise: the same number all the way out
/// from the centre.
float lane(float angle) {
	return fract(sin(angle * 311.7) * 43758.5453);
}


void fragment() {
	vec3 flat_colour = texture(screen, SCREEN_UV).rgb;
	if (strength <= 0.001) {
		COLOR = vec4(flat_colour, 1.0);
	} else {
		vec2 centre = vec2(0.5);
		vec2 away = SCREEN_UV - centre;

		// Smeared inwards, not outwards: sampling towards the middle
		// drags the middle of the frame over the edges, which is the
		// direction a ship going somewhere pulls the view.
		vec3 sum = vec3(0.0);
		float weight = 0.0;
		for (int i = 0; i < SAMPLES; i++) {
			float along = float(i) / float(SAMPLES - 1);
			float w = 1.0 - along * 0.65;
			sum += texture(screen, SCREEN_UV - away * smear * strength * along).rgb * w;
			weight += w;
		}
		vec3 smeared = sum / weight;

		// Streaks, strongest out at the edge where the smear is longest
		// and absent at the middle, where there is nothing to streak.
		float angle = atan(away.y, away.x) / TAU_C + 0.5;
		float out_from = clamp(length(away) * 2.0, 0.0, 1.0);
		// Nine hundred lanes, not a hundred and eighty. At 180 the
		// wedges came out twenty pixels wide at the edge of a 1280 px
		// frame and the screen read as a test pattern rather than as
		// speed. Streaks are thin or they are stripes.
		float streak = lane(floor(angle * 900.0)) * out_from * out_from;
		smeared += vec3(streak * streak_gain * strength * 0.35) * shift;

		vec3 moved = mix(smeared, smeared * shift, strength);
		COLOR = vec4(mix(flat_colour, moved, strength), 1.0);
	}
}
