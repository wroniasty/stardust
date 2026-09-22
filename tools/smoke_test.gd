extends SceneTree
## Headless flight check for the ship. Run with:
##   godot --headless --path . --script res://tools/smoke_test.gd
##
## Verifies the things that are easy to get silently wrong: that the input
## actions exist, that the main engine pushes the ship along its nose without
## spinning it, and that each rotational engine turns the ship the way the
## pilot asked. Exits non-zero on the first failed expectation.
##
## The checks run on the real physics loop, one phase at a time, because the
## physics server cannot be stepped by hand from script.

const SHIP_SCENE: String = "res://scenes/ship.tscn"
const BURN_TICKS: int = 60

enum Phase { MAIN_ENGINE, TURN_RIGHT, TURN_LEFT, DONE }

var _phase: int = Phase.MAIN_ENGINE
var _ticks: int = 0
var _elapsed: float = 0.0
var _ship: Ship = null
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
	if _ticks < BURN_TICKS:
		return false

	_evaluate_phase()
	_ship.free()
	_ship = null
	_phase += 1
	if _phase == Phase.DONE:
		return _finish()
	_begin_phase()
	return false


func _begin_phase() -> void:
	_ticks = 0
	_elapsed = 0.0

	var scene: PackedScene = load(SHIP_SCENE) as PackedScene
	_ship = scene.instantiate() as Ship
	_ship.use_player_input = false
	root.add_child(_ship)

	match _phase:
		Phase.MAIN_ENGINE:
			_ship.thrust_command = 1.0
			_ship.turn_command = 0.0
		Phase.TURN_RIGHT:
			_ship.thrust_command = 0.0
			_ship.turn_command = 1.0
		Phase.TURN_LEFT:
			_ship.thrust_command = 0.0
			_ship.turn_command = -1.0


func _evaluate_phase() -> void:
	match _phase:
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
