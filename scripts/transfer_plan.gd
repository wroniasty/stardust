class_name TransferPlan
extends RefCounted
## Whether this ship is going to arrive at the pin, and when to start stopping.
##
## The crossing between two planets is the one part of flying this game
## that has no instrument at all. In a well there is an orbit to read,
## a tape to watch and ground to judge; out in the open there is a
## number that goes down slowly and nothing that says whether it will
## reach zero. A pilot can be forty degrees off a two hundred thousand
## pixel crossing for a minute and a half without anything on screen
## disagreeing.
##
## So this answers four questions, in the order they come up: am I going
## the right way, am I going straight at it, how close will I actually
## pass, and -- the one that decides whether the trip works -- have I
## left it too late to stop.
##
## **A snapshot, taken once a frame**, like `ConfigurationReport`: the
## ring, the figures under the tape and the warning band all have to
## agree about the same instant, and three readers each doing their own
## arithmetic is three answers that drift apart in the frame a burn
## starts.
##
## **Straight lines.** The pin is a point in system pixels and the ship
## out here is in the star's patched well, so the true path is a conic
## and this is a chord of it. That is deliberate and it is the same
## decision the rest of the game makes (`IDEAS.md`: arcade before
## correct): a pilot crossing between orbits burns, coasts and burns,
## and over the coast the star bends the track by a fraction of a degree
## a minute. What the numbers are for is "turn now" and "start braking
## now", and both of those survive the approximation. The one that does
## not is a grazing pass at the far end of the system, which is why the
## closest approach is a **figure the pilot reads** rather than a promise
## the autopilot keeps.

## What the crossing looks like, worst news first.
##
## Ordered the way the band reads them, so `verdict` can be compared.
## `OVERSHOOT` is on-course and too fast rather than a fifth state: the
## nose is where it should be, and what is wrong is the speed.
enum Verdict { NONE, ON_COURSE, OFF_COURSE, AWAY, OVERSHOOT }

## Inside this, the crossing is over and the instrument goes away.
##
## **Five hundred pixels: close enough to see the thing.** The first
## figure here was ten thousand, on the argument that the scanner's own
## marker contact takes the job over and that ten thousand is four
## planet radii, so whatever is being aimed at is a disc rather than a
## point. The pilot flew it and disagreed, and they are right: a pin is
## a place, not a planet, and most of them are in open space with
## nothing to see -- so the instrument switched itself off a long way
## out and left the last stretch, the one where the braking burn
## actually happens, with nothing on it. At five hundred the pin is
## inside the same screen as the ship and the ring has nothing left to
## say.
const ARRIVED: float = 500.0

## How far off the line still counts as straight at it, in degrees.
##
## Five, because the figures past this point stop being about the same
## manoeuvre: inside it the closest approach is a few per cent of the
## range and the braking burn is the whole job, and outside it the
## closest approach is most of the range and the job is turning. The
## cone is drawn on the ring, so this number is also a thing the pilot
## can see rather than a rule they have to infer.
const CONE_DEGREES: float = 5.0

## Below this there is no course to be right or wrong about, in px/s.
##
## A ship drifting at two pixels a second is not going the wrong way, it
## is not going. The same figure the heading hold uses to decide that a
## direction of travel has stopped being a direction, for the same
## reason.
const MIN_SPEED: float = Ship.HEADING_MIN_SPEED

## Is there a pin at all, and is it still far enough away to be worth
## instruments.
var marked: bool = false
var shows: bool = false

## Range to the pin in pixels, and the world angle it lies at.
var distance: float = 0.0
var bearing: float = 0.0

## Speed, and the part of it that is closing the range. Negative closing
## is opening it.
var speed: float = 0.0
var closing: float = 0.0

## Angle between the way the ship is going and the way the pin is, in
## radians. Zero when there is no course.
var drift: float = 0.0

## How close the ship will pass if nothing changes, in pixels, and how
## long until it does.
var approach: float = 0.0
var approach_in: float = 0.0

## Seconds until the braking burn has to start, negative once it is late.
## `INF` when the ship is not closing at all.
var burn_in: float = INF

## What the ship can brake at, in px/s^2.
var braking: float = 0.0

var verdict: int = Verdict.NONE


## The crossing as it stands, or an empty plan when there is no pin.
static func of(ship: Ship) -> TransferPlan:
	var plan: TransferPlan = TransferPlan.new()
	if ship == null or not is_instance_valid(ship) or not NavMarker.is_marked():
		return plan
	plan.marked = true

	var to_pin: Vector2 = NavMarker.marked - ship.global_position
	plan.distance = to_pin.length()
	plan.bearing = to_pin.angle()
	plan.speed = ship.linear_velocity.length()
	plan.shows = plan.distance > ARRIVED
	if not plan.shows or plan.distance <= 0.0:
		return plan

	var line: Vector2 = to_pin / plan.distance
	plan.closing = ship.linear_velocity.dot(line)
	if plan.speed < MIN_SPEED:
		# Stationary: the range and the bearing are honest, and every
		# other figure here is a division by a speed that is not there.
		return plan
	plan.drift = absf(ship.linear_velocity.angle_to(to_pin))

	# Where the straight line passes, and when. The along-track range
	# and the closing speed are the same cosine, so one angle does both:
	# `|to_pin| cos d` is how far there is to run and `|v| cos d` is how
	# fast it is being run off.
	var along: float = plan.distance * cos(plan.drift)
	plan.approach = plan.distance * sin(plan.drift)
	plan.approach_in = maxf(along, 0.0) / plan.speed
	plan.braking = _braking_of(ship)

	if plan.closing <= 0.0:
		# Receding: the closest approach already happened, which is here.
		plan.approach = plan.distance
		plan.approach_in = 0.0
		plan.verdict = Verdict.AWAY
		return plan

	# When to turn round. The burn has to kill the closing speed over
	# the range that is left, so it starts where the braking distance
	# equals the range -- and `burn_in` is how long the coast before it
	# lasts. Killing the closing component rather than the whole
	# velocity is exact on the line and 0.4% out at the edge of the
	# cone, which is a tenth of what ignoring the turn costs.
	if plan.braking > 0.0:
		plan.burn_in = (
			(along - plan.closing * plan.closing / (2.0 * plan.braking)) / plan.closing
		)
	else:
		# Nothing to brake with. Not "late" -- never.
		plan.burn_in = -INF

	if plan.drift > deg_to_rad(CONE_DEGREES):
		plan.verdict = Verdict.OFF_COURSE
		return plan
	plan.verdict = Verdict.OVERSHOOT if plan.burn_in < 0.0 else Verdict.ON_COURSE
	return plan


## Whether the figures are worth printing: the ship is pointed at the
## pin, so the closest approach and the burn are about this manoeuvre
## rather than about a turn that has not happened yet.
func solved() -> bool:
	return verdict == Verdict.ON_COURSE or verdict == Verdict.OVERSHOOT


## What the ship can brake at, in px/s^2.
##
## Out in the open a ship brakes by swinging the nose onto retrograde
## and burning with the main drive, so the figure is the **forward**
## authority -- see `Ship.brakes_by_turning`, which is also why this
## asks it rather than assuming. A hull that cannot turn brakes with
## whatever opposes the drift, and the honest stand-in for that is the
## retro group.
##
## The turn itself is not counted. It takes a second or two and the
## burns out here run for tens of seconds, so it is inside the slack a
## pilot leaves anyway -- and a figure that pretended to know how long
## the swing takes would have to know which way the ship is pointing
## now, which changes while they read it.
static func _braking_of(ship: Ship) -> float:
	if ship.control == null or ship.mass <= 0.0:
		return 0.0
	var command: ShipControl.Command = (
		ShipControl.Command.FORWARD if ship.brakes_by_turning()
		else ShipControl.Command.BACK
	)
	return ship.control.authority_of(command) / ship.mass
