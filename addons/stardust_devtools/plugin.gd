@tool
extends EditorPlugin
## Stardust devtools: a dock beside the inspector. DEVTOOLS.md, D6.
##
## Three jobs. List the game's resources by kind and open one in the
## editor's own inspector (undo, redo and saving come for free). Run the
## workbench scene. And, while a bench is running, forward every property
## edited in the inspector to it, so the change is heard and seen on the
## ship at once instead of after a save and a restart.

const WORKBENCH_SCENE: String = "res://tools/workbench/workbench.tscn"

## Kind -> directory, the same ones the bench's resource tab lists.
const CATEGORIES: Dictionary = {
	"hulls": "res://resources/hulls",
	"engines": "res://resources/engines",
	"weapons": "res://resources/weapons",
	"generators": "res://resources/generators",
	"jump drives": "res://resources/drives",
	"tanks": "res://resources/tanks",
	"scanners": "res://resources/scanners",
	"sound tables": "res://resources/fx/sounds",
	"look tables": "res://resources/fx/looks",
}

## Only resources under here are forwarded: an edit to a scene or the
## project's own settings is not the bench's business.
const WATCHED_ROOT: String = "res://resources/"

var _dock: VBoxContainer = null
var _debugger: StardustBenchDebugger = null
var _category: OptionButton = null
var _files: ItemList = null
var _link: Label = null
var _paths: Array[String] = []


func _enter_tree() -> void:
	_debugger = StardustBenchDebugger.new()
	_debugger.link_changed.connect(_on_link_changed)
	add_debugger_plugin(_debugger)

	_build_dock()
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)
	EditorInterface.get_inspector().property_edited.connect(_on_property_edited)
	_fill_files()


func _exit_tree() -> void:
	var inspector: EditorInspector = EditorInterface.get_inspector()
	if inspector.property_edited.is_connected(_on_property_edited):
		inspector.property_edited.disconnect(_on_property_edited)
	remove_debugger_plugin(_debugger)
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null


func _build_dock() -> void:
	_dock = VBoxContainer.new()
	_dock.name = "Stardust"

	var run: Button = Button.new()
	run.text = "Uruchom Workbench"
	run.pressed.connect(func() -> void: EditorInterface.play_custom_scene(WORKBENCH_SCENE))
	_dock.add_child(run)

	var stop: Button = Button.new()
	stop.text = "Zatrzymaj"
	stop.pressed.connect(func() -> void: EditorInterface.stop_playing_scene())
	_dock.add_child(stop)

	_link = Label.new()
	_link.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_on_link_changed(false)
	_dock.add_child(_link)

	_category = OptionButton.new()
	for caption: String in CATEGORIES:
		_category.add_item(caption)
	_category.item_selected.connect(func(_i: int) -> void: _fill_files())
	_dock.add_child(_category)

	_files = ItemList.new()
	_files.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_files.custom_minimum_size = Vector2(0.0, 200.0)
	_files.item_selected.connect(_open)
	_dock.add_child(_files)


func _fill_files() -> void:
	_files.clear()
	_paths.clear()
	var directory: String = CATEGORIES[_category.get_item_text(_category.selected)]
	var names: Array = Array(ResourceLoader.list_directory(directory))
	names.sort()
	for file_name: String in names:
		if file_name.ends_with(".tres"):
			_paths.append("%s/%s" % [directory, file_name])
			_files.add_item(file_name.get_basename())


## Opens the chosen file in the inspector. Single click, because the point
## of the dock is to flick between a dozen engines.
func _open(index: int) -> void:
	var resource: Resource = load(_paths[index])
	if resource != null:
		EditorInterface.edit_resource(resource)


func _on_link_changed(connected: bool) -> void:
	_link.text = "Workbench connected: inspector edits go through live." if connected \
			else "Workbench is not running: edits stay in the editor."


## An inspector edit, forwarded when it is a plain value on a game resource.
##
## Values only. An object (a texture, a nested resource) does not survive
## the trip over the debugger channel, and the bench can pick those up from
## a save.
func _on_property_edited(property: String) -> void:
	if not _debugger.is_linked():
		return
	var edited: Object = EditorInterface.get_inspector().get_edited_object()
	var resource: Resource = edited as Resource
	if resource == null or not resource.resource_path.begins_with(WATCHED_ROOT):
		return
	var value: Variant = resource.get(property)
	if value is Object:
		return
	_debugger.send_set(resource.resource_path, property, value)
