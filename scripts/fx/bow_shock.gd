class_name BowShock
extends Node2D
## Jonizacja przed dziobem: widać, że wchodzisz w atmosferę.
##
## The hull has been heating up since M1 -- `hull_heat` rises with the
## air and the square of the speed -- and until now the only thing that
## said so was a number on the debug overlay and a tint on the plating.
## This is the part a pilot can see without reading anything.
##
## **Drawn along the velocity, not along the nose.** A shock forms
## where the air is being hit, which is the way you are going; a ship
## entering backwards burns on its tail. That distinction is free here
## and impossible to add later without redrawing the thing, and it is
## also the whole reason this is not just a glow on the hull.

## Heat at which the shock is as bright and as wide as it gets. One,
## because `hull_heat` is already a 0..1 reading of how close the hull
## is to failing -- a second scale would be a second thing to tune.
const FULL_HEAT: float = 1.0

## Below this there is nothing to draw. A ship in thin air warms very
## slowly, and a permanent faint smear ahead of the nose would read as
## a rendering fault rather than as entry.
const FAINTEST: float = 0.04

## How far ahead of the hull the shock stands and how wide it gets, in
## world pixels, at full heat. Standing off matters: a shock drawn on
## the hull is a hull that is glowing, which is a different thing the
## skin already does.
##
## Against a dart twenty-four pixels long. The first pass had the
## widest reading at seventeen -- about the width of the hull -- and
## on screen it read as a scratch on the nose rather than as a wall of
## air the ship is pushing. A shock has to be bigger than the thing
## making it or it is not a shock.
const STANDOFF: Vector2 = Vector2(9.0, 22.0)
const SPREAD: Vector2 = Vector2(14.0, 38.0)

## How many shells the gradient is built from. Each is an arc at a
## lower alpha, which is the cheapest gradient available to a
## `draw_arc` and plenty at this size.
const SHELLS: int = 5

## Cool at first and hot later, which is the order real entry goes in
## and also the order the hull's own tint goes in -- so the two agree
## rather than fighting.
const COOL: Color = Color(0.55, 0.80, 1.00)
const HOT: Color = Color(1.00, 0.72, 0.38)

## How much of a turn the arc covers. Just over a third: wide enough to
## read as a wall of air, narrow enough not to become a halo.
const ARC: float = 1.25

@export var ship_path: NodePath = NodePath("..")

var _ship: Ship = null


func _ready() -> void:
	# The shock belongs to the world's frame rather than the hull's: it
	# is aimed by the velocity, and a parent rotation would turn it
	# with the ship it is supposed to be independent of.
	top_level = true
	z_index = 40
	_ship = get_node_or_null(ship_path) as Ship


func _process(_delta: float) -> void:
	queue_redraw()


## How hard the air is being hit, 0..1. Zero when there is nothing to
## draw, so one reading answers both "how bright" and "at all".
##
## Public and ungated for the usual reason: the gate belongs in the
## draw, and a brightness that could only be read with a window open
## would be a brightness with no tests.
func intensity() -> float:
	if _ship == null or not is_instance_valid(_ship):
		return 0.0
	var heat: float = clampf(_ship.hull_heat / maxf(FULL_HEAT, 0.001), 0.0, 1.0)
	return 0.0 if heat < FAINTEST else heat


## Which way the shock stands off, in world space: the way the ship is
## going, or the way it is pointing when it is barely moving.
##
## The fallback matters more than it looks. A ship hanging still in
## thick air still heats, slowly, and a shock aimed at a zero vector
## would snap to the right every frame the velocity rounded away.
func facing() -> Vector2:
	if _ship == null or not is_instance_valid(_ship):
		return Vector2.UP
	var going: Vector2 = _ship.linear_velocity
	if going.length_squared() < 1.0:
		return Vector2.UP.rotated(_ship.global_rotation)
	return going.normalized()


func _draw() -> void:
	if not Presentation.is_on():
		return
	var heat: float = intensity()
	if heat <= 0.0:
		return
	var ahead: Vector2 = facing()
	# `top_level` is on, so this node is placed by hand every frame --
	# which means it has to be placed where the hull is **drawn**. The
	# ship is interpolated and this is not, so the physics position
	# would hang the shock a tick of travel in front of its own nose.
	global_position = _ship.drawn_position()
	global_rotation = 0.0

	var stand: float = lerpf(STANDOFF.x, STANDOFF.y, heat)
	var wide: float = lerpf(SPREAD.x, SPREAD.y, heat)
	var tint: Color = COOL.lerp(HOT, heat)
	var along: float = ahead.angle()

	# Centred on the ship, not ahead of it.
	#
	# The first version put the centre a standoff forward and drew the
	# span around the direction of travel, which is the **far** cap of
	# that circle -- so the shock appeared as a detached smile a long
	# way in front of the nose. A bow wave hugs the thing making it:
	# centre on the hull, radius is the standoff, and the arc wraps
	# around the leading edge.
	for shell: int in range(SHELLS):
		var out: float = float(shell) / float(SHELLS - 1)
		var radius: float = stand + wide * out * 0.5
		var alpha: float = heat * lerpf(0.60, 0.08, out)
		# Wider further out, so the shock opens into the slipstream
		# rather than sitting as a stack of parallel rainbows.
		var span: float = ARC * lerpf(1.0, 1.35, out)
		# Two pixels, not one. At a camera zoomed out to a tenth a
		# hairline arc disappears between samples, and the one moment
		# this matters is a long entry watched from far enough away to
		# see the whole descent.
		draw_arc(
			Vector2.ZERO, radius, along - span, along + span, 24,
			Color(tint, alpha), 2.0, true
		)
