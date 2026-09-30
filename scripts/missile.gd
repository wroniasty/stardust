class_name Missile
extends Projectile
## A round that flies under power, and optionally turns to follow something.
##
## Subclassed rather than flagged, because a missile genuinely moves
## differently: it accelerates instead of coasting, so it leaves the rail
## slowly, builds speed, and can be outrun early. Firing one is a commitment
## rather than a click. Everything else -- damage, craters, piercing, blast --
## is the round's own behaviour and inherited unchanged.

## Acceleration along its own nose, px/s^2.
var thrust: float = 0.0

## How fast it can swing that nose towards a target, radians per second.
## Zero is a dumb missile: lit, aimed once, and then honest about it.
var turn_rate: float = 0.0

## What it is chasing. Resolved once at launch rather than every tick, so a
## missile commits to a target the way a real one does and cannot be made to
## swap by something wandering closer.
var target: Node2D = null


func _physics_process(delta: float) -> void:
	if turn_rate > 0.0 and is_instance_valid(target):
		var wanted: Vector2 = (target.global_position - global_position).normalized()
		var heading: Vector2 = velocity.normalized()
		if not heading.is_zero_approx():
			# Turned by the smaller of the angle needed and what it can
			# manage this tick, so guidance is a rate rather than a snap.
			var turn: float = clampf(
				heading.angle_to(wanted), -turn_rate * delta, turn_rate * delta
			)
			velocity = velocity.rotated(turn)

	if thrust > 0.0:
		velocity += velocity.normalized() * thrust * delta

	super._physics_process(delta)


## The ship the pilot is pointing at, or nothing.
##
## Nearest to the **cursor**, not to the launcher. "You shoot where you are
## looking" is the whole thesis of mouse aiming, and a seeker that picks the
## closest ship instead is a weapon that argues with the cursor: point past
## the wreck at the one behind it and the missile goes for the wreck.
##
## Nothing near the cursor means no lock, and a missile with nothing to
## chase flies straight. That is not a special case to be papered over with
## a fallback -- flying straight at the point you indicated is exactly what
## pointing at empty space asked for.
static func find_target(at: Vector2, shooter: Node, tree: SceneTree, reach: float) -> Node2D:
	var best: Node2D = null
	var nearest: float = INF
	for node: Node in tree.get_nodes_in_group(Ship.SHIP_GROUP):
		var ship: Ship = node as Ship
		# Not the one that fired, and not a wreck: a missile spent on
		# something already dead is a missile wasted, and whatever killed it
		# is still right there.
		if ship == null or ship == shooter or ship.is_destroyed():
			continue
		var distance: float = ship.global_position.distance_to(at)
		if distance > reach + ship.hull_extent() or distance >= nearest:
			continue
		nearest = distance
		best = ship
	return best
