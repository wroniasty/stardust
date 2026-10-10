@tool
class_name WeaponData
extends ModuleData
## What a weapon *is*, independent of the hardpoint it is bolted to.
##
## The same split as EngineData and EngineMount: this holds the numbers, the
## Hardpoint holds the position and the angle. Moving a gun to another mount
## changes where it points and nothing else (see IDEAS.md section 4).
##
## The loot generator rolls these. Affixes are baked into the numbers at
## generation time rather than applied as live modifiers -- once an item is
## rolled it never changes, so a list of names for display is all that has to
## survive alongside the values.

## What the weapon throws.
##
## Three behaviours carry all six: a round that coasts, a round that flies
## under power, and a beam that does not fly at all. The rest is data on this
## resource. A class per type would become a class per combination the moment
## mods start changing what a round does (IDEAS.md section 4).
enum Type {
	PROJECTILE, ## A round with travel time, sampled along its path.
	LASER, ## Hitscan: the beam is drawn, the damage is instant.
	DUMB_MISSILE, ## Accelerates after launch, flies straight.
	HOMING_MISSILE, ## Accelerates and turns towards what it can find.
	AOE, ## A round that hurts what it did not hit.
	PULSE, ## Short burst at close range: cheap, fast, no reach.
}


## Whether this type flies under power rather than coasting.
func is_missile() -> bool:
	return type == Type.DUMB_MISSILE or type == Type.HOMING_MISSILE


## Whether it is resolved along a ray instead of being spawned.
func is_beam() -> bool:
	return type == Type.LASER

@export var type: Type = Type.PROJECTILE

## What the weapon throws, as a scene. On the weapon rather than the hardpoint:
## a mount does not decide whether it fires slugs or missiles.
@export var projectile_scene: PackedScene

## Damage on the same 0..1 scale as hull integrity, so 0.08 is twelve hits to
## kill a healthy ship.
@export var damage: float = 0.08

@export var rounds_per_second: float = 4.0

## Muzzle velocity, in pixels per second.
@export var muzzle_speed: float = 600.0

## Total cone of inaccuracy, in degrees.
@export var spread_degrees: float = 2.0

## How far a round travels before it gives up, in pixels.
##
## Range rather than lifetime, because range is what a pilot judges and what an
## affix should modify: a round that flies faster should reach further, not
## live the same four seconds.
@export var range_px: float = 2400.0

## Radius of the hole punched in the crust on impact.
@export var crater_radius: float = 14.0

## If true the round carries the ship's velocity, so shooting while moving does
## not leave rounds hanging behind the ship.
@export var inherit_velocity: bool = true

## Energy per shot, paid out of the ship's generator. Zero until the power
## economy lands later in M2; the field exists so the loot tables have somewhere
## to put it.
##
## This is what limits sustained fire: rate of fire says how fast the gun
## shoots, energy says how long (see IDEAS.md section 14).
@export var energy_cost: float = 0.0

## How many shot mods can be plugged into this weapon. Rarity raises it: the
## slot count is what a found gun offers, and what the pilot then does with
## the slots is theirs (IDEAS.md section 14).
@export var mod_slots: int = 0


## How far this weapon's own ring can turn off its mount, in radians each
## way, and how fast the motor swings it.
##
## On the weapon and not on the hardpoint, for the same reason a gimbal is on
## EngineData: the ring and its motor are part of the machine. A fixed gun is
## zero here whatever it is bolted to, and a turret keeps its sweep when it
## is moved to another mount.
##
## The hull has its own say -- see Hardpoint.traverse_limit -- and the arc
## that actually applies is the smaller of the two. Same shape as bulk
## against a slot's size: what the module can do, against what the hull
## allows (IDEAS.md section 4).
@export var traverse_range: float = 0.0
@export var traverse_rate: float = 3.0


## Acceleration after launch, px/s^2, and how fast the round can turn to
## follow something, radians per second. Missiles only; a coasting round
## ignores both.
##
## A missile leaves the rail slowly and builds speed, which is what makes it
## dodgeable early and what makes firing one a commitment rather than a
## click.
@export var missile_thrust: float = 0.0
@export var missile_turn_rate: float = 0.0

## How far an impact reaches past what it struck. Zero on a round that only
## hurts what it hits.
@export var blast_radius: float = 0.0

## How long the beam stays drawn. Only the drawing: the damage lands the
## instant the trigger is pulled, so a laser is a very fast pulse and energy
## keeps one rule for everything (IDEAS.md section 14).
@export var beam_seconds: float = 0.06


## Seconds a round lives, derived so that range survives a change of speed.
func lifetime() -> float:
	return range_px / maxf(muzzle_speed, 1.0)


## Rounds needed to strip a full hull, which is the number that says what the
## weapon is for better than damage per shot does.
func shots_to_kill() -> int:
	return int(ceilf(1.0 / maxf(damage, 0.0001)))


## Damage per second at full rate of fire.
func damage_per_second() -> float:
	return damage * rounds_per_second


## What a gun is, in the order a pilot cares about it.
func stat_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = [
		row("dps", damage_per_second(), 3, 1),
		row("damage", damage, 3, 1),
		row("rate", rounds_per_second, 2, 1, "/s"),
		row("energy", energy_cost, 1, -1),
		row("per unit", damage / maxf(energy_cost, 0.0001), 4, 1),
		row("spread", rad_to_deg(deg_to_rad(spread_degrees)), 1, -1, " deg"),
		row("range", range_px, 0, 1, " px"),
		row("crater", crater_radius, 0, 1, " px"),
		row("arc", rad_to_deg(traverse_range), 0, 1, " deg"),
		row("traverse", rad_to_deg(traverse_rate), 0, 1, " deg/s"),
		row("sockets", float(mod_slots), 0, 1),
	]
	if blast_radius > 0.0:
		rows.append(row("blast", blast_radius, 0, 1, " px"))
	if is_missile():
		rows.append(row("thrust", missile_thrust, 0, 1))
		rows.append(row("guidance", rad_to_deg(missile_turn_rate), 0, 1, " deg/s"))
	rows.append(row("bulk", bulk, 2, -1))
	return rows


func blurb() -> String:
	return "%s, %d shots from a full pool" % [
		Type.keys()[int(type)].to_lower().replace("_", " "),
		int(100.0 / maxf(energy_cost, 0.0001)),
	]
