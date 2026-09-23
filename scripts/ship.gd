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

## Seconds of coasting before orbit lock is even considered.
const ORBIT_LOCK_DELAY: float = 2.0

## Heating. The hull warms with the power the air is dissipating, which for
## the linear damping the shells apply goes as density times speed squared.
## Tying it to the same quantity that does the braking is what stops the heat
## bar and the deceleration from telling different stories.
##
## HEAT_REFERENCE_SPEED is the speed at which a full-density atmosphere heats
## at HEAT_RATE per second; HEAT_COOLING is the constant bleed, which also sets
## the floor below which a descent never cooks the hull at all.
const HEAT_REFERENCE_SPEED: float = 300.0
const HEAT_RATE: float = 0.8
const HEAT_COOLING: float = 0.05

## Fired on every terrain impact hard enough to hurt. M1.7 turns this into hull
## HP and death; for now it only accumulates.
signal hull_impact(impact_speed: float, damage: float)

## Flight modes. ORBIT_LOCK is a rest state like being landed: the ship stops
## being integrated and follows an analytic circle instead, because holding a
## perfect orbit by hand is busywork (see IDEAS.md section 8).
enum FlightMode { PHYSICAL, ORBIT_LOCK }

## Emitted when the ship enters or leaves orbit lock.
signal flight_mode_changed(mode: FlightMode)

## If true the ship steers itself from the player's input actions. AI ships and
## tests turn this off and write the command fields directly.
@export var use_player_input: bool = true

## Orbit lock can be switched off entirely, which measurement tools need: a
## locked ship holds its radius by definition and would hide integrator drift.
@export var orbit_lock_enabled: bool = true

## Orbit lock tolerances. Radial speed is absolute, tangential is a fraction of
## the circular orbit speed at that radius. Both become module stats in M2.
@export var orbit_lock_radial_tolerance: float = 6.0
@export_range(0.0, 1.0) var orbit_lock_speed_tolerance: float = 0.06

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

## Hull heat, 0..1. Climbs while braking against thick air at speed and bleeds
## off in vacuum. M2 turns a full bar into engine damage.
var hull_heat: float = 0.0

var flight_mode: FlightMode = FlightMode.PHYSICAL

var _coasting_time: float = 0.0
var _lock_planet: Planet = null
var _lock_radius: float = 0.0
var _lock_angle: float = 0.0
var _lock_angular_speed: float = 0.0

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

	if flight_mode == FlightMode.ORBIT_LOCK:
		_run_orbit_lock(state)
		return

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
	_update_heat(state.step)
	_consider_orbit_lock(state)


## Hull heating from braking against the air.
func _update_heat(step: float) -> void:
	var planet: Planet = nearest_planet()
	var density: float = 0.0
	if planet != null:
		density = planet.air_density_at(global_position)

	if density > 0.0:
		var speed_ratio: float = linear_velocity.length() / HEAT_REFERENCE_SPEED
		hull_heat += density * speed_ratio * speed_ratio * HEAT_RATE * step
	hull_heat = clampf(hull_heat - HEAT_COOLING * step, 0.0, 1.0)


## Watches for a good enough circular orbit and takes over when it finds one.
func _consider_orbit_lock(state: PhysicsDirectBodyState2D) -> void:
	if not orbit_lock_enabled:
		return
	if _applied_force.length() > 0.001 or _terrain_contacts > 0:
		_coasting_time = 0.0
		return
	_coasting_time += state.step
	if _coasting_time < ORBIT_LOCK_DELAY:
		return

	var planet: Planet = nearest_planet()
	if planet == null:
		return

	# Locking inside the atmosphere would freeze a decaying orbit in place and
	# quietly cancel aerobraking, which is the opposite of what it is for.
	var position_now: Vector2 = state.transform.origin
	if planet.air_density_at(position_now) > 0.0:
		return

	var offset: Vector2 = position_now - planet.global_position
	var radius: float = offset.length()
	if radius < 0.001 or radius >= planet.influence_radius:
		return

	var up: Vector2 = offset / radius
	var along: Vector2 = up.orthogonal()
	var radial_speed: float = state.linear_velocity.dot(up)
	var tangential_speed: float = state.linear_velocity.dot(along)
	var circular_speed: float = planet.circular_orbit_speed(radius)
	if circular_speed <= 0.0:
		return

	if absf(radial_speed) > orbit_lock_radial_tolerance:
		return
	if absf(absf(tangential_speed) - circular_speed) > circular_speed * orbit_lock_speed_tolerance:
		return

	_lock_planet = planet
	_lock_radius = radius
	_lock_angle = up.angle()
	# Signed, so the lock keeps going the way the pilot was already going.
	_lock_angular_speed = signf(tangential_speed) * circular_speed / radius
	flight_mode = FlightMode.ORBIT_LOCK
	flight_mode_changed.emit(flight_mode)


## Drives the analytic circle while locked.
func _run_orbit_lock(state: PhysicsDirectBodyState2D) -> void:
	if _lock_planet == null or not is_instance_valid(_lock_planet):
		release_orbit_lock()
		return
	# Any thrust hands control back. Rotational engines are left alone so the
	# pilot can still aim while parked.
	if thrust_command > 0.001:
		release_orbit_lock()
		return

	_lock_angle = wrapf(_lock_angle + _lock_angular_speed * state.step, -PI, PI)
	var up: Vector2 = Vector2.from_angle(_lock_angle)

	var body_transform: Transform2D = state.transform
	body_transform.origin = _lock_planet.global_position + up * _lock_radius
	state.transform = body_transform
	# Velocity is kept truthful rather than zeroed, so the HUD, the trajectory
	# preview and the moment of release all see the real orbital motion.
	state.linear_velocity = up.orthogonal() * (_lock_angular_speed * _lock_radius)
	_gravity = _lock_planet.gravity_at(body_transform.origin)

	_update_heat(state.step)


## Hands control back to the solver. Safe to call when not locked.
func release_orbit_lock() -> void:
	if flight_mode == FlightMode.PHYSICAL:
		return
	flight_mode = FlightMode.PHYSICAL
	_coasting_time = 0.0
	_lock_planet = null
	flight_mode_changed.emit(flight_mode)


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
		# A hit is the other way out of orbit lock (IDEAS.md section 8).
		release_orbit_lock()


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
