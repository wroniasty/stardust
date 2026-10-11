class_name FlightAssists
extends RefCounted
## Co komputer pokladowy umie robic za pilota, jako jedna tabela.
##
## Six of these already existed as commands the ship read from a chord or
## a key every tick. What they did not have was a list: each one was a
## field on `Ship`, a branch in `_resolve_commands`, a row in the help
## screen and a `has_*` on `FlightComputerData`, and nothing anywhere
## said they were the same kind of thing.
##
## They are, and the panel that switches them on is the reason it now
## matters. A panel needs them in a fixed order, needs to know which the
## fitted box can actually do, and must keep an empty square where a
## function it cannot do would sit (UI_STYLE section 12, trap 3). All
## three are properties of the set rather than of any one assist, so the
## set is a table and the panel walks it.
##
## Deliberately not a resource and not a node: a table of six literals
## that two files read is a constant, and making it a `.tres` would mean
## a file nobody will ever edit guarding an order nobody will ever
## change.

## The assists, in panel order. That order is muscle memory, so it is
## the authored one rather than the enum's or the alphabet's: the two
## pointing holds first because they are what a pilot reaches for most,
## then the two that fly the ship somewhere, then the two that hold it
## steady.
enum Kind { PROGRADE, RETROGRADE, ORBIT, DEORBIT, LEVEL, ALTITUDE, SPIN_KILL }

## Which field on `FlightComputerData` has to be true for an assist to be
## offered, and what it is called.
##
## `requires` empty means every ship can do it, with no computer at all.
## That is the case for the two heading holds and it is deliberate: they
## have been on `hold_prograde` and `hold_retrograde` since M1, ungated,
## and quietly making them need a module would take something away from
## every ship in the game. The panel offers them because the panel is
## where assists live, not because the computer grants them.
const ALL: Array[Dictionary] = [
	{
		"kind": Kind.PROGRADE, "requires": &"",
		"caption": "prograde", "latches": &"heading",
	},
	{
		"kind": Kind.RETROGRADE, "requires": &"",
		"caption": "retrograde", "latches": &"heading",
	},
	{
		"kind": Kind.ORBIT, "requires": &"has_auto_orbit",
		"caption": "auto-orbit", "latches": &"",
	},
	{
		"kind": Kind.DEORBIT, "requires": &"has_deorbit",
		"caption": "deorbit", "latches": &"",
	},
	{
		"kind": Kind.LEVEL, "requires": &"has_auto_level",
		"caption": "auto-level", "latches": &"",
	},
	{
		"kind": Kind.ALTITUDE, "requires": &"has_altitude_hold",
		"caption": "altitude hold", "latches": &"",
	},
	{
		"kind": Kind.SPIN_KILL, "requires": &"has_rotation_kill",
		"caption": "spin kill", "latches": &"",
	},
]


## The entry for one kind, or an empty dictionary.
static func entry(kind: int) -> Dictionary:
	for one: Dictionary in ALL:
		if int(one["kind"]) == kind:
			return one
	return {}


static func caption(kind: int) -> String:
	return String(entry(kind).get("caption", ""))


## Whether a ship with this computer -- or with none -- can be asked for
## this assist.
##
## Asked of the box's own field rather than of a list of module names,
## which is UI_STYLE section 12's rule: a widget requires a **capability**
## and modules supply capabilities, so a better computer tomorrow needs no
## edit here.
static func offered_by(kind: int, box: FlightComputerData) -> bool:
	var needs: StringName = entry(kind).get("requires", &"")
	if needs == &"":
		return true
	if box == null:
		return false
	return bool(box.get(String(needs)))


## Which kinds cannot be latched at the same time as this one.
##
## Only the pointing pair so far, and they are exclusive because they
## are the same assist with a sign: a ship cannot hold its nose both
## along the velocity and against it, and letting both switches sit down
## at once would show a panel that disagrees with the ship.
static func excludes(kind: int) -> Array[int]:
	var group: StringName = entry(kind).get("latches", &"")
	var out: Array[int] = []
	if group == &"":
		return out
	for one: Dictionary in ALL:
		if int(one["kind"]) != kind and StringName(one["latches"]) == group:
			out.append(int(one["kind"]))
	return out
