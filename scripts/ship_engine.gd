class_name ShipEngine
extends Node2D
## A single engine mounted on a ship.
##
## Named ShipEngine, not Engine, because Engine is a Godot singleton.
##
## The engine knows nothing about steering. It only reports how much force it
## produces and where that force is applied. Torque falls out of the offset
## between the mount point and the centre of mass, so a rotational engine is
## just an engine mounted off-axis (see IDEAS.md section 3).
##
## The node's own position and rotation define the mount: `position` is the
## offset from the ship origin, and the thrust points along `thrust_direction`
## rotated by the node. Exhaust particles are a child, so rotating the node in
## the editor points both the force and the flame the right way.

enum Type {
	MAIN, ## Forward thrust.
	ROTATIONAL, ## Mounted off-axis to turn the ship.
	MANEUVER, ## Lateral translation. M2.
	BRAKING, ## Retro thrust. M2.
	OTHER,
}

@export var engine_type: Type = Type.MAIN

## Force at full throttle and full efficiency, in the ship's local frame.
@export var max_thrust: float = 800.0

## Thrust direction in the engine's own frame. Up is "pushes the ship forward".
@export var thrust_direction: Vector2 = Vector2.UP

## Wear, 0..1. Multiplies the thrust. Damage lowers it (M2).
@export_range(0.0, 1.0) var efficiency: float = 1.0

## Chance of the engine behaving itself, 0..1. Stored now, simulated in M2
## (dropouts, stutter, oscillating thrust).
@export_range(0.0, 1.0) var reliability: float = 1.0

## How far the exhaust reacts behind the throttle, per second.
@export var exhaust_response: float = 12.0

## Set by the ship every physics tick, 0..1.
var throttle: float = 0.0

@onready var _exhaust: GPUParticles2D = get_node_or_null("Exhaust") as GPUParticles2D

var _exhaust_level: float = 0.0


func _process(delta: float) -> void:
	if _exhaust == null:
		return
	_exhaust_level = lerpf(_exhaust_level, current_output(), clampf(exhaust_response * delta, 0.0, 1.0))
	_exhaust.emitting = _exhaust_level > 0.02
	_exhaust.amount_ratio = clampf(_exhaust_level, 0.0, 1.0)


## Thrust direction in the ship's frame, unit length.
func get_thrust_direction() -> Vector2:
	var direction: Vector2 = transform.basis_xform(thrust_direction)
	if direction.is_zero_approx():
		return Vector2.ZERO
	return direction.normalized()


## Throttle scaled by wear, 0..1. This is what actually comes out of the nozzle.
func current_output() -> float:
	return clampf(throttle, 0.0, 1.0) * efficiency


## Force vector in the ship's frame for the current throttle.
func get_thrust_force() -> Vector2:
	return get_thrust_direction() * max_thrust * current_output()


## Sign of the torque this engine produces around the ship origin:
## positive turns the ship clockwise on screen, negative counter-clockwise,
## zero means the thrust line passes through the origin.
func torque_sign() -> float:
	return signf(position.cross(get_thrust_direction()))
