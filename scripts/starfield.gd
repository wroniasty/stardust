class_name Starfield
extends CanvasLayer
## Drives the starfield shader from the active camera.
##
## Sits on a negative layer that does not follow the viewport, so the quad stays
## put and only the shader's world offset moves. Nothing here scales with the
## size of the universe.

@onready var _sky: ColorRect = $Sky

## Framebuffer pixels the field slides per pixel the camera travels.
##
## A feel number, not a derivation: the shader offsets a screen-space
## pattern, so there is no "correct" rate to compute, only one that reads
## as distance.
const PARALLAX_SCALE: float = 1.0

## Who is looking, so the stars can be told when it is daytime. Handed
## in rather than fetched, like everything else in this layer.
@export var ship_path: NodePath

## How wide the galactic band can be, and how much of the sky the
## clouds take. Rolled per system, so two systems are two skies.
const BAND_WIDTH: Vector2 = Vector2(0.10, 0.34)
const NEBULA_AMOUNT: Vector2 = Vector2(0.35, 1.0)

## How fast the daylight reading follows the ship. Slow: crossing a
## terminator at speed should fade the stars in, not switch them.
const DAY_RESPONSE: float = 0.5

var _ship: Ship = null
var _daylight: float = 0.0
var _material: ShaderMaterial = null


func _ready() -> void:
	_material = _sky.material as ShaderMaterial
	_ship = get_node_or_null(ship_path) as Ship


func _process(_delta: float) -> void:
	if _material == null:
		return
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera == null:
		return
	# Straight off the camera's position, with **no zoom in it**.
	#
	# It used to be `position * zoom`, on the argument that the parallax
	# should slow down as the camera pulls back. The argument is fine and
	# the expression is not: zoom is animated by speed, so every change of
	# throttle multiplied the whole offset by a different number and the
	# field lurched by Delta-zoom times the distance from the origin. Once
	# the world moved onto its orbit, nineteen thousand pixels out, a zoom
	# of 1.0 easing to 0.7 threw the sky five thousand pixels sideways --
	# and because the three layers take 0.10, 0.30 and 0.65 of it, they
	# sheared past each other and the whole field looked like it was
	# turning.
	#
	# The shader offsets a screen-space pattern and has no scale term, so
	# it cannot express "see more sky when zoomed out" anyway. What it can
	# express is a field fixed in the world that the camera looks around,
	# and that is worth more than the rate: fly a loop and the stars are
	# where you left them.
	_material.set_shader_parameter(
		"world_offset", camera.get_screen_center_position() * PARALLAX_SCALE
	)

	# The rotation actually on screen, not the one being asked for: while the
	# camera eases towards a new angle the sky has to ease with it, or the
	# stars would arrive before the world does.
	_material.set_shader_parameter("view_rotation", camera.get_screen_rotation())

	# Eased, because crossing a terminator at speed should fade the
	# stars in rather than switch them.
	_daylight = lerpf(
		_daylight,
		wanted_daylight() if Presentation.is_on() else 0.0,
		clampf(get_process_delta_time() / DAY_RESPONSE, 0.0, 1.0),
	)
	_material.set_shader_parameter("daylight", _daylight)


## Dresses the sky for one system: where the galactic band lies, what
## colour the clouds are, how much of either there is.
##
## From the seed and nothing else, so a system is the same sky every
## time you come back to it -- the same rule the planets live under.
## Called by the world when a system opens, and again after a jump.
func dress(system_seed: int) -> void:
	if _material == null:
		return
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = system_seed
	_material.set_shader_parameter("sky_seed", Vector2(
		rng.randf_range(-4000.0, 4000.0), rng.randf_range(-4000.0, 4000.0)
	))
	_material.set_shader_parameter("band_angle", rng.randf_range(0.0, TAU))
	_material.set_shader_parameter(
		"band_width", rng.randf_range(BAND_WIDTH.x, BAND_WIDTH.y)
	)
	_material.set_shader_parameter(
		"nebula_amount", rng.randf_range(NEBULA_AMOUNT.x, NEBULA_AMOUNT.y)
	)
	# Cool and dim. A background that competes with the foreground is a
	# background in the wrong place, and at 640x360 there is very
	# little foreground to lose.
	_material.set_shader_parameter("band_color", Color(
		rng.randf_range(0.55, 0.80),
		rng.randf_range(0.58, 0.82),
		rng.randf_range(0.80, 1.00),
	))
	_material.set_shader_parameter("nebula_color", Color(
		rng.randf_range(0.30, 0.70),
		rng.randf_range(0.20, 0.50),
		rng.randf_range(0.50, 0.90),
	))


## How washed out the sky should be, 0..1, before smoothing.
##
## Air times how lit the place is. Both are needed and neither is
## enough: the day side of an airless moon has a sky full of stars, and
## so does the night side of a thick atmosphere. Ungated and public,
## for the usual reason.
func wanted_daylight() -> float:
	if _ship == null or not is_instance_valid(_ship):
		return 0.0
	var lit: float = GravityWell.daylight_at(get_tree(), _ship.global_position)
	return clampf(_ship.air_density, 0.0, 1.0) * clampf(lit, 0.0, 1.0)


func daylight() -> float:
	return _daylight
