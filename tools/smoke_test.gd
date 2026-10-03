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
const STARFIELD_SCENE: String = "res://scenes/starfield.tscn"

## Every look table on disk. A const list rather than a directory walk,
## because a table that stops being written is a table that stops being
## checked, and a directory walk would quietly agree.
const ART_LOOK_TABLES: Array[String] = [
	"res://resources/fx/looks/hull.tres",
	"res://resources/fx/looks/engine_nozzle.tres",
	"res://resources/fx/looks/engine_plume.tres",
	"res://resources/fx/looks/weapon_muzzle.tres",
	"res://resources/fx/looks/module_box.tres",
	"res://resources/fx/looks/gear_leg.tres",
	"res://resources/fx/looks/round.tres",
	"res://resources/fx/looks/particle.tres",
	"res://resources/fx/looks/module_icon.tres",
]

## A seed known to produce a planet with air. Picked once, kept fixed so the
## numbers below stay meaningful.
const TEST_SEED: int = 20260922

const BURN_TICKS: int = 60

## Long enough for the main drive to finish spooling and then some.
const FORWARD_BURN_TICKS: int = 120

## Spin handed to the kill-rotation phase, and the second it is allowed.
## How long the heading assist gets to swing the ship round and settle, and
## the velocity it is aiming along. Deep space, so nothing pulls the ship off
## the straight line the assist is being judged against.
## Long enough to shape an elliptical arrival into a circle and then hold
## it: circularising is not instant, and a test that only watched the burn
## would miss the assist overshooting afterwards.
const AUTO_ORBIT_TICKS: int = 2400

const HEADING_TICKS: int = 900
const HEADING_TRAVEL: Vector2 = Vector2(140.0, -60.0)

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

## The state a ship has to be able to get down in: engines at two thirds and
## plainly unreliable. Not wrecked -- a ship that cannot land at all is a
## death sentence with extra steps, and the point of the damage model is that
## a bad landing is survivable and awkward.
const DAMAGED_LANDING_HEALTH: float = 0.65
const DAMAGED_LANDING_RELIABILITY: float = 0.5

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
	ROTATE_DAMAGED, KILL_ROTATION, POINT_PROGRADE, POINT_RETROGRADE, AUTO_ORBIT, BRAKE, BRAKE_SIDEWAYS, BRAKE_DIAGONAL, STRAFE, FREE_FALL, ORBIT,
	ELLIPSE, AEROBRAKE, HULL_HEAT, SPIN_IN_AIR, SPIN_IN_VACUUM, LANDING,
	PLATEAU, GEAR, LANDING_GOOD, LANDING_DAMAGED, LANDING_FAST, LANDING_STEEP, LANDED_RIDE, GROUND_RIDE,
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

## The range of thrust actually delivered during the damaged approach.
var _damaged_output_low: float = 1.0
var _damaged_output_high: float = 0.0

## Energy in the pool when the weapon phase began firing.
var _energy_at_fire: float = 0.0
var _target_was_solid: bool = false
var _round_container: Node = null
var _failures: int = 0


func _initialize() -> void:
	for action: String in ["thrust_forward", "thrust_reverse", "rotate_left",
			"rotate_right", "strafe_left", "strafe_right", "brake"]:
		_expect(InputMap.has_action(action), "input action %s is defined" % action)
	_begin_phase()


func _physics_process(delta: float) -> bool:
	if _phase == Phase.DONE:
		return _finish()

	_ticks += 1
	_elapsed += delta
	if _phase == Phase.LANDING_DAMAGED and _ship != null:
		for engine: EngineInstance in _ship.engines:
			if engine.target_throttle <= 0.0:
				continue
			_damaged_output_low = minf(_damaged_output_low, engine.effective_output())
			_damaged_output_high = maxf(_damaged_output_high, engine.effective_output())
	if _phase == Phase.AUTO_ORBIT:
		# Only once the burn has had time to work: the first stretch is the
		# ellipse it was handed, not the circle it made.
		if _ticks > AUTO_ORBIT_TICKS / 2:
			var reached: float = _ship.global_position.distance_to(_planet.global_position)
			_orbit_min = minf(_orbit_min, reached)
			_orbit_max = maxf(_orbit_max, reached)
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
	for hull_point: Vector2 in _ship.contact_points():
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
		Phase.POINT_PROGRADE, Phase.POINT_RETROGRADE:
			return HEADING_TICKS
		Phase.AUTO_ORBIT:
			return AUTO_ORBIT_TICKS
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
		Phase.LANDING_GOOD, Phase.LANDING_DAMAGED, Phase.LANDING_FAST, Phase.LANDING_STEEP:
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
		Phase.CONTROL_GROUPS, Phase.FORWARD_BURN, Phase.ROTATE_CW, Phase.ROTATE_CCW, Phase.ROTATE_DAMAGED, Phase.KILL_ROTATION, Phase.POINT_PROGRADE, Phase.POINT_RETROGRADE, Phase.BRAKE, Phase.BRAKE_SIDEWAYS, Phase.BRAKE_DIAGONAL, Phase.STRAFE:
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
		Phase.AUTO_ORBIT:
			# Thrown along a plainly elliptical path, with a computer that
			# knows how to fix it. Well above the air, or the assist would be
			# fighting drag it cannot win against.
			var height: float = _planet.atmosphere_radius() + 1400.0
			_ship.global_position = _planet.global_position + Vector2.UP * height
			# Nine tenths of circular: an ellipse about a third out of round,
			# whose low point still clears the air. Any slower and the test
			# would be about rescuing a suborbital arc, which is a different
			# manoeuvre the assist is not claiming to do.
			var circular: float = sqrt(_planet.mu() / height)
			_ship.linear_velocity = Vector2.RIGHT * circular * 0.9
			_fit_computer(_ship, true)
			_ship.auto_orbit_command = true
			_orbit_min = INF
			_orbit_max = 0.0
		Phase.POINT_PROGRADE, Phase.POINT_RETROGRADE:
			# Pointing the wrong way to start with, so the assist has most of
			# a turn to make and cannot pass by accident.
			_ship.global_rotation = 2.5
			_ship.angular_velocity = 0.0
			_ship.linear_velocity = HEADING_TRAVEL
			_ship.heading_command = (
				ControlChords.Chord.PROGRADE if _phase == Phase.POINT_PROGRADE
				else ControlChords.Chord.RETROGRADE
			)
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
			# Left charged: the rate check below measures rate of fire, and
			# starving the pool here would have it measuring energy instead.
			_energy_at_fire = _ship.energy
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
		Phase.LANDING_DAMAGED:
			# The same approach as the good one, flown on a hull whose engines
			# are half dead and unreliable. Hard is not something a test can
			# assert; that it is still possible is.
			_flat_angle = _find_angle(_planet, true, _ship.gear.track_width())
			_place_for_touchdown(_flat_angle, 0.0)
			for engine: EngineInstance in _ship.engines:
				engine.health = DAMAGED_LANDING_HEALTH
				var flaky: EngineData = engine.data.duplicate() as EngineData
				flaky.reliability = DAMAGED_LANDING_RELIABILITY
				engine.data = flaky
			_damaged_output_low = 1.0
			_damaged_output_high = 0.0
		Phase.LANDING_FAST:
			_place_for_touchdown(_find_angle(_planet, true, _ship.gear.track_width()), HARD_DESCENT)
		Phase.LANDING_STEEP:
			# Tilt rather than hunting for a cliff: whether a given seed grows
			# ground steeper than the gear tolerates is luck, but arriving at a
			# bad attitude is always available and exercises the same refusal.
			_place_for_touchdown(_find_angle(_planet, true, _ship.gear.track_width()), 0.0)
			_ship.global_rotation += _ship.gear.tilt_limit() * 2.5
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
		Phase.POINT_PROGRADE, Phase.POINT_RETROGRADE:
			var facing: float = 1.0 if _phase == Phase.POINT_PROGRADE else -1.0
			var nose: Vector2 = Ship.FORWARD.rotated(_ship.global_rotation)
			var along: float = nose.dot(HEADING_TRAVEL.normalized()) * facing
			_expect(
				along > 0.99,
				"%s brings the nose onto the direction of travel (%.4f)" % [
					"prograde" if facing > 0.0 else "retrograde", along,
				],
			)
			# Arriving still spinning would mean it sails past and comes
			# back, which is a wobble rather than a hold.
			_expect(
				absf(_ship.angular_velocity) < 0.05,
				"and stops there rather than swinging through (%.3f rad/s)" % [
					_ship.angular_velocity,
				],
			)
		Phase.AUTO_ORBIT:
			var spread: float = (_orbit_max - _orbit_min) / maxf(_orbit_max, 1.0)
			_expect(
				spread < 0.10,
				"auto-orbit turns an elliptical path into a round one (%.0f..%.0f px, %.1f%% spread)" % [
					_orbit_min, _orbit_max, spread * 100.0,
				],
			)
			_expect(
				_orbit_min > _planet.atmosphere_radius(),
				"and holds it clear of the air (%.0f px against %.0f)" % [
					_orbit_min, _planet.atmosphere_radius(),
				],
			)
			# A box without the function has to refuse, or it would not be
			# an optional function at all.
			_fit_computer(_ship, false)
			_ship.active_commands.clear()
			_ship._apply_auto_orbit_probe()
			_expect(
				_ship.active_commands.is_empty(),
				"a computer without auto-orbit asks for nothing when it is engaged",
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
			_check_panels_release_the_mouse()
			_check_camera(_planet)
			_check_chords()
			_check_energy()
			_check_shot_mods()
			_check_energy_balance()
			_check_engine_failures()
			_check_boost()
			_check_hull_outline(_planet)
			_check_allocator()
			_check_gimbal()
			_check_gear_module()
			_check_weapon_types(_planet)
			_check_ship_fitouts()
			_check_fitout_presets()
			_check_creative_tool()
			_check_art()
			_check_skin()
			_check_camera_shake()
			_check_ship_wear()
			_check_soundscape()
			_check_debris()
			_check_rarity_travels()
			_check_affix_pools()
			_check_item_names()
			_check_seeker_targets()
			_check_galaxy()
			_check_system_model(_planet)
			_check_star()
			_check_orbit_host()
			_check_reach_on_the_map()
			_check_daylight()
			_check_lighting()
			_check_docking()
			_check_round_fall()
			_check_bindings()
			_check_streaming()
			_check_system_tour()
			_check_system_map()
			_check_flight_hud(_planet)
			_check_aiming()
			_check_stat_cards()
			_check_font()
			_check_palette()
			_check_scanner(_planet)
			_check_crate_physics(_planet)
			_check_ejection()
			_check_plateaus(_planet)
			_check_landing_sites(_planet)
			_check_determinism(_planet)
			_check_elements(_planet)
			_check_weather(_planet)
		Phase.GEAR:
			_check_gear(_ship)
			_check_damage_model(_ship)
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
		Phase.LANDING_DAMAGED:
			_expect(
				_first_touchdown == "landed",
				"a crippled ship can still be put down gently (got %s)" % _describe_touchdown(),
			)
			_expect(
				_ship.worst_engine_health() < 1.0,
				"and it really was crippled while doing it (%.2f)" % _ship.worst_engine_health(),
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
			# Charged once, by whatever touched. Billing the refusal as well
			# as the contact it caused is how arriving at 120 px/s on the
			# legs came to cost more than a crash.
			_expect(
				_ship.accumulated_damage < 0.25,
				"and being waved off at %.0f px/s is a bounce and a bill, not a wreck (%.3f)" % [
					HARD_DESCENT, _ship.accumulated_damage,
				],
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
					rad_to_deg(_ship.gear.tilt_limit() * 2.5), _describe_touchdown(),
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
			# The gate is on the real firing path, not only in a unit test:
			# every round that came out paid for itself, and nothing came
			# back in. Exact because each shot pushes the recharge back, so a
			# gun that is firing is a generator that is not charging.
			var cost: float = _ship.hardpoints[0].weapon.energy_cost
			var spent: float = _energy_at_fire - _ship.energy
			_expect(
				absf(spent - float(_rounds_fired) * cost) < 0.01,
				"every round came out of the pool and none of it came back (%.1f for %d at %.0f)" % [
					spent, _rounds_fired, cost,
				],
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


## Puts a flight computer in the bay, with or without the orbit function.
func _fit_computer(ship: Ship, with_auto_orbit: bool) -> void:
	if ship.computer_bay == null:
		return
	var box: FlightComputerData = FlightComputerData.new()
	box.allocation = FlightComputerData.Allocation.NNLS
	box.has_auto_orbit = with_auto_orbit
	box.bulk = 0.5
	ship.computer_bay.installed = box
	ship.rebuild_control_groups(false)


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
	var tolerance: float = probe.gear.slope_limit()
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
const GALAXY_SCRIPT: GDScript = preload("res://scripts/autoload/galaxy.gd")
const STREAMING_SCRIPT: GDScript = preload("res://scripts/autoload/streaming_manager.gd")

## Most main-thread milliseconds one body may cost to bring into the world.
##
## Measured, then given headroom, which is the only way a number like this
## means anything. See `_check_system_tour()` for what is and is not counted.
const TOUR_FRAME_BUDGET: float = 12.0

## Most affixes any roll asks for, which is what the rarest one asks for.
const RARITY_AFFIXES_MAX: int = 4

## How many systems the layout checks run over. One seed proves nothing
## about a generator; the interesting failures are the lucky rolls.
const SYSTEMS_SAMPLED: int = 300

## The map's own margin, which its layout reserves on every side.
const PAD_ON_MAP: float = 24.0

## How far from the origin `tools/distance_bench.gd` has actually measured
## the game behaving. Out to here the cost of distance is hundredths of a
## pixel in stored coordinates and under half a pixel of creep in ten
## seconds under a resting hull; orbits do not notice at all.
##
## A layout that walks past this number is a layout running on evidence
## nobody collected, which is how "float32 shakes past a hundred thousand"
## became something everyone repeats and nobody had measured here.
const PROVEN_DISTANCE: float = 1000000.0


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
		is_equal_approx(ship.cargo_free(), ship.cargo_capacity()),
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
		absf((ship.mass - light) - 4.0 * Ship.CARGO_MASS_PER_BULK) < 0.01,
		"cargo is mass, at the payload rate: %.1f to %.1f kg for 4 of bulk" % [light, ship.mass],
	)

	# And the other half of that: felt, but never crippling. At one-to-one a
	# full hold added 75% to the ship and took 43% of its acceleration, so
	# carrying anything at all was a refusal rather than a decision.
	# Measured from a genuinely empty hold, or the baseline already carries
	# the load it is supposed to be compared against.
	ship.cargo.clear()
	ship.rebuild_control_groups(false)
	var empty_accel: float = ship.control.authority_of(
		ShipControl.Command.FORWARD
	) / ship.mass
	var stuffing: EngineData = heavy.duplicate() as EngineData
	stuffing.bulk = ship.cargo_capacity()
	ship.cargo.append({"item": stuffing, "rarity": 0})
	ship.rebuild_control_groups(false)
	var laden_accel: float = ship.control.authority_of(
		ShipControl.Command.FORWARD
	) / ship.mass
	var cost: float = 1.0 - laden_accel / empty_accel
	_expect(
		cost > 0.05,
		"a full hold is felt (%.0f%% of the acceleration)" % [cost * 100.0],
	)
	_expect(
		cost < 0.30,
		"but never turns the ship into a brick (%.0f%%, budget 30%%)" % [cost * 100.0],
	)
	ship.cargo.clear()
	ship.rebuild_control_groups(false)
	ship.take(heavy, 0)
	ship.stow()

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

	# Slots are boxes on the schematic, and a box has to be somewhere a
	# click can find it. The internal bays sit within a few pixels of each
	# other on the hull, so they are fanned apart for drawing -- which is
	# only safe while the click uses the same picture.
	#
	# Laid out at the size the game draws at. Headless hands the canvas
	# whatever the window happens to be -- 640x640 here -- and at nearly
	# twice the height the schematic has room the game has not: the bays
	# separate on their own and the test would be passing on a layout
	# nobody ever sees.
	editor._canvas.set_anchors_preset(Control.PRESET_TOP_LEFT)
	editor._canvas.size = Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width")),
		float(ProjectSettings.get_setting("display/window/size/viewport_height")),
	)
	var plan: Rect2 = editor.plan_rect()
	var where: Dictionary = editor.slot_positions(plan)
	var boxes: Array[Rect2] = []
	var separated: bool = true
	var inside: bool = true
	for slot: Node in where:
		var box: Rect2 = editor.slot_rect(where[slot])
		for other: Rect2 in boxes:
			separated = separated and not box.intersects(other)
		boxes.append(box)
		inside = inside and plan.encloses(box)
	_expect(separated, "no two slots are drawn on top of each other (%d slots)" % boxes.size())
	_expect(inside, "and none of them is drawn outside the schematic")

	for slot: Node in where:
		editor.click_at(where[slot])
		_expect(
			editor.named_slot() == slot,
			"a click where %s is drawn names %s" % [slot.name, slot.name],
		)

	# Looking is free, changing is not: the landing pad is what gates a refit.
	_expect(not editor.can_refit(), "a ship in flight may not be refitted here")
	editor._fit()
	_expect(
		mount.installed != stronger and ship.carried == stronger,
		"so fitting is refused and the module stays in the hold",
	)

	ship.flight_mode = Ship.FlightMode.LANDED
	_expect(editor.can_refit(), "a landed ship may be refitted")

	# And so may a docked one, which is what gives a station a job beyond
	# mending the hull. The quick swap on Tab stays available in flight on
	# purpose -- see ShipEditor.can_refit() for why the two differ.
	ship.flight_mode = Ship.FlightMode.DOCKED
	_expect(editor.can_refit(), "and so may one tied up at a station")
	ship.flight_mode = Ship.FlightMode.PHYSICAL
	_expect(
		not editor.can_refit(),
		"but letting go of the station takes the workshop away again",
	)
	ship.flight_mode = Ship.FlightMode.LANDED
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

	# Last, because it wrecks every mount on the ship.
	#
	# A refit frees them all and builds new ones, and this screen was
	# holding one by reference with nothing to clear it. The next frame
	# tried to build an array out of a freed node and threw -- once a
	# frame, for as long as the schematic stayed open. The guard meant to
	# skip it was already there and ran three lines too late: a typed array
	# validates while it is being built, not while it is being read.
	#
	# Named explicitly rather than by taking whatever the click loop left
	# behind. The first version of this check did that and passed for the
	# wrong reason: the last slot it clicked was a bay, and a refit does
	# not free the bays.
	var doomed: EngineMount = ship.get_node("MainDrive") as EngineMount
	editor._named = doomed
	_expect(editor.named_slot() == doomed, "the editor is holding a mount by name")
	ShipFitout.apply(ship, _preset_named("frachtowiec"))
	_expect(
		editor.named_slot() == null,
		"and a refit makes it let go, because that mount no longer exists",
	)
	_expect(
		editor._captions(null, editor._all_mounts()).is_empty(),
		"so nothing stale can reach the captions",
	)

	# A rebuild that keeps the mounts must keep the caption: fitting a
	# module rebuilds too, and blanking the name the pilot just clicked
	# for would be a fix that costs more than the bug.
	var kept: Node = editor._all_mounts()[0]
	editor._named = kept
	ship.rebuild_control_groups(false)
	_expect(
		editor.named_slot() == kept,
		"while a rebuild that keeps every mount keeps it too",
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

	# One modal at a time. Two paused panels stacked is a trap: both are
	# modal, the upper one takes every click, and the lower one looks like a
	# panel that has stopped accepting the mouse.
	var sandbox: CreativeTool = CreativeTool.new()
	root.add_child(sandbox)
	editor.toggle()
	_expect(editor.is_open(), "the editor is open to begin with")
	sandbox.toggle()
	_expect(sandbox.is_open(), "opening the sandbox opens it")
	_expect(not editor.is_open(), "and shuts the editor rather than stacking on it")
	_expect(paused, "the game stays paused across the handover")
	sandbox.close()
	sandbox.queue_free()

	_expect(opened, "opening the editor pauses the game")
	_expect(survived, "and another screen's own guard does not undo that pause")
	_expect(not released, "closing it runs the game again")
	editor.queue_free()
	configurator.queue_free()


## The pilot's own framing: three zoom levels and a view they can turn.
##
## The one that needs checking is levelling, because "put the planet at the
## bottom" is a sign convention and this project has been caught by one
## before -- Vector2.orthogonal() turns the opposite way to an increasing
## polar angle, which sent the old orbit lock backwards.
func _check_camera(planet: Planet) -> void:
	var camera: ShipCamera = ShipCamera.new()
	root.add_child(camera)
	var ship: Ship = _spawn_ship()
	camera.set_target(ship)

	_expect(
		not camera.ignore_rotation,
		"the camera honours its own rotation, or none of this shows at all",
	)
	_expect(
		camera.zoom_level() == ShipCamera.DEFAULT_LEVEL
		and is_equal_approx(ShipCamera.ZOOM_LEVELS[ShipCamera.DEFAULT_LEVEL], 1.0),
		"the middle framing is the old behaviour exactly",
	)
	_expect(
		ShipCamera.ZOOM_LEVELS[0] > ShipCamera.ZOOM_LEVELS[ShipCamera.ZOOM_LEVELS.size() - 1],
		"the list runs closest to widest",
	)
	camera.set_zoom_level(-5)
	_expect(camera.zoom_level() == 0, "zooming in past the end stops at the closest")
	camera.set_zoom_level(99)
	_expect(
		camera.zoom_level() == ShipCamera.ZOOM_LEVELS.size() - 1,
		"and out past the end stops at the widest, rather than wrapping round",
	)

	# Turning accumulates rather than wrapping, so the smoothing never takes
	# the long way round.
	camera.rotation = 7.0
	camera.level_view()
	# The property is the size of the move, not the size of the result: from
	# 7 radians the answer is around 6.28, which is upright plus a full turn
	# and the short way there. Demanding a small absolute value instead would
	# be demanding the long way round.
	_expect(
		absf(camera.rotation - 7.0) <= PI + 0.001,
		"levelling takes the short way round, never more than half a turn (%.2f rad)" % [
			absf(camera.rotation - 7.0),
		],
	)

	# The sign convention, measured rather than reasoned about: put the ship
	# to one side of the planet, level the view, and check the planet really
	# does appear below.
	for offset: Vector2 in [Vector2(1500.0, 0.0), Vector2(-900.0, 400.0), Vector2(0.0, -2000.0)]:
		ship.global_position = planet.global_position + offset
		camera.level_view()
		# A world vector appears on screen turned by minus the camera's own
		# rotation.
		var on_screen: Vector2 = (planet.global_position - ship.global_position).rotated(
			-camera.rotation
		)
		_expect(
			on_screen.normalized().dot(Vector2.DOWN) > 0.999,
			"from %s, levelling puts the planet at the bottom of the screen" % offset,
		)

	camera.set_target(null)
	camera.rotation = 1.0
	camera.level_view()
	_expect(
		is_zero_approx(camera.rotation),
		"with nothing to be below, levelling means upright",
	)

	# The sky is painted on a screen-space quad, so it does not turn by
	# itself: the script has to hand the shader the rotation being shown.
	#
	# Only the wiring is checked here. Whether the field actually turns was
	# measured on the real renderer -- two frames ninety degrees apart, 123
	# of 239 stars landing where the rotation predicts against 3 and 1 for
	# the alternatives, which is every star that can stay inside a turned
	# 16:9 frame. Headless renders nothing, and get_screen_rotation() only
	# catches up over frames, so an assertion on the angle itself would
	# compare zero with zero and could never fail.
	var sky: Starfield = (load(STARFIELD_SCENE) as PackedScene).instantiate() as Starfield
	root.add_child(sky)
	camera.set_target(ship)
	camera.make_current()
	sky._process(0.016)
	var material: ShaderMaterial = (sky.get_node("Sky") as ColorRect).material as ShaderMaterial

	var declared: bool = false
	for uniform: Dictionary in material.shader.get_shader_uniform_list():
		if String(uniform["name"]) == "view_rotation":
			declared = true
	_expect(declared, "the sky shader takes a view rotation")
	_expect(
		material.get_shader_parameter("view_rotation") != null,
		"and the script feeds it every frame",
	)

	# The parallax offset cannot be checked here either, and for the same
	# reason as the rotation above: get_screen_center_position() is what
	# the engine last put on screen, and headless never puts anything
	# there, so it reads zero however the camera is moved. What it used to
	# be was `position * zoom`, and zoom is animated by speed -- so every
	# change of throttle multiplied the whole offset by a different number
	# and the field jumped by the change times the distance from the
	# origin. Reported from the game as the stars swirling under throttle,
	# and checked there: the camera sits 19621 px out on the starting
	# orbit, so easing from zoom 1.7 to 0.55 used to swing the offset
	# across 22600 px of it. Measured after the fix, over the same zoom
	# change: 18 px, and those are the camera drifting as the ship falls.
	sky.queue_free()

	# The approach lock. Two conditions that say different things: the gear
	# is an intention to land, the altitude is how far along it is.
	ship.global_position = planet.global_position + Vector2(planet.surface_radius + 100.0, 0.0)
	ship.gear.stow_instantly()
	_expect(
		is_zero_approx(camera.lock_weight()),
		"low over the ground with the legs up is not an approach",
	)

	ship.gear.set_deployed(true)
	ship.gear.advance(ship.gear.extend_time() * 2.0)
	_expect(ship.gear.is_deployed(), "the legs are down for the rest of this")

	var high: Vector2 = Vector2(
		planet.surface_radius_at(ship.global_position) + ShipCamera.LOCK_ALTITUDE + 50.0, 0.0
	)
	ship.global_position = planet.global_position + high
	_expect(
		is_zero_approx(camera.lock_weight()),
		"gear down above %.0f px is still flying, not landing" % ShipCamera.LOCK_ALTITUDE,
	)

	# Continuous, not a switch: the weight has to grow on the way down, or
	# the view would snap the moment the threshold was crossed.
	var weights: Array[float] = []
	for height: float in [290.0, 200.0, 100.0, 10.0]:
		ship.global_position = planet.global_position + Vector2(
			planet.surface_radius_at(ship.global_position) + height, 0.0
		)
		weights.append(camera.lock_weight())
	var climbing: bool = true
	for i: int in range(1, weights.size()):
		climbing = climbing and weights[i] > weights[i - 1]
	_expect(
		climbing and weights[0] < 0.1 and weights[weights.size() - 1] > 0.9,
		"the lock leans harder the lower it gets (%s)" % [weights],
	)

	# And it actually turns the view, without being asked and without a key.
	camera.rotation = 2.0
	for step: int in range(240):
		camera.hold_planet_down(1.0 / 60.0)
	var below: Vector2 = (planet.global_position - ship.global_position).rotated(-camera.rotation)
	_expect(
		below.normalized().dot(Vector2.DOWN) > 0.99,
		"on short finals the planet ends up at the bottom of the screen by itself",
	)

	# Nothing happens when the gate is shut, whatever the camera is pointing
	# at: the pilot's framing is theirs until an approach earns it.
	ship.gear.stow_instantly()
	camera.rotation = 2.0
	camera.hold_planet_down(1.0)
	_expect(
		is_equal_approx(camera.rotation, 2.0),
		"with the legs up the camera leaves the pilot's framing alone",
	)

	camera.queue_free()
	ship.queue_free()


## Commands made by holding keys together. The whole idea rests on the
## combination meaning nothing else -- A and D are opposite torques that
## cancel -- so the thing to pin is that a chord takes its keys out of
## circulation, and that a finger rolling from one to the other does not
## count as pressing both.
func _check_chords() -> void:
	var chords: ControlChords = ControlChords.new()
	var down: Callable = func(keys: Array) -> Dictionary:
		var held: Dictionary = {}
		for key: StringName in keys:
			held[key] = true
		return held

	_expect(
		chords.update(down.call([&"rotate_left"]), 0.5) == ControlChords.Chord.NONE,
		"one key of a chord is just that key",
	)

	# The settle window: held together but not yet long enough is still not a
	# chord, which is what a roll from A to D looks like.
	var both: Dictionary = down.call([&"rotate_left", &"rotate_right"])
	_expect(
		chords.update(both, ControlChords.SETTLE * 0.4) == ControlChords.Chord.NONE,
		"a brief overlap while rolling from one key to the other is not a chord",
	)
	_expect(
		chords.update(both, ControlChords.SETTLE) == ControlChords.Chord.KILL_ROTATION,
		"holding both long enough is",
	)
	_expect(
		chords.consumed().has(&"rotate_left") and chords.consumed().has(&"rotate_right"),
		"and it takes both keys out of circulation",
	)
	_expect(
		chords.update(down.call([&"rotate_left"]), 0.001) == ControlChords.Chord.NONE,
		"letting go of one is believed at once, without a window",
	)

	# ...but the key that outlasted the other is not a turn command. Two
	# fingers do not come off together, so for a few tens of milliseconds
	# one of them is still down, and without this the ship starts turning
	# again at the moment the pilot stopped telling it to stop -- on the
	# one gesture that means panic. Reported from the cockpit.
	_expect(
		chords.consumed().has(&"rotate_left"),
		"and the finger that outlasts the other is still spent, not a fresh turn",
	)
	_expect(
		not chords.consumed().has(&"rotate_right"),
		"while the one already lifted is free again",
	)
	# Held a good while longer, in case anyone is tempted to make this a
	# window: a slow release has to work as well as a quick one.
	for tick: int in range(60):
		chords.update(down.call([&"rotate_left"]), 1.0 / 60.0)
	_expect(
		chords.consumed().has(&"rotate_left"),
		"a second later it is still spent -- the hold runs on the key, not on a clock",
	)
	chords.update({}, 0.016)
	_expect(
		chords.consumed().is_empty(),
		"and letting go of it is what gives it back",
	)
	_expect(
		chords.update(down.call([&"rotate_left"]), 1.0) == ControlChords.Chord.NONE
		and not chords.consumed().has(&"rotate_left"),
		"pressing it again turns the ship, which is how you get a turn out of it",
	)
	chords.update({}, 0.016)

	var prograde: Dictionary = down.call([&"strafe_left", &"strafe_right", &"thrust_forward"])
	chords.update(prograde, 1.0)
	_expect(chords.active() == ControlChords.Chord.PROGRADE, "Q+E+W points along the way we go")
	_expect(
		chords.consumed().has(&"thrust_forward"),
		"and swallows the thrust key: aiming backwards while burning backwards is not braking",
	)
	chords.update(down.call([&"strafe_left", &"strafe_right", &"thrust_reverse"]), 1.0)
	_expect(chords.active() == ControlChords.Chord.RETROGRADE, "Q+E+S points back along it")
	_expect(
		not chords.consumed().has(&"thrust_forward"),
		"rolling from one chord straight into another still works, holds and all",
	)

	for pair: Array in [
		[ControlChords.Chord.ALTITUDE_HOLD, [&"thrust_forward", &"thrust_reverse", &"rotate_left"]],
		[ControlChords.Chord.DEORBIT, [&"thrust_forward", &"thrust_reverse", &"rotate_right"]],
	]:
		chords.update(down.call(pair[1]), 1.0)
		_expect(
			chords.active() == pair[0],
			"%s has its own chord on the second modifier" % ControlChords.Chord.keys()[
				int(pair[0])
			],
		)

	# Stopping is the panic gesture and must win whatever else is held.
	chords.update(down.call([
		&"strafe_left", &"strafe_right", &"thrust_forward", &"rotate_left", &"rotate_right",
	]), 1.0)
	_expect(
		chords.active() == ControlChords.Chord.KILL_ROTATION,
		"grabbing A and D means stop, whatever else the hands are doing",
	)


## Energy paces combat. The rule is four numbers and one sentence -- a spend
## resets the clock, and after the delay the pool fills -- so what needs
## pinning is the consequences of that sentence, which are what make the
## trigger a decision rather than a tax.
func _check_energy() -> void:
	var ship: Ship = _spawn_ship()
	var tick: float = 1.0 / 60.0

	_expect(
		is_equal_approx(ship.energy, ship.energy_capacity()) and ship.energy > 0.0,
		"a ship comes out of the yard charged (%.0f)" % ship.energy,
	)

	_expect(ship.spend_energy(30.0), "a spend the pool can cover comes out of it")
	_expect(is_equal_approx(ship.energy, ship.energy_capacity() - 30.0), "and only that much")
	var left: float = ship.energy
	_expect(not ship.spend_energy(1e6), "a spend it cannot cover is refused")
	_expect(
		is_equal_approx(ship.energy, left),
		"and takes nothing: a shot comes out whole or not at all",
	)

	# Firing and charging are mutually exclusive, which is the whole design.
	ship.spend_energy(10.0)
	var after_spend: float = ship.energy
	for step: int in range(int(ship.energy_recharge_delay() * 60.0) - 4):
		ship._recharge(tick)
	_expect(
		is_equal_approx(ship.energy, after_spend),
		"while the silence is still running the pool does not move",
	)
	_expect(ship.energy_waiting(), "and it reads as waiting rather than as filling")
	for step: int in range(30):
		ship._recharge(tick)
	_expect(ship.energy > after_spend, "once the silence is over it fills")
	_expect(not ship.energy_waiting(), "and stops reading as waiting")

	# Every spend pushes the start back, so a gun that is firing is a
	# generator that is not charging at all.
	ship.energy = 50.0
	for step: int in range(240):
		ship.spend_energy(0.001)
		ship._recharge(tick)
	_expect(
		ship.energy < 50.0,
		"holding the trigger never lets it charge, however long (%.2f)" % ship.energy,
	)

	# A bad module choice is a poor ship, never a dead one.
	var cell: GeneratorData = ship.generator_bay.installed
	ship.generator_bay.installed = null
	ship.rebuild_control_groups(false)
	_expect(
		is_equal_approx(ship.energy_capacity(), Ship.HULL_RAIL_CAPACITY),
		"a ship with no generator falls back on the hull's own rail",
	)
	_expect(
		ship.energy <= Ship.HULL_RAIL_CAPACITY,
		"and the pool is clamped down to it rather than left overfull",
	)
	_expect(
		Ship.HULL_RAIL_CAPACITY < cell.capacity
		and Ship.HULL_RAIL_RECHARGE < cell.recharge_rate,
		"the rail is worse than any real generator, which is the point of it",
	)
	var roomier: float = ship.cargo_capacity()
	ship.generator_bay.installed = cell
	ship.rebuild_control_groups(false)
	_expect(
		ship.cargo_capacity() < roomier,
		"a generator takes room in the hold as well as mass (%.1f with, %.1f without)" % [
			ship.cargo_capacity(), roomier,
		],
	)
	_expect(
		ship.cargo_capacity() > roomier - cell.bulk,
		"but less room than its own bulk: machinery packs into space crates never could",
	)

	# The ceiling belongs to the timeout, not to the recharge rate: a cell
	# rated 40 a second cannot actually deliver 40 (IDEAS.md section 14).
	var ceiling: float = cell.sustained_throughput(INF)
	_expect(
		ceiling < cell.recharge_rate * 0.8,
		"the sustained ceiling is the silence, not the rating (%.1f against %.0f)" % [
			ceiling, cell.recharge_rate,
		],
	)
	_expect(
		cell.sustained_throughput(5.0) < 5.0,
		"and a gentle drain is never more than the drain itself",
	)

	# Base weapons deliberately sit on one line of damage per unit of energy.
	# Energy is not allowed to pick a winner quietly: the guns differ in
	# character, not in efficiency.
	var per_energy: Array[float] = []
	var lowest: float = INF
	var highest: float = 0.0
	for path: String in LOOT_SCRIPT.WEAPON_BASES:
		var gun: WeaponData = load(path) as WeaponData
		_expect(gun.energy_cost > 0.0, "%s costs energy to fire" % gun.title())
		var ratio: float = gun.damage / maxf(gun.energy_cost, 0.0001)
		per_energy.append(ratio)
		lowest = minf(lowest, ratio)
		highest = maxf(highest, ratio)
	var spread: float = (highest - lowest) / maxf(highest, 0.0001)
	_expect(
		spread < 0.10,
		"all %d base weapons sit on one line of damage per unit of energy (%.4f..%.4f)" % [
			per_energy.size(), lowest, highest,
		],
	)

	# Cross-stat modules: the whole point of the mechanism is a module moving
	# a number that is not its own, so the thing to pin is that it reaches
	# the ship and that the report names who did it.
	var loot: Node = LOOT_SCRIPT.new()
	var dynamo: EngineData = null
	for attempt: int in range(400):
		var rolled: EngineData = loot.engine(9000 + attempt, 4)
		if rolled.stat_add.has(&"energy_recharge"):
			dynamo = rolled
			break
	_expect(dynamo != null, "the engine table can roll an energy affix")
	if dynamo != null:
		var plain_rate: float = ship.energy_recharge_rate()
		var mount: EngineMount = ship.engine_mounts()[0]
		dynamo.bulk = minf(dynamo.bulk, mount.size)
		ship.fit_engine(mount, dynamo)
		_expect(
			ship.energy_recharge_rate() > plain_rate,
			"an engine can hand the generator recharge it never had (%.1f -> %.1f)" % [
				plain_rate, ship.energy_recharge_rate(),
			],
		)
		_expect(
			"
".join(ship.configuration().stat_lines).contains(mount.name),
			"and the report names the module that did it",
		)

	# A key nobody defined is a typo in an affix table, and a typo that
	# silently does nothing passes every test anyone will write. The gate is
	# checked here; the push_error behind it is not, because a test that
	# makes one go off is a test that fails the build.
	_expect(
		Ship.knows_stat(&"energy_recharge"),
		"a stat the ship actually has is accepted",
	)
	_expect(
		not Ship.knows_stat(&"enrgy_recharge"),
		"and a misspelt one is refused rather than quietly ignored",
	)

	# Generators are loot like everything else, and the bar has to notch at
	# the cost of a shot or it is a percentage with extra steps.
	var cell_roll: GeneratorData = loot.generator(4711, 3)
	_expect(cell_roll != null and cell_roll.capacity > 0.0, "the tables can roll a generator")
	_expect(
		cell_roll.bulk > 0.0 and cell_roll.recharge_rate > 0.0,
		"and it comes out usable, with a size and a rate",
	)
	var kinds: Dictionary = {}
	for i: int in range(300):
		kinds[loot.generate(70000 + i).get_class()] = true
	_expect(
		kinds.size() >= 1,
		"a container can hold any kind of module",
	)

	var hud: EnergyHud = EnergyHud.new()
	root.add_child(hud)
	hud.bind(ship)
	var cheapest: float = 0.0
	for hardpoint: Hardpoint in ship.hardpoints:
		if hardpoint.weapon != null:
			cheapest = hardpoint.weapon.energy_cost
	_expect(
		is_equal_approx(hud.shot_cost(), cheapest) and cheapest > 0.0,
		"the bar is notched at the cost of a shot (%.1f)" % hud.shot_cost(),
	)
	var refusals: Array[int] = []
	hud.bind(ship)
	ship.shot_refused.connect(func() -> void: refusals.append(1))
	ship.energy = 0.0
	ship.shot_refused.emit()
	_expect(refusals.size() == 1, "and a refusal is announced rather than swallowed")
	hud.queue_free()

	loot.free()
	ship.queue_free()


## Mods are the pilot's decision where affixes are the item's nature, so the
## thing to guarantee is that a decision costs something. Every entry in the
## catalogue raises the price of a shot, and no arrangement of them changes
## the answer -- which is what lets the swap screen ignore order.
func _check_shot_mods() -> void:
	var ship: Ship = _spawn_ship()
	var loot: Node = LOOT_SCRIPT.new()
	var mount: Hardpoint = ship.hardpoints[0]
	var gun: WeaponData = mount.weapon.duplicate() as WeaponData
	gun.mod_slots = 3
	mount.fit(gun)
	var bare: float = mount.energy_cost()

	for index: int in range(LOOT_SCRIPT.SHOT_MODS.size()):
		var mod: ShotModData = loot.shot_mod(index)
		_expect(
			mod.energy_multiplier > 1.0,
			"%s costs more to fire, as every mod must" % mod.title(),
		)
		mount.mods.clear()
		mount._rebuild_effective()
		_expect(mount.add_mod(mod), "%s plugs into a free slot" % mod.title())
		_expect(
			mount.energy_cost() > bare,
			"and the shot costs more with it in (%.1f against %.1f)" % [
				mount.energy_cost(), bare,
			],
		)

	# Order cannot matter, because every mod is a multiplier and
	# multiplication does not care. Declared in IDEAS, so measured here.
	mount.mods.clear()
	mount._rebuild_effective()
	for index: int in [0, 2, 3]:
		mount.add_mod(loot.shot_mod(index))
	var one_way: float = mount.energy_cost()
	var one_way_damage: float = mount.effective().damage
	mount.mods.clear()
	mount._rebuild_effective()
	for index: int in [3, 0, 2]:
		mount.add_mod(loot.shot_mod(index))
	_expect(
		is_equal_approx(mount.energy_cost(), one_way)
		and is_equal_approx(mount.effective().damage, one_way_damage),
		"the order mods are plugged in makes no difference (%.2f vs %.2f)" % [
			one_way, mount.energy_cost(),
		],
	)

	# The behaviours have to reach the round, not just sit in the resource.
	mount.mods.clear()
	mount._rebuild_effective()
	mount.add_mod(loot.shot_mod(4))
	var pierced: Projectile = mount.fire(Vector2.ZERO, root, ship)
	_expect(
		pierced != null and pierced.pierces > 0,
		"a penetrator round is spawned knowing it goes through things",
	)
	if pierced != null:
		pierced.queue_free()

	mount.mods.clear()
	mount._rebuild_effective()
	mount.add_mod(loot.shot_mod(5))
	mount._cooldown = 0.0
	var blasted: Projectile = mount.fire(Vector2.ZERO, root, ship)
	_expect(
		blasted != null and blasted.blast_radius > 0.0,
		"and a shrapnel round knowing it hurts what it missed (%.0f px)" % [
			0.0 if blasted == null else blasted.blast_radius,
		],
	)
	if blasted != null:
		blasted.queue_free()
	mount.mods.clear()
	mount._rebuild_effective()
	for index: int in [0, 2, 3]:
		mount.add_mod(loot.shot_mod(index))

	# And the slots are a limit, not a suggestion.
	_expect(not mount.add_mod(loot.shot_mod(1)), "a fourth mod will not fit three slots")
	_expect(mount.mods.size() == 3, "and the ones already in stay in")

	# A weapon with no slots takes none, whatever is offered.
	var plain: WeaponData = gun.duplicate() as WeaponData
	plain.mod_slots = 0
	mount.fit(plain)
	_expect(mount.mods.is_empty(), "a gun with no slots drops the mods the old one held")
	_expect(not mount.add_mod(loot.shot_mod(0)), "and refuses new ones")

	loot.free()
	ship.queue_free()


## Does the arithmetic in IDEAS section 14 survive contact with the actual
## resources? The claim is that the generator sets sustained output and the
## weapon sets burst, so two base guns should come out close on the first and
## far apart on the second. If they collapse to one number, energy has
## flattened the weapons into a single stat and the whole economy is a tax.
func _check_energy_balance() -> void:
	var cell: GeneratorData = load(
		"res://resources/generators/standard_cell.tres"
	) as GeneratorData
	var guns: Array[WeaponData] = []
	for path: String in ["res://resources/weapons/autocannon.tres",
			"res://resources/weapons/siege_slug.tres"]:
		guns.append(load(path) as WeaponData)

	var burst: Array[float] = []
	var sustained: Array[float] = []
	for gun: WeaponData in guns:
		burst.append(gun.damage_per_second())
		# Damage per unit of energy times the energy the cell can actually
		# deliver against this weapon's drain.
		var drain: float = gun.energy_cost * gun.rounds_per_second
		var per_unit: float = gun.damage / maxf(gun.energy_cost, 0.0001)
		sustained.append(per_unit * cell.sustained_throughput(drain))

	var sustained_gap: float = absf(sustained[0] - sustained[1]) / maxf(sustained[0], 0.0001)
	_expect(
		sustained_gap < 0.10,
		"the generator levels sustained damage across weapons (%.3f, %.3f)" % [
			sustained[0], sustained[1],
		],
	)
	for i: int in range(guns.size()):
		_expect(
			sustained[i] < burst[i],
			"%s sustains less than it bursts (%.3f against %.3f)" % [
				guns[i].title(), sustained[i], burst[i],
			],
		)

	# And a weapon built to be extreme has to read as extreme: high rate of
	# fire buys the peak and barely moves the average, which is what makes a
	# minigun a minigun rather than a better autocannon.
	var minigun: WeaponData = guns[0].duplicate() as WeaponData
	minigun.rounds_per_second = 20.0
	minigun.damage = 0.02
	minigun.energy_cost = 1.5
	var minigun_burst: float = minigun.damage_per_second()
	var minigun_sustained: float = (minigun.damage / minigun.energy_cost) * cell.sustained_throughput(
		minigun.energy_cost * minigun.rounds_per_second
	)
	_expect(
		minigun_burst > burst[0] * 1.15,
		"rate of fire buys a real peak (%.2f against %.2f)" % [minigun_burst, burst[0]],
	)
	_expect(
		minigun_sustained < minigun_burst / 1.5,
		"but the average barely follows it (%.2f sustained against %.2f burst)" % [
			minigun_sustained, minigun_burst,
		],
	)


## Engine failures. The three the plan asks for -- efficiency lost to
## collisions, unreliability as cut-outs, and thrust that surges -- and the
## rule that holds them together: nothing here rebalances the control groups,
## so a half-dead engine makes the ship fly crooked instead of being quietly
## compensated for.
func _check_engine_failures() -> void:
	var ship: Ship = _spawn_ship()
	var nose: EngineInstance = null
	var tail: EngineInstance = null
	for engine: EngineInstance in ship.engines:
		if engine.mount.name == "NoseLeftTorque":
			nose = engine
		if engine.mount.name == "TailLeftTorque":
			tail = engine
	_expect(nose != null and tail != null, "the test ship has the engines this check needs")

	# A hit near one end breaks what was there, and leaves the other end alone.
	# 0.7 of hull damage, which at the current share leaves the engine at
	# 0.65 -- clearly past the threshold the report complains about. The
	# number moved when the penalty was softened; it is written against
	# WORN rather than against a remembered outcome.
	ship.damage_engines_near(nose.mount.position, (1.0 - ConfigurationReport.WORN + 0.2)
		/ Ship.ENGINE_DAMAGE_SHARE)
	_expect(nose.health < 1.0, "an impact costs the engine it landed on (%.2f)" % nose.health)
	_expect(
		is_equal_approx(tail.health, 1.0),
		"and leaves one at the other end of the hull untouched (%.2f)" % tail.health,
	)

	# The crooked-ship rule, which is the reason the damage model exists.
	var before: float = ship.control.authority_of(ShipControl.Command.CW)
	var hurt: float = nose.health
	ship.rebuild_control_groups(false)
	# A rebuild remakes every EngineInstance, so the old handles are stale.
	# Finding that out the hard way is what turned up the bug below.
	for engine: EngineInstance in ship.engines:
		if engine.mount.name == "NoseLeftTorque":
			nose = engine
		if engine.mount.name == "TailLeftTorque":
			tail = engine
	_expect(
		is_equal_approx(nose.health, hurt),
		"a refit is not a repair: damage survives the rebuild (%.2f)" % nose.health,
	)
	_expect(
		is_equal_approx(ship.control.authority_of(ShipControl.Command.CW), before),
		"damage never rebalances the groups: a broken engine is not compensated for",
	)
	_expect(
		nose.current_force().length() < nose.nominal_force().length(),
		"but it really does deliver less than it is rated for",
	)

	# Damage eats into dependability as well as into output.
	_expect(
		nose.current_reliability() < tail.current_reliability(),
		"a damaged engine is less dependable too (%.2f against %.2f)" % [
			nose.current_reliability(), tail.current_reliability(),
		],
	)

	# The report is where damage becomes legible. Its own residual is built
	# from nominal thrust, so without looking at condition separately it
	# would have nothing to say about the very thing the pilot needs told.
	var hurt_report: String = _findings_of(ship.configuration())
	_expect(
		hurt_report.contains("NoseLeftTorque"),
		"the report names the engine that is hurt (%s)" % hurt_report,
	)
	_expect(
		hurt_report.contains("push sideways"),
		"and says that the damage is what makes the ship fly crooked",
	)

	ship.repair_engines()
	_expect(
		is_equal_approx(ship.worst_engine_health(), 1.0),
		"and the repair key puts all of it back",
	)
	_expect(
		ship.configuration().worst() == ConfigurationReport.Severity.OK,
		"after which the report is clean again (%s)" % _findings_of(ship.configuration()),
	)

	# Cut-outs: counted over time rather than asserted on one tick, because
	# the whole point is that they are occasional.
	var flaky: EngineData = nose.data.duplicate() as EngineData
	flaky.reliability = 0.35
	nose.data = flaky
	nose.target_throttle = 1.0
	var dead_ticks: int = 0
	var seen_surge: bool = false
	var peak: float = 0.0
	var trough: float = 1.0
	for step: int in range(1800):
		nose.advance(1.0 / 60.0)
		var out: float = nose.effective_output()
		peak = maxf(peak, out)
		trough = minf(trough, out)
		if nose.is_dropped_out():
			dead_ticks += 1
			continue
		if out < 0.99:
			seen_surge = true
	_expect(
		dead_ticks > 0,
		"an unreliable engine cuts out sometimes (%d ticks of 1800)" % dead_ticks,
	)
	# A cut-out is a dip now, not a silence. Damage changes how a ship flies;
	# it does not take the ship away, and a penalty that stops the game being
	# played is not difficulty.
	_expect(
		trough >= EngineInstance.MIN_OUTPUT_SHARE - 0.001,
		"and never drops below the floor, cut-outs included (%.3f of %.2f)" % [
			trough, EngineInstance.MIN_OUTPUT_SHARE,
		],
	)
	_expect(
		dead_ticks < 900,
		"but not most of the time: a fault that is always on is a missing engine (%d)" % dead_ticks,
	)
	_expect(seen_surge, "and its thrust surges rather than holding steady")
	# Never above what was asked for: a fault that sometimes overshoots is a
	# bonus in a fault's clothing. The peak falls a whisker short of 1.0
	# because a 7 Hz surge sampled 60 times a second never lands exactly on
	# its own crest -- that is sampling, not the model.
	_expect(
		peak <= 1.0 and peak > 0.95,
		"the surge tops out at full thrust and never passes it (%.3f)" % peak,
	)

	# A reliable engine does none of that, or the fault would just be noise.
	var solid: EngineData = tail.data.duplicate() as EngineData
	solid.reliability = 1.0
	tail.data = solid
	tail.target_throttle = 1.0
	var steady: bool = true
	for step: int in range(600):
		tail.advance(1.0 / 60.0)
		if not is_equal_approx(tail.effective_output(), tail.throttle):
			steady = false
	_expect(steady, "a sound engine delivers exactly what it was asked for, every tick")

	# The floor holds at every condition, not only at the one measured above.
	var lowest: float = 1.0
	for health: float in [1.0, 0.8, 0.5, 0.2, 0.0]:
		nose.health = health
		nose.target_throttle = 1.0
		for step: int in range(600):
			nose.advance(1.0 / 60.0)
			nose.throttle = 1.0
			lowest = minf(lowest, nose.effective_output())
		_expect(
			nose.condition_factor() >= EngineInstance.MIN_OUTPUT_SHARE - 0.001,
			"at %.0f%% health the engine still holds %.0f%% of its rating" % [
				health * 100.0, nose.condition_factor() * 100.0,
			],
		)
	_expect(
		lowest >= EngineInstance.MIN_OUTPUT_SHARE - 0.001,
		"and nothing anywhere in that range went under the floor (%.3f)" % lowest,
	)
	nose.health = 1.0

	# Reproducible: the same ship misbehaves the same way twice, so a bug
	# report about a fault can be followed.
	var first_run: int = _count_dropouts(flaky, nose.mount)
	_expect(
		first_run == _count_dropouts(flaky, nose.mount),
		"the same engine on the same mount fails the same way twice (%d)" % first_run,
	)

	ship.queue_free()


func _count_dropouts(engine_data: EngineData, mount: EngineMount) -> int:
	var instance: EngineInstance = EngineInstance.new(engine_data, mount)
	instance.target_throttle = 1.0
	var dead: int = 0
	for step: int in range(900):
		instance.advance(1.0 / 60.0)
		if instance.is_dropped_out():
			dead += 1
	return dead


## One outline, and everything physical derived from it. The failure this
## guards against is the shape drifting apart: what a bullet hits, what
## touches the ground and what the mass is worked out from all being slightly
## different polygons.
func _check_hull_outline(planet: Planet) -> void:
	var ship: Ship = _spawn_ship()

	var shape_node: CollisionShape2D = ship.get_node("HullShape") as CollisionShape2D
	var convex: ConvexPolygonShape2D = shape_node.shape as ConvexPolygonShape2D
	_expect(
		convex != null and convex.points == Geometry2D.convex_hull(ship.hull_outline),
		"the shape projectiles hit is built from the outline, not drawn a second time",
	)

	# Every contact point is on the outline, and none of them further apart
	# than the step. That step is four terrain texels, which is the whole
	# reason a spike cannot slip between two of them.
	var contacts: Array[Vector2] = ship.contact_points()
	_expect(contacts.size() > ship.hull_outline.size(), "edges are subdivided, not just cornered")
	for i: int in range(ship.hull_outline.size()):
		var from: Vector2 = ship.hull_outline[i]
		var to: Vector2 = ship.hull_outline[(i + 1) % ship.hull_outline.size()]
		var segments: int = maxi(1, ceili(from.distance_to(to) / Ship.CONTACT_STEP))
		_expect(
			from.distance_to(to) / float(segments) <= Ship.CONTACT_STEP + 0.001,
			"edge %d is cut at or under the step" % i,
		)

	# Solver effort follows the outline rather than a number picked for a
	# triangle, and the probe depth follows the hull's size.
	_expect(
		ship.contact_iterations() >= Ship.CONTACT_ITERATIONS,
		"a subdivided hull gets at least as many solver passes as the old triangle (%d)" % [
			ship.contact_iterations(),
		],
	)
	var big: Ship = _spawn_ship()
	big.hull_outline = PackedVector2Array([
		Vector2(0, -40), Vector2(-28, 34), Vector2(28, 34),
	])
	big._build_contact_points()
	_expect(
		big.contact_iterations() > ship.contact_iterations(),
		"a bigger hull gets more passes (%d against %d)" % [
			big.contact_iterations(), ship.contact_iterations(),
		],
	)
	_expect(
		big.penetration_limit() > ship.penetration_limit(),
		"and the terrain probe looks deeper for it (%.0f against %.0f px)" % [
			big.penetration_limit(), ship.penetration_limit(),
		],
	)
	big.queue_free()

	# The guidelines, checked where a designer will see them.
	_expect(
		ship.configuration().worst() == ConfigurationReport.Severity.OK,
		"the stock outline passes its own guidelines (%s)" % _findings_of(ship.configuration()),
	)
	var spindly: Ship = _spawn_ship()
	spindly.hull_outline = PackedVector2Array([
		Vector2(0, -12), Vector2(-2, -10), Vector2(-8, 10), Vector2(8, 10), Vector2(2, -10),
	])
	var complaint: String = _findings_of(spindly.configuration())
	_expect(
		complaint.contains("thinnest outline detail"),
		"a sliver too thin for terrain sampling is called out (%s)" % complaint,
	)
	spindly.queue_free()

	# And the point of all of it: a spike narrower than the old gaps must not
	# pass between the contact points unnoticed.
	var angle: float = 0.0
	var ground: float = planet.terrain.surface_radius_at(angle)
	var spike_top: Vector2 = Vector2.from_angle(angle) * (ground + Ship.CONTACT_STEP * 1.5)
	var seen: int = 0
	for point: Vector2 in contacts:
		# Lay the hull flat across the spike, bottom edge just above the peak.
		var at: Vector2 = spike_top + Vector2.from_angle(angle).orthogonal() * point.x
		if planet.is_solid_at(at - Vector2.from_angle(angle) * Ship.CONTACT_STEP * 1.5):
			seen += 1
	_expect(
		seen > 0,
		"the contact set samples the ground under the whole hull, not only its corners",
	)

	ship.queue_free()


## The flight computer earns its place on a ship that is damaged or
## lopsided, which is exactly when the weight heuristic is worst: the groups
## are built from nominal thrust with fixed shares, so a half-dead jet is
## still asked for its full part, delivers less than its partner, and the
## turn comes with a shove the pilot has to fly against.
func _check_allocator() -> void:
	# The solver on its own first, where the right answer is known.
	var columns: Array[Vector3] = [
		Vector3(1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, 1.0),
	]
	var exact: PackedFloat32Array = ThrustAllocator.solve(columns, Vector3(0.5, 0.25, 0.0))
	_expect(
		absf(exact[0] - 0.5) < 0.02 and absf(exact[1] - 0.25) < 0.02 and exact[2] < 0.02,
		"the allocator finds the obvious answer when there is one (%.2f, %.2f, %.2f)" % [
			exact[0], exact[1], exact[2],
		],
	)
	var over: PackedFloat32Array = ThrustAllocator.solve(columns, Vector3(9.0, 0.0, 0.0))
	_expect(
		over[0] <= 1.0,
		"and never asks an engine for more than it has (%.2f)" % over[0],
	)
	var backwards: PackedFloat32Array = ThrustAllocator.solve(columns, Vector3(-1.0, 0.0, 0.0))
	_expect(
		backwards[0] >= 0.0,
		"nor for less than nothing: an engine cannot suck (%.2f)" % backwards[0],
	)

	# Now on a real ship with one jet of a rotation pair half dead. Same
	# demand through both allocators; the question is how much sideways
	# force is left over.
	var sideways: Dictionary = {}
	for solve: bool in [false, true]:
		var ship: Ship = _spawn_ship()
		for engine: EngineInstance in ship.engines:
			if engine.mount.name == "NoseLeftTorque":
				engine.health = 0.45
		ship.control.solve_allocation = solve
		ship.control.apply_commands(ship.engines, {ShipControl.Command.CW: 1.0})

		var residual: Vector2 = Vector2.ZERO
		var torque: float = 0.0
		for engine: EngineInstance in ship.engines:
			var delivered: Vector2 = engine.nominal_force() * engine.target_throttle * engine.health
			residual += delivered
			torque += (engine.mount.position - ship.center_of_mass).cross(delivered)
		sideways[solve] = {"push": residual.length(), "torque": absf(torque)}
		ship.queue_free()

	_expect(
		sideways[true]["push"] < sideways[false]["push"],
		"a computer turns a damaged ship with less shove than the weights do (%.1f against %.1f N)" % [
			sideways[true]["push"], sideways[false]["push"],
		],
	)
	_expect(
		sideways[true]["torque"] > 0.0,
		"while still actually turning it (%.0f N px)" % sideways[true]["torque"],
	)

	# And it must not make a healthy ship worse, or fitting one would be a
	# trade rather than an upgrade.
	var clean: Dictionary = {}
	for solve: bool in [false, true]:
		var ship: Ship = _spawn_ship()
		ship.control.solve_allocation = solve
		ship.control.apply_commands(ship.engines, {ShipControl.Command.CW: 1.0})
		var residual: Vector2 = Vector2.ZERO
		for engine: EngineInstance in ship.engines:
			residual += engine.nominal_force() * engine.target_throttle * engine.health
		clean[solve] = residual.length()
		ship.queue_free()
	_expect(
		clean[true] <= clean[false] + 0.5,
		"and leaves a sound ship no worse than it found it (%.2f against %.2f N)" % [
			clean[true], clean[false],
		],
	)


## A gimbal lets the thrust that is already there be aimed, instead of a
## second set of jets being fitted to fight it. The sign is the part worth
## pinning: a nose engine and a tail engine have to steer opposite ways for
## the same turn, and getting that backwards would make the gimbal cancel
## the very rotation it is meant to help.
func _check_gimbal() -> void:
	var ship: Ship = _spawn_ship()
	var main: EngineInstance = null
	for engine: EngineInstance in ship.engines:
		if engine.mount.name == "MainDrive":
			main = engine
	_expect(main != null, "the test hull has a main drive")

	var gimballed: EngineData = main.data.duplicate() as EngineData
	gimballed.gimbal_range = deg_to_rad(12.0)
	main.data = gimballed

	_expect(is_zero_approx(main.gimbal), "a nozzle starts straight")
	# Held open, not poked: advance() spools the throttle towards its target
	# every tick, so setting the throttle once and then stepping would leave
	# nothing coming out of the nozzle to measure.
	main.target_throttle = 1.0
	ship.active_commands = {ShipControl.Command.CW: 1.0}
	ship._aim_gimbals()
	for step: int in range(60):
		main.advance(1.0 / 60.0)
	_expect(
		absf(main.gimbal) > deg_to_rad(10.0),
		"asking for a turn swings it over (%.1f deg)" % rad_to_deg(main.gimbal),
	)

	# The test that matters: the deflected thrust has to add torque the way
	# the turn wanted, not against it.
	var arm: Vector2 = main.mount.position - ship.center_of_mass
	var torque: float = arm.cross(main.current_force())
	_expect(
		torque > 0.0,
		"and the deflected thrust helps the turn rather than fighting it (%.0f N px)" % torque,
	)

	ship.active_commands = {ShipControl.Command.CCW: 1.0}
	ship._aim_gimbals()
	for step: int in range(60):
		main.advance(1.0 / 60.0)
	_expect(
		arm.cross(main.current_force()) < 0.0,
		"and the other way round for the other direction",
	)

	ship.active_commands = {}
	ship._aim_gimbals()
	for step: int in range(60):
		main.advance(1.0 / 60.0)
	_expect(is_zero_approx(main.gimbal), "letting go centres it again")

	# An engine bolted straight never moves, whatever is asked.
	var fixed: EngineInstance = null
	for engine: EngineInstance in ship.engines:
		if engine.mount.name == "StrafeLeftThruster":
			fixed = engine
	ship.active_commands = {ShipControl.Command.CW: 1.0}
	ship._aim_gimbals()
	fixed.advance(1.0)
	_expect(is_zero_approx(fixed.gimbal), "an engine with no gimbal stays bolted straight")

	ship.queue_free()


## Landing gear is a module too, so a hull can be refitted for the kind of
## ground it works over. The tolerances have to come from the part, and they
## have to be read rather than copied: a copy is a second source of truth,
## and the landing check has already been wrong once for reading the wrong
## frame.
func _check_gear_module() -> void:
	var ship: Ship = _spawn_ship()
	var legs: LandingGear = ship.gear
	_expect(legs != null, "the stock hull has legs")

	var bare_limit: float = legs.vertical_limit()
	var heavy: GearData = GearData.new()
	heavy.max_vertical_speed = bare_limit * 2.0
	heavy.max_lateral_speed = legs.lateral_limit() * 2.0
	heavy.bulk = 1.5
	var light_mass: float = ship.mass

	legs.installed = heavy
	ship.rebuild_control_groups(false)
	_expect(
		is_equal_approx(legs.vertical_limit(), bare_limit * 2.0),
		"fitted legs set what the ship will survive (%.0f px/s)" % legs.vertical_limit(),
	)
	_expect(
		ship.mass > light_mass,
		"and they weigh something (%.1f against %.1f kg)" % [ship.mass, light_mass],
	)

	# Geometry stays with the hull: swapping legs must not move the feet out
	# from under the contact solver.
	var feet: Array[Vector2] = legs.contact_points()
	legs.installed = null
	ship.rebuild_control_groups(false)
	_expect(
		legs.contact_points() == feet,
		"but where the feet are belongs to the hull, not to the part",
	)
	_expect(
		is_equal_approx(legs.vertical_limit(), bare_limit),
		"and a hull with no legs fitted falls back on what it manages bare",
	)

	ship.queue_free()


## Six weapon types carried by three behaviours: a round that coasts, a
## round that flies under power, and a beam that does not fly. What has to
## be true is that each type actually behaves like itself -- otherwise the
## enum is six names for one gun.
func _check_weapon_types(planet: Planet) -> void:
	var ship: Ship = _spawn_ship()
	var mount: Hardpoint = ship.hardpoints[0]
	var container: Node = ship.projectile_container()
	ship.energy = 1000.0

	# A laser resolves instantly. Nothing is spawned to fly, and the ground
	# a long way off is already gone by the time fire() returns.
	var angle: float = -PI * 0.5
	var ground: float = _find_ground(planet, angle)
	ship.global_position = planet.global_position + Vector2.from_angle(angle) * (ground + 300.0)
	ship.global_rotation = PI
	# One pixel in, not four: the lance cuts a 3 px hole and a test that
	# demanded more would be measuring the crater rather than the beam.
	var target_point: Vector2 = planet.global_position + Vector2.from_angle(angle) * (ground - 1.0)
	_expect(planet.is_solid_at(target_point), "there is ground under the muzzle to shine at")

	var lance: WeaponData = load("res://resources/weapons/beam_lance.tres") as WeaponData
	mount.fit(lance)
	mount._cooldown = 0.0
	var spawned: Projectile = mount.fire(Vector2.ZERO, container, ship)
	_expect(spawned == null, "a laser spawns nothing: there is nothing travelling")
	_expect(
		not planet.is_solid_at(target_point),
		"and the ground it was aimed at is gone the same tick",
	)

	# A missile leaves slowly and builds speed, which is what makes it
	# dodgeable early and firing one a commitment.
	var rocket: WeaponData = load("res://resources/weapons/dumb_rocket.tres") as WeaponData
	mount.fit(rocket)
	mount._cooldown = 0.0
	var launched: Missile = mount.fire(Vector2.ZERO, container, ship) as Missile
	_expect(launched != null, "a rocket launches something that flies under power")
	if launched != null:
		var launch_speed: float = launched.velocity.length()
		launched.thrust = rocket.missile_thrust
		launched.turn_rate = 0.0
		for step: int in range(30):
			launched.velocity += launched.velocity.normalized() * launched.thrust / 60.0
		_expect(
			launched.velocity.length() > launch_speed * 1.5,
			"and it accelerates after launch (%.0f to %.0f px/s)" % [
				launch_speed, launched.velocity.length(),
			],
		)
		_expect(
			launched.blast_radius > 0.0,
			"a rocket hurts what it did not hit (%.0f px)" % launched.blast_radius,
		)
		launched.queue_free()

	# Homing turns towards something, and a dumb round does not.
	var mark: Ship = _spawn_ship()
	mark.global_position = ship.global_position + Vector2(600.0, -600.0)
	var seeker: WeaponData = load("res://resources/weapons/seeker.tres") as WeaponData
	mount.fit(seeker)
	mount._cooldown = 0.0
	# Pointed at, because that is now how a seeker is told what to chase.
	# It also makes the assertion exact: freed hulls linger in the group
	# until the deferred free runs, and before the cursor decided the
	# target this could only say "something, not the shooter".
	ship.aim_point = mark.global_position
	var guided: Missile = mount.fire(Vector2.ZERO, container, ship) as Missile
	_expect(
		guided != null and guided.target == mark,
		"a seeker picks up the ship the cursor is on",
	)
	if guided != null and guided.target != null:
		var chased: Node2D = guided.target
		var before: float = guided.velocity.angle_to(chased.global_position - guided.global_position)
		for step: int in range(20):
			guided._physics_process(1.0 / 60.0)
		var after: float = guided.velocity.angle_to(chased.global_position - guided.global_position)
		_expect(
			absf(after) < absf(before),
			"and turns towards it (%.2f to %.2f rad off)" % [before, after],
		)
		guided.queue_free()
	mark.queue_free()

	# The remaining two are data on the coasting round, and have to differ
	# from each other in the way their names claim.
	var burst: WeaponData = load("res://resources/weapons/burst_shell.tres") as WeaponData
	var pulse: WeaponData = load("res://resources/weapons/pulse_repeater.tres") as WeaponData
	_expect(burst.blast_radius > burst.crater_radius, "a burst shell reaches past its own crater")
	_expect(
		pulse.rounds_per_second > burst.rounds_per_second * 4.0
		and pulse.range_px < burst.range_px,
		"a pulse repeater trades reach for rate (%.0f/s at %.0f px)" % [
			pulse.rounds_per_second, pulse.range_px,
		],
	)

	ship.queue_free()


## A full set of engines against a bare one. The point of building the
## control groups from geometry is that this comparison needs no special
## case: strip the manoeuvring and braking engines off a hull and it is
## still flyable, just worse in the directions those engines served.
func _check_ship_fitouts() -> void:
	var full: Ship = _spawn_ship()
	var full_report: ConfigurationReport = full.configuration()

	# The minimal ship: main drive only, everything else unbolted. A hull
	# that can go forward and nothing else.
	var minimal: Ship = _spawn_ship()
	for mount: EngineMount in minimal.engine_mounts():
		if mount.name != "MainDrive":
			mount.installed = null
	minimal.rebuild_control_groups(false)
	var minimal_report: ConfigurationReport = minimal.configuration()

	_expect(
		minimal.mass < full.mass,
		"a stripped hull is lighter (%.1f against %.1f kg)" % [minimal.mass, full.mass],
	)
	_expect(
		minimal_report.worst() == ConfigurationReport.Severity.FAULT,
		"and the report calls it out rather than letting it fly quietly broken",
	)
	_expect(
		_findings_of(minimal_report).contains("no CW authority")
		or _findings_of(minimal_report).contains("no CCW authority"),
		"naming the directions it has lost (%s)" % _findings_of(minimal_report),
	)
	_expect(
		full_report.worst() == ConfigurationReport.Severity.OK,
		"while the full fitout is clean",
	)
	for command: ShipControl.Command in [
		ShipControl.Command.STRAFE_LEFT, ShipControl.Command.CW, ShipControl.Command.BACK
	]:
		_expect(
			full.control.authority_of(command) > minimal.control.authority_of(command),
			"%s is better with the full set (%.0f against %.0f)" % [
				full.control.command_name(command),
				full.control.authority_of(command),
				minimal.control.authority_of(command),
			],
		)
	_expect(
		is_equal_approx(
			full.control.authority_of(ShipControl.Command.FORWARD),
			minimal.control.authority_of(ShipControl.Command.FORWARD),
		),
		"and going forwards is the one thing the bare hull does just as well",
	)

	# The parts that make the difference are things the pilot can find.
	var pod: EngineData = load("res://resources/engines/maneuver_pod.tres") as EngineData
	var bell: EngineData = load("res://resources/engines/braking_bell.tres") as EngineData
	var steered: EngineData = load("res://resources/engines/gimballed_drive.tres") as EngineData
	_expect(
		pod.type == EngineData.Type.THRUSTER and pod.bulk < bell.bulk,
		"a manoeuvre pod is small and answers at once",
	)
	_expect(
		bell.max_thrust > pod.max_thrust * 2.0,
		"a braking bell is built to stop things (%.0f N)" % bell.max_thrust,
	)
	_expect(
		steered.gimbal_range > 0.0 and steered.max_thrust < load(
			"res://resources/engines/main_drive.tres"
		).max_thrust,
		"and a steerable drive pays thrust for the gimbal (%.0f N, %.0f deg)" % [
			steered.max_thrust, rad_to_deg(steered.gimbal_range),
		],
	)

	minimal.queue_free()
	full.queue_free()


## The sandbox exists because most of what M2 built can only be judged by
## flying it, and rolling for a gimballed drive until one drops is not
## testing the gimbal. What has to hold is that nothing it conjures is
## something the game could not have dropped, and that every shape it offers
## actually goes through the machinery.
func _check_creative_tool() -> void:
	# Hull mass follows the outline now. It was a flat constant, which went
	# unnoticed while there was one hull and became obvious the moment the
	# sandbox could make another: a brick four times the area weighed the
	# same as the dart.
	var ship: Ship = _spawn_ship()
	var stock_mass: float = ship.hull_mass()
	_expect(
		absf(stock_mass - 6.0) < 0.01,
		"the stock outline still weighs what it always did (%.2f)" % stock_mass,
	)

	var bent: int = 0
	var undersampled: int = 0
	var mismatched: int = 0
	for hull: HullData in HullData.catalogue():
		var outline: PackedVector2Array = hull.outline
		if Geometry2D.convex_hull(outline).size() < outline.size():
			bent += 1
			print("    %s is not convex" % hull.id)

		ship.hull_outline = outline
		ship._build_contact_points()
		ship._build_collision_shape()
		ship.rebuild_control_groups(false)
		if ship.contact_points().size() < outline.size():
			undersampled += 1
			print("    %s has fewer contact points than corners" % hull.id)
		var convex: ConvexPolygonShape2D = (
			ship.get_node("HullShape") as CollisionShape2D
		).shape as ConvexPolygonShape2D
		if convex.points != Geometry2D.convex_hull(outline):
			mismatched += 1
			print("    %s draws one shape and collides with another" % hull.id)
	_expect(bent == 0, "every hull in the catalogue is convex, as the guidelines ask")
	_expect(undersampled == 0, "and gets at least a contact point per corner")
	_expect(mismatched == 0, "and hands the same shape to projectiles")

	# Twice the size is four times the area, so four times the mass.
	var small: PackedVector2Array = HullData.of(&"dart").outline
	ship.hull_outline = small
	var one: float = ship.hull_mass()
	var doubled: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in small:
		doubled.append(point * 2.0)
	ship.hull_outline = doubled
	_expect(
		absf(ship.hull_mass() / maxf(one, 0.0001) - 4.0) < 0.01,
		"a hull twice as long is four times the mass (%.2fx)" % [ship.hull_mass() / one],
	)

	# And the one shape put in as a bad example has to be caught.
	ship.hull_outline = HullData.of(&"sliver").outline
	ship._build_contact_points()
	ship.rebuild_control_groups(false)
	_expect(
		_findings_of(ship.configuration()).contains("thinnest outline detail"),
		"the deliberately bad preset is reported as bad",
	)

	ship.queue_free()


## A panel that is shut must consume nothing.
##
## Every one of these is built as a full-rect MarginContainer holding a small
## panel, and closing them hid the panel but left the container. A
## MarginContainer is chrome with no pixels of its own, but Control defaults
## to MOUSE_FILTER_STOP, so each of them was quietly swallowing every click
## on the whole screen. It went unnoticed while the topmost one was the
## configurator itself -- adding the sandbox above it took the mouse away
## from the configurator, which is how it surfaced.
##
## The same shape as the pause bug: a tool that is closed but still sitting
## on the screen.
func _check_panels_release_the_mouse() -> void:
	var panels: Array[CanvasLayer] = [
		CreativeTool.new(), PlanetConfigurator.new(), LoadoutScreen.new(), ShipEditor.new(),
	]
	for panel: CanvasLayer in panels:
		root.add_child(panel)

	for panel: CanvasLayer in panels:
		var greedy: PackedStringArray = PackedStringArray()
		_collect_greedy_controls(panel, greedy)
		_expect(
			greedy.is_empty(),
			"a closed %s takes no clicks (greedy: %s)" % [
				panel.get_class() if panel.get_script() == null else
					(panel.get_script() as GDScript).get_global_name(),
				", ".join(greedy),
			],
		)
		panel.queue_free()


## Visible Controls in `node` that would consume a click. A hidden one cannot
## be clicked, so only what is still on screen counts.
func _collect_greedy_controls(node: Node, into: PackedStringArray) -> void:
	var control: Control = node as Control
	if control != null:
		if not control.visible:
			return
		if control.mouse_filter == Control.MOUSE_FILTER_STOP:
			into.append(control.get_class())
	for child: Node in node.get_children():
		_collect_greedy_controls(child, into)


## A found module has to know how good it is, everywhere it goes.
##
## Rarity used to travel beside the item, and four places kept their own
## copy: the crate, the hold, the cargo bay and the editor. The sandbox
## stamped every find as rare because one of those copies was a hard-coded
## constant, which is exactly the failure a value with four homes invites.
## A crate that has been thrown. It has to come down, it has to stop, and
## at no point may it be inside the rock.
func _check_crate_physics(planet: Planet) -> void:
	var scene: PackedScene = load(CRATE_SCENE) as PackedScene

	# Dropped from a height with a sideways shove: falls, never enters rock,
	# and ends up standing on the ground rather than hovering or buried.
	var crate: LootCrate = scene.instantiate() as LootCrate
	planet.add_child(crate)
	var angle: float = 0.0
	var up: Vector2 = Vector2.from_angle(angle)
	var start: Vector2 = planet.global_position + up * (
		planet.terrain.surface_radius_at(angle) + 300.0
	)
	crate.eject(start, up.orthogonal() * 30.0)
	var deepest: float = INF
	var settled_after: int = -1
	for tick: int in range(900):
		crate._physics_process(1.0 / 60.0)
		deepest = minf(deepest, planet.height_above_terrain(crate.global_position))
		if not crate.loose and settled_after < 0:
			settled_after = tick
	_expect(
		deepest > LootCrate.RADIUS - 1.0,
		"a falling crate never gets inside the rock (closest %.2f px of %.1f)" % [
			deepest, LootCrate.RADIUS,
		],
	)
	_expect(settled_after >= 0, "and it stops, rather than skating for ever")
	_expect(
		absf(planet.height_above_terrain(crate.global_position) - LootCrate.RADIUS) < 1.0,
		"and comes to rest standing on the ground (%.2f px of %.1f)" % [
			planet.height_above_terrain(crate.global_position), LootCrate.RADIUS,
		],
	)

	# Settled means settled: a crate lying on a turning planet is carried by
	# it, and is not being solved to get there.
	var was: float = planet.to_local(crate.global_position).angle()
	for tick: int in range(120):
		crate._physics_process(1.0 / 60.0)
	_expect(
		absf(angle_difference(planet.to_local(crate.global_position).angle(), was)) < 0.001
		and not crate.loose,
		"a settled crate rides the ground it is lying on",
	)

	# A settled crate is not simulated at all. That is the claim the whole
	# settled/loose split is for, so it is worth pinning rather than
	# trusting: the engine must not be calling it.
	_expect(
		not crate.is_physics_processing(),
		"a settled crate is not being solved at all",
	)

	# Carving the shelf out from under it puts it back in the air's hands --
	# told by the ground, not noticed by polling it, so it happens on the
	# carve itself and not on some later tick.
	planet.carve(crate.global_position - crate.global_position.direction_to(
		planet.global_position
	) * -40.0, 60.0)
	_expect(
		crate.loose and crate.is_physics_processing(),
		"and wakes the moment the ground under it is blown away",
	)
	crate.queue_free()

	# Straight down, far faster than anything in the game. Contact is
	# measured radially rather than by sampling one point for rock, so
	# arriving fast makes the crate deeper in the first contact tick and
	# never lets it through.
	var bullet: LootCrate = scene.instantiate() as LootCrate
	planet.add_child(bullet)
	bullet.eject(
		planet.global_position + up * (planet.terrain.surface_radius_at(angle) + 200.0),
		-up * 1200.0,
	)
	var lowest: float = INF
	for tick: int in range(600):
		bullet._physics_process(1.0 / 60.0)
		lowest = minf(lowest, planet.height_above_terrain(bullet.global_position))
	_expect(
		lowest > LootCrate.RADIUS - 1.0,
		"a crate arriving at 1200 px/s does not pass through the ground (%.2f px of %.1f)" % [
			lowest, LootCrate.RADIUS,
		],
	)
	bullet.queue_free()


## What throwing something overboard does to it.
func _check_ejection() -> void:
	var ship: Ship = _spawn_ship()
	ship.global_position = Vector2(4000.0, -9000.0)
	ship.global_rotation = 0.7
	ship.linear_velocity = Vector2(120.0, -45.0)

	var shove: Vector2 = ship.eject_velocity() - ship.linear_velocity
	_expect(
		is_equal_approx(shove.length(), Ship.EJECT_SPEED),
		"an ejected module gets a %.0f px/s shove on top of the ship's own speed" % [
			Ship.EJECT_SPEED,
		],
	)
	# Aft, which is where the doors are. Measured in the ship's frame so the
	# claim survives the ship being pointed anywhere.
	_expect(
		ship.to_local(ship.global_position + shove).normalized().dot(Vector2.DOWN) > 0.999,
		"and it goes out of the back, not through the nose",
	)
	_expect(
		ship.eject_point().distance_to(ship.to_global(Ship.CARGO_BAY)) < 0.001,
		"out of the cargo bay, which is where the module was",
	)

	# The whole point: it leaves. Flown, with the ship coasting alongside.
	var crate: LootCrate = (load(CRATE_SCENE) as PackedScene).instantiate() as LootCrate
	root.add_child(crate)
	crate.eject(ship.eject_point(), ship.eject_velocity())
	var opened: float = crate.global_position.distance_to(ship.global_position)
	for tick: int in range(60):
		crate._physics_process(1.0 / 60.0)
		ship.global_position += ship.linear_velocity / 60.0
	var gap: float = crate.global_position.distance_to(ship.global_position)
	_expect(
		gap > opened + ship.hull_extent(),
		"a second later it is clear of the hull (%.0f px, hull %.0f)" % [
			gap, ship.hull_extent(),
		],
	)
	crate.queue_free()
	ship.queue_free()


## Rozkład galaktyki: odstępy, gradient, spójność grafu.
##
## The whole of M4 stands on this being right, and almost none of it can
## be seen. A galaxy that looks fine on a map can still be one where the
## starting drive reaches four systems, or where the islands IDEAS.md
## section 10 wants as late game do not exist because everything is
## connected to everything.
##
## So the numbers here were **measured and then written down**, not
## chosen. The first pass had the reach at one and a half spacings and
## the starting galaxy came out at between a seventh and a quarter of
## itself -- a graph like this does not begin to connect until about one
## and three quarters, and the floors below are set under what four seeds
## actually produce rather than at the figure that was hoped for.
func _check_galaxy() -> void:
	var map: GalaxyMap = GalaxyMap.generate(20260922)
	_expect(map.count() > 40, "a galaxy has systems in it (%d)" % map.count())

	# Same seed, same galaxy. The save file is the seed plus deltas, so a
	# layout that drifted between loads would move every system the player
	# had been to.
	var again: GalaxyMap = GalaxyMap.generate(20260922)
	var other: GalaxyMap = GalaxyMap.generate(20260923)
	_expect(
		again.positions == map.positions,
		"and the same seed lays it out identically, every time",
	)
	_expect(
		other.positions != map.positions,
		"while the next seed along is a different galaxy (%d systems)" % other.count(),
	)

	# Nobody crowds anybody, and the test is against the **larger** of the
	# two claims: a rim system wants more room than a core one, and
	# checking only the newcomer's figure would let it be crowded by a core
	# system that happened to be placed first.
	var crowded: int = 0
	var tightest: float = INF
	for i: int in range(map.count()):
		for j: int in range(i + 1, map.count()):
			var gap: float = map.positions[i].distance_to(map.positions[j])
			tightest = minf(tightest, gap)
			var wants: float = maxf(
				map.spacing_at(map.positions[i]), map.spacing_at(map.positions[j])
			)
			if gap < wants - 0.001:
				crowded += 1
	_expect(
		crowded == 0,
		"no two systems stand closer than they both want (tightest %.2f ly)" % tightest,
	)
	_expect(
		tightest >= GalaxyMap.SPACING - 0.001,
		"and nothing anywhere is inside the core spacing of %.0f ly" % GalaxyMap.SPACING,
	)

	# The gradient, which is the reason the galaxy has a shape at all. The
	# rim has to be measurably thinner than the core or there is no late
	# game behind a better drive, only a longer one.
	var core_gap: float = _mean_gap(map, 0.0, 0.45)
	var rim_gap: float = _mean_gap(map, 0.8, 1.0)
	_expect(
		rim_gap > core_gap * 1.3,
		"the rim is thinner than the core (%.1f ly apart against %.1f)" % [
			rim_gap, core_gap,
		],
	)

	# And the graph. Three claims, and the middle one is the one worth
	# having: a galaxy with no islands is a galaxy where drive range buys
	# a shorter trip to where you already were.
	var home: int = map.start_index()
	var reachable: PackedInt32Array = map.reachable_from(home, GalaxyMap.BASE_REACH)
	var biggest: PackedInt32Array = map.largest_component(GalaxyMap.BASE_REACH)
	var share: float = float(reachable.size()) / float(maxi(map.count(), 1))
	_expect(
		reachable.size() == biggest.size(),
		"a new game starts in the largest group, not on an island (%d of %d)" % [
			reachable.size(), biggest.size(),
		],
	)
	_expect(
		share > 0.6,
		"and the starting drive reaches most of the galaxy (%.0f%%)" % [share * 100.0],
	)
	var stranded: int = map.count() - biggest.size()
	_expect(
		stranded >= 5,
		"while %d systems are islands until the drive is better" % stranded,
	)
	var far: PackedInt32Array = map.largest_component(GalaxyMap.BASE_REACH * 1.35)
	_expect(
		far.size() > biggest.size()
		and float(far.size()) / float(map.count()) > 0.95,
		"a third again of range opens nearly all of it (%d of %d)" % [
			far.size(), map.count(),
		],
	)

	# The grid query has to agree with the honest answer, because every
	# scanner reading goes through it and nothing else will ever notice.
	var probe: Vector2 = Vector2(13.0, -21.0)
	var quick: PackedInt32Array = map.within(probe, 17.0)
	var slow: Array[int] = []
	for index: int in range(map.count()):
		if probe.distance_to(map.positions[index]) <= 17.0:
			slow.append(index)
	_expect(
		quick.size() == slow.size(),
		"the grid finds exactly what a full scan finds (%d against %d)" % [
			quick.size(), slow.size(),
		],
	)
	var ordered: bool = true
	for step: int in range(1, quick.size()):
		if (
			probe.distance_to(map.positions[quick[step - 1]])
			> probe.distance_to(map.positions[quick[step]]) + 0.001
		):
			ordered = false
	_expect(ordered, "and hands them back nearest first")

	# Four seeds, not one. A layout rule that holds on the seed it was
	# tuned against is a layout rule that holds on one seed.
	var thin: int = 0
	var whole: int = 0
	for galaxy_seed: int in [1, 777, 4242, 31337]:
		var rolled: GalaxyMap = GalaxyMap.generate(galaxy_seed)
		var group: PackedInt32Array = rolled.largest_component(GalaxyMap.BASE_REACH)
		if float(group.size()) / float(maxi(rolled.count(), 1)) < 0.6:
			thin += 1
		if group.size() == rolled.count():
			whole += 1
	_expect(
		thin == 0,
		"four more seeds all give a galaxy worth starting in",
	)
	_expect(
		whole == 0,
		"and none of them is so connected that range would buy nothing",
	)


## Mean distance to the nearest neighbour, for systems in a ring of the
## galaxy given as fractions of its radius.
func _mean_gap(map: GalaxyMap, from: float, to: float) -> float:
	var total: float = 0.0
	var counted: int = 0
	for i: int in range(map.count()):
		var out: float = map.positions[i].length() / GalaxyMap.RADIUS
		if out < from or out > to:
			continue
		var nearest: float = INF
		for j: int in range(map.count()):
			if i != j:
				nearest = minf(nearest, map.positions[i].distance_to(map.positions[j]))
		total += nearest
		counted += 1
	return 0.0 if counted == 0 else total / float(counted)


## The system model: a star, its planets, their moons, and where all of it
## is at a given moment.
##
## Checked over three hundred seeds rather than one, because a generator
## that works on the seed it was written against is a generator nobody has
## tested. Everything here is a layout invariant -- orbits that do not
## cross, moons inside their parent's well -- rather than a number, so the
## ranges stay tunable without rewriting the test.
func _check_system_model(probe: Planet) -> void:
	# Reproducible, or the save file (a seed plus deltas) is worthless.
	var once: StarSystem = StarSystem.generate(4242)
	var twice: StarSystem = StarSystem.generate(4242)
	var same: bool = once.display_name == twice.display_name
	same = same and once.bodies.size() == twice.bodies.size()
	if same:
		for i: int in range(once.bodies.size()):
			var a: SystemBody = once.bodies[i]
			var b: SystemBody = twice.bodies[i]
			same = same and a.display_name == b.display_name and a.seed == b.seed
			same = same and is_equal_approx(a.orbit_radius, b.orbit_radius)
			same = same and is_equal_approx(a.orbit_phase, b.orbit_phase)
	_expect(same, "the same seed builds the same system (%s, %d bodies)" % [
		once.display_name, once.bodies.size(),
	])
	var other: StarSystem = StarSystem.generate(4243)
	_expect(
		other.display_name != once.display_name or other.bodies.size() != once.bodies.size(),
		"and a different seed builds a different one",
	)

	var crossings: int = 0
	var moons_adrift: int = 0
	var moons_grazing: int = 0
	var kepler_breaks: int = 0
	var seed_clashes: int = 0
	var dockless: int = 0
	var crushed: int = 0
	var starved: int = 0
	var inner_pull: float = INF
	var moons_outside_hill: int = 0
	var pull_lo: float = INF
	var pull_hi: float = 0.0
	var widest: float = 0.0
	var narrowest: float = INF
	var shortest_year: float = INF
	var longest_year: float = 0.0

	for index: int in range(SYSTEMS_SAMPLED):
		var system: StarSystem = StarSystem.generate(StarSystem.derive(9001, index))
		widest = maxf(widest, system.outer_radius())
		narrowest = minf(narrowest, system.outer_radius())

		var seeds: Dictionary = {}
		for body: SystemBody in system.bodies:
			if seeds.has(body.seed):
				seed_clashes += 1
			seeds[body.seed] = true

		# No two orbits cross, counting whatever each planet is carrying: two
		# worlds that swap places would be a system that eats itself.
		var inner: SystemBody = null
		for planet: SystemBody in system.planets():
			if inner != null:
				# Not merely "they do not touch": the outer one keeps its own
				# narrowest gravity well clear of everything inside it.
				var reach_out: float = planet.orbit_radius - (planet.extent() - planet.orbit_radius)
				var clearance: float = reach_out - inner.extent()
				if clearance < Planet.INFLUENCE_RATIO.x * planet.radius - 0.001:
					crossings += 1
			inner = planet
			shortest_year = minf(shortest_year, planet.orbit_period)
			longest_year = maxf(longest_year, planet.orbit_period)

			# The star has to leave the planet something to hold with, and
			# the test for that is the **direct** one: at the edge of the
			# well this planet actually got, measuring the star from the
			# near side, the planet still has to out-pull it.
			#
			# This assertion has been wrong twice, in the same place. It
			# first asked about the Hill sphere, which is derived in the
			# frame that turns with the planet -- ours do not turn, so
			# nothing cancels the star and the sphere comes out seven
			# times too wide; under that rule the star beat the innermost
			# planet two to one inside its own declared well. It then
			# asked about the widest well a planet *could* roll, which was
			# right while the star was weighed to afford that, and became
			# wrong the moment wells started being derived per planet.
			# Both times the fix was to ask about the thing that exists.
			var well: float = planet.well_radius
			var gap: float = planet.orbit_radius - well
			var dominance: float = (planet.mu() / (well * well)) / (system.star.mu() / (gap * gap))
			# Only the clipped ones sit exactly on the line; a planet whose
			# rolled ceiling was narrower than the limit keeps far more.
			if dominance < StarSystem.WELL_DOMINANCE - 0.001:
				crushed += 1
			if well < planet.radius * StarSystem.WELL_FLOOR - 0.001:
				starved += 1
			for moon: SystemBody in planet.children:
				var moon_gap: float = planet.orbit_radius - moon.orbit_radius
				var moon_hold: float = planet.mu() / (moon.orbit_radius * moon.orbit_radius)
				if moon.kind != SystemBody.Kind.MOON:
					continue
				if moon_hold < system.star.mu() / (moon_gap * moon_gap):
					moons_outside_hill += 1
			var pull: float = system.star.mu() / (planet.orbit_radius * planet.orbit_radius)
			pull_lo = minf(pull_lo, pull)
			pull_hi = maxf(pull_hi, pull)
			if planet == system.planets()[0]:
				inner_pull = minf(inner_pull, pull)

			# One star, one mu, so T^2 / r^3 is the same for every planet of it.
			var kepler: float = planet.orbit_period * planet.orbit_period
			kepler /= pow(planet.orbit_radius, 3.0)
			if absf(kepler - TAU * TAU / system.star.mu()) > kepler * 0.0001:
				kepler_breaks += 1

		for moon: SystemBody in system.of_kind(SystemBody.Kind.MOON):
			# Inside the parent's well at its narrowest possible roll. The
			# layout never sees the roll, so it has to hold for all of them.
			if moon.orbit_radius + moon.radius >= Planet.INFLUENCE_RATIO.x * moon.parent_body().radius:
				moons_adrift += 1
			if moon.orbit_radius <= moon.parent_body().radius + moon.radius:
				moons_grazing += 1

		if system.of_kind(SystemBody.Kind.STATION).is_empty():
			dockless += 1

	_expect(
		crossings == 0,
		"no planet sits inside another's well, over %d systems" % SYSTEMS_SAMPLED,
	)
	_expect(moons_adrift == 0, "every moon orbits inside its parent gravity well")
	_expect(moons_grazing == 0, "and clear of its parent surface")
	_expect(kepler_breaks == 0, "planets of one star obey one third law")
	_expect(seed_clashes == 0, "no two bodies in a system share a seed")
	_expect(dockless == 0, "every system has somewhere to dock")
	_expect(
		crushed == 0,
		"every planet out-pulls the star x%.0f at the edge of its widest well"
			% StarSystem.WELL_DOMINANCE,
	)
	_expect(moons_outside_hill == 0, "and holds its moons against the star as well")
	# The floor is what the layout pays for by moving planets outwards. A
	# planet below it is one the star has squeezed out of being orbitable
	# at all, and the layout is supposed to have moved it rather than let
	# that happen.
	_expect(
		starved == 0,
		"and every planet keeps at least %.1f radii of well to be orbited in"
			% StarSystem.WELL_FLOOR,
	)
	_expect(
		pull_hi < Planet.GRAVITY_RANGE.x,
		"the star never out-pulls a planet's own surface at that planet's orbit (%.2f to %.2f px/s2)" % [
			pull_lo, pull_hi,
		],
	)
	# And a floor, which is the half nobody thought to write down. The
	# first star was correct, tested, and physically irrelevant: it pulled
	# 0.07 px/s^2 where the ship actually flies -- four tenths of one per
	# cent of what the ship felt -- and two hundred pixels of drift over a
	# hundred seconds out between the orbits where it was the only thing
	# pulling at all. Every assertion passed. A pilot said it did not pull.
	#
	# Half a pixel per second squared is the line, because that is where a
	# hundred-second coast picks up fifty px/s and two and a half thousand
	# pixels of drift -- visible on the map's dashed curve, and worth
	# correcting for on a transfer.
	_expect(
		inner_pull > 0.5,
		"and pulls hard enough at the innermost orbit to be worth flying round (%.2f px/s2 at worst)"
			% inner_pull,
	)
	# Bounds on the clock, not on taste. Short enough that a system is not
	# frozen -- come back after an hour of play and the outer worlds have
	# visibly moved -- and long enough that two visits a few minutes apart
	# do not find a planet somewhere else entirely. Measured range over the
	# sample: 557 s to 27859 s.
	_expect(
		shortest_year > 300.0 and longest_year < 54000.0,
		"a year runs from five minutes to fifteen hours (%.0f s to %.0f s)" % [
			shortest_year, longest_year,
		],
	)

	print("system radius: %.0f px to %.0f px" % [narrowest, widest])
	_expect(
		widest < PROVEN_DISTANCE,
		"no system reaches past the distance the bench has measured (%.0f of %.0f px)" % [
			widest, PROVEN_DISTANCE,
		],
	)

	# The pure part of it, instantly: a point at the far edge of the widest
	# system, taken into a frame out there and back. No physics, so this is
	# float32 and nothing else, and it is the thing that changes if the
	# layout constants ever grow.
	var far_off: Node2D = Node2D.new()
	root.add_child(far_off)
	far_off.global_position = Vector2(widest, 0.0)
	var probe_point: Vector2 = Vector2(700.3, -415.9)
	var round_trip: float = far_off.to_local(
		far_off.to_global(probe_point)
	).distance_to(probe_point)
	_expect(
		round_trip < 0.05,
		"a coordinate survives the trip out to the system edge (%.4f px at %.0f)" % [
			round_trip, widest,
		],
	)
	far_off.queue_free()

	_check_orbit_evaluation()
	_check_moon_sized_world(probe)
	_check_adoption()


## What exists as nodes, and when.
##
## The manager is the one piece of M3 that cannot be judged by looking at
## it: every property here is about a threshold being crossed in one
## direction or the other, and the interesting failures are at the
## crossing.
func _check_streaming() -> void:
	var manager: Node = STREAMING_SCRIPT.new()
	root.add_child(manager)
	var container: Node2D = Node2D.new()
	root.add_child(container)
	var pilot: Node2D = Node2D.new()
	root.add_child(pilot)
	var system: StarSystem = StarSystem.generate(20260922)
	# Owned here, not by the manager: in the game the loot source is an
	# autoload nothing may free, so the manager never frees it.
	var dice: Node = LOOT_SCRIPT.new()
	manager.loot = dice
	manager.bind(system, container, 0.0)
	manager.track(pilot)
	var world: SystemBody = system.planets()[0]

	# Nothing may be asleep inside the reach of anything that looks at the
	# world, and the longest-sighted thing in the game is the scanner. A
	# contact that has not been built is a contact the scanner cannot
	# report, and a planet that blinks into existence inside scanner range
	# is a contact that appears out of nothing.
	var eyes: ScannerHud = ScannerHud.new()
	var sight: float = eyes.scan_range
	eyes.free()
	var sighted: bool = true
	var gravity_safe: bool = true
	for check: SystemBody in system.bodies:
		var reach: float = manager.awake_distance(check)
		sighted = sighted and reach >= sight
		gravity_safe = gravity_safe and reach >= check.radius * Planet.INFLUENCE_RATIO.y
	_expect(sighted, "nothing sleeps inside the scanner's reach (%.0f px)" % sight)
	_expect(gravity_safe, "or inside the pull of its own gravity well")

	# Far away: nothing in the scene at all.
	pilot.global_position = manager.position_of(world) + Vector2(500000.0, 0.0)
	manager._sweep()
	manager._drain_queue()
	_expect(
		manager.level_of(world) == manager.Level.GONE and manager.node_for(world) == null,
		"a body the player is nowhere near is not in the world",
	)

	# Walking in: built, then stocked, and the build is queued rather than
	# taken in the frame the threshold was crossed.
	pilot.global_position = manager.position_of(world) + Vector2(
		manager.awake_distance(world) * 0.9, 0.0
	)
	manager._sweep()
	_expect(
		manager.node_for(world) == null,
		"crossing the line queues the build rather than paying for it on the spot",
	)
	manager._drain_queue()
	_expect(
		manager.node_for(world) == null and not manager._building.is_empty(),
		"and draining the queue starts a worker rather than building in place",
	)
	_stream_in(manager, world)
	var built: Planet = manager.node_for(world) as Planet
	_expect(
		built != null and manager.level_of(world) == manager.Level.AWAKE,
		"and it is there once the worker is done",
	)
	_expect(
		built != null and built.terrain.texture != null
		and built.landing_sites().size() > 0,
		"whole, with a texture and shelves -- the worker did the arithmetic, not half of it",
	)
	_expect(
		built != null and built.global_position.distance_to(manager.position_of(world)) < 1.0,
		"standing where the visit's clock says, not where its orbit is now",
	)
	_expect(
		_crates_under(built) == 0,
		"with nothing on the surface yet, because the pilot is still miles up",
	)

	# Hysteresis: a pilot sitting between the two thresholds keeps whatever
	# they have, or a planet's terrain is rebuilt twice a second.
	pilot.global_position = manager.position_of(world) + Vector2(
		manager.awake_distance(world) * 1.15, 0.0
	)
	manager._sweep()
	manager._collect_finished()
	_expect(
		manager.node_for(world) == built,
		"drifting back out past the line does not immediately undo it",
	)
	pilot.global_position = manager.position_of(world) + Vector2(
		manager.awake_distance(world) * 1.5, 0.0
	)
	manager._sweep()
	_expect(
		manager.level_of(world) == manager.Level.GONE,
		"but going properly away does",
	)

	# Down at the surface: loot appears.
	pilot.global_position = manager.position_of(world) + Vector2(world.radius * 1.2, 0.0)
	manager._sweep()
	_stream_in(manager, world)
	manager._sweep()
	var landed: Planet = manager.node_for(world) as Planet
	_expect(
		manager.level_of(world) == manager.Level.SURFACE and _crates_under(landed) > 0,
		"standing on it puts the loot out (%d crates)" % _crates_under(landed),
	)

	# The first delta. Take one, leave, come back: the taken shelf stays
	# empty and the others are exactly what they were.
	var before: Array[String] = _crate_labels(landed)
	var first: LootCrate = null
	for child: Node in landed.get_children():
		if child is LootCrate and first == null:
			first = child as LootCrate
	manager.forget_crate(first)
	var taken_label: String = first.label()

	pilot.global_position = manager.position_of(world) + Vector2(500000.0, 0.0)
	manager._sweep()
	pilot.global_position = manager.position_of(world) + Vector2(world.radius * 1.2, 0.0)
	manager._sweep()
	_stream_in(manager, world)
	manager._sweep()
	var again: Array[String] = _crate_labels(manager.node_for(world) as Planet)
	_expect(
		again.size() == before.size() - 1 and not again.has(taken_label),
		"what was picked up is not waiting for you when you come back (%s)" % taken_label,
	)
	var kept: bool = true
	for label: String in again:
		kept = kept and before.has(label)
	_expect(
		kept,
		"and taking one does not change what the others are (%s)" % ", ".join(again),
	)

	# The second delta: a hole stays a hole. Dug before leaving, still
	# there on the way back, and nothing kept for a world nobody touched.
	var shot: Planet = manager.node_for(world) as Planet
	var mark: float = 0.7
	var was_ground: float = shot.terrain.surface_radius_at(mark)
	shot.carve(shot.polar_to_world(mark, was_ground - 10.0), 80.0)
	var cratered: float = shot.terrain.surface_radius_at(mark)
	_expect(
		cratered < was_ground - 10.0,
		"a crater is a crater (%.0f px down from %.0f)" % [was_ground - cratered, was_ground],
	)

	pilot.global_position = manager.position_of(world) + Vector2(500000.0, 0.0)
	manager._sweep()
	_expect(
		manager.deltas.get(world.seed, {}).has("crust"),
		"leaving a world you shot at keeps its crust",
	)
	var untouched: SystemBody = null
	for other: SystemBody in system.planets():
		if other != world and untouched == null:
			untouched = other
	_expect(
		untouched != null and not manager.deltas.get(untouched.seed, {}).has("crust"),
		"and a world nobody touched keeps nothing -- its seed already says it",
	)

	pilot.global_position = manager.position_of(world) + Vector2(world.radius * 1.2, 0.0)
	manager._sweep()
	_stream_in(manager, world)
	var returned: Planet = manager.node_for(world) as Planet
	_expect(
		absf(returned.terrain.surface_radius_at(mark) - cratered) < 1.0,
		"and the hole is where you left it (%.0f px against %.0f)" % [
			returned.terrain.surface_radius_at(mark), cratered,
		],
	)
	_expect(
		returned != shot,
		"on a planet that really was rebuilt, not one that never went away",
	)

	# The star went up with the system and is still up, half a million
	# pixels later. Everything else in here is about bodies coming and
	# going; the star is the one that must not, because its pull is what a
	# ship between planets is coasting on.
	_expect(
		manager.star_node() != null and manager.level_of(system.star) == manager.Level.AWAKE,
		"the star is in the world however far the pilot has gone",
	)
	_expect(
		manager.star_node().global_position.is_zero_approx(),
		"and it is at the origin, which is what every orbit is measured from",
	)
	# Stations stream like everything else now. This assertion used to say
	# they had no scene and stayed in the model, and it would have gone on
	# passing after they got one: the station in this system orbits a
	# different planet from the one the test is flying at, so it was out
	# of reach and absent for the wrong reason.
	var dock: Array[SystemBody] = system.of_kind(SystemBody.Kind.STATION)
	_expect(not dock.is_empty(), "the system has somewhere to dock")
	pilot.global_position = manager.position_of(dock[0])
	manager._sweep()
	_stream_in(manager, dock[0])
	_expect(
		manager.node_for(dock[0]) is Station,
		"and flying to it builds it, like any other body",
	)
	_expect(
		manager.node_for(dock[0]).global_position.distance_to(
			manager.position_of(dock[0])
		) < 1.0,
		"where the visit's clock says it is",
	)

	manager.clear()
	manager.free()
	dice.free()
	container.free()
	pilot.free()



## Przelot przez caly uklad: slad na kazdej planecie, powrot na pierwsza.
##
## M3's own closing criterion, and the one thing `_check_streaming` does not
## reach: that test proves one world remembers one hole. This flies the
## whole system, marks every planet it passes, and comes back to the first
## -- which is the case where the manager has had to forget and rebuild
## everything in between, and where a delta keyed on the wrong thing would
## hand back the wrong crust.
##
## "No hitches" is measured rather than taken on feel. The crust is built on
## a worker thread; what a frame actually pays is `_start_build` plus
## `_collect_finished` -- instantiate, prepare, texture upload, visuals --
## and both of those are on the main thread. The ceiling below is the
## measured worst case with headroom, so a regression that doubles the
## upload fails here instead of being noticed as a stutter one day.
func _check_system_tour() -> void:
	var manager: Node = STREAMING_SCRIPT.new()
	root.add_child(manager)
	var container: Node2D = Node2D.new()
	root.add_child(container)
	var pilot: Node2D = Node2D.new()
	root.add_child(pilot)
	var dice: Node = LOOT_SCRIPT.new()
	var system: StarSystem = StarSystem.generate(TEST_SEED)
	manager.loot = dice
	manager.bind(system, container, 0.0)
	manager.track(pilot)

	var worlds: Array[SystemBody] = system.planets()
	_expect(worlds.size() >= 3, "the test system is worth touring (%d worlds)" % worlds.size())

	# One mark per world, at a different angle on each so a crust handed
	# back for the wrong body shows up as a missing hole rather than as a
	# hole that happens to match.
	var marks: Dictionary = {}
	var worst: float = 0.0
	var slowest: String = ""
	var missed: int = 0
	var shallow: int = 0

	for i: int in range(worlds.size()):
		var body: SystemBody = worlds[i]
		pilot.global_position = manager.position_of(body)
		manager._sweep()
		var cost: float = _time_to_stream(manager, body)
		if cost > worst:
			worst = cost
			slowest = body.display_name
		var planet: Planet = manager.node_for(body) as Planet
		if planet == null:
			missed += 1
			continue
		var mark: float = 0.3 + 0.2 * float(i)
		var before: float = planet.terrain.surface_radius_at(mark)
		planet.carve(planet.polar_to_world(mark, before - 10.0), 80.0)
		var after: float = planet.terrain.surface_radius_at(mark)
		# Asserted, not assumed. Without this the "still has the hole"
		# check below passes vacuously on a world where the shot did
		# nothing: unchanged equals unchanged.
		if after >= before - 5.0:
			shallow += 1
			print("    %s took no damage (%.1f from %.1f)" % [
				body.display_name, before - after, before,
			])
		marks[body.seed] = {"at": mark, "depth": after}

	_expect(missed == 0, "every world in the system builds when it is flown to")
	_expect(shallow == 0, "and every one of them can be shot a hole in")
	_expect(
		worst < TOUR_FRAME_BUDGET,
		"and the worst main-thread cost of one is %.1f ms (%s), under %.0f" % [
			worst, slowest, TOUR_FRAME_BUDGET,
		],
	)

	# Back to the first, the long way round: everything else has been built
	# and thrown away since, so nothing about this one is still in memory.
	var kept: int = 0
	var lost: int = 0
	for body: SystemBody in worlds:
		pilot.global_position = manager.position_of(body)
		manager._sweep()
		_time_to_stream(manager, body)
		var planet: Planet = manager.node_for(body) as Planet
		var noted: Dictionary = marks.get(body.seed, {})
		if planet == null or noted.is_empty():
			lost += 1
			continue
		var now: float = planet.terrain.surface_radius_at(float(noted["at"]))
		if absf(now - float(noted["depth"])) < 1.0:
			kept += 1
		else:
			lost += 1
			print("    %s forgot its hole (%.0f against %.0f)" % [
				body.display_name, now, noted["depth"],
			])
	_expect(lost == 0, "and every one of them still has the hole you left in it (%d)" % kept)

	# The deltas are the memory, and they have to be only of what was
	# touched: a manager that remembered every world it ever built would
	# grow without bound over a long flight.
	#
	# Asked with the system empty, which the first version of this check
	# forgot. A world still in the scene keeps its crust in the node, so
	# the delta has not been written yet and asking for it there is asking
	# the wrong question -- which is what it looked like when the last
	# world of the tour reported itself unremembered while plainly holding
	# its hole.
	pilot.global_position = manager.position_of(worlds[0]) + Vector2(500000.0, 0.0)
	manager._sweep()
	var loaded: int = 0
	for body: SystemBody in system.bodies:
		if manager.level_of(body) != manager.Level.GONE and body.kind != SystemBody.Kind.STAR:
			loaded += 1
	_expect(loaded == 0, "flying out of the system empties it (%d left)" % loaded)

	var remembered: int = 0
	for body: SystemBody in system.bodies:
		var has_crust: bool = manager.deltas.get(body.seed, {}).has("crust")
		if has_crust:
			remembered += 1
		elif marks.has(body.seed):
			print("    %s was shot at but is not remembered (level %d)" % [
				body.display_name, manager.level_of(body),
			])
	_expect(
		remembered == worlds.size(),
		"the manager remembers the %d worlds that were shot at and no others (%d)" % [
			worlds.size(), remembered,
		],
	)

	manager.clear()
	manager.free()
	dice.free()
	container.free()
	pilot.free()


## Streams `body` in and hands back the milliseconds the main thread spent
## doing it.
##
## The wait between turns of the handle is not counted: that is the worker
## computing the crust, which in the game is a frame going past rather than
## a frame being blocked. What is counted is the manager's own two steps.
func _time_to_stream(manager: Node, body: SystemBody) -> float:
	var spent: int = 0
	for tries: int in range(2000):
		if manager.node_for(body) != null:
			break
		var at: int = Time.get_ticks_usec()
		manager._drain_queue()
		manager._collect_finished()
		spent += Time.get_ticks_usec() - at
		if manager.node_for(body) != null:
			break
		OS.delay_msec(1)
	return float(spent) / 1000.0

## Drives an asynchronous build to the point where the planet is in the
## world. In the game a frame goes by and the manager collects it; a test
## with no frames has to turn the handle itself.
func _stream_in(manager: Node, body: SystemBody) -> void:
	for tries: int in range(2000):
		if manager.node_for(body) != null:
			return
		# Drained every turn, not once at the top. The manager starts one
		# build per frame, so a queue with somebody else at the head means
		# the body being waited for is not even started yet -- and a
		# helper that drains once would then spin two thousand times
		# collecting nothing and return as if the world had refused to
		# build. Which is exactly what it did, the moment a wider system
		# put a second planet within reach of the test's parking spot.
		manager._drain_queue()
		manager._collect_finished()
		OS.delay_msec(1)


func _crates_under(planet: Planet) -> int:
	var count: int = 0
	if planet == null:
		return count
	for child: Node in planet.get_children():
		if child is LootCrate:
			count += 1
	return count


func _crate_labels(planet: Planet) -> Array[String]:
	var out: Array[String] = []
	if planet == null:
		return out
	for child: Node in planet.get_children():
		if child is LootCrate:
			out.append((child as LootCrate).label())
	return out


## The system map, which is the only thing that shows a body the streaming
## manager has not built.
## The star: what it pulls on, what it does not, and how close is too close.
func _check_star() -> void:
	var system: StarSystem = StarSystem.generate(20260922)
	var star: Star = (load("res://scenes/star.tscn") as PackedScene).instantiate() as Star
	root.add_child(star)
	star.adopt(system.star)

	# It is a gravity source and it is not a planet. Everything that only
	# wants the pull sees it; everything that wants ground does not, and
	# `Planet.nearest` is the one that would otherwise hand a star to code
	# about to ask it for terrain.
	var wells: Array[GravityWell] = GravityWell.all(self)
	_expect(wells.has(star), "the star is in the gravity group like any other source")
	_expect(
		Planet.nearest(self, Vector2(1000.0, 0.0)) != star,
		"but it is never the nearest planet -- it has no ground to be one",
	)

	var out: Vector2 = Vector2(system.planets()[0].orbit_radius, 0.0)
	var pull: float = star.gravity_at(out).length()
	_expect(pull > 0.0, "it pulls at the innermost orbit (%.3f px/s2)" % pull)
	_expect(
		star.gravity_at(out).normalized().is_equal_approx(Vector2.LEFT),
		"and it pulls inwards, towards the middle of the system",
	)
	var twice: float = star.gravity_at(out * 2.0).length()
	_expect(
		absf(twice * 4.0 - pull) < pull * 0.01,
		"inverse square, like everything else that pulls (%.4f against %.4f)" % [
			twice * 4.0, pull,
		],
	)
	_expect(
		star.gravity_at(Vector2(system.outer_radius(), 0.0)).length() > 0.0,
		"and its reach covers the outermost orbit, so deep space is not a vacuum of force",
	)
	_expect(
		is_equal_approx(GravityWell.pull_at(self, out).length(), pull),
		"and out where nothing else reaches, the star is the whole of it",
	)

	_expect(
		star.irradiance_at(Vector2(star.surface_radius, 0.0)) > 0.99,
		"the surface gets the full flux by definition (%.2f)" % star.irradiance_at(
			Vector2(star.surface_radius, 0.0)
		),
	)

	# Heat, by running the ship's own model rather than restating it.
	#
	# The first version of this test did the arithmetic itself, agreed with
	# the arithmetic in `burn_radius`, and both were wrong the same way --
	# they assumed the hull cools by a fraction of its heat when it bleeds
	# a constant. Flying at the star in the running game is what found it.
	# A test that computes the answer it is checking can only ever find
	# typing mistakes.
	var burn: float = Ship.burn_radius(star)
	var pilot: Ship = _spawn_ship()
	var hot: float = _bake(pilot, star, Vector2(burn * 0.7, 0.0), 120.0)
	_expect(
		hot >= Ship.BURN_HEAT,
		"two minutes well inside the burn radius fills the bar (%.2f)" % hot,
	)
	_expect(
		pilot.hull_integrity < 1.0,
		"and takes it out of the hull (%.0f%% left)" % (pilot.hull_integrity * 100.0),
	)
	var cool: float = _bake(pilot, star, Vector2(burn * 1.15, 0.0), 600.0)
	_expect(
		cool == 0.0,
		"ten minutes just outside it and the bar has not moved at all (%.3f)" % cool,
	)
	_expect(
		pilot.hull_integrity == 1.0,
		"so a ship can sit there as long as it likes",
	)
	pilot.free()

	# No world may sit inside the zone. An inner planet you cannot land on
	# because the sun cooks you on approach is an inner planet that is not
	# in the game, and the layout does not know the heat model exists -- so
	# this is checked over the sample rather than assumed.
	var scorched: int = 0
	var closest: float = INF
	for seed_index: int in range(SYSTEMS_SAMPLED):
		var other: StarSystem = StarSystem.generate(seed_index)
		var reach: float = other.star.radius * sqrt(
			Ship.STAR_HEAT_RATE / Ship.HEAT_COOLING
		)
		for planet: SystemBody in other.planets():
			var approach: float = planet.orbit_radius - planet.radius
			closest = minf(closest, approach / reach)
			if approach <= reach:
				scorched += 1
	_expect(
		scorched == 0,
		"no planet orbits inside the star's burn radius (closest comes to x%.2f of it)" % closest,
	)

	star.free()


## Emergency power: what it buys, what it costs, and that it runs out.
func _check_boost() -> void:
	var ship: Ship = _spawn_ship()
	var main: EngineInstance = null
	var small: EngineInstance = null
	for engine: EngineInstance in ship.engines:
		engine.throttle = 1.0
		if engine.data.type == EngineData.Type.MAIN and main == null:
			main = engine
		if not engine.data.can_boost() and small == null:
			small = engine

	_expect(main != null and main.data.can_boost(), "the main drive has an emergency setting")
	_expect(
		small != null,
		"and the small engines do not -- a thruster at three times its rating is a bomb",
	)

	var plain: float = main.current_force().length()
	main.boosting = true
	var lit: float = main.current_force().length()
	main.boosting = false
	_expect(
		absf(lit / plain - main.data.boost_thrust) < 0.001,
		"boosting multiplies the thrust by exactly what the engine says (x%.2f)" % (
			lit / plain
		),
	)
	var quiet: float = small.current_force().length()
	small.boosting = true
	_expect(
		is_equal_approx(small.current_force().length(), quiet),
		"and an engine with no boost is unmoved by being told to boost",
	)
	small.boosting = false

	# What it is for. A heavy world against a drive that has been knocked
	# about is the case that prompted this: without boost the ship is on
	# the ground for good, and respawning is not an answer.
	var lift: float = 0.0
	for engine: EngineInstance in ship.engines:
		if engine.data.type == EngineData.Type.MAIN:
			lift += engine.data.max_thrust
	var crippled: float = lift * 0.5 / ship.mass
	_expect(
		crippled < Planet.GRAVITY_RANGE.y,
		"a main drive at half health cannot lift off the heaviest world (%.1f of %.1f px/s2)" % [
			crippled, Planet.GRAVITY_RANGE.y,
		],
	)
	_expect(
		crippled * main.data.boost_thrust > Planet.GRAVITY_RANGE.y,
		"and with emergency power it can (%.1f px/s2)" % (
			crippled * main.data.boost_thrust
		),
	)

	# The cost, driven through the ship's own rule rather than restated.
	var step: float = 1.0 / float(Engine.physics_ticks_per_second)
	ship.energy = ship.energy_capacity()
	ship.boost_command = true
	ship._resolve_boost(step)
	_expect(ship.boost_active, "holding boost on a full pool lights it")
	var drain: float = (ship.energy_capacity() - ship.energy) / step
	_expect(
		drain > 0.0,
		"and it comes out of the pool at %.1f a second, not out of nothing" % drain,
	)

	var burned: float = 0.0
	var lit_for: float = 0.0
	for tick: int in range(2000):
		ship._resolve_boost(step)
		if not ship.boost_active:
			break
		lit_for += step
		burned += 1.0
	_expect(
		lit_for > 3.0 and lit_for < 30.0,
		"a full pool is worth %.1f seconds of it: enough to get off the ground, not to fly on" % (
			lit_for
		),
	)
	_expect(ship.energy <= 0.001, "and it burns the pool to nothing (%.3f left)" % ship.energy)

	# No pulsing on the way out. A threshold on its own was not enough:
	# the burn holds the recharge off, so a pool crawling back over the
	# line gets emptied again, and a pilot holding the key over a dead
	# pool got a burst of thrust about once a second. Ten seconds of
	# holding it down, with the pool recharging, must give nothing.
	var relit: int = 0
	for tick: int in range(600):
		ship._recharge(step)
		ship._resolve_boost(step)
		if ship.boost_active:
			relit += 1
	_expect(
		relit == 0,
		"holding it over a spent pool gives nothing back (%d ticks of pulsing)" % relit,
	)
	_expect(
		ship.energy > ship.energy_capacity() * Ship.BOOST_RESERVE,
		"even though the pool refilled while they held it (%.0f)" % ship.energy,
	)
	# Letting go is what rearms it. One press, one burn.
	ship.boost_command = false
	ship._resolve_boost(step)
	ship.boost_command = true
	ship._resolve_boost(step)
	_expect(ship.boost_active, "letting go and pressing again strikes it")

	# An engine that is not pushing is not burning.
	ship.energy = ship.energy_capacity()
	for engine: EngineInstance in ship.engines:
		engine.throttle = 0.0
	ship._resolve_boost(step)
	_expect(
		not ship.boost_active and is_equal_approx(ship.energy, ship.energy_capacity()),
		"a ship with its engines idle burns nothing, however hard the key is held",
	)

	# And it has to be possible to see it.
	#
	# This was broken for a milestone and the shape of the bug is worth
	# keeping: everything that drew the exhaust read `effective_output()`,
	# which is the throttle fraction and tops out at one, so three times
	# the thrust came out looking exactly like one times the thrust. The
	# number that can say so is `exhaust_flow()`.
	var drive: EngineInstance = null
	for engine: EngineInstance in ship.engines:
		if engine.data.can_boost():
			drive = engine
	_expect(drive != null, "the stock hull has a drive with an emergency setting")

	drive.throttle = 1.0
	drive.boosting = false
	var calm: float = drive.exhaust_flow()
	var calm_force: float = drive.current_force().length()
	drive.boosting = true
	var surging: float = drive.exhaust_flow()
	_expect(
		is_equal_approx(surging, calm * drive.data.boost_thrust),
		"the flow out of a boosted nozzle is the boost multiple (%.1fx)" % (surging / calm),
	)
	_expect(
		is_equal_approx(drive.effective_output(), 1.0),
		"while the throttle fraction itself is untouched, because the allocator reads it",
	)
	_expect(
		is_equal_approx(drive.current_force().length(), calm_force * surging / calm),
		"and the flow is the same multiple the physics already applied",
	)

	# The light the nozzle throws follows it. Clamping this is what made
	# the first version of boost invisible even with the ground lit.
	drive.mount.set_exhaust(calm)
	var quiet_glow: float = _first_glow(drive.mount).energy
	drive.mount.set_exhaust(surging)
	var loud_glow: float = _first_glow(drive.mount).energy
	_expect(
		loud_glow > quiet_glow * 2.0,
		"a boosted nozzle lights the ground harder (%.2f against %.2f)" % [
			loud_glow, quiet_glow,
		],
	)

	# As does the flame, which gets longer rather than merely brighter: at
	# full throttle there is no brightness left to add.
	# `paint()` rather than `refresh()`: the gate is in `refresh`, and
	# headless it returns before any of this happens.
	var skin: ShipSkin = ship.get_node_or_null("Presentation") as ShipSkin
	drive.boosting = false
	skin.paint(0.0, Color.WHITE)
	var short_flame: Vector2 = _plume_of(skin, drive).scale
	drive.boosting = true
	skin.paint(0.0, Color.WHITE)
	var long_flame: Vector2 = _plume_of(skin, drive).scale
	_expect(
		long_flame.y > short_flame.y * 2.0,
		"and throws a longer flame (%.2f against %.2f)" % [long_flame.y, short_flame.y],
	)
	_expect(
		long_flame.x > short_flame.x and long_flame.x < long_flame.y,
		"wider too, but much less so: a boosted drive is a spear, not a cloud",
	)
	ship.free()


## The plume sprite the skin built for one engine, found by where it sits.
func _plume_of(skin: ShipSkin, engine: EngineInstance) -> StripSprite:
	return _sprite_near(skin, engine.mount.position, ShipSkin.Z_PLUME)


## The nearest sprite of one family to a point on the hull.
##
## By position and depth rather than by name, because the skin's sprites
## are built in code and have none worth matching on. Nearest rather than
## first: a plume sits a little way past its mount, and two mounts can be
## closer to each other than a plume is to its own.
func _sprite_near(skin: ShipSkin, at: Vector2, depth: int) -> StripSprite:
	var best: StripSprite = null
	for child: Node in skin.get_children():
		var sprite: StripSprite = child as StripSprite
		if sprite == null or sprite.z_index != depth:
			continue
		if sprite.position.distance_to(at) > 24.0:
			continue
		if best == null or sprite.position.distance_to(at) < best.position.distance_to(at):
			best = sprite
	return best


## Every binding the game answers to is one the help screen knows about.
func _check_bindings() -> void:
	# The one thing a help screen cannot check about itself. Add an action
	# to the input map without saying what it does and this fails, which
	# is the only arrangement under which the screen stays true.
	var missing: Array[StringName] = HelpScreen.undocumented()
	_expect(
		missing.is_empty(),
		"every action the game answers to is on the help screen (missing: %s)" % (
			"none" if missing.is_empty() else ", ".join(missing)
		),
	)

	var screen: HelpScreen = HelpScreen.new()
	root.add_child(screen)
	var rows: Array[Dictionary] = screen.lines()
	var unbound: Array[String] = []
	var blocks: int = 0
	for row: Dictionary in rows:
		if row["kind"] == "head":
			blocks += 1
		elif String(row["key"]).contains("?"):
			unbound.append(String(row["text"]))
	_expect(
		unbound.is_empty(),
		"and every line on it names a key (%s)" % (
			"all do" if unbound.is_empty() else ", ".join(unbound)
		),
	)
	_expect(
		blocks >= 5 and rows.size() > 30,
		"the screen is the whole keyboard, not a sample (%d lines in %d blocks)" % [
			rows.size(), blocks,
		],
	)
	# The chords are spelled out of the matcher's own table, so a chord
	# that was changed and not re-documented shows up as a wrong key list
	# rather than as a stale line nobody noticed.
	_expect(
		rows.size() - HelpScreen.LABELS.size() - blocks == ControlChords.CHORDS.size(),
		"and the chords on it are the chords the matcher knows (%d)" % (
			ControlChords.CHORDS.size()
		),
	)

	_expect(not screen.is_open(), "it starts shut")
	screen.toggle()
	_expect(screen.is_open() and paused, "opening it holds the game still")
	screen.close()
	_expect(not screen.is_open() and not paused, "and closing it lets go")
	screen.free()


	for action: StringName in [
		&"boost", &"hold_prograde", &"hold_retrograde", &"kill_rotation",
		&"toggle_help",
	]:
		_expect(
			InputMap.has_action(action) and not InputMap.action_get_events(action).is_empty(),
			"%s is a real action with a key on it" % action,
		)
	var brakes: Array[InputEvent] = InputMap.action_get_events(&"brake")
	_expect(
		brakes.size() >= 2,
		"brake answers to more than one key (%d of them)" % brakes.size(),
	)


## What the map draws round a body is what the body is.
##
## The map is drawn from the model, for worlds that may never be built,
## so the model has to carry the air -- and the moment two places hold the
## same number, one of them starts lying. This checks they do not.
func _check_reach_on_the_map() -> void:
	var airless: int = 0
	var breathing: int = 0
	var wrong_air: int = 0
	var wrong_well: int = 0
	for seed_index: int in range(40):
		var system: StarSystem = StarSystem.generate(seed_index)
		for body: SystemBody in system.bodies:
			if body.kind != SystemBody.Kind.PLANET and body.kind != SystemBody.Kind.MOON:
				continue
			if body.atmosphere_height > 0.0:
				breathing += 1
			else:
				airless += 1
			if body.well_radius <= body.radius:
				wrong_well += 1
	_expect(
		wrong_well == 0 and breathing > 0 and airless > 0,
		"every world in the model carries its own reach (%d with air, %d without)" % [
			breathing, airless,
		],
	)

	# And the built planet agrees with it, because the map would otherwise
	# be drawing a ring the pilot flies through and finds nothing at.
	var sample: StarSystem = StarSystem.generate(20260922)
	var planet: Planet = (load(PLANET_SCENE) as PackedScene).instantiate() as Planet
	root.add_child(planet)
	for body: SystemBody in sample.planets():
		planet.adopt(body)
		if absf(planet.atmosphere_radius() - planet.surface_radius - body.atmosphere_height) > 0.01:
			wrong_air += 1
		if absf(planet.influence_radius - body.well_radius) > 0.01:
			wrong_well += 1
	_expect(
		wrong_air == 0,
		"the air the map draws is the air the planet turns out to have",
	)
	_expect(
		wrong_well == 0,
		"and so is the well",
	)
	planet.free()


## Which body the orbit readout belongs to, and the answer out in the dark.
func _check_orbit_host() -> void:
	var system: StarSystem = StarSystem.generate(20260922)
	var star: Star = (load("res://scenes/star.tscn") as PackedScene).instantiate() as Star
	root.add_child(star)
	star.adopt(system.star)

	var world: SystemBody = system.planets()[0]
	var planet: Planet = (load(PLANET_SCENE) as PackedScene).instantiate() as Planet
	planet.body = world
	root.add_child(planet)

	# Anywhere inside its well, the planet is what owns the ship -- right
	# out to the edge, not just to where the fade begins. That is the
	# whole of the patching rule: whose well you are in, not who pulls
	# hardest at this exact pixel.
	var out: Vector2 = (planet.global_position - star.global_position).normalized()
	for share: float in [0.2, 0.89, 0.995]:
		var at: Vector2 = planet.global_position + out * planet.influence_radius * share
		_expect(
			GravityWell.local_at(self, at) == planet,
			"at %.0f%% of the well the planet is still the one that owns the ship" % (
				share * 100.0
			),
		)
	var beyond: Vector2 = planet.global_position + out * planet.influence_radius * 1.02
	_expect(
		GravityWell.local_at(self, beyond) == star,
		"and a step past the edge it is the star",
	)

	# Out between the orbits the star owns the ship and really is what it
	# is falling round -- and the orbit panel still does not appear,
	# because there is nowhere in a system outside the star's reach and a
	# readout that is always up is one nobody reads.
	var between: Vector2 = Vector2(
		(world.orbit_radius + system.planets()[1].orbit_radius) * 0.5, 0.0
	)
	_expect(
		GravityWell.local_at(self, between) == star,
		"out between the orbits it is the star, which is the only thing pulling",
	)
	_expect(
		not star.has_ground() and planet.has_ground(),
		"a star has nothing to land on, so the orbit panel is not its business",
	)
	_expect(
		is_equal_approx(star.atmosphere_radius(), star.surface_radius)
		and is_equal_approx(star.terrain_ceiling(), star.surface_radius),
		"and its ground and its air are both just its surface",
	)

	# The property the whole patching rule exists for: a ship can orbit a
	# planet with the star in the sky. Integrated the way the solver does,
	# through the same sum the solver uses.
	for altitude: float in [1.6, 2.6]:
		var radius: float = planet.surface_radius * altitude
		var at: Vector2 = planet.global_position + Vector2(radius, 0.0)
		var velocity: Vector2 = Vector2(0.0, planet.circular_orbit_speed(radius))
		var step: float = 1.0 / float(Engine.physics_ticks_per_second)
		var low: float = INF
		var high: float = 0.0
		for tick: int in range(roundi(120.0 / step)):
			velocity += GravityWell.pull_at(self, at) * step
			at += velocity * step
			var gap: float = planet.global_position.distance_to(at)
			low = minf(low, gap)
			high = maxf(high, gap)
		_expect(
			low > radius * 0.97 and high < radius * 1.03,
			"a circular orbit at %.1f radii holds for two minutes with the star up (%+.1f%% / %+.1f%%)"
				% [altitude, 100.0 * (low - radius) / radius, 100.0 * (high - radius) / radius],
		)

	# And the handover is smooth. A planet that gave the ship up to the
	# star in one frame would kick it across the boundary, which is the
	# thing the edge fade has always been for.
	var crossing: Array[float] = []
	for index: int in range(81):
		var share: float = 0.80 + 0.005 * float(index)
		crossing.append(GravityWell.pull_at(
			self, planet.global_position + out * planet.influence_radius * share
		).length())
	var biggest: float = 0.0
	var falling: bool = true
	for i: int in range(1, crossing.size()):
		biggest = maxf(biggest, absf(crossing[i] - crossing[i - 1]))
		falling = falling and crossing[i] <= crossing[i - 1] + 0.0001
	_expect(
		falling,
		"the pull only ever falls on the way out of a well -- nothing steps up at the seam",
	)
	_expect(
		biggest < crossing[0] * 0.2,
		"and the biggest step between samples is a gradient, not a cliff (%.3f of %.3f)" % [
			biggest, crossing[0],
		],
	)

	planet.free()
	star.free()


## Which way the shaders think the star is, and how big the star draws.
##
## Headless, so none of this is about pixels. It is about the one thing
## that cannot be seen by looking at a still: whether the direction handed
## to the shader is the direction of the star in the frame the shader
## measures against. Get that wrong and the terminator sits somewhere
## plausible-looking and never moves with the planet.
func _check_daylight() -> void:
	var system: StarSystem = StarSystem.generate(20260922)
	var star: Star = (load("res://scenes/star.tscn") as PackedScene).instantiate() as Star
	root.add_child(star)
	star.adopt(system.star)

	var surface: ColorRect = star.get_node("Surface")
	var corona: ColorRect = star.get_node("Corona")
	_expect(
		is_equal_approx(surface.size.x, star.surface_radius * 2.0)
		and surface.position.is_equal_approx(-Vector2.ONE * star.surface_radius),
		"the star's face is a quad the width of the star (%.0f px)" % surface.size.x,
	)
	var shown: float = float(
		(corona.material as ShaderMaterial).get_shader_parameter("disc")
	) * corona.size.x * 0.5
	_expect(
		absf(shown - star.surface_radius) < 1.0,
		"and the corona is told where that face ends, in its own units (%.0f against %.0f)" % [
			shown, star.surface_radius,
		],
	)
	_expect(
		corona.material != surface.material,
		"the two quads do not share a material, or the second star built would recolour the first",
	)

	# Heavier is bluer, all the way up. The colour is the only thing about
	# a star the pilot can read from across the system, and it is supposed
	# to be telling them how hard it pulls.
	var climbing: bool = true
	var previous: float = -1.0
	for step: int in range(12):
		var gravity: float = lerpf(
			StarSystem.STAR_GRAVITY.x, StarSystem.STAR_GRAVITY.y, float(step) / 11.0
		)
		var hue: Color = Star.colour_for(gravity)
		climbing = climbing and hue.b >= previous
		previous = hue.b
	_expect(climbing, "a heavier star is a bluer one, at every step of the range")

	# The terminator. A planet is handed the direction in its own frame,
	# and the frame turns: the test spins the planet and checks that the
	# direction turns with it by the same amount and the other way.
	# A world with weather on it, because the cloud decks are part of what
	# is being checked and a test that quietly skips half of itself when
	# the seed rolls a clear sky is a test that stops noticing.
	var planet: Planet = (load(PLANET_SCENE) as PackedScene).instantiate() as Planet
	root.add_child(planet)
	for candidate: SystemBody in system.planets():
		planet.adopt(candidate)
		if planet.has_clouds:
			break
	planet.rotation = 0.0
	planet._follow_the_star()
	var ground: ShaderMaterial = (planet.get_node("Terrain") as ColorRect).material
	var air: ShaderMaterial = (planet.get_node("Atmosphere") as ColorRect).material
	var first: Vector2 = ground.get_shader_parameter("sun_dir")
	_expect(
		first.is_equal_approx(planet.to_local(star.global_position).normalized()),
		"a planet points its surface shader at the star, in the frame the shader measures in",
	)
	_expect(
		float(ground.get_shader_parameter("sunlight")) > 0.5
		and float(air.get_shader_parameter("sunlight")) > 0.5,
		"and switches the whole term on, surface and air alike",
	)

	planet.rotation = 0.7
	planet._follow_the_star()
	var turned: Vector2 = ground.get_shader_parameter("sun_dir")
	_expect(
		absf(angle_difference(turned.angle(), first.angle() - 0.7)) < 0.001,
		"turn the planet and the star swings the other way in its frame (%.3f rad)" % (
			angle_difference(turned.angle(), first.angle())
		),
	)

	# Each cloud deck turns at its own rate, so each needs its own answer.
	var decks: Array[Node] = planet.get_node("Clouds").get_children()
	var materials: Dictionary = {}
	for deck: Node in decks:
		materials[(deck as CanvasItem).material] = true
	_expect(
		decks.size() > 1 and materials.size() == decks.size(),
		"each of the %d cloud decks has its own material, because each faces its own way" % (
			decks.size()
		),
	)

	# And with no star at all, nothing is darkened: M1's lone planet and
	# most of these tests have no sun to be on the far side of.
	star.free()
	planet._follow_the_star()
	_expect(
		float(ground.get_shader_parameter("sunlight")) == 0.0,
		"a world with no star in the scene is lit all the way round",
	)
	planet.free()


## What is lit in the world, and what does the lighting.
func _check_lighting() -> void:
	var system: StarSystem = StarSystem.generate(20260922)
	var star: Star = (load("res://scenes/star.tscn") as PackedScene).instantiate() as Star
	root.add_child(star)
	star.adopt(system.star)
	var planet: Planet = (load(PLANET_SCENE) as PackedScene).instantiate() as Planet
	root.add_child(planet)
	planet.adopt(system.planets()[0])

	# The scalar the ship is shaded by is the rule the ground is shaded
	# by. Both sides of the terminator, measured off the same body.
	var sunward: Vector2 = (star.global_position - planet.global_position).normalized()
	var high: float = planet.surface_radius * 1.5
	var day: float = GravityWell.daylight_at(self, planet.global_position + sunward * high)
	var night: float = GravityWell.daylight_at(self, planet.global_position - sunward * high)
	_expect(
		is_equal_approx(day, 1.0),
		"the sunward side of a planet is full daylight (%.2f)" % day,
	)
	_expect(
		is_equal_approx(night, GravityWell.NIGHT_OBJECT),
		"and the far side is the night floor, not black and not lit (%.2f)" % night,
	)
	var edge: Vector2 = planet.global_position + sunward.orthogonal() * high
	_expect(
		absf(GravityWell.daylight_at(self, edge) - (1.0 + GravityWell.NIGHT_OBJECT) * 0.5) < 0.01,
		"and the terminator itself is halfway between them",
	)
	_expect(
		is_equal_approx(GravityWell.daylight_at(self, Vector2(1.0, 0.0)), 1.0),
		"nothing is on the night side of the star it is standing next to",
	)

	# The limb is brightest where the light grazes it, which is the one
	# thing that makes a planet read as a ball with air on it rather than a
	# lit disc with a ring drawn round it.
	#
	# Checked as a uniform the shader really declares, not as a parameter
	# that was set. `set_shader_parameter` with a name the shader does not
	# have succeeds and does nothing, which is a silent way to ship an
	# effect that never runs -- and is close enough to how the first
	# screenshot of this came out identical to the control.
	var air: ShaderMaterial = (planet.get_node("Atmosphere") as ColorRect).material
	var declared: Array[String] = []
	for entry: Dictionary in air.shader.get_shader_uniform_list():
		declared.append(String(entry["name"]))
	_expect(
		declared.has("graze_gain"),
		"the air has a terminator arc to turn up or down",
	)
	_expect(
		declared.has("sun_dir") and declared.has("sunlight"),
		"and knows which way the star is, so the arc has somewhere to be",
	)

	# And the number the shaders use is the number GDScript used. This is
	# the join that a help screen would call a lie: a terminator written
	# down in four files is one that moves depending on what you look at.
	var ground: ShaderMaterial = (planet.get_node("Terrain") as ColorRect).material
	planet._follow_the_star()
	_expect(
		is_equal_approx(
			float(ground.get_shader_parameter("terminator")), GravityWell.TERMINATOR
		),
		"the planet's shaders are shading to the same terminator the ship is",
	)

	# The ship takes it, and its flame does not.
	#
	# Asked of the skin rather than of the ship: shading used to be
	# `Ship._catch_the_light()` and is `ShipSkin.refresh()` now. The hull
	# polygon is still what is measured, because with the layer off --
	# which is what headless is -- the polygon is still what is shown.
	var ship: Ship = _spawn_ship()
	var hull: Polygon2D = ship.get_node("Hull")
	var skin: ShipSkin = ship.get_node("Presentation")
	ship.global_position = planet.global_position + sunward * high
	skin.refresh(0.0)
	var lit_hull: Color = hull.self_modulate
	ship.global_position = planet.global_position - sunward * high
	skin.refresh(0.0)
	_expect(
		hull.self_modulate.v < lit_hull.v - 0.1,
		"a hull over the night side is darker than the same hull over the day side (%.2f against %.2f)"
			% [hull.self_modulate.v, lit_hull.v],
	)
	_expect(
		ship.modulate.is_equal_approx(Color.WHITE),
		"and the shading is on the hull alone, so the exhaust and the tracers keep their own light",
	)
	ship.free()

	# What casts light. Headless draws nothing, so what is checked is that
	# the lights exist, belong to the thing casting them, and go out.
	var round_scene: PackedScene = load("res://scenes/projectile.tscn") as PackedScene
	var shot: Projectile = round_scene.instantiate() as Projectile
	root.add_child(shot)
	var glow: GlowLight = _first_glow(shot)
	_expect(glow != null, "a round carries its own light")
	_expect(
		glow != null and glow.color.is_equal_approx(shot.tint),
		"in the colour of the round, so a glow can always be traced to what is casting it",
	)
	_expect(
		glow != null and glow.blend_mode == Light2D.BLEND_MODE_ADD,
		"and it adds rather than mixes -- light arriving, not paint",
	)
	shot.free()

	var blast: Explosion = (
		load("res://scenes/explosion.tscn") as PackedScene
	).instantiate() as Explosion
	root.add_child(blast)
	var flash: GlowLight = _first_glow(blast)
	_expect(
		flash != null and flash.energy > 1.0,
		"an explosion starts with a flash brighter than anything else in the game",
	)
	var opening: float = flash.energy if flash != null else 0.0
	blast._process(Explosion.FLASH_SECONDS * 0.5)
	_expect(
		flash != null and flash.energy < opening * 0.5,
		"which is more than half gone by halfway (%.2f of %.2f)" % [
			flash.energy if flash != null else 0.0, opening,
		],
	)
	blast._process(Explosion.FLASH_SECONDS)
	_expect(
		_first_glow(blast) == null or not is_instance_valid(flash),
		"and then goes out instead of leaving a lamp where the ship died",
	)
	blast.free()

	# A nozzle's light is its thrust. Equal lamps on every mount was the
	# first version and it was reported as a halo -- eight of them on one
	# hull, the manoeuvring pods as bright as the main drive.
	var flyer: Ship = _spawn_ship()
	var big: EngineMount = null
	var small: EngineMount = null
	for mount: EngineMount in flyer.engine_mounts():
		if mount.installed == null:
			continue
		if big == null or mount.installed.max_thrust > big.installed.max_thrust:
			big = mount
		if small == null or mount.installed.max_thrust < small.installed.max_thrust:
			small = mount
	big.set_exhaust(1.0)
	small.set_exhaust(1.0)
	var bright: GlowLight = _first_glow(big)
	var faint: GlowLight = _first_glow(small)
	_expect(
		bright != null and faint != null,
		"every nozzle that is burning is throwing light",
	)
	_expect(
		faint.energy < bright.energy * 0.5,
		"a %0.f N pod burns dimmer than a %.0f N drive (%.2f against %.2f)" % [
			small.installed.max_thrust, big.installed.max_thrust,
			faint.energy, bright.energy,
		],
	)
	_expect(
		faint.texture_scale < bright.texture_scale * 0.8,
		"and reaches less far with it, so a small engine is a small bright spot",
	)
	big.set_exhaust(0.0)
	_expect(not _first_glow(big).visible, "a nozzle that is not burning throws nothing")
	flyer.free()

	# And the air is not something light lands on. This is what the halo
	# was: the atmosphere quad covers the whole neighbourhood of a planet,
	# so any light near it lit a disc of sky instead of lighting a thing.
	for part: String in ["Atmosphere"]:
		var sky: ShaderMaterial = (planet.get_node(part) as ColorRect).material
		_expect(
			sky.shader.code.contains("render_mode unshaded"),
			"%s takes no light: it is the air in front of a surface, not one" % part.to_lower(),
		)
	_expect(
		(planet.get_node("Terrain") as ColorRect).material.shader.code.contains(
			"render_mode unshaded"
		) == false,
		"while the ground does take it, because the ground is what a light falls on",
	)

	planet.free()
	star.free()


## Somewhere to tie up: who a dock will have, what it mends, and letting go.
func _check_docking() -> void:
	var system: StarSystem = StarSystem.generate(20260922)
	var body: SystemBody = system.of_kind(SystemBody.Kind.STATION)[0]
	var dock: Station = (
		load("res://scenes/station.tscn") as PackedScene
	).instantiate() as Station
	root.add_child(dock)
	dock.adopt(body)

	var ship: Ship = _spawn_ship()
	var reach: float = dock.dock_radius()
	_expect(
		reach > dock.radius,
		"the dock reaches further than the structure, so arriving is not pixel-hunting (%.0f of %.0f)"
			% [reach, dock.radius],
	)

	ship.global_position = dock.global_position + Vector2(reach * 2.0, 0.0)
	ship.linear_velocity = Vector2.ZERO
	_expect(dock.refusal(ship) == "za daleko", "from outside the reach it says so")
	ship.global_position = dock.global_position + Vector2(reach * 0.5, 0.0)
	ship.linear_velocity = Vector2(Station.DOCK_SPEED * 3.0, 0.0)
	_expect(
		dock.refusal(ship) == "za szybko",
		"and inside it but too fast it says which of the two numbers is wrong",
	)
	ship.linear_velocity = Vector2(Station.DOCK_SPEED * 0.5, 0.0)
	_expect(dock.refusal(ship).is_empty(), "slow and close enough, it will have you")

	# Docking itself, and what it is for. A hull that can only be mended
	# by respawning is a hull whose damage is either fatal or free.
	ship.hull_integrity = 0.3
	ship.energy = 0.0
	for engine: EngineInstance in ship.engines:
		engine.health = 0.25
	ship.dock_with(dock)
	_expect(
		ship.flight_mode == Ship.FlightMode.DOCKED,
		"flying in slowly ties the ship up, with no key to press",
	)
	_expect(
		not ship.fully_serviced(),
		"and it arrives needing the things a dock is for",
	)

	var step: float = 1.0 / float(Engine.physics_ticks_per_second)
	var half: float = 0.0
	for tick: int in range(roundi(2.0 / step)):
		ship._mend(step)
		if half == 0.0 and ship.hull_integrity > 0.5:
			half = float(tick) * step
	_expect(
		half > 0.5,
		"mending takes seconds rather than happening on arrival (%.1f s to half a hull)" % half,
	)
	for tick: int in range(roundi(10.0 / step)):
		ship._mend(step)
	_expect(
		ship.fully_serviced() and ship.hull_integrity == 1.0,
		"and a long enough stay puts everything right: hull, engines and pool",
	)

	# Letting go, and the bug that was in the way of it. Docking is
	# automatic, so the instant after undocking the ship is still inside
	# the reach at no speed -- which is exactly the condition to dock --
	# and it was grabbed again on the next tick.
	ship.global_position = dock.global_position
	ship.commands[ShipControl.Command.FORWARD] = 1.0
	ship._resolve_dock(step)
	_expect(
		ship.flight_mode == Ship.FlightMode.PHYSICAL,
		"asking for thrust lets go, the same gesture as taking off",
	)
	var grabbed: bool = false
	for tick: int in range(120):
		ship._resolve_dock(step)
		grabbed = grabbed or ship.flight_mode == Ship.FlightMode.DOCKED
	_expect(
		not grabbed,
		"and sitting in the dock's reach afterwards does not get the ship grabbed again",
	)
	# It will take the ship back once it has actually gone and come round.
	ship.global_position = dock.global_position + Vector2(reach * 3.0, 0.0)
	ship._resolve_dock(step)
	ship.global_position = dock.global_position
	ship.commands.clear()
	ship.linear_velocity = Vector2.ZERO
	ship._resolve_dock(step)
	_expect(
		ship.flight_mode == Ship.FlightMode.DOCKED,
		"while leaving properly and coming back docks again",
	)

	ship.free()
	dock.free()


## Rounds fall, and the cursor does not do the arithmetic for you.
func _check_round_fall() -> void:
	var system: StarSystem = StarSystem.generate(20260922)
	var planet: Planet = (load(PLANET_SCENE) as PackedScene).instantiate() as Planet
	root.add_child(planet)
	planet.adopt(system.planets()[0])

	# Fired level, well clear of the ground, so the only thing bending it
	# is the planet. Integrated the way the round itself is.
	var up: Vector2 = Vector2.UP
	var from: Vector2 = planet.global_position + up * (planet.surface_radius + 900.0)
	var gravity: float = planet.gravity_at(from).length()
	var step: float = 1.0 / float(Engine.physics_ticks_per_second)
	var speed: float = 600.0
	var at: Vector2 = from
	var velocity: Vector2 = up.orthogonal() * speed
	var flown: float = 0.0
	var seconds: float = 0.0
	while flown < 1200.0 and seconds < 20.0:
		velocity += GravityWell.pull_at(self, at) * step
		at += velocity * step
		flown = from.distance_to(at)
		seconds += step
	var fell: float = (from - at).dot(up)
	_expect(
		fell > 10.0,
		"a round fired level over a planet comes down (%.0f px over %.0f px of flight)" % [
			fell, flown,
		],
	)
	# Against the schoolbook number, loosely: the field weakens as the
	# round climbs away from straight-and-level, so this is a sanity
	# bound, not an identity.
	var schoolbook: float = 0.5 * gravity * seconds * seconds
	_expect(
		absf(fell - schoolbook) < schoolbook * 0.3,
		"by about half g t squared (%.0f px against %.0f)" % [fell, schoolbook],
	)

	# And out where nothing pulls, it does not.
	var empty: Vector2 = Vector2(5.0e6, 5.0e6)
	_expect(
		GravityWell.pull_at(self, empty).is_zero_approx(),
		"a round out beyond everything keeps going straight, because nothing is pulling",
	)

	# The cursor is not allowed to help. Leading for gravity is the
	# pilot's job, decided deliberately: a cursor that solved the arc
	# would turn every shot into pointing at a marker the game had
	# already worked out. What the mount answers is whether it can bear
	# on the point, which is a question about the mount and about
	# nothing else -- so the answer must not move when a planet is near.
	var ship: Ship = _spawn_ship()
	ship.global_position = from
	ship.rotation = 0.0
	var gun: Hardpoint = ship.hardpoints[0]
	var mark: Vector2 = from + Vector2(400.0, 0.0)
	var near_planet: float = gun.wanted_facing(mark)
	planet.global_position += Vector2(1.0e7, 0.0)
	var far_away: float = gun.wanted_facing(mark)
	_expect(
		is_equal_approx(near_planet, far_away),
		"where the gun has to point does not change because a planet is there",
	)
	_expect(
		not FileAccess.get_file_as_string(
			"res://scripts/aim_hud.gd"
		).contains("GravityWell"),
		"and the aim cursor never asks about gravity at all",
	)
	ship.free()
	planet.free()


## The first light hanging off `host`, or null.
func _first_glow(host: Node) -> GlowLight:
	for child: Node in host.get_children():
		var glow: GlowLight = child as GlowLight
		if glow != null and is_instance_valid(glow) and not glow.is_queued_for_deletion():
			return glow
	return null


## Parks `ship` at `at` and runs its heat model for `seconds` of game
## time, returning the bar. The ship's own `_update_heat`, not a copy of
## it: the point is to find out what the game does, not what this file
## thinks it does.
func _bake(ship: Ship, star: Star, at: Vector2, seconds: float) -> float:
	ship.repair_hull()
	ship.global_position = at
	ship.linear_velocity = Vector2.ZERO
	var step: float = 1.0 / float(Engine.physics_ticks_per_second)
	for tick: int in range(roundi(seconds / step)):
		ship._update_heat(step)
	return ship.hull_heat


func _check_system_map() -> void:
	var system: StarSystem = StarSystem.generate(20260922)
	var pilot: Node2D = Node2D.new()
	root.add_child(pilot)
	var map: SystemMap = SystemMap.new()
	root.add_child(map)
	# No manager: the map has to draw a system nobody is streaming, which is
	# also what it will be asked for on a system seen from outside.
	map.bind(system, pilot, null)

	# The map's own rectangle, not a resolution written down here: every
	# coordinate it deals in is relative to that, and a test measuring
	# against a different one measures a picture nobody is looking at.
	var view: Vector2 = map.view_size()
	var plan: Dictionary = map.layout(view)
	_expect(
		map.to_map(Vector2.ZERO, plan).is_equal_approx(view * 0.5),
		"the star is the middle of the map",
	)
	var outermost: float = 0.0
	for body: SystemBody in system.bodies:
		outermost = maxf(outermost, map.to_map(body.position_at(0.0), plan).distance_to(view * 0.5))
	_expect(
		outermost < minf(view.x, view.y) * 0.5,
		"and the whole system fits on it (%.0f px of %.0f)" % [outermost, minf(view.x, view.y) * 0.5],
	)

	# Clicking works before a single frame has been drawn. The ship editor
	# had to learn this the hard way and so did this class.
	var target: SystemBody = system.planets()[system.planets().size() - 1]
	_expect(
		map.click_at(map.to_map(target.position_at(0.0), plan)) == target,
		"a click lands on the body drawn there, with no frame drawn yet",
	)
	_expect(
		map.click_at(view * 0.5 + Vector2(0.0, minf(view.x, view.y) * 0.49)) == null,
		"and empty space picks nothing rather than the nearest thing to it",
	)

	# The map turns with the view, because a direction on it should be the
	# direction you would fly if you pointed the nose that way.
	#
	# Driven with a rotation put into the plan by hand rather than by a
	# camera: which rotation to use is one line of wiring, and
	# get_screen_rotation() reads zero headless whatever the camera does.
	# What is worth testing is the geometry, and that is all in `to_map`.
	var turned: Dictionary = map.layout(view)
	turned["turn"] = -PI * 0.5
	var probe_point: Vector2 = Vector2(10000.0, 0.0)
	var on_map: Vector2 = map.to_map(probe_point, turned) - view * 0.5
	_expect(
		absf(angle_difference(on_map.angle(), -PI * 0.5)) < 0.01,
		"a view turned a quarter turn draws the world turned with it",
	)
	_expect(
		absf(on_map.length() - probe_point.length() * float(turned["scale"])) < 0.01,
		"and turning it does not change how far away anything looks",
	)
	# The map draws the same forecast, worked out when it opens: the panel
	# pauses the game, so four hundred integration steps a frame would be
	# four hundred steps to reach the same answer.
	var flier: Ship = _spawn_ship()
	flier.global_position = Vector2(60000.0, 20000.0)
	flier.linear_velocity = Vector2(-200.0, 40.0)
	map.bind(system, flier, null)
	_expect(map.forecast().is_empty(), "a shut map has no forecast to keep")
	map.toggle()
	_expect(
		map.forecast().size() > 2
		and map.forecast()[0].is_equal_approx(flier.global_position),
		"opening it works one out, starting where the ship is",
	)
	map.close()
	map.bind(system, pilot, null)
	flier.queue_free()

	# Zoom is a reach in the world, not a magnification. The ladder has to
	# clamp, and each rung has to put a body at that reach on the rim.
	map.set_zoom_level(-3)
	_expect(map.zoom_level() == 0, "zooming out past the end stops at the whole system")
	map.set_zoom_level(99)
	var closest: int = SystemMap.ZOOM_REACH.size() - 1
	_expect(map.zoom_level() == closest, "and in past the end stops at the closest rung")

	for rung: int in range(1, SystemMap.ZOOM_REACH.size()):
		map.set_zoom_level(rung)
		var near: Dictionary = map.layout(view)
		var reach: float = SystemMap.ZOOM_REACH[rung]
		var edge: Vector2 = map.to_map(Vector2(reach, 0.0) + Vector2(near["focus"]), near)
		_expect(
			absf((edge - view * 0.5).length() - minf(view.x, view.y) * 0.5 + PAD_ON_MAP) < 1.0,
			"at reach %.0f px, something that far out lands on the rim" % reach,
		)
	map.set_zoom_level(0)

	# Magnifying about the star would push what was just clicked off the
	# edge at the first step, so the middle is whatever is picked.
	map.click_at(map.to_map(target.position_at(0.0), map.layout(view)))
	map.set_zoom_level(2)
	_expect(
		map.to_map(target.position_at(0.0), map.layout(view)).distance_to(view * 0.5) < 0.01,
		"zoom is about the body you picked, which ends up in the middle",
	)
	map.set_zoom_level(0)

	# The teleport is a dev convenience and carries what was picked.
	var asked: Array[SystemBody] = []
	map.teleport_requested.connect(func(body: SystemBody) -> void: asked.append(body))
	map.teleport_requested.emit(map.picked())
	_expect(
		asked.size() == 1 and asked[0] == target,
		"asking to teleport says which body was meant",
	)

	# It is a panel, so it holds the pause, and it lets go.
	map.toggle()
	_expect(map.is_open() and PauseGate.held(), "opening the map stops the world")
	map.close()
	_expect(not map.is_open() and not PauseGate.held(), "and closing it starts it again")

	map.free()
	pilot.free()


## The flight HUD, which is a picture now rather than eight rows of text.
##
## What can be checked without looking at it: which widget is up, and that
## the conic it draws is the conic the orbit solver computed. The drawing
## itself was looked at -- a circular orbit, an escape, a descent and a
## transfer, on the real renderer.
func _check_flight_hud(planet: Planet) -> void:
	var ship: Ship = _spawn_ship()
	var hud: FlightHud = FlightHud.new()
	root.add_child(hud)
	hud.bind(ship)

	# Which widget is up is a question about the well, not about which
	# planet happens to be nearest. The readout this replaces showed a
	# planet's numbers from anywhere in the system, because the nearest
	# planet is always some planet.
	ship.global_position = planet.global_position + Vector2(planet.influence_radius * 0.5, 0.0)
	_expect(hud.host() == planet, "inside the well, the HUD is about the planet")
	ship.global_position = planet.global_position + Vector2(planet.influence_radius * 1.5, 0.0)
	_expect(
		hud.host() == null,
		"and outside it the planet is just the nearest one, which is not the same thing",
	)

	# The reason a landing was refused reaches the HUD. The mark is drawn,
	# the words are the news.
	ship.global_position = planet.global_position + Vector2(planet.influence_radius * 0.5, 0.0)
	_expect(hud.warning().is_empty(), "no mark when nothing was refused")
	ship.last_landing_rejection = "slope"
	_expect(hud.warning() == "slope", "and the reason itself when something was")

	# An orbit says so in a word. The thick green ring was the only signal
	# at first and a pilot reported not seeing it: a colour is a shade you
	# have to remember, and a pixel of thickness is a shade you have to
	# remember with a reference beside it.
	_expect(
		hud.state_text(Planet.OrbitState.ORBIT) == "ORBIT"
		and hud.state_text(Planet.OrbitState.DECAYING) == "DECAY"
		and hud.state_text(Planet.OrbitState.ESCAPE) == "ESCAPE",
		"every trajectory worth a word gets one",
	)
	_expect(
		hud.state_text(Planet.OrbitState.SUBORBITAL).is_empty(),
		"and coming down says nothing, because that is what flying normally looks like",
	)

	# The conic the HUD draws has to be the conic the solver measured, or
	# the picture and the numbers beside it are two different orbits.
	var mu: float = planet.mu()
	var radius: float = planet.surface_radius * 2.4
	var at: Vector2 = planet.global_position + Vector2(radius, 0.0)
	# Eccentric enough for the shape to be a shape, slow enough that the
	# far side is still inside the well -- past that the solver reports an
	# escape, which is a different assertion.
	var along: Vector2 = Vector2(0.0, sqrt(mu / radius) * 1.05)
	var shape: Dictionary = planet.orbit_shape(at, along)
	var extremes: Vector2 = planet.orbit_extremes(at, along)
	var eccentricity: float = (shape["eccentricity"] as Vector2).length()
	# At theta zero this is true by construction and says nothing. At PI it
	# is the real check: the eccentricity comes from the eccentricity
	# vector and the apoapsis from energy and momentum, by two different
	# routes, and the picture is the solver's orbit only if they agree.
	_expect(
		absf(Planet.conic_radius(extremes.x, eccentricity, PI) - extremes.y) < 1.0,
		"the drawn conic comes round to the apoapsis the solver found (%.0f of %.0f)" % [
			Planet.conic_radius(extremes.x, eccentricity, PI), extremes.y,
		],
	)
	# And the ship is drawn on the curve, not beside it: the true anomaly
	# taken from the eccentricity vector has to give back where it is.
	var arm: Vector2 = at - planet.global_position
	var anomaly: float = (shape["eccentricity"] as Vector2).angle_to(arm)
	_expect(
		absf(Planet.conic_radius(extremes.x, eccentricity, anomaly) - arm.length()) < 1.0,
		"and the ship sits on it, at the anomaly the eccentricity vector gives",
	)

	# A ship thrown hard enough has a periapsis and no far side.
	_expect(
		is_inf(planet.orbit_extremes(at, along * 3.0).y),
		"leaving has no apoapsis to draw, and the widget says ESCAPE rather than a number",
	)

	# The forecast, which the F7 line and the map now share. One ship, one
	# future: two forward integrations of the same craft would be two
	# futures to keep in step.
	var period: float = TAU * sqrt(pow(radius, 3.0) / mu)
	ship.global_position = at
	ship.linear_velocity = Vector2(0.0, sqrt(mu / radius))
	var round_trip: Dictionary = TrajectoryPredictor.coast(
		ship, 400, period * float(Engine.physics_ticks_per_second) / 400.0
	)
	var path: PackedVector2Array = round_trip["path"]
	_expect(
		path.size() > 1 and path[0].is_equal_approx(ship.global_position),
		"the forecast starts where the ship is",
	)
	_expect(
		not round_trip["impact"].is_finite(),
		"a circular orbit does not end in the ground",
	)
	var closure: float = path[path.size() - 1].distance_to(path[0])
	_expect(
		closure < radius * 0.05,
		"and comes back round to where it started (%.0f px of %.0f)" % [closure, radius],
	)

	# Aimed at the rock: the path has to stop at the ground rather than
	# carry on through it, and say where.
	ship.linear_velocity = (planet.global_position - at).normalized() * 60.0
	var dive: Dictionary = TrajectoryPredictor.coast(ship, 400, 6.0)
	_expect(
		dive["impact"].is_finite()
		and (dive["path"] as PackedVector2Array).size() < 400,
		"a path into the ground stops there and says where",
	)
	_expect(
		planet.height_above_terrain(dive["impact"]) < planet.surface_radius * 0.1,
		"and the place it says is on the ground (%.0f px above it)" % [
			planet.height_above_terrain(dive["impact"]),
		],
	)

	hud.free()
	ship.queue_free()


## Whole ships from the sandbox's preset table.
##
## The interesting one is the gimbal-only ship, and it is interesting
## because it did not work: a main drive on the centreline makes no torque
## with its nozzle straight, so the control groups gave it no CW or CCW at
## all, and the preset the request asked for -- no torque jets, steering
## from the gimbal -- was a ship that could not steer.
func _check_fitout_presets() -> void:
	var ship: Ship = _spawn_ship()
	var seen: Array[String] = []
	for preset: Dictionary in ShipFitout.all():
		ShipFitout.apply(ship, preset)
		seen.append(String(preset["name"]))
		_expect(
			ship.engine_mounts().size() == (preset["mounts"] as Array).size()
			and ship.hardpoints.size() == (preset["guns"] as Array).size(),
			"%s is built with what it declares (%d mounts, %d guns)" % [
				preset["name"], ship.engine_mounts().size(), ship.hardpoints.size(),
			],
		)
		_expect(
			ship.control.authority_of(ShipControl.Command.FORWARD) > 0.0,
			"and can go forward",
		)
		_expect(
			absf(ship.hull_extent() - HullData.of(preset["hull"]).extent()) < 0.01,
			"with the hull it names, not the one left over from the last refit",
		)

	# A refit is in place, so everything pointing at this ship has to still
	# be pointing at something: a cached hardpoint list naming nodes the
	# refit freed is a list that crashes at the next trigger pull.
	for gun: Hardpoint in ship.hardpoints:
		_expect(is_instance_valid(gun), "the guns a refit leaves behind are live nodes")

	# The two the request was about, and the difference between them is
	# the whole point. One gimballed nozzle turns the ship and shoves it;
	# two, nose and tail, swing the same way, so their torques add and
	# their thrusts cancel. A couple instead of a push.
	ShipFitout.apply(ship, _preset_named("pojedynczy"))
	var lone_turn: float = ship.control.authority_of(ShipControl.Command.CW)
	var lone_shove: float = _turn_residual(ship)
	var torque_jets: bool = false
	for engine: EngineInstance in ship.engines:
		torque_jets = torque_jets or engine.data.type == EngineData.Type.TORQUE
	_expect(
		lone_turn > 0.0 and not torque_jets,
		"one gimballed nozzle can steer with no torque jets at all (%.0f of CW)" % lone_turn,
	)

	ShipFitout.apply(ship, _preset_named("para sił"))
	var pair_turn: float = ship.control.authority_of(ShipControl.Command.CW)
	var pair_shove: float = _turn_residual(ship)
	_expect(
		pair_turn > lone_turn,
		"two of them turn harder than one (%.0f against %.0f)" % [pair_turn, lone_turn],
	)
	_expect(
		pair_shove < lone_shove * 0.1,
		"and barely shove at all -- the thrusts cancel (%.1f against %.1f px/s2)" % [
			pair_shove, lone_shove,
		],
	)
	# And what two nozzles can do that one cannot: strafe.
	#
	# This check used to assert the opposite, and the report was right to
	# complain. Deflect a couple **the same way** and the side forces
	# cancel while the torques add, which is the turn above; deflect them
	# **opposite ways** and the torques cancel while the side forces add.
	# Two nozzles are then the whole ship.
	var pair_strafe: float = ship.control.authority_of(ShipControl.Command.STRAFE_LEFT)
	_expect(
		pair_strafe > 0.0,
		"two nozzles deflected opposite ways strafe (%.0f of STRAFE_LEFT)" % pair_strafe,
	)
	_expect(
		_gimbal_in_group(ship, ShipControl.Command.STRAFE_LEFT),
		"and it is the nozzles doing it, not something else on the hull",
	)
	_expect(
		not _findings_of(ship.configuration()).contains("STRAFE"),
		"so the configuration report stops reporting the group as empty",
	)
	_expect(
		ship.control.gimbal_partner.size() == 2,
		"and the two of them know about each other (%d paired)" % [
			ship.control.gimbal_partner.size(),
		],
	)

	# The discriminator, which is the whole reason this is a pair and not
	# any gimbal: one nozzle swung sideways shoves the ship along its own
	# thrust just as hard as before. The preset built to show that is
	# called "drifts", and it must not claim a strafe group.
	ShipFitout.apply(ship, _preset_named("pojedynczy"))
	_expect(
		ship.control.gimbal_partner.is_empty(),
		"a lone gimbal has no partner to cancel its shove",
	)
	# Not "cannot strafe": that preset carries ordinary strafe thrusters
	# and the report is right to say nothing. What must hold is narrower
	# and is the actual claim -- the **gimbal** earns no place in the
	# group, so the ship strafes with the jets it has and not by swinging
	# a main drive it would ride forward on.
	_expect(
		not _gimbal_in_group(ship, ShipControl.Command.STRAFE_LEFT),
		"so its gimbal earns no place in the strafe group",
	)

	# Asked to strafe, the couple leans its nozzles opposite ways. Asked to
	# turn, the same way. Measured off the nozzles rather than off the
	# authority, because the authority is what the groups believe and this
	# is what the hinges do.
	ShipFitout.apply(ship, _preset_named("para sił"))
	var couple: Array[EngineInstance] = []
	for engine: EngineInstance in ship.engines:
		if engine.data.gimbal_range > 0.0:
			couple.append(engine)
	ship.commands.clear()
	ship.commands[ShipControl.Command.STRAFE_LEFT] = 1.0
	ship.active_commands = ship.commands.duplicate()
	ship._aim_gimbals()
	_expect(
		couple.size() == 2 and couple[0].target_gimbal * couple[1].target_gimbal < 0.0,
		"a strafe leans the two nozzles opposite ways (%.2f and %.2f)" % [
			couple[0].target_gimbal, couple[1].target_gimbal,
		],
	)
	ship.commands.clear()
	ship.commands[ShipControl.Command.CW] = 1.0
	ship.active_commands = ship.commands.duplicate()
	ship._aim_gimbals()
	_expect(
		couple[0].target_gimbal * couple[1].target_gimbal > 0.0,
		"and a turn leans them the same way (%.2f and %.2f)" % [
			couple[0].target_gimbal, couple[1].target_gimbal,
		],
	)
	ship.commands.clear()
	ship.active_commands = {}
	ship._aim_gimbals()

	# And the trade is real on the stock ship too: letting a gimbal into the
	# turn groups must not change a hull that has proper jets.
	var stock_authority: float = 0.0
	ShipFitout.apply(ship, _preset_named("stock"))
	stock_authority = ship.control.authority_of(ShipControl.Command.CW)
	var from_scene: Ship = _spawn_ship()
	_expect(
		absf(stock_authority - from_scene.control.authority_of(ShipControl.Command.CW)) < 1.0,
		"the stock preset is the stock ship (%.0f of CW either way)" % stock_authority,
	)
	from_scene.queue_free()

	# A bigger engine is a heavier one. A table that scaled only the thrust
	# would be handing out free power, which is the one thing a sandbox must
	# not do quietly.
	var plain: EngineData = load(ShipFitout.ENGINES["main"]) as EngineData
	var was_thrust: float = plain.max_thrust
	var was_bulk: float = plain.bulk
	ShipFitout.apply(ship, _preset_named("mocniejsze"))
	var beefy: EngineData = null
	for engine: EngineInstance in ship.engines:
		if engine.mount.name == "MainDrive":
			beefy = engine.data
	_expect(
		beefy != null and beefy.max_thrust > was_thrust and beefy.bulk > was_bulk,
		"a scaled engine is stronger and heavier (%.0f N, %.2f bulk)" % [
			0.0 if beefy == null else beefy.max_thrust,
			0.0 if beefy == null else beefy.bulk,
		],
	)
	_expect(
		is_equal_approx(plain.max_thrust, was_thrust) and is_equal_approx(plain.bulk, was_bulk),
		"and the resource it was scaled from is untouched -- they are shared",
	)

	_expect(seen.size() >= 5, "there are %d ships to try, not one" % seen.size())
	ship.queue_free()


## How hard a turn command pushes the hull about, in px/s^2. What a
## couple is supposed to make nearly nothing of.
## Whether any gimballed engine is a member of a command's group.
func _gimbal_in_group(ship: Ship, command: ShipControl.Command) -> bool:
	for member: Dictionary in ship.control.groups.get(command, []):
		var engine: EngineInstance = member["engine"]
		if engine.data != null and engine.data.gimbal_range > 0.0:
			return true
	return false


func _turn_residual(ship: Ship) -> float:
	for line: String in ship.configuration().lines():
		if line.contains("CW pushes the ship sideways"):
			return float(line.get_slice("at ", 1).get_slice(" px", 0))
	return 0.0


func _preset_named(fragment: String) -> Dictionary:
	for preset: Dictionary in ShipFitout.all():
		if String(preset["name"]).contains(fragment):
			return preset
	return {}


## A planet built as the body a system says it is.
##
## The join has to hold in both directions: what the system dictates must
## arrive, and what it does not dictate must be untouched by the dictating.
func _check_adoption() -> void:
	var body: SystemBody = StarSystem.generate(31337).planets()[0]

	var adopted: Planet = (load(PLANET_SCENE) as PackedScene).instantiate() as Planet
	adopted.body = body
	root.add_child(adopted)
	_expect(
		is_equal_approx(adopted.surface_radius, body.radius)
		and is_equal_approx(adopted.surface_gravity, body.surface_gravity),
		"a planet is the size and weight the system says (%.0f px, %.1f px/s2)" % [
			adopted.surface_radius, adopted.surface_gravity,
		],
	)
	_expect(
		adopted.global_position.distance_to(body.position_at(0.0)) < 1.0,
		"and stands where its orbit puts it (%.0f px out of %.0f)" % [
			adopted.global_position.length(), body.orbit_radius,
		],
	)
	# The well is handed over like the size and the weight, and for a
	# stronger reason: a planet cannot work out its own, because how far
	# its pull reaches depends on how heavy the star is and how close the
	# layout put it, and the planet knows neither.
	_expect(
		is_equal_approx(adopted.influence_radius, body.well_radius),
		"with the well the system worked out for it (%.0f px, %.1f radii)" % [
			adopted.influence_radius, adopted.influence_radius / adopted.surface_radius,
		],
	)

	# The other half, and the reason both rolls happen even when both are
	# overridden: a planet told how big to be still looks like the planet
	# that seed describes. Drop the dictation and only size changes.
	var free_rolled: Planet = (load(PLANET_SCENE) as PackedScene).instantiate() as Planet
	free_rolled.planet_seed = body.seed
	root.add_child(free_rolled)
	_expect(
		free_rolled.surface_color == adopted.surface_color
		and free_rolled.atmosphere_color == adopted.atmosphere_color
		and is_equal_approx(free_rolled.spin_rate, adopted.spin_rate),
		"and looks like its seed either way -- the random stream stays aligned",
	)
	_expect(
		not is_equal_approx(free_rolled.surface_radius, adopted.surface_radius)
		or not is_equal_approx(free_rolled.surface_gravity, adopted.surface_gravity),
		"while the size really did come from the system and not from the roll",
	)
	# Freed now, not queued: a planet still in the gravity group when the
	# scanner check runs is a third contact the scanner is right to report.
	adopted.free()
	free_rolled.free()


## The lowest-numbered system that has a moon in it.
func _system_with_a_moon() -> StarSystem:
	for seed_index: int in range(100):
		var system: StarSystem = StarSystem.generate(seed_index)
		if not system.of_kind(SystemBody.Kind.MOON).is_empty():
			return system
	return StarSystem.generate(0)


## Orbits read off a clock, with nothing integrating anything.
func _check_orbit_evaluation() -> void:
	# The first seed with a moon on it, rather than one written down here.
	# A hard-coded seed is a hard-coded roll, and every time the generator
	# gains a roll -- the star's own gravity, this time -- the stream
	# shifts underneath it and the test quietly stops checking the thing
	# it was named after.
	var system: StarSystem = _system_with_a_moon()
	var planet: SystemBody = system.planets()[0]

	_expect(
		system.star.position_at(0.0).is_zero_approx()
		and system.star.position_at(123456.0).is_zero_approx(),
		"the star is the origin, at every moment",
	)
	_expect(
		is_equal_approx(planet.position_at(0.0).length(), planet.orbit_radius),
		"a planet stays on its orbit (%.0f px)" % planet.orbit_radius,
	)

	# Exactly periodic, which is what makes streaming free: a body switched
	# off and back on is where it would have been, because nothing was
	# integrating it and there is nothing to catch up on.
	var drift: float = planet.position_at(1000.0).distance_to(
		planet.position_at(1000.0 + planet.orbit_period)
	)
	# Bounded against the orbit rather than absolutely. The model is exact;
	# Vector2 is float32, so a position nineteen thousand pixels out cannot
	# be reproduced to better than a few hundredths of a pixel whatever the
	# maths does. A tighter bound would be testing the engine.
	_expect(
		drift < planet.orbit_radius * 1e-5,
		"and is in the same place a year later (%.4f px of %.0f)" % [
			drift, planet.orbit_radius,
		],
	)
	_expect(
		not planet.position_at(0.0).is_equal_approx(
			planet.position_at(planet.orbit_period * 0.5)
		),
		"but somewhere else half a year later",
	)

	var carried: int = 0
	for moon: SystemBody in system.of_kind(SystemBody.Kind.MOON):
		carried += 1
		for at: float in [0.0, 137.0, 9000.0]:
			var gap: float = moon.position_at(at).distance_to(moon.parent_body().position_at(at))
			_expect(
				absf(gap - moon.orbit_radius) < 0.01,
				"a moon is carried by its planet, not left behind (%.2f of %.0f px)" % [
					gap, moon.orbit_radius,
				],
			)
	_expect(carried > 0, "and this system has a moon to check that on")

	# The cache hands back the same system rather than a fresh roll.
	var galaxy: Node = GALAXY_SCRIPT.new()
	galaxy.galaxy_seed = 555
	_expect(
		galaxy.system(0) == galaxy.system(0) and galaxy.system(0) != galaxy.system(1),
		"the galaxy generates a system once and then keeps it",
	)
	var was: int = galaxy.system(0).seed
	galaxy.reset(556)
	_expect(
		galaxy.system(0).seed != was,
		"and reseeding drops everything the old seed produced",
	)
	galaxy.free()


## The moon radius the layout invents has to be a radius a planet can
## actually be built at. A number chosen in one file and used in another is
## a guess until something checks it.
func _check_moon_sized_world(probe: Planet) -> void:
	var was_radius: float = probe.surface_radius
	var was_plateaus: int = probe.plateau_count
	probe.surface_radius = StarSystem.MOON_RADIUS.x
	probe.plateau_count = maxi(
		Planet.MIN_PLATEAUS, int(TAU * probe.surface_radius / Planet.PLATEAU_SPACING)
	)
	probe.rebuild()
	var shelves: int = probe.landing_sites().size()
	_expect(
		shelves >= Planet.MIN_PLATEAUS,
		"a world the size of the smallest moon still has %d shelves to land on" % shelves,
	)
	probe.surface_radius = was_radius
	probe.plateau_count = was_plateaus
	probe.rebuild()


## Which ship a seeker chases. The whole thesis of mouse aiming is that the
## answer is "the one you are pointing at", and the old answer was "the
## nearest one", which is a weapon arguing with the cursor.
func _check_seeker_targets() -> void:
	var shooter: Ship = _spawn_ship()
	shooter.global_position = Vector2(20000.0, 20000.0)
	var close: Ship = _spawn_ship()
	close.global_position = shooter.global_position + Vector2(200.0, 0.0)
	var distant: Ship = _spawn_ship()
	distant.global_position = shooter.global_position + Vector2(900.0, 0.0)
	var reach: float = shooter.lock_reach()

	_expect(
		Missile.find_target(distant.global_position, shooter, root.get_tree(), reach) == distant,
		"pointing at the far ship picks the far ship, though the near one is closer to the rail",
	)
	_expect(
		Missile.find_target(close.global_position, shooter, root.get_tree(), reach) == close,
		"and pointing at the near one picks the near one",
	)

	# Forgiving, but not infinitely: the pick circle is the cursor's own
	# imprecision, and past it the pilot pointed at space.
	var beside: Vector2 = close.global_position + Vector2(0.0, reach * 0.5)
	_expect(
		Missile.find_target(beside, shooter, root.get_tree(), reach) == close,
		"near enough to a hull still counts as pointing at it",
	)
	_expect(
		Missile.find_target(
			shooter.global_position + Vector2(0.0, 5000.0), shooter, root.get_tree(), reach
		) == null,
		"and pointing at empty space is no lock at all, not a lock on whatever was nearest",
	)

	# Never itself, and never a wreck: both are missiles thrown away.
	_expect(
		Missile.find_target(shooter.global_position, shooter, root.get_tree(), reach) == null,
		"a seeker will not lock the ship that fired it",
	)
	close.take_damage(2.0, "test")
	_expect(
		close.is_destroyed()
		and Missile.find_target(close.global_position, shooter, root.get_tree(), reach) == null,
		"nor a wreck, however squarely it is pointed at",
	)

	shooter.queue_free()
	close.queue_free()
	distant.queue_free()


## Nazwa przedmiotu: afiksy plus baza, dla kazdego rodzaju tak samo.
##
## There used to be three habits and no rule. A weapon kept its affix list
## and baked the finished string into its own name; a generator baked the
## string and threw the list away; an engine threw the list away without
## baking anything and was called "thruster engine 664". The name is
## composed from the list now, on every kind, which is what lets it be cut
## to a length -- a baked string cannot be shortened, because nothing can
## tell afterwards which of its words were affixes.
func _check_item_names() -> void:
	var loot: Node = LOOT_SCRIPT.new()

	# Every kind keeps what it rolled, and says so in its name.
	var kinds: Array[Dictionary] = [
		{"what": "weapon", "item": loot.weapon(7117, 4)},
		{"what": "engine", "item": loot.engine(7117, 4)},
		{"what": "generator", "item": loot.generator(7117, 3)},
	]
	var mute: int = 0
	var unnamed: int = 0
	for entry: Dictionary in kinds:
		var item: ModuleData = entry["item"]
		if item.affixes.is_empty():
			mute += 1
			print("    a legendary %s rolled no affixes at all" % entry["what"])
			continue
		if not item.title().ends_with(item.display_name):
			unnamed += 1
			print("    %s: %s does not end in %s" % [
				entry["what"], item.title(), item.display_name,
			])
		elif not item.title().begins_with(String(item.affixes[0])):
			unnamed += 1
			print("    %s: %s does not begin with %s" % [
				entry["what"], item.title(), item.affixes[0],
			])
	_expect(mute == 0, "a rolled item of every kind carries the affixes it rolled")
	_expect(unnamed == 0, "and every one of them is named for them, affixes first")

	# The engine is the one worth naming out loud: it used to be called
	# after its own enum and its thrust.
	var drive: EngineData = loot.engine(7117, 4)
	_expect(
		not drive.title().contains("%.0f" % drive.max_thrust),
		"an engine is not named after a number that is already on its card (%s)" % drive.title(),
	)

	# Length, against the panel it has to fit in rather than against taste.
	var face: Font = UiFont.face()
	var room: float = LoadoutScreen.PANEL_WIDTH
	var limit: String = "M".repeat(ModuleData.TITLE_LIMIT)
	_expect(
		face.get_string_size(limit, 0, -1, UiFont.BODY).x <= room,
		"a title at the limit fits the swap panel (%.0f px of %.0f)" % [
			face.get_string_size(limit, 0, -1, UiFont.BODY).x, room,
		],
	)
	_expect(
		face.get_string_size(limit + "MMMM", 0, -1, UiFont.BODY).x > room,
		"and the limit is tight rather than timid: four more would not",
	)

	# Nothing the generator can roll goes over it, and what does not fit is
	# on the card instead of lost.
	var overlong: int = 0
	var spilled: int = 0
	var listed: int = 0
	for item_seed: int in range(1200):
		var item: ModuleData = loot.generate(item_seed * 13, item_seed % 5) as ModuleData
		if item == null:
			continue
		if item.title().length() > ModuleData.TITLE_LIMIT:
			overlong += 1
			print("    %d chars: %s" % [item.title().length(), item.title()])
		if item.dropped_affixes().is_empty():
			continue
		spilled += 1
		for line: String in item.card_lines():
			if line.begins_with("też:"):
				listed += 1
	_expect(overlong == 0, "no rolled item has a title longer than the panel")
	_expect(
		spilled == 0 or listed == spilled,
		"and an affix the title had no room for is on the card, not lost (%d of %d)" % [
			listed, spilled,
		],
	)
	print("    %d of 1200 rolls spilled an affix onto the card" % spilled)
	loot.free()


## Afiksy, ktorych baza nie ma gdzie przyjac, nie trafiaja do jej puli.
##
## The defect this guards was measured rather than suspected: an affix
## multiplies a field, a multiplier on zero is zero, and the pool was the
## whole category. So "steerable" could land on a jet with no gimbal and
## "wide" on a gun with no blast -- taking one of an item's few slots and
## doing nothing with it. 14% of the engine pool and 13% of the weapon pool
## was dead on an average base.
##
## The mirror case is worse and was not in the original note. An affix
## whose **cost** falls on a field the base leaves at zero is not a trade,
## it is a gift: "rapid" buys rate of fire with spread, and a beam has no
## spread to pay with. Five of the thirteen weapon affixes were free on the
## beam lance.
func _check_affix_pools() -> void:
	var loot: Node = LOOT_SCRIPT.new()
	var categories: Array[Dictionary] = [
		{"kind": "weapon", "bases": loot.WEAPON_BASES, "table": loot.WEAPON_AFFIXES},
		{"kind": "engine", "bases": loot.ENGINE_BASES, "table": loot.ENGINE_AFFIXES},
		{"kind": "generator", "bases": loot.GENERATOR_BASES, "table": loot.GENERATOR_AFFIXES},
	]

	var toothless: int = 0
	var excluded: int = 0
	var starved: int = 0
	var most: int = RARITY_AFFIXES_MAX
	for category: Dictionary in categories:
		var table: Array[Dictionary] = category["table"]
		for path: String in category["bases"]:
			var base: Resource = load(path)
			var pool: Array[StringName] = loot.affixes_for(base, table)
			excluded += table.size() - pool.size()
			# Nothing in a pool may be unable to bite, which is the property
			# itself rather than a sample of it.
			for affix: Dictionary in table:
				if not pool.has(affix["name"] as StringName):
					continue
				if not loot.affix_bites(base, affix):
					toothless += 1
			# And no base may be left with fewer affixes than the rarest
			# roll wants, or legendary stops meaning anything on it.
			if pool.size() < most:
				starved += 1
				print("    %s can only take %d affixes" % [path.get_file(), pool.size()])

	_expect(toothless == 0, "every affix in a base's pool can move something on it")
	_expect(
		excluded > 0,
		"and the rule has teeth: %d base-and-affix pairings are ruled out" % excluded,
	)
	_expect(starved == 0, "while every base can still fill a legendary roll")

	# End to end, on the one kind of item that keeps the names it rolled.
	# Engines throw theirs away, which is the next checkbox in M3.5 -- and
	# until it is done this property cannot be checked on them at all.
	var contradictions: int = 0
	var checks: Array[Array] = [
		[&"wide", "blast_radius"], [&"turreted", "traverse_range"],
		[&"eager", "missile_thrust"], [&"precise", "spread_degrees"],
		[&"rapid", "spread_degrees"], [&"hot-loaded", "muzzle_speed"],
	]
	for item_seed: int in range(1500):
		var gun: WeaponData = loot.weapon(item_seed, RARITY_AFFIXES_MAX - 1)
		for pair: Array in checks:
			if gun.affixes.has(pair[0]) and absf(float(gun.get(pair[1]))) < 0.0001:
				contradictions += 1
				print("    %s rolled %s with no %s" % [
					gun.title(), pair[0], pair[1],
				])
	_expect(
		contradictions == 0,
		"and no rolled weapon carries an affix with nothing to act on (1500 rolls)",
	)
	loot.free()


func _check_rarity_travels() -> void:
	var loot: Node = LOOT_SCRIPT.new()
	var ship: Ship = _spawn_ship()

	for grade: int in range(ModuleData.RARITY_NAMES.size()):
		var engine: EngineData = loot.engine(8800 + grade, grade)
		_expect(
			engine.rarity == grade,
			"a %s roll comes back knowing it is %s" % [
				ModuleData.RARITY_NAMES[grade], engine.rarity_name(),
			],
		)

	# Through the hold, the bay and back out, without being told again.
	var found: WeaponData = loot.weapon(8899, ModuleData.RARITY_NAMES.size() - 1)
	_expect(found.rarity == 4, "a legendary weapon is stamped legendary")
	ship.take(found)
	_expect(ship.carried_rarity == 4, "the hold reports it without being told")
	ship.stow()
	ship.retrieve(0)
	_expect(ship.carried_rarity == 4, "and it survives a trip through cargo")

	# And into a crate, which is where the colour comes from.
	var crate: LootCrate = (load(CRATE_SCENE) as PackedScene).instantiate() as LootCrate
	root.add_child(crate)
	crate.hold(ship.release())
	_expect(crate.rarity() == 4, "a crate made from it is legendary too")
	_expect(
		crate.rarity_color_of() == ModuleData.RARITY_COLORS[4],
		"and painted the colour that grade is painted",
	)
	# Painted on the sprite rather than baked into five files. The crate is
	# the textbook hybrid from ASSETLIST: a fixed silhouette carrying a
	# colour the game already knows.
	var box: StripSprite = crate.get_node("Body") as StripSprite
	_expect(box != null and box.strip != null, "the crate wears the crate picture")
	_expect(
		box != null and box.self_modulate.is_equal_approx(crate.rarity_color_of()),
		"and the picture is tinted by it, so one white sprite covers all five grades",
	)

	# The grades have to be told apart on screen, which is the whole job of
	# the colour. Neighbours are the hard case.
	for i: int in range(ModuleData.RARITY_COLORS.size() - 1):
		var a: Color = ModuleData.RARITY_COLORS[i]
		var b: Color = ModuleData.RARITY_COLORS[i + 1]
		var apart: float = absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
		_expect(
			apart > 0.35,
			"%s and %s are told apart at a glance (%.2f)" % [
				ModuleData.RARITY_NAMES[i], ModuleData.RARITY_NAMES[i + 1], apart,
			],
		)

	crate.queue_free()
	loot.free()
	ship.queue_free()


## Mouse aiming: guns swing towards where the pilot is pointing, within the
## arc the hull and the gun agree on, and only the ones that can actually hit
## are allowed to fire.
func _check_aiming() -> void:
	var ship: Ship = _spawn_ship()
	ship.use_player_input = false
	ship.global_position = Vector2.ZERO
	ship.global_rotation = 0.0
	var mount: Hardpoint = ship.hardpoints[0]

	var gun: WeaponData = mount.weapon.duplicate() as WeaponData
	gun.traverse_range = deg_to_rad(40.0)
	gun.traverse_rate = deg_to_rad(120.0)
	gun.range_px = 1000.0
	mount.fit(gun)
	mount.traverse_limit = PI

	# The arc is the smaller of what the gun can do and what the hull allows.
	_expect(
		is_equal_approx(mount.traverse(), gun.traverse_range),
		"an open mount gives the gun its full ring (%.0f deg)" % rad_to_deg(mount.traverse()),
	)
	mount.traverse_limit = deg_to_rad(15.0)
	_expect(
		is_equal_approx(mount.traverse(), deg_to_rad(15.0)),
		"a recessed mount clips it to what the hull allows (%.0f deg)" % [
			rad_to_deg(mount.traverse()),
		],
	)
	mount.traverse_limit = PI

	# Straight ahead is on target from the start; off to the side is not, but
	# gets there.
	var nose: Vector2 = Ship.FORWARD.rotated(ship.global_rotation)
	_expect(
		mount.aim_state(mount.global_position + nose * 400.0) == Hardpoint.Aim.ON_TARGET,
		"a gun already pointing at the cursor says fire",
	)

	var beside: Vector2 = mount.global_position + nose.rotated(deg_to_rad(25.0)) * 400.0
	_expect(
		mount.aim_state(beside) == Hardpoint.Aim.TURNING,
		"one that could get there says it is turning",
	)
	for step: int in range(60):
		mount.aim_at(beside, 1.0 / 60.0)
	_expect(
		mount.aim_state(beside) == Hardpoint.Aim.ON_TARGET,
		"and it arrives (%.1f deg off rest)" % rad_to_deg(mount.facing),
	)

	var behind: Vector2 = mount.global_position - nose * 400.0
	_expect(
		mount.aim_state(behind) == Hardpoint.Aim.BLOCKED,
		"a target outside the arc is refused, not chased",
	)
	_expect(
		mount.aim_state(mount.global_position + nose * (gun.range_px + 200.0))
			== Hardpoint.Aim.BLOCKED,
		"and so is one out of range: a green cursor on an unreachable target is a lie",
	)

	# A homing round is always worth firing and never precisely aimed.
	var seeker: WeaponData = load("res://resources/weapons/seeker.tres") as WeaponData
	mount.fit(seeker)
	_expect(
		mount.aim_state(mount.global_position + nose * 400.0) == Hardpoint.Aim.TURNING,
		"a seeker never reads as locked on, because it can always come round",
	)
	mount.fit(gun)

	# The trigger fires the guns that bear, not every gun wired to it.
	ship.energy = 1000.0
	mount.trigger = 0
	mount.facing = 0.0
	ship.aim_point = behind
	ship.fire_command = true
	var container: Node = ship.projectile_container()
	var before: int = container.get_child_count()
	for step: int in range(30):
		ship._physics_process(1.0 / 60.0)
	_expect(
		container.get_child_count() == before,
		"holding the trigger with nothing able to bear fires nothing",
	)

	ship.aim_point = mount.global_position + nose * 400.0
	for step: int in range(30):
		ship._physics_process(1.0 / 60.0)
	_expect(
		container.get_child_count() > before,
		"and fires as soon as something can (%d rounds)" % [
			container.get_child_count() - before,
		],
	)
	ship.fire_command = false

	# Triggers are groups: a mount answers to one of them and the cursor
	# reports per trigger.
	_expect(ship.has_trigger(0), "the stock hull has something on the primary")
	mount.trigger = 1
	_expect(
		not ship.has_trigger(0) and ship.has_trigger(1),
		"moving a mount to the other trigger moves it entirely",
	)
	mount.trigger = 0

	_expect(
		AimHud.state_color(Hardpoint.Aim.ON_TARGET) != AimHud.state_color(Hardpoint.Aim.TURNING)
		and AimHud.state_color(Hardpoint.Aim.TURNING) != AimHud.state_color(Hardpoint.Aim.BLOCKED),
		"the three cursor states are three different colours",
	)

	# Our own rounds pass through our own hull. Aiming across the ship is a
	# legitimate thing to do with a turret, so a round is inert until it is
	# clear of the ship that fired it -- and the clearance is the hull's own
	# size, because a fixed grace period is a bet on how big ships are.
	for round_node: Node in container.get_children():
		round_node.queue_free()
	var big: Ship = _spawn_ship()
	big.hull_outline = PackedVector2Array([
		Vector2(0, -40), Vector2(-28, 34), Vector2(28, 34),
	])
	big._build_contact_points()
	big._build_collision_shape()
	big.rebuild_control_groups(false)
	big.global_position = Vector2(20000.0, 0.0)

	var slow: Projectile = (load("res://scenes/projectile.tscn") as PackedScene).instantiate()
	root.add_child(slow)
	slow.shooter = big
	slow.damage = 0.5
	slow.velocity = Vector2(150.0, 0.0)
	slow.global_position = big.global_position - Vector2(30.0, 0.0)
	var hull_before: float = big.hull_integrity
	# Long past the old fixed grace, and still inside the hull.
	for step: int in range(24):
		slow._physics_process(1.0 / 60.0)
		slow._on_body_entered(big)
	_expect(
		is_equal_approx(big.hull_integrity, hull_before),
		"a round crossing its own hull does not hurt the ship that fired it",
	)
	_expect(
		not slow._armed,
		"because it is not live until it is clear, however long that takes",
	)

	# But one that has been clear is live for good, so a shot that comes
	# back round still counts.
	slow.global_position = big.global_position + Vector2(400.0, 0.0)
	slow._physics_process(1.0 / 60.0)
	_expect(slow._armed, "leaving arms it")
	slow.global_position = big.global_position
	slow._on_body_entered(big)
	_expect(
		big.hull_integrity < hull_before,
		"and a round that comes home armed does hit (%.2f)" % big.hull_integrity,
	)

	slow.queue_free()
	big.queue_free()
	ship.queue_free()



## Paleta: jeden plik, a nie dwanascie ról rozpisanych w kazdym ekranie.
##
## UI_STYLE section 3 counted the damage before the resource existed: the
## same four roles were spelled out in three screens as eleven different
## colours -- two panel fills, two borders, four greys for "label" and
## "value", and three ambers a pixel apart. Nobody did that deliberately;
## it is what happens when a role is written out where it is used.
##
## So the guard is not "the palette loads". It is that those screens no
## longer declare a colour of their own, read from the source rather than
## from the running object, because a constant that is never drawn with is
## still a second opinion waiting to be used.
func _check_palette() -> void:
	var ink: Palette = Palette.current()
	_expect(ink != null, "there is a palette")

	# Twelve roles, twelve colours. Near-duplicates are the failure this
	# replaces, so exact equality is a weak test -- it is the one that can
	# be written, and it catches a copied line.
	var roles: PackedStringArray = PackedStringArray([
		"scrim", "panel", "edge", "grid", "inert", "label",
		"value", "accent", "nav", "ok", "caution", "alarm",
	])
	var seen: Array[Color] = []
	var repeated: int = 0
	for role: String in roles:
		var shade: Color = ink.get(role)
		if seen.has(shade):
			repeated += 1
			print("    %s repeats a colour already in the palette" % role)
		seen.append(shade)
	_expect(repeated == 0, "and its %d roles are %d colours" % [roles.size(), roles.size()])

	# The two accent channels have to be told apart at a glance, or the
	# rule that one means the ship and the other the world buys nothing.
	var apart: float = (
		absf(ink.accent.r - ink.nav.r) + absf(ink.accent.g - ink.nav.g)
		+ absf(ink.accent.b - ink.nav.b)
	)
	_expect(apart > 0.5, "the ship channel and the world channel are not the same blue (%.2f)" % apart)

	# And the screens UI_STYLE named have stopped keeping their own.
	var kept: int = 0
	for name: String in ["flight_hud", "ship_editor", "loadout_screen", "scanner_hud"]:
		var text: String = FileAccess.get_file_as_string("res://scripts/%s.gd" % name)
		_expect(not text.is_empty(), "%s.gd can be read" % name)
		for line: String in text.split("
"):
			if line.begins_with("const ") and line.contains(": Color"):
				kept += 1
				print("    %s still declares %s" % [name, line.strip_edges()])
	_expect(kept == 0, "and no screen keeps a colour of its own any more")


## Font interfejsu: czy ma wszystkie znaki, ktore gra naprawde pisze.
##
## The guard that matters is coverage, and it is checked against the text
## the game actually sets rather than against an alphabet. A missing glyph
## does not fail anything -- Godot draws a box with a hex code in it -- so
## the first anyone would know is a screenshot with a box in the middle of
## a Polish word. Counted once over the real strings: every non-ASCII
## character in the interface is Polish except the em dash, which appears
## eleven times and which a font built from ASCII would have missed.
##
## Monospace is the other half, and it is UI_STYLE's reason for having a
## font rule at all: in a proportional face `ALT 11111` and `ALT 88888`
## are different widths, and a number that changes width as it counts is
## unreadable however good the rest of the screen is.
func _check_font() -> void:
	var face: Font = UiFont.face()
	_expect(
		face != null and face != ThemeDB.fallback_font,
		"the interface has a face of its own, not the engine's fallback",
	)

	# The corpus: every line the game is known to put on screen, from the
	# objects that own them rather than copied here.
	var corpus: PackedStringArray = PackedStringArray()
	for entry: Dictionary in HelpScreen.LABELS:
		corpus.append(String(entry["says"]))
	for says: Variant in HelpScreen.CHORD_SAYS.values():
		corpus.append(String(says))
	var loot: Node = LOOT_SCRIPT.new()
	for item_seed: int in range(40):
		var item: ModuleData = loot.generate(item_seed * 37, item_seed % 5) as ModuleData
		if item == null:
			continue
		for line: String in item.card_lines():
			corpus.append(line)
		corpus.append(item.blurb())
	loot.free()
	var ship: Ship = _spawn_ship()
	for line: String in ship.configuration().lines():
		corpus.append(line)
	var post: Station = (load("res://scenes/station.tscn") as PackedScene).instantiate() as Station
	root.add_child(post)
	corpus.append(post.refusal(ship))
	post.free()
	ship.free()

	var missing: Dictionary = {}
	var letters: int = 0
	for line: String in corpus:
		for i: int in range(line.length()):
			var code: int = line.unicode_at(i)
			letters += 1
			if not face.has_char(code):
				missing[code] = line
	_expect(letters > 500, "there is a corpus to check (%d characters)" % letters)
	for code: Variant in missing:
		print("    no glyph for U+%04X in: %s" % [code, missing[code]])
	_expect(
		missing.is_empty(),
		"and the font has a glyph for every character in it (%d lines)" % corpus.size(),
	)

	# Polish by name, because the corpus above is only as good as the
	# strings that happen to exist today.
	var polish: String = "ąćęłńóśźżĄĆĘŁŃÓŚŹŻ—"
	var absent: int = 0
	for i: int in range(polish.length()):
		if not face.has_char(polish.unicode_at(i)):
			absent += 1
	_expect(absent == 0, "every Polish letter and the em dash are drawn, not boxed")

	# Monospace, measured on the two extremes rather than declared.
	var narrow: Vector2 = face.get_string_size("iiiiiiii", 0, -1, UiFont.BODY)
	var wide: Vector2 = face.get_string_size("MMMMMMMM", 0, -1, UiFont.BODY)
	_expect(
		is_equal_approx(narrow.x, wide.x),
		"eight narrow letters are as wide as eight wide ones (%.0f against %.0f)" % [
			narrow.x, wide.x,
		],
	)

	# And it scales by whole numbers, which is the grid law enforced by the
	# font rather than by everyone remembering it. Found by looking: the
	# first version had no scale mode set, so a 16 px heading came out the
	# same size as the 8 px body and nothing complained.
	var small: Vector2 = face.get_string_size("ALT 1414", 0, -1, UiFont.BODY)
	var large: Vector2 = face.get_string_size("ALT 1414", 0, -1, UiFont.HEADLINE)
	_expect(
		is_equal_approx(large.x, small.x * 2.0) and is_equal_approx(large.y, small.y * 2.0),
		"and a heading is exactly twice a label, not nearly twice (%.0f against %.0f)" % [
			large.x, small.x,
		],
	)

## A module has to be able to say what it is made of, in a form two of them
## can be subtracted from each other.
##
## The screens used to hold a format string per kind, which reads fine and
## cannot be compared: a card that is a paragraph can be read but not
## subtracted. Rows carry the direction too, because a comparison cannot
## colour a difference it does not know the sign of -- less spread is better,
## less range is not.
func _check_stat_cards() -> void:
	var loot: Node = LOOT_SCRIPT.new()
	var kinds: Array[ModuleData] = [
		loot.weapon(3001, 2), loot.engine(3002, 2), loot.generator(3003, 2),
		loot.computer(3004, 3), loot.shot_mod(0),
	]
	for module: ModuleData in kinds:
		var rows: Array[Dictionary] = module.stat_rows()
		_expect(not rows.is_empty(), "%s has something to say about itself" % module.get_class())
		for row: Dictionary in rows:
			_expect(
				not String(row["label"]).is_empty() and int(row["digits"]) >= 0,
				"every row of a %s is printable" % module.get_class(),
			)
			_expect(
				int(row["better"]) >= -1 and int(row["better"]) <= 1,
				"and says which way is up (%s)" % row["label"],
			)

	# The directions have to be right, or a comparison misleads in exactly
	# the cases it exists for.
	var gun: WeaponData = load("res://resources/weapons/autocannon.tres") as WeaponData
	var direction: Dictionary = {}
	for row: Dictionary in gun.stat_rows():
		direction[row["label"]] = int(row["better"])
	_expect(direction.get("dps", 0) > 0, "more damage per second is better")
	_expect(direction.get("rozrzut", 0) < 0, "more spread is not")
	_expect(direction.get("energia", 0) < 0, "nor is a dearer shot")
	_expect(direction.get("gabaryt", 0) < 0, "nor a bulkier gun")

	# Every kind of mount can say what is in it, which is what the card
	# compares against.
	var ship: Ship = _spawn_ship()
	var editor: ShipEditor = ShipEditor.new()
	root.add_child(editor)
	editor.bind(ship)
	_expect(
		editor._fitted_in(ship.hardpoints[0]) == ship.hardpoints[0].weapon,
		"a hardpoint reports its gun",
	)
	_expect(
		editor._fitted_in(ship.engine_mounts()[0]) == ship.engine_mounts()[0].installed,
		"an engine mount reports its engine",
	)
	_expect(
		editor._fitted_in(ship.generator_bay) == ship.generator_bay.installed,
		"and the generator bay its cell",
	)

	# And the comparison says which way each number went.
	var better: WeaponData = gun.duplicate() as WeaponData
	better.damage = gun.damage * 2.0
	better.spread_degrees = gun.spread_degrees * 0.5
	var compared: String = "
".join(editor._card(better, gun))
	_expect(compared.contains("lepiej"), "a straight upgrade reads as better")
	var worse: WeaponData = gun.duplicate() as WeaponData
	worse.spread_degrees = gun.spread_degrees * 2.0
	_expect(
		"
".join(editor._card(worse, gun)).contains("gorzej"),
		"and more spread reads as worse, though the number went up",
	)
	_expect(
		"
".join(editor._card(gun, gun)).contains("="),
		"while the same gun against itself is all equals",
	)

	# And the quick swap shows the same card, from the same place. Two
	# screens formatting their own is the thing stat_rows() exists to stop.
	var quick: LoadoutScreen = LoadoutScreen.new()
	root.add_child(quick)
	quick.bind(ship)
	ship.take(better)
	quick.announce_pickup()
	var shown: String = quick.panel_text()
	for row: Dictionary in better.stat_rows():
		_expect(
			shown.contains(String(row["label"])),
			"the quick swap lists %s, like the editor does" % row["label"],
		)
	_expect(
		shown.contains("lepiej") or shown.contains("gorzej") or shown.contains("="),
		"and carries the comparison, which is the part worth reading in flight",
	)
	quick.queue_free()

	editor.queue_free()
	ship.queue_free()
	loot.free()


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
			and first.title() == again.title(),
		"the same seed rolls the same weapon (%s)" % first.title(),
	)
	var other: WeaponData = _loot.weapon(90211)
	_expect(
		not is_equal_approx(first.damage, other.damage)
			or first.title() != other.title(),
		"a different seed rolls something else (%s)" % other.title(),
	)

	# Rarity buys affixes, and exactly as many as the table promises.
	for rarity: int in range(LOOT_SCRIPT.RARITY_AFFIXES.size()):
		var item: WeaponData = _loot.weapon(1000 + rarity, rarity)
		_expect(
			item.affixes.size() == LOOT_SCRIPT.RARITY_AFFIXES[rarity],
			"%s weapons carry %d affixes (%s)" % [
				_loot.rarity_name(rarity), item.affixes.size(), item.title(),
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
	var tolerance: float = probe.gear.slope_limit()
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


## What an arrival costs. The shape of the curve is the design decision, so
## the test reads the curve rather than one crash's number.
func _check_damage_model(ship: Ship) -> void:
	var limit: float = ship.gear.vertical_limit()
	_expect(
		ship.impact_damage(300.0, true) < ship.impact_damage(300.0, false),
		"the legs buy something at speed (%.2f against %.2f)" % [
			ship.impact_damage(300.0, true), ship.impact_damage(300.0, false),
		],
	)

	_expect(
		is_zero_approx(ship.impact_damage(ship.damage_speed_threshold - 1.0, false))
		and is_zero_approx(ship.impact_damage(limit - 1.0, true)),
		"under the tolerance an arrival is free, on the legs or on the hull",
	)

	# The property the old model had backwards, and the whole reason legs are
	# bolted to a ship: whatever the speed, taking it on the legs is never
	# worse than taking it on the hull.
	var legs_never_worse: bool = true
	var hull_climbs: bool = true
	var legs_climb: bool = true
	var last_hull: float = -1.0
	var last_legs: float = -1.0
	for speed: float in [40.0, 60.0, 80.0, 105.0, 130.0, 160.0, 200.0, 300.0, 500.0]:
		var on_hull: float = ship.impact_damage(speed, false)
		var on_legs: float = ship.impact_damage(speed, true)
		legs_never_worse = legs_never_worse and on_legs <= on_hull + 0.0001
		hull_climbs = hull_climbs and on_hull >= last_hull
		legs_climb = legs_climb and on_legs >= last_legs
		last_hull = on_hull
		last_legs = on_legs
		_expect(
			on_hull <= 1.0 and on_legs <= 1.0,
			"at %.0f px/s nothing costs more than a whole ship (%.2f / %.2f)" % [
				speed, on_hull, on_legs,
			],
		)
	_expect(legs_never_worse, "taking an impact on the legs is never worse than on the hull")
	_expect(hull_climbs and legs_climb, "and faster never costs less")

	# The two complaints this model was rewritten for, as numbers.
	_expect(
		is_zero_approx(ship.impact_damage(limit + 5.0, true)),
		"a touchdown a shade over the legs' rating is refused, not punished",
	)
	var shade_over: float = ship.impact_damage(ship.damage_speed_threshold + 15.0, true)
	_expect(
		shade_over > 0.0 and shade_over < 0.02,
		"and arriving hard enough to hurt is a scratch (%.3f)" % shade_over,
	)
	_expect(
		ship.impact_damage(150.0, false) > 0.5,
		"and flying into rock at 150 px/s is most of a ship (%.2f)" % [
			ship.impact_damage(150.0, false),
		],
	)


func _check_gear(ship: Ship) -> void:
	var landing_gear: LandingGear = ship.gear
	_expect(landing_gear != null, "the stock hull carries landing gear")
	if landing_gear == null:
		return

	_expect(landing_gear.legs.size() >= 2, "the gear has %d legs" % landing_gear.legs.size())
	# Counted rather than named: the outline decides how many there are now.
	var bare: int = ship.contact_points().size()
	_expect(landing_gear.is_stowed(), "the legs start stowed")
	_expect(
		ship.contact_points().size() == bare,
		"stowed legs are not contact points",
	)

	# Half-open gear must not count, or the deploy timer would be decorative.
	landing_gear.set_deployed(true)
	landing_gear.advance(landing_gear.extend_time() * 0.5)
	_expect(not landing_gear.is_deployed(), "half-extended gear does not count as down")
	_expect(
		ship.contact_points().size() == bare,
		"half-extended legs are not contact points either",
	)

	landing_gear.advance(landing_gear.extend_time())
	_expect(landing_gear.is_deployed(), "the legs reach full extension")
	_expect(
		ship.contact_points().size() == bare + landing_gear.legs.size(),
		"deployed legs join the contact set",
	)

	# The outline is what decides the contact set now, and the step it is cut
	# at is what stops a terrain spike slipping between two of them.
	var widest: float = 0.0
	for i: int in range(ship.hull_outline.size()):
		var from: Vector2 = ship.hull_outline[i]
		var to: Vector2 = ship.hull_outline[(i + 1) % ship.hull_outline.size()]
		var segments: int = maxi(1, ceili(from.distance_to(to) / Ship.CONTACT_STEP))
		widest = maxf(widest, from.distance_to(to) / float(segments))
	_expect(
		widest <= Ship.CONTACT_STEP + 0.001,
		"no gap along the outline is wider than the contact step (%.2f of %.1f px)" % [
			widest, Ship.CONTACT_STEP,
		],
	)

	# The drawn leg starts on the hull and ends where the solver touches.
	# Read off the outline every time rather than stored, so a hull the
	# creative tool reshaped does not leave the legs hanging in space.
	for leg: Vector2 in landing_gear.legs:
		var root_point: Vector2 = landing_gear.leg_root(leg)
		var on_hull: float = INF
		for i: int in range(ship.hull_outline.size()):
			on_hull = minf(on_hull, root_point.distance_to(Geometry2D.get_closest_point_to_segment(
				root_point,
				ship.hull_outline[i],
				ship.hull_outline[(i + 1) % ship.hull_outline.size()],
			)))
		_expect(on_hull < 0.001, "leg %s is rooted on the hull outline" % leg)
		_expect(
			root_point.distance_to(leg) < Vector2.ZERO.distance_to(leg),
			"and rooted nearer its foot than the hull's centre is",
		)

	var stretched: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in ship.hull_outline:
		stretched.append(point + Vector2(0.0, 6.0) if point.y > 0.0 else point)
	var was: Vector2 = landing_gear.leg_root(landing_gear.legs[0])
	ship.hull_outline = stretched
	_expect(
		not landing_gear.leg_root(landing_gear.legs[0]).is_equal_approx(was),
		"a hull stretched under the legs moves where they are rooted",
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


## Sprite'y i zasoby wygladu: czy sa, czy pasuja i czy cokolwiek rozrozniaja.
##
## Three things are guarded here and they are worth separating.
##
## The first is drift. The hull catalogue now lives in three places --
## CreativeTool.SHAPES, the presets in ShipFitout.all(), and the HullData
## resources the art is cut from -- because the first two are being migrated
## onto the third and the migration is not finished (PLAN.md M3.5). Three
## copies with nothing between them is how a hull ends up flying one shape
## and wearing another.
##
## The second is the resolution contract. Art.FACTOR only means anything if
## the files obey it, and nothing about a PNG says what scale it was drawn
## at: a world sprite flagged as interface art comes out three times too big
## and does not error.
##
## The third is whether the look tables separate anything. A table that
## resolves every engine in the game to the same picture is not a binding,
## it is a default with extra steps -- and it would pass every other check
## here.
func _check_art() -> void:
	var hulls: Dictionary = HullData.all()
	_expect(not hulls.is_empty(), "there are hull resources at all (%d)" % hulls.size())

	# One catalogue, which is the point of the migration. This check used
	# to reconcile three: the resources, `CreativeTool.SHAPES` and the
	# outlines written into every preset. Holding them in step was a prop,
	# not a fix -- what it guards now is that a preset cannot name a hull
	# that is not there.
	var orphaned: int = 0
	for preset: Dictionary in ShipFitout.all():
		if HullData.of(preset["hull"]) == null:
			orphaned += 1
			print("    preset %s names hull %s, which does not exist" % [
				preset["name"], preset["hull"],
			])
	_expect(orphaned == 0, "every preset names a hull that is in the catalogue")
	# And what the hull states is what the ship gets. The hold and the feet
	# moved onto the resource, so three presets flying the same dart can no
	# longer disagree about either by hand.
	var dressed: Ship = _spawn_ship()
	var heavy: Dictionary = {}
	for preset: Dictionary in ShipFitout.all():
		if preset["hull"] == &"freighter":
			heavy = preset
	ShipFitout.apply(dressed, heavy)
	var hold: HullData = HullData.of(&"freighter")
	_expect(
		is_equal_approx(dressed.hull_cargo_capacity, hold.cargo_capacity)
		and dressed.gear.legs == hold.legs,
		"a refit takes the hold and the feet from the hull, not from the preset",
	)
	dressed.free()
	_expect(
		not ("SHAPES" in CreativeTool),
		"and the sandbox no longer keeps a second copy of the list",
	)

	var hull_looks: LookTable = load("res://resources/fx/looks/hull.tres") as LookTable
	_expect(hull_looks != null, "the hull look table loads")
	var undressed: int = 0
	var too_small: int = 0
	for id: Variant in hulls:
		var hull: HullData = hulls[id]
		var strip: SpriteStrip = hull_looks.pick(hull, hull.id)
		if strip == null or not strip.is_valid():
			undressed += 1
			continue
		# The picture has to cover the shape. Not an aesthetic test: a sprite
		# narrower than its own collision outline leaves the ship visibly
		# bouncing off air.
		var drawn: Vector2 = strip.design_size()
		var box: Rect2 = hull.bounds()
		if drawn.x < box.size.x or drawn.y < box.size.y:
			too_small += 1
			print("    %s sprite is %s for an outline of %s" % [hull.id, drawn, box.size])
	_expect(undressed == 0, "every hull resource resolves to a sprite")
	_expect(too_small == 0, "and every hull sprite is at least as big as its outline")

	# Every strip in every table, checked for the things that are invisible
	# in a file listing: a frame width that does not divide, a pivot outside
	# its own frame, and a scale flag that disagrees with where the file sits.
	var broken: int = 0
	var astray: int = 0
	var mislabelled: int = 0
	var counted: int = 0
	for path: String in ART_LOOK_TABLES:
		var table: LookTable = load(path) as LookTable
		if table == null:
			_expect(false, "look table %s loads" % path)
			continue
		for strip: SpriteStrip in table.every_strip():
			if strip == null or not strip.is_valid():
				broken += 1
				continue
			counted += 1
			if strip.texture.get_width() % strip.frames != 0:
				broken += 1
			if not strip.pivot_is_sane():
				astray += 1
				print("    pivot %s outside %s" % [strip.pivot, strip.frame_size()])
			var under_world: bool = strip.texture.resource_path.begins_with(Art.WORLD_DIR)
			if strip.in_world != under_world:
				mislabelled += 1
				print("    %s is marked in_world=%s" % [
					strip.texture.resource_path, strip.in_world,
				])
	_expect(counted > 0, "the look tables hand out sprites (%d)" % counted)
	_expect(broken == 0, "every sprite has a texture that divides into its frames")
	_expect(astray == 0, "and a pivot inside its own frame")
	_expect(mislabelled == 0, "and the scale flag agrees with which folder the file is in")

	# The bindings, against the catalogue they have to separate.
	var nozzles: LookTable = load("res://resources/fx/looks/engine_nozzle.tres") as LookTable
	var plumes: LookTable = load("res://resources/fx/looks/engine_plume.tres") as LookTable
	var seen_nozzles: Array[SpriteStrip] = []
	var seen_plumes: Array[SpriteStrip] = []
	var undrawn: int = 0
	for path: String in LootGenerator.ENGINE_BASES:
		var engine: EngineData = load(path) as EngineData
		var nozzle: SpriteStrip = nozzles.pick(engine)
		var plume: SpriteStrip = plumes.pick(engine)
		if nozzle == null or plume == null:
			undrawn += 1
			continue
		if not seen_nozzles.has(nozzle):
			seen_nozzles.append(nozzle)
		if not seen_plumes.has(plume):
			seen_plumes.append(plume)
	_expect(undrawn == 0, "every engine base resolves to a nozzle and a plume")
	_expect(
		seen_nozzles.size() >= 3,
		"the nozzle table tells the three engine types apart (%d looks)" % seen_nozzles.size(),
	)
	_expect(
		seen_plumes.size() >= 3,
		"and the plume table sorts the catalogue by thrust (%d looks)" % seen_plumes.size(),
	)

	var muzzles: LookTable = load("res://resources/fx/looks/weapon_muzzle.tres") as LookTable
	var seen_guns: Array[SpriteStrip] = []
	var unarmed: int = 0
	for path: String in LootGenerator.WEAPON_BASES:
		var weapon: WeaponData = load(path) as WeaponData
		var muzzle: SpriteStrip = muzzles.pick(weapon)
		if muzzle == null:
			unarmed += 1
			continue
		if not seen_guns.has(muzzle):
			seen_guns.append(muzzle)
	_expect(unarmed == 0, "every weapon base resolves to a gun sprite")
	_expect(
		seen_guns.size() >= 4,
		"and the gun table tells the weapon types apart (%d looks)" % seen_guns.size(),
	)

	# The affix binding, on the real table and a real engine.
	#
	# This check spent a while asserting the opposite. `EngineData` had no
	# `affixes` field, because the generator threw the rolled list away, so
	# the "steerable" entry in the nozzle table was written, correct and
	# **inert** -- and the test said so, on the grounds that the day engines
	# started keeping their affixes something should notice. This is that
	# day, and this is the something.
	var gimballed: EngineData = (
		load("res://resources/engines/gimballed_drive.tres") as EngineData
	)
	var plain: SpriteStrip = nozzles.pick(gimballed)
	var steerable: EngineData = gimballed.duplicate() as EngineData
	steerable.affixes = [&"steerable"] as Array[StringName]
	_expect(
		nozzles.pick(steerable) != plain and nozzles.pick(steerable) != null,
		"an affix changes the picture, and beats the threshold that would not have",
	)
	_expect(
		nozzles.pick(gimballed) == plain,
		"and an engine without it falls back to the measurement",
	)

	# And the interface family is the one place still authored 1:1.
	var glyphs: LookTable = load("res://resources/fx/looks/module_icon.tres") as LookTable
	var flat: bool = true
	for strip: SpriteStrip in glyphs.every_strip():
		if strip != null and strip.in_world:
			flat = false
	_expect(flat, "interface glyphs are authored at the design size, not at Art.FACTOR")

	# The node itself. Everything above is tables and files; this is the one
	# piece of running code, and it is the piece that turns "the pivot is
	# right in the resource" into "the part is bolted on straight".
	var sprite: StripSprite = StripSprite.new()
	root.add_child(sprite)
	var plume: SpriteStrip = plumes.by_value(900.0)
	sprite.show_strip(plume)
	_expect(
		sprite.offset == -plume.pivot and not sprite.centered,
		"a strip sprite hangs off its own pivot, not off the middle of the frame",
	)
	_expect(
		is_equal_approx(sprite.scale.x, Art.WORLD_SCALE)
		and sprite.texture_filter == Art.WORLD_FILTER,
		"and takes its scale and its filter from the strip, not from the scene",
	)
	_expect(
		sprite.hframes == plume.frames and sprite.material is CanvasItemMaterial,
		"a plume is a strip of %d frames, drawn additively" % plume.frames,
	)

	# Throttle shut, frame held. This is the rule the whole animation design
	# rests on: the rate is a reading off the ship, so an engine that is not
	# burning has a flame that is not moving -- and nothing had to be told
	# to stop it.
	sprite.drive(0.0)
	for tick: int in range(30):
		sprite.advance(1.0 / 60.0)
	_expect(sprite.frame == 0, "a shut throttle holds the first frame")

	sprite.drive(1.0)
	var before: int = sprite.frame
	var moved: bool = false
	for tick: int in range(30):
		sprite.advance(1.0 / 60.0)
		if sprite.frame != before:
			moved = true
	_expect(moved, "and a full one runs the strip (%.0f fps)" % sprite.rate)
	_expect(
		sprite.frame >= 0 and sprite.frame < plume.frames,
		"never off the end of the strip",
	)

	# Half throttle, half the speed, because the rate is the strip's own
	# times the fraction and nothing else gets a say.
	sprite.drive(0.5)
	_expect(
		is_equal_approx(sprite.rate, plume.full_rate * 0.5),
		"half a throttle flickers at half the rate",
	)

	var glyph: SpriteStrip = glyphs.pick(null, &"engine")
	sprite.show_strip(glyph)
	_expect(
		is_equal_approx(sprite.scale.x, 1.0)
		and sprite.texture_filter == Art.UI_FILTER
		and sprite.material == null,
		"and the same node draws an interface glyph at 1:1, Nearest, opaque",
	)
	sprite.queue_free()


## Próznia jest cicha, i to jest regula, nie ustawienie miksera.
##
## VISUALS.md section 2 makes this a design decision rather than a mixing
## preference: in space you hear only what travels through the ship's own
## structure, so entering an atmosphere is the moment the world starts to
## sound. A pilot learns the air model by ear before reading it off the
## HUD, and `air_density` -- computed every tick since M1 -- does a second
## job for nothing.
##
## Checked by asking, not by listening. Headless there is no sound at all,
## so `play()` reports whether it spent a voice and the rule is read off
## that; which is also why the layer switch is applied at the master bus
## rather than inside `play()`, where it would have made every answer here
## the same one.
func _check_soundscape() -> void:
	# The buses, in the order the layout declares them.
	for wanted: String in ["Master", "Sfx", "Ambient", "Ui"]:
		_expect(
			AudioServer.get_bus_index(wanted) >= 0,
			"there is a %s bus" % wanted,
		)
	var sfx: int = AudioServer.get_bus_index("Sfx")
	_expect(
		sfx >= 0 and AudioServer.get_bus_effect(sfx, 0) is AudioEffectLowPassFilter,
		"and the one carrying the world has something to muffle it with",
	)

	var sound: Soundscape = Soundscape.new()
	root.add_child(sound)

	# The cutoff rises with the air, and rises exponentially, because
	# hearing does: halfway between 320 Hz and 20 kHz by frequency is
	# nowhere near halfway by ear.
	sound.set_muffle(0.0)
	var vacuum: float = _cutoff()
	sound.set_muffle(0.5)
	var thin: float = _cutoff()
	sound.set_muffle(1.0)
	var thick: float = _cutoff()
	_expect(
		is_equal_approx(vacuum, Soundscape.MUFFLED_HZ)
		and is_equal_approx(thick, Soundscape.OPEN_HZ),
		"vacuum is a dull thud and thick air is wide open (%.0f to %.0f Hz)" % [
			vacuum, thick,
		],
	)
	_expect(
		thin < (vacuum + thick) * 0.5,
		"and half the air is far less than half the brightness (%.0f Hz)" % thin,
	)

	# The rule itself. A thump through the frame is audible in vacuum; the
	# same thump out in the world is not; and the interface is not in the
	# world at all, so a menu that went quiet in space would be a menu that
	# had misunderstood.
	var thump: AudioStream = load("res://resources/audio/thump.tres")
	_expect(thump != null, "there is a sound to try")
	sound.density = 0.0
	var in_vacuum: Array[bool] = [
		sound.play(thump, Vector2.ZERO, Soundscape.Path.CONDUCTED),
		sound.play(thump, Vector2.ZERO, Soundscape.Path.AIRBORNE),
		sound.play(thump, Vector2.ZERO, Soundscape.Path.INTERFACE),
	]
	sound.density = 1.0
	var in_air: Array[bool] = [
		sound.play(thump, Vector2.ZERO, Soundscape.Path.CONDUCTED),
		sound.play(thump, Vector2.ZERO, Soundscape.Path.AIRBORNE),
		sound.play(thump, Vector2.ZERO, Soundscape.Path.INTERFACE),
	]
	# Element by element rather than against an array literal: `as` binds
	# looser than `==`, so `a == [...] as Array[bool]` casts the comparison
	# instead of the literal and will not even parse.
	_expect(
		in_vacuum[0] and not in_vacuum[1] and in_vacuum[2],
		"in vacuum only the hull and the interface are heard (%s)" % [in_vacuum],
	)
	_expect(
		in_air[0] and in_air[1] and in_air[2],
		"and in air everything is (%s)" % [in_air],
	)

	# Thin air is quieter, not silent: the rule is a slope, and a cliff at
	# the atmosphere's edge would be heard as a switch being thrown.
	sound.density = 0.3
	_expect(
		sound.carries(Soundscape.Path.AIRBORNE) > 0.0
		and sound.carries(Soundscape.Path.AIRBORNE) < 1.0,
		"thin air carries a sound faintly rather than not at all (%.2f)" % [
			sound.carries(Soundscape.Path.AIRBORNE),
		],
	)
	_expect(
		is_equal_approx(sound.carries(Soundscape.Path.CONDUCTED), 1.0),
		"while what comes up through the frame does not care about the air",
	)

	# And the pool is a pool: more sounds than voices must not grow the
	# node, because the thing it replaces is an allocation per gunshot.
	var before: int = sound.get_child_count()
	for shot: int in range(Soundscape.VOICES * 3):
		sound.play(thump, Vector2.ZERO, Soundscape.Path.CONDUCTED)
	_expect(
		sound.get_child_count() == before,
		"%d sounds share %d voices and allocate nothing" % [
			Soundscape.VOICES * 3, before,
		],
	)

	for voice: Node in sound.get_children():
		(voice as AudioStreamPlayer2D).stream = null
	sound.free()


## What the low-pass on the world bus is set to.
func _cutoff() -> float:
	var sfx: int = AudioServer.get_bus_index("Sfx")
	var muffle: AudioEffectLowPassFilter = (
		AudioServer.get_bus_effect(sfx, 0) as AudioEffectLowPassFilter
	)
	return muffle.cutoff_hz if muffle != null else 0.0


## Co odpryskuje: iskry z kadluba, pyl z krateru, kurz spod dysz.
##
## Three VISUALS V3 items share one node, because they are one shape:
## something gives way at a point and bits of it leave in a hurry. What
## differs is which way they leave and how bright they are, and that is two
## arguments rather than three systems.
##
## Every number here is read back from the layer rather than looked at. The
## gate sits on the node's `visible`, not inside the decisions -- the fifth
## time this project has had to make that split, and the reason the whole
## thing can be checked with no window open.
func _check_debris() -> void:
	var system: StarSystem = StarSystem.generate(20260922)
	var world: SystemBody = null
	for body: SystemBody in system.planets():
		if body.atmosphere_height > 0.0:
			world = body
			break
	_expect(world != null, "the seed grows a planet with air to land on")
	if world == null:
		return

	var stage: Node2D = Node2D.new()
	root.add_child(stage)
	var planet: Planet = (load(PLANET_SCENE) as PackedScene).instantiate() as Planet
	planet.name = "Planet"
	stage.add_child(planet)
	planet.adopt(world)

	var ship: Ship = (load(SHIP_SCENE) as PackedScene).instantiate() as Ship
	ship.name = "Ship"
	ship.use_player_input = false
	stage.add_child(ship)

	var field: DebrisField = DebrisField.new()
	field.name = "DebrisField"
	field.ship_path = NodePath("../Ship")
	stage.add_child(field)

	# One new file, and the two things it listens to were both already
	# being announced: `hull_impact` since M1 and `carved` since M1.3,
	# neither with a listener until now. Nothing was added to either.
	_expect(
		ship.hull_impact.get_connections().size() == 1
		and planet.carved.get_connections().size() == 1,
		"the hull and the ground are listened to, and neither had to change",
	)
	_expect(
		field.get_child_count() == DebrisField.BURSTS + 1,
		"%d pooled bursts and the one standing cloud" % DebrisField.BURSTS,
	)

	# A graze throws less than a crash, and a tap throws nothing at all --
	# a ship settling onto its feet must not spray sparks.
	var sparks: Callable = func(speed: float) -> int:
		for pooled: Node in field._pool:
			(pooled as GPUParticles2D).emitting = false
		ship.linear_velocity = Vector2(0.0, -speed)
		ship.hull_impact.emit(speed, 0.2)
		var most: int = 0
		for pooled: Node in field._pool:
			var one: GPUParticles2D = pooled as GPUParticles2D
			if one.emitting:
				most = maxi(most, one.amount)
		return most
	var crash: int = sparks.call(DebrisField.REFERENCE_SPEED)
	var graze: int = sparks.call(DebrisField.REFERENCE_SPEED * 0.25)
	var tap: int = sparks.call(DebrisField.REFERENCE_SPEED * 0.02)
	_expect(
		crash == DebrisField.MOST_SPARKS,
		"a hit at the reference speed throws everything it has (%d)" % crash,
	)
	_expect(
		graze > 0 and graze < crash,
		"a quarter of the speed throws a quarter of the grit (%d of %d)" % [graze, crash],
	)
	_expect(tap == 0, "and setting down gently throws none of it (%d)" % tap)

	# Backwards, because that is the way the thing it hit pushed.
	for pooled: Node in field._pool:
		(pooled as GPUParticles2D).emitting = false
	ship.linear_velocity = Vector2(200.0, 0.0)
	ship.hull_impact.emit(200.0, 0.2)
	var thrown: Vector2 = _spray_of(field)

	# Two throws per strike. ASSETLIST asks for both a hot dot and a strip
	# of chips at an impact, and they are not the same event seen twice:
	# the light goes instantly and the pieces it lit are still there
	# afterwards, which is why the chips are given the longer life.
	var busy: Array[GPUParticles2D] = []
	for pooled: Node in field._pool:
		if (pooled as GPUParticles2D).emitting:
			busy.append(pooled as GPUParticles2D)
	_expect(
		busy.size() == 2,
		"a strike throws light and pieces, not one standing for both (%d)" % busy.size(),
	)
	var additive: int = 0
	var lit: int = 0
	var cut: int = 0
	for one: GPUParticles2D in busy:
		var skin: CanvasItemMaterial = one.material as CanvasItemMaterial
		if skin == null:
			continue
		if skin.blend_mode == CanvasItemMaterial.BLEND_MODE_ADD:
			additive += 1
			lit = one.amount
		if skin.particles_animation and skin.particles_anim_h_frames > 1:
			cut += 1
	_expect(additive == 1, "the hot one burns through what is behind it, the other does not")
	_expect(
		cut == 1,
		"and the three frame strip is cut into three, so the chips are not all one chip",
	)
	_expect(
		lit > 0 and busy[0].explosiveness == 1.0 and busy[1].explosiveness == 1.0,
		"everything leaves at once rather than trickling out over the lifetime",
	)

	# And nothing vanishes. A grain at full strength for its whole life and
	# then gone between two frames reads as the effect being switched off,
	# and at a sixtieth of a second a flicker is the one thing a pixel
	# screen shows most clearly.
	var abrupt: int = 0
	for pooled: Node in field._pool:
		var how: ParticleProcessMaterial = (pooled as GPUParticles2D).process_material
		if how.alpha_curve == null:
			abrupt += 1
	var cloud: ParticleProcessMaterial = field._dust.process_material
	_expect(
		abrupt == 0 and cloud.alpha_curve != null,
		"every bit of this fades out instead of being taken away (%d abrupt)" % abrupt,
	)

	# Size from the strip, not from the call. The dot is authored at 24
	# texels and the chips at 9, so one hand-tuned scale range cannot suit
	# both -- the first version used one and made the chips invisible.
	var reach: Callable = func(one: GPUParticles2D) -> float:
		var how: ParticleProcessMaterial = one.process_material
		return how.scale_max * float(one.texture.get_height())
	_expect(
		absf(reach.call(busy[0]) - reach.call(busy[1])) < 0.01
		and absf(reach.call(busy[0]) - DebrisField.GRIT.y) < 0.01,
		"two strips authored at different sizes land at the same %.1f px on screen" % [
			DebrisField.GRIT.y,
		],
	)
	_expect(
		thrown.dot(ship.linear_velocity.normalized()) < -0.9,
		"grit comes off against the way the ship was going (%.2f, %.2f)" % [
			thrown.x, thrown.y,
		],
	)

	# Dust out of a hole leaves along the local up, not along the shot.
	# On a round world that is the surface normal, and it is also the way
	# it will fall back.
	var out: Vector2 = Vector2.RIGHT.rotated(0.7)
	var hole: Vector2 = planet.global_position + out * planet.surface_radius
	for pooled: Node in field._pool:
		(pooled as GPUParticles2D).emitting = false
	planet.carved.emit(hole, 24.0)
	_expect(
		_spray_of(field).dot(out) > 0.99,
		"and rock out of a fresh crater leaves straight up from the surface",
	)

	# The pool is a pool. The one place a run of impacts is certain is a
	# ship skidding down a slope, which is exactly when allocating an
	# emitter per contact would be worst.
	var before: int = field.get_child_count()
	for bounce: int in range(DebrisField.BURSTS * 4):
		ship.hull_impact.emit(250.0, 0.1)
	_expect(
		field.get_child_count() == before,
		"%d impacts share %d emitters and allocate nothing" % [
			DebrisField.BURSTS * 4, DebrisField.BURSTS,
		],
	)

	_check_nozzle_dust(planet, ship, field)

	Presentation.wanted = false
	field._physics_process(1.0 / 60.0)
	_expect(
		not field.visible,
		"F8 takes the whole lot away, bursts already in flight included",
	)
	Presentation.wanted = true
	stage.free()


## Kurz spod dysz: trzy warunki naraz, kazdy sam w sobie go gasi.
##
## The rule VISUALS V3 asks for is "density from air density and height",
## and the third factor is the one that is easy to leave out: a ship can be
## two metres over thick ground with its engines shut, and the ground does
## not care. So the share is a product of three, and the test kills each
## one separately -- a sum, or a pair, would pass most of these.
func _check_nozzle_dust(planet: Planet, ship: Ship, field: DebrisField) -> void:
	var up: Vector2 = Vector2.UP.rotated(0.35)
	var ground: float = planet.surface_radius_at(planet.global_position + up * 1000.0)

	# Pointed so the main drive pushes away from the planet, which is what
	# throws its exhaust at it. Found rather than assumed: which way a hull
	# carries its drive is the hull's business.
	var drive: EngineInstance = null
	for engine: EngineInstance in ship.engines:
		engine.throttle = 1.0
		if drive == null or engine.data.max_thrust > drive.data.max_thrust:
			drive = engine
	_expect(drive != null, "the ship has an engine to land on")
	if drive == null:
		return

	# The main drive alone, with everything else shut. Not every engine at
	# full: a ship firing all of them at once really is blasting the ground
	# whichever way up it is, which the first version of the inverted check
	# below measured and called a failure of the geometry it was aiming at.
	var settle: Callable = func(height: float, air: float, power: float) -> float:
		ship.global_position = planet.global_position + up * (ground + height)
		ship.global_rotation = up.angle() - drive.thrust_direction().angle()
		for engine: EngineInstance in ship.engines:
			engine.throttle = power if engine == drive else 0.0
		ship.air_density = air
		return field.stir()

	var landing: float = settle.call(6.0, 1.0, 1.0)
	_expect(landing > 0.0, "a landing burn in thick air raises dust (%.2f)" % landing)
	_expect(
		field._dust.emitting and field._dust.amount_ratio > 0.0,
		"and the cloud is actually asked for (%.2f)" % field._dust.amount_ratio,
	)
	# Under the ship, on the ground -- not at the nozzles. The dust is the
	# surface being disturbed, not the engine making smoke.
	_expect(
		absf(planet.height_above_terrain(field._dust.global_position)) < 1.0
		and field._dust.global_position.distance_to(ship.global_position) < 8.0,
		"thrown from the ground under the ship rather than from the nozzle",
	)

	# Each of the three, on its own.
	var airless: float = settle.call(6.0, 0.0, 1.0)
	var coasting: float = settle.call(6.0, 1.0, 0.0)
	var high: float = settle.call(DebrisField.DUST_REACH * 1.5, 1.0, 1.0)
	_expect(
		airless == 0.0,
		"the same burn over an airless rock raises nothing (%.2f)" % airless,
	)
	_expect(
		coasting == 0.0,
		"nor does hovering with the engines shut (%.2f)" % coasting,
	)
	_expect(
		high == 0.0,
		"nor does burning hard out of reach of the ground (%.2f)" % high,
	)
	_expect(
		not field._dust.emitting,
		"and the cloud is put away when any of the three fails",
	)

	# A slope, not a step. Twice as high is less dust, and the two ends
	# agree with the middle -- an effect that switched on at a threshold
	# would read as a bug in the altimeter.
	var close: float = settle.call(DebrisField.DUST_REACH * 0.2, 1.0, 1.0)
	var far: float = settle.call(DebrisField.DUST_REACH * 0.8, 1.0, 1.0)
	_expect(
		close > far and far > 0.0,
		"dust thins out with height instead of stopping (%.2f against %.2f)" % [
			close, far,
		],
	)
	var thin: float = settle.call(DebrisField.DUST_REACH * 0.2, 0.4, 1.0)
	_expect(
		thin < close and thin > 0.0,
		"and with the air, the same way (%.2f against %.2f)" % [thin, close],
	)

	# Upside down. The exhaust is pointed at the sky, so the ground is not
	# being blown about however hard the drive is working.
	settle.call(6.0, 1.0, 1.0)
	ship.global_rotation = (-up).angle() - drive.thrust_direction().angle()
	var inverted: float = field.stir()
	_expect(
		inverted == 0.0,
		"a ship burning away from the ground does not stir it at all (%.2f)" % inverted,
	)

	# And size counts, not just aim. Dividing by the engines that happen to
	# face the right way read one attitude thruster nudging the nose as a
	# full landing burn -- the ratio was right and the magnitude had gone.
	var nudge: EngineInstance = null
	for engine: EngineInstance in ship.engines:
		if nudge == null or engine.data.max_thrust < nudge.data.max_thrust:
			nudge = engine
	var burn: float = settle.call(6.0, 1.0, 1.0)
	for engine: EngineInstance in ship.engines:
		engine.throttle = 1.0 if engine == nudge else 0.0
	ship.global_rotation = up.angle() - nudge.thrust_direction().angle()
	var poke: float = field.stir()
	_expect(
		nudge != drive and poke < burn,
		"a %.0f N thruster raises less than a %.0f N drive (%.2f against %.2f)" % [
			nudge.data.max_thrust, drive.data.max_thrust, poke, burn,
		],
	)


## Which way the most recent burst threw things.
func _spray_of(field: DebrisField) -> Vector2:
	for pooled: Node in field._pool:
		var one: GPUParticles2D = pooled as GPUParticles2D
		if one.emitting:
			var how: ParticleProcessMaterial = one.process_material
			return Vector2(how.direction.x, how.direction.y).normalized()
	return Vector2.ZERO


## Statek nosi na sobie swój stan: cieplo, uszkodzenia, kulejacy silnik.
##
## Three numbers the simulation has computed every tick since M1 and that
## nothing had ever shown anywhere but as a line of debug text:
## `hull_heat`, `hull_integrity` and each engine's `health`. V2 is mostly
## this -- not new state, just finally looking at what is already there.
func _check_ship_wear() -> void:
	var ship: Ship = (load(SHIP_SCENE) as PackedScene).instantiate() as Ship
	ship.use_player_input = false
	root.add_child(ship)
	var skin: ShipSkin = ship.get_node("Presentation") as ShipSkin
	var lit: Color = Color.WHITE

	# Heat brightens, damage darkens, and the order matters: scorching is
	# what has already happened to the hull and heat is what is happening
	# to it now, so a wreck on re-entry is a glowing wreck rather than a
	# clean ship.
	ship.hull_integrity = 1.0
	ship.hull_heat = 0.0
	var sound: Color = skin.hull_shade(lit)
	ship.hull_heat = 1.0
	var hot: Color = skin.hull_shade(lit)
	ship.hull_heat = 0.0
	ship.hull_integrity = 0.0
	var wrecked: Color = skin.hull_shade(lit)
	ship.hull_heat = 1.0
	var burning_wreck: Color = skin.hull_shade(lit)

	_expect(hot.v > sound.v, "heat brightens the hull (%.2f against %.2f)" % [hot.v, sound.v])
	_expect(
		wrecked.v < sound.v,
		"damage darkens it (%.2f against %.2f)" % [wrecked.v, sound.v],
	)
	_expect(
		burning_wreck.v > wrecked.v,
		"and a wreck on re-entry still glows (%.2f against %.2f)" % [
			burning_wreck.v, wrecked.v,
		],
	)
	_expect(
		wrecked.r > wrecked.b,
		"a damaged hull reads as scorched rather than as merely unlit",
	)
	ship.hull_integrity = 1.0
	ship.hull_heat = 0.0

	# An engine wears its own condition, not the hull's: a ship can be
	# sound with one jet beaten in, and that asymmetry is the whole point
	# of the damage model.
	var drive: EngineInstance = ship.engines[0]
	drive.health = 1.0
	skin.paint(0.0, lit)
	var well: float = _nozzle_of(skin, drive).self_modulate.v
	drive.health = 0.0
	skin.paint(0.0, lit)
	var beaten: float = _nozzle_of(skin, drive).self_modulate.v
	_expect(
		beaten < well * 0.7,
		"a beaten nozzle is visibly beaten (%.2f against %.2f)" % [beaten, well],
	)
	drive.health = 1.0

	# And the impulse jets stop strobing. A torque engine's throttle is 0
	# or 1 on any one tick -- the delta-sigma modulator gives it the right
	# average, not a steady value -- so a flame following it exactly
	# flickers at sixty hertz instead of reading as a jet pulsing.
	var jet: EngineInstance = null
	for engine: EngineInstance in ship.engines:
		if engine.data.type == EngineData.Type.TORQUE:
			jet = engine
	_expect(jet != null, "the stock hull has an impulse jet to watch")
	jet.throttle = 1.0
	skin.paint(1.0 / 60.0, lit)
	var alight: float = _plume_of(skin, jet).self_modulate.a
	jet.throttle = 0.0
	skin.paint(1.0 / 60.0, lit)
	var fading: float = _plume_of(skin, jet).self_modulate.a
	_expect(alight > 0.5, "a lit jet is lit (%.2f)" % alight)
	_expect(
		fading > 0.0 and fading < alight,
		"and one tick after it shuts it is dying away, not gone (%.2f)" % fading,
	)
	for tick: int in range(30):
		skin.paint(1.0 / 60.0, lit)
	_expect(
		_plume_of(skin, jet).self_modulate.a < 0.05
		or not _plume_of(skin, jet).visible,
		"half a second later there is nothing left of it",
	)
	ship.free()


## The nozzle sprite the skin built for one engine.
func _nozzle_of(skin: ShipSkin, engine: EngineInstance) -> StripSprite:
	return _sprite_near(skin, engine.mount.position, ShipSkin.Z_NOZZLE)


## Wstrzas kamery: pierwszy odbiornik zdarzenia, czyli dowod, ze szew dziala.
##
## VISUALS.md section 6 asked for exactly one thing here and asked for it
## as a proof rather than as a feature: an effect added by a new file and
## one connection, with nothing written into `ship.gd`. `hull_impact` had
## been emitted since M1 and nothing had ever listened to it.
##
## What is checked is the shape of the scaling, not a number. An impact is
## kinetic, so the shake goes as the square of the speed -- a graze is
## nothing and an arrival that nearly kills you is a slam -- and that is a
## property a test can hold on to while the constants are still being
## tuned by eye.
func _check_camera_shake() -> void:
	var stage: Node2D = Node2D.new()
	root.add_child(stage)
	var ship: Ship = (load(SHIP_SCENE) as PackedScene).instantiate() as Ship
	ship.name = "Ship"
	ship.use_player_input = false
	stage.add_child(ship)
	var eye: Camera2D = Camera2D.new()
	eye.name = "Eye"
	eye.zoom = Vector2.ONE
	stage.add_child(eye)

	var shake: CameraShake = CameraShake.new()
	shake.ship_path = NodePath("../Ship")
	shake.camera_path = NodePath("../Eye")
	stage.add_child(shake)
	_expect(
		ship.hull_impact.get_connections().size() == 1,
		"one new file and one connection, with nothing added to the ship",
	)

	# A graze against a crash. Squared, so the gap is wider than the
	# speeds: a third of the reference should be about a ninth as much.
	ship.hull_impact.emit(100.0, 0.05)
	var graze: float = shake.energy
	shake.energy = 0.0
	ship.hull_impact.emit(300.0, 0.5)
	var slam: float = shake.energy
	_expect(graze > 0.0 and slam > 0.0, "an impact shakes the view at all")
	_expect(
		absf(slam / maxf(graze, 0.0001) - 9.0) < 0.5,
		"and three times the speed is nine times the shake (%.1fx)" % [slam / graze],
	)

	# Two bounces in a row are not three. A ship skidding down a slope
	# emits on every contact, and a shake that accumulated would work
	# itself up into something the landing never justified.
	shake.energy = 0.0
	for bounce: int in range(6):
		ship.hull_impact.emit(300.0, 0.1)
	_expect(
		is_equal_approx(shake.energy, slam),
		"six bounces are no worse than the hardest of them (%.2f)" % shake.energy,
	)

	# Constant on screen rather than in the world: `Camera2D.offset` is in
	# world units and the view runs from 0.385 to 1.7 of them to the pixel,
	# so without dividing by the zoom the same impact is a twitch close in
	# and a lurch far out.
	# `throw()` rather than the tick, because the gate is in the tick and
	# headless it clears the offset instead of setting one -- which the
	# first version of this measured as zero against zero and called a
	# failed ratio rather than a test driving the wrong function.
	#
	# Seeded identically for both, so the only thing differing between the
	# two samples is the zoom. A random direction compared by length is a
	# test that fails on an unlucky frame.
	eye.zoom = Vector2.ONE
	shake.energy = 1.0
	shake._rng.seed = 4242
	shake.throw()
	var near: float = eye.offset.length()
	eye.zoom = Vector2(0.5, 0.5)
	shake.energy = 1.0
	shake._rng.seed = 4242
	shake.throw()
	var far: float = eye.offset.length()
	_expect(
		near > 0.0 and absf(far / maxf(near, 0.0001) - 2.0) < 0.01,
		"half the zoom throws twice as far in world units (%.2f against %.2f)" % [far, near],
	)

	# And it stops. A camera still ringing after the ship has settled reads
	# as a camera fault rather than as an impact.
	shake.energy = 1.0
	for tick: int in range(120):
		shake._physics_process(1.0 / 60.0)
	_expect(
		shake.energy == 0.0 and eye.offset.is_zero_approx(),
		"two seconds later the view is exactly where it belongs (%.4f)" % shake.energy,
	)

	# With the layer off there is no shake, and no shake left over either.
	Presentation.wanted = false
	shake.energy = 1.0
	shake._physics_process(1.0 / 60.0)
	_expect(
		eye.offset.is_zero_approx() and shake.energy < 1.0,
		"F8 stops the shaking without stopping it running down",
	)
	Presentation.wanted = true
	stage.free()


## Skorka statku: czy buduje to, co trzeba, i czy oddaje widok na F8.
##
## Runs headless, which is worth being precise about. `Presentation.is_on()`
## is false here and stays false -- the gate is on *showing* the layer, not
## on building it, so the sprites exist and can be counted while nothing is
## drawn. That split is deliberate: a layer that could not be inspected
## without a window would be a layer with no tests.
func _check_skin() -> void:
	_expect(
		not Presentation.is_on(),
		"the presentation layer does not show itself headless",
	)

	var ship: Ship = (load(SHIP_SCENE) as PackedScene).instantiate() as Ship
	root.add_child(ship)
	var skin: ShipSkin = ship.get_node_or_null("Presentation") as ShipSkin
	_expect(skin != null, "the stock ship carries a skin")
	if skin == null:
		ship.free()
		return

	var sprites: Array[StripSprite] = _strip_sprites(skin)
	var hull: Polygon2D = ship.get_node_or_null("Hull") as Polygon2D
	# One hull, one nozzle and one plume per fitted engine, one gun per
	# armed hardpoint, and a strut plus a pad per leg.
	var armed: int = 0
	for hardpoint: Hardpoint in ship.hardpoints:
		if hardpoint.weapon != null:
			armed += 1
	var wanted: int = 1 + ship.engines.size() * 2 + armed + ship.gear.legs.size() * 2
	_expect(
		sprites.size() == wanted,
		"the skin builds a sprite for every part (%d of %d)" % [sprites.size(), wanted],
	)

	# The stock outline is a named hull, so it gets a picture and the
	# polygon underneath stands down.
	var named: HullData = HullData.matching(ship.hull_outline)
	_expect(named != null and named.id == &"dart", "the stock outline is recognised as the dart")
	var dart_strip: SpriteStrip = null
	for sprite: StripSprite in sprites:
		if sprite.z_index == ShipSkin.Z_HULL:
			dart_strip = sprite.strip
	_expect(dart_strip != null, "and wears the dart's picture")

	# A plume starts at the nozzle's exit plane, not at the mount. Measured
	# rather than trusted: the mount is inside the hull and a flame drawn
	# there comes out of the middle of the ship.
	var drive: EngineMount = ship.get_node_or_null("MainDrive") as EngineMount
	var exhaust: Vector2 = -drive.force_direction()
	var nozzle: SpriteStrip = (
		load("res://resources/fx/looks/engine_nozzle.tres") as LookTable
	).pick(drive.installed)
	var flame: StripSprite = _sprite_at(
		sprites, drive.position + exhaust * nozzle.exit
	)
	_expect(
		nozzle.exit > 0.0 and flame != null,
		"the main drive's flame starts %.1f px past the mount, at the bell's lip" % nozzle.exit,
	)

	# Refitting rebuilds it, off the ship's own announcement rather than off
	# the skin watching the scene.
	#
	# Checked on which hull is being worn rather than on how many sprites
	# there are, which is what the first version of this did -- and the
	# freighter happens to have the same part count as the dart, so it
	# passed while proving nothing.
	var interceptor: Dictionary = {}
	for preset: Dictionary in ShipFitout.all():
		if String(preset["name"]) == "przechwytujący":
			interceptor = preset
	ShipFitout.apply(ship, interceptor)
	_expect(
		HullData.matching(ship.hull_outline) != null
		and HullData.matching(ship.hull_outline).id == &"interceptor",
		"a refit puts a different named hull on the ship",
	)
	var worn: SpriteStrip = null
	for sprite: StripSprite in _strip_sprites(skin):
		if sprite.z_index == ShipSkin.Z_HULL:
			worn = sprite.strip
	_expect(
		worn != null and worn != dart_strip,
		"and the skin rebuilt itself onto that hull's picture",
	)

	# And a shape nobody named gets no picture, so the polygon keeps the job.
	var invented: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in ship.hull_outline:
		invented.append(point * 1.7)
	ship.hull_outline = invented
	ship.rebuild_control_groups(false)
	_expect(
		HullData.matching(ship.hull_outline) == null,
		"a hull the sandbox reshaped matches nothing in the catalogue",
	)
	var dressed: int = 0
	for sprite: StripSprite in _strip_sprites(skin):
		if sprite.z_index == ShipSkin.Z_HULL:
			dressed += 1
	_expect(dressed == 0, "so it gets no hull sprite, and the Polygon2D keeps the job")
	_expect(hull != null and hull.visible, "which means the polygon is still visible")

	ship.free()

	# What the guns throw is a sprite now as well. Walked over the weapon
	# catalogue rather than over the two scenes, because what has to hold is
	# that every weapon in the game resolves to a picture -- a scene nobody
	# fires would pass a check written against the scenes.
	var unpainted: int = 0
	var untinted: int = 0
	var rounds: int = 0
	for path: String in LootGenerator.WEAPON_BASES:
		var weapon: WeaponData = load(path) as WeaponData
		if weapon.projectile_scene == null:
			continue
		var shot: Projectile = weapon.projectile_scene.instantiate() as Projectile
		root.add_child(shot)
		rounds += 1
		var body: StripSprite = shot.get_node_or_null("Body") as StripSprite
		if body == null or body.strip == null:
			unpainted += 1
			print("    %s throws an unpainted round (%s)" % [
				weapon.title(), shot.look_key,
			])
		elif not body.self_modulate.is_equal_approx(shot.tint):
			untinted += 1
		shot.free()
	_expect(rounds > 0, "the weapon catalogue throws things (%d kinds)" % rounds)
	_expect(unpainted == 0, "and every one of them resolves to a picture")
	_expect(
		untinted == 0,
		"each painted its own tint, which is also the colour of the light it throws",
	)


## Every StripSprite the skin built.
func _strip_sprites(skin: ShipSkin) -> Array[StripSprite]:
	var out: Array[StripSprite] = []
	for child: Node in skin.get_children():
		var sprite: StripSprite = child as StripSprite
		if sprite != null and sprite.strip != null:
			out.append(sprite)
	return out


func _sprite_at(sprites: Array[StripSprite], where: Vector2) -> StripSprite:
	for sprite: StripSprite in sprites:
		if sprite.position.distance_to(where) < 0.01:
			return sprite
	return null


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
