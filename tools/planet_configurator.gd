class_name PlanetConfigurator
extends CanvasLayer
## Development tool (F6): edit a planet's parameters by hand, rebuild it, and
## get put down on one of its landing shelves.
##
## The point is the loop. Judging a world means flying to it, and flying to a
## world you just changed costs a minute of lifting off, transferring and
## landing again -- so in practice nobody changes anything and the sandbox
## stays one planet wide. This makes "what does 3 g with thin air feel like"
## a ten second question.
##
## Not shipped: this reaches straight into the planet's fields and teleports
## the player, which is exactly what a dev tool should do and exactly what a
## game should not.
##
## The UI is built in code on purpose. A dev tool grows a parameter every time
## someone wonders about one, and a line in FIELDS is a cheaper place to put it
## than a scene file that both this and the game would have to share.

## The key that opens and closes the panel. Handled here rather than in the
## world, because the world stops receiving input the moment the tool pauses
## the tree -- so a panel opened from there could never be closed again.
const TOGGLE_ACTION: StringName = &"debug_planet"

## Emitted after the planet has been rebuilt, so the world can put the ship
## somewhere that still exists.
signal rebuilt

## Emitted when the pilot asks for the next landing shelf.
signal teleport_requested

## Numeric parameters, in the order they appear. Ranges are generous rather
## than realistic: the tool is for finding out what the extremes feel like.
const FIELDS: Array[Dictionary] = [
	{"name": "surface_radius", "label": "promień", "min": 300.0, "max": 3000.0, "step": 10.0},
	{"name": "surface_gravity", "label": "grawitacja", "min": 1.0, "max": 200.0, "step": 1.0},
	{"name": "influence_radius", "label": "zasięg pola", "min": 1000.0, "max": 20000.0, "step": 100.0},
	{"name": "atmosphere_height", "label": "atmosfera h", "min": 0.0, "max": 2000.0, "step": 10.0},
	{"name": "atmosphere_density", "label": "atmosfera gęst", "min": 0.0, "max": 1.0, "step": 0.05},
	{"name": "spin_rate", "label": "obrót rad/s", "min": -0.2, "max": 0.2, "step": 0.005},
	{"name": "plateau_count", "label": "lądowiska", "min": 0.0, "max": 40.0, "step": 1.0, "int": true},
	{"name": "cloud_coverage", "label": "chmury pokrycie", "min": 0.0, "max": 2.0, "step": 0.05},
	{"name": "cloud_opacity", "label": "chmury krycie", "min": 0.0, "max": 1.0, "step": 0.05},
]

const PANEL_WIDTH: float = 250.0

var _planet: Planet = null
var _panel: PanelContainer = null
var _spins: Dictionary = {}
var _seed_spin: SpinBox = null
var _surface_picker: ColorPickerButton = null
var _atmosphere_picker: ColorPickerButton = null
var _clouds_check: CheckBox = null
var _cloud_type: OptionButton = null
var _status: Label = null


func _ready() -> void:
	layer = 20
	# The tree is paused while the panel is open, so the ship does not fall out
	# of the sky while its world is being edited.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_panel.hide()


## Points the tool at the planet it edits. Safe to call again after a respawn.
func bind(planet: Planet) -> void:
	_planet = planet
	_refresh()


## Nothing may leave the tree paused with no panel on screen to explain it.
## Cheap insurance against exactly the failure this tool is best placed to
## cause, and against anything else that pauses and forgets.
func _process(_delta: float) -> void:
	if not is_open() and get_tree().paused:
		get_tree().paused = false


## Escape has to be caught here rather than in _unhandled_key_input: the panel
## is full of Controls, and the GUI eats ui_cancel long before an event is
## considered unhandled.
func _input(event: InputEvent) -> void:
	if is_open() and event.is_action_pressed(&"ui_cancel"):
		toggle()
		get_viewport().set_input_as_handled()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed(TOGGLE_ACTION):
		toggle()
		get_viewport().set_input_as_handled()


func is_open() -> bool:
	return _panel.visible


## Opening pauses the tree, which is the point -- the ship should not fall out
## of the sky while its world is being edited -- but it is also the one way
## this tool can wreck a session: a paused tree stops delivering input to the
## world, so F5 and F7 go dead until the panel is closed again. Hence the very
## visible heading, the second way out on Escape, and _process below.
func toggle() -> void:
	_panel.visible = not _panel.visible
	get_tree().paused = _panel.visible
	if _panel.visible:
		_refresh()


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_panel.position = Vector2(8, 8)
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	add_child(_panel)

	var rows: VBoxContainer = VBoxContainer.new()
	rows.add_theme_constant_override("separation", 2)
	_panel.add_child(rows)

	rows.add_child(_heading("KONFIGURATOR PLANETY - GRA W PAUZIE"))
	rows.add_child(_heading("F6 lub Esc zamyka"))

	_seed_spin = SpinBox.new()
	_seed_spin.min_value = 0
	_seed_spin.max_value = 1000000000
	_seed_spin.step = 1
	rows.add_child(_labelled("seed", _seed_spin))

	for field: Dictionary in FIELDS:
		var spin: SpinBox = SpinBox.new()
		spin.min_value = float(field["min"])
		spin.max_value = float(field["max"])
		spin.step = float(field["step"])
		_spins[field["name"]] = spin
		rows.add_child(_labelled(String(field["label"]), spin))

	_clouds_check = CheckBox.new()
	_clouds_check.text = "chmury"
	rows.add_child(_clouds_check)

	_cloud_type = OptionButton.new()
	for type_name: String in Planet.CloudType.keys():
		_cloud_type.add_item(type_name)
	rows.add_child(_labelled("typ nieba", _cloud_type))

	_surface_picker = ColorPickerButton.new()
	_surface_picker.custom_minimum_size = Vector2(60, 16)
	rows.add_child(_labelled("kolor gruntu", _surface_picker))

	_atmosphere_picker = ColorPickerButton.new()
	_atmosphere_picker.custom_minimum_size = Vector2(60, 16)
	rows.add_child(_labelled("kolor nieba", _atmosphere_picker))

	rows.add_child(_button("Nowy seed (losuj wszystko)", _on_reroll))
	rows.add_child(_button("Przebuduj i wyląduj", _on_rebuild))
	rows.add_child(_button("Następne lądowisko", _on_next_site))
	rows.add_child(_button("Zamknij", toggle))

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 9)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(_status)


func _heading(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 10)
	return label


func _labelled(text: String, control: Control) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	var label: Label = Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(96, 0)
	label.add_theme_font_size_override("font_size", 9)
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


func _button(text: String, handler: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 9)
	button.pressed.connect(handler)
	return button


## Pulls the planet's current values into the controls.
func _refresh() -> void:
	if _planet == null:
		return
	_seed_spin.value = float(_planet.planet_seed)
	for field: Dictionary in FIELDS:
		var name: String = String(field["name"])
		(_spins[name] as SpinBox).value = float(_planet.get(name))
	_clouds_check.button_pressed = _planet.has_clouds
	_cloud_type.selected = int(_planet.cloud_type)
	_surface_picker.color = _planet.surface_color
	_atmosphere_picker.color = _planet.atmosphere_color
	_report()


## Pushes the controls back onto the planet.
func _apply() -> void:
	if _planet == null:
		return
	for field: Dictionary in FIELDS:
		var name: String = String(field["name"])
		var value: float = (_spins[name] as SpinBox).value
		# A SpinBox hands out floats, and assigning one to a statically typed
		# int field through set() is an error rather than a rounding.
		if field.get("int", false):
			_planet.set(name, int(round(value)))
		else:
			_planet.set(name, value)
	_planet.has_clouds = _clouds_check.button_pressed
	_planet.cloud_type = _cloud_type.selected as Planet.CloudType
	_planet.surface_color = _surface_picker.color
	_planet.atmosphere_color = _atmosphere_picker.color


func _on_reroll() -> void:
	if _planet == null:
		return
	# A fresh seed rolls everything, including the dozen cloud parameters this
	# panel does not show. Editing by hand is for asking "what if"; rerolling
	# is for finding a world worth asking about.
	_planet.roll_parameters(randi())
	_refresh()
	_on_rebuild()


func _on_rebuild() -> void:
	if _planet == null:
		return
	_apply()
	_planet.rebuild()
	_refresh()
	rebuilt.emit()


func _on_next_site() -> void:
	teleport_requested.emit()
	_report()


func _report() -> void:
	if _planet == null or _status == null:
		return
	_status.text = "lądowisk: %d   szczyt %.0f   strop powietrza %.0f" % [
		_planet.landing_sites().size(),
		_planet.terrain_ceiling(),
		_planet.atmosphere_radius(),
	]
