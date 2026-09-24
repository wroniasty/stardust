class_name CloudField
extends MultiMeshInstance2D
## One layer of a planet's weather: individual clouds placed around the planet
## in its polar frame, drawn in a single batch.
##
## Clouds are objects with edges, not a pattern filling a ring. The ring shader
## this replaces could not work from inside the atmosphere whatever its
## parameters, because the camera flies through the middle of the ring: every
## cloud was a slice of one continuous field bent along the horizon.
##
## A planet stacks a few of these at different altitudes, each turning at its
## own rate, which is where the sense of depth comes from (IDEAS.md section 5).

## Clouds per layer. A planet with more circumference than this can fill gets
## bigger clouds rather than more of them: a few hundred quads is nothing to
## draw, but the buffers are rebuilt on every generate().
const MAX_CLOUDS: int = 220

## Radians per second this layer turns, on top of the planet's own spin.
var spin: float = 0.0


## Places `count` clouds in a band between `base_radius` and `base_radius +
## thickness`, each `size` pixels, with opacity from `alpha_range`.
##
## Deterministic: the same field_seed always lays out the same sky.
func build(
	field_seed: int,
	count: int,
	base_radius: float,
	thickness: float,
	size: Vector2,
	alpha_range: Vector2,
) -> void:
	count = clampi(count, 0, MAX_CLOUDS)

	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2.ONE

	var batch: MultiMesh = MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_2D
	# Both flags have to be set before the instance count, or the buffers are
	# already allocated without room for them.
	batch.use_custom_data = true
	batch.mesh = quad
	batch.instance_count = count

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = field_seed

	for i: int in range(count):
		# Evenly spaced and then jittered, rather than uniformly random: pure
		# randomness clumps, and a clumped deck leaves half the planet bare.
		var angle: float = TAU * (float(i) + rng.randf_range(-0.4, 0.4)) / float(count)
		var radius: float = base_radius + rng.randf() * thickness
		var scale: Vector2 = size * rng.randf_range(0.7, 1.3)
		# The flat base has to face the ground. A QuadMesh puts UV v = 0 along
		# its local +y, and canvas +y points down, so the quad has to be turned
		# so that its local +y points AWAY from the planet -- measured, not
		# reasoned: the first guess drew every cloud upside down.
		batch.set_instance_transform_2d(i, Transform2D(
			angle - PI * 0.5,
			scale,
			0.0,
			Vector2.from_angle(angle) * radius,
		))
		batch.set_instance_custom_data(i, Color(
			rng.randf(),
			rng.randf_range(alpha_range.x, alpha_range.y),
			rng.randf_range(0.80, 1.0),
			# The shader measures its lobes in units of the cloud's height, so
			# it has to be told how much wider than tall this quad is.
			scale.x / maxf(scale.y, 1.0),
		))

	multimesh = batch


func _process(delta: float) -> void:
	if not is_zero_approx(spin):
		rotation = wrapf(rotation + spin * delta, -PI, PI)


## Clouds currently in this layer.
func cloud_count() -> int:
	if multimesh == null:
		return 0
	return multimesh.instance_count
