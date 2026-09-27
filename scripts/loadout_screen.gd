class_name LoadoutScreen
extends CanvasLayer
## The simple screen for swapping a module in flight (Tab).
##
## Deliberately does not pause. "In flight" means without landing or docking,
## not without time passing: a swap that stops the world is a menu, and the
## interesting version of this decision is the one made while something is
## going wrong. The screen is small, off to one side, and every action is one
## key, so it can be used with the other hand.
##
## One carried module, one highlighted slot, one key to fit. Everything else
## about loadouts is M5's business.

const PANEL_WIDTH: float = 210.0
const FONT_SIZE: int = 8
const SCREEN_MARGIN: int = 6

const BACKGROUND: Color = Color(0.07, 0.07, 0.09, 0.94)
const BORDER: Color = Color(0.45, 0.50, 0.60, 1.0)
const DIM: Color = Color(0.70, 0.74, 0.80)
const PICK: Color = Color(1.00, 0.85, 0.35)

var _ship: Ship = null
var _panel: PanelContainer = null
var _text: Label = null

## Which compatible slot is highlighted. Kept as an index into the list the
## screen last built, and clamped on every redraw, so a slot disappearing
## under it cannot leave the cursor pointing at nothing.
var _cursor: int = 0


func _ready() -> void:
	layer = 15
	_build_ui()
	_panel.hide()


func bind(ship: Ship) -> void:
	if _ship != null and _ship.hold_changed.is_connected(_on_hold_changed):
		_ship.hold_changed.disconnect(_on_hold_changed)
	_ship = ship
	if _ship != null:
		_ship.hold_changed.connect(_on_hold_changed)
	_redraw()


func is_open() -> bool:
	return _panel.visible


func toggle() -> void:
	_panel.visible = not _panel.visible
	_redraw()


## Opens the screen because something was picked up. The pilot asked for the
## module, not for the screen, so this is the one place it opens itself.
func announce_pickup() -> void:
	_cursor = 0
	_panel.show()
	_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_loadout"):
		toggle()
		get_viewport().set_input_as_handled()
		return
	if not is_open():
		return
	if event.is_action_pressed(&"loadout_next"):
		_cursor += 1
		_redraw()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"loadout_fit"):
		_fit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"loadout_drop"):
		if _ship != null:
			_ship.release()
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, SCREEN_MARGIN)
	add_child(margin)

	var compact: Theme = Theme.new()
	compact.default_font_size = FONT_SIZE
	var background: StyleBoxFlat = StyleBoxFlat.new()
	background.bg_color = BACKGROUND
	background.border_color = BORDER
	background.set_border_width_all(1)
	background.set_content_margin_all(4)
	compact.set_stylebox("panel", "PanelContainer", background)

	_panel = PanelContainer.new()
	_panel.theme = compact
	# Bottom left, opposite the planet readout and clear of the landing HUD.
	_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_panel.size_flags_vertical = Control.SIZE_SHRINK_END
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	margin.add_child(_panel)

	_text = Label.new()
	_text.add_theme_constant_override("line_spacing", 0)
	_panel.add_child(_text)


## The slots the carried module could go into, in a stable order.
func _slots() -> Array:
	var slots: Array = []
	if _ship == null or _ship.carried == null:
		return slots
	if _ship.carried is WeaponData:
		for mount: Hardpoint in _ship.hardpoints:
			if mount.can_fit(_ship.carried as WeaponData):
				slots.append(mount)
	elif _ship.carried is EngineData:
		for mount: EngineMount in _ship.engine_mounts():
			if _ship.mount_accepts(mount, _ship.carried as EngineData):
				slots.append(mount)
	return slots


func _fit() -> void:
	var slots: Array = _slots()
	if slots.is_empty() or _ship == null:
		return
	var slot: Node = slots[_cursor % slots.size()]
	var taken: Resource = _ship.release()

	var removed: Resource = null
	if slot is Hardpoint:
		removed = (slot as Hardpoint).fit(taken as WeaponData)
	elif slot is EngineMount:
		removed = _ship.fit_engine(slot as EngineMount, taken as EngineData)

	# Whatever came out goes into the hold, so a swap is never a loss and the
	# pilot can put the old module back if the new one turns out worse.
	if removed != null:
		_ship.take(removed, 0)
	else:
		_redraw()


## What the panel currently says. The label is the only place the screen's
## reasoning becomes visible, so the test reads it rather than re-deriving it.
func panel_text() -> String:
	return "" if _text == null else _text.text


func _on_hold_changed(_item: Resource) -> void:
	_cursor = 0
	_redraw()


func _redraw() -> void:
	if _text == null or not is_open():
		return
	if _ship == null:
		_text.text = "no ship"
		return

	var lines: PackedStringArray = PackedStringArray()
	lines.append("ŁADOWNIA   (Tab zamyka)")

	if _ship.carried == null:
		lines.append("")
		lines.append("pusto - wleć w skrzynkę")
		_text.text = "\n".join(lines)
		_text.add_theme_color_override("font_color", DIM)
		return

	lines.append("")
	for line: String in _describe(_ship.carried):
		lines.append(line)

	var slots: Array = _slots()
	lines.append("")
	if slots.is_empty():
		for line: String in _why_nothing_fits():
			lines.append(line)
	else:
		_cursor = posmod(_cursor, slots.size())
		lines.append("gniazdo (strzałka w dół zmienia):")
		for i: int in range(slots.size()):
			var slot: Node = slots[i]
			var marker: String = ">" if i == _cursor else " "
			lines.append("%s %s  %s" % [marker, slot.name, _fitted_label(slot)])
		lines.append("")
		lines.append("F montuje,  Backspace wyrzuca")

	_text.text = "\n".join(lines)
	_text.add_theme_color_override("font_color", PICK if not slots.is_empty() else DIM)


## Why the carried module has nowhere to go. "No slot" is not an answer the
## pilot can act on: too big for this hull is a reason to keep looking for a
## bigger ship, the wrong kind is a reason to stop carrying it.
func _why_nothing_fits() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("brak pasującego gniazda")
	var engine: EngineData = _ship.carried as EngineData
	if engine == null:
		return lines

	var largest: float = 0.0
	for mount: EngineMount in _ship.engine_mounts():
		if mount.accepts(engine.type):
			largest = maxf(largest, mount.size)
	if largest <= 0.0:
		lines.append("ten kadłub nie bierze tego typu")
	else:
		lines.append("gabaryt %.2f, największe gniazdo %.2f" % [engine.bulk, largest])
	return lines


## What is already in a slot, so a swap is a comparison rather than a leap.
func _fitted_label(slot: Node) -> String:
	if slot is Hardpoint:
		var weapon: WeaponData = (slot as Hardpoint).weapon
		return "pusty" if weapon == null else weapon.display_name
	if slot is EngineMount:
		var engine: EngineData = (slot as EngineMount).installed
		if engine == null:
			return "pusty"
		return "%s %.0f  %.2f/%.2f" % [
			EngineData.Type.keys()[int(engine.type)].to_lower(),
			engine.max_thrust,
			engine.bulk,
			(slot as EngineMount).size,
		]
	return "?"


func _describe(item: Resource) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	if item is WeaponData:
		var weapon: WeaponData = item as WeaponData
		lines.append(weapon.display_name)
		lines.append("obrażenia %.2f x %.1f/s = %.2f dps" % [
			weapon.damage, weapon.rounds_per_second, weapon.damage_per_second(),
		])
		lines.append("rozrzut %.1f st   zasięg %.0f" % [weapon.spread_degrees, weapon.range_px])
		lines.append("krater %.0f   prędkość %.0f" % [weapon.crater_radius, weapon.muzzle_speed])
	elif item is EngineData:
		var engine: EngineData = item as EngineData
		lines.append("%s engine" % EngineData.Type.keys()[int(engine.type)].to_lower())
		lines.append("ciąg %.0f   rozruch %.2f s" % [engine.max_thrust, engine.spool_time])
		lines.append("gabaryt %.2f" % engine.bulk)
		lines.append("niezawodność %.2f   paliwo %.2f" % [engine.reliability, engine.fuel_cost])
	else:
		lines.append("nieznany moduł")
	return lines
