class_name UiFrame
extends RefCounted
## Where the four panels stand (UI_STYLE section 5).
##
## The middle of the screen belongs to the pilot. A 400x220 rectangle in
## the centre is untouchable: nothing goes in it but the one-pixel
## indicators drawn over the world itself, which are transparent and are
## about the view rather than laid on top of it.
##
## The four corners have fixed jobs, so the eye knows where to look
## without reading:
##
##     SHIP        what will kill me: hull, heat, power
##     WORLD       where I am: planet, orbit, apsides
##     CONTEXT     momentary: the lifted module, the mode, a message
##     INSTRUMENTS what I am doing now: ALT, V/S, SLOPE, GEAR
##
## **The two numbers in section 5 do not both fit, and this is where it
## shows.** A panel may be 140 by 120, and the untouchable field leaves
## 120 by 70 either side of it on a 640x360 screen. The field wins,
## because it is the one with a reason behind it -- a pilot flying at a
## cliff is looking at the middle -- so the panel maximum is a ceiling
## that is never reached today. It is kept rather than deleted because
## it is what a panel may grow to if the screen ever gets wider, and
## losing it would lose the distinction between "as much as there is"
## and "as much as is good for it".

## The pilot's own rectangle, in the middle, that no panel may cross.
const FIELD: Vector2 = Vector2(400.0, 220.0)

## Clear of the screen edge, and the ceiling on a panel's size.
const EDGE: float = 4.0
const MOST: Vector2 = Vector2(140.0, 120.0)

## Inside a panel: padding at the rim, and the step from row to row.
const PAD: float = 3.0
const ROW: float = 10.0

enum Slot { SHIP, WORLD, CONTEXT, INSTRUMENTS }


## The pilot's rectangle for this view. Public so a test can check that
## nothing is standing in it.
static func field(view: Vector2) -> Rect2:
	return Rect2((view - FIELD) * 0.5, FIELD)


## Where one panel goes. Snapped, like everything else that is drawn.
static func slot(view: Vector2, which: int) -> Rect2:
	var side: float = maxf((view.x - FIELD.x) * 0.5, EDGE * 2.0)
	var band: float = maxf((view.y - FIELD.y) * 0.5, EDGE * 2.0)
	var size: Vector2 = Vector2(
		minf(side - EDGE, MOST.x), minf(band - EDGE, MOST.y)
	).floor()
	var left: bool = which == Slot.SHIP or which == Slot.CONTEXT
	var top: bool = which == Slot.SHIP or which == Slot.WORLD
	return Rect2(
		Vector2(
			EDGE if left else view.x - EDGE - size.x,
			EDGE if top else view.y - EDGE - size.y,
		).round(),
		size,
	)


## Which corner of itself a panel puts its brackets on: the one facing
## the screen edge it is anchored to, so the four read as one ring.
static func corner(which: int) -> int:
	match which:
		Slot.SHIP:
			return UiDraw.Corner.TOP_LEFT
		Slot.WORLD:
			return UiDraw.Corner.TOP_RIGHT
		Slot.CONTEXT:
			return UiDraw.Corner.BOTTOM_LEFT
		_:
			return UiDraw.Corner.BOTTOM_RIGHT


## Where the rows start inside a panel, and how wide they are.
static func inside(box: Rect2) -> Rect2:
	return Rect2(box.position + Vector2(PAD, PAD), box.size - Vector2(PAD, PAD) * 2.0)
