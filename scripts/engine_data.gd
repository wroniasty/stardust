class_name EngineData
extends ModuleData
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

## A braking engine: a thruster built to push against the way the ship is
## going. Not a control type -- the throttle behaves as a THRUSTER's does --
## only a label, so the editor can draw it differently from a strafe jet.
@export var retro: bool = false

## Force at full throttle and full health, in the ship's local frame.
@export var max_thrust: float = 100.0


## Seconds from idle to full thrust, and back. MAIN only; the other types
## ignore it.
@export var spool_time: float = 0.6

## How far the nozzle can be steered off the mount's own direction, in
## radians each way. Zero means it is bolted straight, which is every engine
## but a gimballed main drive.
##
## A gimbal is what lets one big engine do the work of a torque pair: the
## thrust that is already there gets aimed, instead of a second set of jets
## being fitted to fight it (IDEAS.md section 3).
@export var gimbal_range: float = 0.0

## How fast the nozzle swings, in radians per second. Slow enough that a
## gimbal is a heavy rudder rather than an instant one.
@export var gimbal_rate: float = 3.0

## Chance of behaving, 0..1. Stored now, simulated in M2 as dropouts and
## oscillating thrust.
@export_range(0.0, 1.0) var reliability: float = 1.0

## Fuel burned per second at full throttle.
##
## **This is the M5 item the field was waiting for.** It said so itself:
## "the fuel economy itself lands in M5; until then this is the rate
## `boost_burn` multiplies, and the pool it comes out of is the ship's
## energy". So for three milestones a number called `fuel_cost` cost no
## fuel, was rolled by two affixes (`frugal`, `tuned`) that moved
## nothing, and was printed on every engine card.
##
## It is fuel now, scaled by `Ship.THRUST_FUEL_RATE` -- the one knob
## that says how much a burn costs against what a jump costs.
@export var fuel_cost: float = 0.0

## Emergency power: what the thrust is multiplied by while the pilot holds
## boost.
##
## A way out of a hole, and that is the whole reason it exists. A ship can
## be put somewhere its engines cannot lift it out of -- a heavy world, a
## full hold, a damaged drive, or all three -- and without this the only
## answer is to respawn. One is the default, meaning this engine has no
## emergency setting; only the big drives get one, because a thruster
## running at three times its rating is not a thruster, it is a bomb.
@export var boost_thrust: float = 1.0

## And what it draws from the **energy pool** while it is lit, per second
## at full output.
##
## An absolute rate rather than a multiple of `fuel_cost`, which is what
## it used to be. One number cannot mean fuel per second and also be the
## base of an energy rate: the day `fuel_cost` started costing fuel, a
## `frugal` engine would have become cheaper to boost as a side effect of
## being cheaper to fly, which is two decisions made by one roll.
##
## The figures are the ones that multiple produced, so the balance is
## unchanged: twelve a second on the stock main drive against a pool of
## about a hundred is roughly eight seconds of boost, which is enough to
## get off the ground and not enough to fly anywhere on. Boost is not a
## better engine with a drawback, it is the same engine spent faster.
@export var boost_draw: float = 0.0


## Whether this engine has an emergency setting at all.
func can_boost() -> bool:
	return boost_thrust > 1.0


## Throttle change per second while spooling. MAIN only.
func spool_rate() -> float:
	return 1.0 / maxf(spool_time, 0.001)


func stat_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = [
		row("thrust", max_thrust, 0, 1),
		row("spool", spool_time, 2, -1, " s"),
		row("reliability", reliability, 2, 1),
		row("fuel", fuel_cost, 2, -1, "/s"),
		row("bulk", bulk, 2, -1),
	]
	if can_boost():
		rows.append(row("boost", boost_thrust, 1, 1, "x"))
		rows.append(row("boost draw", boost_draw, 1, -1, "/s"))
	if gimbal_range > 0.0:
		rows.append(row("gimbal", rad_to_deg(gimbal_range), 0, 1, " deg"))
		rows.append(row("gimbal rate", rad_to_deg(gimbal_rate), 0, 1, " deg/s"))
	return rows


## An engine is named like everything else now: in its own resource, and
## composed with whatever it rolled. It used to be named after its own
## enum and its thrust -- "thruster engine 664" -- on the argument that a
## mount decides what an engine is for. True, and it is not an argument
## about what to call it: the thrust is a row on the card, and a number in
## a name is a number in two places.


func blurb() -> String:
	return "%s — %s" % [
		Type.keys()[int(type)].to_lower(),
		"throttled, with a spool-up" if type == Type.MAIN
		else ("impulse, 0 or 1" if type == Type.TORQUE else "instant"),
	]
