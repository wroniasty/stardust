class_name ScannerHud
extends CanvasLayer
## Edge-of-screen markers for what is around the ship: celestial bodies, and
## the loot lying on them.
##
## The first piece of instrumentation that is about the world rather than
## about the ship: at 640x360 a planet is either filling the view or nowhere
## to be seen, and "nowhere to be seen" covers both "just behind me" and "half
## a system away". The scanner turns that into a direction and a number.
##
## Two kinds of thing, two marks. A triangle is a body, sized by how big it is
## and lit by whether the ship is in its well; a diamond is a crate, coloured
## by rarity. They are collected separately because they share nothing but the
## ring they sit on, and they behave differently on it: a planet stops being
## marked once you can see it, a crate does not.
##
## Both read a group -- `gravity_sources` and `loot` -- rather than a list of
## the scanner's own. Those are the same definitions the rest of the game uses,
## so the moons and stars of M3 appear here without this file changing.

## How far the scanner reaches for celestial bodies, measured to the surface.
## Generous for now: one that only saw as far as the gravity well would be
## useless for navigating between bodies. In M5 this becomes a property of a
## scanner module, and a better scanner sees further (IDEAS.md section 4).
@export var scan_range: float = 20000.0

## How far it reaches for loot. Much shorter, and deliberately so: a crate on
## the far side of the system is not a decision, it is noise. This is the
## range at which "there is something over there" is worth a detour.
@export var loot_range: float = 4000.0

## Most crates shown at once, nearest first, so a well picked-over planet does
## not turn the edge of the screen into a picket fence.
@export var max_loot: int = 6

## How far in from the edge of the screen the ring of markers sits. Only
## enough to keep the marker itself on screen: the markers belong to the edge,
## and every pixel they sit inward of it is a pixel taken off the view.
@export var ring_margin: float = 8.0

## Half-length of the marker triangle before scaling. Small on purpose: the
## whole screen is 640x360 and this must not compete with the view.
const MARKER_SIZE: float = 2.5

## Bounds on the size scaling, so a moon stays visible and a star does not
## take over the corner. Narrower than the sizes it ranges over, because at
## two pixels the difference between a marker and a speck is one pixel.
const MARKER_SCALE: Vector2 = Vector2(0.8, 1.8)

## Body radius that draws a marker at scale 1.0. A rocky planet, so moons come
## out smaller and stars larger.
const REFERENCE_RADIUS: float = 1000.0

const FONT_SIZE: int = 8

## Half-size of a loot marker on the ring. Fixed: one crate is much like
## another in size, so the only thing worth encoding in a diamond is its
## rarity colour.
const LOOT_SIZE: float = 2.2

## Half-size of the bracket drawn around a crate that is on screen. Not a
## matter of taste like the others: it has to clear the crate's own glow,
## which is 22 px across and already painted in the rarity colour. The first
## version was smaller than the box it marked and the same colour as it, so it
## drew perfectly and was invisible.
const LOOT_BRACKET: float = 15.0

## Markers dim outside the body's influence radius, so "I am in this well" is
## readable without spending a second colour channel on it.
const INSIDE_ALPHA: float = 1.0
const OUTSIDE_ALPHA: float = 0.5

var _ship: Ship = null
var _canvas: Control = null

## Label boxes already placed this frame. Two markers in nearly the same
## direction print their numbers on top of each other otherwise, which reads
## as one wrong number rather than as two right ones -- seen with a planet and
## a crate on its far side both sitting at the top of the ring.
var _labels: Array[Rect2] = []


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

	for source: Node in get_tree().get_nodes_in_group(GravityWell.GROUP):
		# Every source, star included: the pilot wants to know where the sun
		# is at least as much as where the moon is.
		var body: GravityWell = source as GravityWell
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


## Nearby loot, nearest first. A separate call from contacts() because the two
## are different kinds of thing and carry different facts -- a well and a
## rarity have nothing to say to each other -- and because loot is worth
## marking even when it is on screen, which a planet is not.
func loot_contacts(to_screen: Transform2D, view: Vector2) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if _ship == null or not is_instance_valid(_ship):
		return found

	var centre: Vector2 = view * 0.5
	var extent: Vector2 = centre - Vector2(ring_margin, ring_margin)
	if extent.x <= 0.0 or extent.y <= 0.0:
		return found

	for node: Node in get_tree().get_nodes_in_group(LootCrate.LOOT_GROUP):
		var crate: LootCrate = node as LootCrate
		if crate == null or crate.item == null:
			continue
		var distance: float = _ship.global_position.distance_to(crate.global_position)
		if distance > loot_range:
			continue

		var screen_point: Vector2 = to_screen * crate.global_position
		var offset: Vector2 = screen_point - centre
		# Unlike a planet, a crate on screen still earns a marker. It is eight
		# pixels of box against a whole planet of terrain, and an indicator
		# that vanishes the moment you turn towards the thing it was pointing
		# at is an indicator that fails exactly when it is being used.
		var off_screen: bool = absf(offset.x) >= extent.x or absf(offset.y) >= extent.y
		found.append({
			"crate": crate,
			"at": centre + _on_ring(offset, extent) if off_screen else screen_point,
			"direction": offset.normalized() if off_screen else Vector2.ZERO,
			"distance": distance,
			"rarity": crate.rarity(),
			"on_ring": off_screen,
		})

	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["distance"]) < float(b["distance"])
	)
	return found.slice(0, max_loot)


func _draw_markers() -> void:
	var font: Font = _canvas.get_theme_default_font()
	var to_screen: Transform2D = get_viewport().get_canvas_transform()
	_labels.clear()
	for contact: Dictionary in contacts(to_screen, _canvas.size):
		_draw_marker(font, contact)
	# Over the bodies: loot is the smaller, more urgent mark of the two.
	for contact: Dictionary in loot_contacts(to_screen, _canvas.size):
		_draw_loot(font, contact)


## Loot is a diamond, so it never reads as a small planet. Solid and pointing
## outwards on the ring, hollow and sitting on the thing itself when the crate
## is on screen -- the same mark in two states rather than two marks.
func _draw_loot(font: Font, contact: Dictionary) -> void:
	var at: Vector2 = contact["at"]
	var colour: Color = LootCrate.RARITY_COLORS[
		clampi(int(contact["rarity"]), 0, LootCrate.RARITY_COLORS.size() - 1)
	]

	if not bool(contact["on_ring"]):
		var points: PackedVector2Array = _diamond(at, Vector2.UP, LOOT_BRACKET)
		points.append(points[0])
		_canvas.draw_polyline(points, Color(colour, 0.7), 1.0)
		return

	var direction: Vector2 = contact["direction"]
	_canvas.draw_colored_polygon(_diamond(at, direction, LOOT_SIZE), colour)
	if font != null:
		_draw_label(font, at, direction, LOOT_SIZE, distance_text(contact["distance"]), colour)


func _diamond(at: Vector2, axis: Vector2, size: float) -> PackedVector2Array:
	var side: Vector2 = axis.orthogonal() * size * 0.7
	return PackedVector2Array([at + axis * size, at + side, at - axis * size, at - side])


func _draw_marker(font: Font, contact: Dictionary) -> void:
	var at: Vector2 = contact["at"]
	var direction: Vector2 = contact["direction"]
	var size: float = contact["size"]

	var colour: Color = _marker_color(contact["body"] as GravityWell)
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

	if font != null:
		_draw_label(font, at, direction, size, distance_text(contact["distance"]), colour)


## The distance, inward of the marker so it never runs off the edge it sits
## on, and clear of it by the half-extent the text presents in that direction:
## a marker on a side edge needs the text pushed by half its width, one on the
## bottom edge by half its height.
func _draw_label(
	font: Font, at: Vector2, direction: Vector2, size: float, text: String, colour: Color
) -> void:
	var half: Vector2 = Vector2(
		font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x, float(FONT_SIZE),
	) * 0.5
	var clearance: float = absf(direction.x) * half.x + absf(direction.y) * half.y
	var anchor: Vector2 = at - direction * (size + 2.0 + clearance)

	# First label placed wins the space. Bodies are drawn before loot and
	# loot nearest-first, so what survives a collision is the reading most
	# worth having: a body's range over a crate's, and the near crate's over
	# the far one's.
	var box: Rect2 = Rect2(anchor - half, half * 2.0)
	for taken: Rect2 in _labels:
		if taken.intersects(box):
			return
	_labels.append(box)

	_canvas.draw_string(
		font,
		anchor - Vector2(half.x, -half.y * 0.8),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		FONT_SIZE,
		Color(colour, colour.a * 0.85),
	)


## The body's own colour, lifted to something readable against space. Using
## the body's colour means the marker and the thing you eventually see are
## recognisably the same object.
func _marker_color(body: GravityWell) -> Color:
	return body.marker_color().lerp(Color.WHITE, 0.35)


func distance_text(distance: float) -> String:
	if distance < 0.0:
		return "0"
	if distance < 10000.0:
		return "%d" % roundi(distance)
	return "%.1fk" % (distance / 1000.0)
