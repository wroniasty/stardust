class_name ShotModData
extends ModuleData
## Something plugged into a weapon, changing what its rounds do and what they
## cost.
##
## The distinction from an affix matters: an affix is a fact about the item, a
## mod is a decision by the pilot. So affixes are baked into the numbers at
## generation (IDEAS.md section 4) and mods cannot be -- they get plugged and
## unplugged. The resulting numbers are worked out once, when a mod changes,
## and read from the cache at every shot.
##
## Order is deliberately irrelevant. Ordering is a workshop mechanic with
## dragging, and the swap screen is a small panel in the corner with one key
## per action. If stations ever get a real workbench this can be reopened.

enum Effect {
	NONE,
	## Keeps going after the first thing it hits, up to `pierce_count` more.
	PIERCE,
	## Tears a much wider hole than the round's own calibre would.
	BLAST,
	## Leaves the ground burning -- carried as data now, simulated with the
	## rest of the damage-over-time work.
	INCENDIARY,
}

@export var display_name: String = "mod"

## What it does to the cost of a shot. Greater than one, always: the slot
## says how many mods fit, energy says how much you get to fire with them.
## The table is checked for this the same way affix costs are.
@export var energy_multiplier: float = 1.2

## Multipliers on the weapon's own numbers. Left at one when untouched, so a
## mod only says what it changes.
@export var damage_multiplier: float = 1.0
@export var rate_multiplier: float = 1.0
@export var spread_multiplier: float = 1.0
@export var crater_multiplier: float = 1.0
@export var range_multiplier: float = 1.0
@export var speed_multiplier: float = 1.0

## Behaviour added to the round, as data read at spawn rather than as another
## projectile scene. Section 4 already says a projectile scene is a chassis
## and the rest is data; a scene per combination of mods would be a file per
## combination.
@export var effect: Effect = Effect.NONE

## How many extra things a PIERCE round survives.
@export var pierce_count: int = 1


func stat_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = [row("koszt strzału", energy_multiplier, 2, -1, "x")]
	for pair: Array in [
		["obrażenia", damage_multiplier], ["kadencja", rate_multiplier],
		["rozrzut", spread_multiplier], ["krater", crater_multiplier],
		["zasięg", range_multiplier], ["prędkość", speed_multiplier],
	]:
		if not is_equal_approx(float(pair[1]), 1.0):
			rows.append(row(String(pair[0]), float(pair[1]), 2, 1, "x"))
	if effect != Effect.NONE:
		rows.append(row(Effect.keys()[int(effect)].to_lower(), 1.0, 0, 0))
	return rows


func blurb() -> String:
	return "afiks to cecha przedmiotu, moduł to decyzja pilota"
