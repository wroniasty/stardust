extends SceneTree
## Headless flight check. Run with:
##   godot --headless --path . --script res://tools/smoke_test.gd
##
## Covers the things that are easy to get silently wrong and impossible to see
## by eye: engine wiring, the shape of the gravity field, and whether an orbit
## actually closes. Exits non-zero if any expectation fails.
##
## The flight phases run on the real physics loop, one at a time, because the
## physics server cannot be stepped by hand from script.

const SHIP_SCENE: String = "res://scenes/ship.tscn"
const PLANET_SCENE: String = "res://scenes/planet.tscn"

## A seed known to produce a planet with air. Picked once, kept fixed so the
## numbers below stay meaningful.
const TEST_SEED: int = 20260922

const BURN_TICKS: int = 60

## Long enough for the main drive to finish spooling and then some.
const FORWARD_BURN_TICKS: int = 120

## Spin handed to the kill-rotation phase, and the second it is allowed.
const KILL_SPIN: float = 2.0
const KILL_TICKS: int = 90

## Speed the brake has to shed, and the time it gets.
##
## Eight seconds rather than five because sideways braking is genuinely slower:
## the strafe groups muster 300 N against the retro thruster's 500 N, so a
## sideways stop takes about six seconds to the forward stop's four and a half.
## That is the ship's design showing through, not a fault.
const BRAKE_SPEED: float = 100.0
const BRAKE_TICKS: int = 480
const FALL_TICKS: int = 60
const ORBIT_TICKS: int = 1800
const LANDING_TICKS: int = 600

## How far above the local ground the landing test drops the ship.
const DROP_HEIGHT: float = 60.0

## Orbit lock needs ORBIT_LOCK_DELAY of coasting plus room to prove it holds,
## then a burst of thrust at the end to prove it lets go.
const LOCK_TICKS: int = 300
const LOCK_THRUST_AT_TICK: int = 240

const AEROBRAKE_TICKS: int = 120
const HEAT_TICKS: int = 120

## Spin handed to the ship in the two damping phases, in rad/s.
const SPIN_START: float = 2.0
const SPIN_TICKS: int = 60

## Tilt of the dropped ship, so touchdown happens on one corner.
const LANDING_TILT: float = 0.45

## Landing phases: drop height, and long enough to fall it and settle.
const TOUCHDOWN_HEIGHT: float = 30.0
const TOUCHDOWN_TICKS: int = 180

## Descent forced on the overspeed test, well past what the legs absorb.
const HARD_DESCENT: float = 120.0

## Spin forced on the planet for the carry test, and how long to watch.
const TEST_SPIN: float = 0.02
const RIDE_TICKS: int = 120

## Long enough for a round to cross the gap below and dig in.
const WEAPON_TICKS: int = 60

## Long enough for a round fired straight down to arm and come back.
const SELF_HIT_TICKS: int = 120

## Long enough to fall from orbit and hit the ground hard.
const DEATH_TICKS: int = 900

## FIELD comes first and only inspects a planet. It has to run on the physics
## loop like everything else: nodes added from _initialize() are not in the
## tree yet, so a planet queried there would still hold its default parameters
## instead of the ones _ready() rolls from the seed.
enum Phase { FIELD, TERRAIN, CONTROL_GROUPS, FORWARD_BURN, ROTATE_CW, ROTATE_CCW,
	ROTATE_DAMAGED, KILL_ROTATION, BRAKE, BRAKE_SIDEWAYS, BRAKE_DIAGONAL, STRAFE, FREE_FALL, ORBIT,
	ORBIT_LOCK, AEROBRAKE, HULL_HEAT, SPIN_IN_AIR, SPIN_IN_VACUUM, LANDING,
	PLATEAU, GEAR, LANDING_GOOD, LANDING_FAST, LANDING_STEEP, LANDED_RIDE,
	WEAPON, HULL, SELF_HIT, DEATH, DONE }

var _phase: int = Phase.FIELD
var _ticks: int = 0
var _elapsed: float = 0.0
var _ship: Ship = null
var _planet: Planet = null
var _orbit_radius: float = 0.0
var _orbit_min: float = INF
var _orbit_max: float = 0.0
var _ground_radius: float = 0.0
var _landing_deepest: float = 0.0
var _lock_engaged: bool = false
var _lock_released: bool = false
var _lock_radius_min: float = INF
var _lock_radius_max: float = 0.0
var _entry_speed: float = 0.0
var _peak_heat: float = 0.0
var _peak_drift: float = 0.0
var _clean_turn_spin: float = 0.0
var _damaged_turn_spin: float = 0.0
var _kill_ticks: int = -1
var _peak_turn_during_brake: float = 0.0
var _peak_speed: float = 0.0
var _flat_angle: float = 0.0
var _steep_angle: float = 0.0
var _ride_start_world: Vector2 = Vector2.ZERO
var _ride_start_polar: float = 0.0
var _took_off: bool = false
var _first_touchdown: String = ""
var _death_reported: bool = false
var _death_hull: float = -1.0
var _respawn_radius: float = 0.0
var _self_hit_hull: float = 1.0
var _ride_moved: float = 0.0
var _ride_slip: float = 0.0
var _spin_in_air: float = 0.0
var _spin_in_vacuum: float = 0.0
var _peak_rebound: float = 0.0
var _peak_spin: float = 0.0
var _touched_down: bool = false
var _impact_speed: float = 0.0
var _muzzle_point: Vector2 = Vector2.ZERO
var _target_point: Vector2 = Vector2.ZERO
var _rounds_fired: int = 0
var _target_was_solid: bool = false
var _round_container: Node = null
var _failures: int = 0


func _initialize() -> void:
	for action: String in ["thrust_forward", "thrust_reverse", "rotate_left",
			"rotate_right", "strafe_left", "strafe_right", "kill_rotation", "brake"]:
		_expect(InputMap.has_action(action), "input action %s is defined" % action)
	_begin_phase()


func _physics_process(delta: float) -> bool:
	if _phase == Phase.DONE:
		return _finish()

	_ticks += 1
	_elapsed += delta
	if _phase == Phase.ORBIT:
		var radius: float = _ship.global_position.distance_to(_planet.global_position)
		_orbit_min = minf(_orbit_min, radius)
		_orbit_max = maxf(_orbit_max, radius)
	elif _phase == Phase.ORBIT_LOCK:
		if _ship.flight_mode == Ship.FlightMode.ORBIT_LOCK:
			_lock_engaged = true
			var locked_radius: float = _ship.global_position.distance_to(_planet.global_position)
			_lock_radius_min = minf(_lock_radius_min, locked_radius)
			_lock_radius_max = maxf(_lock_radius_max, locked_radius)
		elif _lock_engaged:
			_lock_released = true
		if _ticks == LOCK_THRUST_AT_TICK:
			_ship.commands[ShipControl.Command.FORWARD] = 1.0
	elif _phase == Phase.ROTATE_CW or _phase == Phase.ROTATE_CCW or _phase == Phase.ROTATE_DAMAGED:
		_peak_drift = maxf(_peak_drift, _ship.linear_velocity.length())
	elif _phase == Phase.LANDED_RIDE:
		if _ship.flight_mode == Ship.FlightMode.LANDED and _ride_start_world == Vector2.ZERO:
			# Forced rather than taken from the seed, and only once the ship is
			# down, so the check means the same thing on every planet.
			_planet.spin_rate = TEST_SPIN
			_ride_start_world = _ship.global_position
			_ride_start_polar = (
				_ship.global_position - _planet.global_position
			).angle() - _planet.global_rotation
		if _ticks == RIDE_TICKS - 20:
			_ride_moved = _ship.global_position.distance_to(_ride_start_world)
			_ride_slip = absf(angle_difference(
				(_ship.global_position - _planet.global_position).angle()
					- _planet.global_rotation,
				_ride_start_polar,
			))
			_ship.commands[ShipControl.Command.FORWARD] = 1.0
		if _ticks > RIDE_TICKS - 20 and _ship.flight_mode == Ship.FlightMode.PHYSICAL:
			_took_off = true
	elif _phase == Phase.DEATH:
		if _death_reported and _respawn_radius == 0.0:
			# The world is not in this scene, so the test stands in for it and
			# does what World._on_ship_destroyed would: put the ship back.
			var radius: float = _planet.surface_radius * 2.0
			_ship.respawn(
				_planet.global_position + Vector2.UP * radius,
				Vector2.RIGHT * _planet.circular_orbit_speed(radius),
			)
			_respawn_radius = _ship.global_position.distance_to(_planet.global_position)
	elif _phase == Phase.KILL_ROTATION:
		if _kill_ticks < 0 and absf(_ship.angular_velocity) < 0.001:
			_kill_ticks = _ticks
	elif _phase == Phase.BRAKE:
		_peak_turn_during_brake = maxf(_peak_turn_during_brake, absf(_ship.angular_velocity))
	elif _phase == Phase.BRAKE_SIDEWAYS or _phase == Phase.BRAKE_DIAGONAL:
		_peak_speed = maxf(_peak_speed, _ship.linear_velocity.length())
	elif _phase == Phase.HULL_HEAT:
		_peak_heat = maxf(_peak_heat, _ship.hull_heat)
	elif _phase == Phase.LANDING:
		_landing_deepest = maxf(_landing_deepest, _deepest_hull_penetration())
		var up: Vector2 = (_ship.global_position - _planet.global_position).normalized()
		if not _touched_down:
			if _ship.get_terrain_contacts() > 0:
				_touched_down = true
			else:
				# Sampled before contact: by the frame contact is reported,
				# _integrate_forces has already cancelled the closing speed.
				_impact_speed = -_ship.linear_velocity.dot(up)
		else:
			_peak_rebound = maxf(_peak_rebound, _ship.linear_velocity.dot(up))
			_peak_spin = maxf(_peak_spin, absf(_ship.angular_velocity))

	if _ticks < _phase_ticks():
		return false

	_evaluate_phase()
	_clear_phase()
	_phase += 1
	if _phase == Phase.DONE:
		return _finish()
	_begin_phase()
	return false


# --- Field checks, no physics needed ---

func _check_gravity_field(planet: Planet) -> void:
	var centre: Vector2 = planet.global_position
	var radius: float = planet.surface_radius

	var at_surface: float = planet.gravity_at(centre + Vector2.UP * radius).length()
	_expect(
		is_equal_approx(at_surface, planet.surface_gravity),
		"gravity at the surface is %.2f px/s2" % at_surface,
	)

	# Inverse square: twice the radius, a quarter of the pull.
	var at_double: float = planet.gravity_at(centre + Vector2.UP * radius * 2.0).length()
	_expect(
		absf(at_double - planet.surface_gravity * 0.25) < planet.surface_gravity * 0.01,
		"gravity at 2R is a quarter of surface (%.2f vs %.2f)" % [at_double, planet.surface_gravity * 0.25],
	)

	# Underground it must stay finite rather than blowing up towards the centre.
	var at_centre: float = planet.gravity_at(centre + Vector2.UP * radius * 0.1).length()
	_expect(at_centre <= planet.surface_gravity + 0.001, "gravity underground is capped at the surface value")

	# The well must fade out, and reach zero without a step the ship could feel.
	var influence: float = planet.influence_radius
	var just_inside: float = planet.gravity_at(centre + Vector2.UP * influence * 0.999).length()
	var outside: float = planet.gravity_at(centre + Vector2.UP * influence * 1.001).length()
	var before_fade: float = planet.gravity_at(centre + Vector2.UP * influence * 0.85).length()
	_expect(outside == 0.0, "gravity is exactly zero beyond the influence radius")
	_expect(just_inside < before_fade * 0.05, "gravity has faded to nothing at the edge (%.4f px/s2)" % just_inside)
	_expect(before_fade > 0.0, "gravity is still full strength before the fade starts")


func _check_atmosphere_shells(planet: Planet) -> void:
	var shells: Array[Node] = planet.get_node("AtmosphereShells").get_children()
	_expect(shells.size() == Planet.SHELL_PROFILE.size(), "planet builds %d drag shells" % shells.size())

	var previous_damp: float = -1.0
	var previous_priority: int = -1
	for shell_node: Node in shells:
		var shell: Area2D = shell_node as Area2D
		_expect(
			shell.linear_damp > previous_damp,
			"%s drags harder than the shell above it (%.3f)" % [shell.name, shell.linear_damp],
		)
		_expect(shell.priority > previous_priority, "%s outranks the shell above it" % shell.name)
		# Air must resist a spin, but always less than it resists a push.
		_expect(
			shell.angular_damp > 0.0 and shell.angular_damp < shell.linear_damp,
			"%s damps spin weaker than motion (%.3f vs %.3f)" % [
				shell.name, shell.angular_damp, shell.linear_damp,
			],
		)
		_expect(
			shell.angular_damp_space_override == Area2D.SPACE_OVERRIDE_COMBINE_REPLACE,
			"%s overrides angular damping explicitly" % shell.name,
		)
		previous_damp = shell.linear_damp
		previous_priority = shell.priority

	# The regression this guards: with drag near the ground strong enough, the
	# terminal velocity falls below the damage threshold and the air makes it
	# impossible to crash, which takes all the skill out of landing.
	var ground_point: Vector2 = planet.global_position + Vector2.UP * planet.surface_radius
	var terminal: float = planet.terminal_velocity_at(ground_point)
	# Created and freed rather than left to the collector: a bare Ship still
	# allocates a physics body, and leaking one makes Godot complain at exit.
	var probe: Ship = Ship.new()
	var threshold: float = probe.damage_speed_threshold
	probe.free()
	_expect(
		terminal > threshold * 1.5,
		"air alone cannot make landing safe (terminal %.0f px/s vs %.0f px/s damage threshold)" % [
			terminal, threshold,
		],
	)


func _check_terrain(planet: Planet) -> void:
	var terrain: PlanetTerrain = planet.terrain
	_expect(terrain.angular_samples > 0 and terrain.radial_samples > 0, "terrain grid is %d x %d" % [
		terrain.angular_samples, terrain.radial_samples,
	])
	_expect(
		terrain.inner_radius < planet.surface_radius and terrain.outer_radius > planet.surface_radius,
		"the stored crust straddles the nominal surface (%.0f .. %.0f, surface %.0f)" % [
			terrain.inner_radius, terrain.outer_radius, planet.surface_radius,
		],
	)

	var centre: Vector2 = planet.global_position
	var angle: float = -PI * 0.5
	var direction: Vector2 = Vector2.from_angle(angle)
	_expect(planet.is_solid_at(centre), "the core is solid")
	_expect(
		not planet.is_solid_at(centre + direction * terrain.outer_radius * 1.01),
		"there is no rock above the terrain ceiling",
	)

	var ground: float = _find_ground(planet, angle)
	_expect(ground > terrain.inner_radius, "a ground surface exists at the test angle (%.0f px)" % ground)

	# Just below the surface must be rock, just above must be sky.
	_expect(planet.is_solid_at(centre + direction * (ground - 4.0)), "rock sits below the surface")
	_expect(not planet.is_solid_at(centre + direction * (ground + 4.0)), "sky sits above the surface")

	# The normal on open ground should point away from the planet.
	var probe: Vector2 = centre + direction * (ground - 2.0)
	var normal: Vector2 = planet.surface_normal_at(probe)
	_expect(normal.dot(direction) > 0.5, "the surface normal points outwards (dot %.2f)" % normal.dot(direction))

	# Carving must remove rock, and must report honestly when it hits nothing.
	var target: Vector2 = centre + direction * (ground - 6.0)
	_expect(planet.carve(target, 20.0), "carving solid ground reports a change")
	_expect(not planet.is_solid_at(target), "carved rock is gone")
	_expect(
		not planet.carve(centre + direction * terrain.outer_radius * 1.5, 20.0),
		"carving empty sky reports no change",
	)


## Marches down from the ceiling to find the first rock at an angle.
func _find_ground(planet: Planet, angle: float) -> float:
	var direction: Vector2 = Vector2.from_angle(angle)
	var radius: float = planet.terrain_ceiling()
	while radius > planet.terrain.inner_radius:
		if planet.is_solid_at(planet.global_position + direction * radius):
			return radius
		radius -= 1.0
	return planet.terrain.inner_radius


## Worst penetration across the hull right now, for the sinking check.
func _deepest_hull_penetration() -> float:
	var deepest: float = 0.0
	for hull_point: Vector2 in Ship.HULL_POINTS:
		var world_point: Vector2 = _ship.global_transform * hull_point
		if not _planet.is_solid_at(world_point):
			continue
		var normal: Vector2 = _planet.surface_normal_at(world_point)
		deepest = maxf(deepest, _planet.penetration_at(world_point, normal))
	return deepest


# --- Flight phases ---

func _phase_ticks() -> int:
	match _phase:
		Phase.FIELD, Phase.TERRAIN, Phase.CONTROL_GROUPS:
			return 1
		Phase.FORWARD_BURN:
			return FORWARD_BURN_TICKS
		Phase.KILL_ROTATION:
			return KILL_TICKS
		Phase.BRAKE, Phase.BRAKE_SIDEWAYS, Phase.BRAKE_DIAGONAL:
			return BRAKE_TICKS
		Phase.ORBIT_LOCK:
			return LOCK_TICKS
		Phase.AEROBRAKE:
			return AEROBRAKE_TICKS
		Phase.HULL_HEAT:
			return HEAT_TICKS
		Phase.SPIN_IN_AIR, Phase.SPIN_IN_VACUUM:
			return SPIN_TICKS
		Phase.LANDING:
			return LANDING_TICKS
		Phase.PLATEAU, Phase.GEAR:
			return 1
		Phase.LANDING_GOOD, Phase.LANDING_FAST, Phase.LANDING_STEEP:
			return TOUCHDOWN_TICKS
		Phase.LANDED_RIDE:
			return RIDE_TICKS
		Phase.WEAPON:
			return WEAPON_TICKS
		Phase.HULL:
			return 1
		Phase.SELF_HIT:
			return SELF_HIT_TICKS
		Phase.DEATH:
			return DEATH_TICKS
		Phase.FREE_FALL:
			return FALL_TICKS
		Phase.ORBIT:
			return ORBIT_TICKS
		_:
			return BURN_TICKS


## Only the phases that actually fly near a world get one. The control phases
## deliberately run in empty space so gravity cannot be mistaken for drift.
func _phase_needs_planet() -> bool:
	match _phase:
		Phase.HULL:
			return false
		Phase.CONTROL_GROUPS, Phase.FORWARD_BURN, Phase.ROTATE_CW, Phase.ROTATE_CCW, Phase.ROTATE_DAMAGED, Phase.KILL_ROTATION, Phase.BRAKE, Phase.BRAKE_SIDEWAYS, Phase.BRAKE_DIAGONAL, Phase.STRAFE:
			return false
		_:
			return true


func _begin_phase() -> void:
	_ticks = 0
	_elapsed = 0.0

	if _phase_needs_planet():
		_planet = _spawn_planet()
	if _phase != Phase.FIELD and _phase != Phase.TERRAIN:
		_ship = _spawn_ship()

	match _phase:
		Phase.FORWARD_BURN:
			_ship.commands[ShipControl.Command.FORWARD] = 1.0
		Phase.ROTATE_CW:
			_ship.commands[ShipControl.Command.CW] = 1.0
			_peak_drift = 0.0
		Phase.ROTATE_CCW:
			_ship.commands[ShipControl.Command.CCW] = 1.0
			_peak_drift = 0.0
		Phase.ROTATE_DAMAGED:
			# Health, not geometry: the groups are deliberately rebuilt from
			# nominal thrust, so nothing here re-balances and the asymmetry has
			# to show up in flight on its own.
			_damage_mount("NoseLeftTorque", 0.3)
			_ship.commands[ShipControl.Command.CW] = 1.0
			_peak_drift = 0.0
		Phase.KILL_ROTATION:
			_ship.angular_velocity = KILL_SPIN
			_ship.kill_rotation_command = true
			_kill_ticks = -1
		Phase.BRAKE:
			_ship.linear_velocity = Ship.FORWARD * BRAKE_SPEED
			_ship.brake_command = true
			_peak_turn_during_brake = 0.0
		Phase.BRAKE_SIDEWAYS:
			# The axis the forward-only test never touched, which is how a
			# reversed pair of strafe commands went unnoticed.
			_ship.linear_velocity = Ship.FORWARD.orthogonal() * BRAKE_SPEED
			_ship.brake_command = true
			_peak_speed = 0.0
		Phase.BRAKE_DIAGONAL:
			_ship.linear_velocity = (Ship.FORWARD + Ship.FORWARD.orthogonal()).normalized() * BRAKE_SPEED
			_ship.brake_command = true
			_peak_speed = 0.0
		Phase.STRAFE:
			_ship.commands[ShipControl.Command.STRAFE_RIGHT] = 1.0
			_peak_drift = 0.0
		Phase.FREE_FALL:
			_ship.global_position = _planet.global_position + Vector2.UP * _planet.surface_radius * 2.0
		Phase.ORBIT:
			# Well clear of the atmosphere, so drag cannot be blamed for drift.
			# Air now reaches 1.45 R at its thickest, so 1.5 R is no longer
			# outside it on every seed.
			_orbit_radius = _planet.surface_radius * 2.0
			_orbit_min = INF
			_orbit_max = 0.0
			_ship.global_position = _planet.global_position + Vector2.UP * _orbit_radius
			# v = sqrt(g * R^2 / r) is the circular orbit speed for an inverse
			# square field with g measured at the surface.
			var speed: float = sqrt(_planet.surface_gravity * pow(_planet.surface_radius, 2.0) / _orbit_radius)
			_ship.linear_velocity = Vector2.RIGHT * speed
		Phase.WEAPON:
			_ground_radius = _find_ground(_planet, -PI * 0.5)
			# Parked well above the ground, nose pointing straight down at it.
			_ship.global_position = _planet.global_position + Vector2.UP * (_ground_radius + 200.0)
			_ship.global_rotation = PI
			_ship.freeze = true
			_target_point = _planet.global_position + Vector2.UP * (_ground_radius - 4.0)
			var hardpoint: Hardpoint = _ship.hardpoints[0]
			# No spread and no inherited motion: the round must land where the
			# test says it will, not somewhere in a cone.
			hardpoint.spread_degrees = 0.0
			hardpoint.inherit_velocity = false
			_muzzle_point = hardpoint.global_position
			_target_was_solid = _planet.is_solid_at(_target_point)
			_rounds_fired = 0
			_round_container = _ship.projectile_container()
			_round_container.child_entered_tree.connect(_on_round_spawned)
			_ship.fire_command = true
		Phase.ORBIT_LOCK:
			var lock_radius: float = _planet.surface_radius * 2.0
			_ship.global_position = _planet.global_position + Vector2.UP * lock_radius
			_ship.linear_velocity = Vector2.RIGHT * _planet.circular_orbit_speed(lock_radius)
			_lock_engaged = false
			_lock_released = false
			_lock_radius_min = INF
			_lock_radius_max = 0.0
		Phase.AEROBRAKE:
			# In the thin top shell at orbital speed: the manoeuvre the shells
			# were shaped for, where drag bites slowly instead of like a wall.
			var brake_radius: float = _planet.surface_radius + _planet.atmosphere_height * 0.85
			_ship.global_position = _planet.global_position + Vector2.UP * brake_radius
			_ship.linear_velocity = Vector2.RIGHT * _planet.circular_orbit_speed(brake_radius)
			_ship.orbit_lock_enabled = false
			_entry_speed = _ship.linear_velocity.length()
		Phase.HULL_HEAT:
			# Deep and fast: the suicidal entry, where the counter should move.
			var heat_radius: float = _planet.surface_radius + _planet.atmosphere_height * 0.15
			_ship.global_position = _planet.global_position + Vector2.UP * heat_radius
			_ship.linear_velocity = Vector2.RIGHT * Ship.HEAT_REFERENCE_SPEED
			_ship.orbit_lock_enabled = false
			_peak_heat = 0.0
		Phase.PLATEAU, Phase.GEAR:
			pass
		Phase.LANDING_GOOD:
			_flat_angle = _find_angle(_planet, true, _ship.gear.track_width())
			_place_for_touchdown(_flat_angle, 0.0)
		Phase.LANDING_FAST:
			_place_for_touchdown(_find_angle(_planet, true, _ship.gear.track_width()), HARD_DESCENT)
		Phase.LANDING_STEEP:
			# Tilt rather than hunting for a cliff: whether a given seed grows
			# ground steeper than the gear tolerates is luck, but arriving at a
			# bad attitude is always available and exercises the same refusal.
			_place_for_touchdown(_find_angle(_planet, true, _ship.gear.track_width()), 0.0)
			_ship.global_rotation += _ship.gear.max_tilt * 2.5
		Phase.LANDED_RIDE:
			_place_for_touchdown(_find_angle(_planet, true, _ship.gear.track_width()), 0.0)
			_took_off = false
		Phase.HULL:
			pass
		Phase.SELF_HIT:
			# Parked and shooting straight down at the planet. The round has to
			# clear its own hull, which is the case the arming delay exists for.
			_ship.global_position = _planet.global_position + Vector2.UP * (
				_planet.terrain_ceiling() + 400.0
			)
			_ship.global_rotation = PI
			_ship.freeze = true
			_ship.orbit_lock_enabled = false
			_ship.fire_command = true
			_self_hit_hull = _ship.hull_integrity
		Phase.DEATH:
			# Driven down rather than merely dropped. A ship released from
			# height does not die: the air brakes it to its terminal 154 px/s,
			# which costs 0.38 of the hull and no more. That is the atmosphere
			# working as designed, so killing it takes arriving faster than the
			# air can prevent.
			_ship.global_position = _planet.global_position + Vector2.UP * (
				_planet.surface_radius * 1.4
			)
			_ship.linear_velocity = Vector2.DOWN * 400.0
			_ship.orbit_lock_enabled = false
			_death_reported = false
			_death_hull = -1.0
			_respawn_radius = 0.0
			_ship.destroyed.connect(_on_ship_destroyed)
		Phase.SPIN_IN_AIR:
			# Above the tallest possible mountain but well inside the air, so
			# the only thing that can slow the spin is drag.
			_ship.global_position = _planet.global_position + Vector2.UP * (_planet.terrain_ceiling() + 60.0)
			_ship.angular_velocity = SPIN_START
		Phase.SPIN_IN_VACUUM:
			# Outside the atmosphere but still inside the gravity well, so the
			# two phases differ in air and nothing else.
			_ship.global_position = _planet.global_position + Vector2.UP * (_planet.surface_radius * 2.5)
			_ship.angular_velocity = SPIN_START
		Phase.LANDING:
			_ground_radius = _find_ground(_planet, -PI * 0.5)
			_ship.global_position = _planet.global_position + Vector2.UP * (_ground_radius + DROP_HEIGHT)
			_ship.linear_velocity = Vector2.ZERO
			# Tilted on purpose: a level drop hits every hull point at once and
			# would pass even with a purely linear response. One corner first is
			# what proves the ship pivots.
			_ship.global_rotation = LANDING_TILT
			_landing_deepest = 0.0
			_peak_rebound = 0.0
			_peak_spin = 0.0
			_touched_down = false
			_impact_speed = 0.0


func _on_round_spawned(node: Node) -> void:
	if node is Projectile:
		_rounds_fired += 1


func _evaluate_phase() -> void:
	match _phase:
		Phase.FIELD:
			_check_gravity_field(_planet)
			_check_atmosphere_shells(_planet)
		Phase.TERRAIN:
			_check_terrain(_planet)
		Phase.CONTROL_GROUPS:
			_check_control_groups()
		Phase.FORWARD_BURN:
			# The nose points up, so thrust shows as negative Y velocity. The
			# main drive spools, so the ramp costs half the spool time.
			var thrust: float = _mount_thrust("MainDrive")
			var spool: float = _mount_spool("MainDrive")
			var expected: float = (thrust / _ship.mass) * (_elapsed - spool * 0.5)
			_expect(
				absf(-_ship.linear_velocity.y - expected) < expected * 0.05,
				"the main drive reaches %.1f px/s along the nose after %.1f s (got %.1f)" % [
					expected, _elapsed, -_ship.linear_velocity.y,
				],
			)
			_expect(absf(_ship.linear_velocity.x) < 0.01, "forward thrust does not push sideways")
			_expect(absf(_ship.angular_velocity) < 0.001, "forward thrust does not spin the ship")
		Phase.ROTATE_CW:
			_clean_turn_spin = _ship.angular_velocity
			_expect(_clean_turn_spin > 0.0, "CW spins clockwise (%.3f rad/s)" % _clean_turn_spin)
			# The acceptance criterion: an intact rotation couple is two equal
			# and opposite forces, so it must add no linear speed whatsoever.
			_expect(
				_peak_drift < 0.01,
				"an intact CW couple adds no linear drift (peak %.4f px/s)" % _peak_drift,
			)
		Phase.ROTATE_CCW:
			_expect(_ship.angular_velocity < 0.0, "CCW spins counter-clockwise (%.3f rad/s)" % _ship.angular_velocity)
			_expect(
				_peak_drift < 0.01,
				"an intact CCW couple adds no linear drift (peak %.4f px/s)" % _peak_drift,
			)
		Phase.ROTATE_DAMAGED:
			_damaged_turn_spin = _ship.angular_velocity
			_expect(
				_damaged_turn_spin > 0.0 and _damaged_turn_spin < _clean_turn_spin * 0.95,
				"a damaged couple turns weaker (%.3f vs %.3f rad/s)" % [
					_damaged_turn_spin, _clean_turn_spin,
				],
			)
			_expect(
				_peak_drift > 1.0,
				"a damaged couple no longer cancels, so the ship slides (%.2f px/s)" % _peak_drift,
			)
		Phase.KILL_ROTATION:
			var seconds: float = float(_kill_ticks) / float(Engine.physics_ticks_per_second)
			_expect(
				_kill_ticks >= 0 and seconds < 1.0,
				"kill rotation stops %.1f rad/s in %.2f s" % [KILL_SPIN, seconds],
			)
			_expect(
				absf(_ship.angular_velocity) < 0.001,
				"the spin is fully dead afterwards (%.4f rad/s)" % _ship.angular_velocity,
			)
		Phase.BRAKE_SIDEWAYS, Phase.BRAKE_DIAGONAL:
			var label: String = "sideways" if _phase == Phase.BRAKE_SIDEWAYS else "diagonal"
			_expect(
				_ship.linear_velocity.length() < 1.0,
				"brake stops a %s %.0f px/s run (%.2f px/s left)" % [
					label, BRAKE_SPEED, _ship.linear_velocity.length(),
				],
			)
			# The symptom of a reversed command: the brake accelerates instead.
			_expect(
				_peak_speed <= BRAKE_SPEED + 1.0,
				"braking never speeds the ship up (peaked at %.1f px/s from %.0f)" % [
					_peak_speed, BRAKE_SPEED,
				],
			)
		Phase.BRAKE:
			_expect(
				_ship.linear_velocity.length() < 1.0,
				"brake stops a %.0f px/s run (%.2f px/s left after %.1f s)" % [
					BRAKE_SPEED, _ship.linear_velocity.length(), _elapsed,
				],
			)
			_expect(
				_peak_turn_during_brake < 0.05,
				"brake does not touch rotation (peak %.4f rad/s)" % _peak_turn_during_brake,
			)
		Phase.STRAFE:
			var sideways: float = _ship.linear_velocity.rotated(-_ship.global_rotation).x
			_expect(sideways > 1.0, "strafe right moves the ship right (%.1f px/s)" % sideways)
			_expect(
				absf(_ship.angular_velocity) < 0.01,
				"strafe barely rotates the ship (%.4f rad/s)" % _ship.angular_velocity,
			)
		Phase.FREE_FALL:
			var expected_g: float = _planet.surface_gravity * 0.25
			var fall_speed: float = _ship.linear_velocity.y
			_expect(fall_speed > 0.0, "an unpowered ship falls towards the planet")
			_expect(
				absf(fall_speed - expected_g * _elapsed) < expected_g * _elapsed * 0.05,
				"free fall reaches %.2f px/s after %.2f s (got %.2f)" % [expected_g * _elapsed, _elapsed, fall_speed],
			)
			_expect(absf(_ship.linear_velocity.x) < 0.001, "free fall is straight down")
		Phase.ORBIT:
			var drift: float = maxf(
				absf(_orbit_max - _orbit_radius), absf(_orbit_radius - _orbit_min)
			) / _orbit_radius
			_expect(
				drift < 0.02,
				"circular orbit holds its radius over %.0f s (drift %.2f%%, %.0f..%.0f px)" % [
					_elapsed, drift * 100.0, _orbit_min, _orbit_max,
				],
			)
		Phase.ORBIT_LOCK:
			_expect(_lock_engaged, "a coasting circular orbit engages orbit lock")
			var held: float = _lock_radius_max - _lock_radius_min
			_expect(
				held < 0.5,
				"orbit lock holds the radius exactly (%.0f .. %.0f px)" % [_lock_radius_min, _lock_radius_max],
			)
			_expect(_lock_released, "thrust hands control back to the solver")
			_expect(
				_ship.flight_mode == Ship.FlightMode.PHYSICAL,
				"the ship ends the phase under physics again",
			)
		Phase.AEROBRAKE:
			var speed_now: float = _ship.linear_velocity.length()
			_expect(
				speed_now < _entry_speed,
				"the thin top shell brakes an orbiting ship (%.1f -> %.1f px/s in %.1f s)" % [
					_entry_speed, speed_now, _elapsed,
				],
			)
			_expect(
				speed_now > _entry_speed * 0.90,
				"the top shell brakes gently rather than like a wall (%.1f%% lost)" % [
					(1.0 - speed_now / _entry_speed) * 100.0,
				],
			)
		Phase.HULL_HEAT:
			_expect(_peak_heat > 0.0, "a fast pass through thick air heats the hull (peak %.3f)" % _peak_heat)
			_expect(
				_ship.hull_heat <= 1.0,
				"hull heat stays inside its range (%.3f)" % _ship.hull_heat,
			)
		Phase.PLATEAU:
			_check_plateaus(_planet)
			_check_weather(_planet)
		Phase.GEAR:
			_check_gear(_ship)
		Phase.LANDING_GOOD:
			_expect(_first_touchdown == "landed", "a gentle touchdown on a shelf with the legs out is a landing")
			_expect(_ship.freeze, "a landed ship is frozen rather than still being solved")
			# Height rather than speed: a frozen body reports no velocity at
			# all, so the meaningful question is where it came to rest.
			var ground: float = _planet.surface_radius_at(_ship.global_position)
			var resting: float = _ship.global_position.distance_to(_planet.global_position)
			_expect(
				resting > ground and resting < ground + 20.0,
				"the ship rests on the surface, neither sunk nor hovering (%.1f px above ground)" % [
					resting - ground,
				],
			)
		Phase.LANDING_FAST:
			# Judged on the first touchdown, not the final state: a ship waved
			# off at speed bounces, sheds it, and may land properly later.
			_expect(
				_first_touchdown == "speed",
				"arriving at %.0f px/s is refused for speed (got %s)" % [
					HARD_DESCENT, _describe_touchdown(),
				],
			)
			_expect(
				_ship.accumulated_damage > 0.0,
				"overspeed costs damage rather than simply failing (%.3f)" % _ship.accumulated_damage,
			)
		Phase.LANDING_STEEP:
			# Either refusal is correct and which one trips first is geometry:
			# a ship leaning 37 degrees puts its legs on ground at two very
			# different heights, so the footing can fail before the attitude
			# does. Pinning the test to one of them would be testing the
			# accident rather than the rule.
			_expect(
				_first_touchdown == "tilt" or _first_touchdown == "slope",
				"arriving at %.0f deg off level is refused (got %s)" % [
					rad_to_deg(_ship.gear.max_tilt * 2.5), _describe_touchdown(),
				],
			)
			_expect(
				_ship.flight_mode != Ship.FlightMode.LANDED,
				"a badly tilted arrival is left to the contact solver to tip over",
			)
		Phase.LANDED_RIDE:
			_expect(_ride_moved > 1.0, "a spinning planet carries the landed ship with it (%.1f px)" % _ride_moved)
			_expect(
				_ride_slip < 0.001,
				"the ship stays on the same patch of ground (%.5f rad of slip)" % _ride_slip,
			)
			_expect(_took_off, "thrust lifts the ship off again")
			_expect(
				not _ship.freeze and _ship.flight_mode == Ship.FlightMode.PHYSICAL,
				"lift-off hands the ship back to the solver",
			)
		Phase.HULL:
			_check_hull(_ship)
		Phase.SELF_HIT:
			_expect(
				_ship.hull_integrity == _self_hit_hull,
				"a ship is not hit by its own muzzle blast (hull %.2f)" % _ship.hull_integrity,
			)
		Phase.DEATH:
			_expect(_death_reported, "a fatal impact reports the ship destroyed")
			_expect(
				_death_hull <= 0.0,
				"the hull was empty when it died (%.3f)" % _death_hull,
			)
			_expect(
				is_equal_approx(_ship.hull_integrity, 1.0),
				"respawn restores the hull (%.2f)" % _ship.hull_integrity,
			)
			_expect(
				not _ship.freeze and _ship.flight_mode == Ship.FlightMode.PHYSICAL,
				"respawn hands the ship back to the solver",
			)
			_expect(
				_ship.hull_heat == 0.0 and _ship.accumulated_damage == 0.0,
				"respawn clears the heat and the damage log",
			)
			_expect(
				_respawn_radius > _planet.atmosphere_radius(),
				"respawn puts the ship outside the atmosphere (%.0f px)" % _respawn_radius,
			)
		Phase.SPIN_IN_AIR:
			_spin_in_air = _ship.angular_velocity
			_expect(
				_planet.altitude_at(_ship.global_position) < _planet.atmosphere_height,
				"the spinning ship is inside the atmosphere",
			)
			_expect(
				_spin_in_air < SPIN_START * 0.98,
				"air slows a spin (%.3f -> %.3f rad/s in %.1f s)" % [SPIN_START, _spin_in_air, _elapsed],
			)
		Phase.SPIN_IN_VACUUM:
			_spin_in_vacuum = _ship.angular_velocity
			_expect(
				is_equal_approx(_spin_in_vacuum, SPIN_START),
				"vacuum leaves a spin alone (%.3f rad/s)" % _spin_in_vacuum,
			)
			# The point of the whole feature: the difference is the air, and the
			# ship must still turn more freely than it decelerates.
			_expect(
				_spin_in_air < _spin_in_vacuum,
				"the same ship keeps its spin longer in vacuum than in air",
			)
		Phase.LANDING:
			var resting: float = _ship.global_position.distance_to(_planet.global_position)
			_expect(
				resting > _planet.terrain.inner_radius,
				"a dropped ship does not fall through the crust (rests at %.0f px, core at %.0f)" % [
					resting, _planet.terrain.inner_radius,
				],
			)
			_expect(
				absf(resting - _ground_radius) < 40.0,
				"a dropped ship settles on the ground it fell towards (%.0f px vs ground %.0f)" % [
					resting, _ground_radius,
				],
			)
			_expect(
				_ship.linear_velocity.length() < 20.0,
				"a landed ship comes to rest (%.1f px/s)" % _ship.linear_velocity.length(),
			)
			# The bug this replaced: an aggregated central impulse produced no
			# torque at all, so a ship landing on one corner never tipped.
			_expect(
				_peak_spin > 0.05,
				"touching down on one corner pivots the ship (peak spin %.3f rad/s)" % _peak_spin,
			)
			_expect(
				absf(_ship.angular_velocity) < 0.2,
				"the pivot settles rather than spinning on (%.3f rad/s)" % _ship.angular_velocity,
			)
			# The other half of the bug: over-correcting the overlap every tick
			# handed back more height than gravity took, so the ship hopped.
			_expect(
				_peak_rebound < maxf(_impact_speed * 0.4, 5.0),
				"the hull does not hop off the ground (rebound %.1f px/s from a %.1f px/s impact)" % [
					_peak_rebound, _impact_speed,
				],
			)
			# Which face it ends on is not the test's business: a triangle
			# dropped tilted can legitimately settle on a side, and tipping over
			# is a designed outcome (IDEAS.md section 7). It only has to stop.
			_expect(
				_ship.get_terrain_contacts() > 0,
				"the ship is still in contact with the ground at the end",
			)
			# Two different things are worth checking here, and conflating them
			# was wrong: a hard impact legitimately buries the hull for a few
			# ticks before the correction digs it out, while a settled ship must
			# sit at the slop forever. Only the second one being violated is a
			# bug, so they get separate bounds.
			var settled: float = _deepest_hull_penetration()
			_expect(
				settled <= Ship.PENETRATION_SLOP + 0.25,
				"a settled hull rests at the correction slop (%.1f px)" % settled,
			)
			var step: float = 1.0 / float(Engine.physics_ticks_per_second)
			var allowed_peak: float = maxf(_impact_speed * step * 4.0, 1.0)
			_expect(
				_landing_deepest <= allowed_peak,
				"impact overlap stays within a few ticks of travel (peak %.1f px, allowed %.1f at %.0f px/s)" % [
					_landing_deepest, allowed_peak, _impact_speed,
				],
			)
		Phase.WEAPON:
			_round_container.child_entered_tree.disconnect(_on_round_spawned)
			_expect(_target_was_solid, "the ground under the muzzle was solid before firing")
			_expect(_rounds_fired > 0, "holding the trigger spawns rounds (%d in %.1f s)" % [_rounds_fired, _elapsed])
			var expected: float = _ship.hardpoints[0].rounds_per_second * _elapsed
			_expect(
				absf(float(_rounds_fired) - expected) <= 2.0,
				"rate of fire is respected (%d rounds, expected about %.0f)" % [_rounds_fired, expected],
			)
			_expect(
				not _planet.is_solid_at(_target_point),
				"a round punched a hole through the ground it hit",
			)


## Every command must have engines behind it, and the two rotation groups have
## to be balanced couples or turning will shove the ship sideways.
func _check_control_groups() -> void:
	for command: ShipControl.Command in ShipControl.COMMAND_AXES:
		_expect(
			_ship.control.has_authority(command),
			"%s has authority (%.0f)" % [
				_ship.control.command_name(command), _ship.control.authority_of(command),
			],
		)

	for command: ShipControl.Command in [ShipControl.Command.CW, ShipControl.Command.CCW]:
		var members: Array = _ship.control.groups.get(command, [])
		_expect(members.size() >= 2, "%s is a couple, not a single engine" % _ship.control.command_name(command))
		var residual: Vector2 = Vector2.ZERO
		for member: Dictionary in members:
			var engine: EngineInstance = member["engine"]
			residual += engine.nominal_force() * float(member["weight"])
		_expect(
			residual.length() < 0.01,
			"%s leaves no net side force (%.4f N)" % [
				_ship.control.command_name(command), residual.length(),
			],
		)


func _mount_thrust(mount_name: String) -> float:
	for engine: EngineInstance in _ship.engines:
		if engine.mount.name == mount_name:
			return engine.data.max_thrust
	return 0.0


func _mount_spool(mount_name: String) -> float:
	for engine: EngineInstance in _ship.engines:
		if engine.mount.name == mount_name:
			return engine.data.spool_time
	return 0.0


func _damage_mount(mount_name: String, health: float) -> void:
	for engine: EngineInstance in _ship.engines:
		if engine.mount.name == mount_name:
			engine.health = health
			return


## Angle of the flattest or the steepest ground on the planet.
##
## Scanned rather than read from the generator, so the check measures the
## terrain that actually exists after the plateau pass rather than what the
## pass intended.
func _find_angle(planet: Planet, flattest: bool, span: float = 24.0) -> float:
	var best_angle: float = 0.0
	var best_slope: float = INF if flattest else -INF
	var samples: int = 1440
	for i: int in range(samples):
		var angle: float = TAU * float(i) / float(samples)
		# Three samples across the track, not two: a two point measure reads
		# level astride a ridge, and searching for the minimum of a measure
		# that can be fooled finds precisely the places that fool it.
		var slope: float = maxf(
			absf(_span_slope(planet, angle, span * 0.5, 0.0)),
			absf(_span_slope(planet, angle, 0.0, span * 0.5)),
		)
		if flattest == (slope < best_slope):
			best_slope = slope
			best_angle = angle
	return best_angle


## Slope between two offsets along the surface, in radians.
func _span_slope(planet: Planet, angle: float, back: float, forward: float) -> float:
	var radius: float = planet.surface_radius
	var behind: float = planet.terrain.surface_radius_at(angle - planet.global_rotation - back / radius)
	var ahead: float = planet.terrain.surface_radius_at(angle - planet.global_rotation + forward / radius)
	return atan2(ahead - behind, back + forward)


func _on_ship_destroyed(_at: Vector2, _velocity: Vector2) -> void:
	_death_reported = true
	_death_hull = _ship.hull_integrity


func _on_landing_rejected(reason: String) -> void:
	if _first_touchdown.is_empty():
		_first_touchdown = reason


func _on_landed(_planet_landed_on: Planet) -> void:
	if _first_touchdown.is_empty():
		_first_touchdown = "landed"


## Drops the ship just above the ground at an angle, upright, legs already out.
func _place_for_touchdown(angle: float, descent: float) -> void:
	var direction: Vector2 = Vector2.from_angle(angle)
	var ground: float = _planet.terrain.surface_radius_at(angle - _planet.global_rotation)
	_ship.global_position = _planet.global_position + direction * (ground + TOUCHDOWN_HEIGHT)
	# Upright means the ship's nose points away from the planet.
	_ship.global_rotation = direction.angle() + PI * 0.5
	_ship.linear_velocity = -direction * descent
	_ship.angular_velocity = 0.0
	_ship.orbit_lock_enabled = false
	_planet.spin_rate = 0.0
	if _ship.gear != null:
		# Skipping the deploy timer: how long the legs take is the gear check's
		# business, not the landing check's.
		_ship.gear.set_deployed(true)
		_ship.gear.extension = 1.0
	_first_touchdown = ""
	_ship.landing_rejected.connect(_on_landing_rejected)
	_ship.landed.connect(_on_landed)


## Clouds are weather, not scenery painted on the rock: whatever the seed rolls,
## the deck has to end up above every mountain and below the top of the air.
##
## Both bounds are property checks rather than numbers, because the cloud
## parameters are rolled per planet and the terrain ceiling moves with them.
func _check_weather(planet: Planet) -> void:
	# Sweep seeds rather than trusting the one planet this run happens to have:
	# a fifth of all planets are airless and would pass the bounds vacuously.
	var probe: Planet = planet
	var airless: int = 0
	var cloudy: int = 0
	for planet_seed: int in range(40):
		probe.generate(planet_seed)
		if probe.atmosphere_height <= 0.0:
			airless += 1
			_expect_quiet(not probe.has_clouds, "airless planet %d has no weather" % planet_seed)
			continue
		if not probe.has_clouds:
			continue
		cloudy += 1
		_expect_quiet(
			probe.cloud_base_radius() > probe.terrain.outer_radius,
			"planet %d keeps its clouds above the rock (%.0f vs ceiling %.0f)" % [
				planet_seed, probe.cloud_base_radius(), probe.terrain.outer_radius,
			],
		)
		_expect_quiet(
			probe.cloud_ceiling() > probe.cloud_base_radius(),
			"planet %d has a deck with thickness" % planet_seed,
		)
		_expect_quiet(
			probe.cloud_ceiling() <= probe.atmosphere_radius() + 0.001,
			"planet %d keeps its clouds inside the air (%.0f vs top %.0f)" % [
				planet_seed, probe.cloud_ceiling(), probe.atmosphere_radius(),
			],
		)
	_expect(cloudy > 0, "seeds roll cloudy planets (%d of 40, %d airless)" % [cloudy, airless])
	_expect(airless > 0, "seeds still roll airless rocks (%d of 40)" % airless)
	probe.generate(planet.planet_seed)


## Plateaus have to be real ground a stock ship can stand on, not just a number
## in the generator.
func _check_plateaus(planet: Planet) -> void:
	_expect(planet.plateau_count > 0, "the planet levels %d landing shelves" % planet.plateau_count)

	var probe: Ship = _spawn_ship()
	var tolerance: float = probe.gear.max_slope
	var flat_enough: int = 0
	var samples: int = 720
	for i: int in range(samples):
		var angle: float = TAU * float(i) / float(samples)
		var point: Vector2 = planet.global_position + Vector2.from_angle(angle) * planet.surface_radius
		if absf(planet.slope_at(point, 24.0)) < tolerance:
			flat_enough += 1
	probe.free()

	_expect(
		flat_enough > 0,
		"somewhere on the planet is landable: %d of %d sampled angles are under %.0f deg" % [
			flat_enough, samples, rad_to_deg(tolerance),
		],
	)


func _describe_touchdown() -> String:
	return _first_touchdown if not _first_touchdown.is_empty() else "no touchdown at all"


## The hull is one number every damage source shares, so the door is what gets
## tested rather than each way of knocking on it.
func _check_hull(ship: Ship) -> void:
	_expect(is_equal_approx(ship.hull_integrity, 1.0), "a fresh hull is intact")
	_expect(not ship.is_destroyed(), "a fresh ship is not destroyed")

	ship.take_damage(0.3, "test")
	_expect(
		is_equal_approx(ship.hull_integrity, 0.7),
		"damage comes off the hull (%.2f)" % ship.hull_integrity,
	)
	_expect(
		is_equal_approx(ship.accumulated_damage, 0.3),
		"damage is logged as well as subtracted",
	)

	var deaths: Array[bool] = []
	ship.destroyed.connect(func(_at: Vector2, _v: Vector2) -> void: deaths.append(true))
	ship.take_damage(0.5, "test")
	_expect(not ship.is_destroyed(), "a hull with something left survives")
	_expect(deaths.is_empty(), "surviving does not announce a death")

	ship.take_damage(0.5, "test")
	_expect(ship.is_destroyed(), "running the hull out destroys the ship")
	_expect(deaths.size() == 1, "death is announced exactly once")

	# Damage after death must not fire it again, or a wreck being shot at would
	# respawn once per hit.
	ship.take_damage(0.5, "test")
	_expect(deaths.size() == 1, "a wreck cannot die twice")


func _check_gear(ship: Ship) -> void:
	var landing_gear: LandingGear = ship.gear
	_expect(landing_gear != null, "the stock hull carries landing gear")
	if landing_gear == null:
		return

	_expect(landing_gear.legs.size() >= 2, "the gear has %d legs" % landing_gear.legs.size())
	_expect(landing_gear.is_stowed(), "the legs start stowed")
	_expect(
		ship.contact_points().size() == Ship.HULL_POINTS.size(),
		"stowed legs are not contact points",
	)

	# Half-open gear must not count, or the deploy timer would be decorative.
	landing_gear.set_deployed(true)
	landing_gear.advance(landing_gear.deploy_time * 0.5)
	_expect(not landing_gear.is_deployed(), "half-extended gear does not count as down")
	_expect(
		ship.contact_points().size() == Ship.HULL_POINTS.size(),
		"half-extended legs are not contact points either",
	)

	landing_gear.advance(landing_gear.deploy_time)
	_expect(landing_gear.is_deployed(), "the legs reach full extension")
	_expect(
		ship.contact_points().size() == Ship.HULL_POINTS.size() + landing_gear.legs.size(),
		"deployed legs join the contact set",
	)

# --- Plumbing ---

func _spawn_ship() -> Ship:
	var scene: PackedScene = load(SHIP_SCENE) as PackedScene
	var ship: Ship = scene.instantiate() as Ship
	ship.use_player_input = false
	root.add_child(ship)
	# Quiet rebuild: the group dump is worth printing once at startup, not
	# twenty times inside a test run.
	ship.rebuild_control_groups(false)
	return ship


func _spawn_planet() -> Planet:
	var scene: PackedScene = load(PLANET_SCENE) as PackedScene
	var planet: Planet = scene.instantiate() as Planet
	planet.planet_seed = TEST_SEED
	root.add_child(planet)
	return planet


func _clear_phase() -> void:
	if _ship != null:
		_ship.free()
		_ship = null
	if _planet != null:
		_planet.free()
		_planet = null


func _finish() -> bool:
	if _failures == 0:
		print("smoke test: OK")
		quit(0)
	else:
		print("smoke test: %d check(s) FAILED" % _failures)
		quit(1)
	return true


## Like _expect, but silent when it passes. For sweeps over many seeds, where
## one line per seed would bury every other check in the run.
func _expect_quiet(condition: bool, description: String) -> void:
	if not condition:
		print("  FAIL %s" % description)
		_failures += 1


func _expect(condition: bool, description: String) -> void:
	if condition:
		print("  ok   %s" % description)
	else:
		print("  FAIL %s" % description)
		_failures += 1
