@tool
class_name PresetEditor
extends VBoxContainer
## Edytor presetow: caly statek w jednym pliku, z podgladem.
##
## The sibling of the hull dock, and the same shape: a list on the left,
## a picture in the middle, a form and a save button on the right. What
## differs is that a preset has no geometry of its own -- it says what
## goes where **by kind**, and the hull answers where -- so the picture
## is a preview rather than a canvas and nothing on it can be dragged.
##
## The preview is the reason this is not just the inspector. A preset is
## four lines saying "a torque jet in every torque place"; what that
## produces on a given hull is nine engines in particular spots with a
## centre of mass somewhere, and no column of dropdowns will tell you
## that.

const DIRECTORY: String = "res://resources/presets"
const HULL_LOOKS: String = "res://resources/fx/looks/hull.tres"

## Where the things a preset can name live. Scanned rather than listed,
## so a new engine shows up in the dropdown by existing.
const ENGINE_DIR: String = "res://resources/engines"
const WEAPON_DIR: String = "res://resources/weapons"
const MODULE_DIRS: Array[String] = [
	"res://resources/generators", "res://resources/scanners",
	"res://resources/drives", "res://resources/tanks",
]

## The kinds of place an engine can fill, in the order a preset reads
## best: push, turn, slide, stop.
const ENGINE_KINDS: Array[StringName] = [
	HullData.SLOT_DRIVE, HullData.SLOT_TORQUE,
	HullData.SLOT_STRAFE, HullData.SLOT_RETRO,
]

var _files: ItemList = null
var _canvas: PresetCanvas = null
var _status: Label = null
var _title: Label = null
var _save: Button = null

var _name_field: LineEdit = null
var _blurb_field: LineEdit = null
var _hull_pick: OptionButton = null
var _skin_pick: OptionButton = null
var _scale_field: SpinBox = null
var _mount_rows: VBoxContainer = null
var _gun_rows: VBoxContainer = null
var _bay_rows: VBoxContainer = null
var _balance: Dictionary = {}
var _verdict: Label = null

var _paths: Array[String] = []
var _hulls: Array[HullData] = []
var _engines: Array[Resource] = []
var _weapons: Array[Resource] = []
var _modules: Array[Resource] = []
var _skins: Array[StringName] = []

var _on_disk: ShipPreset = null
var _editing: ShipPreset = null
var _path: String = ""
## Guard against the form writing back while it is being filled in.
var _filling: bool = false


func _ready() -> void:
	custom_minimum_size = Vector2(0.0, 360.0)
	_hulls = HullData.catalogue()
	_engines = _load_from([ENGINE_DIR])
	_weapons = _load_from([WEAPON_DIR])
	_modules = _load_from(MODULE_DIRS)
	_skins = _skin_keys()
	_build()
	_fill_files()


## Every resource in these directories, in a stable order.
func _load_from(directories: Array[String]) -> Array[Resource]:
	var out: Array[Resource] = []
	for directory: String in directories:
		var names: Array = Array(ResourceLoader.list_directory(directory))
		names.sort()
		for file_name: String in names:
			if not file_name.ends_with(".tres"):
				continue
			var one: Resource = load("%s/%s" % [directory, file_name])
			if one != null:
				out.append(one)
	return out


## The hull pictures there are, which is what a skin key may name.
func _skin_keys() -> Array[StringName]:
	var out: Array[StringName] = []
	var looks: LookTable = load(HULL_LOOKS) as LookTable
	if looks == null:
		return out
	for key: Variant in looks.by_key:
		out.append(key)
	out.sort()
	return out


func _build() -> void:
	var columns: HBoxContainer = HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(columns)

	var left: VBoxContainer = VBoxContainer.new()
	left.custom_minimum_size = Vector2(150.0, 0.0)
	var caption: Label = Label.new()
	caption.text = "Presety"
	left.add_child(caption)
	_files = ItemList.new()
	_files.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_files.item_selected.connect(_open)
	left.add_child(_files)
	columns.add_child(left)

	var middle: VBoxContainer = VBoxContainer.new()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title = Label.new()
	_title.text = "wybierz preset"
	middle.add_child(_title)
	_canvas = PresetCanvas.new()
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.hovered.connect(func(note: String) -> void: _status.text = note)
	middle.add_child(_canvas)
	columns.add_child(middle)

	columns.add_child(_build_form())

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.text = "najedz na gniazdo, zeby zobaczyc co w nim siedzi"
	add_child(_status)


func _build_form() -> Control:
	var scroller: ScrollContainer = ScrollContainer.new()
	scroller.custom_minimum_size = Vector2(300.0, 0.0)
	scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var column: VBoxContainer = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_name_field = LineEdit.new()
	_name_field.text_changed.connect(func(text: String) -> void: _set_field(&"display_name", text))
	column.add_child(_titled("nazwa", _name_field))

	_blurb_field = LineEdit.new()
	_blurb_field.text_changed.connect(func(text: String) -> void: _set_field(&"blurb", text))
	column.add_child(_titled("opis", _blurb_field))

	_hull_pick = OptionButton.new()
	for hull: HullData in _hulls:
		_hull_pick.add_item(String(hull.id))
	_hull_pick.item_selected.connect(_on_hull_picked)
	column.add_child(_titled("kadlub", _hull_pick))

	# The skin, which is a key into the hull look table rather than a
	# texture: no gameplay resource in this project carries a picture.
	_skin_pick = OptionButton.new()
	_skin_pick.add_item("(jak kadlub)")
	for key: StringName in _skins:
		_skin_pick.add_item(String(key))
	_skin_pick.item_selected.connect(_on_skin_picked)
	column.add_child(_titled("grafika", _skin_pick))

	_scale_field = SpinBox.new()
	_scale_field.min_value = 0.1
	_scale_field.max_value = 4.0
	_scale_field.step = 0.05
	_scale_field.value_changed.connect(func(value: float) -> void: _set_field(&"engine_scale", value))
	column.add_child(_titled("silniki x", _scale_field))

	column.add_child(HSeparator.new())
	column.add_child(_heading("Silniki"))
	_mount_rows = VBoxContainer.new()
	column.add_child(_mount_rows)
	column.add_child(_adder("+ silnik", _add_mount))

	column.add_child(_heading("Dziala"))
	_gun_rows = VBoxContainer.new()
	column.add_child(_gun_rows)
	column.add_child(_adder("+ dzialo", _add_gun))

	column.add_child(_heading("Zatoki"))
	_bay_rows = VBoxContainer.new()
	column.add_child(_bay_rows)
	column.add_child(_adder("+ zatoka", _add_bay))

	column.add_child(HSeparator.new())
	column.add_child(_heading("Bilans"))
	for row: Array in [
		["mass", "masa"], ["centre", "srodek masy y"],
		["torque_gap", "krzyz momentu"], ["strafe_gap", "strafe od srodka"],
	]:
		column.add_child(_build_balance_row(row[0], row[1]))
	_verdict = Label.new()
	_verdict.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_verdict)

	column.add_child(HSeparator.new())
	var fit: Button = Button.new()
	fit.text = "Dopasuj widok"
	fit.pressed.connect(func() -> void: _canvas.fit())
	column.add_child(fit)

	var revert: Button = Button.new()
	revert.text = "Przywroc z dysku"
	revert.pressed.connect(_revert)
	column.add_child(revert)

	_save = Button.new()
	_save.text = "Zapisz .tres"
	_save.disabled = true
	_save.pressed.connect(_write_file)
	column.add_child(_save)

	scroller.add_child(column)
	return scroller


func _heading(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	return label


func _titled(caption: String, control: Control) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	var label: Label = Label.new()
	label.text = caption
	label.custom_minimum_size = Vector2(90.0, 0.0)
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


func _adder(caption: String, action: Callable) -> Button:
	var button: Button = Button.new()
	button.text = caption
	button.pressed.connect(action)
	return button


func _build_balance_row(key: String, caption: String) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	var label: Label = Label.new()
	label.text = caption
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var figure: Label = Label.new()
	figure.text = "-"
	row.add_child(figure)
	_balance[key] = figure
	return row


func _fill_files() -> void:
	_files.clear()
	_paths.clear()
	var names: Array = Array(ResourceLoader.list_directory(DIRECTORY))
	names.sort()
	for file_name: String in names:
		if file_name.ends_with(".tres"):
			_paths.append("%s/%s" % [DIRECTORY, file_name])
			_files.add_item(file_name.get_basename())


func _open(index: int) -> void:
	if index < 0 or index >= _paths.size():
		return
	_path = _paths[index]
	_on_disk = load(_path) as ShipPreset
	if _on_disk == null:
		_status.text = "%s to nie jest ShipPreset" % _path
		return
	_editing = _copy_of(_on_disk)
	_canvas.show_preset(_editing)
	_fill_form()
	_refresh()


## A preset to edit without touching the one the editor has loaded.
##
## The arrays and the `MountFit`s and `BayFit`s in them are copied,
## because those are what the form writes to. What is **not** copied is
## the hull, the engines, the weapons and the modules: those are
## catalogue entries, and a preset naming one should name the same
## object the rest of the game does.
func _copy_of(preset: ShipPreset) -> ShipPreset:
	var out: ShipPreset = preset.duplicate() as ShipPreset
	var mounts: Array[MountFit] = []
	for fit: MountFit in preset.mounts:
		mounts.append(fit.duplicate() as MountFit if fit != null else null)
	out.mounts = mounts
	var guns: Array[WeaponData] = []
	guns.assign(preset.guns)
	out.guns = guns
	var bays: Array[BayFit] = []
	for bay: BayFit in preset.bays:
		bays.append(bay.duplicate() as BayFit if bay != null else null)
	out.bays = bays
	return out


func _fill_form() -> void:
	if _editing == null:
		return
	_filling = true
	_name_field.text = _editing.display_name
	_blurb_field.text = _editing.blurb
	_scale_field.value = _editing.engine_scale
	for i: int in range(_hulls.size()):
		if _hulls[i] == _editing.hull:
			_hull_pick.selected = i
	_skin_pick.selected = 0
	for i: int in range(_skins.size()):
		if _skins[i] == _editing.look_key:
			_skin_pick.selected = i + 1
	_rebuild_rows()
	_filling = false


## The three variable-length lists, rebuilt wholesale.
##
## Wholesale because a row carries its own index into the array and a
## removal shifts every later one: rebuilding is shorter than keeping
## the indices honest, and these lists are four rows long.
func _rebuild_rows() -> void:
	for parent: VBoxContainer in [_mount_rows, _gun_rows, _bay_rows]:
		for child: Node in parent.get_children():
			parent.remove_child(child)
			child.queue_free()
	if _editing == null:
		return

	for i: int in range(_editing.mounts.size()):
		_mount_rows.add_child(_mount_row(i))
	for i: int in range(_editing.guns.size()):
		_gun_rows.add_child(_gun_row(i))
	for i: int in range(_editing.bays.size()):
		_bay_rows.add_child(_bay_row(i))


func _mount_row(index: int) -> Control:
	var fit: MountFit = _editing.mounts[index]
	var row: HBoxContainer = HBoxContainer.new()

	var kind: OptionButton = OptionButton.new()
	for i: int in range(ENGINE_KINDS.size()):
		kind.add_item(String(ENGINE_KINDS[i]))
		if ENGINE_KINDS[i] == fit.kind:
			kind.selected = i
	# A mount pinned to a named place is the odd one out, and saying so
	# beats showing a kind dropdown that does nothing.
	if not String(fit.place).is_empty():
		kind.disabled = true
		kind.add_item(String(fit.place))
		kind.selected = kind.item_count - 1
	kind.item_selected.connect(
		func(picked: int) -> void: _set_mount(index, &"kind", ENGINE_KINDS[picked])
	)
	row.add_child(kind)

	var engine: OptionButton = OptionButton.new()
	engine.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i: int in range(_engines.size()):
		engine.add_item(_display_of(_engines[i]))
		if _engines[i] == fit.engine:
			engine.selected = i
	engine.item_selected.connect(
		func(picked: int) -> void: _set_mount(index, &"engine", _engines[picked])
	)
	row.add_child(engine)

	var scale: SpinBox = SpinBox.new()
	scale.min_value = 0.1
	scale.max_value = 4.0
	scale.step = 0.05
	scale.value = fit.scale
	scale.value_changed.connect(
		func(value: float) -> void: _set_mount(index, &"scale", value)
	)
	row.add_child(scale)

	row.add_child(_remover(func() -> void: _drop(&"mounts", index)))
	return row


func _gun_row(index: int) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	var pick: OptionButton = OptionButton.new()
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i: int in range(_weapons.size()):
		pick.add_item(_display_of(_weapons[i]))
		if _weapons[i] == _editing.guns[index]:
			pick.selected = i
	pick.item_selected.connect(func(picked: int) -> void: _set_gun(index, _weapons[picked]))
	row.add_child(pick)
	row.add_child(_remover(func() -> void: _drop(&"guns", index)))
	return row


func _bay_row(index: int) -> Control:
	var bay: BayFit = _editing.bays[index]
	var row: HBoxContainer = HBoxContainer.new()

	var size_field: SpinBox = SpinBox.new()
	size_field.min_value = 0.1
	size_field.max_value = 12.0
	size_field.step = 0.1
	size_field.value = bay.size
	size_field.value_changed.connect(
		func(value: float) -> void: _set_bay(index, &"size", value)
	)
	row.add_child(size_field)

	var pick: OptionButton = OptionButton.new()
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick.add_item("(pusta)")
	for i: int in range(_modules.size()):
		pick.add_item(_display_of(_modules[i]))
		if _modules[i] == bay.installed:
			pick.selected = i + 1
	pick.item_selected.connect(
		func(picked: int) -> void: _set_bay(
			index, &"installed", null if picked == 0 else _modules[picked - 1]
		)
	)
	row.add_child(pick)

	row.add_child(_remover(func() -> void: _drop(&"bays", index)))
	return row


func _remover(action: Callable) -> Button:
	var button: Button = Button.new()
	button.text = "x"
	button.pressed.connect(action)
	return button


func _display_of(what: Resource) -> String:
	var named: Variant = what.get("display_name")
	if named is String and not (named as String).is_empty():
		return named
	return what.resource_path.get_file().get_basename()


# --- edits -----------------------------------------------------------

func _set_field(field: StringName, value: Variant) -> void:
	if _filling or _editing == null:
		return
	_editing.set(field, value)
	_changed()


func _on_hull_picked(index: int) -> void:
	if _filling or _editing == null or index < 0 or index >= _hulls.size():
		return
	_editing.hull = _hulls[index]
	# A new hull reframes: the point of changing it is to see what the
	# same four lines build on a different shape.
	_canvas.show_preset(_editing)
	_refresh()


func _on_skin_picked(index: int) -> void:
	if _filling or _editing == null:
		return
	_editing.look_key = &"" if index == 0 else _skins[index - 1]
	_changed()


func _set_mount(index: int, field: StringName, value: Variant) -> void:
	if _filling or _editing == null or index >= _editing.mounts.size():
		return
	_editing.mounts[index].set(field, value)
	_changed()


func _set_gun(index: int, weapon: WeaponData) -> void:
	if _filling or _editing == null or index >= _editing.guns.size():
		return
	_editing.guns[index] = weapon
	_changed()


func _set_bay(index: int, field: StringName, value: Variant) -> void:
	if _filling or _editing == null or index >= _editing.bays.size():
		return
	_editing.bays[index].set(field, value)
	_changed()


func _add_mount() -> void:
	if _editing == null:
		return
	var fit: MountFit = MountFit.new()
	fit.kind = ENGINE_KINDS[0]
	if not _engines.is_empty():
		fit.engine = _engines[0] as EngineData
	_editing.mounts.append(fit)
	_rebuild_rows()
	_changed()


func _add_gun() -> void:
	if _editing == null or _weapons.is_empty():
		return
	_editing.guns.append(_weapons[0] as WeaponData)
	_rebuild_rows()
	_changed()


func _add_bay() -> void:
	if _editing == null:
		return
	var bay: BayFit = BayFit.new()
	bay.size = 1.5
	_editing.bays.append(bay)
	_rebuild_rows()
	_changed()


func _drop(field: StringName, index: int) -> void:
	if _editing == null:
		return
	var list: Array = _editing.get(field)
	if index < 0 or index >= list.size():
		return
	list.remove_at(index)
	_rebuild_rows()
	_changed()


func _changed() -> void:
	_canvas.refresh()
	_refresh()


func _revert() -> void:
	if _on_disk == null:
		return
	_editing = _copy_of(_on_disk)
	_canvas.show_preset(_editing)
	_fill_form()
	_refresh()


# --- reporting -------------------------------------------------------

func _refresh() -> void:
	if _editing == null:
		return
	_report_balance()
	var fault: String = ShipFitout.fault_in(_editing)
	var dirty: bool = not _same_as_disk()
	# A preset that cannot be flown must not be saved over a working one:
	# `apply` refuses it, and the ship that would be refitted is the one
	# somebody is flying.
	_save.disabled = not dirty or not fault.is_empty()
	_title.text = "%s%s%s" % [
		_path.get_file(), "  *" if dirty else "",
		"" if fault.is_empty() else "    nie da sie zbudowac: " + fault,
	]


func _report_balance() -> void:
	var found: Dictionary = _canvas.balance
	if found.is_empty():
		return
	(_balance["mass"] as Label).text = "%.2f kg" % float(found["mass"])
	(_balance["centre"] as Label).text = "%.2f" % (found["centre"] as Vector2).y
	var wrong: Array[String] = []
	for key: String in ["torque_gap", "strafe_gap"]:
		var value: float = found[key]
		var allowed: float = (
			HullCanvas.TORQUE_TOLERANCE if key == "torque_gap"
			else HullCanvas.STRAFE_TOLERANCE
		)
		var figure: Label = _balance[key]
		figure.text = "%.2f px" % value
		var over: bool = value > allowed
		figure.modulate = Color(1.0, 0.45, 0.35) if over else Color(0.45, 0.95, 0.60)
		if over:
			wrong.append(key)
	if wrong.is_empty():
		_verdict.text = "wywazony"
		_verdict.modulate = Color(0.45, 0.95, 0.60)
		return
	var says: Array[String] = []
	if wrong.has("torque_gap"):
		says.append("obrot pchnie statek na bok")
	if wrong.has("strafe_gap"):
		says.append("strafe bedzie obracal")
	_verdict.text = " - ".join(says)
	_verdict.modulate = Color(1.0, 0.45, 0.35)


## Whether the copy still says what the file says. Compared field by
## field rather than by `==`, because two resources are never equal.
func _same_as_disk() -> bool:
	if _editing == null or _on_disk == null:
		return true
	for field: StringName in [
		&"display_name", &"blurb", &"hull", &"look_key", &"engine_scale", &"order",
	]:
		if _editing.get(field) != _on_disk.get(field):
			return false
	if _editing.guns != _on_disk.guns:
		return false
	if _editing.mounts.size() != _on_disk.mounts.size():
		return false
	for i: int in range(_editing.mounts.size()):
		for field: StringName in [&"kind", &"place", &"engine", &"scale", &"socket", &"centered"]:
			if _editing.mounts[i].get(field) != _on_disk.mounts[i].get(field):
				return false
	if _editing.bays.size() != _on_disk.bays.size():
		return false
	for i: int in range(_editing.bays.size()):
		for field: StringName in [&"size", &"installed", &"at"]:
			if _editing.bays[i].get(field) != _on_disk.bays[i].get(field):
				return false
	return true


## Copy the edited values onto the resource the editor has loaded and
## write it out.
##
## Onto the loaded instance rather than a fresh one, so the catalogue and
## any open inspector see the change instead of a third version of the
## same preset existing in one process.
func _write_file() -> void:
	if _editing == null or _on_disk == null:
		return
	for field: StringName in [
		&"display_name", &"blurb", &"hull", &"look_key", &"engine_scale",
		&"order", &"mounts", &"guns", &"bays",
	]:
		_on_disk.set(field, _editing.get(field))
	var failed: Error = ResourceSaver.save(_on_disk, _path)
	if failed != OK:
		_status.text = "nie udalo sie zapisac %s (blad %d)" % [_path, failed]
		return
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().update_file(_path)
	# The catalogue is cached, and the menu and the refit list read it.
	ShipFitout._catalogue.clear()
	_editing = _copy_of(_on_disk)
	_canvas.show_preset(_editing)
	_status.text = "zapisano %s" % _path
	_refresh()
