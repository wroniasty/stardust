class_name Starfield
extends CanvasLayer
## Drives the starfield shader from the active camera.
##
## Sits on a negative layer that does not follow the viewport, so the quad stays
## put and only the shader's world offset moves. Nothing here scales with the
## size of the universe.

@onready var _sky: ColorRect = $Sky

var _material: ShaderMaterial = null


func _ready() -> void:
	_material = _sky.material as ShaderMaterial


func _process(_delta: float) -> void:
	if _material == null:
		return
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera == null:
		return
	# Screen pixels moved, not world units: zoom must scale the parallax or the
	# stars drift at the wrong rate when the camera pulls back.
	var parallax_offset: Vector2 = camera.get_screen_center_position() * camera.zoom
	_material.set_shader_parameter("world_offset", parallax_offset)

	# The rotation actually on screen, not the one being asked for: while the
	# camera eases towards a new angle the sky has to ease with it, or the
	# stars would arrive before the world does.
	_material.set_shader_parameter("view_rotation", camera.get_screen_rotation())
