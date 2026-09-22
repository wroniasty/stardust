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
const FALL_TICKS: int = 60
const ORBIT_TICKS: int = 900

## FIELD comes first and only inspects a planet. It has to run on the physics
## loop like everything else: nodes added from _initialize() are not in the
## tree yet, so a planet queried there would still hold its default parameters
## instead of the ones _ready() rolls from the seed.
enum Phase { FIELD, MAIN_ENGINE, TURN_RIGHT, TURN_LEFT, FREE_FALL, ORBIT, DONE }

var _phase: int = Phase.FIELD
var _ticks: int = 0
var _elapsed: float = 0.0
var _ship: Ship = null
var _planet: Planet = null
var _orbit_radius: float = 0.0
var _orbit_min: float = INF
var _orbit_max: float = 0.0
var _failures: int = 0


func _initialize() -> void:
	for action: String in ["ship_thrust", "ship_rotate_left", "ship_rotate_right"]:
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
		previous_damp = shell.linear_damp
		previous_priority = shell.priority


# --- Flight phases ---

func _phase_ticks() -> int:
	match _phase:
		Phase.FIELD:
			return 1
		Phase.FREE_FALL:
			return FALL_TICKS
		Phase.ORBIT:
			return ORBIT_TICKS
		_:
			return BURN_TICKS


func _begin_phase() -> void:
	_ticks = 0
	_elapsed = 0.0

	if _phase == Phase.FIELD or _phase == Phase.FREE_FALL or _phase == Phase.ORBIT:
		_planet = _spawn_planet()
	if _phase != Phase.FIELD:
		_ship = _spawn_ship()

	match _phase:
		Phase.MAIN_ENGINE:
			_ship.thrust_command = 1.0
		Phase.TURN_RIGHT:
			_ship.turn_command = 1.0
		Phase.TURN_LEFT:
			_ship.turn_command = -1.0
		Phase.FREE_FALL:
			_ship.global_position = _planet.global_position + Vector2.UP * _planet.surface_radius * 2.0
		Phase.ORBIT:
			# Well clear of the atmosphere, so drag cannot be blamed for drift.
			_orbit_radius = _planet.surface_radius * 1.5
			_orbit_min = INF
			_orbit_max = 0.0
			_ship.global_position = _planet.global_position + Vector2.UP * _orbit_radius
			# v = sqrt(g * R^2 / r) is the circular orbit speed for an inverse
			# square field with g measured at the surface.
			var speed: float = sqrt(_planet.surface_gravity * pow(_planet.surface_radius, 2.0) / _orbit_radius)
			_ship.linear_velocity = Vector2.RIGHT * speed


func _evaluate_phase() -> void:
	match _phase:
		Phase.FIELD:
			_check_gravity_field(_planet)
			_check_atmosphere_shells(_planet)
		Phase.MAIN_ENGINE:
			# The nose points up, so thrust must show up as negative Y velocity.
			var expected: float = (800.0 / _ship.mass) * _elapsed
			_expect(
				absf(-_ship.linear_velocity.y - expected) < expected * 0.05,
				"main engine reaches %.1f px/s along the nose (got %.1f)" % [expected, -_ship.linear_velocity.y],
			)
			_expect(absf(_ship.linear_velocity.x) < 0.01, "main engine does not push sideways")
			_expect(absf(_ship.angular_velocity) < 0.001, "main engine does not spin the ship")
		Phase.TURN_RIGHT:
			_check_turn(1.0, "RotateRightEngine", "clockwise")
		Phase.TURN_LEFT:
			_check_turn(-1.0, "RotateLeftEngine", "counter-clockwise")
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


func _check_turn(turn: float, expected_engine: String, description: String) -> void:
	_expect(
		signf(_ship.angular_velocity) == signf(turn),
		"turn %+.0f spins the ship %s (angular velocity %.3f)" % [turn, description, _ship.angular_velocity],
	)
	for engine: ShipEngine in _ship.engines:
		if engine.engine_type != ShipEngine.Type.ROTATIONAL:
			continue
		var should_burn: bool = engine.name == expected_engine
		_expect(
			(engine.throttle > 0.0) == should_burn,
			"turn %+.0f leaves %s throttle at %.2f" % [turn, engine.name, engine.throttle],
		)


# --- Plumbing ---

func _spawn_ship() -> Ship:
	var scene: PackedScene = load(SHIP_SCENE) as PackedScene
	var ship: Ship = scene.instantiate() as Ship
	ship.use_player_input = false
	root.add_child(ship)
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


func _expect(condition: bool, description: String) -> void:
	if condition:
		print("  ok   %s" % description)
	else:
		print("  FAIL %s" % description)
		_failures += 1
