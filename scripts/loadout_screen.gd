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

## A floor, not a width: the panel takes whatever the longest card line needs,
## and this only keeps an empty hold from collapsing to a sliver.
const PANEL_WIDTH: float = 210.0
const FONT_SIZE: int = 8
const SCREEN_MARGIN: int = 6


var _ship: Ship = null
var _panel: PanelContainer = null
var _text: Label = null

## Which compatible slot is highlighted. Kept as an index into the list the
## screen last built, and clamped on every redraw, so a slot disappearing
## under it cannot leave the cursor pointing at nothing.
var _cursor: int = 0

## What the last swap did, from ConfigurationReport.compare(). Kept until the
## next one: "was that an upgrade" is the question the pilot came to the
## screen for, and it must not vanish on the next redraw.
var _report: PackedStringArray = PackedStringArray()


## The twelve colours every screen draws from (UI_STYLE section 3). This
## file used to spell out its own, which is how three screens ended up
## with two panel fills, two borders and three ambers a pixel apart.
var _ink: Palette = Palette.current()

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
			_ship.jettison()
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Transparent to the mouse. A MarginContainer is chrome with no pixels of
	# its own, but Control defaults to MOUSE_FILTER_STOP, so a full-rect one
	# swallows every click on the whole screen -- including clicks meant for
	# a panel on a lower CanvasLayer, and including while its own panel is
	# hidden. Children are still picked normally; only this node steps out of
	# the way.
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, SCREEN_MARGIN)
	add_child(margin)

	var compact: Theme = Theme.new()
	compact.default_font_size = FONT_SIZE
	var background: StyleBoxFlat = StyleBoxFlat.new()
	background.bg_color = _ink.over(_ink.panel, 0.94)
	background.border_color = _ink.edge
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
	_text.add_theme_font_override("font", ModuleData.card_font())
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
	# Measured before the swap, because the only honest way to say what a
	# module did is to have measured the ship without it.
	var before: ConfigurationReport = _ship.configuration()
	var taken: Resource = _ship.release()

	var removed: Resource = null
	if slot is Hardpoint:
		removed = (slot as Hardpoint).fit(taken as WeaponData)
	elif slot is EngineMount:
		removed = _ship.fit_engine(slot as EngineMount, taken as EngineData)

	_report = _ship.configuration().compare(before)

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
	lines.append("HOLD   (Tab closes)")

	if _ship.carried == null:
		lines.append("")
		lines.append("empty - fly into a crate")
		lines.append_array(_report_lines())
		_text.text = "\n".join(lines)
		_text.add_theme_color_override("font_color", _ink.label)
		return

	var slots: Array = _slots()

	# The same card the editor shows, against whatever it would replace.
	# Two screens formatting their own would be two things disagreeing about
	# what a weapon is, and in flight the difference is the only part worth
	# reading anyway.
	var replacing: ModuleData = null
	if not slots.is_empty():
		replacing = _fitted_in(slots[posmod(_cursor, slots.size())])
	lines.append("")
	var carried: ModuleData = _ship.carried as ModuleData
	if carried != null:
		for line: String in carried.card_lines(replacing):
			lines.append(line)
	lines.append("")
	if slots.is_empty():
		for line: String in _why_nothing_fits():
			lines.append(line)
	else:
		_cursor = posmod(_cursor, slots.size())
		lines.append("socket (down arrow changes it):")
		for i: int in range(slots.size()):
			var slot: Node = slots[i]
			var marker: String = ">" if i == _cursor else " "
			lines.append("%s %s  %s" % [marker, slot.name, _fitted_label(slot)])
		lines.append("")
		lines.append("F montuje,  Backspace wyrzuca")

	lines.append_array(_report_lines())

	_text.text = "\n".join(lines)
	_text.add_theme_color_override("font_color", _ink.caution if not slots.is_empty() else _ink.label)


## The last swap, as the configuration report saw it. Shown under the slots
## rather than in a popup: the pilot is still flying, and the point of these
## lines is that they can be glanced at.
func _report_lines() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if _report.is_empty():
		return out
	out.append("")
	out.append("-- after the swap --")
	out.append_array(_report)
	return out


## Why the carried module has nowhere to go. "No slot" is not an answer the
## pilot can act on: too big for this hull is a reason to keep looking for a
## bigger ship, the wrong kind is a reason to stop carrying it.
func _why_nothing_fits() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("no socket it fits")
	var engine: EngineData = _ship.carried as EngineData
	if engine == null:
		return lines

	var largest: float = 0.0
	for mount: EngineMount in _ship.engine_mounts():
		if mount.accepts(engine.type):
			largest = maxf(largest, mount.size)
	if largest <= 0.0:
		lines.append("this hull does not take that kind")
	else:
		lines.append("bulk %.2f, largest socket %.2f" % [engine.bulk, largest])
	return lines


## What is fitted in a slot, so a swap is a comparison rather than a leap.
func _fitted_in(slot: Node) -> ModuleData:
	if slot is Hardpoint:
		return (slot as Hardpoint).weapon
	if slot is EngineMount:
		return (slot as EngineMount).installed
	if slot is ModuleBay:
		return (slot as ModuleBay).installed
	if slot is LandingGear:
		return (slot as LandingGear).installed
	return null


## A one-line summary of what is in a slot, for the slot list.
func _fitted_label(slot: Node) -> String:
	var fitted: ModuleData = _fitted_in(slot)
	return "empty" if fitted == null else fitted.title()
