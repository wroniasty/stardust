class_name PlanetTerrain
extends RefCounted
## The destructible crust of a planet, stored as a bitmap in the polar frame.
##
## One texel is (angle, radius), not (x, y). The polar frame is the answer to
## the open question in IDEAS.md: it wraps around the planet with no seam and no
## wasted corners, every surface query in the game is already polar (landing
## legs, ground vehicles), and a column of texels is literally "the ground under
## this angle", which is what the landing checks need.
##
## Only the crust is stored: a band from `inner_radius` to `outer_radius` around
## the nominal surface. Everything below the band is solid core and everything
## above it is sky, so neither needs texels.
##
## Occupancy lives in a PackedByteArray for collision queries, which are far too
## frequent for Image.get_pixel(), and is mirrored into an Image for the GPU.

## Roughly how many pixels one texel should cover on screen. Keeping this near
## the render scale means the terrain reads as pixel art rather than as mush.
const TARGET_TEXEL_PX: float = 1.5

const MIN_ANGULAR_SAMPLES: int = 512
const MAX_ANGULAR_SAMPLES: int = 4096
const MIN_RADIAL_SAMPLES: int = 64
const MAX_RADIAL_SAMPLES: int = 512

## How far the tallest mountains and the deepest stored rock sit from the
## nominal surface, as a fraction of the planet radius.
const MOUNTAIN_FRACTION: float = 0.12
const DEPTH_FRACTION: float = 0.10

const SOLID: int = 255
const EMPTY: int = 0

## Ring of probes used to read a surface normal out of the bitmap.
const NORMAL_PROBES: int = 8
const NORMAL_PROBE_DISTANCE: float = 4.0

## How far to march when measuring how deep a point sits inside rock.
const MAX_PENETRATION: float = 24.0
const PENETRATION_STEP: float = 2.0

var angular_samples: int = 0
var radial_samples: int = 0

## Bottom and top of the stored band, in pixels from the planet centre.
var inner_radius: float = 0.0
var outer_radius: float = 0.0

var texture: ImageTexture = null

var _solid: PackedByteArray = PackedByteArray()
var _image: Image = null
var _band: float = 1.0


## Builds the crust for a planet of `surface_radius` from `terrain_seed`.
func generate(terrain_seed: int, surface_radius: float) -> void:
	inner_radius = surface_radius * (1.0 - DEPTH_FRACTION)
	outer_radius = surface_radius * (1.0 + MOUNTAIN_FRACTION)
	_band = outer_radius - inner_radius

	angular_samples = clampi(
		roundi(TAU * surface_radius / TARGET_TEXEL_PX), MIN_ANGULAR_SAMPLES, MAX_ANGULAR_SAMPLES
	)
	radial_samples = clampi(
		roundi(_band / TARGET_TEXEL_PX), MIN_RADIAL_SAMPLES, MAX_RADIAL_SAMPLES
	)

	var relief: FastNoiseLite = FastNoiseLite.new()
	relief.seed = terrain_seed
	relief.noise_type = FastNoiseLite.TYPE_SIMPLEX
	relief.fractal_type = FastNoiseLite.FRACTAL_FBM
	relief.fractal_octaves = 4
	relief.frequency = 0.45

	# A second, much slower noise decides where the planet is mountainous and
	# where it is plains. Without it the whole surface has one roughness and
	# there is nowhere flat to put a ship down.
	var terrain_type: FastNoiseLite = FastNoiseLite.new()
	terrain_type.seed = terrain_seed + 7919
	terrain_type.noise_type = FastNoiseLite.TYPE_SIMPLEX
	terrain_type.frequency = 0.08

	_solid = PackedByteArray()
	_solid.resize(angular_samples * radial_samples)
	_solid.fill(EMPTY)

	var mountain_height: float = surface_radius * MOUNTAIN_FRACTION
	for column: int in range(angular_samples):
		var angle: float = TAU * (float(column) + 0.5) / float(angular_samples)
		# Sampling the noise on the unit circle instead of on a flat angle is
		# what makes the terrain wrap with no seam at angle zero.
		var on_circle: Vector2 = Vector2.from_angle(angle)
		var roughness: float = remap(terrain_type.get_noise_2dv(on_circle * 10.0), -1.0, 1.0, 0.05, 1.0)
		var shape: float = relief.get_noise_2dv(on_circle * 10.0)
		var height: float = surface_radius + shape * roughness * mountain_height

		var top_row: int = clampi(_row_of(height), -1, radial_samples - 1)
		for row: int in range(top_row + 1):
			_solid[row * angular_samples + column] = SOLID

	_image = Image.create_from_data(angular_samples, radial_samples, false, Image.FORMAT_R8, _solid)
	texture = ImageTexture.create_from_image(_image)


## True if the point, in the planet's local frame, is inside rock.
func is_solid_local(point: Vector2) -> bool:
	var radius: float = point.length()
	if radius < inner_radius:
		return true
	if radius >= outer_radius:
		return false
	return _solid[_index(point.angle(), radius)] != EMPTY


## Outward surface normal at a point in the planet's local frame.
##
## Read from the bitmap rather than from a stored height, so a crater wall gives
## the same quality of normal as untouched ground.
func normal_local(point: Vector2) -> Vector2:
	var away: Vector2 = Vector2.ZERO
	for probe: int in range(NORMAL_PROBES):
		var direction: Vector2 = Vector2.from_angle(TAU * float(probe) / float(NORMAL_PROBES))
		if not is_solid_local(point + direction * NORMAL_PROBE_DISTANCE):
			away += direction
	if away.is_zero_approx():
		# Buried with rock on every side: the only sane way out is straight up.
		return point.normalized() if not point.is_zero_approx() else Vector2.UP
	return away.normalized()


## How far a point would have to travel along `normal` to leave the rock.
func penetration_local(point: Vector2, normal: Vector2) -> float:
	var travelled: float = 0.0
	while travelled < MAX_PENETRATION:
		travelled += PENETRATION_STEP
		if not is_solid_local(point + normal * travelled):
			return travelled
	return MAX_PENETRATION


## Clears a disc of rock. Returns true if anything was actually removed, so the
## caller can skip the texture upload when a shot hits empty sky.
func carve_local(centre: Vector2, radius: float) -> bool:
	var distance: float = centre.length()
	if distance - radius >= outer_radius or distance + radius <= inner_radius:
		return false

	var low: int = clampi(_row_of(distance - radius), 0, radial_samples - 1)
	var high: int = clampi(_row_of(distance + radius), 0, radial_samples - 1)

	# Angular span the disc can possibly reach, so we walk a wedge and not the
	# whole ring. A disc covering the centre has no meaningful span.
	var columns: PackedInt32Array = PackedInt32Array()
	if distance <= radius:
		for column: int in range(angular_samples):
			columns.append(column)
	else:
		var half_span: float = asin(clampf(radius / distance, -1.0, 1.0)) * 1.2
		var centre_angle: float = centre.angle()
		var steps: int = maxi(1, ceili(half_span / TAU * float(angular_samples)))
		var middle: int = _column_of(centre_angle)
		for offset: int in range(-steps, steps + 1):
			columns.append(wrapi(middle + offset, 0, angular_samples))

	var radius_squared: float = radius * radius
	var changed: bool = false
	for row: int in range(low, high + 1):
		var sample_radius: float = _radius_of(row)
		for column: int in columns:
			var index: int = row * angular_samples + column
			if _solid[index] == EMPTY:
				continue
			var texel: Vector2 = Vector2.from_angle(_angle_of(column)) * sample_radius
			if texel.distance_squared_to(centre) <= radius_squared:
				_solid[index] = EMPTY
				changed = true

	if changed:
		_upload()
	return changed


## Pushes the occupancy array to the GPU. Kept separate so it can be timed.
func _upload() -> void:
	_image.set_data(angular_samples, radial_samples, false, Image.FORMAT_R8, _solid)
	texture.update(_image)


func _index(angle: float, radius: float) -> int:
	return _row_of(radius) * angular_samples + _column_of(angle)


func _column_of(angle: float) -> int:
	var turn: float = fposmod(angle, TAU) / TAU
	return clampi(int(turn * float(angular_samples)), 0, angular_samples - 1)


func _row_of(radius: float) -> int:
	return clampi(int((radius - inner_radius) / _band * float(radial_samples)), 0, radial_samples - 1)


func _angle_of(column: int) -> float:
	return TAU * (float(column) + 0.5) / float(angular_samples)


func _radius_of(row: int) -> float:
	return inner_radius + (float(row) + 0.5) / float(radial_samples) * _band
