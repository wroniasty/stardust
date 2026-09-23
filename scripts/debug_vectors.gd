class_name DebugVectors
extends Node2D
## World-space debug arrows on the ship: where it is going, and which way it is
## being pulled.
##
## Drawn in the world rather than on the HUD CanvasLayer, because the whole
## point is to compare these directions against the planet and the terrain.
## The node parks itself on the ship every frame but is never a child of it, so
## the arrows keep world orientation while the ship rolls.

## Pixels of arrow per pixel per second of speed, and the range it is held to.
const VELOCITY_SCALE: float = 0.20
const VELOCITY_MIN: float = 10.0
const VELOCITY_MAX: float = 56.0

## Pixels of arrow per px/s^2 of pull, and its range. Gravity spans a much
## smaller numeric range than speed, so it gets its own scale.
const GRAVITY_SCALE: float = 0.9
const GRAVITY_MIN: float = 10.0
const GRAVITY_MAX: float = 40.0

const HEAD_LENGTH: float = 5.0
const HEAD_WIDTH: float = 3.5

const VELOCITY_COLOR: Color = Color(0.45, 1.0, 0.55)
const GRAVITY_COLOR: Color = Color(1.0, 0.55, 0.35)

@export var ship_path: NodePath

var _ship: Ship = null


func _ready() -> void:
	add_to_group(EngineDebugDraw.DEBUG_GROUP)
	if not ship_path.is_empty():
		_ship = get_node_or_null(ship_path) as Ship


func _physics_process(_delta: float) -> void:
	if _ship == null or not visible:
		return
	# Physics rather than idle: reading the ship's transform from a rendered
	# frame gets the un-interpolated physics position, so the arrows would sit
	# a fraction of a tick away from the hull they belong to.
	global_position = _ship.global_position
	queue_redraw()


func _draw() -> void:
	if _ship == null:
		return

	var velocity: Vector2 = _ship.linear_velocity
	if not velocity.is_zero_approx():
		_draw_arrow(velocity.normalized(), _length(velocity.length(), VELOCITY_SCALE, VELOCITY_MIN, VELOCITY_MAX), VELOCITY_COLOR)

	# The net pull, not the direction to one body: with a moon in the field
	# (M3) the sum is what the ship actually follows.
	var gravity: Vector2 = _ship.get_applied_gravity()
	if not gravity.is_zero_approx():
		_draw_arrow(gravity.normalized(), _length(gravity.length(), GRAVITY_SCALE, GRAVITY_MIN, GRAVITY_MAX), GRAVITY_COLOR)


## Arrow length for a magnitude, clamped so it stays readable at 640x360 both
## when drifting and when screaming towards a planet.
func _length(magnitude: float, scale_factor: float, shortest: float, longest: float) -> float:
	return clampf(magnitude * scale_factor, shortest, longest)


func _draw_arrow(direction: Vector2, length: float, color: Color) -> void:
	var tip: Vector2 = direction * length
	var base: Vector2 = direction * maxf(length - HEAD_LENGTH, 0.0)
	var side: Vector2 = direction.orthogonal() * HEAD_WIDTH

	draw_line(Vector2.ZERO, base, color, 1.0)
	draw_colored_polygon(PackedVector2Array([tip, base + side, base - side]), color)
