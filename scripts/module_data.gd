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

## What this kind of thing is called, before any affix: "autocannon",
## "main drive", "standard cell". Every kind has one now, including
## engines, which used to be named after their own enum.
@export var display_name: String = "module"

## Names of the affixes rolled into the numbers, for display only.
##
## On the base class, so every kind keeps the roll that made it. There used
## to be three habits here and no rule: a weapon kept its list, a generator
## threw it away after baking it into a string, and an engine threw it away
## without baking anything -- which is why engines were called "thruster
## engine 664".
@export var affixes: Array[StringName] = []

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
	return [row("bulk", bulk, 2, -1)]


## A short line of prose under the numbers. Blank unless a kind has
## something worth saying that a number cannot.
func blurb() -> String:
	return ""


## Longest title a card can show, in characters.
##
## Derived rather than picked: the swap screen's panel is 210 px wide, the
## interface font is fixed-width at six pixels a character, and the panel
## keeps a few for its border. A test checks this against the real panel
## and the real font from both sides -- that a title this long fits and
## that a longer one does not -- so the number cannot drift away from the
## thing it describes.
##
## The question had no answer at all until the font had one. In a
## proportional face "how many characters fit" depends on which characters,
## which is the other half of why UI_STYLE insists on monospace here.
const TITLE_LIMIT: int = 33


## What this module is called: its affixes, then its base name.
##
## Composed on every call rather than baked in at generation. That matters
## for more than tidiness: a baked string cannot be shortened, because
## nothing can tell afterwards which words were affixes. Composing means
## the same item can be named at one length for a card and another for a
## pickup prompt, and means an affix list and a name can never disagree.
func title() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for affix: StringName in affixes.slice(0, named_affixes()):
		parts.append(String(affix))
	parts.append(display_name)
	return " ".join(parts)


## How many affixes the title has room for.
##
## As many as fit, in the order they were rolled; the rest go on their own
## line of the card. The plan asked for "the two strongest" instead, and
## that cannot be done yet, because nothing ranks affixes: the table is
## ordered by theme and a rolled list is in roll order, so neither is a
## ranking. Inventing one here would be inventing it in the wrong place.
func named_affixes() -> int:
	var room: int = TITLE_LIMIT - display_name.length()
	var taken: int = 0
	for affix: StringName in affixes:
		room -= String(affix).length() + 1
		if room < 0:
			break
		taken += 1
	return taken


## The affixes the title had no room for.
func dropped_affixes() -> Array[StringName]:
	return affixes.slice(named_affixes())


## The whole information card: what it is, how good the roll was, a line of
## prose, and every number with its difference from what it would replace.
##
## Here rather than in a screen, so the quick swap and the editor read the
## same card. Two screens each formatting their own would be two things
## quietly disagreeing about what a weapon is, which is the problem the rows
## above were introduced to end.
func card_lines(against: ModuleData = null) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	out.append("%s   %s" % [title(), rarity_name()])
	var prose: String = blurb()
	if not prose.is_empty():
		out.append(prose)
	# What the title had to leave out. On its own line rather than lost:
	# an affix that changed the numbers and is named nowhere is a number
	# the pilot cannot account for.
	var spilled: Array[StringName] = dropped_affixes()
	if not spilled.is_empty():
		var rest: PackedStringArray = PackedStringArray()
		for affix: StringName in spilled:
			rest.append(String(affix))
		out.append("also: %s" % ", ".join(rest))

	var other: Dictionary = {}
	if against != null:
		for row: Dictionary in against.stat_rows():
			other[row["label"]] = row

	for row: Dictionary in stat_rows():
		out.append(_stat_line(row, other.get(row["label"], {})))
	return out


## The font a card is written for.
##
## The lines above pad with spaces -- "%-13s %8.2f" puts the labels and the
## numbers in columns, and in a proportional font that is simply false: the
## spaces are narrower than the letters they are standing in for, so the
## numbers come out ragged and a column of values cannot be read down. Either
## the padding goes or the font is fixed-width, and a card is a table.
##
## It used to build a SystemFont here and ask the OS for Consolas, which
## made the look of every screen in the game depend on what happened to be
## installed. The answer lives in `UiFont` now -- one face, three sizes --
## and this stays only because the format strings above are the reason the
## face has to be fixed-width, and a rule should be stated where it is
## relied on.
static func card_font() -> Font:
	return UiFont.face()


## A row, and how it differs from the same row on the module it replaces.
func _stat_line(row: Dictionary, was: Dictionary) -> String:
	var digits: int = int(row["digits"])
	var text: String = "%-13s %8.*f%s" % [row["label"], digits, float(row["value"]), row["suffix"]]
	if was.is_empty():
		return text
	var change: float = float(row["value"]) - float(was["value"])
	if absf(change) < pow(10.0, -float(digits)) * 0.5:
		return text + "   ="
	# Marked by whether it is an improvement, not by whether it went up:
	# less spread and less bulk are both wins with a minus in front.
	var good: bool = change * float(row["better"]) > 0.0
	return "%s  %s%.*f %s" % [
		text, "+" if change > 0.0 else "", digits, change, "better" if good else "worse",
	]


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
