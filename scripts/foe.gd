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
## What it does **not** have, on purpose and for now: any behaviour at
## all. It stands, it can be shot, it dies. That is enough to close the
## loop the garrison model has been waiting on -- beat a major, leave,
## come back, and find it still gone -- and behaviour is a thing to add
## to something that already works rather than a second unknown.

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

## Hull colours. Their own, not the interface palette: this is a thing
## in the world, and UI_STYLE's twelve roles are about the panel over
## it. Rank is the channel -- a major is the one you remember, so it is
## the one that is lit.
const INK_MINOR: Color = Color(0.72, 0.36, 0.33)
const INK_MAJOR: Color = Color(0.96, 0.55, 0.30)
const INK_TURRET: Color = Color(0.55, 0.47, 0.52)

signal died(foe: Foe)

## What the roster said this one is. Kept whole rather than unpacked
## into fields: the spawner needs it back to write the kill down, and
## two copies of a dictionary is one of them going stale.
var member: Dictionary = {}

## And the garrison it belongs to, for the territory it holds and the
## posture it holds it with. Read by the AI when there is one.
var held: Dictionary = {}

var hull: float = 1.0
var hull_full: float = 1.0

var _size: float = SIZE_FIGHTER
var _ink: Color = INK_MINOR
var _shape: CollisionShape2D = null


func _ready() -> void:
	# Layer one, the same one the player's hull is on, because that is
	# what the round's mask looks for. A second layer would be a second
	# thing to keep in step with every weapon in the game.
	collision_layer = 1
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
	queue_redraw()


## Whether this one never comes back once it is gone.
func is_major() -> bool:
	return int(member.get("rank", Garrison.Rank.MINOR)) == Garrison.Rank.MAJOR


## The same name the ship answers to, which is the whole of how a round
## knows it can hurt this. See `Damage`.
func take_damage(amount: float, _cause: String = "") -> void:
	if amount <= 0.0 or hull <= 0.0:
		return
	hull = maxf(hull - amount, 0.0)
	queue_redraw()
	if hull <= 0.0:
		died.emit(self)


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
