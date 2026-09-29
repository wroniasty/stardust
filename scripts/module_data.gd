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

## Rarity names and the colour each one is painted in, dullest to brightest.
## The colour is the only thing readable from orbit, and at 640x360 the pale
## grey of a common find and the near-white of an uncommon one have to be
## told apart as an eight-pixel dot.
const RARITY_NAMES: Array[String] = ["common", "uncommon", "rare", "epic", "legendary"]
const RARITY_COLORS: Array[Color] = [
	Color(0.55, 0.57, 0.60), ## pale grey
	Color(0.85, 0.89, 0.94), ## silver
	Color(0.35, 0.62, 1.00), ## blue
	Color(0.72, 0.42, 1.00), ## purple
	Color(1.00, 0.80, 0.28), ## gold
]

## How good the roll that made this module was, 0..4.
##
## On the module rather than travelling beside it. It used to ride alongside,
## on the argument that rarity is a fact about the roll and not about the
## machine -- true, and it cost more than it was worth: the crate, the hold,
## the cargo bay and the editor each carried their own copy, and the sandbox
## quietly stamped every find it made as rare because one of those copies was
## a hard-coded constant. When there was no shared base class the argument
## had nowhere to go; ModuleData is that base now.
@export var rarity: int = 0


## What this module's roll is called, and the colour it is painted.
func rarity_name() -> String:
	return RARITY_NAMES[clampi(rarity, 0, RARITY_NAMES.size() - 1)]


func rarity_color() -> Color:
	return RARITY_COLORS[clampi(rarity, 0, RARITY_COLORS.size() - 1)]


## How big the module physically is: the mass it adds, and what has to fit in
## the slot. One unit across every kind of module, so a cargo bay needs no
## table of conversions and a pilot no second number to learn.
@export var bulk: float = 1.0

## One line of an information card: a label, the number behind it, how to
## print it, and which way is up.
##
## `better` is +1 when more is better, -1 when less is, 0 when it is just a
## fact. That last field is the whole reason these are rows rather than a
## formatted string: a comparison cannot colour a difference it cannot tell
## the direction of, and "spread 1.0 against 2.0" is an improvement while
## "bulk 1.0 against 2.0" is a different kind of one.
static func row(
	label: String, value: float, digits: int, better: int, suffix: String = ""
) -> Dictionary:
	return {
		"label": label, "value": value, "digits": digits, "better": better, "suffix": suffix,
	}


## What this module is, as rows. Overridden by each kind; the base answers
## with what every module has.
##
## On the resource rather than in the screen that draws it, so a card, a
## comparison and a future tooltip all read the same numbers and none of
## them can quietly disagree about what a weapon is.
func stat_rows() -> Array[Dictionary]:
	return [row("gabaryt", bulk, 2, -1)]


## A short line of prose under the numbers. Blank unless a kind has
## something worth saying that a number cannot.
func blurb() -> String:
	return ""


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
