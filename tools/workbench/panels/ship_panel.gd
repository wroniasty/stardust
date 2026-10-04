class_name BenchShipPanel
extends VBoxContainer
## Which hull, which engine in each mount, which gun on each hardpoint.
##
## Every list is a directory listing of the resources the game itself loads,
## so a new engine or weapon file shows up here without anyone editing the
## tool. The mounts and hardpoints are read off the ship, not off a preset:
## after a refit the panel describes the ship that is actually there.

const ENGINES_DIR: String = "res://resources/engines"
const WEAPONS_DIR: String = "res://resources/weapons"

const HEADING_COLOR: Color = Color(0.72, 0.68, 0.92)
const LABEL_WIDTH: float = 78.0

var _bench: Workbench = null
var _ship: Ship = null

var _presets: OptionButton = null
var _hulls: OptionButton = null
var _scale: SpinBox = null
var _engine_box: VBoxContainer = null
var _gun_box: VBoxContainer = null
var _status: Label = null

var _engines: Array[EngineData] = []
var _weapons: Array[WeaponData] = []


func bind(bench: Workbench, ship: Ship) -> void:
	_bench = bench
	_ship = ship
	for resource: Resource in _load_all(ENGINES_DIR):
		_engines.append(resource as EngineData)
	for resource: Resource in _load_all(WEAPONS_DIR):
		_weapons.append(resource as WeaponData)
	_build()
	_ship.configuration_changed.connect(_refresh_deferred)
	_refresh()


func _build() -> void:
	add_child(_heading("preset"))
	_presets = OptionButton.new()
	for preset: Dictionary in ShipFitout.all():
		_presets.add_item(String(preset["name"]))
	add_child(_presets)
	add_child(_button("załóż preset", _on_preset))

	add_child(_heading("kadłub"))
	_hulls = OptionButton.new()
	for hull: HullData in HullData.catalogue():
		_hulls.add_item("%s (%s)" % [hull.display_name, hull.id])
	add_child(_hulls)
	_scale = SpinBox.new()
	_scale.min_value = 0.3
	_scale.max_value = 4.0
	_scale.step = 0.1
	_scale.value = 1.0
	add_child(_labelled("skala", _scale))
	add_child(_button("zmień kadłub", _on_hull))

	add_child(_heading("silniki"))
	_engine_box = VBoxContainer.new()
	add_child(_engine_box)

	add_child(_heading("broń"))
	_gun_box = VBoxContainer.new()
	add_child(_gun_box)

	add_child(_heading("statek"))
	var frozen: CheckBox = CheckBox.new()
	frozen.text = "zamrożony"
	frozen.toggled.connect(func(on: bool) -> void: _ship.freeze = on)
	add_child(frozen)
	add_child(_button("wróć na środek", _bench.reset_ship))

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)


## Rebuilds the two per-part lists from the ship as it is now.
##
## Deferred when it comes from the ship's signal: picking an item in one of
## these buttons is what causes the signal, and freeing a button from inside
## its own `item_selected` is how a UI crashes.
func _refresh_deferred() -> void:
	_refresh.call_deferred()


func _refresh() -> void:
	for box: VBoxContainer in [_engine_box, _gun_box]:
		for child: Node in box.get_children():
			box.remove_child(child)
			child.queue_free()

	for mount: EngineMount in _ship.engine_mounts():
		_engine_box.add_child(_labelled(String(mount.name), _engine_picker(mount)))
	for hardpoint: Hardpoint in _ship.hardpoints:
		_gun_box.add_child(_labelled(String(hardpoint.name), _gun_picker(hardpoint)))
	if _ship.hardpoints.is_empty():
		_gun_box.add_child(_note("brak hardpointów"))

	_status.text = "%d silników, %d dział, masa %.1f" % [
		_ship.engines.size(), _ship.hardpoints.size(), _ship.mass,
	]


## A picker holding only what the mount will take, with the empty mount and
## whatever is in there now (a scaled copy has no file to match it to).
func _engine_picker(mount: EngineMount) -> OptionButton:
	var picker: OptionButton = OptionButton.new()
	picker.add_item("(pusty)")
	picker.set_item_metadata(0, null)
	var chosen: int = 0
	var found: bool = mount.installed == null
	for data: EngineData in _engines:
		if not mount.fits(data):
			continue
		picker.add_item(_name_of(data))
		picker.set_item_metadata(picker.item_count - 1, data)
		if mount.installed != null and not mount.installed.resource_path.is_empty() \
				and data.resource_path == mount.installed.resource_path:
			chosen = picker.item_count - 1
			found = true
	if not found:
		picker.add_item("* %s" % _name_of(mount.installed))
		picker.set_item_metadata(picker.item_count - 1, mount.installed)
		chosen = picker.item_count - 1
	picker.selected = chosen
	picker.item_selected.connect(_on_engine_picked.bind(mount, picker))
	return picker


func _gun_picker(hardpoint: Hardpoint) -> OptionButton:
	var picker: OptionButton = OptionButton.new()
	var chosen: int = 0
	var found: bool = false
	for data: WeaponData in _weapons:
		if not hardpoint.can_fit(data):
			continue
		picker.add_item(_name_of(data))
		picker.set_item_metadata(picker.item_count - 1, data)
		if hardpoint.weapon != null and data.resource_path == hardpoint.weapon.resource_path:
			chosen = picker.item_count - 1
			found = true
	if not found and hardpoint.weapon != null:
		picker.add_item("* %s" % _name_of(hardpoint.weapon))
		picker.set_item_metadata(picker.item_count - 1, hardpoint.weapon)
		chosen = picker.item_count - 1
	picker.selected = chosen
	picker.item_selected.connect(_on_gun_picked.bind(hardpoint, picker))
	return picker


func _on_engine_picked(index: int, mount: EngineMount, picker: OptionButton) -> void:
	var data: EngineData = picker.get_item_metadata(index) as EngineData
	if data == null:
		mount.installed = null
		_ship.rebuild_control_groups(false)
	else:
		_ship.fit_engine(mount, data)


func _on_gun_picked(index: int, hardpoint: Hardpoint, picker: OptionButton) -> void:
	var data: WeaponData = picker.get_item_metadata(index) as WeaponData
	if data == null:
		return
	hardpoint.fit(data)
	# The skin redraws off this signal, and fitting a gun is not otherwise
	# something the ship announces.
	_ship.rebuild_control_groups(false)


func _on_preset() -> void:
	ShipFitout.apply(_ship, ShipFitout.all()[_presets.selected])
	_ship.energy = _ship.energy_capacity()


func _on_hull() -> void:
	_bench.apply_hull(HullData.catalogue()[_hulls.selected], _scale.value)


## Every resource of a kind in a directory, in name order.
func _load_all(directory: String) -> Array[Resource]:
	var out: Array[Resource] = []
	var names: Array = Array(ResourceLoader.list_directory(directory))
	names.sort()
	for file_name: String in names:
		if file_name.ends_with(".tres"):
			var resource: Resource = load("%s/%s" % [directory, file_name])
			if resource != null:
				out.append(resource)
	return out


## File stem first, because it is what the files are called and what a
## designer will type into a preset.
func _name_of(module: ModuleData) -> String:
	if module == null:
		return "-"
	var stem: String = module.resource_path.get_file().get_basename()
	if stem.is_empty():
		return module.display_name
	return stem


func _heading(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_color_override("font_color", HEADING_COLOR)
	return label


func _note(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.modulate = Color(1, 1, 1, 0.55)
	return label


func _labelled(text: String, control: Control) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	var label: Label = Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(LABEL_WIDTH, 0.0)
	label.clip_text = true
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


func _button(text: String, handler: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.pressed.connect(handler)
	return button
