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
const CRATE_SCENE: String = "res://scenes/loot_crate.tscn"

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

## Long enough for a hull dropped on a turning planet to settle and then be
## watched for a while. Friction needs a moment to bring it up to the speed of
## the ground, so the slip is measured over the second half only.
const GROUND_RIDE_TICKS: int = 240
const GROUND_RIDE_SETTLE: int = 120

## Long enough for a round to cross the gap below and dig in.
const WEAPON_TICKS: int = 60

## Long enough for a round fired straight down to arm and come back.
const SELF_HIT_TICKS: int = 120

## Half an orbital period at the elliptical phase's radius, plus margin, so the
## ship actually reaches its apoapsis instead of being trusted to be on the way.
## Measured rather than estimated: the semi-major axis comes out at 1926 px,
## giving T = 2*PI*sqrt(a^3/mu) = 92 s, so the climb takes 2772 ticks.
const ELLIPSE_TICKS: int = 2950

## Long enough to fall from orbit and hit the ground hard.
const DEATH_TICKS: int = 900

## FIELD comes first and only inspects a planet. It has to run on the physics
## loop like everything else: nodes added from _initialize() are not in the
## tree yet, so a planet queried there would still hold its default parameters
## instead of the ones _ready() rolls from the seed.
enum Phase { FIELD, TERRAIN, CONTROL_GROUPS, FORWARD_BURN, ROTATE_CW, ROTATE_CCW,
	ROTATE_DAMAGED, KILL_ROTATION, BRAKE, BRAKE_SIDEWAYS, BRAKE_DIAGONAL, STRAFE, FREE_FALL, ORBIT,
	ELLIPSE, AEROBRAKE, HULL_HEAT, SPIN_IN_AIR, SPIN_IN_VACUUM, LANDING,
	PLATEAU, GEAR, LANDING_GOOD, LANDING_FAST, LANDING_STEEP, LANDED_RIDE, GROUND_RIDE,
	WEAPON, HULL, SELF_HIT, DEATH, DONE }

var _phase: int = Phase.FIELD
var _ticks: int = 0
var _elapsed: float = 0.0
var _ship: Ship = null
var _planet: Planet = null
var _orbit_radius: float = 0.0
var _orbit_min: float = INF
var _orbit_max: float = 0.0

## What the elements predicted at launch, to be compared with where the ship
## actually went once the integrator has had half an orbit to disagree.
var _predicted_extremes: Vector2 = Vector2.ZERO

## Whether the trajectory reading ever disagreed with what the ship was doing.
var _orbit_reading_held: bool = true
var _aerobrake_read_decaying: bool = false
var _ground_radius: float = 0.0
var _landing_deepest: float = 0.0
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
## Where the resting hull sat in the planet's own frame once it had settled,
## and how far it drifted from there afterwards.
var _ground_start_polar: float = 0.0
var _ground_slip: float = 0.0
var _ground_contacts: int = 0

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
	if _phase == Phase.ORBIT or _phase == Phase.ELLIPSE:
		var radius: float = _ship.global_position.distance_to(_planet.global_position)
		_orbit_min = minf(_orbit_min, radius)
		_orbit_max = maxf(_orbit_max, radius)
		if _planet.orbit_state(
			_ship.global_position, _ship.linear_velocity
		) != Planet.OrbitState.ORBIT:
			_orbit_reading_held = false
	elif _phase == Phase.AEROBRAKE:
		if _planet.orbit_state(
			_ship.global_position, _ship.linear_velocity
		) == Planet.OrbitState.DECAYING:
			_aerobrake_read_decaying = true
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
	elif _phase == Phase.GROUND_RIDE:
		if _ticks == GROUND_RIDE_SETTLE:
			_ground_start_polar = _polar_angle()
		if _ticks > GROUND_RIDE_SETTLE:
			_ground_slip = absf(angle_difference(_polar_angle(), _ground_start_polar))
			_ground_contacts = maxi(_ground_contacts, _ship.get_terrain_contacts())
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
		Phase.GROUND_RIDE:
			return GROUND_RIDE_TICKS
		Phase.ORBIT:
			return ORBIT_TICKS
		Phase.ELLIPSE:
			return ELLIPSE_TICKS
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
			_orbit_reading_held = true
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
			# test says it will, not somewhere in a cone. Done by fitting a
			# copy rather than by poking the mount, because the numbers belong
			# to the weapon now -- which is also the swap the loot flow uses.
			var aimed: WeaponData = hardpoint.weapon.duplicate() as WeaponData
			aimed.spread_degrees = 0.0
			aimed.inherit_velocity = false
			hardpoint.fit(aimed)
			_muzzle_point = hardpoint.global_position
			_target_was_solid = _planet.is_solid_at(_target_point)
			_rounds_fired = 0
			_round_container = _ship.projectile_container()
			_round_container.child_entered_tree.connect(_on_round_spawned)
			_ship.fire_command = true
		Phase.GROUND_RIDE:
			# Dropped onto a turning planet with the LEGS UP, so the landing
			# check refuses it and the contact solver is what holds it there.
			# That is the path a ship is on whenever it is sitting on rock
			# without having landed properly, and it was the one that slid.
			_planet.spin_rate = TEST_SPIN
			_ground_start_polar = 0.0
			_ground_slip = 0.0
			_ground_contacts = 0
			if _ship.gear != null:
				_ship.gear.set_deployed(false)
				_ship.gear.extension = 0.0
			_ground_radius = _find_ground(_planet, -PI * 0.5)
			_ship.global_position = _planet.global_position + Vector2.UP * (_ground_radius + 12.0)
			_ship.global_rotation = 0.0
			_ship.linear_velocity = Vector2.ZERO
			_ship.angular_velocity = 0.0
		Phase.ELLIPSE:
			# Just above the air, thrown tangentially harder than a circle
			# needs: the launch point is then exactly the periapsis, which is
			# what makes the prediction checkable without a second measurement.
			_orbit_radius = _planet.surface_radius * 1.4
			_orbit_min = INF
			_orbit_max = 0.0
			_orbit_reading_held = true
			_ship.global_position = _planet.global_position + Vector2.UP * _orbit_radius
			_ship.linear_velocity = (
				Vector2.RIGHT * _planet.circular_orbit_speed(_orbit_radius) * 1.12
			)
			_predicted_extremes = _planet.orbit_extremes(
				_ship.global_position, _ship.linear_velocity
			)
		Phase.AEROBRAKE:
			# In the thin top shell at orbital speed: the manoeuvre the shells
			# were shaped for, where drag bites slowly instead of like a wall.
			var brake_radius: float = _planet.surface_radius + _planet.atmosphere_height * 0.85
			_ship.global_position = _planet.global_position + Vector2.UP * brake_radius
			_ship.linear_velocity = Vector2.RIGHT * _planet.circular_orbit_speed(brake_radius)
			_entry_speed = _ship.linear_velocity.length()
		Phase.HULL_HEAT:
			# Deep and fast: the suicidal entry, where the counter should move.
			var heat_radius: float = _planet.surface_radius + _planet.atmosphere_height * 0.15
			_ship.global_position = _planet.global_position + Vector2.UP * heat_radius
			_ship.linear_velocity = Vector2.RIGHT * Ship.HEAT_REFERENCE_SPEED
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
			_expect(
				_orbit_reading_held,
				"the whole coast reads as ORBIT, tick by tick",
			)
		Phase.ELLIPSE:
			# The whole point of the elements is that they predict where the
			# ship WILL be, so the test flies there and looks. A sign error or
			# a wrong mu passes every self-consistent check and fails this one.
			_expect(
				absf(_orbit_min - _predicted_extremes.x) < _orbit_radius * 0.01,
				"the launch point is the predicted periapsis (%.0f vs %.0f px)" % [
					_orbit_min, _predicted_extremes.x,
				],
			)
			_expect(
				absf(_orbit_max - _predicted_extremes.y) < _orbit_radius * 0.01,
				"the ship coasts to the predicted apoapsis (%.0f vs %.0f px)" % [
					_orbit_max, _predicted_extremes.y,
				],
			)
			_expect(
				_orbit_reading_held,
				"an eccentric orbit reads as ORBIT too, the whole way round",
			)
			_expect(
				_predicted_extremes.y > _orbit_radius * 1.1,
				"the test orbit is actually eccentric (%.0f .. %.0f px)" % [
					_predicted_extremes.x, _predicted_extremes.y,
				],
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
			# The one case where the reading has to change by itself: drag eats
			# the periapsis and the orbit stops being one.
			_expect(
				_aerobrake_read_decaying,
				"aerobraking is read as a decaying orbit while it happens",
			)
		Phase.HULL_HEAT:
			_expect(_peak_heat > 0.0, "a fast pass through thick air heats the hull (peak %.3f)" % _peak_heat)
			_expect(
				_ship.hull_heat <= 1.0,
				"hull heat stays inside its range (%.3f)" % _ship.hull_heat,
			)
		Phase.PLATEAU:
			_check_weapons()
			_check_loot()
			_check_hold()
			_check_bulk()
			_check_configuration_report()
			_check_cargo()
			_check_editor()
			_check_pause_gate()
			_check_scanner(_planet)
			_check_plateaus(_planet)
			_check_landing_sites(_planet)
			_check_determinism(_planet)
			_check_elements(_planet)
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
		Phase.GROUND_RIDE:
			_expect(_ground_contacts > 0, "the hull really is resting on the rock")
			# What the ground did underneath it while it was watched. Sliding
			# instead of being carried shows up as the hull keeping its world
			# position while this angle runs away.
			var turned: float = TEST_SPIN * float(GROUND_RIDE_TICKS - GROUND_RIDE_SETTLE) / 60.0
			_expect(
				_ground_slip < turned * 0.25,
				"a hull resting on a turning planet is carried, not slid (%.4f rad of slip, ground turned %.4f)" % [
					_ground_slip, turned,
				],
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
			# Measured against the GROUND, not the world. A hull at rest on a
			# turning planet is moving in world coordinates, and it should be:
			# checking the world speed would pass a ship that is sliding and
			# fail one that is correctly being carried along.
			var ground_speed: float = (
				_ship.linear_velocity - _planet.surface_velocity_at(_ship.global_position)
			).length()
			_expect(
				ground_speed < 5.0,
				"a landed ship comes to rest on the ground (%.1f px/s relative, %.1f absolute)" % [
					ground_speed, _ship.linear_velocity.length(),
				],
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
			var expected: float = _ship.hardpoints[0].weapon.rounds_per_second * _elapsed
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
			probe.cloud_count() > 0,
			"planet %d with weather actually has clouds in the sky" % planet_seed,
		)
		_expect_quiet(
			probe.cloud_ceiling() <= probe.atmosphere_radius() + 0.001,
			"planet %d keeps its clouds inside the air (%.0f vs top %.0f)" % [
				planet_seed, probe.cloud_ceiling(), probe.atmosphere_radius(),
			],
		)
	_expect(cloudy > 0, "seeds roll cloudy planets (%d of 40, %d airless)" % [cloudy, airless])
	_expect(airless > 0, "seeds still roll airless rocks (%d of 40)" % airless)

	# Every archetype has to actually turn up, or one of them is a dead branch
	# nobody will ever see and the weighting is wrong.
	var seen: Dictionary = {}
	for planet_seed: int in range(120):
		probe.generate(planet_seed)
		if probe.has_clouds:
			seen[probe.cloud_type] = int(seen.get(probe.cloud_type, 0)) + 1
	for type_name: String in Planet.CloudType.keys():
		var type_value: int = Planet.CloudType[type_name]
		_expect(
			seen.has(type_value),
			"seeds roll %s skies (%d in 120)" % [type_name, int(seen.get(type_value, 0))],
		)

	probe.generate(planet.planet_seed)


## The shelves the generator reports have to be the shelves it levelled.
##
## The configurator teleports onto these angles, so a stale or empty list puts
## the ship inside a mountain. Checked against the slope the gear will judge.
func _check_landing_sites(planet: Planet) -> void:
	var sites: PackedFloat32Array = planet.landing_sites()
	_expect(
		sites.size() == planet.plateau_count,
		"the planet reports every shelf it levelled (%d of %d)" % [sites.size(), planet.plateau_count],
	)

	var probe: Ship = _spawn_ship()
	var tolerance: float = probe.gear.max_slope
	var steepest: float = 0.0
	for angle: float in sites:
		var point: Vector2 = planet.polar_to_world(angle, planet.surface_radius)
		steepest = maxf(steepest, absf(planet.slope_at(point, 24.0)))
	probe.queue_free()
	_expect(
		steepest < tolerance,
		"every reported shelf is flat enough to stand on (worst %.1f deg, gear takes %.1f)" % [
			rad_to_deg(steepest), rad_to_deg(tolerance),
		],
	)


## Rolling and building are separate calls now, so the pair still has to add up
## to what one generate() used to do.
func _check_determinism(planet: Planet) -> void:
	planet.roll_parameters(4242)
	var radius: float = planet.surface_radius
	var gravity: float = planet.surface_gravity
	var air: float = planet.atmosphere_height
	planet.roll_parameters(4242)
	_expect(
		is_equal_approx(planet.surface_radius, radius)
			and is_equal_approx(planet.surface_gravity, gravity)
			and is_equal_approx(planet.atmosphere_height, air),
		"the same seed rolls the same planet twice",
	)
	planet.generate(planet.planet_seed)


## Where the ship sits in the planet's own frame, which is the only place a
## slip against the ground can be seen: in world coordinates a carried ship and
## a sliding one both move.
func _polar_angle() -> float:
	return (_ship.global_position - _planet.global_position).angle() - _planet.global_rotation


## A weapon is loot: its numbers live in the Resource, and fitting a different
## one has to change what the gun does without touching the mount.
func _check_weapons() -> void:
	var stock: WeaponData = load("res://resources/weapons/autocannon.tres") as WeaponData
	var siege: WeaponData = load("res://resources/weapons/siege_slug.tres") as WeaponData
	_expect(stock != null and siege != null, "both stock weapons load as resources")
	if stock == null or siege == null:
		return

	# Range rather than lifetime is the stat, so the derived lifetime has to
	# follow the speed: the same range at 900 px/s must not live as long.
	_expect(
		is_equal_approx(stock.lifetime(), stock.range_px / stock.muzzle_speed),
		"lifetime is range over speed (%.2f s for %.0f px at %.0f px/s)" % [
			stock.lifetime(), stock.range_px, stock.muzzle_speed,
		],
	)

	# The point of two weapons: they have to be different in ways a pilot
	# notices, or the loot generator has nothing to vary.
	_expect(
		siege.damage > stock.damage * 2.0 and siege.rounds_per_second < stock.rounds_per_second,
		"the siege slug trades rate of fire for damage (%.2f at %.1f/s vs %.2f at %.1f/s)" % [
			siege.damage, siege.rounds_per_second, stock.damage, stock.rounds_per_second,
		],
	)
	_expect(
		stock.damage_per_second() > siege.damage_per_second(),
		"and the autocannon still wins on sustained damage (%.2f vs %.2f per s)" % [
			stock.damage_per_second(), siege.damage_per_second(),
		],
	)
	_expect(
		stock.shots_to_kill() == 13 and siege.shots_to_kill() == 4,
		"shots to kill reads as whole rounds (%d vs %d)" % [
			stock.shots_to_kill(), siege.shots_to_kill(),
		],
	)

	var probe: Ship = _spawn_ship()
	var mount: Hardpoint = probe.hardpoints[0]
	_expect(mount.weapon != null, "the stock hull comes with a gun fitted")

	# An empty accepted-type list is a general purpose mount.
	_expect(mount.can_fit(siege), "a general purpose mount takes any weapon")
	var previous: WeaponData = mount.fit(siege)
	_expect(
		mount.weapon == siege and previous == stock,
		"fitting hands the old weapon back",
	)

	# A mount that names its types refuses everything else, which is what
	# stops a missile rack from holding an autocannon.
	mount.accepts = [WeaponData.Type.HOMING_MISSILE]
	_expect(not mount.can_fit(stock), "a mount that names its types refuses the rest")
	_expect(
		mount.fit(stock) == stock and mount.weapon == siege,
		"a refused weapon is handed straight back and changes nothing",
	)
	probe.queue_free()


## The loot generator, reached as a script because the smoke test has no
## autoloads (see _check_loot).
const LOOT_SCRIPT: GDScript = preload("res://scripts/autoload/loot_generator.gd")


## The hold is one slot and fitting is a swap: nothing found may be lost, and
## nothing may be fitted where it does not belong.
## Bulk is the one number that says how big an engine is, and it has to act
## like a size and like a mass at once. The symmetry it can break is already
## pinned by _check_control_groups(), which measures the leftover side force
## rather than the weights behind it.
## The scanner reports a direction and a distance for bodies that are off
## screen. Tested against the geometry rather than the pixels: contacts() is
## handed the world-to-screen transform, so no camera or rendered frame is
## needed and the answers are exact.
func _check_scanner(planet: Planet) -> void:
	var ship: Ship = _spawn_ship()
	var scanner: ScannerHud = ScannerHud.new()
	root.add_child(scanner)
	scanner.bind(ship)

	var view: Vector2 = Vector2(640.0, 360.0)
	var centre: Vector2 = view * 0.5
	var ring: Vector2 = centre - Vector2(scanner.ring_margin, scanner.ring_margin)

	# Straight above the planet, high enough that its centre is off the bottom
	# of the screen. The transform is the one a camera locked to the ship
	# produces: the ship at the centre, no zoom, no rotation.
	var altitude: float = 2000.0
	ship.global_position = planet.global_position - Vector2(0.0, planet.surface_radius + altitude)
	var to_screen: Transform2D = Transform2D(0.0, centre - ship.global_position)

	var found: Array[Dictionary] = scanner.contacts(to_screen, view)
	_expect(found.size() == 1, "one body in range gives one marker (got %d)" % found.size())
	if found.size() == 1:
		var contact: Dictionary = found[0]
		_expect(
			(contact["direction"] as Vector2).dot(Vector2.DOWN) > 0.99,
			"the marker points at the planet below, not somewhere else",
		)
		_expect(
			is_equal_approx((contact["at"] as Vector2).y, centre.y + ring.y),
			"and sits on the bottom of the ring (y %.1f, expected %.1f)" % [
				(contact["at"] as Vector2).y, centre.y + ring.y,
			],
		)
		_expect(
			absf(float(contact["distance"]) - altitude) < 1.0,
			"the number is the distance to the surface, not to the centre (%.0f)" % [
				contact["distance"],
			],
		)
		_expect(bool(contact["inside"]), "and the marker knows the ship is inside the well")

	# Close enough that the planet's centre is on screen: the pilot can see it,
	# so an edge marker would be pointing at nothing they need.
	ship.global_position = planet.global_position - Vector2(0.0, 100.0)
	_expect(
		scanner.contacts(Transform2D(0.0, centre - ship.global_position), view).is_empty(),
		"a body whose centre is on screen gets no edge marker",
	)

	# And past the scanner's reach there is nothing to report, however large.
	ship.global_position = planet.global_position - Vector2(
		0.0, planet.surface_radius + scanner.scan_range + 10.0,
	)
	_expect(
		scanner.contacts(Transform2D(0.0, centre - ship.global_position), view).is_empty(),
		"a body beyond the scanner's range is not reported",
	)

	# Outside the well the marker stays, dimmed: still worth steering by.
	ship.global_position = planet.global_position - Vector2(0.0, planet.influence_radius + 500.0)
	var far: Array[Dictionary] = scanner.contacts(
		Transform2D(0.0, centre - ship.global_position), view,
	)
	_expect(far.size() == 1, "a body outside its own well is still reported")
	if far.size() == 1:
		_expect(not bool(far[0]["inside"]), "but it is marked as outside the well")

	# Loot rides the same ring but answers to its own range, and is worth a
	# mark even on screen -- eight pixels of box against a whole planet.
	var crate: LootCrate = (load(CRATE_SCENE) as PackedScene).instantiate() as LootCrate
	crate.hold(WeaponData.new(), 3)
	root.add_child(crate)

	ship.global_position = Vector2(50000.0, 50000.0)
	crate.global_position = ship.global_position + Vector2(0.0, scanner.loot_range + 10.0)
	to_screen = Transform2D(0.0, centre - ship.global_position)
	_expect(
		scanner.loot_contacts(to_screen, view).is_empty(),
		"a crate past the loot range is not reported, though a planet at that range would be",
	)

	crate.global_position = ship.global_position + Vector2(0.0, 1200.0)
	var near: Array[Dictionary] = scanner.loot_contacts(
		Transform2D(0.0, centre - ship.global_position), view,
	)
	_expect(near.size() == 1, "a crate inside the loot range is reported")
	if near.size() == 1:
		_expect(bool(near[0]["on_ring"]), "off screen it goes on the ring")
		_expect(int(near[0]["rarity"]) == 3, "and carries its rarity, which is its colour")

	crate.global_position = ship.global_position + Vector2(20.0, 30.0)
	var seen: Array[Dictionary] = scanner.loot_contacts(
		Transform2D(0.0, centre - ship.global_position), view,
	)
	_expect(seen.size() == 1, "a crate on screen is still reported")
	if seen.size() == 1:
		_expect(
			not bool(seen[0]["on_ring"])
			and (seen[0]["at"] as Vector2).is_equal_approx(centre + Vector2(20.0, 30.0)),
			"and is marked where it actually is, not shoved out to the edge",
		)

	_expect(
		scanner.contacts(Transform2D(0.0, centre - ship.global_position), view).is_empty(),
		"a crate is not mistaken for a celestial body",
	)
	crate.queue_free()

	_expect(scanner.distance_text(12345.0) == "12.3k", "long distances are shortened")
	_expect(scanner.distance_text(-5.0) == "0", "and being underground does not read as negative")

	scanner.queue_free()
	ship.queue_free()


## The report is the guard a pilot has instead of a test suite: swapping a
## module can leave the ship crooked rather than merely worse, and nothing in
## flight says so. Every fault here is one this project has actually shipped
## into a working tree at least once.
## MAUX1: the cargo bay is a capacity, not a rack of slots, and what it holds
## is mass like anything else. Jettison has to produce something recoverable,
## or throwing a module overboard is tidying up rather than a decision.
func _check_cargo() -> void:
	var ship: Ship = _spawn_ship()
	var loot: Node = LOOT_SCRIPT.new()

	_expect(Ship.module_bulk(loot.weapon(11, 0)) > 0.0, "a weapon has a bulk, like an engine")
	_expect(ship.cargo_used() == 0.0, "a fresh bay is empty")
	_expect(
		is_equal_approx(ship.cargo_free(), ship.cargo_capacity),
		"and all of its capacity is free",
	)

	# Carrying is felt. A bay full of engines is a slower ship, which is the
	# price of hoarding and the reason to choose what to keep.
	var light: float = ship.mass
	var heavy: EngineData = loot.engine(4242, 0)
	heavy.bulk = 4.0
	ship.take(heavy, 0)
	_expect(ship.stow(), "the hold empties into the bay")
	_expect(ship.carried == null, "and the hold is free for the next find")
	_expect(
		is_equal_approx(ship.cargo_used(), 4.0),
		"the bay is measured in bulk, not in slots (%.1f)" % ship.cargo_used(),
	)
	_expect(
		ship.mass > light + 3.9,
		"cargo is mass: the ship went from %.1f to %.1f" % [light, ship.mass],
	)

	# And the capacity is the constraint, not a suggestion.
	var enormous: EngineData = loot.engine(4243, 0)
	enormous.bulk = ship.cargo_free() + 0.1
	ship.take(enormous, 0)
	_expect(not ship.stow(), "a module too big for the space left is refused")
	_expect(ship.carried == enormous, "and stays in the hold rather than vanishing")
	ship.release()

	_expect(ship.retrieve(0) and ship.carried == heavy, "what was stowed comes back out")
	_expect(ship.cargo.is_empty(), "and leaves the bay")
	_expect(not ship.retrieve(0), "an empty bay has nothing to hand over")

	# Jettison announces rather than destroys: who turns it back into a crate
	# is the world's business, but something must survive the throw.
	var thrown: Array[Resource] = []
	ship.jettisoned.connect(func(item: Resource, _rarity: int) -> void: thrown.append(item))
	_expect(ship.jettison() == heavy, "jettison hands back what went overboard")
	_expect(thrown.size() == 1 and thrown[0] == heavy, "and announces it exactly once")
	_expect(ship.carried == null, "leaving the hold empty")
	_expect(ship.jettison() == null, "an empty hold has nothing to throw")

	# A crate dropped by a ship sitting on top of it must not be picked back
	# up in the same frame, or throwing something away is a no-op.
	var crate: LootCrate = (load(CRATE_SCENE) as PackedScene).instantiate() as LootCrate
	crate.hold(heavy, 0)
	crate.grace = 2.0
	root.add_child(crate)
	var touches: Array[int] = []
	crate.touched.connect(func(_c: LootCrate, _b: Node) -> void: touches.append(1))
	crate._on_body_entered(ship)
	_expect(touches.is_empty(), "a just-jettisoned crate ignores the ship that dropped it")
	crate.grace = 0.0
	crate._on_body_entered(ship)
	_expect(touches.size() == 1, "and answers once the grace has run out")

	crate.queue_free()
	loot.free()
	ship.queue_free()


## MAUX1: the editor answers "would this be better" before anything is
## bolted on. Working that out means fitting the module, measuring, and
## putting everything back -- so the thing that must be true above all is
## that asking the question changes nothing.
func _check_editor() -> void:
	var ship: Ship = _spawn_ship()
	var editor: ShipEditor = ShipEditor.new()
	root.add_child(editor)
	editor.bind(ship)

	var mount: EngineMount = ship.get_node("MainDrive") as EngineMount
	var stronger: EngineData = mount.installed.duplicate() as EngineData
	stronger.max_thrust = mount.installed.max_thrust * 2.0
	ship.take(stronger, 2)

	var mass: float = ship.mass
	var centre: Vector2 = ship.center_of_mass
	var authority: float = ship.control.authority_of(ShipControl.Command.FORWARD)

	editor._refresh_preview()
	_expect(not editor._preview.is_empty(), "the preview says what fitting would do")
	_expect(
		"
".join(editor._preview).contains("FORWARD"),
		"and names the direction that would change (%s)" % ", ".join(editor._preview),
	)
	_expect(
		is_equal_approx(ship.mass, mass)
		and ship.center_of_mass.is_equal_approx(centre)
		and is_equal_approx(ship.control.authority_of(ShipControl.Command.FORWARD), authority),
		"and asking leaves the ship exactly as it was (%.2f kg, %.1f N)" % [
			ship.mass, ship.control.authority_of(ShipControl.Command.FORWARD),
		],
	)
	_expect(mount.installed != stronger, "the candidate is not left bolted in")

	# Looking is free, changing is not: the landing pad is what gates a refit.
	_expect(not editor.can_refit(), "a ship in flight may not be refitted here")
	editor._fit()
	_expect(
		mount.installed != stronger and ship.carried == stronger,
		"so fitting is refused and the module stays in the hold",
	)

	ship.flight_mode = Ship.FlightMode.LANDED
	_expect(editor.can_refit(), "a landed ship may be refitted")
	editor._fit()
	_expect(mount.installed == stronger, "and then the module actually goes on")
	_expect(
		ship.control.authority_of(ShipControl.Command.FORWARD) > authority * 1.5,
		"with the change the preview promised (%.0f -> %.0f)" % [
			authority, ship.control.authority_of(ShipControl.Command.FORWARD),
		],
	)

	# Clicking. Resolved against the layout rather than against whatever the
	# last frame happened to leave behind, which is what makes it checkable
	# here at all -- headless never draws.
	var loot: Node = LOOT_SCRIPT.new()
	ship.take(loot.weapon(555, 1), 1)
	loot.free()
	_expect(editor._items().size() >= 2, "there is a list to click on")
	editor._pick = 0
	_expect(
		editor.click_at(editor._row_rect(1, editor._panels()["list"]).get_center()),
		"a click on the second row hits it",
	)
	_expect(editor._pick == 1, "and selects it")
	_expect(not editor.click_at(Vector2(-50.0, -50.0)), "a click on nothing selects nothing")

	# And on the schematic: a mount the module fits becomes the target, one
	# it does not is refused by name rather than silently ignored.
	editor._pick = 0
	var place: Callable = editor._plan_placement(editor._panels()["plan"])
	var targets: Array[Node] = editor._targets()
	_expect(not targets.is_empty(), "the held module fits somewhere")
	if not targets.is_empty():
		var fitting: Node = targets[targets.size() - 1]
		_expect(
			editor.click_at(place.call((fitting as Node2D).position)),
			"a click on a mount hits it",
		)
		_expect(editor._targets()[editor._slot] == fitting, "and aims the swap at that mount")

	var torque: EngineMount = ship.get_node("NoseLeftTorque") as EngineMount
	_expect(
		editor.click_at(place.call(torque.position)) and not editor._targets().has(torque),
		"a mount the module does not fit is still clickable, and says so",
	)

	editor.queue_free()
	ship.queue_free()


## A pause is a claim, and only its own holder may drop it.
##
## The obvious guard -- "if my panel is shut and the tree is paused, unpause
## it" -- is correct with one such screen and destructive with two. The
## planet configurator ran it every frame and released the pause the ship
## editor had just taken, so the editor opened over a running game and the
## ship fell out of the sky while its own schematic was on screen.
##
## Driven with a null tree: the claim bookkeeping is the part that broke, and
## actually pausing the tree the smoke test is running in would stall it.
func _check_pause_gate() -> void:
	var first: Node = Node.new()
	var second: Node = Node.new()
	root.add_child(first)
	root.add_child(second)

	PauseGate.hold(first, null)
	_expect(PauseGate.held(), "a claim holds the game")
	PauseGate.hold(first, null)
	PauseGate.release(first, null)
	_expect(not PauseGate.held(), "claiming twice is still one claim")

	PauseGate.hold(first, null)
	PauseGate.hold(second, null)
	PauseGate.release(first, null)
	_expect(PauseGate.held(), "one holder letting go does not release another's claim")
	PauseGate.release(second, null)
	_expect(not PauseGate.held(), "and the last one dropped runs the game again")

	PauseGate.release(first, null)
	_expect(not PauseGate.held(), "releasing a claim never made changes nothing")

	# A screen freed while holding would otherwise pause the game for ever,
	# with nothing left in the tree that could let go.
	PauseGate.hold(second, null)
	second.free()
	_expect(not PauseGate.held(), "a holder freed while holding stops holding")

	first.free()

	# The bug itself, not just the bookkeeping: the configurator's own guard
	# running while the editor is open must leave the pause alone. Done
	# synchronously with no frames in between, so the real tree is paused
	# only for the length of these three lines.
	var editor: ShipEditor = ShipEditor.new()
	var configurator: PlanetConfigurator = PlanetConfigurator.new()
	root.add_child(editor)
	root.add_child(configurator)
	# `paused` rather than get_tree().paused: this script is the SceneTree.
	editor.toggle()
	var opened: bool = paused
	configurator._process(0.016)
	var survived: bool = paused
	editor.close()
	var released: bool = paused

	_expect(opened, "opening the editor pauses the game")
	_expect(survived, "and another screen's own guard does not undo that pause")
	_expect(not released, "closing it runs the game again")
	editor.queue_free()
	configurator.queue_free()


func _check_configuration_report() -> void:
	var ship: Ship = _spawn_ship()

	var stock: ConfigurationReport = ship.configuration()
	_expect(
		stock.worst() == ConfigurationReport.Severity.OK,
		"the stock ship reports a clean configuration (%s)" % _findings_of(stock),
	)
	_expect(stock.mass > 0.0 and stock.inertia > 0.0, "and carries the mass properties with it")

	# One side of a torque pair made twice as strong: the torques still add,
	# the forces no longer cancel, and every turn shoves the ship sideways.
	# This is the failure that prompted the report, so it is the one it must
	# not miss.
	var nose: EngineMount = ship.get_node("NoseLeftTorque") as EngineMount
	var stronger: EngineData = nose.installed.duplicate() as EngineData
	stronger.max_thrust = nose.installed.max_thrust * 2.0
	ship.fit_engine(nose, stronger)

	var crooked: ConfigurationReport = ship.configuration()
	_expect(
		crooked.worst() == ConfigurationReport.Severity.FAULT,
		"a lopsided torque pair is a fault, not a footnote (%s)" % _findings_of(crooked),
	)
	_expect(
		_findings_of(crooked).contains("sideways"),
		"and it is named as a sideways push rather than as a number nobody can place",
	)
	_expect(
		float(crooked.residual[ShipControl.Command.CW]) > 1.0,
		"the residual force is measured, not guessed (%.1f N)" % [
			crooked.residual[ShipControl.Command.CW],
		],
	)

	# Comparing against the report taken before the swap is what lets the
	# screen say what the module did rather than what the ship now is.
	var delta: PackedStringArray = crooked.compare(stock)
	_expect(not delta.is_empty(), "a swap that changes the ship is reported as a change")
	_expect(
		"
".join(delta).contains("sideways"),
		"and a fault the module introduced is blamed on it",
	)
	_expect(
		crooked.compare(crooked).is_empty(),
		"while comparing a configuration with itself invents nothing",
	)
	# The fault existed before this comparison, so it is not news.
	_expect(
		not "
".join(stock.compare(crooked)).contains("sideways"),
		"a fault already present is not re-blamed on the next module",
	)

	# A direction with nothing left behind it is the loudest thing the report
	# can say, and the easiest to cause: one mount emptied.
	var reverse: EngineMount = ship.get_node("NoseReverseThruster") as EngineMount
	reverse.installed = null
	ship.rebuild_control_groups(false)
	_expect(
		_findings_of(ship.configuration()).contains("no BACK authority"),
		"an empty command group is reported outright (%s)" % _findings_of(ship.configuration()),
	)

	ship.queue_free()


func _findings_of(report: ConfigurationReport) -> String:
	if report.findings.is_empty():
		return "clean"
	var parts: PackedStringArray = PackedStringArray()
	for finding: Dictionary in report.findings:
		parts.append(finding["text"])
	return "; ".join(parts)


func _check_bulk() -> void:
	var ship: Ship = _spawn_ship()

	var mount: EngineMount = ship.get_node("MainDrive") as EngineMount
	var base: EngineData = mount.installed

	# A slot is a hole in the hull. What is bolted into it is the mass, so a
	# heavier engine has to move the centre of mass -- that is the whole point
	# of bulk being a number rather than a yes/no.
	var before: Vector2 = ship.center_of_mass
	var heavy: EngineData = base.duplicate() as EngineData
	# Right up to the capacity, which is the largest engine the slot can hold
	# and so the sharpest version of the question.
	heavy.bulk = mount.size
	_expect(mount.size > base.bulk, "the stock drive leaves room in its slot (%.2f of %.2f)" % [
		base.bulk, mount.size,
	])
	_expect(mount.fits(heavy), "a slot takes an engine that fills it exactly")
	ship.fit_engine(mount, heavy)
	_expect(
		ship.center_of_mass.distance_to(before) > 0.05,
		"bulk is felt as mass: the centre of mass moved %.3f px" % [
			ship.center_of_mass.distance_to(before),
		],
	)

	# And past the capacity it simply does not go in, though the type is one
	# the slot lists.
	var monster: EngineData = base.duplicate() as EngineData
	monster.bulk = mount.size + 0.1
	_expect(mount.accepts(monster.type), "the slot does list this type")
	_expect(not mount.fits(monster), "but an engine past the slot capacity does not fit")
	_expect(
		ship.fit_engine(mount, monster) == monster and mount.installed == heavy,
		"a refused engine is handed straight back and changes nothing",
	)

	# Which is what makes 'compact' worth rolling: the same machine, smaller,
	# opens a slot that the full-sized one is locked out of.
	var small: EngineMount = ship.get_node("NoseLeftTorque") as EngineMount
	var shrunk: EngineData = monster.duplicate() as EngineData
	shrunk.bulk = small.size
	_expect(not small.fits(monster), "an oversized engine is locked out of a small slot")
	_expect(small.fits(shrunk), "and a compact one of the same type goes in")

	# An engine can now be too big for the whole hull, so the screen has to say
	# so. "No slot" on its own is not something a pilot can act on: too big is
	# a reason to keep it and look for a bigger ship, the wrong kind is a
	# reason to drop it.
	var screen: LoadoutScreen = LoadoutScreen.new()
	root.add_child(screen)
	screen.bind(ship)

	var giant: EngineData = base.duplicate() as EngineData
	giant.bulk = 99.0
	ship.release()
	ship.take(giant, 0)
	screen.announce_pickup()
	var refusal: String = screen.panel_text()
	_expect(
		refusal.contains("99.00") and refusal.contains("%.2f" % mount.size),
		"the screen says how big the engine is and how big the largest slot is",
	)

	ship.release()
	ship.take(shrunk, 0)
	screen.announce_pickup()
	_expect(
		screen.panel_text().contains("%.2f" % shrunk.bulk),
		"and a fitting engine still shows its bulk, so a swap can be compared",
	)

	screen.queue_free()
	ship.queue_free()


func _check_hold() -> void:
	var ship: Ship = _spawn_ship()
	var loot: Node = LOOT_SCRIPT.new()

	_expect(ship.carried == null, "a fresh ship carries nothing")

	var first: WeaponData = loot.weapon(31337, 2)
	_expect(ship.take(first, 2), "a found module goes into the hold")
	var second: WeaponData = loot.weapon(31338, 2)
	_expect(not ship.take(second, 2), "a full hold refuses the next find")
	_expect(ship.carried == first, "and keeps what it already had")
	_expect(ship.release() == first, "releasing hands the module back")
	_expect(ship.carried == null, "and empties the hold")

	# Fitting an engine has to change what the ship can do, or engines are not
	# loot -- they are decoration.
	var mount: EngineMount = ship.engine_mounts()[0]
	var before: float = ship.control.authority_of(ShipControl.Command.FORWARD)
	var stronger: EngineData = (mount.installed.duplicate() as EngineData)
	stronger.max_thrust = mount.installed.max_thrust * 2.0
	var removed: EngineData = ship.fit_engine(mount, stronger)
	var after: float = ship.control.authority_of(ShipControl.Command.FORWARD)
	_expect(removed != null, "fitting an engine hands the old one back")
	_expect(
		after > before * 1.5,
		"a stronger engine is felt in the command authority (%.0f -> %.0f)" % [before, after],
	)

	# And a mount only takes what it says it takes.
	var refused: EngineData = stronger.duplicate() as EngineData
	refused.type = EngineData.Type.THRUSTER
	mount.allowed_types = 1 << int(EngineData.Type.MAIN)
	_expect(not ship.mount_accepts(mount, refused), "a mount refuses a type it does not list")
	_expect(
		ship.fit_engine(mount, refused) == refused and mount.installed == stronger,
		"a refused engine is handed straight back and changes nothing",
	)

	loot.free()
	ship.queue_free()


## Loot has to be reproducible, bounded, and a trade rather than a ladder.
func _check_loot() -> void:
	# Instantiated rather than reached through the autoload: this test runs as
	# a --script main loop, where autoloads do not exist.
	var _loot: Node = LOOT_SCRIPT.new()
	# Reproducible: a container is its seed. Two pilots opening the same crate,
	# or one pilot after a reload, must find the same thing.
	var first: WeaponData = _loot.weapon(90210)
	var again: WeaponData = _loot.weapon(90210)
	_expect(
		is_equal_approx(first.damage, again.damage)
			and is_equal_approx(first.rounds_per_second, again.rounds_per_second)
			and first.display_name == again.display_name,
		"the same seed rolls the same weapon (%s)" % first.display_name,
	)
	var other: WeaponData = _loot.weapon(90211)
	_expect(
		not is_equal_approx(first.damage, other.damage)
			or first.display_name != other.display_name,
		"a different seed rolls something else (%s)" % other.display_name,
	)

	# Rarity buys affixes, and exactly as many as the table promises.
	for rarity: int in range(LOOT_SCRIPT.RARITY_AFFIXES.size()):
		var item: WeaponData = _loot.weapon(1000 + rarity, rarity)
		_expect(
			item.affixes.size() == LOOT_SCRIPT.RARITY_AFFIXES[rarity],
			"%s weapons carry %d affixes (%s)" % [
				_loot.rarity_name(rarity), item.affixes.size(), item.display_name,
			],
		)

	# Nothing the generator can roll may be unusable. Every field of every
	# rolled item has to land inside the limits, at every rarity, or a lucky
	# seed produces a gun with no rate of fire.
	var strays: int = 0
	for i: int in range(400):
		var rarity: int = i % LOOT_SCRIPT.RARITY_AFFIXES.size()
		strays += _fields_outside_limits(_loot.weapon(5000 + i, rarity))
		strays += _fields_outside_limits(_loot.engine(7000 + i, rarity))
	_expect(strays == 0, "800 rolled items stay inside their limits (%d strays)" % strays)

	# The weights have to produce the shape they describe: common common,
	# legendary rare. Checked as an ordering, not as exact counts.
	var counts: Array[int] = [0, 0, 0, 0, 0]
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 424242
	for i: int in range(4000):
		counts[_loot.roll_rarity(rng)] += 1
	var ordered: bool = true
	for i: int in range(counts.size() - 1):
		if counts[i] <= counts[i + 1]:
			ordered = false
	_expect(ordered, "rarity thins out as it climbs (%s)" % [counts])

	# The design claim, guarded at the table rather than at one sample: an
	# affix that has a cost must actually cost something. Rarity that is only
	# ever better is a number going up, not a choice.
	var costed: int = 0
	var free_lunches: int = 0
	for table: Array[Dictionary] in [LOOT_SCRIPT.WEAPON_AFFIXES, LOOT_SCRIPT.ENGINE_AFFIXES]:
		for affix: Dictionary in table:
			if not affix.has("cost_field"):
				continue
			costed += 1
			var field: String = String(affix["cost_field"])
			var cost: Vector2 = affix["cost"] as Vector2
			var helps: bool = cost.x > 1.0 if bool(LOOT_SCRIPT.HIGHER_IS_BETTER[field]) else cost.x < 1.0
			if helps:
				free_lunches += 1
	_expect(costed >= 3, "several affixes are trades rather than gifts (%d of them)" % costed)
	_expect(free_lunches == 0, "and every one of those trades actually costs something")
	_loot.free()


## How many fields of `item` fall outside what the generator promises.
func _fields_outside_limits(item: Resource) -> int:
	var strays: int = 0
	for field: String in LOOT_SCRIPT.LIMITS:
		if not (field in item):
			continue
		var bounds: Vector2 = LOOT_SCRIPT.LIMITS[field]
		var value: float = float(item.get(field))
		if value < bounds.x - 0.0001 or value > bounds.y + 0.0001:
			print("  stray: %s = %.3f outside %.3f..%.3f" % [field, value, bounds.x, bounds.y])
			strays += 1
	return strays


## Plateaus have to be real ground a stock ship can stand on, not just a number
## in the generator.
## Elements have to agree with the two cases that can be written down without
## integrating anything: a circle, and a throw fast enough to leave.
func _check_elements(planet: Planet) -> void:
	var radius: float = planet.surface_radius * 2.0
	var point: Vector2 = planet.global_position + Vector2.UP * radius
	var circular: float = planet.circular_orbit_speed(radius)

	var circle: Vector2 = planet.orbit_extremes(point, Vector2.RIGHT * circular)
	_expect(
		absf(circle.x - radius) < 1.0 and absf(circle.y - radius) < 1.0,
		"a circular orbit has both apsides at its own radius (%.0f, %.0f vs %.0f)" % [
			circle.x, circle.y, radius,
		],
	)

	# sqrt(2) times circular is escape velocity exactly; a shade over it must
	# not come back, whatever the planet.
	var escape: Vector2 = planet.orbit_extremes(point, Vector2.RIGHT * circular * 1.45)
	_expect(is_inf(escape.y), "escape velocity has no apoapsis")

	# Being in orbit is read off the trajectory rather than switched on, so the
	# reading is what has to be tested: each of the four answers, from a state
	# that plainly deserves it.
	_expect(
		planet.orbit_state(point, Vector2.RIGHT * circular) == Planet.OrbitState.ORBIT,
		"a circular orbit above the air reads as ORBIT",
	)
	_expect(
		planet.orbit_state(point, Vector2.RIGHT * circular * 1.45) == Planet.OrbitState.ESCAPE,
		"escape velocity reads as ESCAPE",
	)
	_expect(
		planet.orbit_state(point, Vector2.DOWN * 10.0) == Planet.OrbitState.SUBORBITAL,
		"a ship dropped straight down reads as SUBORBITAL",
	)
	# Aimed rather than guessed: for a tangential throw the periapsis comes out
	# at r*x/(2-x) with x = (v/v_circ)^2, so inverting that puts it exactly
	# halfway between the highest rock and the top of the air. Picking a round
	# fraction of circular speed instead dropped it into the ground.
	var target: float = (planet.terrain_ceiling() + planet.atmosphere_radius()) * 0.5
	var grazing: float = circular * sqrt(2.0 * target / (radius + target))
	_expect(
		planet.orbit_state(point, Vector2.RIGHT * grazing) == Planet.OrbitState.DECAYING,
		"an orbit whose periapsis is in the air reads as DECAYING",
	)
	# Outside the well the planet is not holding anything, whatever the conic
	# would say if it were asked.
	var far: Vector2 = planet.global_position + Vector2.UP * (planet.influence_radius * 1.1)
	_expect(
		planet.orbit_state(far, Vector2.RIGHT * circular) == Planet.OrbitState.ESCAPE,
		"beyond the influence radius there is no orbit to be in",
	)

	# Radial drop: no angular momentum at all, so the periapsis is the centre.
	var falling: Vector2 = planet.orbit_extremes(point, Vector2.DOWN * 10.0)
	_expect(
		falling.x < 1.0 and falling.y < radius * 1.02,
		"a straight drop has its periapsis at the centre (%.1f)" % falling.x,
	)


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
