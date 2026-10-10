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
var _balance: Dictionary = {}
var _reference: OptionButton = null
var _verdict: Label = null
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

	# The figures that decide whether a hand-drawn hull flies straight,
	# and the fitout they are measured with.
	#
	# A hull has no centre of mass of its own: the engines and the modules
	# are most of a ship's weight, and where they sit is the preset's
	# business. So the dock says which fitout it weighed, rather than
	# quoting a number that is true of nothing.
	var heading: Label = Label.new()
	heading.text = "Bilans"
	column.add_child(heading)

	_reference = OptionButton.new()
	for preset: ShipPreset in ShipFitout.all():
		_reference.add_item(preset.display_name)
	_reference.item_selected.connect(_on_reference_picked)
	column.add_child(_reference)

	for row: Array in [
		["mass", "masa"], ["centre", "srodek masy y"],
		["torque_gap", "krzyz momentu"], ["strafe_gap", "strafe od srodka"],
		["leg_drop", "nogi pod kadlubem"],
	]:
		column.add_child(_build_balance_row(row[0], row[1]))

	_verdict = Label.new()
	_verdict.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_verdict)

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


## One line of the balance block: a caption and a figure that goes red
## when it is outside tolerance.
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


func _on_reference_picked(_index: int) -> void:
	_canvas.reference = _picked_reference()
	_canvas.refresh()
	_refresh()


func _picked_reference() -> ShipPreset:
	var presets: Array[ShipPreset] = ShipFitout.all()
	var index: int = _reference.selected
	return presets[index] if index >= 0 and index < presets.size() else null


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
	_canvas.reference = _picked_reference()
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

	_report_balance()

	var dirty: bool = not HullHandles.same(_editing, _on_disk)
	_save.disabled = not dirty
	_undo_button.disabled = _undo.is_empty()
	_title.text = "%s%s%s" % [
		_path.get_file(),
		"  *" if dirty else "",
		"    (%d uwag - najedz na licznik)" % trouble if trouble > 0 else "",
	]


## The balance figures, and one sentence saying what is wrong.
##
## Red is not a refusal. A hull with a 3 px torque gap flies, it just
## yaws when you ask it to strafe -- and knowing that while the mouse is
## still down is the whole point, because the alternative is finding out
## from the smoke test four minutes later.
func _report_balance() -> void:
	var found: Dictionary = _canvas.balance
	if found.is_empty():
		return
	(_balance["mass"] as Label).text = "%.2f kg" % float(found["mass"])
	(_balance["centre"] as Label).text = "%.2f" % (found["centre"] as Vector2).y

	var wrong: Array[String] = []
	for key: String in ["torque_gap", "strafe_gap", "leg_drop"]:
		var value: float = found[key]
		var allowed: float = {
			"torque_gap": HullCanvas.TORQUE_TOLERANCE,
			"strafe_gap": HullCanvas.STRAFE_TOLERANCE,
			"leg_drop": HullCanvas.LEG_TOLERANCE,
		}[key]
		var figure: Label = _balance[key]
		figure.text = "%.2f px" % value
		var over: bool = value > allowed
		figure.modulate = Color(1.0, 0.45, 0.35) if over else Color(0.45, 0.95, 0.60)
		if over:
			wrong.append(key)

	if wrong.is_empty():
		_verdict.text = "wywazony: obrot nie znosi na bok, strafe nie obraca"
		_verdict.modulate = Color(0.45, 0.95, 0.60)
		return
	var says: Array[String] = []
	if wrong.has("torque_gap"):
		says.append("obrot bedzie pchal statek na bok (dysze nie sa para wzgledem srodka masy)")
	if wrong.has("strafe_gap"):
		says.append("strafe bedzie obracal statkiem")
	if wrong.has("leg_drop"):
		says.append("statek stanie wysoko nad gruntem")
	_verdict.text = " - ".join(says)
	_verdict.modulate = Color(1.0, 0.45, 0.35)


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
