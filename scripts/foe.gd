class_name Foe
extends CharacterBody2D
## One enemy, standing where its garrison put it.
##
## **Not a `Ship`, and that is the decision this class is.** The player's
## hull is two and a half thousand lines of mounts, fitout, fuel, heat
## and a least-squares thrust solver, and a core world holds two dozen
## defenders. Giving each of them that machinery would mean rolling a
## loadout per enemy so that `strength` meant something, and solving a
## control allocation per enemy per tick so that it could move.
##
## So a foe is the cheap half: a number for how much it can take, a
## shape to be hit in, and a place to stand. The project has made this
## trade once before and written down why -- `LootCrate` integrates
## itself rather than being a `RigidBody2D` -- and the reason is the
## same one: not everything that exists has to be simulated like the
## thing the game is about.
##
## `CharacterBody2D` rather than a bare `Node2D`, because a round hits
## what the physics server reports and an `Area2D` is not reported by
## `body_entered`. It costs nothing while nothing moves it, and the AI
## that will move it is a later item.
##
## It stands, it shoots what comes into its territory, it flies about
## inside that territory, and it dies.
##
## ## The one thing none of the archetypes does
##
## **Nothing leaves its territory.** Not as a preference the steering
## expresses and the momentum overrules -- as a line the goal is
## clamped to and the position is clamped to, every tick. A defender
## that followed the pilot out would turn every contact into a
## commitment, and a game where contact is commitment is a game of
## avoiding contact. Holding the line is what makes the same enemy a
## decision: go round, or go in.
##
## The archetypes differ only in **where inside the line they want to
## be**, which is enough to make them read differently from the cockpit:
## an aggressor comes to meet you, a patrol keeps its distance, a runner
## breaks off when it is hurt.

## Hull a defender gets per point of strength, on the same 0..1 scale
## the ship's integrity uses.
##
## Measured against the stock autocannon, which does 0.08 a round: a
## rim fighter at 0.55 strength takes 3 rounds, a core fighter 7, a
## core turret 10, a core elite 16. The crowd is meant to be the
## pressure, so a single one of them has to die in a pass -- twelve
## rounds each, which is what a full ship takes, would make clearing a
## core world a matter of ammunition rather than of flying.
const HULL_PER_STRENGTH: float = 0.30

## How big each shape is drawn and hit, by what it is.
##
## A turret is squat because it is bolted down, a carrier is the big
## one, and a fighter is small enough that a crowd of them reads as a
## crowd rather than as a wall. The ship is about 24 by 32 for scale.
const SIZE_FIGHTER: float = 7.0
const SIZE_TURRET: float = 9.0
const SIZE_ELITE: float = 12.0
const SIZE_CARRIER: float = 16.0

## How far a defender can shoot, by what it is.
##
## A turret reaches as far as the player's own autocannon; a fighter
## less, because it is supposed to be got past. Both are well inside
## the territory they stand in -- six thousand pixels typical -- so
## crossing the line is a warning rather than an ambush: you see them
## light up with room to turn round.
const REACH_FIGHTER: float = 1800.0
const REACH_TURRET: float = 2400.0

## Shots a second, and what one does to a hull.
##
## Slow and light on purpose. The crowd is meant to be the pressure:
## a rim fighter is 0.011 of a hull a second and six of them, if the
## pilot sits still inside everything's reach, take a quarter of a
## minute. A core fighter is three times that, and the four or five of
## them a pilot can be in range of at once are about seven seconds of
## standing still -- which is a fight you can fly out of rather than
## one you lose by entering.
const ROUNDS_PER_SECOND: float = 0.8
const DAMAGE_PER_STRENGTH: float = 0.04

## And how a round leaves. The same muzzle speed and the same spread as
## the stock autocannon, so a pilot can read a defender's fire against
## something they already know.
##
## Twice the spread was the first answer -- a bolted-down gun with no
## gunner is not an ace -- and the measurement threw it out: four
## degrees is a cone 126 px wide at the far end of a defender's reach,
## against a hull 24 px across, so the gun that was meant to be
## inaccurate was simply a gun that never hits. At two degrees a
## defender lands about one round in two at close range, which is what
## "not an ace" should have meant.
const MUZZLE_SPEED: float = 600.0
const SPREAD: float = 0.0349

## How fast a defender can go, and how quickly it gets there.
##
## Slower than the ship on purpose, and the reason is not balance: the
## pilot's way out is **leaving the territory**, not out-running
## anybody. The stock dart does about 58 px/s per second of burn and
## three times that boosting, so it passes any of these inside a few
## seconds of open throttle -- while they turn tighter than it does,
## which is what makes them annoying at close range and irrelevant at
## long.
const TOP_SPEED_FIGHTER: float = 260.0
const TOP_SPEED_ELITE: float = 320.0
const TOP_SPEED_CARRIER: float = 90.0
const ACCELERATION: float = 180.0

## Where each kind wants to sit, as a share of its own reach.
##
## This is the whole difference between the archetypes. An aggressor
## closes until it is well inside its own gun; a patrol holds the far
## end of it and makes the pilot come to it; a runner sits on the edge
## where one wrong turn by the pilot loses it. A carrier keeps back,
## because what it is for is the stream, not the duel.
const STAND_OFF_AGGRESSOR: float = 0.45
const STAND_OFF_PATROL: float = 0.75
const STAND_OFF_RUNNER: float = 0.95
const STAND_OFF_CARRIER: float = 0.85

## What is left of a runner when it breaks off.
##
## Only the runner, and only when hurt. A whole archetype that flees on
## sight would be an archetype the pilot never meets; one that flees
## when it is nearly dead is the one that gets away with the news.
const FLEE_BELOW: float = 0.35

## Close enough to its post to call it standing there, in pixels.
const HOME_WITHIN: float = 40.0

## How far out from its goal it starts slowing down, in pixels.
##
## Without it a defender oscillates across its post for ever: full speed
## at one pixel out means it arrives doing 260 px/s and leaves again.
const ARRIVE_BAND: float = 140.0

## The line, for a group that holds no body.
##
## `Garrison.adrift` gives its members no territory, because what they
## hold is wherever they happen to be. They still hold it: a defender
## with no line is the chase the design rules out, so the line becomes a
## shell round where it was put.
const LOOSE_TERRITORY: float = 2500.0

## The physics layer defenders stand on.
##
## Their own, so a garrison does not shoot itself to pieces while
## shooting at the pilot: a defender's round looks for layer one and
## finds only the ship, while the pilot's rounds look for both. Whether
## defenders can ever hurt each other is a question for the day
## something can turn them on one another, and answering it now would
## be inventing a faction system for nobody.
const LAYER: int = 4

const ROUND_SCENE: String = "res://scenes/projectile.tscn"

## Hull colours. Their own, not the interface palette: this is a thing
## in the world, and UI_STYLE's twelve roles are about the panel over
## it. Rank is the channel -- a major is the one you remember, so it is
## the one that is lit.
const INK_MINOR: Color = Color(0.72, 0.36, 0.33)
const INK_MAJOR: Color = Color(0.96, 0.55, 0.30)
const INK_TURRET: Color = Color(0.55, 0.47, 0.52)

## What a defender is doing. Three, because the questions are three:
## is the pilot in my territory, am I at my post, and nothing else.
##
## Movement is the only thing the state picks. Firing is decided by
## reach and cadence whatever the state says, so a defender that is
## walking home and happens to have something in range shoots at it.
enum State { HOLD, ENGAGE, RETURN }

signal died(foe: Foe)

## Shot at. The garrison it belongs to wants to know, whatever its
## posture: being shot is the one provocation nobody rolls for.
signal hurt(foe: Foe)

## Whether this one is in the fight. Set by the spawner, which owns the
## question of what woke the garrison; a foe only has to know the
## answer.
var awake: bool = false

## What the roster said this one is. Kept whole rather than unpacked
## into fields: the spawner needs it back to write the kill down, and
## two copies of a dictionary is one of them going stale.
var member: Dictionary = {}

## And the garrison it belongs to, for the territory it holds and the
## posture it holds it with. Read by the AI when there is one.
var held: Dictionary = {}

var hull: float = 1.0
var hull_full: float = 1.0

## Where the thing it is holding is, in world coordinates.
##
## Written by the spawner every tick rather than read from `held`,
## because a planet turns and a station orbits: a territory measured
## from where the body was when the garrison stood up would drift off
## the body it is supposed to be a shell round.
var anchor: Vector2 = Vector2.ZERO

## Its post, as an offset from the anchor. The spawner works out where
## that is (`station_for`); keeping it relative is what lets the body
## move without the garrison sliding off it.
var station: Vector2 = Vector2.ZERO

## How far out the line is. Nought means the garrison gave none, and
## then `LOOSE_TERRITORY` applies -- see there.
var territory: float = 0.0

var state: State = State.HOLD

var _size: float = SIZE_FIGHTER
var _ink: Color = INK_MINOR
var _shape: CollisionShape2D = null
var _reach: float = REACH_FIGHTER
var _damage: float = 0.02
var _top_speed: float = TOP_SPEED_FIGHTER
var _stand_off: float = STAND_OFF_PATROL

## Which way round the pilot this one takes station, as an angle.
##
## From its own seed, so a dozen defenders converging on one ship form
## an arc rather than a pile. Cheaper than separation steering and
## deterministic, which matters here: a crowd that arranges itself
## differently on the second visit is a crowd that cannot be tested.
var _slot: float = 0.0

## Seconds until this one can fire again. Started at a fraction of the
## interval drawn from the member's own seed, so a garrison opens up
## as a scatter rather than as one volley -- six rounds arriving on the
## same frame is a wall, and the same six staggered is a fight.
var _cooldown: float = 0.0


func _ready() -> void:
	collision_layer = LAYER
	collision_mask = 1
	if _shape == null:
		_shape = CollisionShape2D.new()
		var circle: CircleShape2D = CircleShape2D.new()
		circle.radius = _size
		_shape.shape = circle
		add_child(_shape)
	queue_redraw()


## Puts a roster entry on this node. Everything about what it is comes
## from the entry, so there is nothing to keep in step by hand.
func arm(entry: Dictionary, garrison: Dictionary = {}) -> void:
	member = entry
	held = garrison
	hull_full = maxf(float(entry.get("strength", 1.0)) * HULL_PER_STRENGTH, 0.01)
	hull = hull_full
	var archetype: int = int(entry.get("archetype", Garrison.Archetype.PATROL))
	var major: bool = int(entry.get("rank", Garrison.Rank.MINOR)) == Garrison.Rank.MAJOR
	match archetype:
		Garrison.Archetype.TURRET:
			_size = SIZE_TURRET
			_ink = INK_TURRET
		Garrison.Archetype.CARRIER:
			_size = SIZE_CARRIER
			_ink = INK_MAJOR
		_:
			_size = SIZE_ELITE if major else SIZE_FIGHTER
			_ink = INK_MAJOR if major else INK_MINOR
	if _shape != null and _shape.shape is CircleShape2D:
		(_shape.shape as CircleShape2D).radius = _size
	_reach = (
		REACH_TURRET if archetype == Garrison.Archetype.TURRET
		else REACH_FIGHTER * (1.2 if major else 1.0)
	)
	_damage = float(entry.get("strength", 1.0)) * DAMAGE_PER_STRENGTH
	var share: float = float(absi(int(entry.get("seed", 0))) % 1000) / 1000.0
	_cooldown = _interval() * share
	_slot = share * TAU
	_top_speed = (
		TOP_SPEED_CARRIER if archetype == Garrison.Archetype.CARRIER
		else (TOP_SPEED_ELITE if major else TOP_SPEED_FIGHTER)
	)
	match archetype:
		Garrison.Archetype.AGGRESSOR:
			_stand_off = STAND_OFF_AGGRESSOR
		Garrison.Archetype.RUNNER:
			_stand_off = STAND_OFF_RUNNER
		Garrison.Archetype.CARRIER:
			_stand_off = STAND_OFF_CARRIER
		_:
			_stand_off = STAND_OFF_PATROL
	territory = float(garrison.get("territory", 0.0))
	queue_redraw()


func _interval() -> float:
	return 1.0 / maxf(ROUNDS_PER_SECOND, 0.01)


## How far this one can shoot. Public because the spawner decides who
## is worth firing at and the answer has to be the same number.
func reach() -> float:
	return _reach


## Whether this one never comes back once it is gone.
func is_major() -> bool:
	return int(member.get("rank", Garrison.Rank.MINOR)) == Garrison.Rank.MAJOR


## The same name the ship answers to, which is the whole of how a round
## knows it can hurt this. See `Damage`.
func take_damage(amount: float, _cause: String = "") -> void:
	if amount <= 0.0 or hull <= 0.0:
		return
	hull = maxf(hull - amount, 0.0)
	hurt.emit(self)
	queue_redraw()
	if hull <= 0.0:
		died.emit(self)


## One tick of standing watch. Does nothing at all while the garrison
## is asleep, which is what makes a passive world cost nothing to fly
## past.
##
## **It leads the target**, and the first version did not. The reason
## given then was that a pilot who keeps moving should be hard to hit
## and that leading belongs to a gunner. Both true, and together they
## produced a garrison that could not hit anything: measured in the
## running game, rounds passing 143 px behind a ship that was doing
## nothing but falling. In this game nothing is ever still -- the ship
## falls, the crates fall, the rounds themselves fall -- so "where it
## is" is never where it will be, and a gunner who cannot hit a falling
## object cannot hit anything near a planet.
##
## First order, which is the honest amount: the round flies straight at
## a constant speed, so the time to arrive is the distance over that
## speed, and the lead is what the target does in that time. A pilot's
## defence is **changing** velocity rather than merely having one,
## which is a better lesson than the one the miss was teaching.
func tick(delta: float, target: Node2D, container: Node) -> void:
	if not awake or hull <= 0.0 or target == null or not is_instance_valid(target):
		return
	if not holds_still():
		_steer(delta, target)
	var out: Vector2 = target.global_position - global_position
	if out.length() > _reach:
		# Out of reach, so point where it is going instead of at
		# something it cannot shoot. A defender aimed at a ship two
		# screens away reads as a defender that is about to fire.
		if velocity.length() > 1.0:
			rotation = velocity.angle() + PI * 0.5
		return
	rotation = out.angle() + PI * 0.5
	_cooldown -= delta
	if _cooldown > 0.0:
		return
	_cooldown = _interval()
	fire_at(lead_on(target), container)


## Whether this one is bolted down. A turret is the thing that does not
## move, which is the whole of why the archetype exists.
func holds_still() -> bool:
	return int(member.get("archetype", Garrison.Archetype.PATROL)) == Garrison.Archetype.TURRET


## How far out this one's line is.
func line() -> float:
	return territory if territory > 0.0 else LOOSE_TERRITORY


## One tick of flying. Picks a state, picks a goal, and moves towards it
## at a bounded acceleration -- the same first-order follower the camera
## uses, for the same reason: a thing that snaps to its goal does not
## look like a thing with mass.
func _steer(delta: float, target: Node2D) -> void:
	state = _state_for(target)
	var goal: Vector2 = _inside(_goal_for(target))
	var out: Vector2 = goal - global_position
	var want: Vector2 = Vector2.ZERO
	if out.length() > 1.0:
		want = out.normalized() * _top_speed * clampf(
			out.length() / ARRIVE_BAND, 0.0, 1.0
		)
	velocity = velocity.move_toward(want, ACCELERATION * delta)
	move_and_slide()

	# And the line again, on the position this time.
	#
	# Clamping the goal is not enough and the difference is momentum: a
	# defender that accelerated towards a goal on the line arrives doing
	# 260 px/s and coasts straight through it. So the outward component
	# of the velocity is taken away at the line and the tangential part
	# is left, which is a defender turning along its own perimeter
	# rather than one bouncing off an invisible wall.
	var away: Vector2 = global_position - anchor
	var reach: float = line()
	if away.length() > reach and reach > 0.0:
		var outward: Vector2 = away.normalized()
		global_position = anchor + outward * reach
		velocity = velocity.slide(outward)


## What this one is doing, from two distances and nothing else.
func _state_for(target: Node2D) -> State:
	if target.global_position.distance_to(anchor) <= line():
		return State.ENGAGE
	if global_position.distance_to(anchor + station) <= HOME_WITHIN:
		return State.HOLD
	return State.RETURN


## Where it wants to be.
##
## Engaging, that is a point at its own stand-off range from the pilot,
## on its own bearing round them -- so the defenders of one body spread
## into an arc instead of stacking on the line between the pilot and the
## body. Otherwise it is its post, which is also what a runner that has
## had enough heads away from.
func _goal_for(target: Node2D) -> Vector2:
	if state != State.ENGAGE:
		return anchor + station
	if runs_away():
		var away: Vector2 = global_position - target.global_position
		if away.length() < 1.0:
			away = Vector2.RIGHT.rotated(_slot)
		return global_position + away.normalized() * line()
	return target.global_position + Vector2.RIGHT.rotated(_slot) * (_stand_off * _reach)


## Whether this one has had enough. Public because it is a thing the
## pilot can see -- a runner peeling off is information -- and a test
## should be able to ask rather than infer.
func runs_away() -> bool:
	return (
		int(member.get("archetype", Garrison.Archetype.PATROL)) == Garrison.Archetype.RUNNER
		and hull < hull_full * FLEE_BELOW
	)


## The same point, brought inside the line.
func _inside(goal: Vector2) -> Vector2:
	var out: Vector2 = goal - anchor
	var reach: float = line()
	if out.length() <= reach or reach <= 0.0:
		return goal
	return anchor + out.normalized() * reach


## Where to aim to hit something that is going somewhere.
##
## Duck-typed on `linear_velocity`, like the damage path: a gunner has
## no business knowing whether it is shooting at a hull, a drone or
## whatever is shootable next.
func lead_on(target: Node2D) -> Vector2:
	var at: Vector2 = target.global_position
	if not ("linear_velocity" in target):
		return at
	var travel: Vector2 = target.get("linear_velocity")
	var flight: float = at.distance_to(global_position) / maxf(MUZZLE_SPEED, 1.0)
	return at + travel * flight


## Puts one round down the line. Public so a test can make it shoot
## without waiting for a cadence.
func fire_at(at: Vector2, container: Node) -> Node2D:
	if container == null or not is_instance_valid(container):
		return null
	var scene: PackedScene = load(ROUND_SCENE) as PackedScene
	if scene == null:
		return null
	var shot: Projectile = scene.instantiate() as Projectile
	if shot == null:
		return null
	var aim: float = (at - global_position).angle() + randf_range(-SPREAD, SPREAD)
	shot.shooter = self
	shot.damage = _damage
	# Layer one only: the pilot's hull and nothing else. See `LAYER`.
	shot.collision_mask = 1
	shot.global_position = global_position
	shot.velocity = Vector2.RIGHT.rotated(aim) * MUZZLE_SPEED
	shot.rotation = shot.velocity.angle() + PI * 0.5
	container.add_child(shot)
	return shot


func _draw() -> void:
	var archetype: int = int(member.get("archetype", Garrison.Archetype.PATROL))
	# Dimmed by what is left of it, so a defender that has been worked
	# on looks worked on. Floor well above black: an almost-dead foe
	# still has to be visible against a planet at night.
	var wear: float = clampf(hull / maxf(hull_full, 0.0001), 0.0, 1.0)
	var ink: Color = _ink.lerp(Color(0.22, 0.16, 0.16), (1.0 - wear) * 0.65)

	if archetype == Garrison.Archetype.TURRET:
		# Bolted down: a squat box on a base, which is the one shape
		# here that should not look like it goes anywhere.
		draw_rect(Rect2(Vector2(-_size, -_size * 0.6), Vector2(_size * 2.0, _size * 1.2)), ink, true)
		draw_rect(
			Rect2(Vector2(-_size * 0.3, -_size * 1.4), Vector2(_size * 0.6, _size * 0.9)),
			ink,
			true,
		)
		return
	if archetype == Garrison.Archetype.CARRIER:
		# A slab with a mouth: the thing other things come out of.
		draw_rect(
			Rect2(Vector2(-_size, -_size * 0.5), Vector2(_size * 2.0, _size)), ink, true
		)
		draw_rect(
			Rect2(Vector2(_size * 0.2, -_size * 0.25), Vector2(_size * 0.8, _size * 0.5)),
			Color(0.08, 0.07, 0.09),
			true,
		)
		return
	# Everything that flies is a dart, pointed the way it is facing.
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(0.0, -_size),
			Vector2(_size * 0.72, _size * 0.8),
			Vector2(0.0, _size * 0.45),
			Vector2(-_size * 0.72, _size * 0.8),
		]),
		ink,
	)
	if is_major():
		draw_arc(Vector2.ZERO, _size * 1.35, 0.0, TAU, 20, ink, 1.0)
	if awake:
		# One ring, drawn only while it is in the fight. A defender that
		# looked the same awake and asleep would make "passive" a thing
		# the pilot can only learn by being shot.
		draw_arc(Vector2.ZERO, _size * 1.9, 0.0, TAU, 24, Color(ink, 0.55), 1.0)
