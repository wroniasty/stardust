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

## What the weapon throws. Only PROJECTILE flies today; the rest are declared
## because the hardpoint's accepted-type list has to be able to name them, and
## they land later in M2.
enum Type {
	PROJECTILE, ## A round with travel time, sampled along its path.
	LASER, ## Hitscan.
	DUMB_MISSILE, ## Slow, accelerating, no guidance.
	HOMING_MISSILE, ## Slow, accelerating, turns towards a target.
	AOE, ## Damage over an area rather than at a point.
	PULSE, ## Short burst at close range.
}

@export var type: Type = Type.PROJECTILE

## Shown when the weapon is fitted or found. Rolled names come from the
## generator; a hand-made weapon just carries its own.
@export var display_name: String = "gun"

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


## Names of the affixes rolled into the numbers above, for display only.
@export var affixes: Array[StringName] = []


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
