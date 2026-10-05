class_name UiWarning
extends RefCounted
## What is wrong with the ship, in the order it will kill you.
##
## One band in one place, rather than a panel that turns red all over.
## That is not taste: the widget gallery's alarm sheet put four red rows
## on screen at once and the whole panel read as a single
## undifferentiated warning, which is UI_STYLE section 3 seen from the
## wrong side -- warnings pay for their attention by being **absent**,
## and a colour that is everywhere has stopped paying.
##
## So the rows keep their own grading, because a number shading from
## green through amber is a *reading* and the pilot is meant to watch it
## move. The pulse belongs to exactly one place that names the worst
## thing in two or three letters. A pilot learns where to look once and
## never reads the panel to find out that something is wrong -- which is
## what "readable without reading" means.
##
## The order is by **how soon it kills**, not by how bad it sounds. An
## empty pool is annoying and a hull at a fifth is fatal, so they are
## not close together on this list even though both are "a bar near
## zero".

enum Level { NONE, CAUTION, ALARM }

## Hull: amber below the first, red below the second.
const HULL_CAUTION: float = 0.6
const HULL_ALARM: float = 0.25

## Heat, as a share of the point where the hull starts taking damage.
## Amber before it, red past it -- past it is not a warning any more,
## it is a thing already happening.
const HEAT_CAUTION: float = 0.8

## Fuel, as a share of the tank. Below the second there is not enough
## left to cross anywhere, which out between stars is the same as none.
const FUEL_CAUTION: float = 0.25
const FUEL_ALARM: float = 0.05


## The one warning worth a band, or an empty dictionary when nothing is
## wrong. `{"says": String, "level": Level}`.
##
## `well` may be null: out in the open there is no orbit to decay and no
## ground to meet, which is most of what this looks at.
static func worst(ship: Ship, well: GravityWell) -> Dictionary:
	if ship == null or not is_instance_valid(ship):
		return {}

	# Hull first and heat second, because those are the two that end the
	# flight rather than spoil it. Heat comes after hull only because a
	# hull already gone is not a warning about anything.
	var hull: float = clampf(ship.hull_integrity, 0.0, 1.0)
	if hull <= HULL_ALARM:
		return {"says": "HULL", "level": Level.ALARM}

	if ship.hull_heat >= Ship.BURN_HEAT:
		return {"says": "BURN", "level": Level.ALARM}

	# A decaying orbit is the slowest of the fatal ones and the easiest
	# to miss, which is exactly why it earns a band: nothing about the
	# view changes while it happens.
	if well != null and is_instance_valid(well):
		var state: GravityWell.OrbitState = well.orbit_state(
			ship.global_position, ship.linear_velocity
		)
		if state == GravityWell.OrbitState.DECAYING:
			return {"says": "DECAY", "level": Level.ALARM}

	var tank: float = ship.fuel_capacity()
	if tank > 0.0 and ship.fuel / tank <= FUEL_ALARM:
		return {"says": "FUEL", "level": Level.ALARM}

	if hull <= HULL_CAUTION:
		return {"says": "HULL", "level": Level.CAUTION}

	if ship.hull_heat >= Ship.BURN_HEAT * HEAT_CAUTION:
		return {"says": "HEAT", "level": Level.CAUTION}

	if tank > 0.0 and ship.fuel / tank <= FUEL_CAUTION:
		return {"says": "FUEL", "level": Level.CAUTION}

	return {}
