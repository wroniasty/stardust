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
## Looking is free; changing is not. The screen opens anywhere -- planning a
## refit on the way home is a reasonable thing to do -- but bolting a module
## on needs the ship on the ground. That gives a landing pad a purpose beyond
## being somewhere not to die, without the screen refusing to open and
## refusing to say why. Throwing something overboard stays available in
## flight: dumping ballast under pressure is exactly the decision worth
## having.
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

## How far one press swings a hardpoint's rest direction. Five degrees: fine
## enough to place a gun deliberately, coarse enough that pointing one across
## the ship is not a hundred presses.
const AIM_STEP: float = deg_to_rad(5.0)

## How long the arc wedge is drawn on the schematic, in panel pixels.
const ARC_LENGTH: float = 16.0

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

## What fitting the selected module into the highlighted slot would do,
## worked out by fitting it, measuring, and putting things back. Cached
## against the selection rather than recomputed every frame: the answer only
## changes when the selection does, and a speculative rebuild per frame is
## work nobody asked for.
var _preview: PackedStringArray = PackedStringArray()
var _preview_key: String = ""




func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Takes the mouse while it is open, and only then: the node is hidden the
	# rest of the time, so the game never loses a click to an unseen panel.
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.gui_input.connect(_on_click)
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
	PauseGate.hold_exclusive(self, get_tree())


func close() -> void:
	_canvas.hide()
	PauseGate.release(self, get_tree())


func _process(_delta: float) -> void:
	if is_open():
		_refresh_preview()
		_canvas.queue_redraw()
	else:
		# Guard against leaving the game paused with nothing on screen to
		# explain it. Releases only this screen's own claim -- releasing
		# everyone's is what broke the pause when there were two screens.
		PauseGate.release(self, get_tree())


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
	elif event.is_action_pressed(&"editor_aim_ccw"):
		_turn_mount(-AIM_STEP)
	elif event.is_action_pressed(&"editor_aim_cw"):
		_turn_mount(AIM_STEP)
	elif event.is_action_pressed(&"editor_trigger"):
		_swap_trigger()
	else:
		return
	get_viewport().set_input_as_handled()


## Whether the ship is somewhere a module can be changed. Docking joins this
## when there is anything to dock to.
func can_refit() -> bool:
	return _ship != null and _ship.flight_mode == Ship.FlightMode.LANDED


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
	elif item is GeneratorData:
		if _ship.generator_bay != null and _ship.generator_bay.fits(item as GeneratorData):
			out.append(_ship.generator_bay)
	elif item is FlightComputerData:
		if _ship.computer_bay != null and _ship.computer_bay.fits(item as FlightComputerData):
			out.append(_ship.computer_bay)
	elif item is GearData:
		if _ship.gear != null:
			out.append(_ship.gear)
	elif item is ShotModData:
		# A mod goes into a gun, not into a socket on the hull, so the
		# targets are the weapons with a slot free rather than the mounts.
		for mount: Hardpoint in _ship.hardpoints:
			if mount.weapon != null and mount.mods.size() < mount.weapon.mod_slots:
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
	if _ship.generator_bay != null:
		out.append(_ship.generator_bay)
	if _ship.computer_bay != null:
		out.append(_ship.computer_bay)
	if _ship.gear != null:
		out.append(_ship.gear)
	return out


func _fit() -> void:
	var targets: Array[Node] = _targets()
	var picked: Dictionary = _selected()
	if targets.is_empty() or picked.is_empty():
		_notice = "nie ma gdzie tego zamontować"
		return

	if not can_refit():
		_notice = "montaż tylko na ziemi — wyląduj albo użyj Tab w locie"
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
	if slot is Hardpoint and item is ShotModData:
		# Plugging a mod in is not a swap -- nothing comes back out -- so it
		# takes the item and leaves `removed` null.
		if not (slot as Hardpoint).add_mod(item as ShotModData):
			_ship.take(item, 0)
			_notice = "nie ma wolnego gniazda w tej broni"
			return
	elif slot is Hardpoint:
		removed = (slot as Hardpoint).fit(item as WeaponData)
	elif slot is EngineMount:
		removed = _ship.fit_engine(slot as EngineMount, item as EngineData)
	elif slot is GeneratorBay:
		var bay: GeneratorBay = slot as GeneratorBay
		removed = bay.installed
		bay.installed = item as GeneratorData
	elif slot is ComputerBay:
		var box: ComputerBay = slot as ComputerBay
		removed = box.installed
		box.installed = item as FlightComputerData
	elif slot is LandingGear:
		var legs: LandingGear = slot as LandingGear
		removed = legs.installed
		legs.installed = item as GearData

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


## Works out what fitting would do without committing to it: bolt the module
## in, measure, put everything back exactly as it was.
##
## Only engines move the control groups -- a weapon is compared on its own
## numbers instead, further down -- so this is the engine half of the answer.
func _refresh_preview() -> void:
	var picked: Dictionary = _selected()
	var targets: Array[Node] = _targets()
	var key: String = "%d/%d/%d" % [_pick, _slot, targets.size()]
	if key == _preview_key:
		return
	_preview_key = key
	_preview = PackedStringArray()
	if picked.is_empty() or targets.is_empty():
		return

	var mount: EngineMount = targets[posmod(_slot, targets.size())] as EngineMount
	var candidate: EngineData = picked["item"] as EngineData
	if mount == null or candidate == null:
		return

	var before: ConfigurationReport = _ship.configuration()
	var previous: EngineData = mount.installed
	mount.installed = candidate
	_ship.rebuild_control_groups(false)
	_preview = _ship.configuration().compare(before)
	mount.installed = previous
	_ship.rebuild_control_groups(false)


## The one-line answer to "is this better", for whichever kind of module is
## selected. Engines are compared through the control groups, because where
## an engine goes decides what it does; a weapon is the same gun wherever it
## is bolted, so it is compared against the gun already in the slot.
func _verdict() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var targets: Array[Node] = _targets()
	var picked: Dictionary = _selected()
	if targets.is_empty() or picked.is_empty():
		return out
	var slot: Node = targets[posmod(_slot, targets.size())]

	if slot is Hardpoint:
		var fitted: WeaponData = (slot as Hardpoint).weapon
		var candidate: WeaponData = picked["item"] as WeaponData
		if fitted == null:
			out.append("%s: pusty" % slot.name)
		elif candidate != null:
			out.append("%s: %s  dps %.2f -> %.2f   rozrzut %.1f -> %.1f   krater %.0f -> %.0f" % [
				slot.name,
				fitted.display_name,
				fitted.damage_per_second(),
				candidate.damage_per_second(),
				fitted.spread_degrees,
				candidate.spread_degrees,
				fitted.crater_radius,
				candidate.crater_radius,
			])
		return out

	out.append("%s: %s" % [
		slot.name, "bez zmian w sterowaniu" if _preview.is_empty() else ", ".join(_preview),
	])
	return out


## Swings the highlighted hardpoint's rest direction.
##
## Where a gun sits belongs to the hull, not to the gun, so it is set here
## and never rolled with the weapon.
func _turn_mount(by: float) -> void:
	var slot: Hardpoint = _highlighted() as Hardpoint
	if slot == null:
		_notice = "obrót ustawia się na gnieździe broni"
		return
	slot.rotation = wrapf(slot.rotation + by, -PI, PI)
	_notice = "%s celuje %.0f st od dziobu" % [slot.name, rad_to_deg(slot.rotation)]


## Moves the highlighted hardpoint to the other trigger.
func _swap_trigger() -> void:
	var slot: Hardpoint = _highlighted() as Hardpoint
	if slot == null:
		_notice = "spust przypisuje się do gniazda broni"
		return
	slot.trigger = 1 - slot.trigger
	_notice = "%s na %s spust" % [slot.name, "lewy" if slot.trigger == 0 else "prawy"]


## The mount the slot cursor is on, whatever kind it is. Falls back to the
## whole schematic so a mount can still be adjusted with an empty hold.
func _highlighted() -> Node:
	var targets: Array[Node] = _targets()
	if not targets.is_empty():
		return targets[posmod(_slot, targets.size())]
	var mounts: Array[Node] = _all_mounts()
	return null if mounts.is_empty() else mounts[posmod(_slot, mounts.size())]


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


## A click picks whatever is under it: a row in the list, or a mount on the
## schematic. Only mounts the selected module fits can be picked, because the
## slot cursor indexes the list of those and pointing it at anything else
## would mean two ways of saying "nowhere".
func _on_click(event: InputEvent) -> void:
	var press: InputEventMouseButton = event as InputEventMouseButton
	if press == null or not press.pressed or press.button_index != MOUSE_BUTTON_LEFT:
		return
	if click_at(press.position):
		_canvas.accept_event()


## Turns a point on screen into a selection. Public so the behaviour can be
## driven without a mouse or a rendered frame. True when something was hit.
func click_at(at: Vector2) -> bool:
	if _ship == null:
		return false
	var panels: Dictionary = _panels()

	for i: int in range(_items().size()):
		if _row_rect(i, panels["list"]).has_point(at):
			_pick = i
			_slot = 0
			return true

	var place: Callable = _plan_placement(panels["plan"])
	var targets: Array[Node] = _targets()
	for mount: Node in _all_mounts():
		if at.distance_to(place.call((mount as Node2D).position)) > DOT_PICKED + 2.0:
			continue
		var index: int = targets.find(mount)
		if index >= 0:
			_slot = index
		else:
			_notice = "%s nie przyjmie tego modułu" % mount.name
		return true
	return false


## Where the three panels go. A function of the viewport and nothing else,
## so a click can be resolved without waiting for a frame to have been drawn
## -- the earlier version read back what the last _draw left behind, which
## made mouse input untestable and wrong before the first frame.
func _panels() -> Dictionary:
	var view: Vector2 = _canvas.size
	var list: Rect2 = Rect2(6.0, 6.0, view.x * 0.34, view.y * 0.72)
	return {
		"view": view,
		"list": list,
		"plan": Rect2(list.end.x + 6.0, 6.0, view.x - list.end.x - 12.0, view.y * 0.72),
		"info": Rect2(6.0, list.end.y + 6.0, view.x - 12.0, view.y - list.end.y - 12.0),
	}


## The clickable box of one row of the list.
func _row_rect(index: int, list: Rect2) -> Rect2:
	var top: float = list.position.y + PAD + float(FONT_SIZE) + ROW * (1.5 + float(index))
	return Rect2(
		list.position.x + PAD - 2.0,
		top - float(FONT_SIZE),
		list.size.x - PAD * 2.0 + 2.0,
		ROW,
	)


## Maps a point in the ship's own frame onto the schematic, fitting the hull
## and every mount into the panel with room for the names beside the dots.
func _plan_placement(plan: Rect2) -> Callable:
	var bounds: Rect2 = Rect2(Vector2.ZERO, Vector2.ZERO)
	var first: bool = true
	for point: Vector2 in _ship.hull_outline:
		bounds = Rect2(point, Vector2.ZERO) if first else bounds.expand(point)
		first = false
	for mount: Node in _all_mounts():
		bounds = bounds.expand((mount as Node2D).position)
	bounds = bounds.grow(2.0)

	# Generous horizontal padding: every dot prints its name beside it, and
	# the names are wider than the ship is.
	var room: Vector2 = plan.size - Vector2(plan.size.x * 0.52, PAD * 4.0 + float(FONT_SIZE))
	var scale: float = minf(room.x / bounds.size.x, room.y / bounds.size.y)
	var origin: Vector2 = plan.position + Vector2(plan.size.x * 0.5, plan.size.y * 0.55)
	var centre: Vector2 = bounds.get_center()
	return func(p: Vector2) -> Vector2:
		return origin + (p - centre) * scale


func _draw_editor() -> void:
	var font: Font = _canvas.get_theme_default_font()
	if font == null or _ship == null:
		return
	var panels: Dictionary = _panels()

	_canvas.draw_rect(Rect2(Vector2.ZERO, panels["view"] as Vector2), SCRIM)
	for key: String in ["list", "plan", "info"]:
		_panel(panels[key])
	_draw_list(font, panels["list"])
	_draw_plan(font, panels["plan"])
	_draw_info(font, panels["info"])


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
		_ship.cargo_used(), _ship.cargo_capacity(),
	], LABEL)
	y += ROW * 1.5

	var items: Array[Dictionary] = _items()
	if items.is_empty():
		_text(font, Vector2(x, y), "pusto", LABEL)
		return

	for i: int in range(items.size()):
		var entry: Dictionary = items[i]
		var item: Resource = entry["item"]
		var module: ModuleData = item as ModuleData
		var colour: Color = (
			ModuleData.RARITY_COLORS[0] if module == null else module.rarity_color()
		)
		if i == _pick:
			_canvas.draw_rect(_row_rect(i, rect), Color(PICK, 0.18))
		_text(font, Vector2(x, y), "%s %-22s %4.1f" % [
			">" if bool(entry["held"]) else " ", _label(item).left(22), Ship.module_bulk(item),
		], colour if i != _pick else PICK)
		y += ROW


## The schematic, built from the hull polygon and the mount positions so it
## cannot disagree with the ship it describes.
func _draw_plan(font: Font, rect: Rect2) -> void:
	_text(font, rect.position + Vector2(PAD, PAD + float(FONT_SIZE)), "SCHEMAT", LABEL)

	var hull: PackedVector2Array = _ship.hull_outline
	var mounts: Array[Node] = _all_mounts()
	if hull.size() < 3:
		return

	var place: Callable = _plan_placement(rect)
	var origin: Vector2 = rect.position + Vector2(rect.size.x * 0.5, rect.size.y * 0.55)

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
		var caption: String = mount.name
		var gun: Hardpoint = mount as Hardpoint
		if gun != null:
			caption = "%s %s" % [mount.name, "L" if gun.trigger == 0 else "P"]
			if gun.weapon != null and gun.weapon.mod_slots > 0:
				caption += " %d/%d" % [gun.mods.size(), gun.weapon.mod_slots]
			_draw_arc_for(gun, at)
		var label: Vector2 = at + Vector2(DOT + 3.0, float(FONT_SIZE) * 0.4)
		if at.x < origin.x - 0.5:
			label.x = at.x - DOT - 3.0 - _width(font, caption)
		_text(font, label, caption, colour)


## The wedge a gun can cover, from its rest direction. A number in a panel
## does not tell a pilot whether the nose gun reaches behind the wing; a
## wedge on the schematic does.
func _draw_arc_for(gun: Hardpoint, at: Vector2) -> void:
	var arc: float = gun.traverse()
	var rest: float = gun.rotation - PI * 0.5
	var colour: Color = Color(FIT, 0.35) if gun.trigger == 0 else Color(PICK, 0.35)
	if arc <= 0.0:
		# A fixed gun still shows which way it looks, as one line: the
		# absence of an arc is information too.
		_canvas.draw_line(at, at + Vector2.from_angle(rest) * ARC_LENGTH, colour, 1.0)
		return
	_canvas.draw_arc(at, ARC_LENGTH, rest - arc, rest + arc, 16, colour, 1.0)
	for edge: float in [rest - arc, rest + arc]:
		_canvas.draw_line(at, at + Vector2.from_angle(edge) * ARC_LENGTH, colour, 1.0)


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

	# What the swap would do, before anything is committed. The reason to
	# come to this screen rather than press Tab and find out.
	y += ROW * 0.4
	for line: String in _verdict():
		_text(font, Vector2(x, y), line.left(96), FIT)
		y += ROW

	if not _notice.is_empty():
		_text(font, Vector2(x, y), _notice.left(96), WARN)

	var state: String = "NA ZIEMI — montaż dostępny" if can_refit() else "W LOCIE — montaż po wylądowaniu"
	_text(
		font,
		Vector2(rect.end.x - PAD - _width(font, state), rect.position.y + PAD + float(FONT_SIZE)),
		state,
		FIT if can_refit() else WARN,
	)
	_text(font, Vector2(x, rect.end.y - PAD), _keys(), LABEL)


func _keys() -> String:
	return "strzałki: wybór   F: montuj   S: schowaj   , .: obrót   G: spust   Bksp: za burtę"


func _label(item: Resource) -> String:
	if item is WeaponData:
		return (item as WeaponData).display_name
	if item is EngineData:
		return "%s engine %.0f" % [
			EngineData.Type.keys()[int((item as EngineData).type)].to_lower(),
			(item as EngineData).max_thrust,
		]
	if item is GeneratorData:
		return (item as GeneratorData).display_name
	if item is FlightComputerData:
		return (item as FlightComputerData).display_name
	if item is GearData:
		return (item as GearData).display_name
	if item is ShotModData:
		return (item as ShotModData).display_name
	return "moduł"


func _describe(item: Resource) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var module: ModuleData = item as ModuleData
	out.append("%s   %s   gabaryt %.2f" % [
		_label(item),
		"" if module == null else module.rarity_name(),
		Ship.module_bulk(item),
	])
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
	elif item is ShotModData:
		var mod: ShotModData = item as ShotModData
		out.append("koszt strzału x%.2f   efekt: %s" % [
			mod.energy_multiplier,
			ShotModData.Effect.keys()[int(mod.effect)].to_lower(),
		])
	elif item is GearData:
		var legs: GearData = item as GearData
		out.append("opada %.0f px/s   w bok %.0f px/s   przechył %.0f st   nachylenie %.0f st" % [
			legs.max_vertical_speed,
			legs.max_lateral_speed,
			rad_to_deg(legs.max_tilt),
			rad_to_deg(legs.max_slope),
		])
	elif item is FlightComputerData:
		var box: FlightComputerData = item as FlightComputerData
		var has: PackedStringArray = PackedStringArray()
		if box.allocation == FlightComputerData.Allocation.NNLS:
			has.append("rozdział ciągu")
		if box.has_auto_level:
			has.append("auto-poziom")
		if box.has_auto_orbit:
			has.append("auto-orbita")
		out.append("funkcje: %s" % (", ".join(has) if not has.is_empty() else "żadne"))
		out.append("pobór %.1f/s" % box.idle_draw)
	elif item is GeneratorData:
		var cell: GeneratorData = item as GeneratorData
		out.append("pojemność %.0f   ładowanie %.0f/s   cisza %.2f s   pułap %.0f/s" % [
			cell.capacity,
			cell.recharge_rate,
			cell.recharge_delay,
			cell.sustained_throughput(INF),
		])
	return out
