class_name Shipwright
extends RefCounted
## Putting a ship back together: by hand with spare parts, or by sitting at
## a dock and waiting.
##
## The second piece off `ship.gd`, after `Hold`. Static and stateless, like
## `Refinery` and `Damage`, because a repair is not a thing a ship **has**
## -- it is a thing done to one, and what it costs depends on where the
## ship is standing rather than on anything it is carrying around.
##
## ## Three ways a ship gets mended, and they are three on purpose
##
## - **Paid, by hand** (`mend_hull`, `mend_engine`): spare parts out of the
##   hold, at a rate that depends on where the ship is. Partial, like every
##   other shortfall in this game -- ten parts against a bill of twenty-five
##   buy two fifths of the repair rather than nothing.
## - **Free, over time** (`service`): what a dock does while the pilot sits
##   there. The wait is the price.
## - **Free, at once** (`repair_hull`, `repair_engines`): what a developer
##   key does, and what a repair bay will do when there is one. A cost and
##   a debug key are two different things and always were.
##
## Everything here takes the ship, and that is the honest shape: mending
## reaches into the hull, the engines, the pool and the tank. Hiding that
## behind a wrapper that owned a back-reference would be the same coupling
## with a longer name.

## How fast a dock puts things right, per second docked.
##
## Over time rather than on arrival, so docking is a pause in the flight
## and not a button: a wrecked hull takes the best part of ten seconds to
## put right, which is long enough to be a decision about whether you can
## afford to sit still and short enough that nobody waits for it twice.
##
## Energy fills faster than the generator manages on its own, because that
## is what being plugged into something bigger than you means.
const DOCK_HULL_RATE: float = 0.12
const DOCK_ENGINE_RATE: float = 0.18
const DOCK_ENERGY_RATE: float = 3.0

## And of the tank, per second docked.
##
## Slower than the energy pool on purpose. Energy is combat's clock and
## refills itself anywhere; fuel is range's clock and only comes from a
## dock, so sitting still for it is the price of having gone a long way
## (IDEAS.md section 14). Still generous -- the wait is meant to be felt,
## not endured.
const DOCK_FUEL_RATE: float = 0.12


## Puts the hull back together with spare parts. Returns how many were
## spent.
##
## Partial, like every other shortfall in this game: ten parts against
## a bill of twenty-five buy two fifths of the repair rather than
## nothing.
static func mend_hull(ship: Ship) -> int:
	if ship == null or not is_instance_valid(ship):
		return 0
	var missing: float = 1.0 - ship.hull_integrity
	if missing <= 0.0001:
		return 0
	var place: Refinery.Place = Refinery.place_of(ship)
	var bill: int = Refinery.parts_for_hull(missing, place)
	var paid: int = ship.spend_units(Stores.Kind.SPARE_PARTS, bill)
	if paid <= 0:
		return 0
	ship.hull_integrity = clampf(
		ship.hull_integrity + missing * float(paid) / float(bill), 0.0, 1.0
	)
	ship.hull_changed.emit(ship.hull_integrity)
	return paid


## And one engine, which costs by its bulk: what goes into a drive is
## not the plating that comes out of a wreck.
static func mend_engine(ship: Ship, engine: EngineInstance) -> int:
	if ship == null or not is_instance_valid(ship):
		return 0
	if engine == null or engine.data == null or engine.health >= 0.9999:
		return 0
	var missing: float = 1.0 - engine.health
	var place: Refinery.Place = Refinery.place_of(ship)
	var bill: int = Refinery.parts_for_engine(engine.data.bulk, missing, place)
	var paid: int = ship.spend_units(Stores.Kind.SPARE_PARTS, bill)
	if paid <= 0:
		return 0
	engine.health = clampf(
		engine.health + missing * float(paid) / float(bill), 0.0, 1.0
	)
	return paid


## One tick of sitting at a dock: hull, heat, engines, pool and tank.
static func service(ship: Ship, delta: float) -> void:
	if ship == null or not is_instance_valid(ship):
		return
	if ship.hull_integrity < 1.0:
		ship.hull_integrity = minf(
			ship.hull_integrity + DOCK_HULL_RATE * delta, 1.0
		)
		ship.hull_changed.emit(ship.hull_integrity)
	ship.hull_heat = maxf(ship.hull_heat - DOCK_HULL_RATE * delta, 0.0)
	for engine: EngineInstance in ship.engines:
		engine.health = minf(engine.health + DOCK_ENGINE_RATE * delta, 1.0)
	var pool: float = ship.energy_capacity()
	ship.energy = minf(ship.energy + pool * DOCK_ENERGY_RATE * delta, pool)
	# And the tank, which is what a dock is actually for. M3 left this
	# line out on purpose -- "the dock tops up energy for now, and when
	# fuel exists this is where it gets bought" -- because there was no
	# fuel to put in. There is now.
	ship.add_fuel(ship.fuel_capacity() * DOCK_FUEL_RATE * delta)


## True while everything a dock can mend is mended.
static func fully_serviced(ship: Ship) -> bool:
	if ship == null or not is_instance_valid(ship):
		return false
	if ship.hull_integrity < 1.0 or ship.energy < ship.energy_capacity() - 0.01:
		return false
	if ship.fuel < ship.fuel_capacity() - 0.01:
		return false
	for engine: EngineInstance in ship.engines:
		if engine.health < 1.0:
			return false
	return true


## The free, total repair: what the sandbox's key does and what a repair
## bay will do.
##
## Separate from `respawn`, which also moves the ship and empties the
## hold. The sandbox wants the one without the other -- carry on from
## where you are, undamaged.
static func repair_hull(ship: Ship) -> void:
	if ship == null or not is_instance_valid(ship):
		return
	ship.hull_integrity = 1.0
	ship.hull_heat = 0.0
	ship.accumulated_damage = 0.0
	ship.last_landing_rejection = ""


static func repair_engines(ship: Ship) -> void:
	if ship == null or not is_instance_valid(ship):
		return
	for engine: EngineInstance in ship.engines:
		engine.health = 1.0
