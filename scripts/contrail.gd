class_name Contrail
extends Line2D
## A condensation trail streaming off one point of the hull.
##
## Tells the pilot they are in air, and how much of it, without a HUD element:
## nothing in space, a thin thread high up, a thick rope low and fast. That is
## the same quantity the drag and the hull heating use, so what you see is what
## is slowing you down.
##
## top_level is on, so the recorded points stay where they were dropped in the
## world instead of being dragged along by the ship (which would make the trail
## a rigid stick glued to the hull).

## Where on the hull the trail comes off, in the ship's local frame.
@export var anchor_offset: Vector2 = Vector2.ZERO

## The ship this hangs off. Defaults to the parent.
@export var ship_path: NodePath = NodePath("..")

## Points kept at full intensity. Each point is one physics tick of travel.
@export var max_points: int = 44

## density * speed at which the trail reaches full length and opacity. Below
## it the trail is proportionally shorter, which is what makes altitude and
## speed readable at a glance.
@export var reference_flow: float = 45.0

## Points removed per tick when the trail is shrinking. Low enough that leaving
## the atmosphere lets the trail stream out behind rather than blink off.
const FADE_PER_TICK: int = 2

## Below this the trail stops emitting entirely, so a ship drifting in vacuum
## leaves nothing at all.
const MIN_FLOW: float = 0.02

var _ship: Ship = null


func _ready() -> void:
	top_level = true
	clear_points()
	_ship = get_node_or_null(ship_path) as Ship


func _physics_process(_delta: float) -> void:
	if _ship == null:
		return

	var flow: float = clampf(
		_ship.air_density * _ship.linear_velocity.length() / reference_flow, 0.0, 1.0
	)

	if flow > MIN_FLOW:
		add_point(_ship.global_transform * anchor_offset)

	var wanted: int = int(round(flow * float(max_points)))
	var removed: int = 0
	while get_point_count() > wanted and removed < FADE_PER_TICK:
		remove_point(0)
		removed += 1

	modulate.a = flow
