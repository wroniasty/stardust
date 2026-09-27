class_name EngineData
extends Resource
## What an engine *is*, independent of where it is bolted on.
##
## The type does not name a role. A MAIN engine is not "the one that goes
## forward": it is an engine whose throttle takes time to spool. What a given
## engine is good for comes out of its mount geometry in
## Ship.rebuild_control_groups(), so moving an engine changes what it does
## without touching any data (see IDEAS.md section 3).
##
## M2 turns these into loot: the generator rolls the numbers, the affix tables
## hang off the same fields.

## Throttle character, not purpose.
enum Type {
	MAIN, ## Spools up and down over spool_time. Big, slow to answer.
	TORQUE, ## Impulse only: fully on or fully off, nothing in between.
	THRUSTER, ## Instant and proportional. Small, precise.
}

@export var type: Type = Type.THRUSTER

## Force at full throttle and full health, in the ship's local frame.
@export var max_thrust: float = 100.0

## How big the machine physically is. Does two jobs, and deliberately only one
## number does both:
##
## 1. It is the mass the engine adds to the ship. Not the mount's `size`: a
##    slot is a hole in the hull, and a hole weighs nothing. What is bolted
##    into it is what moves the centre of mass.
## 2. It must be no larger than the slot's `size`, or it does not fit.
##
## This is what stops "any engine in any mount" from being a free upgrade.
## Types stay open on purpose -- a MAIN engine in a nose slot is a legitimate,
## sluggish choice (see IDEAS.md section 3) -- but a nine-hundred-newton drive
## is physically large, so it only goes where there is room, and wherever it
## goes it is felt as mass.
@export var bulk: float = 1.0

## Seconds from idle to full thrust, and back. MAIN only; the other types
## ignore it.
@export var spool_time: float = 0.6

## Chance of behaving, 0..1. Stored now, simulated in M2 as dropouts and
## oscillating thrust.
@export_range(0.0, 1.0) var reliability: float = 1.0

## Fuel burned per second at full throttle. Unused until the fuel economy lands
## in M5; the field exists so the loot tables have somewhere to put it.
@export var fuel_cost: float = 0.0


## Throttle change per second while spooling. MAIN only.
func spool_rate() -> float:
	return 1.0 / maxf(spool_time, 0.001)
