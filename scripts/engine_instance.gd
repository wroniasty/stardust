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
const RUINED_RELIABILITY: float = 0.7

## The least an engine will ever deliver of what its throttle asked for, at
## any condition and including mid-cut-out.
##
## A floor rather than a curve down to nothing, because the thing damage is
## for is changing how a ship flies, not taking the ship away. Measured at
## the old tuning, a single hard arrival left the nearest engine giving 53%
## and the ship was no longer worth flying; punishment that stops the game
## being played is not difficulty.
##
## The asymmetry that makes a damaged ship fly crooked survives: 70% on one
## side against 100% on the other is still lopsided, which is the property
## the damage model exists for (IDEAS.md section 3).
const MIN_OUTPUT_SHARE: float = 0.7

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

## Where the nozzle is aimed, in radians off the mount's direction. Only
## ever non-zero on an engine with a gimbal.
var gimbal: float = 0.0

## Where the pilot's demand wants it aimed. Slewed towards, not snapped to.
var target_gimbal: float = 0.0

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
## What share of its rated thrust this engine can hold right now.
##
## The one place the health-to-thrust mapping lives. Anything planning a burn
## -- the allocator, the configuration report -- has to reason with the same
## curve the nozzle actually follows, or it is planning against an engine
## that does not exist.
func condition_factor() -> float:
	return lerpf(MIN_OUTPUT_SHARE, 1.0, health)


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
##
## All of it floored at MIN_OUTPUT_SHARE, cut-outs included. A cut-out is a
## dip rather than a silence now: audible in the handling, survivable in the
## flying.
func effective_output() -> float:
	if throttle <= 0.0:
		return 0.0
	if is_dropped_out():
		return throttle * MIN_OUTPUT_SHARE
	return throttle * maxf(condition_factor() * _surge_factor(), MIN_OUTPUT_SHARE)


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
	if data.gimbal_range > 0.0:
		var wanted: float = clampf(target_gimbal, -data.gimbal_range, data.gimbal_range)
		gimbal = move_toward(gimbal, wanted, data.gimbal_rate * delta)
	else:
		gimbal = 0.0
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


## Set by the ship each tick: whether this engine is running on emergency
## power. Owned here rather than read from the ship, because what an
## engine is doing is an engine's business -- and because the ship has to
## be able to switch it off for one engine and not another when the pool
## only stretches so far.
var boosting: bool = false


## What the thrust is multiplied by right now. One unless this engine has
## an emergency setting and is being asked for it.
func boost_factor() -> float:
	return data.boost_thrust if boosting and data.can_boost() else 1.0


## Fuel per second this engine would burn on emergency power at what it is
## currently managing. Zero for an engine with no boost, and zero for one
## that is idle, dropped out or dead -- a drive that is not pushing is not
## burning, however hard the pilot leans on the key.
func boost_demand() -> float:
	if not data.can_boost():
		return 0.0
	return data.fuel_cost * data.boost_burn * effective_output()


## Which way this engine is actually pushing, with the nozzle where it is.
func thrust_direction() -> Vector2:
	return mount.force_direction().rotated(gimbal)


## Force in the ship's local frame at the current throttle.
func current_force() -> Vector2:
	return thrust_direction() * data.max_thrust * effective_output() * boost_factor()


## Force in the ship's local frame at full throttle, ignoring health.
##
## The control groups are built from this, not from what the engine can still
## manage. That is deliberate: if damage rebalanced the weights, a broken
## thruster would be silently compensated for, and the whole point of the
## damage model is that a half-dead engine makes the ship fly crooked. The
## compensating flight computer is an M2 module the player has to find.
## Undeflected on purpose as well as undamaged: the groups describe what the
## hull is, and where a steerable nozzle happens to be pointing this tick is
## not that.
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
