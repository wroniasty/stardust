@tool
class_name ResourceForm
extends VBoxContainer
## A form for any Resource, built from what the resource says about itself.
##
## Lived in `tools/workbench/` until the workbench was reset. It survived
## that because it had stopped being the bench's: the preset dock builds
## its own rows from it, and a second auto-form would have been a second
## place for `get_property_list()` quirks to be learned.
##
## Every exported variable becomes a row, typed by `get_property_list()`:
## a range hint is a clamp, an enum hint is a drop-down, an embedded resource
## with its own script (a `SoundStrip` inside a table) unfolds into a form of
## its own. Nothing here knows what a weapon or an engine is, so a field
## added to `WeaponData` tomorrow shows up in the next run with no change to
## the tool -- which is the only reason to build it from the property list
## rather than by hand.
##
## It writes into the live object. Resources are shared through the loader's
## cache, so the engine a ship is flying *is* the one being edited, and a
## change is felt on the next tick without anything being told. That is
## also the reason the preset dock makes a resource its **own copy**
## before handing it to this: editing a catalogue engine in place would
## change it for every preset and every ship in the process.
##
## `@tool` because the preset dock is an editor dock, and a non-tool
## script loaded there is a placeholder whose methods cannot be called
## (DEVTOOLS.md rule 7). It has no `_init` and no side effects, so
## running in the editor costs nothing.
##
## What it does not do: arrays, dictionaries and packed arrays are shown as a
## count and left alone. They are structure rather than a number to nudge,
## and a half-working editor for them would be worse than the inspector.

## Raised after a value has been written, with the resource that owns it
## (which is a sub-resource when the row was in a nested form).
signal edited(resource: Resource)

## How deep embedded resources unfold. Past this a row just names the file.
const MAX_DEPTH: int = 3

## Step used for every real number. Small on purpose: a `SpinBox` snaps to
## its step, so a coarse one would quietly round a value the user only
## looked at when the row was built.
const FLOAT_STEP: float = 0.0001

## The narrowest and widest the caption column is allowed to be.
##
## Measured rather than fixed. It was a flat 78 px, which fits `bulk`
## and `damage` and cuts `rounds_per_second` down to "rounds" -- and a
## form of fifteen rows reading "travers", "travers", "missile",
## "missile" is a form you cannot use. The names are known before a
## single row is built, so the column is sized to the longest of them.
const LABEL_MIN: float = 78.0

## The most of the row the caption column may take.
##
## A share rather than a number of pixels, which means it moves with the
## form: the dock this sits in is resizable and a column that was right
## at 380 px is wrong at 700. Half, so a long field name is readable
## while the control it names still has somewhere to be. Past it the
## name is clipped and the tooltip carries it.
const CAPTION_SHARE: float = 0.5

## What a caption label is called, so it can be told from a label that
## is showing a value.
const CAPTION: StringName = &"Caption"

var _resource: Resource = null
var _depth: int = 0

## When set, the form edits a **set of overrides** on top of `_resource`
## rather than the resource itself, and every row grows a checkbox.
##
## This is what a preset entry wants. An outright copy of a catalogue
## engine freezes all twenty-three of its fields: retune the catalogue
## later and the copy silently keeps the old numbers for every one of
## them, including the ones nobody meant to pin. An override says "this
## engine, but with the damage at 50", and everything unticked follows
## the file it came from.
var _overrides: Dictionary = {}
var _overriding: bool = false

## How wide the longest name in the rows currently shown wants to be,
## before the share above is applied. Measured once per build; the
## clamp is reapplied whenever the form changes size.
var _natural_caption: float = LABEL_MIN

## Whether the collection fields are shown at all. See `show_resource`.
var _with_arrays: bool = true


func _ready() -> void:
	# The share below is of the form's own width, which it does not have
	# until it is laid out -- and changes again whenever the dock is
	# dragged.
	resized.connect(_fit_captions)


## Builds the rows for `resource`, replacing whatever was shown.
## `with_arrays` false leaves out every array, dictionary and packed
## array. They show as a count and cannot be edited here anyway, and
## where something else owns them -- the hull dock's canvas owns a
## hull's outline and its slot lists, and its counters already say how
## many there are -- nine rows of "4 items" is noise in front of the
## three fields this panel is for.
func show_resource(
	resource: Resource, depth: int = 0, with_arrays: bool = true
) -> void:
	_overriding = false
	_overrides = {}
	_resource = resource
	_depth = depth
	_with_arrays = with_arrays
	_build()


## The same rows, but editing `overrides` on top of `base`.
##
## The dictionary is held by reference and written into directly, which
## is what lets the preset entry that owns it see the change without
## being told.
func show_overrides(base: Resource, overrides: Dictionary, depth: int = 0) -> void:
	_overriding = true
	_overrides = overrides
	_resource = base
	_depth = depth
	_with_arrays = true
	_build()


func _build() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	if _resource == null:
		return
	_natural_caption = _widest_caption()
	for property: Dictionary in _resource.get_property_list():
		if not _is_exported(property):
			continue
		# A nested resource cannot be half-overridden: the dictionary is
		# flat, and "this engine but with its curve's third point moved"
		# is not a thing it can say. Shown as a name and left alone.
		if _overriding and int(property["type"]) == TYPE_OBJECT:
			continue
		if not _with_arrays and _is_collection(int(property["type"])):
			continue
		var row: Control = _row(property)
		if row == null:
			continue
		add_child(row if not _overriding else _togglable(String(property["name"]), row))


## A row with a checkbox in front of it: ticked means the preset pins
## this one, unticked means it follows the catalogue.
##
## Ticking seeds the override with the value the row is already showing,
## which is the catalogue's -- so switching it on changes nothing until
## the number beside it is changed, and the figure never jumps.
func _togglable(key: String, row: Control) -> Control:
	var line: HBoxContainer = HBoxContainer.new()
	var tick: CheckBox = CheckBox.new()
	tick.button_pressed = _overrides.has(key)
	tick.tooltip_text = "nadpisz to pole w tym presecie"
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tick.toggled.connect(func(on: bool) -> void:
		if on:
			_overrides[key] = _resource.get(key)
		else:
			_overrides.erase(key)
		_set_live(row, on)
		edited.emit(_resource))
	line.add_child(tick)
	line.add_child(row)
	_set_live(row, _overrides.has(key))
	return line


## Greys out a row that is not overridden, so what the preset actually
## decides is readable at a glance down the column.
func _set_live(where: Node, on: bool) -> void:
	for child: Node in where.get_children():
		if child.get("disabled") != null:
			child.set("disabled", not on)
		if child.get("editable") != null:
			child.set("editable", on)
		_set_live(child, on)
	if where is Control:
		(where as Control).modulate = Color.WHITE if on else Color(1, 1, 1, 0.5)


## Whether the property is one the author wrote with `@export`. The usage
## flags are how the editor tells, and the form follows the editor.
## What the caption column is right now: as wide as the longest name
## asks, and never more than its share of the form.
func caption_width() -> float:
	return minf(_natural_caption, maxf(LABEL_MIN, size.x * CAPTION_SHARE))


## Reapplies that to the rows already built. Connected to `resized`,
## because the answer changes when the dock is dragged wider.
func _fit_captions() -> void:
	var width: float = caption_width()
	for label: Label in _captions_under(self):
		label.custom_minimum_size = Vector2(width, 0.0)


func _captions_under(where: Node) -> Array[Label]:
	var out: Array[Label] = []
	for child: Node in where.get_children():
		if child is Label and child.name == CAPTION:
			out.append(child)
		out.append_array(_captions_under(child))
	return out


## How wide the longest field name wants to be, unclamped.
func _widest_caption() -> float:
	var font: Font = get_theme_default_font()
	var size: int = get_theme_default_font_size()
	var widest: float = LABEL_MIN
	for property: Dictionary in _resource.get_property_list():
		if not _is_exported(property):
			continue
		if not _with_arrays and _is_collection(int(property["type"])):
			continue
		widest = maxf(widest, font.get_string_size(
			String(property["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1.0, size
		).x)
	# Room for the gap the container puts between the two.
	return widest + 6.0


## `control` beside the caption column, taking the rest of the row.
##
## Inlined when the workbench was reset: it was one of six helpers on a
## `BenchForm` class, and the only one anything left standing still
## wanted.
func _labelled(text: String, control: Control) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	var label: Label = Label.new()
	# Named so the dock self-check can tell a caption from the labels
	# that carry a value -- "0 items", a nested resource's file name --
	# which have no column to fit into.
	label.name = CAPTION
	label.text = text
	label.custom_minimum_size = Vector2(caption_width(), 0.0)
	label.clip_text = true
	# The name in full, for the one that was too long even for the
	# ceiling.
	label.tooltip_text = text
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


func _is_exported(property: Dictionary) -> bool:
	var usage: int = property["usage"]
	return (usage & PROPERTY_USAGE_EDITOR) != 0 and (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0


func _row(property: Dictionary) -> Control:
	var key: String = property["name"]
	var value: Variant = _value_of(key)
	match int(property["type"]):
		TYPE_BOOL:
			var check: CheckBox = CheckBox.new()
			check.button_pressed = bool(value)
			check.toggled.connect(func(on: bool) -> void: _write(key, on))
			return _labelled(key, check)
		TYPE_INT:
			if int(property["hint"]) == PROPERTY_HINT_ENUM:
				return _labelled(key, _enum_picker(key, property, int(value)))
			return _labelled(key, _number(key, property, float(value), true))
		TYPE_FLOAT:
			return _labelled(key, _number(key, property, float(value), false))
		TYPE_STRING, TYPE_STRING_NAME:
			var line: LineEdit = LineEdit.new()
			line.text = str(value)
			var is_name: bool = int(property["type"]) == TYPE_STRING_NAME
			line.text_submitted.connect(func(text: String) -> void:
				_write(key, StringName(text) if is_name else text))
			line.focus_exited.connect(func() -> void:
				var current: String = str(_value_of(key))
				if line.text != current:
					_write(key, StringName(line.text) if is_name else line.text))
			return _labelled(key, line)
		TYPE_COLOR:
			var picker: ColorPickerButton = ColorPickerButton.new()
			picker.color = value
			picker.custom_minimum_size = Vector2(40.0, 14.0)
			picker.color_changed.connect(func(color: Color) -> void: _write(key, color))
			return _labelled(key, picker)
		TYPE_VECTOR2:
			return _labelled(key, _vector(key, value as Vector2))
		TYPE_OBJECT:
			return _object_row(key, value as Resource)
		TYPE_ARRAY, TYPE_DICTIONARY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_FLOAT32_ARRAY:
			var label: Label = Label.new()
			label.text = "%d items" % _count_of(value)
			label.modulate = Color(1, 1, 1, 0.55)
			return _labelled(key, label)
	return null


## A spin box for a number, clamped to the range hint when there is one and
## free beyond it when the hint says `or_greater`.
func _number(key: String, property: Dictionary, value: float, whole: bool) -> SpinBox:
	var spin: SpinBox = SpinBox.new()
	spin.step = 1.0 if whole else FLOAT_STEP
	spin.allow_greater = true
	spin.allow_lesser = true
	spin.custom_minimum_size = Vector2(70.0, 0.0)
	if int(property["hint"]) == PROPERTY_HINT_RANGE:
		var parts: PackedStringArray = String(property["hint_string"]).split(",")
		if parts.size() >= 2:
			spin.min_value = float(parts[0])
			spin.max_value = float(parts[1])
			spin.allow_greater = String(property["hint_string"]).contains("or_greater")
			spin.allow_lesser = String(property["hint_string"]).contains("or_less")
	else:
		spin.min_value = -1000000.0
		spin.max_value = 1000000.0
	spin.set_value_no_signal(value)
	spin.value_changed.connect(func(v: float) -> void: _write(key, int(v) if whole else v))
	return spin


## "A,B,C" or "A:5,B:7": the names, and the values when they are not 0..n.
func _enum_picker(key: String, property: Dictionary, value: int) -> OptionButton:
	var picker: OptionButton = OptionButton.new()
	var next: int = 0
	for entry: String in String(property["hint_string"]).split(","):
		var parts: PackedStringArray = entry.split(":")
		if parts.size() > 1:
			next = int(parts[1])
		picker.add_item(parts[0].strip_edges(), next)
		if next == value:
			picker.selected = picker.item_count - 1
		next += 1
	picker.item_selected.connect(func(index: int) -> void: _write(key, picker.get_item_id(index)))
	return picker


func _vector(key: String, value: Vector2) -> HBoxContainer:
	var box: HBoxContainer = HBoxContainer.new()
	var spins: Array[SpinBox] = []
	for axis: int in range(2):
		var spin: SpinBox = SpinBox.new()
		spin.step = FLOAT_STEP
		spin.allow_greater = true
		spin.allow_lesser = true
		spin.min_value = -1000000.0
		spin.max_value = 1000000.0
		spin.custom_minimum_size = Vector2(56.0, 0.0)
		spin.set_value_no_signal(value[axis])
		spins.append(spin)
		box.add_child(spin)
	for spin: SpinBox in spins:
		spin.value_changed.connect(func(_v: float) -> void:
			_write(key, Vector2(spins[0].value, spins[1].value)))
	return box


## An embedded resource with a script unfolds; a file reference just says
## which file it is.
func _object_row(key: String, value: Resource) -> Control:
	if value == null:
		var empty: Label = Label.new()
		empty.text = "(none)"
		empty.modulate = Color(1, 1, 1, 0.55)
		return _labelled(key, empty)
	if value.get_script() == null or _depth >= MAX_DEPTH or not value.resource_path.is_empty():
		var named: Label = Label.new()
		named.text = value.resource_path.get_file() if not value.resource_path.is_empty() \
				else value.get_class()
		named.clip_text = true
		named.modulate = Color(1, 1, 1, 0.55)
		return _labelled(key, named)

	var box: VBoxContainer = VBoxContainer.new()
	var fold: Button = Button.new()
	fold.text = "▸ %s" % key
	fold.toggle_mode = true
	fold.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var inner: ResourceForm = ResourceForm.new()
	inner.visible = false
	inner.edited.connect(func(source: Resource) -> void: edited.emit(source))
	inner.show_resource(value, _depth + 1)
	fold.toggled.connect(func(open: bool) -> void:
		inner.visible = open
		fold.text = "%s %s" % ["▾" if open else "▸", key])
	box.add_child(fold)
	box.add_child(inner)
	return box


func _count_of(value: Variant) -> int:
	if value is Array or value is Dictionary:
		return value.size()
	return (value as PackedVector2Array).size() if value is PackedVector2Array \
			else (value as PackedFloat32Array).size()


## Writes one value into the live resource and says so.
##
## `emit_changed` as well as the signal of our own: other holders of the
## resource (an inspector, a sprite built off it) listen for that one, and
## a form that edited behind their backs would leave them showing the old
## number.
## Whether this is one of the types shown as a count rather than
## edited.
static func _is_collection(type: int) -> bool:
	return type in [
		TYPE_ARRAY, TYPE_DICTIONARY,
		TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_FLOAT32_ARRAY,
	]


## What the row shows: the override when there is one, the resource's
## own value otherwise.
func _value_of(key: String) -> Variant:
	if _overriding and _overrides.has(key):
		return _overrides[key]
	return _resource.get(key)


func _write(key: String, value: Variant) -> void:
	if _overriding:
		# Into the dictionary, never into the catalogue resource: the
		# engine being shown is the one every other preset and every
		# flying ship is holding.
		_overrides[key] = value
		edited.emit(_resource)
		return
	_resource.set(key, value)
	_resource.emit_changed()
	edited.emit(_resource)
