class_name ModuleData
extends Resource
## What every module has in common: a size, and the right to change numbers
## that are not its own.
##
## The second part is the point of the class. An engine with the `dynamo`
## affix gives up thrust and hands back recharge rate; a generator with
## `buffered` buys capacity with mass. A pilot who would rather shoot flies a
## slower ship. That is what stops loot being a shopping list of the same
## number going up (IDEAS.md section 14).

## How big the module physically is: the mass it adds, and what has to fit in
## the slot. One unit across every kind of module, so a cargo bay needs no
## table of conversions and a pilot no second number to learn.
@export var bulk: float = 1.0

## Flat additions and multipliers on ship-wide stats, keyed by name.
##
## Two dictionaries rather than one with a rule about which keys add. "You add
## capacities and multiply costs" needs remembering which field is which, and
## affix tables are data nobody type-checks while writing them.
##
## Order across the ship is fixed: base, plus every stat_add, then times every
## stat_mul. Sums first, so a multiplier works on the whole ship rather than
## on whatever happened to be bolted on before it.
@export var stat_add: Dictionary = {}
@export var stat_mul: Dictionary = {}
