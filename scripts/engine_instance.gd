class_name EngineInstance
extends RefCounted
## One engine actually fitted to one mount, with its current wear and throttle.
##
## RefCounted rather than a node: an instance is a pairing the ship rebuilds
## whenever the configuration changes, and giving each one a node would mean
## keeping the scene tree in sync with a list that is derived anyway.

var data: EngineData = null
var mount: EngineMount = null

## Condition, 0..1. Multiplies the thrust, and eats into how dependable the
## engine is: a bent thruster is not merely weaker, it is less trustworthy.
var health: float = 1.0

## How reliable an engine at zero health is, as a share of its rating. Not
## zero: a wrecked engine that simply never fires is a missing engine, and
## the interesting failure is the one that fires *sometimes*.
const RUINED_RELIABILITY: float = 0.35

## Expected cut-outs per second at zero reliability, and how long one lasts.
## Per second rather than per tick, or the physics rate would decide how
## broken the ship feels.
const DROPOUT_RATE: float = 2.5
const DROPOUT_LENGTH: float = 0.18

## How much of its thrust an utterly unreliable engine loses to surging, and
## how fast the surge cycles.
const SURGE_DEPTH: float = 0.45
const SURGE_HZ: float = 7.0

## Seconds left of the current cut-out, and where the surge is in its cycle.
var _dropout_left: float = 0.0
var _surge_phase: float = 0.0

## Per-engine randomness, seeded from the mount so a given ship misbehaves
## the same way twice. Shared randomness would have every engine on the hull
## cut out on the same tick, which reads as a stutter in the game rather than
## as a fault in one machine.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

## Current throttle after the type's response curve, 0..1.
var throttle: float = 0.0

## Where the control solver wants the throttle to be, 0..1.
var target_throttle: float = 0.0

## Accumulated demand for an impulse engine's duty cycle. See advance().
var _pulse_charge: float = 0.0


func _init(engine_data: EngineData, engine_mount: EngineMount) -> void:
	data = engine_data
	mount = engine_mount
	_rng.seed = hash(mount.name)
	_surge_phase = _rng.randf() * TAU


## How likely this engine is to behave right now, 0..1. The rating, pulled
## down by whatever damage it has taken.
func current_reliability() -> float:
	return clampf(data.reliability * lerpf(RUINED_RELIABILITY, 1.0, health), 0.0, 1.0)


## True while the engine is in the middle of a cut-out.
func is_dropped_out() -> bool:
	return _dropout_left > 0.0


## What actually comes out of the nozzle, 0..1.
##
## Three things in order: how hard it was asked, what condition it is in, and
## whether it is behaving. The middle one is why a damaged ship flies crooked
## -- the control groups were built from nominal thrust and do not know about
## any of this.
func effective_output() -> float:
	if is_dropped_out():
		return 0.0
	return throttle * health * _surge_factor()


## The surge, never above one. An unreliable engine reads as struggling to
## hold its output, not as occasionally exceeding it: thrust that sometimes
## overshoots would be a bonus wearing a fault's clothes.
func _surge_factor() -> float:
	var unreliability: float = 1.0 - current_reliability()
	if unreliability <= 0.0:
		return 1.0
	return 1.0 - unreliability * SURGE_DEPTH * (0.5 + 0.5 * sin(_surge_phase))


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
	_advance_faults(delta)
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


## Rolls for a cut-out and moves the surge along. Kept apart from the
## throttle curve above because the throttle is what the pilot asked for and
## this is what the machine does about it.
func _advance_faults(delta: float) -> void:
	_surge_phase = fmod(_surge_phase + delta * SURGE_HZ * TAU, TAU)

	if _dropout_left > 0.0:
		_dropout_left = maxf(_dropout_left - delta, 0.0)
		return

	var unreliability: float = 1.0 - current_reliability()
	if unreliability <= 0.0:
		return
	# Only while something is being asked of it. An idle engine cutting out
	# is not a fault anybody can observe, and rolling for it would burn the
	# sequence that makes a given ship misbehave reproducibly.
	if target_throttle <= 0.0:
		return
	if _rng.randf() < unreliability * DROPOUT_RATE * delta:
		_dropout_left = DROPOUT_LENGTH
