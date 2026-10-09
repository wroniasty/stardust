class_name Refinery
extends RefCounted
## Turning one thing aboard into another, at a rate that depends on
## where the ship is standing.
##
## PLAN.md M5.2 asks for exactly one number across three states --
## docked at a station, sitting on a planet, loose in space -- and not
## for a market. The point is to give a pilot a reason to put the ship
## down somewhere, not a spreadsheet: the same stardust is worth more at
## a yard than it is in the dark, and that is the whole mechanic.
##
## Static and stateless. A refinery is not a thing on the ship; it is
## what the ship can do with what it has, and which answers it gets
## depends only on where it is.

## Where the work is being done.
enum Place { SPACE, LANDED, DOCKED }

const PLACE_NAMES: Array[String] = ["in space", "landed", "docked"]

## How much of the nominal yield each place gives.
##
## A yard is the reference, so docked is 1.0 and nothing is ever better
## than it: the numbers on a card are what a station would give you, and
## everywhere else is a known discount rather than a mystery. Landed is
## most of it, because a planet is a place to work with the legs down.
## Space is a little over half, which is meant to read as "possible, and
## you would rather not".
const YIELD_AT: Array[float] = [0.55, 0.85, 1.0]

## What a module is worth as scrap, per unit of bulk, at a yard.
##
## Eight, so a common module of average size comes apart into about ten
## parts and three pieces of junk are one full hull. That ratio is the
## whole reason breaking things down exists: a hold of commons nobody
## wants should be worth carrying home, and three-for-a-repair is a
## number that makes it worth the trip without making the trip the
## point.
const PARTS_PER_BULK: float = 8.0

## What rarity adds to that, by grade.
##
## **Deliberately small.** A legendary is worth more as scrap than a
## common, but nowhere near enough to make scrapping good gear a
## strategy -- the rate stops at a little over half again while the
## item itself is worth incomparably more in a socket. Loot that is
## best melted down is loot the generator wasted its time on.
const RARITY_YIELD: Array[float] = [1.0, 1.1, 1.25, 1.4, 1.6]

## What a thing is mostly made of, which decides how much of it
## survives being taken apart.
##
## Three families rather than a row per module type, the same way the
## schematic draws three weapon silhouettes rather than six: at this
## resolution the difference between a scanner and a flight computer is
## not a difference, and a table with nine entries is nine numbers
## nobody will keep honest.
enum Family { STRUCTURE, FRAME, PRECISION }

const FAMILY_YIELD: Array[float] = [1.0, 0.85, 0.6]

## Parts to put a hull back from nothing to new, at a yard.
const HULL_PARTS: int = 25

## And to put an engine back, per unit of its bulk. Dearer than hull
## plating by the same logic that makes a precision module poor scrap:
## what comes out of a wreck is metal, and what goes into a drive is
## not.
const ENGINE_PARTS_PER_BULK: float = 10.0

## What one unit of raw ore becomes at a yard, and what of.
##
## Derived rather than chosen: see `Stores.BULK` for why both come out
## at 2.4 of their own sink per full hold.
##
## **Refining never costs room**, and that is a property of the bulks
## rather than a coincidence -- see `Stores.BULK`. At a yard iron is
## exactly even, twenty-five units of rock for fifty parts of the same
## volume; everywhere worse it frees room, because what a bad place
## does is throw material away and the material it throws is the
## volume. Dust frees room everywhere.
##
## So a refining run is never refused for space, and a pilot who needs
## room right now can get it by refining badly on purpose. That is a
## decision rather than a punishment, which is the whole shape this
## mechanic is supposed to have.
const ORE_YIELD: Dictionary = {
	Stores.Kind.IRON_ORE: {"into": Stores.Kind.SPARE_PARTS, "each": 2.0},
	Stores.Kind.DUST_ORE: {"into": Stores.Kind.STARDUST, "each": 3.0},
}


## What this ore refines into, or -1 if it is not ore.
static func refines_into(kind: int) -> int:
	if not ORE_YIELD.has(kind):
		return -1
	return int((ORE_YIELD[kind] as Dictionary)["into"])


## How many units this much ore yields here, in whole units.
##
## Floored once over the whole batch rather than per unit, so refining
## thirty at a time is not quietly worse than refining thirty one at a
## time -- which is the kind of difference that teaches a pilot to click
## thirty times.
static func units_from(kind: int, units: int, place: Place) -> int:
	if units <= 0 or not ORE_YIELD.has(kind):
		return 0
	var each: float = float((ORE_YIELD[kind] as Dictionary)["each"])
	return int(floor(each * float(units) * efficiency(place)))


## Stardust for one hyperdrive charge, at a yard.
##
## Thirty, so a full hold of nothing but stardust is eight charges and
## the stock drive's four is a hundred and twenty units. Both are
## numbers a pilot can do in their head while deciding whether this
## system is worth one more look.
const STARDUST_PER_CHARGE: int = 30


## Where this ship is, for the purposes of making things.
##
## Off the flight mode, which already has exactly these three states, so
## nothing new has to be tracked and the two cannot disagree about
## whether the legs are down.
static func place_of(ship: Ship) -> Place:
	if ship == null or not is_instance_valid(ship):
		return Place.SPACE
	match ship.flight_mode:
		Ship.FlightMode.DOCKED:
			return Place.DOCKED
		Ship.FlightMode.LANDED:
			return Place.LANDED
		_:
			return Place.SPACE


static func efficiency(place: Place) -> float:
	return YIELD_AT[clampi(int(place), 0, YIELD_AT.size() - 1)]


## What one charge costs here, in stardust. Rounded up, because a charge
## is a whole thing and half a charge is not a thing at all.
static func stardust_for_charge(place: Place) -> int:
	return int(ceil(float(STARDUST_PER_CHARGE) / efficiency(place)))


## The most charges this much stardust could make here.
static func charges_from(stardust: int, place: Place) -> int:
	var each: int = stardust_for_charge(place)
	return 0 if each <= 0 else stardust / each


## Which family a module belongs to.
##
## By script class, because that is what the item already is. The
## alternative -- a field on `ModuleData` set in every `.tres` -- is a
## number somebody has to remember to set on the next base, and the one
## they forget will quietly be worth zero.
static func family_of(item: Resource) -> Family:
	if item is EngineData or item is TankData or item is GearData:
		return Family.STRUCTURE
	if item is WeaponData:
		return Family.FRAME
	return Family.PRECISION


## What this comes apart into, in whole spare parts.
##
## Bulk is the headline and the other two are adjustments to it, which
## is the order the mockup asks for and also the only one that makes
## sense: scrap is material, and bulk is how much material there is.
static func parts_from(item: Resource, place: Place) -> int:
	var module: ModuleData = item as ModuleData
	if module == null:
		return 0
	var grade: int = clampi(module.rarity, 0, RARITY_YIELD.size() - 1)
	return int(floor(
		PARTS_PER_BULK
		* maxf(module.bulk, 0.0)
		* RARITY_YIELD[grade]
		* FAMILY_YIELD[int(family_of(item))]
		* efficiency(place)
	))


## Parts to mend this much hull, where 1.0 is all of it.
##
## Divided by the efficiency rather than multiplied, because this is a
## cost and the others are yields: a bad place makes you pay more for
## the same result, which is the same sentence as getting less for the
## same input.
static func parts_for_hull(missing: float, place: Place) -> int:
	if missing <= 0.0:
		return 0
	return maxi(int(ceil(
		float(HULL_PARTS) * clampf(missing, 0.0, 1.0) / efficiency(place)
	)), 1)


## Parts to mend this much of an engine of this bulk.
static func parts_for_engine(bulk: float, missing: float, place: Place) -> int:
	if missing <= 0.0 or bulk <= 0.0:
		return 0
	return maxi(int(ceil(
		ENGINE_PARTS_PER_BULK * bulk * clampf(missing, 0.0, 1.0) / efficiency(place)
	)), 1)


static func family_name(family: int) -> String:
	return ["structure", "frame", "precision"][clampi(family, 0, 2)]


static func place_name(place: int) -> String:
	return PLACE_NAMES[clampi(place, 0, PLACE_NAMES.size() - 1)]
