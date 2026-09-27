class_name ScannerHud
extends CanvasLayer
## Edge-of-screen markers for the celestial bodies around the ship.
##
## The first piece of instrumentation that is about the world rather than
## about the ship: at 640x360 a planet is either filling the view or nowhere
## to be seen, and "nowhere to be seen" covers both "just behind me" and "half
## a system away". The scanner turns that into a direction and a number.
##
## Reads the `gravity_sources` group rather than a list of its own, which is
## the same definition of "celestial body" the physics uses. Moons and stars
## join that group in M3 and appear here without this file changing.

## How far the scanner reaches, measured to the surface. Generous for now: one
## that only saw as far as the gravity well would be useless for navigating
## between bodies. In M5 this becomes a property of a scanner module, and a
## better scanner sees further (IDEAS.md section 4).
@export var scan_range: float = 20000.0

## How far in from the edge of the screen the ring of markers sits. Enough to
## clear the marker and its label.
@export var ring_margin: float = 16.0

## Half-length of the marker triangle before scaling. Small on purpose: the
## whole screen is 640x360 and this must not compete with the view.
const MARKER_SIZE: float = 3.5

## Bounds on the size scaling, so a moon stays visible and a star does not
## take over the corner.
const MARKER_SCALE: Vector2 = Vector2(0.7, 2.0)

## Body radius that draws a marker at scale 1.0. A rocky planet, so moons come
## out smaller and stars larger.
const REFERENCE_RADIUS: float = 1000.0

const FONT_SIZE: int = 8

## Markers dim outside the body's influence radius, so "I am in this well" is
## readable without spending a second colour channel on it.
const INSIDE_ALPHA: float = 1.0
const OUTSIDE_ALPHA: float = 0.5

var _ship: Ship = null
var _canvas: Control = null


func _ready() -> void:
	layer = 8
	# Keeps drawing while the tree is paused, for the same reason the landing
	# HUD does: a readout frozen on stale values is worse than none.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_markers)
	add_child(_canvas)


func bind(ship: Ship) -> void:
	_ship = ship


func _process(_delta: float) -> void:
	if _canvas != null:
		_canvas.queue_redraw()


## What the scanner would draw, as data: one entry per body that earns a
## marker, with where it goes and what it says.
##
## Takes the world-to-screen transform rather than reading the viewport, so
## the geometry is a pure function of the arguments and can be tested without
## a camera or a rendered frame. `to_screen` is the canvas transform, which
## already carries the camera's position, zoom and -- once the landing camera
## lands (VISUALS V4) -- its rotation, which is the case a hand-rolled
## world-space angle would quietly get wrong.
func contacts(to_screen: Transform2D, view: Vector2) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if _ship == null or not is_instance_valid(_ship):
		return found

	var centre: Vector2 = view * 0.5
	var extent: Vector2 = centre - Vector2(ring_margin, ring_margin)
	if extent.x <= 0.0 or extent.y <= 0.0:
		return found

	for source: Node in get_tree().get_nodes_in_group(Planet.GRAVITY_GROUP):
		var body: Planet = source as Planet
		if body == null:
			continue
		var to_centre: float = _ship.global_position.distance_to(body.global_position)
		if to_centre - body.surface_radius > scan_range:
			continue

		var screen_point: Vector2 = to_screen * body.global_position
		var offset: Vector2 = screen_point - centre
		# A body whose centre is on screen is one the pilot can already see;
		# an edge marker for it would point at nothing they need.
		if absf(offset.x) < extent.x and absf(offset.y) < extent.y:
			continue
		if offset.is_zero_approx():
			continue

		found.append({
			"body": body,
			"at": centre + _on_ring(offset, extent),
			"direction": offset.normalized(),
			# To the surface, not to the centre: it is the number the pilot
			# acts on, and on a 1000 px planet the two are nothing alike.
			"distance": to_centre - body.surface_radius,
			"inside": to_centre < body.influence_radius,
			# How big the body is, not how close. A 2D world has no
			# perspective -- a planet's radius on screen is its radius times
			# the zoom, whatever the range -- so distance has nothing to say
			# here and is carried by the brightness and the number instead.
			# Square root, or a star would be an order of magnitude past a moon.
			"size": MARKER_SIZE * clampf(
				sqrt(body.surface_radius / REFERENCE_RADIUS),
				MARKER_SCALE.x,
				MARKER_SCALE.y,
			),
		})
	return found


## Where a direction from the centre meets the ring, as an offset from the
## centre. The ring is a rectangle rather than a circle because the screen is
## one: a circle would leave the corners empty while crowding the short edges.
func _on_ring(offset: Vector2, extent: Vector2) -> Vector2:
	var scale_x: float = extent.x / absf(offset.x) if absf(offset.x) > 0.0001 else INF
	var scale_y: float = extent.y / absf(offset.y) if absf(offset.y) > 0.0001 else INF
	return offset * minf(scale_x, scale_y)


func _draw_markers() -> void:
	var font: Font = _canvas.get_theme_default_font()
	for contact: Dictionary in contacts(get_viewport().get_canvas_transform(), _canvas.size):
		_draw_marker(font, contact)


func _draw_marker(font: Font, contact: Dictionary) -> void:
	var at: Vector2 = contact["at"]
	var direction: Vector2 = contact["direction"]
	var size: float = contact["size"]

	var colour: Color = _marker_color(contact["body"] as Planet)
	colour.a = INSIDE_ALPHA if bool(contact["inside"]) else OUTSIDE_ALPHA

	# A triangle pointing out of the screen, at the body.
	var side: Vector2 = direction.orthogonal() * size
	_canvas.draw_colored_polygon(
		PackedVector2Array([
			at + direction * size,
			at - direction * size + side,
			at - direction * size - side,
		]),
		colour,
	)

	if font == null:
		return
	var text: String = distance_text(contact["distance"])
	var half: Vector2 = Vector2(
		font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x, float(FONT_SIZE),
	) * 0.5

	# Inward of the marker, so the label never runs off the edge it sits on,
	# and clear of it by the half-extent the text presents in that direction:
	# a marker on a side edge needs the text pushed by half its width, one on
	# the bottom edge by half its height.
	var clearance: float = absf(direction.x) * half.x + absf(direction.y) * half.y
	var anchor: Vector2 = at - direction * (size + 2.0 + clearance)
	colour.a *= 0.85
	_canvas.draw_string(
		font,
		anchor - Vector2(half.x, -half.y * 0.8),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		FONT_SIZE,
		colour,
	)


## The body's own colour, lifted to something readable against space. Using
## the surface colour means the marker and the planet you eventually see are
## recognisably the same object.
func _marker_color(body: Planet) -> Color:
	return body.surface_color.lerp(Color.WHITE, 0.35)


func distance_text(distance: float) -> String:
	if distance < 0.0:
		return "0"
	if distance < 10000.0:
		return "%d" % roundi(distance)
	return "%.1fk" % (distance / 1000.0)
