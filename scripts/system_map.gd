class_name SystemMap
extends CanvasLayer
## The system, seen from above. Key `M`.
##
## Drawn from the **model**, not from what happens to be in the scene. That
## is the whole reason it can exist: the streaming manager keeps one planet
## in the world at a time, and a map built from live nodes would show one
## dot and call it a system. `StarSystem` knows where everything is whether
## or not anything was built for it.
##
## Bodies are markers, not scale drawings. A system is a quarter of a
## million pixels across and a planet is two thousand, so a planet drawn to
## scale is a tenth of a pixel. Orbits are to scale, because the thing a
## map is for is knowing how far away something is.
##
## Names come on a click, the way the editor's schematic does it: a system
## with five planets, three moons and two docks is ten labels, and ten
## labels is a wall of text laid over the one line the pilot wanted.
##
## What this cannot do yet is zoom. A moon orbits a few thousand pixels
## out of a system a few hundred thousand across, so every satellite sits
## inside its planet's marker; clicking the planet names them, which says
## they are there without pretending to show them.

const FONT_SIZE: int = 8
const PAD: float = 8.0

## Nearly opaque, and that is not timidity about the art. The editor gets
## away with 0.72 because it lays solid panels over the world; a map is
## thin lines on a dark field, and at 0.86 the flight HUD read straight
## through it and the two sets of numbers fought.
const SCRIM: Color = Color(0.0, 0.0, 0.02, 0.96)
const ORBIT: Color = Color(0.24, 0.30, 0.40)
const LABEL: Color = Color(0.56, 0.63, 0.72)
const TEXT: Color = Color(0.78, 0.80, 0.83)
const PICK: Color = Color(1.00, 0.85, 0.35)
const SHIP: Color = Color(0.36, 0.92, 0.50)

## A body in the world right now is drawn brighter than one that is only in
## the model. Not decoration: it is the difference between a place you can
## fly into and a place that will be built when you get there, and it is
## the only window onto what the streaming manager is doing.
const LIVE: Color = Color(0.92, 0.94, 0.97)
const MODELLED: Color = Color(0.52, 0.56, 0.62)

## Marker sizes, by kind. A star is a disc, a planet a ring, a moon a small
## ring, a station a square: shapes rather than colours, because at eight
## pixels a colour is three pixels of it.
const STAR_SIZE: float = 5.0
const PLANET_SIZE: float = 3.5
const MOON_SIZE: float = 2.0
const STATION_SIZE: float = 2.0

## How close a click has to land to pick a body, in screen pixels.
const PICK_RADIUS: float = 9.0

var _system: StarSystem = null
var _ship: Node2D = null

## Who is streaming this system, if anyone. Handed in like everything else
## here -- the map asked for it by path in its first draft, which is the
## habit that put a planet a radian and a half off its orbit under
## `--script`. With no manager the map still draws, from the model alone.
var _manager: Node = null
var _canvas: Control = null
var _panel: Control = null
var _picked: SystemBody = null

func _ready() -> void:
	layer = 21
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_map)
	add_child(_canvas)
	_canvas.hide()


## What to draw and who is looking. Handed in rather than fetched: the
## manager is an autoload in the game and does not exist under `--script`.
func bind(system: StarSystem, ship: Node2D, manager: Node = null) -> void:
	_system = system
	_ship = ship
	_manager = manager


func is_open() -> bool:
	return _canvas.visible


func toggle() -> void:
	if is_open():
		close()
		return
	_canvas.show()
	# Exclusive: two paused panels stacked on each other is a trap, because
	# the lower one looks exactly like a panel that stopped taking input.
	PauseGate.hold_exclusive(self, get_tree())
	_canvas.queue_redraw()


func close() -> void:
	_canvas.hide()
	PauseGate.release(self, get_tree())


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_map"):
		toggle()
		get_viewport().set_input_as_handled()
	elif is_open() and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open():
		return
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	click_at(_canvas.get_global_mouse_position())
	_canvas.queue_redraw()
	get_viewport().set_input_as_handled()


## Picks whatever is nearest the point, or nothing.
##
## Works the layout out again rather than reading back where the last
## `_draw` put things. The ship editor was written the second way first
## and it made mouse input untestable and wrong before the first frame had
## been drawn; this is the same class and I wrote the same bug, so it is
## the same fix -- the layout is a function of the system and the viewport
## and nothing else.
func click_at(at: Vector2) -> SystemBody:
	if _system == null:
		return null
	var plan: Dictionary = layout(_canvas.size)
	var best: SystemBody = null
	var nearest: float = PICK_RADIUS
	for body: SystemBody in _system.bodies:
		var gap: float = at.distance_to(to_map(_position_of(body), plan))
		if gap < nearest:
			nearest = gap
			best = body
	_picked = best
	return best


func picked() -> SystemBody:
	return _picked


## Pixels of world per pixel of map, and where the star sits. A function of
## the system and the viewport only, so a click resolves without waiting
## for a frame to have been drawn -- the same reason the ship editor works
## this out rather than reading back what the last `_draw` left behind.
func layout(view: Vector2) -> Dictionary:
	var room: float = minf(view.x, view.y) * 0.5 - PAD * 3.0
	var reach: float = _system.outer_radius() if _system != null else 1.0
	return {
		"centre": view * 0.5,
		"scale": room / maxf(reach, 1.0),
		"turn": -_view_rotation(),
	}


## How the world is turned on screen right now.
##
## The map turns with it, so a direction on the map is the direction you
## would fly if you pointed the nose that way. A map with a fixed north is
## a map you have to do arithmetic on before it tells you anything, and the
## camera is already free to sit at any angle -- the arrows turn it, and
## the approach lock turns it for you on short finals.
func _view_rotation() -> float:
	var camera: Camera2D = get_viewport().get_camera_2d()
	return 0.0 if camera == null else camera.get_screen_rotation()


## The area the map is drawn into. Public because every coordinate here is
## relative to it, so a caller that wants to reason about the picture has
## to be working from the same rectangle the map is.
func view_size() -> Vector2:
	return _canvas.size


func to_map(point: Vector2, plan: Dictionary) -> Vector2:
	return Vector2(plan["centre"]) + point.rotated(float(plan["turn"])) * float(plan["scale"])


func _process(_delta: float) -> void:
	if is_open():
		_canvas.queue_redraw()


func _draw_map() -> void:
	if _system == null:
		return
	var view: Vector2 = _canvas.size
	_canvas.draw_rect(Rect2(Vector2.ZERO, view), SCRIM, true)
	var font: Font = ModuleData.card_font()
	var plan: Dictionary = layout(view)

	_text(font, Vector2(PAD, PAD + float(FONT_SIZE)), "UKŁAD %s" % _system.display_name, LABEL)
	_text(
		font, Vector2(PAD, view.y - PAD), "M zamyka,  klik wybiera ciało", LABEL
	)

	# Orbits first, so no marker is drawn under a line.
	for body: SystemBody in _system.bodies:
		if body.orbit_period <= 0.0 or body.parent_body() == null:
			continue
		# A ring is a circle whichever way the view is turned, so only its
		# centre has to turn with everything else.
		var around: Vector2 = to_map(_position_of(body.parent_body()), plan)
		var ring: float = body.orbit_radius * float(plan["scale"])
		if ring >= 1.0:
			# The chosen body's own ring is lit, because "which of these
			# five circles" is the question a marker alone cannot answer.
			_canvas.draw_arc(
				around, ring, 0.0, TAU, 64, PICK if body == _picked else ORBIT, 1.0
			)

	for body: SystemBody in _system.bodies:
		_draw_body(body, to_map(_position_of(body), plan))

	if _ship != null and is_instance_valid(_ship):
		_draw_ship(to_map(_ship.global_position, plan))

	_draw_readout(font, view)


## Where a body is this visit. Through the manager when there is one, so
## the map and the world cannot disagree about where anything is; from the
## body's own clock otherwise, which is what a test sees.
func _position_of(body: SystemBody) -> Vector2:
	if _manager != null and is_instance_valid(_manager):
		return _manager.position_of(body)
	return body.position_at(0.0)


## Whether this body is in the world right now, or only in the model.
func _is_live(body: SystemBody) -> bool:
	if _manager == null or not is_instance_valid(_manager):
		return false
	return _manager.node_for(body) != null


func _draw_body(body: SystemBody, at: Vector2) -> void:
	var colour: Color = LIVE if _is_live(body) else MODELLED
	if body == _picked:
		colour = PICK

	match body.kind:
		SystemBody.Kind.STAR:
			_canvas.draw_circle(at, STAR_SIZE, colour)
		SystemBody.Kind.PLANET:
			_canvas.draw_arc(at, PLANET_SIZE, 0.0, TAU, 16, colour, 1.0)
		SystemBody.Kind.MOON:
			_canvas.draw_arc(at, MOON_SIZE, 0.0, TAU, 12, colour, 1.0)
		_:
			_canvas.draw_rect(
				Rect2(at - Vector2(STATION_SIZE, STATION_SIZE), Vector2(STATION_SIZE, STATION_SIZE) * 2.0),
				colour,
				false,
				1.0,
			)


## The ship, as a cross rather than a dot: a dot at this scale is
## indistinguishable from a moon, and the one thing a pilot has to find on
## a map instantly is themselves.
func _draw_ship(at: Vector2) -> void:
	_canvas.draw_line(at - Vector2(4.0, 0.0), at + Vector2(4.0, 0.0), SHIP, 1.0)
	_canvas.draw_line(at - Vector2(0.0, 4.0), at + Vector2(0.0, 4.0), SHIP, 1.0)
	_canvas.draw_arc(at, 6.0, 0.0, TAU, 16, SHIP, 1.0)


## What is known about the body that was clicked. Nothing until one is,
## because a map that explains everything at once explains nothing.
func _draw_readout(font: Font, view: Vector2) -> void:
	if _picked == null:
		return
	var lines: PackedStringArray = PackedStringArray()
	lines.append("%s   %s" % [_picked.display_name, _picked.kind_name()])
	lines.append("promień      %8.0f px" % _picked.radius)
	if _picked.surface_gravity > 0.0:
		lines.append("grawitacja   %8.1f px/s2" % _picked.surface_gravity)
	if _picked.orbit_radius > 0.0:
		lines.append("orbita       %8.0f px" % _picked.orbit_radius)
		lines.append("rok          %8.0f s" % _picked.orbit_period)
	if _ship != null and is_instance_valid(_ship):
		lines.append("stąd         %8.0f px" % _ship.global_position.distance_to(
			_position_of(_picked)
		))
	# A moon orbits its planet at a few thousand pixels and the system is a
	# few hundred thousand across, so at this scale a satellite sits inside
	# its planet's own marker. Naming them is not a substitute for a zoom,
	# but it is the difference between "there is nothing there" and "there
	# is something there you cannot see yet".
	for child: SystemBody in _picked.children:
		lines.append("  %s %s" % [child.kind_name(), child.display_name])

	var y: float = PAD + float(FONT_SIZE) * 3.0
	for line: String in lines:
		_text(font, Vector2(view.x - PAD - _width(font, line), y), line, TEXT)
		y += float(FONT_SIZE) + 2.0


func _text(font: Font, at: Vector2, text: String, colour: Color) -> void:
	_canvas.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, colour)


func _width(font: Font, text: String) -> float:
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
