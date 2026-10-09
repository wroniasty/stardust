class_name CreativeTool
extends CanvasLayer
## The sandbox: conjure any module into the hold, and reshape the hull.
##
## A development tool, and the honest reason it exists is that most of what
## M2 built can only be judged by flying it. Rolling for a gimballed drive
## until one drops is not testing the gimbal, and the hull outline work was
## done so the solver would cope with shapes that do not exist yet -- which
## is a claim nobody can check without a way to make one.
##
## Opens like the planet configurator (`T`), pauses through the same gate,
## and lives in tools/ because it ships with nobody.

const TOGGLE_ACTION: StringName = &"debug_creative"

## The generator, by script rather than through the autoload. Autoloads do
## not exist under `--script`, so a tool that named the singleton could not
## be compiled by the smoke test.
const LOOT: GDScript = preload("res://scripts/autoload/loot_generator.gd")

## The hull list used to live here, as a const table of outlines. It is
## `resources/hulls/` now, read through `HullData.catalogue()` -- the same
## resources `ShipFitout` builds its presets from and the same ones the
## sprites are cut from. Three copies of a catalogue were two too many, and
## the test that held them in step was a prop rather than a fix.
##
## The spread is still the point of the list: a long thin hull and a wide
## flat one fail against the contact solver in different ways, and one of
## them is in there as a deliberately bad example.

## What the tool can conjure. Each one asks the real generator, so anything
## the sandbox produces is something the game could have dropped.
const KINDS: Array[String] = [
	"anything", "weapon", "engine", "generator", "computer", "gear", "shot mod",
]

const PANEL_WIDTH: float = 244.0
const FONT_SIZE: int = 8
const SCREEN_MARGIN: int = 6
const BACKGROUND: Color = Color(0.06, 0.07, 0.10, 0.97)
const BORDER: Color = Color(0.50, 0.45, 0.62, 1.0)

var _ship: Ship = null
var _loot: Node = null
var _panel: PanelContainer = null
var _kind: OptionButton = null
var _rarity: OptionButton = null
var _seed_spin: SpinBox = null
var _shape: OptionButton = null
var _fitout: OptionButton = null
var _scale: SpinBox = null
var _status: Label = null
var _report: Label = null


func _ready() -> void:
	layer = 21
	process_mode = Node.PROCESS_MODE_ALWAYS
	_loot = LOOT.new()
	add_child(_loot)
	_build_ui()
	_panel.hide()


func bind(ship: Ship) -> void:
	_ship = ship
	_refresh()


func is_open() -> bool:
	return _panel.visible


func toggle() -> void:
	if is_open():
		close()
		return
	_panel.show()
	PauseGate.hold_exclusive(self, get_tree())
	_refresh()


func close() -> void:
	_panel.hide()
	PauseGate.release(self, get_tree())


func _process(_delta: float) -> void:
	if not is_open():
		PauseGate.release(self, get_tree())


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(TOGGLE_ACTION):
		toggle()
		get_viewport().set_input_as_handled()
	elif is_open() and event.is_action_pressed(&"ui_cancel"):
		toggle()
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
	background.bg_color = BACKGROUND
	background.border_color = BORDER
	background.set_border_width_all(1)
	background.set_content_margin_all(4)
	compact.set_stylebox("panel", "PanelContainer", background)

	_panel = PanelContainer.new()
	_panel.theme = compact
	# Right-hand side, so it does not sit on top of the planet configurator.
	_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	_panel.size_flags_vertical = Control.SIZE_FILL
	margin.add_child(_panel)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel.add_child(scroll)

	var rows: VBoxContainer = VBoxContainer.new()
	rows.add_theme_constant_override("separation", 1)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)

	rows.add_child(_heading("SANDBOX - PAUSED - T / Esc closes"))

	rows.add_child(_heading("LOOT"))
	_kind = OptionButton.new()
	for kind: String in KINDS:
		_kind.add_item(kind)
	rows.add_child(_labelled("kind", _kind))

	_rarity = OptionButton.new()
	_rarity.add_item("z losowania")
	for grade: String in LOOT.RARITY_NAMES:
		_rarity.add_item(grade)
	rows.add_child(_labelled("rarity", _rarity))

	_seed_spin = SpinBox.new()
	_seed_spin.min_value = 0
	_seed_spin.max_value = 1000000000
	_seed_spin.step = 1
	_seed_spin.value = 1
	rows.add_child(_labelled("seed", _seed_spin))

	rows.add_child(_button("to the hold", _on_spawn))
	rows.add_child(_button("fill cargo", _on_fill))
	rows.add_child(_button("empty cargo", _on_empty))

	rows.add_child(_heading("CONFIGURATION"))
	_fitout = OptionButton.new()
	for preset: Dictionary in ShipFitout.all():
		_fitout.add_item(preset["name"])
	rows.add_child(_labelled("ship", _fitout))
	rows.add_child(_button("rebuild the ship", _on_refit))

	rows.add_child(_heading("HULL"))
	_shape = OptionButton.new()
	for hull: HullData in HullData.catalogue():
		_shape.add_item(hull.display_name)
	rows.add_child(_labelled("shape", _shape))

	_scale = SpinBox.new()
	_scale.min_value = 0.5
	_scale.max_value = 4.0
	_scale.step = 0.1
	_scale.value = 1.0
	rows.add_child(_labelled("scale", _scale))
	rows.add_child(_button("rebuild the hull", _on_reshape))

	rows.add_child(_heading("SHIP"))
	rows.add_child(_button("repair the ship", _on_repair_ship))
	rows.add_child(_button("repair the engines", _on_repair))
	rows.add_child(_button("recharge", _on_recharge))
	rows.add_child(_button("damage a random engine", _on_break))

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(_status)

	rows.add_child(_heading("REPORT"))
	_report = Label.new()
	_report.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(_report)


func _heading(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(0.72, 0.68, 0.92))
	return label


func _labelled(text: String, control: Control) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	var label: Label = Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(72.0, 0.0)
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


func _button(text: String, handler: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.pressed.connect(handler)
	return button


## One rolled module of the chosen kind. Everything goes through the real
## generator, so nothing the sandbox makes is something the game could not
## have dropped -- a tool that can conjure impossible items tests a game
## nobody is going to play.
func _roll() -> Resource:
	var item_seed: int = int(_seed_spin.value)
	var rarity: int = _rarity.selected - 1 if _rarity.selected > 0 else LOOT.ROLLED
	match KINDS[_kind.selected]:
		"weapon":
			return _loot.weapon(item_seed, rarity)
		"engine":
			return _loot.engine(item_seed, rarity)
		"generator":
			return _loot.generator(item_seed, rarity)
		"computer":
			return _loot.computer(item_seed, rarity)
		"gear":
			return _roll_gear(item_seed)
		"shot mod":
			return _loot.shot_mod(item_seed % LOOT.SHOT_MODS.size())
		_:
			return _loot.generate(item_seed, rarity)


## Gear has no generator of its own yet, so the sandbox rolls it here rather
## than pretending the tables can. Written where the gap is visible.
func _roll_gear(item_seed: int) -> GearData:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = item_seed
	var legs: GearData = GearData.new()
	legs.display_name = "test gear"
	legs.max_vertical_speed = rng.randf_range(25.0, 110.0)
	legs.max_lateral_speed = rng.randf_range(12.0, 60.0)
	legs.max_tilt = deg_to_rad(rng.randf_range(8.0, 35.0))
	legs.max_slope = deg_to_rad(rng.randf_range(10.0, 40.0))
	legs.bulk = rng.randf_range(0.6, 2.4)
	return legs


func _on_spawn() -> void:
	if _ship == null:
		return
	var item: Resource = _roll()
	if item == null:
		_say("the roll produced nothing")
		return
	# Into the hold if it is free, into cargo otherwise: the tool should not
	# make the pilot juggle to accept what it just made.
	if _ship.carried == null and _ship.take(item):
		_say("to the hold: %s" % _name_of(item))
	elif Ship.module_bulk(item) <= _ship.cargo_free():
		_ship.cargo.append({"item": item, "rarity": _grade(item)})
		_ship.rebuild_control_groups(false)
		_ship.cargo_changed.emit()
		_say("do cargo: %s" % _name_of(item))
	else:
		_say("no room for %s" % _name_of(item))
	_seed_spin.value = int(_seed_spin.value) + 1
	_refresh()


func _on_fill() -> void:
	if _ship == null:
		return
	var added: int = 0
	# Bounded rather than while-free: a run of tiny mods would otherwise fill
	# the bay with a hundred of them and the tool would look hung.
	for attempt: int in range(40):
		var item: Resource = _roll()
		if item == null or Ship.module_bulk(item) > _ship.cargo_free():
			_seed_spin.value = int(_seed_spin.value) + 1
			continue
		_ship.cargo.append({"item": item, "rarity": _grade(item)})
		_seed_spin.value = int(_seed_spin.value) + 1
		added += 1
	_ship.rebuild_control_groups(false)
	_ship.cargo_changed.emit()
	_say("added %d, holding %.1f / %.1f" % [
		added, _ship.cargo_used(), _ship.cargo_capacity(),
	])
	_refresh()


func _on_empty() -> void:
	if _ship == null:
		return
	_ship.cargo.clear()
	_ship.rebuild_control_groups(false)
	_ship.cargo_changed.emit()
	_say("cargo empty")
	_refresh()


## Swaps the hull for another outline and rebuilds everything derived from
## it. The whole reason the outline became one source is so that this is
## three calls rather than a scene edit.
## Rebuilds the ship as one of the presets: mounts, engines, guns, hull,
## hold and legs in one go.
##
## The hull comes with the fitout rather than being kept from whatever the
## shape picker last did, because a fitout is a ship and a ship is a shape
## with engines on it. Reshaping afterwards still works and is the
## interesting thing to do next: it is how you find out what a layout does
## on a hull it was not drawn for.
func _on_refit() -> void:
	if _ship == null:
		return
	var preset: Dictionary = ShipFitout.all()[_fitout.selected]
	ShipFitout.apply(_ship, preset)
	_scale.value = 1.0
	# The shape picker follows, so the two controls do not disagree about
	# what the ship currently is.
	var catalogue: Array[HullData] = HullData.catalogue()
	for i: int in range(catalogue.size()):
		if catalogue[i].id == preset["hull"]:
			_shape.selected = i
	_say("%s - %s. %d engines, %d guns, hold %.0f" % [
		preset["name"], preset["blurb"], _ship.engines.size(),
		_ship.hardpoints.size(), _ship.cargo_capacity(),
	])
	_refresh()


func _on_reshape() -> void:
	if _ship == null:
		return
	var chosen: HullData = HullData.catalogue()[_shape.selected]
	var factor: float = float(_scale.value)
	var outline: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in chosen.outline:
		outline.append(point * factor)

	_ship.hull_outline = outline
	_ship._build_contact_points()
	_ship._build_collision_shape()
	_ship.rebuild_control_groups(false)

	# The drawing follows here, which the game does not require: a real hull
	# is drawn and simulated as two different shapes on purpose, the outline
	# only matching closely enough not to look odd (IDEAS.md section 6). In a
	# sandbox that would mean reshaping the ship and seeing nothing change,
	# so the tool keeps them together and the distinction stays where it
	# belongs -- in ships someone actually authored.
	var drawn: Polygon2D = _ship.get_node_or_null("Hull") as Polygon2D
	if drawn != null:
		drawn.polygon = outline
	_say("%s x%.1f - %d contact points, %d solver passes" % [
		chosen.display_name, factor, _ship.contact_points().size(), _ship.contact_iterations(),
	])
	_refresh()


## Everything back to new: hull, engines and the pool.
##
## Kept beside the engines-only button rather than replacing it, because
## flying a sound hull on ruined engines is a different experiment from
## flying a ruined hull on sound ones, and the sandbox exists to be able
## to set up either.
func _on_repair_ship() -> void:
	if _ship == null:
		return
	_ship.repair_hull()
	_ship.repair_engines()
	_ship.energy = _ship.energy_capacity()
	_say("ship as new: hull 100%, engines, pool %.0f" % _ship.energy)
	_refresh()


func _on_repair() -> void:
	if _ship == null:
		return
	_ship.repair_engines()
	_say("engines as new")
	_refresh()


func _on_recharge() -> void:
	if _ship == null:
		return
	_ship.energy = _ship.energy_capacity()
	_say("pool full: %.0f" % _ship.energy)


func _on_break() -> void:
	if _ship == null or _ship.engines.is_empty():
		return
	var victim: EngineInstance = _ship.engines[randi() % _ship.engines.size()]
	victim.health = clampf(victim.health - 0.35, 0.0, 1.0)
	_say("%s na %.0f%%" % [victim.mount.name, victim.health * 100.0])
	_refresh()


func _say(text: String) -> void:
	if _status != null:
		_status.text = text


## The configuration report, live. Reshaping a hull is exactly the thing the
## outline guidelines were written for, and a tool that let someone build a
## bad one without saying so would be worse than no tool.
func _refresh() -> void:
	if _report == null or _ship == null:
		return
	var report: ConfigurationReport = _ship.configuration()
	var lines: PackedStringArray = PackedStringArray()
	lines.append("mass %.1f  inertia %.0f" % [_ship.mass, _ship.inertia])
	lines.append("cargo %.1f / %.1f" % [_ship.cargo_used(), _ship.cargo_capacity()])
	for finding: Dictionary in report.findings:
		lines.append("%s: %s" % [
			ConfigurationReport.Severity.keys()[int(finding["severity"])], finding["text"],
		])
	if report.findings.is_empty():
		lines.append("konfiguracja czysta")
	_report.text = "\n".join(lines)


## Name plus grade, because "to the hold: main engine" says nothing about
## whether the thing that just appeared is the legendary one that was asked
## for.
func _name_of(item: Resource) -> String:
	var module: ModuleData = item as ModuleData
	var grade: String = "" if module == null else " [%s]" % module.rarity_name()
	for property: String in ["display_name"]:
		if property in item:
			return String(item.get(property)) + grade
	return "module" + grade


func _grade(item: Resource) -> int:
	var module: ModuleData = item as ModuleData
	return module.rarity if module != null else 0
