class_name JumpController
extends Node
## Sekwencja skoku: Idle, Charging, Transit, Arrival.
##
## IDEAS.md section 10, as a machine with four states and one rule per
## edge between them. It owns the decision and the clock and nothing
## else: it never moves the ship, never frees a system and never draws
## anything. When the old system has to go it says so, and the world --
## which is the only thing that knows what a system is made of -- does
## it.
##
## That split is the reason this can be tested at all. A jump is the one
## action in the game that destroys the scene it is happening in, and a
## controller that did the destroying would be a controller no headless
## test could run twice.

enum Phase {
	## Nothing happening. The only state the pilot can steer in.
	IDLE,
	## Spooling. Interruptible by letting go or by being hit, and burning
	## fuel the whole time -- which is what makes a cancelled charge cost
	## something rather than being a free look.
	CHARGING,
	## Gone. The old system is taken down and the new one brought up
	## halfway through, under the effect, where nobody can see the seam.
	TRANSIT,
	## Arrived, and the effect fading. Still a state rather than an
	## instant, because the pilot needs a moment to read where they are
	## before the controls mean anything again.
	ARRIVAL,
}

## How close to dead ahead a system has to be to be the one you are
## aiming at. IDEAS.md asks for fifteen degrees: wide enough to hold
## while turning, narrow enough that two candidates rarely tie.
const CONE: float = 0.26179939

## How long a press may last and still count as a tap.
##
## The drive is armed and disarmed by tapping the key and charged by
## holding it, which is one key doing two jobs and needs one number to
## tell them apart. A fifth of a second: longer than anybody taps,
## shorter than anybody notices waiting before a charge that takes
## seconds anyway.
const ARM_TAP: float = 0.22

## How long the crossing lasts, and where in it the worlds change over.
##
## The swap is at the middle rather than at either end so that the effect
## is already covering the screen when the old system goes and has not
## begun to clear when the new one is up. A seam at the start would be a
## system vanishing in front of the pilot; one at the end would be a
## system appearing.
const TRANSIT_SECONDS: float = 1.8
const SWAP_AT: float = 0.5

## How long the arrival reads for, and how much of the approach speed
## survives it. Not zero: a jump that parked the ship would make the
## heading it preserves meaningless.
const ARRIVAL_SECONDS: float = 0.7
const SPEED_KEPT: float = 0.25

## Where in a drive's range the strain starts counting, as a fraction.
##
## IDEAS.md section 10 asks for risk at the edge of the reach as well as
## from a shortfall. Only the last seventh of it: a drive asked for
## nine tenths of what it can do is being used, not abused, and a model
## that charged for every jump would make range a lie.
const STRAIN_FROM: float = 0.85

## How far along the lane a failed jump drops the ship.
const FELL_SHORT: Vector2 = Vector2(0.35, 0.80)

## The drive was switched on or off. The HUD shows destinations only
## while it is on, which is what makes arming a thing the pilot does
## rather than a state they are in by default.
signal armed_changed(armed: bool)

## The drive spooled, spent its charge and had nowhere to put the ship.
##
## Its own signal rather than a `refused`, because the two are different
## events: a refusal happens instead of a jump and costs nothing, and
## this happens **as** a jump and costs the whole charge. Carries what
## was in the way, so the cough can name it.
signal balked(blocker: SystemBody)

signal phase_changed(phase: Phase)

## Why a jump would not start. Carries the reason, because "nothing
## happened" is the one thing an instrument must never say.
signal refused(reason: String)

## The moment the worlds change over. The listener frees the old system,
## brings up the new one and puts the ship at `at` facing `heading`.
signal crossed(from_index: int, to_index: int, at: Vector2, heading: float)

signal arrived(index: int)

## A jump that did not arrive. Carries where it fell out, so the thing
## that builds worlds can make the sector it fell into.
signal misjumped(toward: int, adrift_at: Vector2)

var phase: Phase = Phase.IDLE

## Set from the input map when this is the player's; written directly by
## a test. Split for the usual reason -- a machine that can only be
## driven through a keyboard is a machine with no tests.
var use_player_input: bool = true
var holding: bool = false

## Whether the drive is lit and looking for somewhere to go.
##
## **Off by default, and off again after every arrival.** A jump is one
## trip; a pilot who has just come out of one should be looking at where
## they are rather than at six headings out of it, and re-arming is the
## moment they decide to go on.
var armed: bool = false

## How long the key has been down, for telling a tap from a hold.
var _held_for: float = 0.0

var _ship: Ship = null
var _system: StarSystem = null
var _map: GalaxyMap = null

## Where the ship is in the galaxy, in light years, and which system
## that is -- or -1 for the gap between two of them.
##
## The position is the real address and the index is a convenience.
## That is the other way round from how this started, and it had to
## change the moment a misjump could put a pilot somewhere that is not
## on the map: a scanner still works out there, and it works off a
## point, not off an entry in a list.
var _at: Vector2 = Vector2.ZERO
var _here: int = 0
var _galaxy: Node = null

## The roll. Seeded from the clock in the game and set by hand in a
## test, because a risk nobody can reproduce is a risk nobody can check.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

## The system clock the bodies were placed against. See `bind`. Not
## `_clock`, which is this machine's own transit timer -- two different
## clocks, and the one that got the plain name was here first.
var _visit_time: float = 0.0

## What the charge is for, and what it costs. Latched when the charge
## starts: the nose is how you pick a target, not how you keep one, and
## a jump that cancelled because the ship drifted three degrees would be
## a jump nobody could complete while turning.
var _target: int = -1
var _bill: float = 0.0
var _spent: float = 0.0

## Whether this jump is running on a hyperdrive charge rather than on
## engine fuel. Decided when the spool starts and kept, so that a tank
## filled mid-charge cannot quietly change what the jump costs.
var _on_charge: bool = false

## Latched with the target, for the same reason: the pilot committed to
## a gamble with known odds, and odds that moved while the drive spooled
## would be odds nobody agreed to.
var _risk: float = 0.0

## Whether the last crossing came out where it was aimed.
var _went_astray: bool = false
var _charge: float = 0.0
var _clock: float = 0.0
var _swapped: bool = false


func _init() -> void:
	_rng.randomize()


## Where the ship is now. `here` is -1 out in the gap, and `at` is then
## the only thing that says where that gap is.
func bind(
	ship: Ship,
	system: StarSystem,
	map: GalaxyMap,
	here: int,
	galaxy: Node = null,
	at: Vector2 = Vector2.INF,
	clock: float = 0.0,
) -> void:
	if _ship != null and is_instance_valid(_ship) and _ship.hull_impact.is_connected(_on_hit):
		_ship.hull_impact.disconnect(_on_hit)
	_ship = ship
	_system = system
	_map = map
	_here = here
	_galaxy = galaxy
	# The moment the bodies in this scene were placed at, frozen on
	# arrival (`StreamingManager.visit_time`). Handed in rather than read,
	# so the clearance rules ask about the planets the pilot can see
	# rather than about where they would be if the clock had run on.
	_visit_time = clock
	if at != Vector2.INF:
		_at = at
	elif map != null and here >= 0 and here < map.count():
		_at = map.positions[here]
	if _ship != null:
		_ship.hull_impact.connect(_on_hit)


## Which system the nose is pointing at, or -1.
##
## In the world's frame, not the screen's. The galaxy and the system are
## the same plane, so "pointing at it" is a question about two headings
## and has nothing to do with where the camera happens to be looking --
## the first version of this asked through the canvas transform, which
## gave the right answer for the wrong reason and would have stopped
## doing so the moment anything scaled the view unevenly.
##
## Nearest to dead ahead inside the cone, not the first one found: a
## target that changed while the pilot held still would not be one.
func aimed_at() -> int:
	if _ship == null or not is_instance_valid(_ship) or _map == null:
		return -1
	var eyes: ScannerData = _ship.scanner()
	if eyes == null:
		return -1
	var nose: Vector2 = Vector2.UP.rotated(_ship.global_rotation)
	var home: Vector2 = _at
	var best: int = -1
	var closest: float = cos(CONE)
	for index: int in _map.within(home, eyes.reach):
		if index == _here:
			continue
		var heading: Vector2 = (_map.positions[index] - home).normalized()
		var alignment: float = nose.dot(heading)
		if alignment >= closest:
			closest = alignment
			best = index
	return best


## Why a jump cannot start right now, or "" when it can.
##
## One function, so the HUD, the refusal and the machine itself cannot
## disagree about what is stopping the pilot.
func blocked_by(index: int) -> String:
	if _ship == null or not is_instance_valid(_ship):
		return "no ship"
	if index < 0 or _map == null or index >= _map.count() or index == _here:
		return "no target"
	var holding: SystemBody = (
		null if _system == null else _system.holding(_ship.global_position, _visit_time)
	)
	if holding != null:
		return "too close to %s" % holding.display_name
	var drive: JumpDriveData = _ship.jump_drive()
	if drive == null:
		return "no drive"
	var away: float = _at.distance_to(_map.positions[index])
	if not drive.can_cross(away):
		return "out of range"
	if _ship.charges <= 0 and _ship.fuel <= 0.0:
		return "no charge, no fuel"
	return ""


## What the lane to a destination runs into, or null when it is clear.
##
## **Not part of `blocked_by`**, and that is the decision rather than an
## oversight. Everything `blocked_by` lists stops the drive from
## lighting at all: no target, no drive, nothing in the tank, a planet
## filling the sky. A fouled lane is different -- the drive will light,
## spool and spend the charge, and then fail, because the thing it needed
## was somewhere to put the ship and there was a planet there. The HUD
## says so first, loudly; a pilot who holds anyway gets the cough.
func lane_blocked(index: int) -> SystemBody:
	if _ship == null or not is_instance_valid(_ship) or _system == null:
		return null
	if _map == null or index < 0 or index >= _map.count() or index == _here:
		return null
	var toward: Vector2 = _map.positions[index] - _at
	return _system.lane_blocked(_ship.global_position, toward, _visit_time)


## What a jump to `index` would cost, in fuel.
func bill_for(index: int) -> float:
	var drive: JumpDriveData = _ship.jump_drive() if _ship != null else null
	if drive == null or _map == null or index < 0 or index >= _map.count():
		return 0.0
	return drive.fuel_for(_at.distance_to(_map.positions[index]), _ship.mass)


## How likely a jump to `index` is to fail, 0..1.
##
## Two ways to court it and the worse of the two counts, rather than the
## sum: a pilot who is both short of fuel and at the edge of the reach
## is in one kind of trouble, not two, and adding the figures would make
## the edge of the map unflyable for a reason nobody could read off the
## HUD.
##
## A shortfall is not a refusal. IDEAS.md section 10 is explicit about
## it: the missing fraction is the chance of coming out somewhere else,
## which is what makes "I have almost enough" a decision instead of a
## wall.
##
## **A charge takes the shortfall out of the question entirely.** That
## is what a charge is for: it buys a clean jump, and the only thing
## left to worry about is how far. With an empty magazine the drive
## improvises on engine fuel and the old rule applies unchanged -- which
## is how the split keeps its promise that a dry hold is a problem
## rather than a stop.
func misjump_risk(index: int) -> float:
	if _ship == null or not is_instance_valid(_ship) or _map == null:
		return 0.0
	var drive: JumpDriveData = _ship.jump_drive()
	if drive == null or index < 0 or index >= _map.count():
		return 0.0
	var fare: float = bill_for(index)
	var shortfall: float = 0.0
	if _ship.charges <= 0:
		shortfall = (
			0.0 if fare <= 0.0 else clampf(1.0 - _ship.fuel / fare, 0.0, 1.0)
		)
	var away: float = _at.distance_to(_map.positions[index])
	var strain: float = clampf(
		(away / maxf(drive.reach, 0.001) - STRAIN_FROM) / maxf(1.0 - STRAIN_FROM, 0.001),
		0.0,
		1.0,
	)
	return maxf(shortfall, strain)


## Where a jump that failed puts the ship, in galaxy coordinates.
##
## Part of the way along the lane it was trying to fly, which is the
## only honest answer: the drive did work, it stopped early. Short
## enough that the sector is nearer the departure than the destination,
## because a misjump that dropped you most of the way there would be a
## cheaper jump rather than a failed one.
func adrift_point(index: int, share: float) -> Vector2:
	if _map == null or index < 0 or index >= _map.count():
		return _at
	return _at.lerp(_map.positions[index], clampf(share, 0.0, 1.0))


## Where a ship arriving at `index` comes out, in that system's pixels.
##
## On the near side, facing in: `outer_radius * (source - target)`, which
## is IDEAS.md section 10's own formula. The point of it is that the two
## coordinate spaces line up, so a pilot who flew north-east to leave
## arrives on the target's south-west edge with the star ahead -- the
## crossing reads as one flight rather than as a teleport.
func arrival_point(index: int) -> Vector2:
	if _map == null or index < 0 or index >= _map.count():
		return Vector2.ZERO
	var out: Vector2 = (_at - _map.positions[index]).normalized()
	if out.is_zero_approx():
		out = Vector2.UP
	var target: StarSystem = _system_at(index)
	var reach: float = target.outer_radius() if target != null else 100000.0
	return out * reach


## And the same for a sector, which has no star to come in towards but
## is entered from the same side for the same reason.
func adrift_arrival(toward: int) -> Vector2:
	if _map == null or toward < 0 or toward >= _map.count():
		return Vector2.UP * StarSystem.VOID_REACH
	var out: Vector2 = (_at - _map.positions[toward]).normalized()
	if out.is_zero_approx():
		out = Vector2.UP
	return out * StarSystem.VOID_REACH


## Which way the drive is pointed, in the world's frame, or zero when it
## is pointed nowhere.
##
## The lane and the heading are the same thing because the galaxy and the
## system are the same plane -- the decision the whole of section 10
## rests on. Public because the sky streaks along it and the sky has no
## business working it out a second time.
func lane_heading() -> Vector2:
	var index: int = showing()
	if _map == null or index < 0 or index >= _map.count():
		return Vector2.ZERO
	return (_map.positions[index] - _at).normalized()


func _system_at(index: int) -> StarSystem:
	if _galaxy == null or not _galaxy.has_method("system"):
		return null
	return _galaxy.system(index) as StarSystem


func _physics_process(delta: float) -> void:
	if use_player_input:
		_read_key(delta)
	advance(delta)


## One key, two jobs. A tap toggles the drive; a press that outlives a
## tap is a hold, and a hold on a live drive is a charge.
##
## The tap is read on release rather than on press, which is the only way
## round the ambiguity: every hold begins as a press, so a press cannot
## mean "toggle" without also toggling at the start of every charge.
func _read_key(delta: float) -> void:
	if Input.is_action_pressed(&"jump"):
		_held_for += delta
		holding = armed and _held_for >= ARM_TAP
		return
	if _held_for > 0.0 and _held_for < ARM_TAP and phase == Phase.IDLE:
		set_armed(not armed)
	_held_for = 0.0
	holding = false


## Switches the drive on or off. Public and free of input, like every
## other door into this machine, so a test can arm it without a keyboard.
func set_armed(on: bool) -> void:
	if armed == on:
		return
	armed = on
	armed_changed.emit(armed)


## One step of the machine. Public and free of input, so a test can run a
## whole jump without a keyboard and without a frame.
func advance(delta: float) -> void:
	match phase:
		Phase.IDLE:
			_idle()
		Phase.CHARGING:
			_charging(delta)
		Phase.TRANSIT:
			_transit(delta)
		Phase.ARRIVAL:
			_arrival(delta)


func _idle() -> void:
	if not holding or not armed:
		return
	var wanted: int = aimed_at()
	var excuse: String = blocked_by(wanted)
	if not excuse.is_empty():
		# Once per press, not once per tick: a reason repeated sixty times
		# a second is a reason nobody reads.
		holding = false
		refused.emit(excuse)
		return
	_target = wanted
	# Weighed before the charge is spent, because spending one is what
	# takes the shortfall out of the risk and the pilot is owed the
	# figure they were shown when they pressed.
	_risk = misjump_risk(wanted)
	# Which currency this jump runs on, decided once and here. A charge
	# if there is one, engine fuel if there is not -- the drive fires
	# either way, and the difference is how likely it is to arrive where
	# it was pointed.
	#
	# **Spent at the spool-up, not at the arrival.** A charge is dumped
	# into the coils to start the thing, so an interruption costs the
	# whole of it; the fuel path already works that way and a charge
	# cannot be burned by the second because it is indivisible. It makes
	# starting a jump in a fight an expensive way to find out you are
	# in one, which is the lesson that rule exists to teach.
	_on_charge = _ship.draw_charge()
	_bill = 0.0 if _on_charge else bill_for(wanted)
	_spent = 0.0
	_charge = 0.0
	_enter(Phase.CHARGING)


func _charging(delta: float) -> void:
	if not holding:
		_target = -1
		_enter(Phase.IDLE)
		refused.emit("interrupted")
		return
	var drive: JumpDriveData = _ship.jump_drive()
	if drive == null:
		_enter(Phase.IDLE)
		refused.emit("no drive")
		return
	# Burned as it goes, which is how a cancelled charge comes to cost
	# something without a second rule for it. IDEAS.md asks for partial
	# burn on an interruption; spending by the second gives it for free
	# and makes the tank readable while it happens.
	# Capped at what is left of the fare. A tick boundary rarely divides
	# the charge time, so the last tick of a 2.4 second spool at sixty
	# hertz charged a full rate for a fraction of a second and the jump
	# came out eight tenths of a per cent over its own price. Small, and
	# exactly the kind of number that is wrong for ever once nobody is
	# looking at it.
	var want: float = minf(
		_bill * delta / maxf(drive.charge_time, 0.001), maxf(_bill - _spent, 0.0)
	)
	# What there is, not what was asked for. Running the tank dry mid
	# charge used to cancel the jump; it does not any more, because
	# IDEAS.md section 10 wants a shortfall to be a risk rather than a
	# wall. The risk was weighed when the charge started and the pilot
	# can still let go.
	_spent += _ship.draw_fuel(want)
	_charge += delta
	if _charge < drive.charge_time:
		return
	# The lane is checked **here**, at the moment the drive would fire,
	# and not when it was lit. Two reasons, and the second is the better
	# one: the charge has been spent by now, so a fouled lane costs what
	# a jump costs; and the bodies have moved during the spool, so a
	# planet that drifted into the way balks the jump exactly as a
	# planet that was always there does. The pilot was told before they
	# started -- `lane_blocked` is on the HUD -- so this is the cough
	# rather than the news.
	var fouled: SystemBody = lane_blocked(_target)
	if fouled != null:
		_target = -1
		_enter(Phase.IDLE)
		balked.emit(fouled)
		return
	_clock = 0.0
	_swapped = false
	_enter(Phase.TRANSIT)


func _transit(delta: float) -> void:
	_clock += delta
	if not _swapped and _clock >= TRANSIT_SECONDS * SWAP_AT:
		_swapped = true
		var heading: float = _ship.global_rotation if _ship != null else 0.0
		# The roll happens here rather than at the start, so that the
		# whole charge is spent before anybody finds out -- which is
		# what makes the gamble cost something whichever way it lands.
		_went_astray = _risk > 0.0 and _rng.randf() < _risk
		if _went_astray:
			var share: float = _rng.randf_range(FELL_SHORT.x, FELL_SHORT.y)
			var fell_at: Vector2 = adrift_point(_target, share)
			var came_in: Vector2 = adrift_arrival(_target)
			# Announced first. The listener has to build a sector before
			# it can be told to put the ship in one, and a sector is
			# known only by where it is.
			misjumped.emit(_target, fell_at)
			_here = -1
			_at = fell_at
			crossed.emit(_here, -1, came_in, heading)
		else:
			crossed.emit(_here, _target, arrival_point(_target), heading)
			# Only after the listener has been told, because the arrival
			# point is measured from where the ship was: moving the
			# address first would put the pilot on the wrong side of the
			# system they just reached, which is a bug that looks like a
			# rounding error.
			_here = _target
			_at = _map.positions[_target]
	if _clock >= TRANSIT_SECONDS:
		_clock = 0.0
		_enter(Phase.ARRIVAL)


## Arriving switches the drive off. See `armed`.
func _arrival(delta: float) -> void:
	_clock += delta
	if _clock < ARRIVAL_SECONDS:
		return
	var reached: int = _here
	_target = -1
	_enter(Phase.IDLE)
	arrived.emit(reached)


## How far through the current state it is, 0..1. What the effect reads.
func progress() -> float:
	match phase:
		Phase.CHARGING:
			var drive: JumpDriveData = _ship.jump_drive() if _ship != null else null
			var full: float = drive.charge_time if drive != null else 1.0
			return clampf(_charge / maxf(full, 0.001), 0.0, 1.0)
		Phase.TRANSIT:
			return clampf(_clock / TRANSIT_SECONDS, 0.0, 1.0)
		Phase.ARRIVAL:
			return clampf(_clock / ARRIVAL_SECONDS, 0.0, 1.0)
		_:
			return 0.0


## Which system this controller thinks it is in, or -1 out in the gap.
func here() -> int:
	return _here


## Where it thinks it is, in light years. The real address.
func at() -> Vector2:
	return _at


## Whether the last crossing fell short.
func went_astray() -> bool:
	return _went_astray


## The roll, for tests and for anything that wants to show the odds.
func rolls_with(seeded: int) -> void:
	_rng.seed = seeded


## What the charge is aimed at, or -1.
func target() -> int:
	return _target


## The system the pilot would jump to if they pressed now: the latched
## one while charging, whatever the nose is on otherwise.
func showing() -> int:
	return _target if phase != Phase.IDLE else aimed_at()


func _enter(next: Phase) -> void:
	if phase == next:
		return
	phase = next
	phase_changed.emit(phase)


## A hit while spooling stops the jump. The fuel already burned is gone,
## which is the cost of having tried.
func _on_hit(_impact_speed: float, _damage: float) -> void:
	if phase != Phase.CHARGING:
		return
	holding = false
	_target = -1
	_enter(Phase.IDLE)
	refused.emit("a hit broke the charge")
