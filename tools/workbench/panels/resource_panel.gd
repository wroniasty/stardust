class_name BenchResourcePanel
extends VBoxContainer
## Pick a resource, edit its fields, feel it on the ship.
##
## Edits go straight into the object the game loaded, so they take effect on
## the running ship without a restart, and nothing touches the file until
## "zapisz" is pressed. "Cofnij" puts the file's values back into the live
## object (rather than reloading it, which would leave the ship holding the
## old copy).

## Category caption -> directory. The same directories the game lists.
const CATEGORIES: Dictionary = {
	"kadłuby": "res://resources/hulls",
	"silniki": "res://resources/engines",
	"bronie": "res://resources/weapons",
	"generatory": "res://resources/generators",
	"napędy skokowe": "res://resources/drives",
	"zbiorniki": "res://resources/tanks",
	"skanery": "res://resources/scanners",
}

var _bench: Workbench = null
var _ship: Ship = null

var _category: OptionButton = null
var _file: OptionButton = null
var _form: BenchResourceForm = null
var _status: Label = null
var _apply_hull: Button = null

var _paths: Array[String] = []
var _current: Resource = null

## Paths edited since they were last saved or reverted.
var _dirty: Dictionary = {}


func bind(bench: Workbench, ship: Ship) -> void:
	_bench = bench
	_ship = ship
	_build()
	_fill_files()


func _build() -> void:
	add_child(BenchForm.heading("zasób"))
	_category = OptionButton.new()
	for caption: String in CATEGORIES:
		_category.add_item(caption)
	_category.item_selected.connect(func(_i: int) -> void: _fill_files())
	add_child(_category)
	_file = OptionButton.new()
	_file.item_selected.connect(func(_i: int) -> void: _open_selected())
	add_child(_file)

	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.add_child(BenchForm.button("zapisz", save_current))
	buttons.add_child(BenchForm.button("cofnij", revert_current))
	add_child(buttons)
	_apply_hull = BenchForm.button("załóż ten kadłub", _on_apply_hull)
	add_child(_apply_hull)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)

	add_child(BenchForm.heading("pola"))
	_form = BenchResourceForm.new()
	_form.edited.connect(_on_edited)
	add_child(_form)


## The files of the chosen category, with an asterisk on the ones edited.
func _fill_files() -> void:
	var directory: String = CATEGORIES[_category.get_item_text(_category.selected)]
	_paths.clear()
	_file.clear()
	var names: Array = Array(ResourceLoader.list_directory(directory))
	names.sort()
	for file_name: String in names:
		if file_name.ends_with(".tres"):
			_paths.append("%s/%s" % [directory, file_name])
			_file.add_item(_caption(_paths[-1]))
	if not _paths.is_empty():
		_file.selected = 0
		_open_selected()
	else:
		_form.show_resource(null)


func _caption(path: String) -> String:
	return "%s%s" % ["* " if _dirty.has(path) else "", path.get_file().get_basename()]


func _open_selected() -> void:
	if _file.selected < 0 or _file.selected >= _paths.size():
		return
	_current = load(_paths[_file.selected])
	_form.show_resource(_current)
	_apply_hull.visible = _current is HullData
	_status.text = _paths[_file.selected]


func _on_edited(resource: Resource) -> void:
	_dirty[_paths[_file.selected]] = true
	_file.set_item_text(_file.selected, _caption(_paths[_file.selected]))
	_status.text = "zmieniony, nie zapisany: %s" % _paths[_file.selected]
	_bench.refresh_for(resource)


func _on_apply_hull() -> void:
	var hull: HullData = _current as HullData
	if hull != null:
		_bench.apply_hull(hull, 1.0)


## Writes the live object over its file. Only on request, and only the
## object being shown: the files are the project's data.
func save_current() -> void:
	if _current == null or _current.resource_path.is_empty():
		return
	var result: Error = ResourceSaver.save(_current, _current.resource_path)
	if result != OK:
		_status.text = "nie zapisano (%s)" % error_string(result)
		return
	_dirty.erase(_current.resource_path)
	_file.set_item_text(_file.selected, _caption(_current.resource_path))
	_status.text = "zapisano %s" % _current.resource_path


## Copies the file's values back into the live object.
##
## A fresh copy read without the cache, so the original on disk is what is
## compared against; copied field by field into the object the ship holds,
## because replacing it in the cache would leave the ship on the old one.
func revert_current() -> void:
	if _current == null or _current.resource_path.is_empty():
		return
	var fresh: Resource = ResourceLoader.load(
		_current.resource_path, "", ResourceLoader.CACHE_MODE_IGNORE
	)
	if fresh == null:
		return
	for property: Dictionary in _current.get_property_list():
		var usage: int = property["usage"]
		if (usage & PROPERTY_USAGE_STORAGE) != 0 and (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
			_current.set(property["name"], fresh.get(property["name"]))
	_current.emit_changed()
	_dirty.erase(_current.resource_path)
	_file.set_item_text(_file.selected, _caption(_current.resource_path))
	_form.show_resource(_current)
	_ship.rebuild_control_groups(false)
	_status.text = "cofnięto do pliku: %s" % _current.resource_path
