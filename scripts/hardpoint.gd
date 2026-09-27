class_name Hardpoint
extends Node2D
## A weapon mount on a ship: where a gun sits, which way it points, and how
## fast it can shoot.
##
## Same idea as ShipEngine: the node's own transform is the mount. Rotate the
## node in the editor and the gun points elsewhere, with no code to change.
##
## The hardpoint owns the trigger timing but not the trigger. The ship decides
## when to pull it, so an AI or an autopilot uses exactly the same path as the
## player (M5).
##
## The numbers live in the fitted WeaponData, not here: a mount is a place, and
## what stands in it is loot (M2).

## Direction the gun points in its own frame, matching the ship's nose.
const MUZZLE_DIRECTION: Vector2 = Vector2.UP

## What is bolted on. Empty mounts are normal -- a hull can carry more
## hardpoints than the pilot has guns for.
@export var weapon: WeaponData = null

## Weapon types this mount will take. Empty means anything, which is what a
## general purpose mount is; a missile rack lists what it can hold.
@export var accepts: Array[WeaponData.Type] = []

var _cooldown: float = 0.0


## Advances the cooldown. Driven by the ship so the order is deterministic.
func tick(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)


func can_fire() -> bool:
	return _cooldown <= 0.0 and weapon != null and weapon.projectile_scene != null


## Whether this mount will take `candidate`. A mount that lists nothing takes
## anything; the check is here rather than in the loot generator so that a
## weapon found in the world can be offered against the ship that has to hold
## it (IDEAS.md section 4).
func can_fit(candidate: WeaponData) -> bool:
	if candidate == null:
		return false
	return accepts.is_empty() or accepts.has(candidate.type)


## Fits `candidate` if this mount will take it. Returns what was there before,
## so a swap in flight can hand the old gun back to the pilot.
func fit(candidate: WeaponData) -> WeaponData:
	if not can_fit(candidate):
		return candidate
	var previous: WeaponData = weapon
	weapon = candidate
	_cooldown = 0.0
	return previous


## Spawns one round into `container`. Returns it, or null if still cooling down.
##
## The round is parented to the world, never to the ship: a projectile must not
## inherit the ship's motion after it leaves the barrel.
func fire(carrier_velocity: Vector2, container: Node, shooter: Node = null) -> Projectile:
	if not can_fire() or container == null:
		return null
	_cooldown = 1.0 / maxf(weapon.rounds_per_second, 0.001)

	var round_instance: Projectile = weapon.projectile_scene.instantiate() as Projectile
	if round_instance == null:
		return null

	var spread: float = deg_to_rad(weapon.spread_degrees)
	var aim: float = global_rotation + randf_range(-spread * 0.5, spread * 0.5)
	var direction: Vector2 = MUZZLE_DIRECTION.rotated(aim)

	# The round carries the weapon's numbers rather than its own defaults: a
	# projectile scene is a chassis, and what it hits for is loot.
	round_instance.damage = weapon.damage
	round_instance.crater_radius = weapon.crater_radius
	round_instance.lifetime = weapon.lifetime()

	round_instance.shooter = shooter
	round_instance.global_position = global_position
	round_instance.velocity = direction * weapon.muzzle_speed
	if weapon.inherit_velocity:
		round_instance.velocity += carrier_velocity
	round_instance.rotation = round_instance.velocity.angle() + PI * 0.5

	container.add_child(round_instance)
	return round_instance
