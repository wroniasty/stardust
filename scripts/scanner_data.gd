class_name ScannerData
extends ModuleData
## A survey scanner: how far it sees other systems, and how much it says.
##
## Two numbers that do different jobs, which IDEAS.md section 10 keeps
## apart on purpose: **reach** decides which systems appear at all, and
## **depth** decides how much you know about one before committing a jump
## to it. A pilot with a long cheap scanner sees a lot of dots with
## nothing written under them.
##
## Reach is deliberately not the same number as the jump drive's. Systems
## you can see and cannot yet reach are drawn grey -- that is what turns
## a better drive into somewhere to go rather than a shorter trip to
## where you already were.
##
## **This is not the thing that finds planets in the system you are in.**
## That stays with the hull: `ScannerHud.scan_range` is in pixels, and the
## streaming manager guarantees nothing is asleep inside it. A module
## free to raise that number would be a module able to promise contacts
## the world has not built yet, so the two sensors stay two sensors. This
## one looks outward.

## How much a scanner says about a system before you go there.
##
## Steps rather than a dial, because each step is a different sentence on
## a marker rather than a bigger number: "something at 14 ly" and "a red
## dwarf, four worlds, two docks" are not the same reading made finer.
enum Depth {
	## A direction and a distance. Enough to fly at, nothing more.
	BEARING,
	## And what kind of star it is, and what it is called.
	CLASS,
	## And how many worlds it holds.
	SURVEY,
	## And what is built there, and how dangerous it is.
	DEEP,
}

const DEPTH_NAMES: Array[String] = ["bearing", "class", "survey", "deep"]

## How far it sees, in light years.
@export var reach: float = 14.0

## How much it says. Bought with rarity rather than with affixes, the same
## way a flight computer buys functions: a finer reading is a different
## instrument, not a bigger one.
@export var depth: Depth = Depth.BEARING


func depth_name() -> String:
	return DEPTH_NAMES[clampi(int(depth), 0, DEPTH_NAMES.size() - 1)]


## Whether this scanner tells you at least this much about a system.
func knows(wanted: Depth) -> bool:
	return int(depth) >= int(wanted)


func stat_rows() -> Array[Dictionary]:
	return [
		row("range", reach, 1, 1, " ly"),
		row("resolution", float(int(depth)), 0, 1),
		row("bulk", bulk, 2, -1),
	]


func blurb() -> String:
	return "reads: %s" % depth_name()
