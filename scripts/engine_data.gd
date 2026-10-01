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

## Fuel burned per second at full throttle. The fuel economy itself lands
## in M5; until then this is the rate `boost_burn` multiplies, and the
## pool it comes out of is the ship's energy (see Ship.BOOST_RESERVE).
@export var fuel_cost: float = 0.0

## Emergency power: what the thrust is multiplied by while the pilot holds
## boost, and what the burn is multiplied by to pay for it.
##
## A way out of a hole, and that is the whole reason it exists. A ship can
## be put somewhere its engines cannot lift it out of -- a heavy world, a
## full hold, a damaged drive, or all three -- and without this the only
## answer is to respawn. One is the default, meaning this engine has no
## emergency setting; only the big drives get one, because a thruster
## running at three times its rating is not a thruster, it is a bomb.
##
## The burn multiplier is deliberately far steeper than the thrust one.
## Boost is not a better engine with a drawback, it is the same engine
## spent faster: three times the push for twelve times the burn means
## roughly eight seconds of it on a full pool, which is enough to get off
## the ground and not enough to fly anywhere on.
@export var boost_thrust: float = 1.0
@export var boost_burn: float = 1.0


## Whether this engine has an emergency setting at all.
func can_boost() -> bool:
	return boost_thrust > 1.0


## Throttle change per second while spooling. MAIN only.
func spool_rate() -> float:
	return 1.0 / maxf(spool_time, 0.001)


func stat_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = [
		row("ciąg", max_thrust, 0, 1),
		row("rozruch", spool_time, 2, -1, " s"),
		row("niezawodność", reliability, 2, 1),
		row("paliwo", fuel_cost, 2, -1, "/s"),
		row("gabaryt", bulk, 2, -1),
	]
	if can_boost():
		rows.append(row("dopalanie", boost_thrust, 1, 1, "x"))
		rows.append(row("spalanie", fuel_cost * boost_burn, 1, -1, "/s"))
	if gimbal_range > 0.0:
		rows.append(row("gimbal", rad_to_deg(gimbal_range), 0, 1, " st"))
		rows.append(row("wychylanie", rad_to_deg(gimbal_rate), 0, 1, " st/s"))
	return rows


## An engine has no name of its own: what it is called comes from its type,
## because what it is for comes from where it is mounted.
func title() -> String:
	return "%s engine %.0f" % [Type.keys()[int(type)].to_lower(), max_thrust]


func blurb() -> String:
	return "%s — %s" % [
		Type.keys()[int(type)].to_lower(),
		"przepustnica z rozruchem" if type == Type.MAIN
		else ("impulsowy, 0 albo 1" if type == Type.TORQUE else "natychmiastowy"),
	]
