class_name ShipEditor
extends CanvasLayer
## MAUX1: the prototype ship editor. Cargo, hold, and every place a module can
## go, on one screen.
##
## The quick swap on Tab stays what it is -- one slot, no pause, a decision
## taken while still flying. This is the other half: somewhere to look at the
## whole ship, see what fitting a module would actually do, and stow or throw
## away what is not wanted. It pauses, because reading a schematic while
## falling is not a decision, it is an accident.
##
## Prototype, and deliberately so. It opens anywhere rather than only when
## landed, because the point of it right now is to be poked at.
##
## The schematic is generated from the same data the ship flies on -- the hull
## collision polygon and the mount nodes' own positions -- never drawn by
## hand. A hand-drawn one would have been wrong the moment the torque cross
## moved, which happened twice while the bulk work was going in.

## Opaque, not nearly-opaque. At 0.95 the debug overlay behind still came
## through as readable grey text: five percent of bright green on near-black
## is twice the panel's own brightness.
const PANEL_BG: Color = Color(0.05, 0.06, 0.08, 1.0)

## Dims the world behind the panels, so the screen reads as "the game has
## stopped" rather than as a window left open over it.
const SCRIM: Color = Color(0.0, 0.0, 0.02, 0.72)
const PANEL_EDGE: Color = Color(0.28, 0.32, 0.39)
const LABEL: Color = Color(0.56, 0.63, 0.72)
const TEXT: Color = Color(0.78, 0.80, 0.83)
const PICK: Color = Color(1.00, 0.85, 0.35)
const FIT: Color = Color(0.36, 0.88, 0.62)
const HULL: Color = Color(0.29, 0.34, 0.41)
const HULL_FILL: Color = Color(0.10, 0.14, 0.19)

## A mount the selected module will not go into. Readable, but plainly not a
## candidate.
const IDLE_MOUNT: Color = Color(0.42, 0.47, 0.55)
const WARN: Color = Color(1.00, 0.55, 0.35)

const FONT_SIZE: int = 8
const ROW: float = 10.0
const PAD: float = 5.0

## Radius of a mount dot on the schematic, and the extra a highlighted one
## gets so it reads as a target rather than as a slightly bigger dot.
const DOT: float = 2.5
const DOT_PICKED: float = 4.5

var _ship: Ship = null
var _canvas: Control = null

## Index into _items(): the hold first, then the cargo bay.
var _pick: int = 0

## Index into _targets(): which of the mounts the selected module fits is
## highlighted. Wrapped on every redraw, so a slot disappearing under it
## cannot leave the cursor pointing at nothing.
var _slot: int = 0

## Last line of feedback, from a fit, a stow or a refusal.
var _notice: String = ""


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_editor)
	add_child(_canvas)
	_canvas.hide()


func bind(ship: Ship) -> void:
	_ship = ship


func is_open() -> bool:
	return _canvas.visible


func toggle() -> void:
	if is_open():
		close()
		return
	_pick = 0
	_slot = 0
	_notice = ""
	_canvas.show()
	get_tree().paused = true


func close() -> void:
	_canvas.hide()
	get_tree().paused = false


func _process(_delta: float) -> void:
	if is_open():
		_canvas.queue_redraw()
	elif get_tree().paused and not _anything_else_paused():
		# The same guard the planet configurator needs: a screen that pauses
		# the tree must never be the reason a closed screen leaves it paused.
		get_tree().paused = false


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_editor"):
		toggle()
		get_viewport().set_input_as_handled()
		return
	if not is_open():
		return

	if event.is_action_pressed(&"ui_cancel"):
		close()
	elif event.is_action_pressed(&"ui_down"):
		_pick += 1
		_slot = 0
	elif event.is_action_pressed(&"ui_up"):
		_pick -= 1
		_slot = 0
	elif event.is_action_pressed(&"ui_right"):
		_slot += 1
	elif event.is_action_pressed(&"ui_left"):
		_slot -= 1
	elif event.is_action_pressed(&"loadout_fit"):
		_fit()
	elif event.is_action_pressed(&"loadout_drop"):
		_jettison()
	elif event.is_action_pressed(&"editor_stow"):
		_stow()
	else:
		return
	get_viewport().set_input_as_handled()


## Whether some other screen wants the tree paused. Only the configurator
## does, and asking it directly beats keeping a counter both would have to
## remember to update.
func _anything_else_paused() -> bool:
	for node: Node in get_parent().get_children():
		var configurator: PlanetConfigurator = node as PlanetConfigurator
		if configurator != null and configurator.is_open():
			return true
	return false


## Everything the pilot can act on, hold first. One list rather than two
## panels to tab between: whichever module is selected, the keys mean the
## same thing.
func _items() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _ship == null:
		return out
	if _ship.carried != null:
		out.append({"item": _ship.carried, "rarity": _ship.carried_rarity, "held": true})
	for entry: Dictionary in _ship.cargo:
		out.append({"item": entry["item"], "rarity": int(entry["rarity"]), "held": false})
	return out


func _selected() -> Dictionary:
	var items: Array[Dictionary] = _items()
	if items.is_empty():
		return {}
	_pick = posmod(_pick, items.size())
	return items[_pick]


## Mounts the selected module will go into. Asked of the mounts themselves,
## so the editor cannot drift from what fitting actually allows.
func _targets() -> Array[Node]:
	var out: Array[Node] = []
	var picked: Dictionary = _selected()
	if picked.is_empty() or _ship == null:
		return out
	var item: Resource = picked["item"]
	if item is WeaponData:
		for mount: Hardpoint in _ship.hardpoints:
			if mount.can_fit(item as WeaponData):
				out.append(mount)
	elif item is EngineData:
		for mount: EngineMount in _ship.engine_mounts():
			if _ship.mount_accepts(mount, item as EngineData):
				out.append(mount)
	return out


## Every place a module could go, fitted or not, for the schematic.
func _all_mounts() -> Array[Node]:
	var out: Array[Node] = []
	if _ship == null:
		return out
	for mount: EngineMount in _ship.engine_mounts():
		out.append(mount)
	for mount: Hardpoint in _ship.hardpoints:
		out.append(mount)
	return out


func _fit() -> void:
	var targets: Array[Node] = _targets()
	var picked: Dictionary = _selected()
	if targets.is_empty() or picked.is_empty():
		_notice = "nie ma gdzie tego zamontować"
		return

	var slot: Node = targets[posmod(_slot, targets.size())]
	var item: Resource = picked["item"]
	var before: ConfigurationReport = _ship.configuration()

	# Out of wherever it was, so the ship is never holding two copies of it.
	if bool(picked["held"]):
		_ship.release()
	else:
		_ship.cargo.remove_at(_pick - (1 if _ship.carried != null else 0))

	var removed: Resource = null
	if slot is Hardpoint:
		removed = (slot as Hardpoint).fit(item as WeaponData)
	elif slot is EngineMount:
		removed = _ship.fit_engine(slot as EngineMount, item as EngineData)

	# Whatever came out goes back to the bay, or to the hold when the bay is
	# full. Never nowhere: a swap must always be reversible.
	if removed != null:
		if Ship.module_bulk(removed) <= _ship.cargo_free():
			_ship.cargo.append({"item": removed, "rarity": 0})
		elif not _ship.take(removed, 0):
			_ship.jettison()
			_notice = "ładownia i cargo pełne — stary moduł za burtę"
	_ship.rebuild_control_groups(false)
	_ship.cargo_changed.emit()

	var delta: PackedStringArray = _ship.configuration().compare(before)
	_notice = "zamontowano w %s — %s" % [
		slot.name, "bez zmian w sterowaniu" if delta.is_empty() else ", ".join(delta),
	]


func _stow() -> void:
	var picked: Dictionary = _selected()
	if picked.is_empty() or not bool(picked["held"]):
		_notice = "schować można tylko to, co jest w ładowni"
		return
	_notice = "schowano do cargo" if _ship.stow() else "cargo nie ma tyle miejsca"


func _jettison() -> void:
	var picked: Dictionary = _selected()
	if picked.is_empty():
		return
	if not bool(picked["held"]):
		# Everything leaves by the same door, so there is one jettison path
		# and one place the world hears about it.
		var index: int = _pick - (1 if _ship.carried != null else 0)
		if _ship.carried != null:
			_notice = "najpierw opróżnij ładownię"
			return
		_ship.retrieve(index)
	_ship.jettison()
	_notice = "wyrzucono za burtę"


func _draw_editor() -> void:
	var font: Font = _canvas.get_theme_default_font()
	if font == null or _ship == null:
		return
	var view: Vector2 = _canvas.size

	var list: Rect2 = Rect2(6.0, 6.0, view.x * 0.34, view.y * 0.72)
	var plan: Rect2 = Rect2(list.end.x + 6.0, 6.0, view.x - list.end.x - 12.0, view.y * 0.72)
	var info: Rect2 = Rect2(6.0, list.end.y + 6.0, view.x - 12.0, view.y - list.end.y - 12.0)

	_canvas.draw_rect(Rect2(Vector2.ZERO, view), SCRIM)
	_panel(list)
	_panel(plan)
	_panel(info)
	_draw_list(font, list)
	_draw_plan(font, plan)
	_draw_info(font, info)


func _panel(rect: Rect2) -> void:
	_canvas.draw_rect(rect, PANEL_BG)
	_canvas.draw_rect(rect, PANEL_EDGE, false, 1.0)


func _width(font: Font, text: String) -> float:
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x


func _text(font: Font, at: Vector2, text: String, colour: Color) -> void:
	_canvas.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, colour)


func _draw_list(font: Font, rect: Rect2) -> void:
	var y: float = rect.position.y + PAD + float(FONT_SIZE)
	var x: float = rect.position.x + PAD
	_text(font, Vector2(x, y), "ŁADOWNIA / CARGO   %.1f / %.1f" % [
		_ship.cargo_used(), _ship.cargo_capacity,
	], LABEL)
	y += ROW * 1.5

	var items: Array[Dictionary] = _items()
	if items.is_empty():
		_text(font, Vector2(x, y), "pusto", LABEL)
		return

	for i: int in range(items.size()):
		var entry: Dictionary = items[i]
		var item: Resource = entry["item"]
		var colour: Color = LootCrate.RARITY_COLORS[
			clampi(int(entry["rarity"]), 0, LootCrate.RARITY_COLORS.size() - 1)
		]
		if i == _pick:
			_canvas.draw_rect(
				Rect2(x - 2.0, y - float(FONT_SIZE), rect.size.x - PAD * 2.0 + 2.0, ROW),
				Color(PICK, 0.18),
			)
		_text(font, Vector2(x, y), "%s %-22s %4.1f" % [
			">" if bool(entry["held"]) else " ", _label(item).left(22), Ship.module_bulk(item),
		], colour if i != _pick else PICK)
		y += ROW


## The schematic, built from the hull polygon and the mount positions so it
## cannot disagree with the ship it describes.
func _draw_plan(font: Font, rect: Rect2) -> void:
	_text(font, rect.position + Vector2(PAD, PAD + float(FONT_SIZE)), "SCHEMAT", LABEL)

	var hull: PackedVector2Array = _ship.hull_outline()
	var mounts: Array[Node] = _all_mounts()
	if hull.size() < 3:
		return

	# Fit the hull and every mount into the panel, leaving room for the name
	# printed beside each dot.
	var bounds: Rect2 = Rect2(hull[0], Vector2.ZERO)
	for point: Vector2 in hull:
		bounds = bounds.expand(point)
	for mount: Node in mounts:
		bounds = bounds.expand((mount as Node2D).position)
	bounds = bounds.grow(2.0)

	# Generous horizontal padding: every dot prints its name beside it, and
	# the names are wider than the ship is.
	var room: Vector2 = rect.size - Vector2(rect.size.x * 0.52, PAD * 4.0 + float(FONT_SIZE))
	var scale: float = minf(room.x / bounds.size.x, room.y / bounds.size.y)
	var origin: Vector2 = rect.position + Vector2(rect.size.x * 0.5, rect.size.y * 0.55)
	var place: Callable = func(p: Vector2) -> Vector2:
		return origin + (p - bounds.get_center()) * scale

	var outline: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in hull:
		outline.append(place.call(point))
	_canvas.draw_colored_polygon(outline, HULL_FILL)
	outline.append(outline[0])
	_canvas.draw_polyline(outline, HULL, 1.0)

	var targets: Array[Node] = _targets()
	var chosen: Node = null
	if not targets.is_empty():
		_slot = posmod(_slot, targets.size())
		chosen = targets[_slot]

	for mount: Node in mounts:
		var at: Vector2 = place.call((mount as Node2D).position)
		var fits: bool = targets.has(mount)
		var colour: Color = PICK if mount == chosen else (FIT if fits else IDLE_MOUNT)
		if mount == chosen:
			_canvas.draw_arc(at, DOT_PICKED, 0.0, TAU, 12, colour, 1.0)
		_canvas.draw_circle(at, DOT, colour)
		# Every mount is named, not only the ones that fit: the schematic is
		# the map of where anything could go, and a dot with no name is a
		# place the pilot cannot ask about.
		# Names go outward, away from the hull. Inward they meet in the middle
		# and the two halves of every mirrored pair print over each other.
		var label: Vector2 = at + Vector2(DOT + 3.0, float(FONT_SIZE) * 0.4)
		if at.x < origin.x - 0.5:
			label.x = at.x - DOT - 3.0 - _width(font, mount.name)
		_text(font, label, mount.name, colour)


func _draw_info(font: Font, rect: Rect2) -> void:
	var x: float = rect.position.x + PAD
	var y: float = rect.position.y + PAD + float(FONT_SIZE)
	var picked: Dictionary = _selected()

	if picked.is_empty():
		_text(font, Vector2(x, y), "nic nie wybrano", LABEL)
		_text(font, Vector2(x, y + ROW * 2.0), _keys(), LABEL)
		return

	var item: Resource = picked["item"]
	for line: String in _describe(item):
		_text(font, Vector2(x, y), line, TEXT)
		y += ROW

	if not _notice.is_empty():
		_text(font, Vector2(x, y), _notice.left(88), WARN)
	_text(font, Vector2(x, rect.end.y - PAD), _keys(), LABEL)


func _keys() -> String:
	return "strzałki: wybór / gniazdo    F: montuj    S: schowaj    Backspace: za burtę    Esc: zamknij"


func _label(item: Resource) -> String:
	if item is WeaponData:
		return (item as WeaponData).display_name
	if item is EngineData:
		return "%s engine %.0f" % [
			EngineData.Type.keys()[int((item as EngineData).type)].to_lower(),
			(item as EngineData).max_thrust,
		]
	return "moduł"


func _describe(item: Resource) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	out.append("%s   gabaryt %.2f" % [_label(item), Ship.module_bulk(item)])
	if item is WeaponData:
		var weapon: WeaponData = item as WeaponData
		out.append("obrażenia %.2f x %.1f/s = %.2f dps   rozrzut %.1f st   zasięg %.0f   krater %.0f" % [
			weapon.damage,
			weapon.rounds_per_second,
			weapon.damage_per_second(),
			weapon.spread_degrees,
			weapon.range_px,
			weapon.crater_radius,
		])
	elif item is EngineData:
		var engine: EngineData = item as EngineData
		out.append("ciąg %.0f   rozruch %.2f s   niezawodność %.2f   paliwo %.2f" % [
			engine.max_thrust, engine.spool_time, engine.reliability, engine.fuel_cost,
		])
	return out
