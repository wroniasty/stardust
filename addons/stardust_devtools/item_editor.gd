@tool
class_name ItemEditor
extends VBoxContainer
## Dock "Moduly": kazdy rodzaj przedmiotu, jego pola i to, co kupuje
## rzadkosc. DEVTOOLS.md, D8.
##
## The third dock, and the one D8 left open: "ten sam dock dla broni i
## silników (`FIELDS` jest tabelą, nie kodem)". It turned out to need no
## `FIELDS` at all. A hull is a shape and a preset is an assembly, so
## each of those docks draws a picture nobody else can draw; an item is
## **numbers**, and the inspector already shows numbers. What the
## inspector cannot show is the two things this dock is for:
##
## **Whether the generator may use this file** (`ModuleData.rollable`).
## Before it, the generator kept six hard-coded lists of paths, so the
## answer lived in a script a designer does not open and was given by
## omission.
##
## **What rarity buys, per file** (`ModuleData.roll_ranges`). The
## inspector shows a dictionary of `Vector2` as a fold-out of key/value
## pairs with no idea which field names are legal, which end of the pair
## is the good one, or what the result looks like. Here every row is a
## field the generator can actually roll, the two ends are labelled, and
## the panel underneath rolls the thing five times so the answer is on
## screen next to the question.
##
## Edited on a **loose copy**, like the other two docks: the resource the
## loader handed over is the one every preset and every running ship is
## pointing at, so a number typed here would otherwise be live before
## anybody pressed save.

## Read as a script rather than as the autoload, which does not exist in
## the editor. The same thing the smoke test does, for the same reason.
const LOOT_SCRIPT: GDScript = preload("res://scripts/autoload/loot_generator.gd")

## How the five sample rolls are seeded. Fixed, so the panel does not
## shuffle under a designer typing into the row above it; the reroll
## button is there for when one sample reads oddly.
const PREVIEW_SEED: int = 20261012

## The narrowest the right-hand column may be squeezed, and how much
## wider than half it starts. The same pair as the other two docks, and
## the same reason: a floor low enough to be a floor rather than a
## layout.
const SIDE_FLOOR: float = 260.0
const SIDE_EXTRA: float = 300.0

## Step for every spin box, matching `ResourceForm`: a coarse step
## rounds a value somebody only looked at.
const FLOAT_STEP: float = 0.0001

## How far a band end may be typed when the field has no entry in
## `LootGenerator.LIMITS`. Wide, because the limits table is about what
## the game can take and this is only about what a text box will accept.
const OPEN_END: float = 100000.0

var _kinds: OptionButton = null
var _files: ItemList = null
var _title: Label = null
var _form: ResourceForm = null
var _bands: VBoxContainer = null
var _note: Label = null
var _samples: VBoxContainer = null
var _status: Label = null
var _save: Button = null

## field name -> {"check": CheckBox, "dull": SpinBox, "good": SpinBox}
var _rows: Dictionary = {}

var _paths: Array[String] = []
var _kind: StringName = &""

## The file as the loader has it, and the loose copy being edited.
var _on_disk: ModuleData = null
var _editing: ModuleData = null
var _path: String = ""

var _seed: int = PREVIEW_SEED
var _loot: Node = null


func _ready() -> void:
	custom_minimum_size = Vector2(0.0, 340.0)
	_loot = LOOT_SCRIPT.new()
	_loot.name = "Roller"
	add_child(_loot)
	_build()
	_fill_kinds()


func _build() -> void:
	var columns: HSplitContainer = HSplitContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(columns)

	columns.add_child(_build_file_list())

	var rest: HSplitContainer = HSplitContainer.new()
	rest.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rest.split_offset = -int(SIDE_EXTRA)
	columns.add_child(rest)

	rest.add_child(_build_fields())
	rest.add_child(_build_side())

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.text = "wybierz rodzaj i plik"
	add_child(_status)


## Left: which kind, then which file of that kind.
func _build_file_list() -> Control:
	var column: VBoxContainer = VBoxContainer.new()
	column.custom_minimum_size = Vector2(170.0, 0.0)
	_kinds = OptionButton.new()
	_kinds.item_selected.connect(_on_kind_picked)
	column.add_child(_kinds)
	_files = ItemList.new()
	_files.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_files.item_selected.connect(_open)
	column.add_child(_files)
	return column


## Middle: the fields of the file itself, from its own property list.
##
## Without arrays and dictionaries, as the hull dock's panel is: the one
## dictionary an item has is `roll_ranges`, and it has a panel of its own
## on the right where the field names can be the rows rather than
## something to be typed correctly.
func _build_fields() -> Control:
	var column: VBoxContainer = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title = Label.new()
	_title.text = "nic nie wybrane"
	column.add_child(_title)

	var scroller: ScrollContainer = ScrollContainer.new()
	scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroller)
	_form = ResourceForm.new()
	_form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_form.edited.connect(_on_field_edited)
	scroller.add_child(_form)
	return column


## Right: the bands, the rolls they produce, and the two buttons.
func _build_side() -> Control:
	var scroller: ScrollContainer = ScrollContainer.new()
	scroller.custom_minimum_size = Vector2(SIDE_FLOOR, 0.0)
	scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var column: VBoxContainer = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroller.add_child(column)

	var caption: Label = Label.new()
	caption.text = "Zakresy losowania"
	column.add_child(caption)

	_note = Label.new()
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.modulate = Color(0.75, 0.78, 0.84)
	column.add_child(_note)

	# Which column is which, written down rather than remembered. The
	# whole point of naming the ends is that "from 3.0 to 0.8" and "from
	# 0.8 to 3.0" are the same band -- the generator reads which end is
	# the good one off the field, not off the order.
	var header: HBoxContainer = HBoxContainer.new()
	var spacer: Label = Label.new()
	spacer.text = "pole"
	spacer.custom_minimum_size = Vector2(96.0, 0.0)
	header.add_child(spacer)
	for text: String in ["nudny", "najlepszy"]:
		var mark: Label = Label.new()
		mark.text = text
		mark.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(mark)
	column.add_child(header)

	_bands = VBoxContainer.new()
	_bands.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_bands)

	column.add_child(HSeparator.new())
	var rolls: Label = Label.new()
	rolls.text = "Co z tego wychodzi"
	column.add_child(rolls)
	_samples = VBoxContainer.new()
	_samples.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_samples)

	var reroll: Button = Button.new()
	reroll.text = "przelosuj probki"
	reroll.pressed.connect(_on_reroll)
	column.add_child(reroll)

	column.add_child(HSeparator.new())
	_save = Button.new()
	_save.text = "Zapisz .tres"
	_save.pressed.connect(_write_file)
	column.add_child(_save)
	var revert: Button = Button.new()
	revert.text = "Przywroc z dysku"
	revert.pressed.connect(_revert)
	column.add_child(revert)
	return scroller


func _fill_kinds() -> void:
	_kinds.clear()
	for entry: Dictionary in ModuleData.CATALOGUE:
		_kinds.add_item(String(entry["title"]))
	if ModuleData.CATALOGUE.is_empty():
		return
	_kinds.select(0)
	_on_kind_picked(0)


func _on_kind_picked(index: int) -> void:
	if index < 0 or index >= ModuleData.CATALOGUE.size():
		return
	_kind = ModuleData.CATALOGUE[index]["id"]
	_fill_files()
	_forget()


## The files of the current kind, with the ones outside the loot pool
## dimmed.
##
## Dimmed rather than hidden or marked with a word: the list is the one
## place a designer can see the pool at a glance, and "which of these
## twelve does the generator use" is a question the flag now answers
## file by file.
func _fill_files() -> void:
	_files.clear()
	_paths.clear()
	for path: String in ModuleData.files_of(_kind):
		var module: ModuleData = load(path) as ModuleData
		_paths.append(path)
		_files.add_item(path.get_file().get_basename())
		var last: int = _files.item_count - 1
		if module != null and not module.rollable:
			_files.set_item_custom_fg_color(last, Color(0.55, 0.57, 0.62))
			_files.set_item_tooltip(last, "poza pula losowania (rollable = false)")


func _forget() -> void:
	_on_disk = null
	_editing = null
	_path = ""
	_title.text = "nic nie wybrane"
	_form.show_resource(null, 0, false)
	_rebuild_bands()
	_refresh()


func _open(index: int) -> void:
	if index < 0 or index >= _paths.size():
		return
	_path = _paths[index]
	_on_disk = load(_path) as ModuleData
	if _on_disk == null:
		_status.text = "%s to nie jest ModuleData" % _path
		return
	_editing = copy_of(_on_disk)
	_title.text = "%s  (%s)" % [_editing.display_name, _path.get_file()]
	_form.show_resource(_editing, 0, false)
	_rebuild_bands()
	_refresh()
	_status.text = "edytujesz kopie %s" % _path.get_file()


## A loose copy of a module, bands and all.
##
## `duplicate()` copies the property values and would hand back the
## **same** dictionary object for `roll_ranges`, so editing a band on the
## copy would edit the file's -- which is the one thing editing a copy
## exists to prevent. Public and static because the dock's own check
## wants it without a dock.
static func copy_of(item: ModuleData) -> ModuleData:
	var copy: ModuleData = item.duplicate() as ModuleData
	copy.roll_ranges = item.roll_ranges.duplicate()
	copy.affixes = item.affixes.duplicate()
	return copy


## Which fields of a module may carry a band: its own exported floats,
## and only those the generator knows which way is up for.
##
## Asked of the resource rather than listed per kind, which is the whole
## of what D8 meant by "`FIELDS` is a table, not code" -- except that
## here there is no table either. A float added to `WeaponData` tomorrow
## gets a row the next time this dock opens, as long as somebody said in
## `HIGHER_IS_BETTER` which way is better. A float with no direction
## cannot be banded, because a band's two ends are the dull one and the
## good one and nothing would know which was which.
static func bandable_fields(item: ModuleData) -> Array[String]:
	var out: Array[String] = []
	if item == null:
		return out
	var directions: Dictionary = LOOT_SCRIPT.HIGHER_IS_BETTER
	for property: Dictionary in item.get_property_list():
		var usage: int = property["usage"]
		if (usage & PROPERTY_USAGE_EDITOR) == 0:
			continue
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		if int(property["type"]) != TYPE_FLOAT:
			continue
		var field: String = property["name"]
		if directions.has(field):
			out.append(field)
	return out


func _rebuild_bands() -> void:
	for child: Node in _bands.get_children():
		_bands.remove_child(child)
		child.queue_free()
	_rows = {}
	if _editing == null:
		return
	for field: String in bandable_fields(_editing):
		_bands.add_child(_build_band_row(field))


func _build_band_row(field: String) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	var check: CheckBox = CheckBox.new()
	check.text = field
	check.custom_minimum_size = Vector2(96.0, 0.0)
	check.clip_text = true
	check.tooltip_text = field
	check.button_pressed = _editing.roll_ranges.has(field)
	check.toggled.connect(_on_band_toggled.bind(field))
	row.add_child(check)

	var band: Vector2 = _editing.roll_ranges.get(field, Vector2.ZERO)
	var better: bool = bool(LOOT_SCRIPT.HIGHER_IS_BETTER[field])
	var dull: SpinBox = _build_end(field, ModuleData.dull_end(band, better))
	var good: SpinBox = _build_end(field, ModuleData.good_end(band, better))
	row.add_child(dull)
	row.add_child(good)
	_rows[field] = {"check": check, "dull": dull, "good": good}
	_set_row_live(field, check.button_pressed)
	return row


func _build_end(field: String, value: float) -> SpinBox:
	var box: SpinBox = SpinBox.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.step = FLOAT_STEP
	box.allow_lesser = false
	box.allow_greater = false
	# The field's own floor and ceiling when the generator has one: a
	# band outside them would be rolled and then clamped, which is a
	# number typed and a different number used.
	var limits: Dictionary = LOOT_SCRIPT.LIMITS
	if limits.has(field):
		var bounds: Vector2 = limits[field]
		box.min_value = bounds.x
		box.max_value = bounds.y
		box.tooltip_text = "%s: %s .. %s" % [
			field, short(bounds.x), short(bounds.y),
		]
	else:
		box.min_value = 0.0
		box.max_value = OPEN_END
	box.value = value
	box.value_changed.connect(_on_band_edited.bind(field))
	return box


## Turning a band on seeds both ends with the value the file already
## has, so switching it on changes nothing until a number is moved. The
## preset dock's overrides work the same way and for the same reason: a
## checkbox that silently rerolls an item is a checkbox nobody dares
## press twice.
func _on_band_toggled(on: bool, field: String) -> void:
	if _editing == null:
		return
	var row: Dictionary = _rows[field]
	if on:
		var now: float = float(_editing.get(field))
		(row["dull"] as SpinBox).set_value_no_signal(now)
		(row["good"] as SpinBox).set_value_no_signal(now)
		_editing.roll_ranges[field] = Vector2(now, now)
	else:
		_editing.roll_ranges.erase(field)
	_set_row_live(field, on)
	_refresh()


func _on_band_edited(_value: float, field: String) -> void:
	if _editing == null or not _editing.roll_ranges.has(field):
		return
	var row: Dictionary = _rows[field]
	_editing.roll_ranges[field] = Vector2(
		(row["dull"] as SpinBox).value, (row["good"] as SpinBox).value
	)
	_refresh()


func _set_row_live(field: String, on: bool) -> void:
	var row: Dictionary = _rows[field]
	for key: String in ["dull", "good"]:
		var box: SpinBox = row[key]
		box.editable = on
		box.modulate = Color.WHITE if on else Color(1.0, 1.0, 1.0, 0.45)


## A field typed in the middle column. Nothing to rebuild -- the bands
## are rows about field *names* -- but the samples are rolled from the
## values, so they are not what they were.
func _on_field_edited(_resource: Resource) -> void:
	_refresh()


func _on_reroll() -> void:
	_seed += 1
	_refresh()


func _revert() -> void:
	if _on_disk == null:
		return
	_editing = copy_of(_on_disk)
	_form.show_resource(_editing, 0, false)
	_rebuild_bands()
	_refresh()
	_status.text = "przywrocono %s z dysku" % _path.get_file()


## Writes the copy back onto the loaded resource and saves it.
##
## Onto the loaded instance rather than a fresh one, which is the hull
## dock's reasoning and holds harder here: that object is the one the
## preset catalogue, every running ship and any open inspector are
## pointing at, so saving updates them instead of leaving two versions
## of one autocannon in the process.
func _write_file() -> void:
	if _editing == null or _on_disk == null:
		return
	for field: String in _fields_of(_editing):
		_on_disk.set(field, _editing.get(field))
	_on_disk.roll_ranges = _editing.roll_ranges.duplicate()
	var failed: Error = ResourceSaver.save(_on_disk, _path)
	if failed != OK:
		_status.text = "nie udalo sie zapisac %s (blad %d)" % [_path, failed]
		return
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().update_file(_path)
	_status.text = "zapisano %s" % _path
	_refresh()


## A number short enough for a row of this width.
##
## Written out rather than `%.4g`, because **GDScript's format operator
## has no `%g`**: it hands the format string straight back and the
## engine prints "unsupported format character". This file printed that
## sixty-two times into its first gate run, and the gate said the docks
## passed -- the dock stage was grepped for `DOCK FAIL` and `SCRIPT
## ERROR` only, so an engine error in the editor was invisible to it.
## Both halves are fixed; the project had already written the `%g` half
## down once, in `configuration_report.gd`.
static func short(value: float) -> String:
	var size: float = absf(value)
	if size >= 1000.0:
		return "%.0f" % value
	if size >= 100.0:
		return "%.1f" % value
	if size >= 1.0:
		return "%.2f" % value
	return "%.3f" % value


## Every exported property of a module, by name.
static func _fields_of(item: ModuleData) -> Array[String]:
	var out: Array[String] = []
	for property: Dictionary in item.get_property_list():
		var usage: int = property["usage"]
		if (usage & PROPERTY_USAGE_STORAGE) == 0:
			continue
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		out.append(property["name"])
	return out


## The note, the samples and whether saving is allowed.
func _refresh() -> void:
	_note.text = _explain()
	if _save != null:
		_save.disabled = _editing == null
	_fill_samples()


## What a designer has to know about this kind and this file before
## typing a band into it.
##
## Both halves are states the dock can be in where a band is a number
## nothing reads, and neither is an error: a catalogue item is supposed
## to be out of the pool, and a computer is supposed to be built from
## its own table.
func _explain() -> String:
	if _editing == null:
		return "wybierz plik"
	var entry: Dictionary = ModuleData.kind_entry(_kind)
	if not bool(entry.get("rolls", true)):
		return (
			"Generator buduje ten rodzaj z wlasnej tabeli, nie z pliku: "
			+ "funkcje losuje rzadkosc (LootGenerator.computer). "
			+ "Zakresy i `rollable` nie sa tu czytane -- te pliki sluza "
			+ "presetom i zdarzeniom."
		)
	if not _editing.rollable:
		return (
			"`rollable` wylaczone: generator tego pliku nie uzywa, "
			+ "wiec zakresy nic nie robia. Plik dalej sluzy presetom "
			+ "i zdarzeniom."
		)
	if _editing.roll_ranges.is_empty():
		return (
			"Bez zakresow: rzadkosc daje tylko affiksy, a liczby sa "
			+ "takie, jak w pliku. Zaznacz pole, zeby rzadkosc nim ruszala."
		)
	return "Rzadkosc ciagnie zaznaczone pola od nudnego konca do najlepszego."


## Five rolls of this base, one per grade, from the generator itself.
##
## The point of the panel. A band is two numbers and an affix table is
## twelve rows of multipliers, and what a designer wants to know is what
## comes out of the pair -- which is a question only the generator can
## answer, so it is asked rather than modelled. The same instance, the
## same `_dress`, the same clamps.
##
## **Every stat, not only the banded ones.** The first version printed
## the fields with bands on them, so a file with no bands showed one
## number -- `bulk` -- and a tank rolled five times read as five
## identical tanks. What a roll does to the rest is most of the news:
## an affix moved something, the clamps caught something, and neither is
## visible if the panel only prints what the designer was already
## looking at.
##
## The rows are the module's own `stat_rows()`, which is what a card
## shows the pilot: one list, so a sample here and a find in the game
## cannot describe the same item differently. A banded field the card
## leaves out is appended, because somebody is tuning it.
func _fill_samples() -> void:
	for child: Node in _samples.get_children():
		_samples.remove_child(child)
		child.queue_free()
	if _editing == null or _loot == null:
		return
	for grade: int in range(ModuleData.RARITY_NAMES.size()):
		var rolled: ModuleData = _loot.sample(
			_editing, _kind, grade, _seed + grade * 7919
		) as ModuleData
		_samples.add_child(_sample_block(grade, rolled))


## One grade: what it is called, and what it came out as.
##
## Two labels rather than one line, because the name carries the affixes
## and the numbers carry the result, and at this width they are both
## going to wrap -- so the break is put where it means something instead
## of wherever the column ends.
func _sample_block(grade: int, rolled: ModuleData) -> Control:
	var block: VBoxContainer = VBoxContainer.new()
	block.add_theme_constant_override("separation", 0)
	var head: Label = Label.new()
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.modulate = ModuleData.RARITY_COLORS[grade]
	block.add_child(head)
	if rolled == null:
		head.text = "%s: nie udalo sie zlosowac" % ModuleData.RARITY_NAMES[grade]
		return block
	head.text = "%s  %s" % [ModuleData.RARITY_NAMES[grade], rolled.title()]
	var stats: Label = Label.new()
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats.text = "   %s" % stats_line(rolled)
	# The same hue, dimmer: the grade is the thing to find at a glance
	# and the numbers are what you read once you have found it.
	stats.modulate = Color(ModuleData.RARITY_COLORS[grade], 0.75)
	block.add_child(stats)
	return block


## Everything a rolled item has to say, in one line.
##
## `stat_rows()` is the module's own answer to that and already carries
## how many digits each figure deserves, so this prints rather than
## decides. Public, because the dock's check reads it to say the panel
## shows more than one number.
static func stats_line(item: ModuleData) -> String:
	var parts: PackedStringArray = PackedStringArray()
	var said: Dictionary = {}
	for stat: Dictionary in item.stat_rows():
		var label: String = stat["label"]
		said[label] = true
		parts.append("%s %s%s" % [
			label,
			String.num(float(stat["value"]), int(stat["digits"])),
			String(stat["suffix"]),
		])
	# A band on a field the card does not print is still a field
	# somebody is tuning, and this panel is where they are tuning it.
	for field: String in item.roll_ranges:
		if said.has(field) or not field in item:
			continue
		parts.append("%s %s" % [field, short(float(item.get(field)))])
	return "  ".join(parts)
