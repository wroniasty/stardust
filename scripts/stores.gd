class_name Stores
extends RefCounted
## What a ship carries loose, counted in units rather than in items.
##
## The hold already holds modules, each with a bulk, and this is the
## other thing that goes in it: stuff by the unit. Keeping both in the
## same volume is the whole decision the premise asks for -- a hold full
## of ore is a hold with no room for the drive you just found, and
## "what do I carry home" is the question an exploration game is made
## of (PLAN.md M5.2, last item).
##
## **Counted, not weighed.** A unit is a whole thing: twelve spare parts,
## not 12.4 of them. A pilot reading a panel should be able to say how
## many repairs that is without dividing, and every number here is one
## somebody has to hold in their head while deciding whether to turn
## back.
##
## Its own class rather than four fields on `Ship`, for two reasons.
## Raw ore arrives in several kinds (M5.2) and each one would otherwise
## be another field, another line in the save and another line in the
## bulk sum. And `ship.gd` is two and a half thousand lines already,
## which is its own argument.

## What can be carried by the unit.
##
## **Two ores, and one each.** PLAN.md M5.2 asks for few kinds and many
## decisions, and the way to get both is to make every ore the raw form
## of something the pilot already runs out of: iron ore becomes spare
## parts, which is repair, and dust ore becomes stardust, which is
## range. A third ore would need a third sink or it would be a second
## road to the same place -- and "which of these two do I need more" is
## already the question, so a third road would only dilute it.
##
## Append-only. The save keys on the enum's own values, so a reorder is
## a save that means something else.
enum Kind { SPARE_PARTS, STARDUST, IRON_ORE, DUST_ORE }

const NAMES: Array[String] = ["spare parts", "stardust", "iron ore", "dust ore"]

## How much room one unit takes, derived from what a full hold is worth
## of it rather than chosen as a number.
##
## The stock hull holds six bulk (`Hold.FINDS_PER_HOLD`), so: a hold of
## nothing but parts is fifty of them -- two hull rebuilds -- and a hold
## of nothing but stardust is a hundred and twenty-five, which is
## sixty-two fuel, or half a tank. Both are figures a pilot can hold in
## their head, which is the only reason either number is what it is.
##
## The stardust figure used to be quoted in hyperdrive charges, which
## are gone: one tank pays for the jumps and the thrust now, so the
## honest unit for stardust is fuel.
## **A full hold is worth the same in either ore**, on purpose:
## twenty-five iron ore make fifty parts, which is two hull rebuilds,
## and twenty dust ore make sixty stardust, which is two jump charges.
## The choice is which of the two you need, not which pays better -- a
## table where one ore simply paid more would have no choice in it.
##
## And an ore is **at least as bulky as what comes out of it**, which is
## not decoration: iron at 0.20 was tried first, and at a yard twenty-
## five of it refines into fifty parts worth 6.0 bulk out of 5.0 freed.
## Refining would have been blocked in the one place it works best,
## which reads as a bug however well it is explained. At 0.24 the swap
## is exactly even at a yard and frees room anywhere worse, where the
## material thrown away is what buys the space.
const BULK: Array[float] = [0.12, 0.048, 0.24, 0.30]


## Whether this is something that has to be refined before it is any
## use. Asked by the panels, which show raw rock differently, and by the
## refinery, which is the only thing that consumes it.
static func is_ore(kind: int) -> bool:
	return kind == Kind.IRON_ORE or kind == Kind.DUST_ORE


## Kind -> whole units held. Missing is zero; nothing writes a zero.
var held: Dictionary = {}


## How many of this are aboard.
func count(kind: Kind) -> int:
	return int(held.get(kind, 0))


## What all of it takes up in the hold.
func bulk() -> float:
	var total: float = 0.0
	for kind: Variant in held:
		total += bulk_of(int(kind), int(held[kind]))
	return total


## Room for this many units, in bulk.
static func bulk_of(kind: int, units: int) -> float:
	if kind < 0 or kind >= BULK.size():
		return 0.0
	return BULK[kind] * float(units)


## How many units of this would fit in `room` bulk.
static func fits_in(kind: int, room: float) -> int:
	if kind < 0 or kind >= BULK.size() or BULK[kind] <= 0.0:
		return 0
	return maxi(int(floor(room / BULK[kind])), 0)


## Puts units in, as many as fit. Returns how many went in.
##
## A partial load rather than a refusal: scooping ore into a hold with
## room for half of it should take half, not nothing. The caller is told
## the number so it can say what was left behind.
func add(kind: Kind, units: int, room: float) -> int:
	if units <= 0:
		return 0
	var taken: int = mini(units, fits_in(kind, room))
	if taken <= 0:
		return 0
	held[kind] = count(kind) + taken
	return taken


## Takes units out. Returns how many there were to take, which is less
## than asked for when the bin runs out -- the same shape as drawing on
## a tank that is nearly dry, and for the same reason: a shortfall is a
## number the caller has to decide about, not an error.
func spend(kind: Kind, units: int) -> int:
	if units <= 0:
		return 0
	var given: int = mini(units, count(kind))
	if given <= 0:
		return 0
	if given == count(kind):
		held.erase(kind)
	else:
		held[kind] = count(kind) - given
	return given


func clear() -> void:
	held.clear()


## Everything aboard, for a panel: one entry per kind that has any.
func listed() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for kind: int in range(NAMES.size()):
		if count(kind as Kind) > 0:
			out.append({
				"kind": kind,
				"name": NAMES[kind],
				"units": count(kind as Kind),
				"bulk": bulk_of(kind, count(kind as Kind)),
			})
	return out


## The save form: a plain dictionary of whole numbers.
##
## Keyed by the enum's own value rather than by name. A rename of a kind
## is then a rename; a reorder is a save that means something else, and
## the enum is append-only for exactly that reason.
func to_record() -> Dictionary:
	var out: Dictionary = {}
	for kind: Variant in held:
		out[int(kind)] = int(held[kind])
	return out


static func from_record(record: Dictionary) -> Stores:
	var stores: Stores = Stores.new()
	for kind: Variant in record:
		var units: int = int(record[kind])
		if units > 0 and int(kind) >= 0 and int(kind) < NAMES.size():
			stores.held[int(kind)] = units
	return stores


static func kind_name(kind: int) -> String:
	return NAMES[clampi(kind, 0, NAMES.size() - 1)]
