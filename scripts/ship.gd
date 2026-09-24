class_name Ship
extends RigidBody2D
## A ship: a rigid body plus a set of engine mounts.
##
## Steering is not scripted and engines have no assigned roles. The pilot names
## one of six commands, ShipControl works out from the geometry which engines
## serve it and how strongly, and the solver does the rest. Move an engine and
## its job moves with it; break one and the ship flies crooked, with no code
## anywhere that knows what "crooked" means (see IDEAS.md section 3).
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

## Mass of the bare hull, before any modules. Modules add their mount size on
## top, which is what lets fitting and losing them move the centre of mass.
const HULL_MASS: float = 6.0

## Floor for the angular speed at which kill rotation gives up pulsing and just
## zeroes the spin. The real threshold is computed per tick from the ship's own
## authority, because a single pulse of an impulse engine changes the spin by a
## fixed amount: if the epsilon is smaller than one pulse, every correction
## overshoots and flips the sign, and the assist chatters around zero forever
## instead of finishing. Measured on the stock ship, one pulse is worth about
## 0.04 rad/s, which is twice this floor.
const KILL_ROTATION_EPS: float = 0.02

## Safety factor on that per-pulse estimate.
const KILL_ROTATION_PULSE_MARGIN: float = 1.5

## Angular speed at or above which kill rotation asks for full counter-thrust.
##
## Well under one rad/s on purpose. Because the assist tapers proportionally,
## the spin below this point decays exponentially rather than linearly, and a
## high value spends more time crawling through the last fraction than it did
## killing the first whole radian per second. At 1.0 the stock ship needs about
## two seconds to stop 2 rad/s; at 0.2 it needs under one, which is the bar.
const KILL_ROTATION_GAIN: float = 0.2

## Legs that must be on the ground before a landing is even considered.
const MIN_LEGS_DOWN: int = 2

## How far below a leg the ground may be and still count as touched, in pixels.
##
## Standing for the suspension travel real gear would have, and not optional:
## requiring the legs to be actually buried meant waiting until one of them had
## already been in the rock long enough for the contact solver to tip the ship
## onto it. The landing was then judged on an attitude the landing itself had
## caused, and a level touchdown on flat ground came out 32 degrees off.
const LEG_CONTACT_REACH: float = 5.0

## Damage per px/s of touchdown speed above what the gear can absorb.
const GEAR_OVERLOAD_DAMAGE: float = 0.01

## Below this speed the brake stops the ship outright rather than chasing it.
const BRAKE_EPS: float = 2.0

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
enum FlightMode { PHYSICAL, ORBIT_LOCK, LANDED }

## Emitted when the ship enters or leaves orbit lock or the ground.
signal flight_mode_changed(mode: FlightMode)

## Emitted on a touchdown the gear could not absorb. `reason` is one of
## "speed", "tilt" or "slope", which is what the HUD wants to show.
signal landing_rejected(reason: String)

## Emitted the moment the ship settles on a planet.
signal landed(planet: Planet)

## Emitted when the hull runs out, with the last position and velocity so the
## wreck can be thrown in the right direction.
signal destroyed(at: Vector2, velocity: Vector2)

## Emitted whenever the hull changes, for the HUD.
signal hull_changed(integrity: float)

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

var engines: Array[EngineInstance] = []
var hardpoints: Array[Hardpoint] = []

## Geometry-derived control groups. Rebuilt on every configuration change.
var control: ShipControl = ShipControl.new()

## What the pilot is asking for, ShipControl.Command -> 0..1. Persistent: input
## refreshes it every tick, an AI or a test writes it once and it holds.
var commands: Dictionary = {}

## What is actually flown this tick: the pilot's commands plus whatever the
## assists add on top, rebuilt from scratch every tick.
##
## Kept separate from `commands` on purpose. When the assists wrote straight
## into the pilot's set, nothing ever cleared their entries for a ship not
## driven by input, so the brake kept pushing after the ship had stopped and
## drove it backwards instead of settling.
var active_commands: Dictionary = {}

## Assist holds, set from input or by an AI.
var kill_rotation_command: bool = false
var brake_command: bool = false

## Held-down trigger. Read by the weapons every physics tick.
var fire_command: bool = false

## Hull condition, 1.0 intact and 0.0 destroyed.
##
## On the same 0..1 scale as hull_heat and engine health, which is what makes
## the existing damage numbers work unchanged: a 100 px/s scrape costs 0.16, a
## 200 px/s crash costs 0.56, and anything past about 310 px/s is fatal outright.
var hull_integrity: float = 1.0

## Total damage taken since the last respawn, for the readout.
var accumulated_damage: float = 0.0

## Hull heat, 0..1. Climbs while braking against thick air at speed and bleeds
## off in vacuum. M2 turns a full bar into engine damage.
var hull_heat: float = 0.0

## Air density at the hull, 0..1, refreshed every physics tick. Cached here
## because the heat model, the contrails and the HUD all want it and none of
## them should be repeating the planet lookup.
var air_density: float = 0.0

var flight_mode: FlightMode = FlightMode.PHYSICAL

## The landing gear, if this hull has any.
var gear: LandingGear = null

## Why the last touchdown was refused, for the HUD. Empty once landed.
var last_landing_rejection: String = ""

var _landed_planet: Planet = null
var _landed_angle: float = 0.0
var _landed_radius: float = 0.0
var _landed_heading: float = 0.0

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
		if child is Hardpoint:
			hardpoints.append(child as Hardpoint)
		elif child is LandingGear:
			gear = child as LandingGear
	# Set once here rather than at every landing: it never changes, and writing
	# it from _integrate_forces would be another state change the server
	# refuses mid-flush.
	freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
	rebuild_control_groups()


## Re-reads the fitted engines, recomputes mass, centre of mass and inertia,
## and rebuilds the control groups from the new geometry.
##
## Must be called after anything that changes the configuration: fitting or
## removing a module, or a change in mass. Not after damage: health is
## deliberately left out of the group maths so a broken engine shows up as a
## crooked ship rather than being quietly compensated for.
func rebuild_control_groups(verbose: bool = true) -> void:
	engines.clear()
	for child: Node in get_children():
		var mount: EngineMount = child as EngineMount
		if mount != null and mount.installed != null:
			engines.append(EngineInstance.new(mount.installed, mount))

	_recompute_mass_properties()
	control.rebuild(engines, center_of_mass, mass, inertia)

	if verbose:
		print("%s: mass %.1f, com (%.2f, %.2f), inertia %.0f" % [
			name, mass, center_of_mass.x, center_of_mass.y, inertia,
		])
		for line: String in control.describe():
			print("  " + line)


## Mass, centre of mass and inertia from the hull plus the fitted modules.
##
## The hull is treated as a uniform lamina over its collision polygon, so the
## numbers follow the shape instead of being guessed; modules are point masses
## at their mounts. The body is switched to a custom centre of mass because the
## default one ignores the modules entirely, and every torque in the control
## maths is measured from it.
func _recompute_mass_properties() -> void:
	var polygon: PackedVector2Array = _hull_polygon()
	var hull_centroid: Vector2 = _polygon_centroid(polygon)
	var hull_inertia: float = _polygon_inertia(polygon, HULL_MASS, hull_centroid)

	var total_mass: float = HULL_MASS
	var weighted: Vector2 = hull_centroid * HULL_MASS
	for engine: EngineInstance in engines:
		var module: float = engine.mount.module_mass()
		total_mass += module
		weighted += engine.mount.position * module

	var centre: Vector2 = weighted / maxf(total_mass, 0.0001)

	# Parallel axis theorem: the hull's own inertia about its centroid, shifted
	# to the combined centre, plus each module as a point mass.
	var total_inertia: float = hull_inertia + HULL_MASS * hull_centroid.distance_squared_to(centre)
	for engine: EngineInstance in engines:
		total_inertia += engine.mount.module_mass() * engine.mount.position.distance_squared_to(centre)

	mass = total_mass
	center_of_mass_mode = RigidBody2D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = centre
	inertia = maxf(total_inertia, 0.0001)


func _hull_polygon() -> PackedVector2Array:
	var shape_node: CollisionShape2D = get_node_or_null("HullShape") as CollisionShape2D
	if shape_node != null:
		var convex: ConvexPolygonShape2D = shape_node.shape as ConvexPolygonShape2D
		if convex != null and convex.points.size() >= 3:
			return convex.points
	# Falling back on the contact points keeps a ship without a shape usable
	# rather than dividing by a zero area.
	return PackedVector2Array(HULL_POINTS)


func _polygon_centroid(polygon: PackedVector2Array) -> Vector2:
	var area: float = 0.0
	var centroid: Vector2 = Vector2.ZERO
	for i: int in range(polygon.size()):
		var a: Vector2 = polygon[i]
		var b: Vector2 = polygon[(i + 1) % polygon.size()]
		var cross: float = a.cross(b)
		area += cross
		centroid += (a + b) * cross
	if absf(area) < 0.0001:
		return Vector2.ZERO
	return centroid / (3.0 * area)


## Mass moment of inertia of a uniform polygon about its own centroid.
func _polygon_inertia(polygon: PackedVector2Array, polygon_mass: float, centroid: Vector2) -> float:
	var area: float = 0.0
	var moment: float = 0.0
	for i: int in range(polygon.size()):
		var a: Vector2 = polygon[i]
		var b: Vector2 = polygon[(i + 1) % polygon.size()]
		var cross: float = a.cross(b)
		area += cross
		moment += cross * (a.dot(a) + a.dot(b) + b.dot(b))
	area *= 0.5
	if absf(area) < 0.0001:
		return polygon_mass
	# moment/12 is the polar second moment of AREA about the origin; multiplying
	# by the areal density turns it into a mass moment, then the parallel axis
	# theorem shifts it to the centroid.
	var about_origin: float = (moment / 12.0) * (polygon_mass / area)
	return maxf(about_origin - polygon_mass * centroid.length_squared(), 0.0001)


## Weapons fire here and not in _integrate_forces: that callback runs while the
## physics server is flushing queries, and adding nodes to the tree from inside
## it is not allowed.
## Input is polled here rather than in _integrate_forces, and so is the decision
## to leave the ground. A frozen body gets no _integrate_forces at all, so a
## landed ship that only listened there could never be told to take off again.
func _physics_process(delta: float) -> void:
	if use_player_input:
		read_player_input()
		fire_command = Input.is_action_pressed("ship_fire")
		if Input.is_action_just_pressed("toggle_gear") and gear != null:
			gear.set_deployed(not gear.is_deployed() and not gear.is_moving())

	if gear != null:
		gear.advance(delta)
		# Deployed legs only bite in air. Scaling by density rather than
		# switching on a boolean keeps the speed brake worthless in vacuum,
		# where a drag penalty would be nonsense.
		linear_damp = gear.deployed_drag * gear.extension * air_density

	if flight_mode == FlightMode.LANDED:
		if _wants_translation(commands) or brake_command:
			take_off()
		else:
			_hold_landed_pose()

	var container: Node = projectile_container()
	for hardpoint: Hardpoint in hardpoints:
		hardpoint.tick(delta)
		if fire_command:
			hardpoint.fire(linear_velocity, container, self)


## Where fired rounds are parented. Falls back to the ship's own parent so a
## ship dropped into a bare scene (a test, a preview) still shoots.
func projectile_container() -> Node:
	var container: Node = get_tree().get_first_node_in_group(PROJECTILE_GROUP)
	if container != null:
		return container
	return get_parent()


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if flight_mode == FlightMode.LANDED:
		return

	_resolve_commands(state)
	control.apply_commands(engines, active_commands)
	for engine: EngineInstance in engines:
		engine.advance(state.step)
		engine.mount.set_exhaust(engine.effective_output())

	_applied_force = Vector2.ZERO
	_applied_torque = 0.0

	if flight_mode == FlightMode.ORBIT_LOCK:
		# The lock owns where the ship is, not which way it points. Torque still
		# reaches the body so the pilot can aim, reorient for a burn or kill a
		# spin while parked; only the forces that would move it are dropped,
		# and a command that would move it releases the lock anyway.
		_apply_engine_torque(state)
		_run_orbit_lock(state)
		return

	# Gravity is summed from the bodies in range rather than left to the
	# physics server, so the falloff can be ours (see IDEAS.md section 5).
	_gravity = gravity_acceleration_at(state.transform.origin)
	state.apply_central_force(_gravity * mass)

	var body_rotation: float = state.transform.get_rotation()
	for engine: EngineInstance in engines:
		var local_force: Vector2 = engine.current_force()
		if local_force.is_zero_approx():
			continue
		# Confirmed against the 4.7 docs: apply_force()'s position is "the
		# offset from the body origin in global coordinates". From the ORIGIN,
		# not the centre of mass, so the mount position is only rotated, never
		# shifted. The server takes the torque about the centre of mass itself,
		# which is why center_of_mass has to be right for any of this to work.
		var force: Vector2 = local_force.rotated(body_rotation)
		var offset: Vector2 = engine.mount.position.rotated(body_rotation)
		state.apply_force(force, offset)
		_applied_force += force
		_applied_torque += (engine.mount.position - center_of_mass).rotated(body_rotation).cross(force)

	_resolve_terrain(state)
	_update_heat(state.step)
	_consider_orbit_lock(state)


## Turns the ship without pushing it, for use while the lock owns the position.
##
## The rotational groups are couples with no net force by design, so taking
## only their torque is what they were going to do anyway rather than an
## approximation (see IDEAS.md section 3).
func _apply_engine_torque(state: PhysicsDirectBodyState2D) -> void:
	var body_rotation: float = state.transform.get_rotation()
	for engine: EngineInstance in engines:
		var local_force: Vector2 = engine.current_force()
		if local_force.is_zero_approx():
			continue
		var force: Vector2 = local_force.rotated(body_rotation)
		var arm: Vector2 = (engine.mount.position - center_of_mass).rotated(body_rotation)
		_applied_torque += arm.cross(force)
	if not is_zero_approx(_applied_torque):
		state.apply_torque(_applied_torque)


## Hull heating from braking against the air.
func _update_heat(step: float) -> void:
	var planet: Planet = nearest_planet()
	air_density = planet.air_density_at(global_position) if planet != null else 0.0

	if air_density > 0.0:
		var speed_ratio: float = linear_velocity.length() / HEAT_REFERENCE_SPEED
		hull_heat += air_density * speed_ratio * speed_ratio * HEAT_RATE * step
	hull_heat = clampf(hull_heat - HEAT_COOLING * step, 0.0, 1.0)


## Direction a body travels in when its polar angle increases, at outward
## direction `up`.
##
## Deliberately NOT `up.orthogonal()`. That turns 90 degrees anticlockwise,
## which in Godot's Y-down space is the opposite handedness to the angle the
## lock advances with. Mixing the two made the locked ship run backwards along
## its own orbit: the sign of the tangential speed was measured against one
## tangent and the position was then stepped along the other.
static func _tangent(up: Vector2) -> Vector2:
	return Vector2(-up.y, up.x)


## Watches for a good enough circular orbit and takes over when it finds one.
func _consider_orbit_lock(state: PhysicsDirectBodyState2D) -> void:
	if not orbit_lock_enabled:
		return
	if not active_commands.is_empty() or _applied_force.length() > 0.001 or _terrain_contacts > 0:
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
	var along: Vector2 = _tangent(up)
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
	# Anything that would move the ship hands control back. Rotation commands
	# are left alone so the pilot can still aim while parked.
	if _wants_translation(active_commands) or brake_command:
		release_orbit_lock()
		return

	_lock_angle = wrapf(_lock_angle + _lock_angular_speed * state.step, -PI, PI)
	var up: Vector2 = Vector2.from_angle(_lock_angle)

	var body_transform: Transform2D = state.transform
	body_transform.origin = _lock_planet.global_position + up * _lock_radius
	state.transform = body_transform
	# Velocity is kept truthful rather than zeroed, so the HUD, the trajectory
	# preview and the moment of release all see the real orbital motion.
	state.linear_velocity = _tangent(up) * (_lock_angular_speed * _lock_radius)
	_gravity = _lock_planet.gravity_at(body_transform.origin)

	_update_heat(state.step)


## True if any command in `set` would translate the ship rather than turn it.
func _wants_translation(command_set: Dictionary) -> bool:
	for command: ShipControl.Command in ShipControl.LINEAR_COMMANDS:
		if float(command_set.get(command, 0.0)) > 0.001:
			return true
	return false


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

	# Before the impulses, while the approach speed and attitude are still the
	# ones the pilot flew rather than ones the first bounce produced.
	if _try_land(state, planet):
		return

	var local_points: Array[Vector2] = contact_points()
	for i: int in range(local_points.size()):
		var world_point: Vector2 = body_transform * local_points[i]
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
		hull_impact.emit(impact_speed, damage)
		# A hit is the other way out of orbit lock (IDEAS.md section 8).
		release_orbit_lock()
		take_damage(damage, "impact")


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


## Points tested against the terrain: the hull always, the legs once they are
## fully out. The legs are appended last so the contact loop can tell which
## contacts were made on them.
func contact_points() -> Array[Vector2]:
	var points: Array[Vector2] = HULL_POINTS.duplicate()
	if gear != null:
		points.append_array(gear.contact_points())
	return points


## Decides whether a touchdown is a landing, and does it.
##
## Nothing here is scripted difficulty: every threshold is a gear stat, and the
## ship either meets them or does not. Returns true when the ship has landed,
## in which case the caller must not also apply contact impulses.
func _try_land(state: PhysicsDirectBodyState2D, planet: Planet) -> bool:
	if gear == null or not gear.is_deployed():
		return false
	# Not while burning. Without this a ship that has just lifted off is still
	# sitting on its legs at zero descent, meets every condition, and lands
	# again on the same tick, so it can never leave.
	if _wants_translation(active_commands) or brake_command:
		return false

	var legs_down: int = 0
	for clearance: float in ground_under_legs(planet, state.transform):
		if clearance <= LEG_CONTACT_REACH:
			legs_down += 1
	# Nothing is touching yet, so there is nothing to judge.
	if legs_down == 0:
		return false

	var up: Vector2 = (state.transform.origin - planet.global_position).normalized()
	var slope: float = slope_under_legs(planet, state.transform)
	# Derived from the height field rather than probed out of the bitmap. The
	# probe ring needs to straddle a surface, and a leg resting a few pixels
	# into the rock has most of its ring inside: it reported a level shelf as a
	# 55 degree wall and refused every landing. Taking the normal from the same
	# slope the check already measures cannot disagree with it either.
	var normal: Vector2 = up.rotated(-slope)
	# Measured against the ground, which is moving on a spinning planet: what
	# matters is the speed relative to the rock, not to the planet's centre.
	var relative: Vector2 = state.linear_velocity - planet.surface_velocity_at(state.transform.origin)
	var descent: float = -relative.dot(up)
	var lateral: float = absf(relative.dot(up.orthogonal()))

	var over_descent: float = descent - gear.max_vertical_speed
	var over_lateral: float = lateral - gear.max_lateral_speed
	if over_descent > 0.0 or over_lateral > 0.0:
		_reject_landing("speed")
		# Not binary: the legs take the overshoot as damage and the ship stays
		# in the air's hands, rather than the landing simply not happening.
		var excess: float = maxf(over_descent, 0.0) + maxf(over_lateral, 0.0)
		var damage: float = excess * GEAR_OVERLOAD_DAMAGE
		hull_impact.emit(descent, damage)
		take_damage(damage, "gear")
		return false

	# Attitude is judged on the first leg to touch, not once they all have.
	# They never all would: at an 18 px track and 3 px of travel, two legs can
	# only be down together if the ship is within about ten degrees of level,
	# so waiting for both made a fifteen degree tolerance unreachable and the
	# check dead code. Refusing early also gives the pilot a reason instead of
	# an unexplained tumble.
	var ship_up: Vector2 = FORWARD.rotated(state.transform.get_rotation())
	if absf(ship_up.angle_to(normal)) > gear.max_tilt:
		_reject_landing("tilt")
		return false

	# Standing on one leg is not standing.
	if legs_down < MIN_LEGS_DOWN:
		return false

	# Measured across the legs, which is the ground they actually have to stand
	# on. A shorter span is no good here: over 12 px on a 1.5 px texel grid a
	# single step between texels reads as a cliff.
	if absf(slope) > gear.max_slope:
		_reject_landing("slope")
		return false

	_settle_on(planet, state)
	return true


## Clearance between each leg and the ground directly beneath it, in pixels.
## Negative means the leg is already in the rock.
##
## Sampled per leg rather than through the ship's centre. A two point slope
## taken across the hull can read as perfectly level while the ship sits astride
## a ridge, because both samples land on the flanks and neither sees the crest
## between them. Asking each leg about its own patch cannot be fooled that way,
## and it is what IDEAS.md section 7 specifies anyway.
func ground_under_legs(planet: Planet, from: Transform2D) -> Array[float]:
	var clearances: Array[float] = []
	if gear == null:
		return clearances
	for leg: Vector2 in gear.legs:
		var leg_point: Vector2 = from * leg
		clearances.append(
			leg_point.distance_to(planet.global_position) - planet.surface_radius_at(leg_point)
		)
	return clearances


## Ground slope across the outermost legs, in radians, signed along the line
## from the first leg to the last.
func slope_under_legs(planet: Planet, from: Transform2D) -> float:
	if gear == null or gear.legs.size() < 2:
		return 0.0
	var first_leg: Vector2 = gear.legs[0]
	var last_leg: Vector2 = gear.legs[gear.legs.size() - 1]
	var first: Vector2 = from * first_leg
	var last: Vector2 = from * last_leg
	var run: float = first.distance_to(last)
	if run < 0.001:
		return 0.0
	var rise: float = planet.surface_radius_at(last) - planet.surface_radius_at(first)
	return atan2(rise, run) * signf(last_leg.x - first_leg.x)


func _reject_landing(reason: String) -> void:
	if last_landing_rejection == reason:
		return
	last_landing_rejection = reason
	landing_rejected.emit(reason)


## Pins the ship to the ground in the planet's polar frame.
##
## Stored as (angle, radius, heading relative to the planet) rather than as a
## world transform, so a turning planet carries the ship with it. The ship is
## deliberately NOT reparented to the planet: IDEAS.md section 9 requires the
## player to stay a direct child of the world, because systems are streamed in
## and out underneath it.
func _settle_on(planet: Planet, state: PhysicsDirectBodyState2D) -> void:
	var offset: Vector2 = state.transform.origin - planet.global_position
	_landed_planet = planet
	_landed_angle = offset.angle() - planet.global_rotation
	_landed_radius = offset.length()
	_landed_heading = state.transform.get_rotation() - planet.global_rotation

	state.linear_velocity = Vector2.ZERO
	state.angular_velocity = 0.0
	# Deferred, because this runs inside _integrate_forces and freezing is a
	# change to the body's state in the physics server, which refuses it while
	# it is flushing queries. The same trap as spawning a projectile from here.
	# One tick passes before it takes hold, which costs nothing: flight_mode is
	# already LANDED, so _integrate_forces bails out and applies no gravity, and
	# the velocity has just been zeroed.
	set_deferred("freeze", true)

	last_landing_rejection = ""
	flight_mode = FlightMode.LANDED
	flight_mode_changed.emit(flight_mode)
	landed.emit(planet)


## Keeps a landed ship glued to its patch of ground as the planet turns.
func _hold_landed_pose() -> void:
	if _landed_planet == null or not is_instance_valid(_landed_planet):
		flight_mode = FlightMode.PHYSICAL
		freeze = false
		return
	# The angle stays in the planet's own frame: polar_to_world runs it through
	# to_global(), which already applies the planet's rotation. Adding the
	# rotation here as well turned a parked ship into one sliding across the
	# ground at twice the surface speed.
	global_position = _landed_planet.polar_to_world(_landed_angle, _landed_radius)
	global_rotation = _landed_heading + _landed_planet.global_rotation


## Releases the ship from the ground, carrying the surface velocity with it so
## lift-off from a spinning planet does not start with a jolt.
func take_off(state: PhysicsDirectBodyState2D = null) -> void:
	if flight_mode != FlightMode.LANDED:
		return
	var surface_velocity: Vector2 = Vector2.ZERO
	if _landed_planet != null and is_instance_valid(_landed_planet):
		surface_velocity = _landed_planet.surface_velocity_at(global_position)

	freeze = false
	flight_mode = FlightMode.PHYSICAL
	_landed_planet = null
	if state != null:
		state.linear_velocity = surface_velocity
	else:
		linear_velocity = surface_velocity
	flight_mode_changed.emit(flight_mode)


## Takes damage from any source. The single door in, so that every way of
## hurting the ship shares the death path rather than each inventing its own.
## `cause` is not used yet. It is here because M2 wants damage to fall on the
## part that took it, and the call sites that know the answer are these.
func take_damage(amount: float, cause: String = "") -> void:
	if amount <= 0.0 or hull_integrity <= 0.0:
		return
	var _taken_by: String = cause
	accumulated_damage += amount
	hull_integrity = maxf(hull_integrity - amount, 0.0)
	hull_changed.emit(hull_integrity)
	if hull_integrity <= 0.0:
		_destroy()


func is_destroyed() -> bool:
	return hull_integrity <= 0.0


func _destroy() -> void:
	# The ship is not freed. Everything points at it, the camera, the HUD, the
	# contrails, the debug layer, and re-instantiating would mean rewiring all
	# of it on every death in a game whose whole point is dying often. The world
	# puts it back together in place instead.
	release_orbit_lock()
	if flight_mode == FlightMode.LANDED:
		set_deferred("freeze", false)
		flight_mode = FlightMode.PHYSICAL
		_landed_planet = null
	destroyed.emit(global_position, linear_velocity)


## Puts a wrecked ship back in the air, intact and empty-handed.
##
## Resets everything a death should clear rather than only the obvious parts:
## leaving the heat, the gear or a stale landing rejection behind would have the
## new ship inherit the old one's problems.
func respawn(at: Vector2, velocity: Vector2) -> void:
	hull_integrity = 1.0
	accumulated_damage = 0.0
	hull_heat = 0.0
	last_landing_rejection = ""
	commands.clear()
	active_commands.clear()
	kill_rotation_command = false
	brake_command = false
	fire_command = false
	for engine: EngineInstance in engines:
		engine.throttle = 0.0
		engine.target_throttle = 0.0
		engine.mount.set_exhaust(0.0)
	if gear != null:
		gear.set_deployed(false)
		gear.extension = 0.0

	flight_mode = FlightMode.PHYSICAL
	_landed_planet = null
	_coasting_time = 0.0
	freeze = false
	global_position = at
	global_rotation = velocity.angle() - PI * 0.5 if not velocity.is_zero_approx() else 0.0
	linear_velocity = velocity
	angular_velocity = 0.0
	# Without this the interpolator draws a streak from where the wreck died to
	# where the new ship appeared.
	reset_physics_interpolation()

	hull_changed.emit(hull_integrity)
	flight_mode_changed.emit(flight_mode)


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


## Fills the command set from the input actions. Only action names here, never
## keycodes. Called from _physics_process, see the note there.
func read_player_input() -> void:
	commands.clear()
	_set_command(ShipControl.Command.FORWARD, Input.get_action_strength("thrust_forward"))
	_set_command(ShipControl.Command.BACK, Input.get_action_strength("thrust_reverse"))
	_set_command(ShipControl.Command.CCW, Input.get_action_strength("rotate_left"))
	_set_command(ShipControl.Command.CW, Input.get_action_strength("rotate_right"))
	_set_command(ShipControl.Command.STRAFE_LEFT, Input.get_action_strength("strafe_left"))
	_set_command(ShipControl.Command.STRAFE_RIGHT, Input.get_action_strength("strafe_right"))
	kill_rotation_command = Input.is_action_pressed("kill_rotation")
	brake_command = Input.is_action_pressed("brake")


func _set_command(command: ShipControl.Command, amount: float) -> void:
	if amount > 0.0:
		commands[command] = amount


## Adds whatever the two assists are asking for on top of the pilot's commands.
func _resolve_commands(state: PhysicsDirectBodyState2D) -> void:
	active_commands = commands.duplicate()
	if kill_rotation_command:
		_apply_kill_rotation(state)
	if brake_command:
		_apply_brake(state)


## Cancels spin by asking for the opposite rotation, proportionally.
##
## Below the epsilon the spin is zeroed outright: impulse engines are all or
## nothing, so chasing the last hundredth of a radian with them oscillates
## forever instead of converging.
func _apply_kill_rotation(state: PhysicsDirectBodyState2D) -> void:
	var spin: float = state.angular_velocity
	var opposing: ShipControl.Command = (
		ShipControl.Command.CCW if spin > 0.0 else ShipControl.Command.CW
	)

	# Derived rather than fixed, so retuning the torque jets cannot silently
	# reintroduce the chatter this guards against.
	var per_pulse: float = control.authority_of(opposing) / maxf(inertia, 0.0001) * state.step
	var epsilon: float = maxf(KILL_ROTATION_EPS, per_pulse * KILL_ROTATION_PULSE_MARGIN)
	if absf(spin) <= epsilon:
		state.angular_velocity = 0.0
		return
	var amount: float = clampf(absf(spin) / KILL_ROTATION_GAIN, 0.0, 1.0)
	active_commands[opposing] = maxf(float(active_commands.get(opposing, 0.0)), amount)


## Kills linear velocity by pushing against it, one axis at a time.
##
## Rotation is left alone entirely: brake is for stopping, aiming stays the
## pilot's job. A direction with no engines behind it simply is not braked, so
## a ship with no reverse thruster cannot stop itself going forward. That is
## the intended consequence of building the groups from geometry, not a gap.
func _apply_brake(state: PhysicsDirectBodyState2D) -> void:
	var local_velocity: Vector2 = state.linear_velocity.rotated(-state.transform.get_rotation())
	if local_velocity.length() < BRAKE_EPS:
		state.linear_velocity = Vector2.ZERO
		return

	# Each pair is (what fights a negative component, what fights a positive
	# one). Forward is -Y, so drifting forward is negative and wants BACK;
	# drifting right is +X and wants STRAFE_LEFT. Getting the second pair the
	# wrong way round made the brake push the ship harder in the direction it
	# was already sliding.
	_brake_axis(
		local_velocity.y,
		ShipControl.Command.BACK,
		ShipControl.Command.FORWARD,
	)
	_brake_axis(
		local_velocity.x,
		ShipControl.Command.STRAFE_RIGHT,
		ShipControl.Command.STRAFE_LEFT,
	)


## One velocity component against the group that opposes it.
##
## `opposes_negative` is the command that pushes against a negative component,
## `opposes_positive` against a positive one. Named for what they fight rather
## than for their own direction, because the two read the same at a glance and
## the pair for the sideways axis was written backwards. The throttle
## is the time the group would need to kill this component, clamped to one
## second, so it holds full thrust while there is real speed to shed and eases
## off over the last stretch instead of overshooting into a wobble.
func _brake_axis(
	component: float, opposes_negative: ShipControl.Command, opposes_positive: ShipControl.Command
) -> void:
	if is_zero_approx(component):
		return
	var command: ShipControl.Command = opposes_negative if component < 0.0 else opposes_positive
	var authority: float = control.authority_of(command)
	if authority <= 0.0:
		return
	var amount: float = clampf(absf(component) * mass / authority, 0.0, 1.0)
	active_commands[command] = maxf(float(active_commands.get(command, 0.0)), amount)
