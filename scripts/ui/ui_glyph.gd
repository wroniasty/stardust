class_name UiGlyph
extends RefCounted
## Male kształty rysowane kreską: co robi przycisk, bez słowa.
##
## Seven shapes for the seven flight assists, plus the chip the computer
## panel is opened by. Drawn rather than imported, which is UI_STYLE
## section 2 and 9: everything in the interface is lines on the design
## grid, and a bitmap icon at 640x360 would be the one thing on screen
## that cannot be drawn at a different size or recoloured by state.
##
## Each shape fits a square of side `2 * size` centred on `at` and is
## built from at most four strokes. That ceiling is the design: a
## thirteen-pixel square holds a direction, a curve or a bar, and an icon
## that needs more than that is an icon that should have been a word.
##
## The editor's own module glyphs (`ShipEditor._draw_kind_glyph`) are a
## second set and stay where they are, except the chip, which now has a
## caller here as well. The rest move when something outside the editor
## needs them; moving thirteen shapes for no second reader is churn.

## How the strokes are coloured when a shape is drawn "on": handed in,
## because the panel owns the state and this owns the shape.
static func chip(canvas: CanvasItem, at: Vector2, size: float, ink: Color) -> void:
	# A die with legs down both sides, the same chip the editor draws for
	# a fitted computer, so the thing in the bay and the thing on the HUD
	# are recognisably one object.
	var body: Vector2 = Vector2(size, size) * 0.7
	canvas.draw_rect(Rect2(at - body, body * 2.0), ink, false, 1.0)
	for side: float in [-1.0, 1.0]:
		for step: float in [-0.5, 0.5]:
			var y: float = at.y + step * size
			canvas.draw_line(
				Vector2(at.x + side * size * 0.7, y),
				Vector2(at.x + side * size * 1.3, y),
				ink,
				1.0,
			)


## One assist's shape.
static func assist(
	canvas: CanvasItem, kind: int, at: Vector2, size: float, ink: Color
) -> void:
	match kind:
		FlightAssists.Kind.PROGRADE:
			_arrow(canvas, at, size, ink, Vector2.RIGHT)
		FlightAssists.Kind.RETROGRADE:
			_arrow(canvas, at, size, ink, Vector2.LEFT)
		FlightAssists.Kind.ORBIT:
			# A closed ring with a mark on it: going round, and staying.
			canvas.draw_arc(at, size * 0.8, 0.0, TAU, 14, ink, 1.0)
			canvas.draw_rect(
				Rect2(at + Vector2(size * 0.8 - 1.0, -1.0), Vector2(2.0, 2.0)), ink
			)
		FlightAssists.Kind.DEORBIT:
			# The same ring, opened at the bottom and falling out of
			# itself: the orbit that no longer closes.
			canvas.draw_arc(at, size * 0.8, PI * 1.15, PI * 2.85, 12, ink, 1.0)
			canvas.draw_line(
				at + Vector2(0.0, size * 0.4), at + Vector2(0.0, size * 1.2), ink, 1.0
			)
		FlightAssists.Kind.LEVEL:
			# A horizon with the ship's own line square to it.
			canvas.draw_line(
				at + Vector2(-size, size * 0.4), at + Vector2(size, size * 0.4), ink, 1.0
			)
			canvas.draw_line(
				at + Vector2(0.0, size * 0.4), at + Vector2(0.0, -size * 0.6), ink, 1.0
			)
		FlightAssists.Kind.ALTITUDE:
			# A bar to hold and an arrow pointing at it from below, which
			# is the manoeuvre: stop falling, here.
			canvas.draw_line(
				at + Vector2(-size, -size * 0.6), at + Vector2(size, -size * 0.6), ink, 1.0
			)
			canvas.draw_line(
				at + Vector2(0.0, size), at + Vector2(0.0, -size * 0.3), ink, 1.0
			)
			for side: float in [-1.0, 1.0]:
				canvas.draw_line(
					at + Vector2(0.0, -size * 0.3),
					at + Vector2(side * size * 0.5, size * 0.2),
					ink,
					1.0,
				)
		FlightAssists.Kind.SPIN_KILL:
			# A turn with a bar across its head: the spin, stopped.
			canvas.draw_arc(at, size * 0.75, PI * 0.35, PI * 1.75, 10, ink, 1.0)
			var tip: Vector2 = at + Vector2.from_angle(PI * 0.35) * size * 0.75
			canvas.draw_line(
				tip + Vector2(-size * 0.45, -size * 0.45),
				tip + Vector2(size * 0.45, size * 0.45),
				ink,
				1.0,
			)


## An arrow along `way`, used for both heading holds so that prograde and
## retrograde are the same picture mirrored -- which is what they are.
static func _arrow(
	canvas: CanvasItem, at: Vector2, size: float, ink: Color, way: Vector2
) -> void:
	var tip: Vector2 = at + way * size
	canvas.draw_line(at - way * size, tip, ink, 1.0)
	var across: Vector2 = way.orthogonal() * size * 0.55
	canvas.draw_line(tip, tip - way * size * 0.6 + across, ink, 1.0)
	canvas.draw_line(tip, tip - way * size * 0.6 - across, ink, 1.0)
