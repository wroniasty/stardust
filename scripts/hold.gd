class_name Hold
extends RefCounted
## What a ship is carrying: one thing in its hands, a bay of things stowed,
## and whatever it has by the unit.
##
## Lifted out of `ship.gd`, which was three thousand lines and counting and
## had the flight model, the collision response, the fitout, the hold and
## the repair bay all answering to the same class. This is the first of
## two pieces taken off it.
##
## **The ship's own API did not change.** `ship.carried`, `ship.cargo`,
## `ship.stores`, `ship.take()`, `ship.stow()` and the rest
## all still work, because ninety-seven places read those fields and a
## hundred and thirty-six call those methods, and a refactor whose value is
## "the file is shorter" does not get to spend two hundred and thirty edits
## buying it. `Ship` forwards; this holds.
##
## ## What it does not know
##
## **How big it is.** Capacity is a fact about the ship -- the hull's own
## figure, plus what a cargo module adds, minus what a generator crowds out
## -- so every call that needs room takes it as an argument. That is the
## same shape `Stores.add` already had, and it is what lets this be tested
## without building a ship.
##
## **Where the ship is.** Refining and breaking things down pay a rate that
## depends on whether the legs are down (`Refinery.Place`), so that arrives
## as an argument too.
##
## **That anything happened.** Nothing here emits. The hold changing is
## mass changing, and mass changing is handling changing, so the ship has
## to rebuild its control groups and tell its instruments -- which is the
## ship's business and was already written out in eight separate places
## before this split gave it one.

## The one module the ship is carrying loose, and how good it was. One slot,
## not an inventory: a full hold has to be dealt with before the next find,
## which keeps the loadout screen to a single decision (IDEAS.md section 4).
var carried: Resource = null

## The cargo bay: things stowed for later, measured in the same bulk unit as
## everything else. Not slots -- a capacity -- so "can I take this" is a
## question about the machine rather than about a grid, and a full bay of
## heavy modules is felt in how the ship flies.
##
## Entries are { "item": Resource, "rarity": int }, in the order they were
## stowed. Rarity rides alongside because no module Resource carries it.
var cargo: Array[Dictionary] = []

## And what it carries by the unit: spare parts, stardust, and the ore
## kinds that arrive with mining.
##
## The same volume as the modules, deliberately. A hold full of ore is a
## hold with no room for the drive you just found, and that trade is
## what the premise is made of -- see `Stores`.
var stores: Stores = Stores.new()

## How many average finds the stock hold holds. **The premise parameter**,
## and the reason the hold is a number with an argument behind it rather
## than a number off a hull (PLAN.md, premise point 7).
##
## "Loot galore" against a small hold is a sequence of decisions; against
## a big one it is hoovering. So the hold is sized against **what one
## cleared world hands over**, and both sides of that were measured
## rather than guessed:
##
## - An average rolled module is **1.54 bulk** (20000 rolls across every
##   kind: a weapon 1.39, an engine 1.71, a tank or jump drive 2.22, a
##   shot mod 0.20).
## - One defended body hands over one item per defender: **4.2 at the rim**
##   (worst 7), 9.2 mid-ladder, **15.5 in the core** (worst 21).
##
## Four, so clearing one rim world slightly overfills the hold. That is
## the shape the premise asks for at the only place it can be taught: at
## the rim the pilot can take nearly everything and learns that the hold
## is the limit, and by the core they are carrying a quarter of what they
## kill and choosing which quarter.
##
## The hold used to be 11 bulk, which is 7.1 finds -- larger than
## anything the rim could hand over, so the first few hours of the game
## had no such decision in them at all.
##
## The figure is about the **hull's** hold. What a given ship can carry
## is that minus whatever its fitted generator crowds out
## (`Ship.CARGO_CROWDING`) and plus whatever a cargo module adds
## (`cargo_capacity` is in `Ship.STATS`) -- the stock ship comes out at
## 3.3 finds for the first reason, which is the pilot's trade rather than
## the premise's, and a cargo module being a real find rather than a
## filler is the second.
const FINDS_PER_HOLD: float = 4.0


## How good the thing in the hold is. Read off the module rather than
## stored, so it cannot disagree with what is actually being carried.
func carried_rarity() -> int:
	var module: ModuleData = carried as ModuleData
	return module.rarity if module != null else 0


## How big any module is, whichever kind it is. The one place that knows
## that both module Resources answer to the same field.
static func module_bulk(item: Resource) -> float:
	var module: ModuleData = item as ModuleData
	return module.bulk if module != null else 0.0


## What is in the bay and the bins, in bulk. The thing in the hands is not
## counted: it is in the pilot's hands, and whether it will **fit** in the
## bay is what `stow` is for.
func used() -> float:
	var total: float = stores.bulk()
	for entry: Dictionary in cargo:
		total += module_bulk(entry["item"] as Resource)
	return total


## Room left, given what this ship can hold.
##
## Not `free`: `RefCounted` already has one of those, and overriding it
## with a different signature is a parse error rather than a surprise.
func room_left(capacity: float) -> float:
	return maxf(capacity - used(), 0.0)


## Puts a find in the hands. Fails when they are full, which is the whole
## of the one-slot rule.
func take(item: Resource, rarity: int = -1) -> bool:
	if carried != null or item == null:
		return false
	# A caller that knows better may still say so, but nothing has to
	# remember to: the module carries its own grade.
	if rarity >= 0 and item is ModuleData:
		(item as ModuleData).rarity = rarity
	carried = item
	return true


## Empties the hands and returns what was in them.
func release() -> Resource:
	var item: Resource = carried
	carried = null
	return item


## Moves what is in the hands into the bay. Fails, rather than overfilling,
## when there is no room: the bay is the constraint, not a suggestion.
func stow(capacity: float) -> bool:
	if carried == null or module_bulk(carried) > room_left(capacity):
		return false
	cargo.append({"item": carried, "rarity": carried_rarity()})
	carried = null
	return true


## Moves one thing out of the bay and into the hands, which must be empty.
func retrieve(index: int) -> bool:
	if carried != null or index < 0 or index >= cargo.size():
		return false
	var entry: Dictionary = cargo[index]
	cargo.remove_at(index)
	carried = entry["item"]
	return true


## Puts units aboard, as many as there is room for. Returns how many went
## in, so the caller can say what was left on the ground.
func load_units(kind: Stores.Kind, units: int, capacity: float) -> int:
	return stores.add(kind, units, room_left(capacity))


## Takes units out -- to spend, to refine, or to throw away. Returns how
## many there were.
func spend_units(kind: Stores.Kind, units: int) -> int:
	return stores.spend(kind, units)


func carrying(kind: Stores.Kind) -> int:
	return stores.count(kind)


## Turns raw ore into what it is for, as much of it as there is room for
## the result of.
##
## Returns how many units came out, and spends only the ore it actually
## used -- a partial run rather than a refusal, the same shape as loading
## into a hold with room for half.
##
## The room check will not fire as the tables stand: both ores are at
## least as bulky as what comes out of them, so refining is even at a
## yard and frees room anywhere worse (`Stores.BULK`). It is here
## because that is a property of four numbers in three files, and a
## change to any of them must not be able to quietly overfill a hold --
## so the batch walks down to the largest one whose product fits in the
## room the batch itself frees, and the test asserts the invariant
## rather than the arithmetic.
func refine(
	kind: Stores.Kind, units: int, capacity: float, place: Refinery.Place
) -> int:
	var into: int = Refinery.refines_into(kind)
	if into < 0:
		return 0
	var batch: int = mini(units, stores.count(kind))
	var room: float = room_left(capacity)
	while batch > 0:
		var trial: int = Refinery.units_from(kind, batch, place)
		if trial <= 0:
			batch -= 1
			continue
		var swell: float = (
			Stores.bulk_of(into, trial) - Stores.bulk_of(kind, batch)
		)
		if swell <= room:
			break
		batch -= 1
	if batch <= 0:
		return 0
	var made: int = Refinery.units_from(kind, batch, place)
	if made <= 0:
		return 0
	stores.spend(kind, batch)
	# Straight into `held`, not through `load_units`: the room was
	# already worked out above against the ore this run is spending, and
	# asking again would measure it against a hold that has just got
	# emptier.
	stores.held[into] = stores.count(into as Stores.Kind) + made
	return made


## Breaks what is in the hands down into spare parts. Returns how many
## were kept, zero when there was nothing to break.
##
## The arithmetic is `Refinery`'s and the transaction is here, which is
## the same split the rest of this project uses: a rate is a fact about
## the galaxy and a swap is a thing that happens to this ship.
##
## Parts that will not fit are lost rather than refused. A hold with no
## room is the pilot's problem before they pull the lever, and a scrap
## job that silently half-finished would leave a module in two states
## at once.
func scrap_carried(capacity: float, place: Refinery.Place) -> int:
	if carried == null:
		return 0
	var made: int = Refinery.parts_from(carried, place)
	carried = null
	return stores.add(Stores.Kind.SPARE_PARTS, made, room_left(capacity))


## The same for something already in the bay.
func scrap_cargo(index: int, capacity: float, place: Refinery.Place) -> int:
	if index < 0 or index >= cargo.size():
		return 0
	var entry: Dictionary = cargo[index]
	var made: int = Refinery.parts_from(entry["item"] as Resource, place)
	cargo.remove_at(index)
	return stores.add(Stores.Kind.SPARE_PARTS, made, room_left(capacity))


## Empties everything and hands back the items, for whoever is going to
## leave them lying about.
##
## **This is what dying costs**, and the shape of it is the rule. The
## hull and everything bolted into it survive, because re-earning a
## loadout on every death is a punishment a sandbox built on "explore
## fast, die often" cannot afford -- a pilot who loses their guns loses
## the next hour as well, and the hour is the game. Fuel, charges and
## energy survive for a harder reason: a death that empties the tanks
## can leave a pilot in a system they have no way out of, which is not
## a consequence but a dead end.
##
## What is left to lose is this, and losing it is enough: it is
## everything the trip was for. The items come back as entries for the
## world to scatter, so the loss is recoverable by somebody brave
## enough to fly back to the wreck through whatever made it.
##
## The counted stores are simply gone, and that is a decision rather
## than an oversight: a crate holds a thing and a spare part is a
## quantity, so a hundred and forty of them would be a hundred and
## forty crates, or a crate type that does not exist yet. The refinery
## is how they are replaced.
##
func spill() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if carried != null:
		out.append({"item": carried, "rarity": carried_rarity()})
		carried = null
	for entry: Dictionary in cargo:
		out.append(entry)
	cargo.clear()
	stores.clear()
	return out
