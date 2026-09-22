class_name Projectile
extends Area2D
## Base class for anything a weapon throws.
##
## One type exists for now (a plain projectile). M2 turns the numbers into a
## Resource so the loot generator can roll them; the flight and impact logic
## stays here (see IDEAS.md section 4).
##
## Terrain is not a physics body, so the engine cannot report a hit against it.
## The projectile samples the crust along the segment it is about to travel,
## which also solves tunnelling: at 600 px/s a tick covers 10 px while a terrain
## texel is 1.5 px, so a single end-of-tick test would shoot straight through
## thin rock.
##
## Area2D rather than Node2D because ships and stations *are* physics bodies and
## M1.7 needs projectiles to hit the hull. Monitoring stays off until then.

## Distance between terrain samples along the flight path, in pixels. Must stay
## below the terrain texel size or thin walls can be missed.
const SAMPLE_STEP: float = 1.0

## Emitted wherever the projectile stops. `point` is in world space.
signal impacted(point: Vector2, damage: float)

## Seconds before an unspent round removes itself.
@export var lifetime: float = 4.0

## Damage dealt to whatever it hits. Used from M1.7.
@export var damage: float = 12.0

## Radius of the hole punched in the crust on impact.
@export var crater_radius: float = 14.0

## Travel in world space, set by the hardpoint that fired it.
var velocity: Vector2 = Vector2.ZERO

var _planet: Planet = null
var _age: float = 0.0


func _ready() -> void:
	# Resolved once: a projectile lives for a few seconds and never outlives
	# the planet it was fired near. M3 will have to re-check as systems stream.
	_planet = Planet.nearest(get_tree(), global_position)


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()
		return

	var start: Vector2 = global_position
	var step: Vector2 = velocity * delta

	var hit: Vector2 = _first_solid_along(start, step)
	if hit.is_finite():
		_impact(hit)
		return

	global_position = start + step
	rotation = velocity.angle() + PI * 0.5


## Walks the segment and returns the first point inside rock, or a non-finite
## vector when the path is clear.
func _first_solid_along(start: Vector2, step: Vector2) -> Vector2:
	if _planet == null:
		return Vector2.INF

	var samples: int = maxi(1, ceili(step.length() / SAMPLE_STEP))
	for i: int in range(1, samples + 1):
		var point: Vector2 = start + step * (float(i) / float(samples))
		if _planet.is_solid_at(point):
			return point
	return Vector2.INF


func _impact(point: Vector2) -> void:
	global_position = point
	if _planet != null:
		_planet.carve(point, crater_radius)
	impacted.emit(point, damage)
	queue_free()
