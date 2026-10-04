class_name JumpHud
extends CanvasLayer
## Other systems at the edge of the screen: where they are, whether you can
## get there, and what is known about them.
##
## The outward-looking half of the instrumentation. `ScannerHud` answers
## "what is around me in this system" in pixels; this answers "where else
## could I be" in light years, and the two never share a number.
##
## It works at all because of the one decision IDEAS.md section 10 rests
## on: the galaxy and the system are the same plane. A system to the
## north-east on the map is north-east out of the window, so a marker on
## the edge of the screen is a heading, not a symbol -- point the nose at
## it and fly.
##
## **Three separate things decide what a pilot sees here**, and keeping
## them apart is the point of the whole module split:
##
## - the scanner's reach decides which systems appear at all,
## - the scanner's depth decides how much is written under them,
## - the drive's reach and what is in the tank decide their colour.
##
## So a long cheap scanner shows a lot of unlabelled dots, and a good one
## bolted to a short drive shows a lot of grey ones. That is what makes a
## better drive buy somewhere to go.
##
## Everything is handed in rather than fetched, for the same reason the
## system map learned to: the galaxy is an autoload and does not exist
## under `--script`, and a HUD that cannot be tested without a rendered
## frame is a HUD with no tests.

## How far in from the edge the ring of markers sits. Enough for the
## selection ring as well as the chevron, which the first pass was not.
const RING_MARGIN: float = 14.0

## Half-size of a marker. Small: this shares an edge with the scanner's
## own contacts and must not shout over them.
const MARKER: float = 2.6

## Most systems marked at once, nearest first.
##
## The same rule the loot markers learned: a scanner that draws every
## contact turns the edge of the screen into a picket fence, and nine
## names around a 640x360 frame overlap into one grey smear. The ones
## left out are the far ones, which are also the ones a pilot is least
## likely to be choosing between right now.
const MOST_SHOWN: int = 6

const FONT_SIZE: int = 8

var _ship: Ship = null
var _system: StarSystem = null
var _map: GalaxyMap = null
var _here: int = 0

## Where the ship is in the galaxy. The real address, because a misjump
## can leave it somewhere `_here` cannot name.
var _at: Vector2 = Vector2.ZERO

## Who can turn an index into a system. The galaxy autoload in the game,
## a bare instance of the same script in a test -- handed in, because
## fetching it by path is the habit this file's own docstring warns
## about and the one that would make the labels untestable.
var _galaxy: Node = null

## Who decides what the nose is on. The HUD used to work it out itself,
## through the canvas transform, which gave the right answer for the
## wrong reason: aiming is a question about two headings in the world
## and the camera has nothing to say about it. The machine that acts on
## the answer should be the one that has it.
var _jump: JumpController = null
var _canvas: Control = null

var _ink: Palette = Palette.current()


func _ready() -> void:
	layer = 9
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_markers)
	add_child(_canvas)


func bind(
	ship: Ship,
	system: StarSystem,
	map: GalaxyMap,
	here: int,
	galaxy: Node = null,
	jump: JumpController = null,
	at: Vector2 = Vector2.INF,
) -> void:
	_ship = ship
	_system = system
	_map = map
	_here = here
	_galaxy = galaxy
	_jump = jump
	if at != Vector2.INF:
		_at = at
	elif map != null and here >= 0 and here < map.count():
		_at = map.positions[here]


func _process(_delta: float) -> void:
	if _canvas != null:
		_canvas.queue_redraw()


## Why there is nothing to show, or an empty string when there is.
##
## Three distinguishable answers rather than a blank screen. A HUD that
## draws nothing when the scanner is missing, nothing when the star is
## holding you down and nothing when there is genuinely nowhere to go has
## told the pilot the same thing three times and meant something
## different each time.
func silence() -> String:
	if _ship == null or not is_instance_valid(_ship):
		return "no ship"
	if _ship.scanner() == null:
		return "no scanner"
	if _system != null and _system.is_mass_locked(_ship.global_position):
		return "mass lock  %.0f px" % _system.jump_clearance(_ship.global_position)
	return ""


## What the jump scanner would draw, as data.
##
## A pure function of its arguments, like `ScannerHud.contacts()`: the
## transform carries the camera's position, zoom and rotation, so a
## heading worked out by hand in world space cannot quietly disagree with
## where the marker lands.
func contacts(to_screen: Transform2D, view: Vector2) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if not silence().is_empty() or _map == null:
		return found

	var eyes: ScannerData = _ship.scanner()
	var drive: JumpDriveData = _ship.jump_drive()
	var centre: Vector2 = view * 0.5
	var extent: Vector2 = centre - Vector2(RING_MARGIN, RING_MARGIN)
	if extent.x <= 0.0 or extent.y <= 0.0:
		return found

	var home: Vector2 = _at
	for index: int in _map.within(home, eyes.reach):
		if index == _here or found.size() >= MOST_SHOWN:
			continue
		# The galaxy's direction is the world's direction; the transform
		# turns it into the screen's. Scale falls out in the normalise,
		# which is what makes a light year and a pixel mix safely here
		# and nowhere else.
		var out: Vector2 = (_map.positions[index] - home)
		var away: float = out.length()
		var heading: Vector2 = to_screen.basis_xform(out).normalized()
		if heading.is_zero_approx():
			continue

		var crossable: bool = drive != null and drive.can_cross(away)
		var cost: float = drive.fuel_for(away, _ship.mass) if drive != null else INF
		found.append({
			"index": index,
			"at": centre + _on_ring(heading, extent),
			"heading": heading,
			"distance": away,
			"cost": cost,
			"crossable": crossable,
			"affordable": crossable and cost <= _ship.fuel,
			"label": _label_for(index, away, eyes),
			"colour": _colour_for(crossable, crossable and cost <= _ship.fuel),
		})
	return found


## Which system is lit: the one being charged, or the one the nose is
## on. Asked of the controller, which owns the question.
func target() -> int:
	return _jump.showing() if _jump != null else -1


## What is written under a marker, which is the scanner's depth and
## nothing else. Each step is a different sentence rather than a finer
## number, so each one is a branch.
func _label_for(index: int, away: float, eyes: ScannerData) -> String:
	if not eyes.knows(ScannerData.Depth.CLASS):
		return "%.1f" % away
	var system: StarSystem = _system_at(index)
	if system == null:
		return "%.1f" % away
	var line: String = "%s %.1f" % [system.display_name, away]
	if eyes.knows(ScannerData.Depth.SURVEY):
		line += "  %dp" % system.planets().size()
	if eyes.knows(ScannerData.Depth.DEEP):
		line += " %dd" % system.of_kind(SystemBody.Kind.STATION).size()
	return line


## The system behind an index, through the galaxy when there is one.
##
## Only asked for when the scanner is good enough to say something about
## it: generating a system is cheap but not free, and a bearing-only
## scanner would otherwise be unrolling a hundred star systems to print a
## hundred distances it already knew.
func _system_at(index: int) -> StarSystem:
	if _galaxy == null or not _galaxy.has_method("system"):
		return null
	return _galaxy.system(index) as StarSystem


func _colour_for(crossable: bool, affordable: bool) -> Color:
	if not crossable:
		return _ink.inert
	return _ink.nav if affordable else _ink.caution


## Where a direction meets the ring. A rectangle, because the screen is
## one: a circle leaves the corners empty and crowds the short edges.
func _on_ring(heading: Vector2, extent: Vector2) -> Vector2:
	var scale_x: float = extent.x / absf(heading.x) if absf(heading.x) > 0.0001 else INF
	var scale_y: float = extent.y / absf(heading.y) if absf(heading.y) > 0.0001 else INF
	return heading * minf(scale_x, scale_y)


func _draw_markers() -> void:
	if not Presentation.is_on():
		return
	var view: Vector2 = _canvas.size
	var font: Font = UiFont.face()
	var excuse: String = silence()
	if not excuse.is_empty():
		_canvas.draw_string(
			font, Vector2(RING_MARGIN, view.y - RING_MARGIN), excuse,
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, _ink.inert,
		)
		return

	var to_screen: Transform2D = get_viewport().get_canvas_transform()
	var chosen: int = target()
	# Marks first, then the words, so a name is never drawn under a
	# chevron it does not belong to.
	var written: Array[Rect2] = []
	var listed: Array[Dictionary] = contacts(to_screen, view)
	for contact: Dictionary in listed:
		_draw_mark(contact, int(contact["index"]) == chosen)
	# The chosen one first, so that when two names cannot both fit the
	# one the nose is on is the one that survives.
	for contact: Dictionary in listed:
		if int(contact["index"]) == chosen:
			_write_label(font, contact, true, view, written)
	for contact: Dictionary in listed:
		if int(contact["index"]) != chosen:
			_write_label(font, contact, false, view, written)


func _draw_mark(contact: Dictionary, chosen: bool) -> void:
	var at: Vector2 = contact["at"]
	var heading: Vector2 = contact["heading"]
	# A chevron pointing the way out, rather than a triangle: the
	# scanner's own contacts are triangles, and two kinds of thing on one
	# ring have to be told apart at three pixels.
	var side: Vector2 = heading.orthogonal() * MARKER
	var tip: Vector2 = at + heading * MARKER * 1.4
	_canvas.draw_line(at - side, tip, contact["colour"], 1.0)
	_canvas.draw_line(at + side, tip, contact["colour"], 1.0)
	if chosen:
		_canvas.draw_arc(at, MARKER * 2.0, 0.0, TAU, 12, _ink.accent, 1.0)


## The name under a mark, if there is room for it.
##
## A label that would land on one already written is dropped rather than
## nudged. Two systems a few degrees apart are two marks a few pixels
## apart, and sliding their names aside only moves the collision
## somewhere the mark is not: a name beside the wrong chevron is worse
## than a chevron with no name, which at least still says "something
## that way". The chosen one is written first and so always wins.
func _write_label(
	font: Font, contact: Dictionary, chosen: bool, view: Vector2, written: Array[Rect2]
) -> void:
	var at: Vector2 = contact["at"]
	var heading: Vector2 = contact["heading"]
	var colour: Color = contact["colour"]
	var text: String = contact["label"]
	var width: float = font.get_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE
	).x
	# Inboard of the mark, far enough to clear the selection ring, and
	# then **clamped onto the screen**. Pushing back along the heading
	# alone is right for the mark and wrong for the words: a marker near
	# a corner has its label centred on a point a few pixels from the
	# edge, so half of it hangs off the side it is pointing at. Half a
	# distance is worse than no distance.
	var clear: float = MARKER * 2.0 + float(FONT_SIZE) * 0.8
	var anchor: Vector2 = at - heading * clear
	# Centred under a mark on the top or bottom edge, and set beside one
	# on the left or right. Centring everything put the name of a
	# side marker straight through its own chevron, because inboard for
	# those two edges is sideways and the half-width pulled it back out
	# again.
	var beside: float = anchor.x - width * 0.5
	if absf(heading.x) > absf(heading.y):
		beside = anchor.x - width if heading.x > 0.0 else anchor.x
	var label_at: Vector2 = Vector2(
		clampf(beside, 2.0, maxf(view.x - width - 2.0, 2.0)),
		clampf(anchor.y + float(FONT_SIZE) * 0.4, float(FONT_SIZE), view.y - 2.0),
	)
	var box: Rect2 = Rect2(
		label_at - Vector2(0.0, float(FONT_SIZE)), Vector2(width, float(FONT_SIZE) + 1.0)
	)
	for other: Rect2 in written:
		if box.intersects(other):
			return
	written.append(box)
	_canvas.draw_string(
		font, label_at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE,
		_ink.value if chosen else colour,
	)
