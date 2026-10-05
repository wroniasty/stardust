class_name UiDraw
extends RefCounted
## The primitives every screen is drawn out of (UI_STYLE section 6).
##
## Static and stateless on purpose: this is a vocabulary, not a set of
## objects. A seventh primitive is supposed to cost a change to UI_STYLE
## before it costs a change here, which is the whole point of the list
## being six long.
##
## **Everything snaps on the way in**, which is UI_STYLE section 2 and
## not a preference. The interface stands at scale 1.0 on a 640x360
## canvas the window magnifies by whole numbers, so a design pixel
## really is a pixel, and a coordinate with a fraction in it rasterises
## differently from one frame to the next. That is not theory either:
## the orbit instrument's apsis dots were reported as flickering and
## half the cause was exactly this rule being applied late.

## Width of the label column in a reading row.
##
## Fixed, because a value that slides left when it gains a digit is a
## value the eye has to find again every time it reads it.
const LABEL_WIDTH: float = 34.0

## Padding inside a panel, and the arm of a corner bracket.
const PAD: float = 3.0
const BRACKET_ARM: float = 4.0

## How fast an alarm pulses, in hertz.
##
## Square wave at half duty, never a sine: a sine spends most of its
## time part-lit, which reads as something fading rather than as
## something wrong. Two hertz because slower looks like a slow fade and
## faster looks like a fault in the screen.
const PULSE_HZ: float = 2.0

## Which screen edge a panel is anchored to. The brackets go on that
## side, so the four panels read as pieces of one ring round the pilot's
## field rather than as four boxes dropped on the view.
## Taken as a plain `int` by `panel` rather than as this type: an enum
## put into an untyped container comes back out an int, and the static
## checker will not hand it back, so a caller with a table of panels
## cannot pass one. The name is still worth having at the call site.
enum Corner { TOP_LEFT, TOP_RIGHT, BOTTOM_LEFT, BOTTOM_RIGHT }


## Whole pixels. Called at the top of every helper here rather than left
## to the caller, because the one time it is forgotten is the time it
## matters.
static func snap(at: Vector2) -> Vector2:
	return at.round()


static func snap_rect(box: Rect2) -> Rect2:
	return Rect2(box.position.round(), box.size.round())


## Whether an alarm is in its lit half this instant.
##
## Off the engine clock rather than off a counter each caller keeps, so
## every warning on screen pulses **together**. Two alarms out of phase
## read as two separate things going wrong, which is a lie the interface
## should not be able to tell by accident.
##
## The clock keeps running while the tree is paused, deliberately: the
## HUD goes on drawing through a pause and a warning that froze
## half-lit would read as a stuck screen.
static func pulse() -> bool:
	return fmod(float(Time.get_ticks_msec()) * 0.001 * PULSE_HZ, 1.0) < 0.5


## A reading row: the label in dim ink on the left, the value hard
## against the right of the row, the unit after it in dim.
##
## Eighty per cent of the interface is this, and it is meant to be
## boring. The value carries the state in its colour; nothing else in
## the row changes.
static func row(
	canvas: CanvasItem,
	font: Font,
	at: Vector2,
	width: float,
	label: String,
	value: String,
	ink: Color,
	dim: Color,
	unit: String = "",
) -> void:
	if canvas == null or font == null:
		return
	var corner: Vector2 = snap(at)
	canvas.draw_string(
		font, corner, label, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.BODY, dim
	)
	var unit_width: float = 0.0 if unit.is_empty() else text_width(font, " " + unit)
	var right: float = corner.x + width - unit_width
	# The floor is the label's own width rather than the column width.
	# A fixed floor is what pushed a six-character value off the side of
	# a 60 px panel: the value is right-aligned, which is the rule that
	# matters, and the column only has to stop the two colliding.
	var at_value: float = maxf(
		right - text_width(font, value),
		corner.x + text_width(font, label) + 3.0,
	)
	canvas.draw_string(
		font, snap(Vector2(at_value, corner.y)), value,
		HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.BODY, ink,
	)
	if unit.is_empty():
		return
	canvas.draw_string(
		font, snap(Vector2(right, corner.y)), " " + unit,
		HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.BODY, dim,
	)


## Four corner brackets, never a full rectangle.
##
## Eight strokes where a frame spends four whole lines of the visual
## budget to say the same thing. Used for a target, a chosen slot, a
## crate on screen -- anything the eye has to find rather than read.
static func bracket(
	canvas: CanvasItem, box: Rect2, ink: Color, arm: float = BRACKET_ARM
) -> void:
	if canvas == null:
		return
	var at: Rect2 = snap_rect(box)
	for corner: Vector2 in [
		at.position,
		Vector2(at.end.x, at.position.y),
		Vector2(at.position.x, at.end.y),
		at.end,
	]:
		var inward: Vector2 = Vector2(
			1.0 if corner.x <= at.get_center().x else -1.0,
			1.0 if corner.y <= at.get_center().y else -1.0,
		)
		canvas.draw_line(corner, corner + Vector2(inward.x * arm, 0.0), ink, 1.0)
		canvas.draw_line(corner, corner + Vector2(0.0, inward.y * arm), ink, 1.0)


## A panel: a dimmed ground, and brackets on the two corners facing the
## screen edge it is anchored to.
##
## No border on four sides, with one exception the caller asks for:
## `edged` is for the flight instruments bottom right, which at landing
## lie over the messiest background the game owns. Everywhere else a
## full frame is four lines spent saying what two corners already said.
static func panel(
	canvas: CanvasItem,
	box: Rect2,
	fill: Color,
	ink: Color,
	corner: int,
	edged: bool = false,
) -> void:
	if canvas == null:
		return
	var at: Rect2 = snap_rect(box)
	canvas.draw_rect(at, fill, true)
	if edged:
		canvas.draw_rect(at, ink, false, 1.0)
		return

	# The two corners on the anchored edge: a panel in the top left
	# belongs to the top of the screen, so its brackets sit on its top
	# two corners and the four panels read as one ring round the
	# pilot's field rather than as four boxes dropped on the view.
	var top: bool = corner == Corner.TOP_LEFT or corner == Corner.TOP_RIGHT
	var y: float = at.position.y if top else at.end.y
	var step: float = 1.0 if top else -1.0
	for x: float in [at.position.x, at.end.x]:
		var inward: float = 1.0 if x <= at.get_center().x else -1.0
		canvas.draw_line(
			Vector2(x, y), Vector2(x + inward * BRACKET_ARM, y), ink, 1.0
		)
		canvas.draw_line(
			Vector2(x, y), Vector2(x, y + step * BRACKET_ARM), ink, 1.0
		)


static func text_width(font: Font, text: String) -> float:
	if font == null:
		return 0.0
	return font.get_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.BODY
	).x
