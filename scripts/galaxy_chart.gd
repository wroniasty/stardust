class_name GalaxyChart
extends CanvasLayer
## The galaxy from outside, and only the part of it the pilot has any
## business knowing. Key `N`.
##
## One layer out from `SystemMap`: that draws a `StarSystem` in pixels,
## this draws `GalaxyMap` in light years, and the two never share a
## number. What makes them the same gesture is that both come off the
## **model** rather than off the scene. There is one system instantiated
## at a time and there never will be more, so a chart built from live
## nodes would be a chart of one dot.
##
## **Three things are visible and nothing else is**, which is the whole
## design of this screen:
##
## - systems the player has been in. Knowledge, written down in
##   `Galaxy.deltas`, and it never goes away.
## - systems the scanner reaches from where the ship stands right now.
##   Instrumentation, and it goes away when the ship moves.
## - the galactic core. Known by premise rather than earned: the game is
##   a flight inwards, and a chart that made the pilot discover which
##   way inwards is would be hiding the goal rather than the route.
##
## So the chart fills in as the game is played, and from the first frame
## of a new game it already says the one thing the premise needs it to:
## you are out here, the end is in there, everything between is dark.
##
## Everything is handed in rather than fetched, for the reason the jump
## HUD states at length: the galaxy is an autoload and does not exist
## under `--script`, and a screen that cannot be tested without a
## rendered frame is a screen with no tests.

const FONT_SIZE: int = 8
const PAD: float = 8.0

## How far the chart reaches from its middle, in light years, per step.
##
## Reaches rather than magnifications, the same decision `SystemMap`
## arrived at and for a weaker version of the same reason: a multiplier
## means nothing on its own, and these four numbers each mean something
## sayable. The whole galaxy with its rim inside the frame; a third of
## it; everywhere two jumps could take a starting drive; everywhere one
## could.
##
## The last is the view the pilot asked for -- "roughly this system and
## its neighbours" -- and it is `BASE_REACH` rather than a round number
## because a neighbour **is** something within one jump of the starting
## drive. A round number would mean one thing on this galaxy and
## something else after a change to the spacing.
const CHART_REACH: Array[float] = [
	GalaxyMap.RADIUS * 1.06,
	GalaxyMap.RADIUS * 0.5,
	GalaxyMap.BASE_REACH * 2.0,
	GalaxyMap.BASE_REACH,
]

## How far the middle of the view may wander from the middle of the
## galaxy. Far enough to put the rim comfortably on screen at any zoom,
## near enough that a long drag cannot lose the galaxy off the edge and
## leave the pilot looking at empty black with no way back.
const FOCUS_LEASH: float = GalaxyMap.RADIUS * 1.2

## How close a click has to land to pick a system, in screen pixels.
const PICK_RADIUS: float = 8.0

## How far the pointer may travel between press and release and still
## count as a click rather than a drag.
const DRAG_SLOP: float = 3.0

## Marker sizes. Shapes rather than colours tell these apart, because
## the palette's colours are roles and "visited" and "on the scanner"
## are the same role -- a system -- known two different ways.
const SEEN_SIZE: float = 1.5
const CONTACT_SIZE: float = 2.0
const GOAL_SIZE: float = 3.5
const HERE_SIZE: float = 4.0

## Above this reach, in light years, names stop being drawn.
##
## A hundred and eleven systems with names on a 640x360 field is one
## grey smear, and the fix for that is not smaller text. The current
## system, the core and whatever was clicked are named at every zoom,
## because those three are the chart answering a question rather than
## listing its contents.
const LABEL_REACH: float = GalaxyMap.BASE_REACH * 2.5

const DASH: float = 4.0
const DASH_GAP: float = 3.0

## Opacity of the sheet over the world, and of the readout panel on it.
## The chart pauses the game, so there is little reason to let the world
## through -- the lesson `SystemMap` records about 0.86 is that two sets
## of numbers then fight.
const SHEET: float = 0.96
const PANEL: float = 0.90

var _map: GalaxyMap = null
var _ship: Ship = null

## Who knows where the player has been. The galaxy autoload in the game,
## a bare instance of the same script in a test.
var _galaxy: Node = null

## Which system the ship is in, or -1 adrift between two.
var _here: int = 0

## And where it is in light years, which is the real address: a misjump
## leaves the ship somewhere `_here` cannot name, and the chart has to
## go on drawing.
var _at: Vector2 = Vector2.ZERO

var _canvas: Control = null

## Index into `CHART_REACH`. Kept across openings, like the system map's:
## it is a setting, not a state of the flight.
var _zoom: int = 0

## The light-year point in the middle of the view, and whether it is
## still tied to the ship. The wheel and a drag untie it; a click on
## empty space ties it back, which is the bargain the system map already
## makes and the only one that needs no second key to undo.
var _focus: Vector2 = Vector2.ZERO
var _focus_follows: bool = true

var _picked: int = -1

var _dragging: bool = false
var _drag_last: Vector2 = Vector2.ZERO
var _drag_travel: float = 0.0

var _ink: Palette = Palette.current()


func _ready() -> void:
	layer = 21
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_chart)
	add_child(_canvas)
	_canvas.hide()


func bind(
	map: GalaxyMap,
	ship: Ship,
	galaxy: Node = null,
	here: int = 0,
	at: Vector2 = Vector2.INF,
) -> void:
	_map = map
	_ship = ship
	_galaxy = galaxy
	_here = here
	if at != Vector2.INF:
		_at = at
	elif map != null and here >= 0 and here < map.count():
		_at = map.positions[here]
	_picked = -1


func is_open() -> bool:
	return _canvas.visible


func toggle() -> void:
	if is_open():
		close()
		return
	_canvas.show()
	PauseGate.hold_exclusive(self, get_tree())
	_canvas.queue_redraw()


func close() -> void:
	_canvas.hide()
	_dragging = false
	PauseGate.release(self, get_tree())


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_galaxy_map"):
		toggle()
		get_viewport().set_input_as_handled()
	elif not is_open():
		return
	elif event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"camera_zoom_in"):
		zoom_at(view_size() * 0.5, 1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"camera_zoom_out"):
		zoom_at(view_size() * 0.5, -1)
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open():
		return
	var moved: InputEventMouseMotion = event as InputEventMouseMotion
	if moved != null:
		drag_to(_canvas.get_global_mouse_position())
		return
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click == null:
		return
	if (
		click.button_index == MOUSE_BUTTON_WHEEL_UP
		or click.button_index == MOUSE_BUTTON_WHEEL_DOWN
	):
		if click.pressed:
			zoom_at(
				_canvas.get_global_mouse_position(),
				1 if click.button_index == MOUSE_BUTTON_WHEEL_UP else -1,
			)
		get_viewport().set_input_as_handled()
		return
	if click.button_index != MOUSE_BUTTON_LEFT:
		return
	if click.pressed:
		drag_from(_canvas.get_global_mouse_position())
	else:
		drag_end(_canvas.get_global_mouse_position())
	get_viewport().set_input_as_handled()


## Press, move, release: one gesture that turns out to be a pan or a
## pick depending on how far it travelled.
##
## Two gestures on one button, which is worth the small machinery
## because both alternatives are worse. A separate pan button is a
## button nobody finds, and a pan on the right button collides with the
## pin the system map already put there. The slop is what stops a click
## becoming a one-pixel pan when a hand is not quite still.
##
## Public, all three, because this is the half of the screen a test can
## reach: there is no mouse under `--script`, but there is a press, a
## move and a release.
func drag_from(at: Vector2) -> void:
	_dragging = true
	_drag_last = at
	_drag_travel = 0.0


func drag_to(at: Vector2) -> void:
	if not _dragging:
		return
	var by: Vector2 = at - _drag_last
	_drag_last = at
	_drag_travel += by.length()
	if _drag_travel > DRAG_SLOP:
		pan_by(by)


func drag_end(at: Vector2) -> void:
	drag_to(at)
	var was_drag: bool = _drag_travel > DRAG_SLOP
	_dragging = false
	if not was_drag:
		click_at(at)
	_canvas.queue_redraw()


## Slides the view. `by` is in screen pixels, the way a hand moves.
func pan_by(by: Vector2) -> void:
	if by.is_zero_approx():
		return
	var plan: Dictionary = layout(view_size())
	_focus_follows = false
	_focus = _hold(
		Vector2(plan["focus"])
		- by.rotated(-float(plan["turn"])) / maxf(float(plan["scale"]), 0.000001)
	)
	_canvas.queue_redraw()


## Steps the zoom, keeping whatever is under the cursor under the
## cursor. The arithmetic is the inverse transform read twice, exactly
## as the system map does it, and the early return matters for the same
## reason: without it, leaning on the wheel at the end of the ladder
## would drag the view sideways while the scale stood still.
func zoom_at(at: Vector2, by: int) -> void:
	var was: int = _zoom
	var world: Vector2 = from_chart(at, layout(view_size()))
	set_zoom_level(_zoom + by)
	if _zoom == was:
		return
	var plan: Dictionary = layout(view_size())
	_focus_follows = false
	_focus = _hold(world - (at - Vector2(plan["centre"])).rotated(
		-float(plan["turn"])
	) / maxf(float(plan["scale"]), 0.000001))
	_canvas.queue_redraw()


func set_zoom_level(level: int) -> void:
	_zoom = clampi(level, 0, CHART_REACH.size() - 1)
	_canvas.queue_redraw()


func zoom_level() -> int:
	return _zoom


## The middle of the view, kept on a leash round the galaxy.
func _hold(point: Vector2) -> Vector2:
	return point.limit_length(FOCUS_LEASH)


func view_size() -> Vector2:
	return _canvas.size


## Light years per pixel, which way is up, and what is in the middle. A
## function of the chart's state and the viewport and nothing else, so a
## click resolves before a frame has been drawn.
func layout(view: Vector2) -> Dictionary:
	var room: float = minf(view.x, view.y) * 0.5 - PAD * 3.0
	var reach: float = CHART_REACH[clampi(_zoom, 0, CHART_REACH.size() - 1)]
	return {
		"centre": view * 0.5,
		"scale": room / maxf(reach, 0.0001),
		"reach": reach,
		"turn": -_view_rotation(),
		"focus": _homed() if _focus_follows else _focus,
	}


## What the chart centres on until the pilot says otherwise: the ship,
## except at the widest rung, where it is the galaxy.
##
## The widest rung reaches just past the rim, and a reach like that
## centred on a ship **at** the rim leaves half the galaxy off the side.
## Showing the whole thing is the only job that rung has. Every tighter
## one is about where you are, which is the only thing those are for.
func _homed() -> Vector2:
	return Vector2.ZERO if _zoom == 0 else _at


## The chart turns with the world, like the system map and for a
## stronger reason: the galaxy and the system are the same plane
## (IDEAS.md section 10), so a direction on this chart is the direction
## to point the nose in. A fixed north here would be a chart you have to
## do arithmetic on before it tells you which way the core is.
func _view_rotation() -> float:
	var camera: Camera2D = get_viewport().get_camera_2d() if is_inside_tree() else null
	return 0.0 if camera == null else camera.get_screen_rotation()


func to_chart(point: Vector2, plan: Dictionary) -> Vector2:
	var out: Vector2 = point - Vector2(plan["focus"])
	return Vector2(plan["centre"]) + out.rotated(float(plan["turn"])) * float(plan["scale"])


## `to_chart` read backwards. Written as the exact inverse rather than
## derived a second time, so a change to one that is not mirrored in the
## other shows up as a round trip that does not close.
func from_chart(at: Vector2, plan: Dictionary) -> Vector2:
	var from_centre: Vector2 = at - Vector2(plan["centre"])
	return Vector2(plan["focus"]) + from_centre.rotated(
		-float(plan["turn"])
	) / maxf(float(plan["scale"]), 0.000001)


## What the chart shows, as data: one entry per system that is on it at
## all, and why it is on it.
##
## The knowledge rule in one function, so the drawing cannot quietly
## widen it and a test can read it without a frame. A system can qualify
## three ways at once -- the core is a place you eventually fly to --
## which is why these are flags rather than one kind.
func charted() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _map == null:
		return out
	var goal: int = _map.centre_index()
	var contacts: Dictionary = {}
	# The scanner is the outward-looking one, the same module the jump
	# HUD reads, and it works here whether or not the star is holding
	# the ship down. A mass lock stops a jump, not a sensor; the HUD
	# goes quiet inside one because its markers are targets, and a chart
	# is not a target.
	var eyes: ScannerData = (
		_ship.scanner() if _ship != null and is_instance_valid(_ship) else null
	)
	if eyes != null:
		for index: int in _map.within(_at, eyes.reach):
			contacts[index] = true
	for index: int in range(_map.count()):
		var visited: bool = has_visited(index)
		var contact: bool = contacts.has(index)
		if not (visited or contact or index == goal):
			continue
		out.append({
			"index": index,
			"at": _map.positions[index],
			"visited": visited,
			"contact": contact,
			"goal": index == goal,
			"here": index == _here,
			"tier": _map.tier_of(index),
			"distance": _at.distance_to(_map.positions[index]),
		})
	return out


## Whether the player has been here. The system the ship is in counts
## without being written down anywhere, which is one rule instead of a
## write on every arrival path and a bug on the one that was missed.
func has_visited(index: int) -> bool:
	if index == _here:
		return true
	if _galaxy == null or not _galaxy.has_method("has_visited"):
		return false
	return bool(_galaxy.has_visited(index))


## What a system is called, or an empty string when that is not known.
##
## Visited is the whole name; a scanner contact is named only if the
## scanner reads class or better, which is the rule the jump HUD's
## labels already follow. Unknown is **nothing**, not "???" -- a chart
## with eleven question marks on it has drawn eleven things it does not
## know.
func name_of(index: int) -> String:
	if _map == null or index < 0 or index >= _map.count():
		return ""
	if index == _map.centre_index() and not has_visited(index):
		return "core"
	var eyes: ScannerData = (
		_ship.scanner() if _ship != null and is_instance_valid(_ship) else null
	)
	var reads: bool = eyes != null and eyes.knows(ScannerData.Depth.CLASS)
	if not (has_visited(index) or reads):
		return ""
	if _galaxy == null or not _galaxy.has_method("system"):
		return ""
	var system: StarSystem = _galaxy.system(index) as StarSystem
	return "" if system == null else system.display_name


## Picks the system nearest the point, or nothing. Works the layout out
## again rather than reading back where the last frame put things.
func click_at(at: Vector2) -> int:
	_picked = -1
	if _map == null:
		return -1
	var plan: Dictionary = layout(view_size())
	var nearest: float = PICK_RADIUS
	for entry: Dictionary in charted():
		var gap: float = at.distance_to(to_chart(entry["at"], plan))
		if gap < nearest:
			nearest = gap
			_picked = int(entry["index"])
	# A click on nothing is how a pilot says "never mind" and gets the
	# ship back in the middle.
	if _picked < 0:
		_focus_follows = true
	return _picked


func picked() -> int:
	return _picked


func _process(_delta: float) -> void:
	if is_open():
		_canvas.queue_redraw()


func _draw_chart() -> void:
	if _map == null:
		return
	var view: Vector2 = _canvas.size
	_canvas.draw_rect(Rect2(Vector2.ZERO, view), _ink.over(_ink.scrim, SHEET), true)
	var font: Font = UiFont.face()
	var plan: Dictionary = layout(view)

	_draw_bands(plan)
	_draw_range(plan)

	var listed: Array[Dictionary] = charted()
	for entry: Dictionary in listed:
		_draw_system(entry, plan)
	for entry: Dictionary in listed:
		_draw_name(font, entry, plan)

	_draw_heading(font, view, plan)
	_draw_readout(font, view)


## The tiers, as the rings they are.
##
## A tier is a band of radius and nothing else, so drawing it as
## anything but concentric circles would be inventing a second idea.
## Ten faint rings also do the job a legend would: the pilot can see
## that the bands are even and that the core is one small circle, which
## is the shape of the whole game.
func _draw_bands(plan: Dictionary) -> void:
	var middle: Vector2 = to_chart(Vector2.ZERO, plan)
	var scale: float = float(plan["scale"])
	for band: int in range(1, GalaxyMap.TIERS + 1):
		var ring: float = GalaxyMap.RADIUS * float(band) / float(GalaxyMap.TIERS) * scale
		if ring < 6.0:
			continue
		var rim: bool = band == GalaxyMap.TIERS
		_canvas.draw_arc(
			middle, ring, 0.0, TAU, 96,
			_ink.edge if rim else _ink.over(_ink.grid, 0.30),
			1.0,
		)


## How far one jump goes from where the ship stands, dashed.
##
## The one circle on this chart that is about leaving rather than about
## where things are, which is the job the mass lock ring does on the
## system map -- and dashed for that reason, so it reads as a boundary
## and not as a thing in the galaxy.
func _draw_range(plan: Dictionary) -> void:
	var drive: JumpDriveData = (
		_ship.jump_drive() if _ship != null and is_instance_valid(_ship) else null
	)
	if drive == null:
		return
	var ring: float = drive.reach * float(plan["scale"])
	if ring < 4.0:
		return
	_dashed_ring(to_chart(_at, plan), ring, _ink.over(_ink.grid, 0.8))


func _draw_system(entry: Dictionary, plan: Dictionary) -> void:
	var at: Vector2 = UiDraw.snap(to_chart(entry["at"], plan))
	var index: int = int(entry["index"])
	if bool(entry["goal"]):
		# A ring round the end of the road, drawn whether or not
		# anything is known about what is in it.
		# Wider than the ship's own ring rather than the same size: two
		# shapes in two rings of one radius read as one symbol twice, and
		# these two are the ends of the journey.
		_canvas.draw_arc(at, GOAL_SIZE + 4.0, 0.0, TAU, 24, _ink.value, 1.0)
		_diamond(at, GOAL_SIZE, _ink.value)
	elif bool(entry["visited"]):
		# A filled square: somewhere that is a fact.
		_canvas.draw_rect(
			Rect2(at - Vector2(SEEN_SIZE, SEEN_SIZE), Vector2(SEEN_SIZE, SEEN_SIZE) * 2.0),
			_ink.value,
			true,
		)
	else:
		# A hollow diamond: somewhere the scanner can see and nobody has
		# been. Hollow because that is exactly what is being said.
		_diamond(at, CONTACT_SIZE, _ink.nav)

	if index == _picked:
		UiDraw.bracket(
			_canvas,
			Rect2(at - Vector2(5.0, 5.0), Vector2(10.0, 10.0)),
			_ink.caution,
			3.0,
		)
	if bool(entry["here"]):
		_draw_here(at)


## The ship, as the cross in a circle it is on the system map. The one
## thing a pilot has to find instantly is themselves, and the shape that
## means that should not change between two screens.
func _draw_here(at: Vector2) -> void:
	_canvas.draw_line(
		at - Vector2(HERE_SIZE, 0.0), at + Vector2(HERE_SIZE, 0.0), _ink.accent, 1.0
	)
	_canvas.draw_line(
		at - Vector2(0.0, HERE_SIZE), at + Vector2(0.0, HERE_SIZE), _ink.accent, 1.0
	)
	_canvas.draw_arc(at, HERE_SIZE + 2.0, 0.0, TAU, 16, _ink.accent, 1.0)


func _diamond(at: Vector2, size: float, ink: Color) -> void:
	var points: PackedVector2Array = PackedVector2Array([
		at + Vector2(0.0, -size),
		at + Vector2(size, 0.0),
		at + Vector2(0.0, size),
		at + Vector2(-size, 0.0),
		at + Vector2(0.0, -size),
	])
	for step: int in range(1, points.size()):
		_canvas.draw_line(points[step - 1], points[step], ink, 1.0)


## A name beside a mark, when there is a reason for one. The current
## system, the core and the clicked one are named at every zoom; the
## rest only once the chart is close enough that the names do not land
## on each other.
func _draw_name(font: Font, entry: Dictionary, plan: Dictionary) -> void:
	var index: int = int(entry["index"])
	var always: bool = bool(entry["here"]) or bool(entry["goal"]) or index == _picked
	if not always and float(plan["reach"]) > LABEL_REACH:
		return
	var text: String = name_of(index)
	if text.is_empty():
		return
	# Clear of the widest mark here, which is the ring round the core:
	# a name touching the circle it belongs to reads as part of it.
	var at: Vector2 = UiDraw.snap(to_chart(entry["at"], plan) + Vector2(10.0, 3.0))
	var ink: Color = _ink.label
	if index == _picked:
		ink = _ink.caution
	elif bool(entry["here"]):
		ink = _ink.accent
	elif bool(entry["visited"]):
		ink = _ink.value
	_canvas.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, ink)


## Where the pilot is, where the game is going, and what the chart is
## showing. The middle line is the premise.
func _draw_heading(font: Font, view: Vector2, plan: Dictionary) -> void:
	var line: float = PAD + float(FONT_SIZE)
	_text(font, Vector2(PAD, line), "GALAXY CHART", _ink.label)
	var home: String = "adrift" if _here < 0 else name_of(_here)
	if home.is_empty():
		home = "unknown"
	_text(
		font,
		Vector2(PAD, line + float(FONT_SIZE) * 1.5),
		"here  %s   tier %d of %d" % [home, tier_here(), GalaxyMap.TIERS],
		_ink.value,
	)
	var core: int = _map.centre_index()
	_text(
		font,
		Vector2(PAD, line + float(FONT_SIZE) * 3.0),
		(
			"core  %.1f ly" % _at.distance_to(_map.positions[core]) if core >= 0
			else "core  --"
		),
		_ink.label,
	)
	_text(
		font,
		Vector2(PAD, line + float(FONT_SIZE) * 4.5),
		"reach %.0f ly" % float(plan["reach"]),
		_ink.label,
	)
	_text(
		font,
		Vector2(PAD, view.y - PAD),
		"N closes,  drag moves,  wheel or + / - zooms,  click reads",
		_ink.label,
	)


## The band the ship is in, which is a question about a place rather
## than about a system: a tier is a radius, so a ship adrift between two
## systems has one as surely as a system does.
func tier_here() -> int:
	if _map != null and _here >= 0:
		return _map.tier_of(_here)
	var out: float = _at.length() / maxf(GalaxyMap.RADIUS, 0.0001)
	return GalaxyMap.TIERS - clampi(
		int(out * float(GalaxyMap.TIERS)), 0, GalaxyMap.TIERS - 1
	)


## What is known about the clicked system. Nothing until one is clicked,
## because a chart that explains everything at once explains nothing.
func _draw_readout(font: Font, view: Vector2) -> void:
	if _picked < 0 or _picked >= _map.count():
		return
	var away: float = _at.distance_to(_map.positions[_picked])
	var text: String = name_of(_picked)
	var rows: Array[Array] = [
		["system", text if not text.is_empty() else "unknown", ""],
		["tier", "%d" % _map.tier_of(_picked), ""],
		["range", "%.1f" % away, "ly"],
		["been", "yes" if has_visited(_picked) else "no", ""],
	]
	var drive: JumpDriveData = (
		_ship.jump_drive() if _ship != null and is_instance_valid(_ship) else null
	)
	if drive != null:
		if drive.can_cross(away):
			rows.append(["fuel", "%.0f" % drive.fuel_for(away, _ship.mass), ""])
		else:
			rows.append(["jump", "too far", ""])

	var width: float = 104.0
	var high: float = float(FONT_SIZE) * float(rows.size()) + 10.0
	var box: Rect2 = Rect2(
		Vector2(view.x - PAD - width, view.y - PAD - high), Vector2(width, high)
	)
	UiDraw.panel(
		_canvas,
		box,
		_ink.over(_ink.panel, PANEL),
		_ink.edge,
		UiDraw.Corner.BOTTOM_RIGHT,
	)
	var y: float = box.position.y + float(FONT_SIZE) + 2.0
	for entry: Array in rows:
		UiDraw.row(
			_canvas,
			font,
			Vector2(box.position.x + UiDraw.PAD, y),
			width - UiDraw.PAD * 2.0,
			String(entry[0]),
			String(entry[1]),
			_ink.value,
			_ink.label,
			String(entry[2]),
		)
		y += float(FONT_SIZE)


func _dashed_ring(at: Vector2, radius: float, ink: Color) -> void:
	var step: float = DASH / maxf(radius, 1.0)
	var gap: float = DASH_GAP / maxf(radius, 1.0)
	var angle: float = 0.0
	while angle < TAU:
		var to: float = minf(angle + step, TAU)
		_canvas.draw_arc(at, radius, angle, to, 3, ink, 1.0)
		angle = to + gap


func _text(font: Font, at: Vector2, text: String, ink: Color) -> void:
	_canvas.draw_string(
		font, UiDraw.snap(at), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, ink
	)
