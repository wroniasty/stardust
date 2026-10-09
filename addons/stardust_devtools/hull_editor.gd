@tool
class_name HullEditor
extends VBoxContainer
## Graficzny edytor kadlubow: wybierz .tres, ciagnij punkty, zapisz plik.
##
## The dock could already open a hull in the inspector, which gives a
## column of numbers: `torque_slots` is four `Vector2`s in a fold-out, and
## working out that the third one is the jet hanging off the left side of
## the tail means reading `HullData.slots()` and doing the comparison in
## your head. A hull is a shape. This draws it.
##
## What it edits is a **loose copy**. Nothing on disk changes until the
## save button is pressed, which is what makes the revert button honest
## and what keeps a half-dragged outline out of a running game.
##
## Undo is a local stack of `HullHandles.snapshot` rather than the
## editor's `EditorUndoRedoManager`. The editor's manager wants an object
## and a property per step, and a drag is neither -- it is one gesture
## that can rename two jets and materialise a whole derived kind. One
## snapshot per gesture says what actually happened (DEVTOOLS.md D6 keeps
## the manager open for the inspector side, where it fits).

const DIRECTORY: String = "res://resources/hulls"

## How many gestures back you can go. A drag is one entry, not one per
## pixel; see `HullCanvas._on_motion`.
const UNDO_DEPTH: int = 64

var _files: ItemList = null
var _canvas: HullCanvas = null
var _status: Label = null
var _title: Label = null
var _save: Button = null
var _undo_button: Button = null
var _rows: Dictionary = {}
var _paths: Array[String] = []

## The resource as it is on disk (the editor's own loaded instance), and
## the copy being dragged around.
var _on_disk: HullData = null
var _editing: HullData = null
var _path: String = ""
var _undo: Array[Dictionary] = []


func _ready() -> void:
	custom_minimum_size = Vector2(0.0, 340.0)
	_build()
	_fill_files()


func _build() -> void:
	var columns: HBoxContainer = HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(columns)

	columns.add_child(_build_file_list())

	var middle: VBoxContainer = VBoxContainer.new()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title = Label.new()
	_title.text = "wybierz kadlub"
	middle.add_child(_title)
	_canvas = HullCanvas.new()
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.about_to_change.connect(_remember)
	_canvas.changed.connect(_on_changed)
	_canvas.hovered.connect(func(note: String) -> void: _status.text = note)
	middle.add_child(_canvas)
	columns.add_child(middle)

	columns.add_child(_build_side())

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.text = "LPM ciagnij  -  PPM usun  -  2x LPM na krawedzi: nowy wierzcholek"
	add_child(_status)


func _build_file_list() -> Control:
	var column: VBoxContainer = VBoxContainer.new()
	column.custom_minimum_size = Vector2(150.0, 0.0)
	var caption: Label = Label.new()
	caption.text = "Kadluby"
	column.add_child(caption)
	_files = ItemList.new()
	_files.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_files.item_selected.connect(_open)
	column.add_child(_files)
	return column


## The right-hand column, inside a scroller.
##
## Nine kinds of place plus the buttons do not fit the bottom panel at the
## height the editor opens it, and the one control that must never be the
## one clipped off the end is save.
func _build_side() -> Control:
	var scroller: ScrollContainer = ScrollContainer.new()
	scroller.custom_minimum_size = Vector2(266.0, 0.0)
	scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var column: VBoxContainer = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var caption: Label = Label.new()
	caption.text = "Miejsca"
	column.add_child(caption)

	for entry: Dictionary in HullHandles.FIELDS:
		column.add_child(_build_row(entry))

	column.add_child(HSeparator.new())

	var snap: CheckBox = CheckBox.new()
	snap.text = "siatka co %.2f" % HullCanvas.SNAP_STEP
	snap.button_pressed = true
	snap.toggled.connect(func(on: bool) -> void: _canvas.snapping = on)
	column.add_child(snap)

	var fit: Button = Button.new()
	fit.text = "Dopasuj widok"
	fit.pressed.connect(func() -> void: _canvas.fit())
	column.add_child(fit)

	_undo_button = Button.new()
	_undo_button.text = "Cofnij"
	_undo_button.disabled = true
	_undo_button.pressed.connect(_step_back)
	column.add_child(_undo_button)

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


## One line per editable array: its colour, its name, how many places it
## has against how many the game wants, and a button to add another.
func _build_row(entry: Dictionary) -> Control:
	var field: StringName = entry["field"]
	var row: HBoxContainer = HBoxContainer.new()

	var swatch: ColorRect = ColorRect.new()
	swatch.custom_minimum_size = Vector2(10.0, 10.0)
	swatch.color = HullCanvas.PAINT[field]
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(swatch)

	var caption: Label = Label.new()
	caption.text = entry["caption"]
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(caption)

	var count: Label = Label.new()
	count.text = "-"
	row.add_child(count)

	var add: Button = Button.new()
	add.text = "+"
	add.pressed.connect(func() -> void: _canvas.add_to(field))
	row.add_child(add)

	_rows[field] = count
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
	_on_disk = load(_path) as HullData
	if _on_disk == null:
		_status.text = "%s to nie jest HullData" % _path
		return
	_editing = HullHandles.copy_of(_on_disk)
	_undo.clear()
	_canvas.show_hull(_editing)
	_refresh()


## Called before every gesture, so a snapshot of the hull as it was is on
## the stack before it stops being true.
func _remember(note: String) -> void:
	if _editing == null:
		return
	_undo.append(HullHandles.snapshot(_editing))
	while _undo.size() > UNDO_DEPTH:
		_undo.remove_at(0)
	_status.text = note


func _step_back() -> void:
	if _undo.is_empty() or _editing == null:
		return
	HullHandles.restore(_editing, _undo.pop_back())
	_canvas.refresh()
	_refresh()


func _revert() -> void:
	if _on_disk == null:
		return
	_remember("przywroc z dysku")
	HullHandles.restore(_editing, HullHandles.snapshot(_on_disk))
	_canvas.refresh()
	_refresh()


func _on_changed() -> void:
	_refresh()


## The counts, the dirty marker and what is still wrong, after anything
## changes.
func _refresh() -> void:
	if _editing == null:
		return
	var trouble: int = 0
	for entry: Dictionary in HullHandles.tally(_editing):
		var count: Label = _rows[entry["field"]]
		var wanted: int = entry["wanted"]
		count.text = ("%d" % entry["have"]) if wanted == 0 else ("%d/%d" % [entry["have"], wanted])
		if not entry["declared"]:
			# Not in the file: what the hull is flying on until someone
			# touches it. Worth marking, because it is the difference
			# between "this hull was designed" and "this is the default".
			count.text += " ~"
		var note: String = entry["note"]
		count.tooltip_text = note
		count.modulate = Color(1.0, 0.55, 0.45) if note != "" else Color.WHITE
		if note != "":
			trouble += 1

	var dirty: bool = not HullHandles.same(_editing, _on_disk)
	_save.disabled = not dirty
	_undo_button.disabled = _undo.is_empty()
	_title.text = "%s%s%s" % [
		_path.get_file(),
		"  *" if dirty else "",
		"    (%d uwag - najedz na licznik)" % trouble if trouble > 0 else "",
	]


## Copy the edited values onto the resource the editor has loaded and
## write it out.
##
## Onto the loaded instance rather than a fresh one on purpose: that
## object is the one `HullData.all()` cached and the one any open
## inspector is showing, so saving updates them instead of leaving three
## versions of the same hull in one process.
##
## Geometry only, for the same reason. The dock draws shapes and never
## shows `display_name` or `cargo_capacity`, so if someone renames a hull
## in the inspector while this is open, saving here must not quietly put
## the old name back.
func _write_file() -> void:
	if _editing == null or _on_disk == null:
		return
	HullHandles.restore(_on_disk, HullHandles.snapshot(_editing), false)
	var failed: Error = ResourceSaver.save(_on_disk, _path)
	if failed != OK:
		_status.text = "nie udalo sie zapisac %s (blad %d)" % [_path, failed]
		return
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().update_file(_path)
	_status.text = "zapisano %s" % _path
	_refresh()
