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

## The flash. Bright and wide, because this is the one event in the game
## that is supposed to light up the whole neighbourhood, and gone in a
## fraction of the time the debris takes -- a flash that faded with the
## sparks would read as a fire rather than a detonation.
const FLASH_REACH: float = 320.0
const FLASH_STRENGTH: float = 2.6
const FLASH_SECONDS: float = 0.45
const FLASH_COLOUR: Color = Color(1.00, 0.78, 0.45)

@onready var _debris: GPUParticles2D = $Debris

var _flash: GlowLight = null
var _flash_left: float = 0.0


func _ready() -> void:
	_debris.emitting = true
	_flash = GlowLight.make(FLASH_COLOUR, FLASH_REACH, FLASH_STRENGTH)
	add_child(_flash)
	_flash_left = FLASH_SECONDS
	# Outliving the particles would leave an invisible node in the scene for
	# every death, which in a game about dying often adds up.
	get_tree().create_timer(_debris.lifetime * 2.0).timeout.connect(queue_free)


func _process(delta: float) -> void:
	if _flash == null:
		return
	_flash_left -= delta
	if _flash_left <= 0.0:
		_flash.queue_free()
		_flash = null
		return
	# Squared, so the drop is steep at the start and long in the tail:
	# the eye reads that as a flash, and a linear fade as a dimmer switch.
	var share: float = _flash_left / FLASH_SECONDS
	_flash.energy = FLASH_STRENGTH * share * share


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
	var altitude: float = planet.height_above_terrain(global_position)
	if altitude <= crater_reach:
		planet.carve(global_position, crater_radius)
