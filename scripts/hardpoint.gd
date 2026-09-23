class_name Hardpoint
extends Node2D
## A weapon mount on a ship: where a gun sits, which way it points, and how
## fast it can shoot.
##
## Same idea as ShipEngine: the node's own transform is the mount. Rotate the
## node in the editor and the gun points elsewhere, with no code to change.
##
## The hardpoint owns the rate of fire but not the trigger. The ship decides
## when to pull it, so an AI or an autopilot uses exactly the same path as the
## player (M5).
##
## M2 replaces the exported numbers with a weapon Resource the loot generator
## rolls, and adds the allowed-type list from IDEAS.md section 4.

## Direction the gun points in its own frame, matching the ship's nose.
const MUZZLE_DIRECTION: Vector2 = Vector2.UP

@export var projectile_scene: PackedScene

@export var rounds_per_second: float = 4.0

## Muzzle velocity, added to whatever the ship is already doing.
@export var muzzle_speed: float = 600.0

## Total cone of inaccuracy, in degrees.
@export var spread_degrees: float = 2.0

## If true the round carries the ship's velocity, so shooting while moving
## does not leave rounds hanging behind the ship.
@export var inherit_velocity: bool = true

var _cooldown: float = 0.0


## Advances the cooldown. Driven by the ship so the order is deterministic.
func tick(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)


func can_fire() -> bool:
	return _cooldown <= 0.0 and projectile_scene != null


## Spawns one round into `container`. Returns it, or null if still cooling down.
##
## The round is parented to the world, never to the ship: a projectile must not
## inherit the ship's motion after it leaves the barrel.
func fire(carrier_velocity: Vector2, container: Node, shooter: Node = null) -> Projectile:
	if not can_fire() or container == null:
		return null
	_cooldown = 1.0 / maxf(rounds_per_second, 0.001)

	var round_instance: Projectile = projectile_scene.instantiate() as Projectile
	if round_instance == null:
		return null

	var spread: float = deg_to_rad(spread_degrees)
	var aim: float = global_rotation + randf_range(-spread * 0.5, spread * 0.5)
	var direction: Vector2 = MUZZLE_DIRECTION.rotated(aim)

	round_instance.shooter = shooter
	round_instance.global_position = global_position
	round_instance.velocity = direction * muzzle_speed
	if inherit_velocity:
		round_instance.velocity += carrier_velocity
	round_instance.rotation = round_instance.velocity.angle() + PI * 0.5

	container.add_child(round_instance)
	return round_instance
