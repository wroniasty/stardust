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

## If true the ship steers itself from the player's input actions. AI ships and
## tests turn this off and write the command fields directly.
@export var use_player_input: bool = true

var engines: Array[ShipEngine] = []

## Steering commands, refreshed every physics tick. Thrust is 0..1, turn is
## -1..1 with positive turning the nose clockwise on screen.
var thrust_command: float = 0.0
var turn_command: float = 0.0

var _applied_force: Vector2 = Vector2.ZERO
var _applied_torque: float = 0.0


func _ready() -> void:
	for child: Node in get_children():
		if child is ShipEngine:
			engines.append(child as ShipEngine)


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if use_player_input:
		read_player_input()
	_apply_commands_to_engines()

	_applied_force = Vector2.ZERO
	_applied_torque = 0.0

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
