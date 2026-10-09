class_name Corona
extends RefCounted
## Stardust out of a star's wind, and where it can be had.
##
## **Not by flying through the star.** `star.gd` records that as a
## decision rather than a limitation: a ship heading into a star dies of
## heat a few thousand pixels before anything touches, which is why the
## star has no collision shape at all. So "collect stardust by passing
## through the star" would need either a module that moves
## `Ship.BURN_HEAT` -- a module that rewrites the heat model for one
## errand -- or the collecting moved outside the radius that kills.
## Premise point 4 picks the second, and this is it.
##
## ## The stream is thickest where it is worst to sit
##
## The band starts at the burn radius -- the distance the ship's own
## heating and cooling rates make survivable, `Ship.burn_radius` -- and
## thins to nothing well outside it. Richest at the inner edge, so the
## pilot is choosing between a faster scoop and a hull that is cooking,
## and the cost is a model that already exists and already has a bar on
## the HUD. Nothing here knows about heat; it only arranges for the
## pilot to want to be where heat is.
##
## Pure data, like `Deposits` and `Garrison`: it answers how much is in
## the wind at a distance, and something else decides whether to go
## there.

## Where the stream starts and ends, as multiples of the ship's own burn
## radius.
##
## The inner edge **is** the burn radius rather than just inside it, so
## the best scoop is at the exact distance the heat model calls the
## limit. A band that started inside it would be a band whose best part
## is unreachable, and one that started well outside would make the heat
## irrelevant -- in both cases the choice the mechanic is for stops
## existing.
const FROM: float = 1.0
const TO: float = 2.6

## Units a second at the inner edge with a full scoop.
##
## Ten seconds a jump charge (`Refinery.STARDUST_PER_CHARGE` is thirty),
## and about forty to fill the hold. Both are numbers a pilot can decide
## about while watching the heat bar climb, which is the only clock that
## matters here.
const UNITS_PER_SECOND: float = 3.0


## How thick the wind is here, 1.0 at the inner edge and 0.0 outside the
## band. Linear, because this is an arcade game and the pilot has to be
## able to predict it from the altitude alone.
static func density_at(distance: float, burn_radius: float) -> float:
	if burn_radius <= 0.0:
		return 0.0
	var inner: float = burn_radius * FROM
	var outer: float = burn_radius * TO
	if distance >= outer:
		return 0.0
	if distance <= inner:
		# Inside the burn radius it is still 1.0 rather than more. There
		# is nothing to buy by going further in, which is the point: the
		# reward for flying into a star should be dying, not a bonus.
		return 1.0
	return 1.0 - (distance - inner) / (outer - inner)


## And what that is worth to a ship with this much scoop, in units a
## second. Zero without a scoop: the wind is there for everybody and
## only a fitted mod can hold any of it.
static func units_per_second(scoop: float, distance: float, burn_radius: float) -> float:
	if scoop <= 0.0:
		return 0.0
	return UNITS_PER_SECOND * scoop * density_at(distance, burn_radius)


## Where a pilot would park to scoop, given a star. For the readout, and
## so the one place that knows the band's shape is this one.
static func best_radius(burn_radius: float) -> float:
	return burn_radius * FROM
