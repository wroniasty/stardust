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
uniform vec3 space_color : source_color = vec3(0.016, 0.02, 0.043);
uniform vec3 far_color : source_color = vec3(0.55, 0.60, 0.85);
uniform vec3 mid_color : source_color = vec3(0.80, 0.85, 1.0);
uniform vec3 near_color : source_color = vec3(1.0, 0.97, 0.90);

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

void fragment() {
	vec2 pixel = FRAGCOORD.xy;

	float far = star_layer(pixel + world_offset * 0.10, 17.0, 0.55, 0.055);
	float mid = star_layer(pixel + world_offset * 0.30, 41.0, 0.45, 0.045);
	float near = star_layer(pixel + world_offset * 0.65, 96.0, 0.40, 0.030);

	vec3 color = space_color;
	color += far_color * far * 0.30;
	color += mid_color * mid * 0.60;
	color += near_color * near;

	COLOR = vec4(color, 1.0);
}
