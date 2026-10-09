class_name MainMenu
extends Control
## The first screen: which ship to fly and which galaxy to fly it in.
##
## Built in code from two decisions -- a ShipFitout preset and a galaxy seed --
## and nothing else, so adding a preset or a hull adds a row here without
## anyone touching this file. Start hands both to `GameSettings` and opens the
## world, which reads them in its `_ready`.

const WORLD_SCENE: String = "res://scenes/world.tscn"

## Digits only, and short enough to read back. Longer than a nine digit seed
## buys nothing a player will ever type.
const SEED_MAX_LENGTH: int = 12

var _ships: ItemList = null
var _blurb: Label = null
var _seed_field: LineEdit = null


func _ready() -> void:
	# A resumed game has already said where it is; the menu would only ask
	# again and then be ignored.
	if OS.get_cmdline_user_args().has("resume"):
		start.call_deferred()
		return
	_build()


func _build() -> void:
	var ui_theme: Theme = Theme.new()
	ui_theme.default_font = UiFont.face()
	ui_theme.default_font_size = UiFont.BODY
	theme = ui_theme
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var backdrop: ColorRect = ColorRect.new()
	backdrop.color = Color(0.03, 0.04, 0.07)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var column: VBoxContainer = VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_CENTER)
	column.custom_minimum_size = Vector2(360.0, 0.0)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	column.add_theme_constant_override("separation", 6)
	add_child(column)

	var title: Label = Label.new()
	title.text = "STARDUST"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", UiFont.HEADLINE)
	column.add_child(title)

	column.add_child(_heading("SHIP"))
	_ships = ItemList.new()
	_ships.auto_height = true
	_ships.select_mode = ItemList.SELECT_SINGLE
	var presets: Array[ShipPreset] = ShipFitout.all()
	var picked: int = 0
	for i: int in range(presets.size()):
		_ships.add_item(presets[i].display_name)
		if presets[i].display_name == GameSettings.fitout_name:
			picked = i
	_ships.select(picked)
	_ships.item_selected.connect(_on_ship_selected)
	_ships.item_activated.connect(func(_index: int) -> void: start())
	column.add_child(_ships)

	_blurb = Label.new()
	_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_blurb.modulate = Color(0.7, 0.75, 0.82)
	column.add_child(_blurb)
	_on_ship_selected(picked)

	column.add_child(_heading("GALAXY SEED"))
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	column.add_child(row)

	_seed_field = LineEdit.new()
	_seed_field.text = str(GameSettings.galaxy_seed)
	_seed_field.max_length = SEED_MAX_LENGTH
	_seed_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed_field.text_changed.connect(_on_seed_edited)
	_seed_field.text_submitted.connect(func(_text: String) -> void: start())
	row.add_child(_seed_field)

	var randomize_button: Button = Button.new()
	randomize_button.text = "Randomize"
	randomize_button.pressed.connect(_on_randomize)
	row.add_child(randomize_button)

	var go: Button = Button.new()
	go.text = "START"
	go.pressed.connect(start)
	column.add_child(go)
	_ships.grab_focus()


func _heading(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.modulate = Color(0.95, 0.8, 0.35)
	return label


func _on_ship_selected(index: int) -> void:
	var presets: Array[ShipPreset] = ShipFitout.all()
	if index < 0 or index >= presets.size():
		return
	# `caption`, not `blurb`: the scaled preset's sentence is computed
	# from the figure its engines are actually built with.
	_blurb.text = presets[index].caption()


## Keeps the field a number. Filtering on the way in rather than refusing at
## Start, because a seed field that accepts letters and then complains is a
## field that was never going to work.
func _on_seed_edited(text: String) -> void:
	var digits: String = ""
	for character: String in text:
		if character >= "0" and character <= "9":
			digits += character
	if digits != text:
		var caret: int = _seed_field.caret_column
		_seed_field.text = digits
		_seed_field.caret_column = mini(caret, digits.length())


func _on_randomize() -> void:
	_seed_field.text = str(GameSettings.random_seed())


## The seed as typed, or the standing one if the field was emptied.
func chosen_seed() -> int:
	if _seed_field == null or _seed_field.text.is_empty():
		return GameSettings.galaxy_seed
	return _seed_field.text.to_int()


## The preset picked in the list.
func chosen_fitout() -> String:
	if _ships == null:
		return GameSettings.fitout_name
	var picked: PackedInt32Array = _ships.get_selected_items()
	if picked.is_empty():
		return GameSettings.fitout_name
	return _ships.get_item_text(picked[0])


## Hands the choices to the world and opens it.
func start() -> void:
	if not OS.get_cmdline_user_args().has("resume"):
		GameSettings.galaxy_seed = chosen_seed()
		GameSettings.fitout_name = chosen_fitout()
		GameSettings.chosen = true
	get_tree().change_scene_to_file(WORLD_SCENE)
