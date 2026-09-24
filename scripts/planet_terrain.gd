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
const MAX_ANGULAR_SAMPLES: int = 8192
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
const PENETRATION_STEP: float = 1.0

## Arc width of a landing shelf as a fraction of the full circle, and how much
## of its half-width is spent ramping back into the surrounding relief.
const PLATEAU_MIN_ARC: float = 0.006
const PLATEAU_MAX_ARC: float = 0.018
const PLATEAU_RAMP_FRACTION: float = 0.6

## Bisections run after the march finds the exit. The result drives positional
## correction, and the correction only converges if the depth can be measured
## finer than the slop it is correcting towards: a 1 px march against a 0.5 px
## slop can never tell "0.4 deep" from "1.0 deep", so it lifts the hull every
## tick and the ship rocks forever. Four bisections give 1/16 px.
const PENETRATION_REFINEMENTS: int = 4

var angular_samples: int = 0
var radial_samples: int = 0

## Bottom and top of the stored band, in pixels from the planet centre.
var inner_radius: float = 0.0
var outer_radius: float = 0.0

var texture: ImageTexture = null

## Arc length the haze floor is averaged over, in pixels.
##
## The atmosphere must not pour into narrow holes. A shot digs a shaft barely
## wider than itself, and feeding the exact column height to the shader filled
## each one with full-brightness haze from the crust floor up, so a burst of
## fire left hard-edged bright stripes standing in the sky between the rock
## pillars. Averaging over an arc several craters wide lets the haze follow the
## broad shape of the ground and ignore the punctures.
const HAZE_SMOOTHING_PX: float = 80.0

## One texel per angular column holding the radius the atmosphere should treat
## as ground: the smoothed envelope, but never below the real surface, so a
## mountain peak still pushes the haze up while a shaft does not pull it down.
var height_texture: ImageTexture = null

## Radius of the highest rock in each column. Kept in step with carving.
var _surface_radius: PackedFloat32Array = PackedFloat32Array()
var _haze_floor: PackedFloat32Array = PackedFloat32Array()
var _height_image: Image = null

var _solid: PackedByteArray = PackedByteArray()
var _image: Image = null
var _band: float = 1.0


## Builds the crust for a planet of `surface_radius` from `terrain_seed`.
##
## `plateau_count` flat landing shelves are levelled into the relief afterwards.
## Without them a rough planet can be unlandable everywhere, which is a
## generation bug rather than a difficulty setting (IDEAS.md section 7).
func generate(terrain_seed: int, surface_radius: float, plateau_count: int = 0) -> void:
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
	var heights: PackedFloat32Array = PackedFloat32Array()
	heights.resize(angular_samples)
	for column: int in range(angular_samples):
		# Sampling the noise on the unit circle instead of on a flat angle is
		# what makes the terrain wrap with no seam at angle zero.
		var on_circle: Vector2 = Vector2.from_angle(_angle_of(column))
		var roughness: float = remap(terrain_type.get_noise_2dv(on_circle * 10.0), -1.0, 1.0, 0.05, 1.0)
		var shape: float = relief.get_noise_2dv(on_circle * 10.0)
		heights[column] = surface_radius + shape * roughness * mountain_height

	_level_plateaus(heights, terrain_seed, plateau_count)

	for column: int in range(angular_samples):
		var top_row: int = clampi(_row_of(heights[column]), -1, radial_samples - 1)
		for row: int in range(top_row + 1):
			_solid[row * angular_samples + column] = SOLID

	_rebuild_surface_cache()
	_image = Image.create_from_data(angular_samples, radial_samples, false, Image.FORMAT_R8, _solid)
	texture = ImageTexture.create_from_image(_image)


## Flattens `count` arcs to a constant radius, with a soft ramp at each end so a
## shelf does not sit on the plain behind a cliff.
func _level_plateaus(heights: PackedFloat32Array, terrain_seed: int, count: int) -> void:
	if count <= 0:
		return

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = terrain_seed + 104729

	for i: int in range(count):
		var centre: int = rng.randi_range(0, angular_samples - 1)
		var half_width: int = maxi(
			2, int(float(angular_samples) * rng.randf_range(PLATEAU_MIN_ARC, PLATEAU_MAX_ARC) * 0.5)
		)
		var ramp: int = maxi(1, int(float(half_width) * PLATEAU_RAMP_FRACTION))

		# Level to the height already at the middle, so the shelf stays part of
		# the landscape instead of hovering at some invented altitude.
		var level: float = heights[wrapi(centre, 0, angular_samples)]
		for offset: int in range(-half_width - ramp, half_width + ramp + 1):
			var column: int = wrapi(centre + offset, 0, angular_samples)
			var distance: int = absi(offset)
			var blend: float = 1.0
			if distance > half_width:
				blend = 1.0 - float(distance - half_width) / float(ramp)
			heights[column] = lerpf(heights[column], level, clampf(blend, 0.0, 1.0))


## Surface radius per column, so slope queries under the landing legs are a
## lookup rather than a march down from the ceiling every tick.
func _rebuild_surface_cache() -> void:
	_surface_radius.resize(angular_samples)
	for column: int in range(angular_samples):
		_surface_radius[column] = _scan_surface(column)
	_haze_floor.resize(angular_samples)
	_refresh_haze_floor(0, angular_samples - 1)
	_upload_heights()


## Recomputes the haze floor for a span of columns, wrapping at the seam.
##
## Only a span, because the average at one column depends on the exact heights
## within half a window of it: carving touches a wedge, so only that wedge plus
## a window either side can change, and redoing the whole ring on every shot
## would cost more than the carve itself.
func _refresh_haze_floor(first: int, last: int) -> void:
	var half: int = _haze_window()

	# A morphological closing: dilate, then erode, both over the same window.
	#
	# Plainer filters were each wrong in their own way. A mean is dragged down
	# by the hole it is supposed to ignore, so a shaft kept a third of its
	# bright column. Taking the mean of the upper half fixed that but sat some
	# ten pixels above untouched ground everywhere, which would draw a thin
	# dark rim along the whole horizon. Closing fills anything narrower than the
	# window and leaves everything else exactly where it was, which is the
	# property actually wanted.
	# Written the obvious way, which is O(columns * window) per pass. Over a
	# carve that is nothing, but building a planet closes the whole ring and
	# generation went from 14 ms to 57 ms on the largest worlds because of it.
	# Left as is: M3 already plans to move terrain generation onto a worker
	# thread, and a sliding-window min/max would be a lot of machinery to save
	# something that is about to stop being on the critical path.
	var dilated: PackedFloat32Array = PackedFloat32Array()
	dilated.resize(last - first + 1 + half * 2)
	for i: int in range(dilated.size()):
		var centre: int = first - half + i
		var peak: float = -INF
		for offset: int in range(-half, half + 1):
			peak = maxf(peak, _surface_radius[wrapi(centre + offset, 0, angular_samples)])
		dilated[i] = peak

	for index: int in range(first, last + 1):
		var column: int = wrapi(index, 0, angular_samples)
		var valley: float = INF
		for offset: int in range(-half, half + 1):
			valley = minf(valley, dilated[index - first + half + offset])
		# Closing is extensive, so this can only ever confirm the floor is at or
		# above the real ground; kept as a guard rather than as arithmetic.
		_haze_floor[column] = maxf(valley, _surface_radius[column])


func _haze_window() -> int:
	return maxi(1, int(HAZE_SMOOTHING_PX / TARGET_TEXEL_PX * 0.5))


## Pushes the height column to the GPU. A single row of floats, so a crater
## costs about 17 KB of upload on a big planet.
func _upload_heights() -> void:
	var data: PackedByteArray = _haze_floor.to_byte_array()
	var resized: bool = _height_image == null or _height_image.get_width() != angular_samples
	if resized:
		_height_image = Image.create_from_data(angular_samples, 1, false, Image.FORMAT_RF, data)
		height_texture = ImageTexture.create_from_image(_height_image)
		return
	_height_image.set_data(angular_samples, 1, false, Image.FORMAT_RF, data)
	height_texture.update(_height_image)


## Highest solid radius in a column, or the inner radius when it has been dug
## out entirely.
func _scan_surface(column: int) -> float:
	for row: int in range(radial_samples - 1, -1, -1):
		if _solid[row * angular_samples + column] != EMPTY:
			return _radius_of(row)
	return inner_radius


## Radius the atmosphere treats as ground at an angle. Exposed for tests and
## tools; the shader reads the same numbers from height_texture.
func haze_floor_at(angle: float) -> float:
	if _haze_floor.is_empty():
		return inner_radius
	return _haze_floor[_column_of(angle)]


## Radius of the ground at an angle, in the planet's local frame.
func surface_radius_at(angle: float) -> float:
	if _surface_radius.is_empty():
		return inner_radius
	return _surface_radius[_column_of(angle)]


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
			return _refine_exit(point, normal, travelled - PENETRATION_STEP, travelled)
	return MAX_PENETRATION


## Bisects between a known solid distance and a known empty one.
func _refine_exit(point: Vector2, normal: Vector2, solid: float, empty: float) -> float:
	for i: int in range(PENETRATION_REFINEMENTS):
		var middle: float = (solid + empty) * 0.5
		if is_solid_local(point + normal * middle):
			solid = middle
		else:
			empty = middle
	return empty


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
	# Tracked unwrapped as well. A wedge that straddles the seam comes out of
	# the array with its last column numerically before its first, and a span
	# taken from those two would be empty.
	var span_first: int = 0
	var span_last: int = angular_samples - 1
	if distance <= radius:
		for column: int in range(angular_samples):
			columns.append(column)
	else:
		var half_span: float = asin(clampf(radius / distance, -1.0, 1.0)) * 1.2
		var centre_angle: float = centre.angle()
		var steps: int = maxi(1, ceili(half_span / TAU * float(angular_samples)))
		var middle: int = _column_of(centre_angle)
		span_first = middle - steps
		span_last = middle + steps
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
		for column: int in columns:
			_surface_radius[column] = _scan_surface(column)
		var reach: int = _haze_window()
		_refresh_haze_floor(span_first - reach, span_last + reach)
		_upload_heights()
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
