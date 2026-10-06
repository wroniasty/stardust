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


static func place_name(place: int) -> String:
	return PLACE_NAMES[clampi(place, 0, PLACE_NAMES.size() - 1)]
