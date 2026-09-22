class_name Ship
extends RigidBody2D
## A ship: a rigid body plus a bag of engines.
##
## Steering is not scripted. The pilot picks which engines burn, every burning
## engine pushes at its own mount point, and the resulting motion (including
## all rotation) comes out of the physics solver. That way a damaged or
## asymmetric engine layout changes how the ship flies for free.
##
## Gravity is applied by the ship itself from nearby bodies (M1.2), never by
## the physics server: gravity_scale stays 0.

## Nose direction in the ship's local frame.
const FORWARD: Vector2 = Vector2.UP

## Points of the hull tested against the terrain bitmap. The engine's own
## collision shape never meets the terrain, because the terrain is not a
## physics body (see IDEAS.md section 6): it is pixels, and these are the
## pixels we ask about. Nose and the two rear corners carry the hull outline,
## the rest stop a long edge from sinking in between corners.
const HULL_POINTS: Array[Vector2] = [
	Vector2(0, -12),
	Vector2(-8, 10),
	Vector2(8, 10),
	Vector2(-4, -1),
	Vector2(4, -1),
	Vector2(0, 10),
]

## Projectiles are parented to the node in this group, so they stay put in the
## world instead of riding along with the ship that fired them.
const PROJECTILE_GROUP: StringName = &"projectile_container"

## Fired on every terrain impact hard enough to hurt. M1.7 turns this into hull
## HP and death; for now it only accumulates.
signal hull_impact(impact_speed: float, damage: float)

## If true the ship steers itself from the player's input actions. AI ships and
## tests turn this off and write the command fields directly.
@export var use_player_input: bool = true

## How much of the impact speed a bounce gives back. Arcade, not elastic.
@export_range(0.0, 1.0) var terrain_bounce: float = 0.25

## How much sideways speed is scrubbed off per contact, 0..1.
@export_range(0.0, 1.0) var terrain_friction: float = 0.4

## Impacts slower than this are free. Above it, damage grows with the excess.
@export var damage_speed_threshold: float = 60.0
@export var damage_per_speed: float = 0.004

var engines: Array[ShipEngine] = []
var hardpoints: Array[Hardpoint] = []

## Steering commands, refreshed every physics tick. Thrust is 0..1, turn is
## -1..1 with positive turning the nose clockwise on screen.
var thrust_command: float = 0.0
var turn_command: float = 0.0

## Held-down trigger. Read by the weapons every physics tick.
var fire_command: bool = false

## Total damage taken from terrain impacts so far. Becomes HP loss in M1.7.
var accumulated_damage: float = 0.0

var _applied_force: Vector2 = Vector2.ZERO
var _applied_torque: float = 0.0
var _gravity: Vector2 = Vector2.ZERO
var _terrain_contacts: int = 0


func _ready() -> void:
	for child: Node in get_children():
		if child is ShipEngine:
			engines.append(child as ShipEngine)
		elif child is Hardpoint:
			hardpoints.append(child as Hardpoint)


## Weapons fire here and not in _integrate_forces: that callback runs while the
## physics server is flushing queries, and adding nodes to the tree from inside
## it is not allowed.
func _physics_process(delta: float) -> void:
	if use_player_input:
		fire_command = Input.is_action_pressed("ship_fire")

	var container: Node = projectile_container()
	for hardpoint: Hardpoint in hardpoints:
		hardpoint.tick(delta)
		if fire_command:
			hardpoint.fire(linear_velocity, container)


## Where fired rounds are parented. Falls back to the ship's own parent so a
## ship dropped into a bare scene (a test, a preview) still shoots.
func projectile_container() -> Node:
	var container: Node = get_tree().get_first_node_in_group(PROJECTILE_GROUP)
	if container != null:
		return container
	return get_parent()


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if use_player_input:
		read_player_input()
	_apply_commands_to_engines()

	_applied_force = Vector2.ZERO
	_applied_torque = 0.0

	# Gravity is summed from the bodies in range rather than left to the
	# physics server, so the falloff can be ours (see IDEAS.md section 5).
	_gravity = gravity_acceleration_at(state.transform.origin)
	state.apply_central_force(_gravity * mass)

	var body_rotation: float = state.transform.get_rotation()
	for engine: ShipEngine in engines:
		var local_force: Vector2 = engine.get_thrust_force()
		if local_force.is_zero_approx():
			continue
		# apply_force() takes the offset from the body origin in global
		# coordinates: rotated with the body, but not translated.
		var force: Vector2 = local_force.rotated(body_rotation)
		var offset: Vector2 = engine.position.rotated(body_rotation)
		state.apply_force(force, offset)
		_applied_force += force
		_applied_torque += offset.cross(force)

	_resolve_terrain(state)


## Pushes the ship out of any rock its hull is inside, and bounces it.
##
## This runs after the forces because it has the last word: it edits the
## velocity and the transform directly. One aggregated response per tick rather
## than a proper per-point impulse solve, which is the arcade trade named in
## IDEAS.md section 6 — the real landing logic arrives in M1.6.
func _resolve_terrain(state: PhysicsDirectBodyState2D) -> void:
	_terrain_contacts = 0

	var planet: Planet = nearest_planet()
	if planet == null:
		return

	var body_transform: Transform2D = state.transform
	var normal: Vector2 = Vector2.ZERO
	var deepest: float = 0.0

	for hull_point: Vector2 in HULL_POINTS:
		var world_point: Vector2 = body_transform * hull_point
		if not planet.is_solid_at(world_point):
			continue
		_terrain_contacts += 1
		var point_normal: Vector2 = planet.surface_normal_at(world_point)
		normal += point_normal
		deepest = maxf(deepest, planet.penetration_at(world_point, point_normal))

	if _terrain_contacts == 0:
		return

	normal = normal.normalized()
	if normal.is_zero_approx():
		return

	# Lift the hull clear before touching the velocity, or the next tick starts
	# buried again and the ship sinks one step per frame.
	body_transform.origin += normal * (deepest + 0.5)
	state.transform = body_transform

	var velocity: Vector2 = state.linear_velocity
	var closing: float = velocity.dot(normal)
	if closing >= 0.0:
		return

	var impact_speed: float = -closing
	velocity -= (1.0 + terrain_bounce) * closing * normal
	var along_surface: Vector2 = velocity - velocity.dot(normal) * normal
	velocity -= along_surface * terrain_friction
	state.linear_velocity = velocity
	state.angular_velocity *= 0.5

	if impact_speed > damage_speed_threshold:
		var damage: float = (impact_speed - damage_speed_threshold) * damage_per_speed
		accumulated_damage += damage
		hull_impact.emit(impact_speed, damage)


## How many hull points were inside rock last tick.
func get_terrain_contacts() -> int:
	return _terrain_contacts


## Closest planet, or null if there is none in the scene.
func nearest_planet() -> Planet:
	return Planet.nearest(get_tree(), global_position)


## Gravitational acceleration the ship felt last tick. Not get_gravity(),
## which is already taken by PhysicsBody2D.
func get_applied_gravity() -> Vector2:
	return _gravity


## Sums the pull of every gravity source that reaches `point`.
func gravity_acceleration_at(point: Vector2) -> Vector2:
	var total: Vector2 = Vector2.ZERO
	for source: Node in get_tree().get_nodes_in_group(Planet.GRAVITY_GROUP):
		var planet: Planet = source as Planet
		if planet != null:
			total += planet.gravity_at(point)
	return total


## Total force applied by the engines last tick, in global coordinates.
func get_applied_force() -> Vector2:
	return _applied_force


## Total torque applied by the engines last tick.
func get_applied_torque() -> float:
	return _applied_torque


## Ship speed along its own nose direction. Negative means flying backwards.
func get_forward_speed() -> float:
	return linear_velocity.dot(FORWARD.rotated(global_rotation))


## Fills the command fields from the input actions.
func read_player_input() -> void:
	thrust_command = Input.get_action_strength("ship_thrust")
	turn_command = Input.get_axis("ship_rotate_left", "ship_rotate_right")


func _apply_commands_to_engines() -> void:
	var thrust: float = clampf(thrust_command, 0.0, 1.0)
	var turn: float = clampf(turn_command, -1.0, 1.0)
	var wanted_turn_sign: float = signf(turn)

	for engine: ShipEngine in engines:
		match engine.engine_type:
			ShipEngine.Type.MAIN:
				engine.throttle = thrust
			ShipEngine.Type.ROTATIONAL:
				# An engine burns only if its torque turns the ship the way the
				# pilot asked. Which engine that is comes from its mount point,
				# so a relocated engine steers correctly without any wiring.
				if wanted_turn_sign != 0.0 and is_equal_approx(engine.torque_sign(), wanted_turn_sign):
					engine.throttle = absf(turn)
				else:
					engine.throttle = 0.0
			_:
				engine.throttle = 0.0
