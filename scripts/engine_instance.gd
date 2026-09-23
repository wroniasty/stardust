class_name EngineInstance
extends RefCounted
## One engine actually fitted to one mount, with its current wear and throttle.
##
## RefCounted rather than a node: an instance is a pairing the ship rebuilds
## whenever the configuration changes, and giving each one a node would mean
## keeping the scene tree in sync with a list that is derived anyway.

var data: EngineData = null
var mount: EngineMount = null

## Condition, 0..1. Multiplies the thrust. Damage lowers it (M2).
var health: float = 1.0

## Current throttle after the type's response curve, 0..1.
var throttle: float = 0.0

## Where the control solver wants the throttle to be, 0..1.
var target_throttle: float = 0.0

## Accumulated demand for an impulse engine's duty cycle. See advance().
var _pulse_charge: float = 0.0


func _init(engine_data: EngineData, engine_mount: EngineMount) -> void:
	data = engine_data
	mount = engine_mount


## What actually comes out of the nozzle, 0..1.
func effective_output() -> float:
	return throttle * health


## Advances the throttle one step, following this engine type's character.
##
## TORQUE is the interesting one. It is an impulse engine: the throttle is only
## ever 0 or 1, never in between. Reading that as "fire whenever anything is
## asked of it" is a trap, and it bit: a torque jet sitting in a strafe group at
## weight 0.16 fired at full power, throwing four times the intended side force
## and sending the brake chasing a drift it was creating itself.
##
## So the fraction becomes a duty cycle instead of an amplitude, through a
## first-order delta-sigma modulator: demand accumulates, the engine fires for
## one whole tick each time the accumulator passes 1, and the remainder carries
## over. The average thrust is exactly the demand, every individual tick is
## still hard on or hard off, and a small share now means an occasional puff
## rather than a full burn.
func advance(delta: float) -> void:
	match data.type:
		EngineData.Type.MAIN:
			throttle = move_toward(
				throttle, clampf(target_throttle, 0.0, 1.0), data.spool_rate() * delta
			)
		EngineData.Type.TORQUE:
			_pulse_charge += clampf(target_throttle, 0.0, 1.0)
			if _pulse_charge >= 1.0:
				_pulse_charge -= 1.0
				throttle = 1.0
			else:
				throttle = 0.0
		_:
			throttle = clampf(target_throttle, 0.0, 1.0)


## Force in the ship's local frame at the current throttle.
func current_force() -> Vector2:
	return mount.force_direction() * data.max_thrust * effective_output()


## Force in the ship's local frame at full throttle, ignoring health.
##
## The control groups are built from this, not from what the engine can still
## manage. That is deliberate: if damage rebalanced the weights, a broken
## thruster would be silently compensated for, and the whole point of the
## damage model is that a half-dead engine makes the ship fly crooked. The
## compensating flight computer is an M2 module the player has to find.
func nominal_force() -> Vector2:
	return mount.force_direction() * data.max_thrust


func type_name() -> String:
	return EngineData.Type.keys()[int(data.type)]
