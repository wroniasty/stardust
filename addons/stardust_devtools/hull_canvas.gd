@tool
class_name HullCanvas
extends HullView
## Plotno edytora kadluba: rysuje ksztalt i pozwala go ciagnac mysza.
##
## Drawing and mouse, and nothing else: what a point *means* lives in
## `HullHandles`, which file is open lives in the panel above, and where
## a point lands on screen lives in `HullView`. This deliberately knows
## nothing about the editor, so it can be put in a window, run with F6,
## or instantiated by the smoke test.
##
## A hull is about twenty-four pixels tall, so the view is zoomed hard by
## default and the grid is drawn in hull units rather than screen pixels.
## Coordinates on screen are only ever derived from hull coordinates --
## there is no second copy of a position to drift.

## Pushed before a change, so whoever owns the undo stack can snapshot the
## hull while it is still the old one.
signal about_to_change(note: String)

## And after, so the panel can mark the file dirty and recount.
signal changed()

## What the cursor is over, as a line of text for a status bar.
signal hovered(note: String)

## One colour per editable array, so the eye can tell a torque jet from a
## side gun without reading the label.
const PAINT: Dictionary = {
	&"outline": Color(0.62, 0.78, 1.0),
	&"legs": Color(0.76, 0.60, 0.96),
	&"drive_slots": Color(1.00, 0.55, 0.22),
	&"front_slots": Color(1.00, 0.86, 0.32),
	&"side_slots": Color(0.96, 0.72, 0.36),
	&"rear_slots": Color(0.92, 0.58, 0.44),
	&"torque_slots": Color(0.34, 0.88, 0.70),
	&"strafe_slots": Color(0.40, 0.74, 1.00),
	&"retro_slots": Color(1.00, 0.42, 0.60),
}

## The centre of mass, and the two things measured against it. Brighter
## than anything else on the canvas because they are the figures a hull
## is wrong about, and the ones a designer cannot see.
const BALANCE: Color = Color(1.0, 0.45, 0.35)
const BALANCE_OK: Color = Color(0.45, 0.95, 0.60)
const GROUND: Color = Color(0.60, 0.55, 0.45, 0.55)

## How far off each figure may be before it is drawn as wrong.
##
## Measured across the catalogue: the stock dart is 0.00 and 0.00, and it
## is the only hull that is. Half a pixel of arm is the point at which
## the residual side force stops being visible in flight.
const TORQUE_TOLERANCE: float = 0.5
const STRAFE_TOLERANCE: float = 0.5

## And how far below the hull's underside a foot may hang. Every shipped
## hull is 0 to 3 px; ten leaves the ship resting twenty-five px up.
const LEG_TOLERANCE: float = 6.0

const MIDDLE: Color = Color(1.0, 0.85, 0.4, 0.35)
const HULL_FILL: Color = Color(0.62, 0.78, 1.0, 0.10)

## How close the cursor has to be, in screen pixels, to grab something.
const GRAB_RADIUS: float = 9.0

## And how close to an edge a double click counts as "on the outline".
const EDGE_RADIUS: float = 8.0

## The step the grid and the drag both use. Quarters, because that is
## what the shipped hulls are written in (`-2.75`, `1.75`): a tool that
## snapped to whole pixels could not reproduce the files it edits.
const SNAP_STEP: float = 0.25

## How long the tick showing which way a mount faces is drawn, in pixels.
const FACING_TICK: float = 11.0

## The hull being edited. A loose copy owned by the panel: this draws and
## mutates it, and nothing on disk changes until someone presses save.
var hull: HullData = null

## Grid snapping. Hull positions in the shipped files are quarters
## (`-2.75`, `1.75`), so that is the step; holding Alt drags free.
var snapping: bool = true
var snap_step: float = SNAP_STEP

## The fitout the balance is measured with. A hull has no centre of
## mass on its own -- engines and modules are most of a ship's weight --
## so the figures are only meaningful against a fitout, and the dock says
## which one it used.
var reference: ShipPreset = null

## What `ShipFitout.balance_of` last said. Recomputed on every change,
## because every change can move it.
var balance: Dictionary = {}

var _handles: Array[Dictionary] = []
var _hover: int = -1
var _grabbed: int = -1
var _dragged: bool = false
var _panning: bool = false
var _last_mouse: Vector2 = Vector2.ZERO
## Whether the view is somebody's: panned or zoomed by hand. Until it
## is, the canvas reframes itself whenever it changes size, so a dock
## opened at one height and then dragged to another still shows the hull.
var _touched: bool = false


func _ready() -> void:
	super()
	refresh()


## The view is this canvas's once it has been panned or zoomed; until
## then it keeps reframing itself as the dock changes size.
func view_is_held() -> bool:
	return _touched


## What the view frames: every place the hull has, the nozzles bolted
## outside the outline included.
func framed_points() -> Array[Vector2]:
	var points: Array[Vector2] = []
	for handle: Dictionary in _handles:
		points.append(handle["at"])
	return points


## Put a hull on the canvas and frame it.
func show_hull(which: HullData) -> void:
	hull = which
	_hover = -1
	_grabbed = -1
	reframe()


## Re-read the hull. Called after anything changes it, including changes
## made somewhere other than here.
func refresh() -> void:
	# Same reason as in `HullHandles.of`: the empty branch of a ternary is
	# statically a plain Array, which an `Array[Dictionary]` refuses.
	_handles = []
	if hull != null:
		_handles = HullHandles.of(hull)
	balance = {}
	if hull != null:
		balance = ShipFitout.balance_of(hull, reference)
	queue_redraw()


## Frame the hull and hand the view back to the canvas, so it keeps
## following until somebody pans or zooms again.
func reframe() -> void:
	_touched = false
	refresh()
	fit()


## Add a point to one array, dropped in the middle of what that array
## already has, and grab it so the next drag places it.
func add_to(field: StringName) -> void:
	if hull == null:
		return
	var spec: Dictionary = HullHandles.spec_for(field)
	about_to_change.emit("dodaj %s" % spec.get("caption", field))
	var points: Array[Vector2] = HullHandles.shown(hull, field)
	var at: Vector2 = Vector2.ZERO
	if not points.is_empty():
		for point: Vector2 in points:
			at += point
		at /= float(points.size())
		at += Vector2(0.0, 2.0)
	HullHandles.add(hull, field, _snapped(at))
	refresh()
	changed.emit()


func _snapped(at: Vector2) -> Vector2:
	if not snapping or snap_step <= 0.0:
		return at
	return Vector2(snappedf(at.x, snap_step), snappedf(at.y, snap_step))


func _draw() -> void:
	draw_grid()
	if hull == null:
		return
	_draw_middle()
	_draw_ground()
	_draw_outline()
	_draw_legs()
	_draw_slots()
	_draw_balance()
	_draw_handles()


## The line that decides whether a torque jet is called Nose or Tail.
##
## It is the middle of the **bounding box**, not y = 0, and it moves when
## the outline is reshaped -- so without drawing it, pulling the nose
## forward can silently rename two jets and nobody would see why.
func _draw_middle() -> void:
	if hull.outline.is_empty():
		return
	var middle: float = hull.bounds().get_center().y
	var at: float = to_screen(Vector2(0.0, middle)).y
	# Faint, and labelled for what it actually decides. The first version
	# drew this as the only horizontal line on the canvas, brightly, and
	# the first thing anyone did with the dock was align the strafe pair
	# to it -- which is the one line those positions must **not** be
	# aligned to. What they answer to is the centre of mass, below.
	var dim: Color = MIDDLE
	dim.a *= 0.5
	draw_dashed_line(Vector2(0.0, at), Vector2(size.x, at), dim, 1.0, 3.0)
	var font: Font = get_theme_default_font()
	draw_string(
		font, Vector2(6.0, at - 3.0), "nose/tail, nazwy  y=%.2f" % middle,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 9, dim,
	)


func _draw_outline() -> void:
	var points: Array[Vector2] = HullHandles.shown(hull, &"outline")
	if points.size() < 2:
		return
	var screen: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in points:
		screen.append(to_screen(point))
	if screen.size() >= 3:
		draw_colored_polygon(screen, HULL_FILL)
	screen.append(screen[0])
	draw_polyline(screen, PAINT[&"outline"], 1.5)


## Feet get a short ground line, because a leg is a stance rather than a
## point: two legs at different heights is the thing worth seeing.
func _draw_legs() -> void:
	var tint: Color = PAINT[&"legs"]
	for at: Vector2 in HullHandles.shown(hull, &"legs"):
		var middle: Vector2 = to_screen(at)
		draw_line(middle + Vector2(-5.0, 0.0), middle + Vector2(5.0, 0.0), tint, 1.5)


func _draw_slots() -> void:
	for handle: Dictionary in _handles:
		var field: StringName = handle["field"]
		if field == &"outline" or field == &"legs":
			continue
		var tint: Color = PAINT[field]
		if handle["derived"]:
			tint.a = 0.38
		var at: Vector2 = to_screen(handle["at"])
		# Which way the mount points, from the game's own `turn`. The two
		# strafe thrusters cross -- the one that pushes left sits on the
		# right -- and this is where that stops being a surprise.
		var facing: Vector2 = Vector2.UP.rotated(handle["turn"])
		draw_line(at, at + facing * FACING_TICK, tint, 1.0)
		draw_circle(at, 3.0, tint)


## Every handle on top of everything else, so none is buried under the
## polygon it belongs to, and then the label for whichever one the cursor
## is on.
func _draw_handles() -> void:
	for i: int in range(_handles.size()):
		var handle: Dictionary = _handles[i]
		var field: StringName = handle["field"]
		var tint: Color = PAINT[field]
		if handle["derived"]:
			tint.a = 0.45
		var at: Vector2 = to_screen(handle["at"])
		var radius: float = 4.5 if i == _hover or i == _grabbed else 3.0
		if field == &"outline" or field == &"legs":
			draw_rect(Rect2(at - Vector2.ONE * radius, Vector2.ONE * radius * 2.0), tint)
		else:
			draw_arc(at, radius + 1.0, 0.0, TAU, 16, tint, 1.0)
	var picked: int = _grabbed if _grabbed >= 0 else _hover
	if picked < 0 or picked >= _handles.size():
		return
	var shown: Dictionary = _handles[picked]
	var font: Font = get_theme_default_font()
	var caption: String = "%s  (%.2f, %.2f)" % [
		shown["label"], (shown["at"] as Vector2).x, (shown["at"] as Vector2).y,
	]
	var anchor: Vector2 = to_screen(shown["at"]) + Vector2(9.0, -7.0)
	var width: float = font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11).x
	draw_rect(
		Rect2(anchor + Vector2(-3.0, -10.0), Vector2(width + 6.0, 15.0)),
		Color(0.0, 0.0, 0.0, 0.65),
	)
	draw_string(
		font, anchor, caption, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, PAINT[shown["field"]],
	)


func _gui_input(event: InputEvent) -> void:
	if hull == null:
		return
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null:
		_on_button(button)
		return
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null:
		_on_motion(motion)


func _on_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		if not event.pressed:
			return
		_touched = true
		zoom_about(
			event.position,
			1.12 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.12,
		)
		accept_event()
		return

	if event.button_index == MOUSE_BUTTON_MIDDLE:
		_panning = event.pressed
		_last_mouse = event.position
		accept_event()
		return

	if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_erase_under(event.position)
		accept_event()
		return

	if event.button_index != MOUSE_BUTTON_LEFT:
		return

	if not event.pressed:
		_grabbed = -1
		_dragged = false
		accept_event()
		return

	var under: int = HullHandles.nearest(_handles, to_hull(event.position), GRAB_RADIUS / _zoom)
	if event.double_click and under < 0:
		_insert_on_edge(event.position)
		accept_event()
		return
	_grabbed = under
	_dragged = false
	_hover = under
	queue_redraw()
	accept_event()


func _on_motion(event: InputEventMouseMotion) -> void:
	if _panning:
		_touched = true
		pan_by(event.relative)
		return

	if _grabbed >= 0:
		var handle: Dictionary = _handles[_grabbed]
		if not _dragged:
			# Snapshot once per drag, not once per pixel, or a single
			# nudge costs forty undos.
			about_to_change.emit("przesun %s" % handle["label"])
			_dragged = true
		var free: bool = event.alt_pressed
		var want: Vector2 = to_hull(event.position)
		if snapping and not free:
			want = _snapped(want)
		HullHandles.move(hull, handle["field"], handle["index"], want)
		refresh()
		# `refresh` rebuilt the list, and a derived kind that was just
		# written down now has the same indices -- but the labels may have
		# changed, which is the point of showing them live.
		changed.emit()
		_report(_grabbed)
		return

	var under: int = HullHandles.nearest(_handles, to_hull(event.position), GRAB_RADIUS / _zoom)
	if under != _hover:
		_hover = under
		_report(under)
		queue_redraw()


func _report(which: int) -> void:
	if which < 0 or which >= _handles.size():
		hovered.emit("LPM ciagnij  -  PPM usun  -  2x LPM na krawedzi: nowy wierzcholek  -  srodkowy: przesun widok  -  Alt: bez siatki")
		return
	var handle: Dictionary = _handles[which]
	var spec: Dictionary = HullHandles.spec_for(handle["field"])
	var at: Vector2 = handle["at"]
	hovered.emit("%s  %s  (%.2f, %.2f)%s" % [
		spec.get("caption", ""), handle["label"], at.x, at.y,
		"   [z wyliczenia - przeciagniecie zapisze caly komplet]" if handle["derived"] else "",
	])


func _erase_under(at: Vector2) -> void:
	var which: int = HullHandles.nearest(_handles, to_hull(at), GRAB_RADIUS / _zoom)
	if which < 0:
		return
	var handle: Dictionary = _handles[which]
	# Asked before the snapshot, so a refused removal does not leave a
	# step on the undo stack that goes back to where you already are.
	if not HullHandles.can_erase(hull, handle["field"], handle["index"]):
		hovered.emit("nie da sie usunac: %s to minimum" % handle["label"])
		return
	about_to_change.emit("usun %s" % handle["label"])
	HullHandles.erase(hull, handle["field"], handle["index"])
	_hover = -1
	_grabbed = -1
	refresh()
	changed.emit()


## A double click on the outline puts a vertex where the click landed,
## between the two it sits between -- so detail grows where it is wanted
## rather than at the end of the list.
func _insert_on_edge(at: Vector2) -> void:
	var want: Vector2 = to_hull(at)
	var found: Dictionary = HullHandles.nearest_edge(hull, want)
	if int(found["edge"]) < 0 or float(found["gap"]) * _zoom > EDGE_RADIUS:
		return
	about_to_change.emit("nowy wierzcholek")
	HullHandles.insert(hull, &"outline", int(found["edge"]) + 1, _snapped(want))
	refresh()
	changed.emit()


## Srodek masy, i te dwie rzeczy, ktore sie wzgledem niego mierzy.
##
## The line that matters. A torque jet's arm is its distance from **here**,
## not from the middle of the outline, and a strafe thruster makes no spin
## only when it sits on this line. Neither is visible without drawing it,
## which is how a hull with a 2.5 px strafe offset got saved.
func _draw_balance() -> void:
	if balance.is_empty():
		return
	var centre: Vector2 = balance["centre"]
	var at: Vector2 = to_screen(centre)
	draw_dashed_line(
		Vector2(0.0, at.y), Vector2(size.x, at.y), BALANCE, 1.0, 6.0,
	)
	# A crosshair, so the x of it is readable too: a hull whose weight is
	# off the centre line rolls under its own main drive.
	draw_line(at + Vector2(-6.0, 0.0), at + Vector2(6.0, 0.0), BALANCE, 1.5)
	draw_line(at + Vector2(0.0, -6.0), at + Vector2(0.0, 6.0), BALANCE, 1.5)
	var font: Font = get_theme_default_font()
	draw_string(
		font, Vector2(6.0, at.y - 4.0),
		"srodek masy  (%.2f, %.2f)" % [centre.x, centre.y],
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10, BALANCE,
	)

	# Each jet's and thruster's arm, drawn as the thing it is: the gap
	# between where it sits and the line it turns the ship about.
	_draw_arms(HullHandles.shown(hull, &"torque_slots"), centre,
			float(balance["torque_gap"]), TORQUE_TOLERANCE)
	_draw_arms(HullHandles.shown(hull, &"strafe_slots"), centre,
			float(balance["strafe_gap"]), STRAFE_TOLERANCE)


## A tick from each place to the centre-of-mass line, green while the
## figure is inside tolerance and red once it is not.
func _draw_arms(
	places: Array[Vector2], centre: Vector2, gap: float, tolerance: float
) -> void:
	var tint: Color = BALANCE_OK if gap <= tolerance else BALANCE
	tint.a = 0.8
	for place: Vector2 in places:
		var from: Vector2 = to_screen(place)
		draw_line(from, Vector2(from.x, to_screen(centre).y), tint, 1.0)


## Gdzie kadlub stanie, jesli nogi sa tam, gdzie sa.
##
## Two lines: the hull's own underside, and the lowest foot. The gap
## between them is how high the ship hovers, which is invisible in a
## polygon editor and was ten pixels on a hull saved from this dock.
func _draw_ground() -> void:
	if hull.outline.size() < 3:
		return
	var under: float = to_screen(Vector2(0.0, hull.bounds().end.y)).y
	draw_line(Vector2(0.0, under), Vector2(size.x, under), GROUND, 1.0)
	if hull.legs.is_empty():
		return
	var lowest: float = hull.legs[0].y
	for leg: Vector2 in hull.legs:
		lowest = maxf(lowest, leg.y)
	var floor_at: float = to_screen(Vector2(0.0, lowest)).y
	var drop: float = lowest - hull.bounds().end.y
	var tint: Color = GROUND if drop <= LEG_TOLERANCE else BALANCE
	draw_dashed_line(
		Vector2(0.0, floor_at), Vector2(size.x, floor_at), tint, 1.0, 2.0,
	)
	draw_string(
		get_theme_default_font(), Vector2(6.0, floor_at + 10.0),
		"grunt, %.1f px pod kadlubem" % drop,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 9, tint,
	)
