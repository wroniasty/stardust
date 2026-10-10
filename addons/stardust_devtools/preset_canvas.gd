@tool
class_name PresetCanvas
extends HullView
## Podglad presetu: co ten fitout stawia na tym kadlubie.
##
## Read-only on purpose. A preset says what goes where **by kind**, and
## where that lands is the hull's answer, not the preset's -- so there is
## nothing here to drag. What the picture is for is the question a form
## of dropdowns cannot answer: given this hull and these four lines, what
## ship comes out.
##
## Everything drawn comes from `ShipFitout.placements` and
## `ShipFitout.balance_of`, the same calls `apply` builds the real ship
## with, so the preview cannot show a ship the game would not build.

## What the cursor is over, as a line of text for a status bar.
signal hovered(note: String)

const HULL_LINE: Color = Color(0.62, 0.78, 1.0)
const HULL_FILL: Color = Color(0.62, 0.78, 1.0, 0.10)
const GUN_EMPTY: Color = Color(0.70, 0.70, 0.70, 0.45)
const GUN_ARMED: Color = Color(1.00, 0.86, 0.32)
const BAY_EMPTY: Color = Color(0.70, 0.70, 0.70, 0.40)
const BAY_FULL: Color = Color(0.60, 0.85, 0.95)
const LEG: Color = Color(0.76, 0.60, 0.96)
const BALANCE: Color = Color(1.0, 0.45, 0.35)

## How close the cursor has to be, in screen pixels, to name something.
const NAME_RADIUS: float = 10.0

## How long the tick showing which way a mount faces is drawn.
const FACING_TICK: float = 11.0

var preset: ShipPreset = null

## What `ShipFitout` last said about this pairing.
var balance: Dictionary = {}

var _spots: Array[Dictionary] = []
var _guns: Array[Dictionary] = []
var _hover: int = -1


func _ready() -> void:
	super()
	refresh()


## Put a preset on the canvas and frame it.
func show_preset(which: ShipPreset) -> void:
	preset = which
	_hover = -1
	refresh()
	fit()


## Re-read the preset. Called after anything changes it.
func refresh() -> void:
	_spots = []
	_guns = []
	balance = {}
	var hull: HullData = preset.hull if preset != null else null
	if hull != null:
		_spots = ShipFitout.placements(hull, preset)
		balance = ShipFitout.balance_of(hull, preset)
		# The gun places, filled in the order the hull offers them --
		# front first, then the sides, then astern, exactly as `apply`
		# hands the weapons out.
		var next_gun: int = 0
		for slot: Dictionary in hull.slots():
			if ShipFitout.SOCKET_FOR.has(slot["kind"]):
				continue
			var carried: WeaponData = null
			if next_gun < preset.guns.size():
				carried = preset.guns[next_gun]
				next_gun += 1
			_guns.append({"slot": slot, "weapon": carried})
	queue_redraw()


func framed_points() -> Array[Vector2]:
	var points: Array[Vector2] = []
	var hull: HullData = preset.hull if preset != null else null
	if hull == null:
		return points
	for point: Vector2 in hull.outline:
		points.append(point)
	for spot: Dictionary in _spots:
		points.append(spot["at"])
	for gun: Dictionary in _guns:
		points.append((gun["slot"] as Dictionary)["at"])
	for leg: Vector2 in hull.legs:
		points.append(leg)
	for bay: BayFit in preset.bays:
		if bay != null:
			points.append(bay.at)
	return points


func _draw() -> void:
	draw_grid()
	var hull: HullData = preset.hull if preset != null else null
	if hull == null:
		return
	_draw_outline(hull)
	_draw_legs(hull)
	_draw_bays()
	_draw_guns()
	_draw_mounts()
	_draw_centre()
	_draw_label()


func _draw_outline(hull: HullData) -> void:
	if hull.outline.size() < 3:
		return
	var screen: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in hull.outline:
		screen.append(to_screen(point))
	draw_colored_polygon(screen, HULL_FILL)
	screen.append(screen[0])
	draw_polyline(screen, HULL_LINE, 1.5)


func _draw_legs(hull: HullData) -> void:
	for leg: Vector2 in hull.legs:
		var at: Vector2 = to_screen(leg)
		draw_line(at + Vector2(-5.0, 0.0), at + Vector2(5.0, 0.0), LEG, 1.5)


## A module bay as a box the size of the hole, so a big generator in a
## small ship reads as the thing it is.
func _draw_bays() -> void:
	for bay: BayFit in preset.bays:
		if bay == null:
			continue
		var filled: bool = bay.installed != null
		var tint: Color = BAY_FULL if filled else BAY_EMPTY
		var half: float = maxf(bay.size, 0.2) * 0.5 * _zoom
		var at: Vector2 = to_screen(bay.at)
		draw_rect(
			Rect2(at - Vector2(half, half), Vector2(half, half) * 2.0),
			tint, false, 1.0,
		)


func _draw_guns() -> void:
	for gun: Dictionary in _guns:
		var slot: Dictionary = gun["slot"]
		var armed: bool = gun["weapon"] != null
		var tint: Color = GUN_ARMED if armed else GUN_EMPTY
		var at: Vector2 = to_screen(slot["at"])
		var facing: Vector2 = Vector2.UP.rotated(float(slot["turn"]))
		draw_line(at, at + facing * FACING_TICK * 0.7, tint, 1.0)
		# A triangle rather than a circle, so a gun is never mistaken for
		# an engine at a glance.
		var across: Vector2 = facing.orthogonal() * 3.0
		draw_polyline(
			PackedVector2Array([
				at + facing * 4.0, at + across, at - across, at + facing * 4.0,
			]),
			tint, 1.0,
		)


func _draw_mounts() -> void:
	for spot: Dictionary in _spots:
		var tint: Color = _paint_for(spot["kind"])
		var at: Vector2 = to_screen(spot["at"])
		var facing: Vector2 = Vector2.UP.rotated(float(spot["turn"]))
		draw_line(at, at + facing * FACING_TICK, tint, 1.0)
		draw_circle(at, 3.0, tint)


## The same colours the hull dock paints each kind of place in, so the
## two docks cannot disagree about what a torque jet looks like.
func _paint_for(kind: StringName) -> Color:
	var field: StringName = HullHandles.field_for_kind(kind)
	return HullCanvas.PAINT.get(field, Color.WHITE)


func _draw_centre() -> void:
	if balance.is_empty():
		return
	var at: Vector2 = to_screen(balance["centre"])
	draw_line(at + Vector2(-6.0, 0.0), at + Vector2(6.0, 0.0), BALANCE, 1.5)
	draw_line(at + Vector2(0.0, -6.0), at + Vector2(0.0, 6.0), BALANCE, 1.5)
	draw_dashed_line(
		Vector2(0.0, at.y), Vector2(size.x, at.y), BALANCE, 1.0, 6.0,
	)


func _draw_label() -> void:
	if _hover < 0:
		return
	var named: String = _named_at(_hover)
	if named.is_empty():
		return
	var font: Font = get_theme_default_font()
	var anchor: Vector2 = _point_at(_hover) + Vector2(9.0, -7.0)
	var width: float = font.get_string_size(named, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11).x
	draw_rect(
		Rect2(anchor + Vector2(-3.0, -10.0), Vector2(width + 6.0, 15.0)),
		Color(0.0, 0.0, 0.0, 0.7),
	)
	draw_string(font, anchor, named, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, Color.WHITE)


## Everything nameable, as one list, so hovering has one index space.
func _point_at(index: int) -> Vector2:
	if index < _spots.size():
		return to_screen(_spots[index]["at"])
	return to_screen((_guns[index - _spots.size()]["slot"] as Dictionary)["at"])


func _named_at(index: int) -> String:
	if index < 0:
		return ""
	if index < _spots.size():
		var spot: Dictionary = _spots[index]
		var engine: EngineData = spot["engine"]
		var share: float = spot["share"]
		return "%s: %s%s" % [
			spot["name"], engine.display_name if engine != null else "puste",
			"" if is_equal_approx(share, 1.0) else " (%.0f%% silnika)" % (share * 100.0),
		]
	var gun: Dictionary = _guns[index - _spots.size()]
	var weapon: WeaponData = gun["weapon"]
	return "%s: %s" % [
		(gun["slot"] as Dictionary)["name"],
		weapon.display_name if weapon != null else "puste",
	]


func _gui_input(event: InputEvent) -> void:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null and button.pressed:
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_about(button.position, 1.12)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_about(button.position, 1.0 / 1.12)
		return
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion == null:
		return
	var nearest: int = -1
	var closest: float = NAME_RADIUS
	for i: int in range(_spots.size() + _guns.size()):
		var gap: float = _point_at(i).distance_to(motion.position)
		if gap <= closest:
			closest = gap
			nearest = i
	if nearest == _hover:
		return
	_hover = nearest
	hovered.emit(_named_at(nearest))
	queue_redraw()
