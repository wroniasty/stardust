class_name Explosion
extends Node2D
## A one-shot burst of debris, and the crater it leaves if it happens low
## enough to touch the ground.
##
## Frees itself once the last particle has gone. Nothing else tracks it, so a
## death that spawns one costs no bookkeeping anywhere.

## Radius of the hole a death leaves in the crust, in pixels. Zero disables it.
@export var crater_radius: float = 22.0

## How far above the ground a wreck still gouges the surface.
@export var crater_reach: float = 18.0

@onready var _debris: GPUParticles2D = $Debris


func _ready() -> void:
	_debris.emitting = true
	# Outliving the particles would leave an invisible node in the scene for
	# every death, which in a game about dying often adds up.
	get_tree().create_timer(_debris.lifetime * 2.0).timeout.connect(queue_free)


## Throws the debris along the direction the wreck was travelling, so a ship
## that dies at speed does not explode into a tidy symmetrical puff.
func set_drift(velocity: Vector2) -> void:
	if velocity.is_zero_approx():
		return
	var process: ParticleProcessMaterial = _debris.process_material as ParticleProcessMaterial
	if process == null:
		return
	process.direction = Vector3(velocity.x, velocity.y, 0.0).normalized()
	process.spread = 180.0


## Gouges the ground if the wreck came down on or near it.
func scar_terrain() -> void:
	if crater_radius <= 0.0:
		return
	var planet: Planet = Planet.nearest(get_tree(), global_position)
	if planet == null:
		return
	var altitude: float = (
		global_position.distance_to(planet.global_position)
		- planet.surface_radius_at(global_position)
	)
	if altitude <= crater_reach:
		planet.carve(global_position, crater_radius)
