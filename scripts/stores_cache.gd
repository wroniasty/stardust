@tool
class_name StoresCache
extends Resource
## A counted store in a box: so many spare parts, so much stardust.
##
## **The piece that was missing.** Modules could go overboard from the
## first day -- each one is a thing, and a crate holds a thing -- while
## the units could not. A hold with two hundred spare parts in it could
## only be emptied at a refinery, which meant a pilot who filled up on
## ore had nowhere to put the drive they found next. `Hold.spill` says
## the same thing from the other side: it drops the modules and
## **loses** the units, "or a crate type that does not exist yet".
## This is that type.
##
## It is not rolled and it is not on any loot table. A cache exists
## because somebody threw one out, and later because something died
## holding one -- the two ways a quantity gets out of a hold. A world
## generator that scattered these would be scattering refined goods on
## planets that have no industry, which is the opposite of the economy
## the game is built on: ore comes out of the ground, parts and
## stardust come out of a refinery.
##
## **Not a `ModuleData`**, deliberately. It has no bulk of its own, no
## rarity, no condition and nothing to fit it to, and every one of
## those fields would have to be given a meaning it does not have. What
## it has is a kind and a count, and the bulk follows from `Stores`.

## Which store, from `Stores.Kind`. An int rather than the enum type so
## the resource saves and loads as plainly as the hold does.
@export var kind: int = Stores.Kind.SPARE_PARTS

## How many units are in it. Always at least one: an empty cache is a
## crate with nothing in it, and nothing is what `null` is for.
@export var units: int = 0


static func of(kind_wanted: int, count: int) -> StoresCache:
	if count <= 0:
		return null
	var made: StoresCache = StoresCache.new()
	made.kind = kind_wanted
	made.units = count
	return made


## What colour a box of this is painted, from the palette's own roles
## rather than from a new colour: UI_STYLE section 3 forbids a screen
## keeping its own, and these have roles already. Parts and stardust
## are the **ship's** own stuff -- repair and range -- so they take the
## ship channel; raw rock is rock, and takes the dullest ink there is.
##
## Parts and stardust are told apart by the label on the crate and by
## which of the two reads as a material rather than by a thirteenth
## colour: `accent` is the worked part, `value` the dust.
static func tint(kind: int) -> Color:
	var ink: Palette = Palette.current()
	if kind == Stores.Kind.SPARE_PARTS:
		return ink.accent
	if kind == Stores.Kind.STARDUST:
		return ink.value
	return ink.inert


## What the box takes up, which is exactly what it took up in the hold
## it came out of. The room is the whole reason a pilot throws one.
func bulk() -> float:
	return Stores.bulk_of(kind, units)


## What the pilot is told they have found: "48 spare parts".
##
## The count first, because the count is the news. A crate that said
## "spare parts" and left the number for a panel would be a crate a
## pilot has to pick up to price.
func title() -> String:
	return "%d %s" % [units, Stores.kind_name(kind)]
