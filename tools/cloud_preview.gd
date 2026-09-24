extends Node2D
## Renders one planet per cloud archetype to PNG, so the sky can be judged by
## looking at it instead of by reading parameters.
##
## Clouds and atmosphere are the one part of this project where the tests can
## only guard properties (above the rock, inside the air, non-zero thickness)
## and never the thing that actually matters. Four rounds of atmosphere
## feedback went by before anyone measured the artefact; this makes looking
## cheap.
##
##     godot --path . tools/cloud_preview.tscn -- <output directory>
##
## Two shots per archetype: the whole disc, and a low pass under the deck.

const PLANET_SCENE: PackedScene = preload("res://scenes/planet.tscn")

## How far to search for a seed of each archetype before giving up on it.
const SEED_LIMIT: int = 400

var _output_dir: String = "user://cloud_preview"

@onready var _camera: Camera2D = $Camera


func _ready() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.size() > 0:
		_output_dir = arguments[0]
	DirAccess.make_dir_recursive_absolute(_output_dir)
	_run()


func _run() -> void:
	var planet: Planet = PLANET_SCENE.instantiate() as Planet
	add_child(planet)

	for type_name: String in Planet.CloudType.keys():
		var wanted: int = Planet.CloudType[type_name]
		var found: int = _find_seed(planet, wanted)
		if found < 0:
			print("no seed found for %s in %d tries" % [type_name, SEED_LIMIT])
			continue
		planet.generate(found)
		print("%s: seed %d, R %.0f, deck %.0f..%.0f, %d clouds, coverage %.2f, puff %.1f x %.1f, shear %.2f" % [
			type_name, found, planet.surface_radius,
			planet.cloud_base_radius(), planet.cloud_ceiling(), planet.cloud_count(),
			planet.cloud_coverage, planet.cloud_puff_size, planet.cloud_puff_height,
			planet.cloud_shear,
		])
		await _shoot(type_name, "disc", Vector2.ZERO, planet.atmosphere_radius() * 1.15)
		# A low pass: the camera sits under the deck, looking along it, which is
		# where the player actually meets the weather.
		var low: Vector2 = Vector2.UP * (planet.surface_radius + planet.atmosphere_height * 0.25)
		await _shoot(type_name, "pass", low, planet.atmosphere_height * 0.7)

	print("wrote previews to %s" % _output_dir)
	get_tree().quit()


## First seed that rolls `wanted`, or -1.
func _find_seed(planet: Planet, wanted: int) -> int:
	for candidate: int in range(SEED_LIMIT):
		planet.generate(candidate)
		if planet.has_clouds and planet.cloud_type == wanted:
			return candidate
	return -1


func _shoot(type_name: String, shot: String, at: Vector2, half_height: float) -> void:
	_camera.position = at
	# Zoom is a scale factor, so fitting a given world height means dividing the
	# viewport height by it.
	var viewport_height: float = float(get_viewport().get_visible_rect().size.y)
	_camera.zoom = Vector2.ONE * (viewport_height * 0.5 / maxf(half_height, 1.0))

	# Two frames: one for the camera to take effect, one to draw with it.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

	var image: Image = get_viewport().get_texture().get_image()
	var path: String = "%s/%s_%s.png" % [_output_dir, type_name.to_lower(), shot]
	image.save_png(path)
