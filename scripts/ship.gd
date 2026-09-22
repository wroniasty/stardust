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

## Passes of the contact solver per tick. The contacts are coupled, so one
## pass leaves the ship visibly soft on a multi-point landing.
const CONTACT_ITERATIONS: int = 4

## Below this closing speed a contact does not bounce at all, in px/s. Without
## it a resting hull keeps trading tiny impulses with the ground.
const RESTITUTION_CUTOFF: float = 30.0

## Overlap left uncorrected, in pixels, and the fraction of the rest that is
## corrected per tick. Both exist to keep positional correction from pumping
## energy into a resting ship.
const PENETRATION_SLOP: float = 0.5
const PENETRATION_CORRECTION: float = 0.6

## Fired on every terrain impact hard enough to hurt. M1.7 turns this into hull
## HP and death; for now it only accumulates.
signal hull_impact(impact_speed: float, damage: float)

## If true the ship steers itself from the player's input actions. AI ships and
## tests turn this off and write the command fields directly.
@export var use_player_input: bool = true

## Restitution: how much of the closing speed a hard hit gives back. Only
## applied above RESTITUTION_CUTOFF, so a ship sitting on the ground stays.
@export_range(0.0, 1.0) var terrain_bounce: float = 0.15

## Coulomb friction coefficient between hull and rock. Caps the tangential
## impulse at each contact, which is what stops a landed ship sliding downhill.
@export_range(0.0, 2.0) var terrain_friction: float = 0.7

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


## Resolves every hull point that is inside rock.
##
## Each contact gets its own impulse applied at its own offset from the centre
## of mass, which is what makes the ship pivot: touch down on one rear corner
## and the impulse there spins the ship about that corner, exactly as it should.
## An aggregated central response cannot do that no matter how it is tuned.
##
## Runs after the engine forces because it has the last word: it edits the
## velocity, the spin and the transform directly.
func _resolve_terrain(state: PhysicsDirectBodyState2D) -> void:
	_terrain_contacts = 0

	var planet: Planet = nearest_planet()
	if planet == null:
		return

	var body_transform: Transform2D = state.transform
	var points: Array[Vector2] = []
	var normals: Array[Vector2] = []
	var deepest: float = 0.0
	var deepest_normal: Vector2 = Vector2.ZERO

	for hull_point: Vector2 in HULL_POINTS:
		var world_point: Vector2 = body_transform * hull_point
		if not planet.is_solid_at(world_point):
			continue
		var point_normal: Vector2 = planet.surface_normal_at(world_point)
		if point_normal.is_zero_approx():
			continue
		points.append(world_point)
		normals.append(point_normal)
		var depth: float = planet.penetration_at(world_point, point_normal)
		if depth > deepest:
			deepest = depth
			deepest_normal = point_normal

	_terrain_contacts = points.size()
	if _terrain_contacts == 0:
		return

	# Torque comes from the lever arm to the centre of mass, not to the origin.
	# On this hull they are ~3 px apart, which is enough to matter.
	var centre_of_mass: Vector2 = body_transform.origin + state.center_of_mass
	var impact_speed: float = _apply_contact_impulses(state, centre_of_mass, points, normals)

	# Positional correction is deliberately partial and leaves a sliver of
	# overlap. Pushing the hull fully clear every tick adds height that gravity
	# then gives back, and the ship hops along the ground forever.
	if deepest > PENETRATION_SLOP:
		body_transform.origin += deepest_normal * ((deepest - PENETRATION_SLOP) * PENETRATION_CORRECTION)
		state.transform = body_transform

	if impact_speed > damage_speed_threshold:
		var damage: float = (impact_speed - damage_speed_threshold) * damage_per_speed
		accumulated_damage += damage
		hull_impact.emit(impact_speed, damage)


## Solves the contacts with sequential impulses and returns the hardest
## approach speed seen, for the damage model.
##
## Several passes because the contacts are coupled: an impulse at the nose
## changes the closing speed at the tail. Four is plenty for six points.
func _apply_contact_impulses(
	state: PhysicsDirectBodyState2D,
	centre_of_mass: Vector2,
	points: Array[Vector2],
	normals: Array[Vector2],
) -> float:
	var inverse_mass: float = state.inverse_mass
	var inverse_inertia: float = state.inverse_inertia
	var hardest: float = 0.0

	for iteration: int in range(CONTACT_ITERATIONS):
		for i: int in range(points.size()):
			var arm: Vector2 = points[i] - centre_of_mass
			var normal: Vector2 = normals[i]

			var closing: float = _velocity_at(state, arm).dot(normal)
			if closing >= 0.0:
				continue
			if iteration == 0:
				hardest = maxf(hardest, -closing)

			var normal_arm: float = arm.cross(normal)
			var normal_mass: float = inverse_mass + normal_arm * normal_arm * inverse_inertia
			if normal_mass <= 0.0:
				continue

			# Bounce only above a cutoff. Keeping restitution at a resting
			# contact is the other half of why the ship never stopped hopping.
			var restitution: float = terrain_bounce if -closing > RESTITUTION_CUTOFF else 0.0
			var normal_impulse: float = -(1.0 + restitution) * closing / normal_mass
			_apply_impulse_at(state, normal * normal_impulse, arm, inverse_mass, inverse_inertia)

			# Coulomb friction along the surface, capped by the normal impulse.
			var tangent: Vector2 = Vector2(-normal.y, normal.x)
			var sliding: float = _velocity_at(state, arm).dot(tangent)
			var tangent_arm: float = arm.cross(tangent)
			var tangent_mass: float = inverse_mass + tangent_arm * tangent_arm * inverse_inertia
			if tangent_mass <= 0.0:
				continue
			var limit: float = terrain_friction * normal_impulse
			var friction_impulse: float = clampf(-sliding / tangent_mass, -limit, limit)
			_apply_impulse_at(state, tangent * friction_impulse, arm, inverse_mass, inverse_inertia)

	return hardest


## Velocity of the hull at an offset from the centre of mass.
func _velocity_at(state: PhysicsDirectBodyState2D, arm: Vector2) -> Vector2:
	return state.linear_velocity + state.angular_velocity * Vector2(-arm.y, arm.x)


func _apply_impulse_at(
	state: PhysicsDirectBodyState2D,
	impulse: Vector2,
	arm: Vector2,
	inverse_mass: float,
	inverse_inertia: float,
) -> void:
	state.linear_velocity += impulse * inverse_mass
	state.angular_velocity += arm.cross(impulse) * inverse_inertia


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
