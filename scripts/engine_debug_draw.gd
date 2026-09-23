class_name EngineDebugDraw
extends Node2D
## Draws every engine on the hull with its live throttle, plus the centre of
## mass.
##
## Worth having because the control groups are computed rather than declared:
## when the ship does something unexpected, the question is always "which
## engines actually fired", and this answers it directly instead of by
## inference from the console dump.
##
## A child of the ship, so mount positions are already in the right frame.

## Group every debug visual joins, so one key hides the lot.
const DEBUG_GROUP: StringName = &"debug_visuals"

const TRIANGLE_LENGTH: float = 6.0
const TRIANGLE_HALF_WIDTH: float = 2.5
const CROSS_ARM: float = 4.0

const TYPE_COLORS: Dictionary = {
	EngineData.Type.MAIN: Color(1.0, 0.55, 0.15),
	EngineData.Type.TORQUE: Color(0.25, 0.9, 1.0),
	EngineData.Type.THRUSTER: Color(1.0, 0.92, 0.3),
}

const DAMAGED_OUTLINE: Color = Color(1.0, 0.25, 0.2)
const CENTRE_COLOR: Color = Color(1.0, 1.0, 1.0, 0.8)

var _ship: Ship = null


func _ready() -> void:
	add_to_group(DEBUG_GROUP)
	_ship = get_parent() as Ship


func _physics_process(_delta: float) -> void:
	if visible and _ship != null:
		queue_redraw()


func _draw() -> void:
	if _ship == null:
		return

	for engine: EngineInstance in _ship.engines:
		_draw_engine(engine)

	# The centre of mass is the pivot every torque in the control maths is
	# measured from, so seeing where it actually sits explains most surprises.
	var centre: Vector2 = _ship.center_of_mass
	draw_line(centre - Vector2(CROSS_ARM, 0.0), centre + Vector2(CROSS_ARM, 0.0), CENTRE_COLOR, 1.0)
	draw_line(centre - Vector2(0.0, CROSS_ARM), centre + Vector2(0.0, CROSS_ARM), CENTRE_COLOR, 1.0)


func _draw_engine(engine: EngineInstance) -> void:
	var origin: Vector2 = engine.mount.position
	# The triangle points down the exhaust, which is the opposite of the force.
	var exhaust: Vector2 = -engine.mount.force_direction()
	if exhaust.is_zero_approx():
		return

	var tip: Vector2 = origin + exhaust * TRIANGLE_LENGTH
	var side: Vector2 = exhaust.orthogonal() * TRIANGLE_HALF_WIDTH
	var shape: PackedVector2Array = PackedVector2Array([tip, origin + side, origin - side])

	var color: Color = TYPE_COLORS.get(engine.data.type, Color.WHITE)
	color.a = 0.3 + 0.7 * engine.throttle
	draw_colored_polygon(shape, color)

	if engine.health < 1.0:
		draw_polyline(
			PackedVector2Array([shape[0], shape[1], shape[2], shape[0]]), DAMAGED_OUTLINE, 1.0
		)
