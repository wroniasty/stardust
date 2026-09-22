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

	COLOR = vec4(color, 1.0);
}
