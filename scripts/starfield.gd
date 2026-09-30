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

var _material: ShaderMaterial = null


func _ready() -> void:
	_material = _sky.material as ShaderMaterial


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
