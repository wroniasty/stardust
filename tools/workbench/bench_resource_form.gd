class_name BenchResourceForm
extends VBoxContainer
## A form for any Resource, built from what the resource says about itself.
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
## change is felt on the next tick without anything being told.
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

var _resource: Resource = null
var _depth: int = 0


## Builds the rows for `resource`, replacing whatever was shown.
func show_resource(resource: Resource, depth: int = 0) -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_resource = resource
	_depth = depth
	if resource == null:
		return
	for property: Dictionary in resource.get_property_list():
		if not _is_exported(property):
			continue
		var row: Control = _row(property)
		if row != null:
			add_child(row)


## Whether the property is one the author wrote with `@export`. The usage
## flags are how the editor tells, and the form follows the editor.
func _is_exported(property: Dictionary) -> bool:
	var usage: int = property["usage"]
	return (usage & PROPERTY_USAGE_EDITOR) != 0 and (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0


func _row(property: Dictionary) -> Control:
	var key: String = property["name"]
	var value: Variant = _resource.get(key)
	match int(property["type"]):
		TYPE_BOOL:
			var check: CheckBox = CheckBox.new()
			check.button_pressed = bool(value)
			check.toggled.connect(func(on: bool) -> void: _write(key, on))
			return BenchForm.labelled(key, check)
		TYPE_INT:
			if int(property["hint"]) == PROPERTY_HINT_ENUM:
				return BenchForm.labelled(key, _enum_picker(key, property, int(value)))
			return BenchForm.labelled(key, _number(key, property, float(value), true))
		TYPE_FLOAT:
			return BenchForm.labelled(key, _number(key, property, float(value), false))
		TYPE_STRING, TYPE_STRING_NAME:
			var line: LineEdit = LineEdit.new()
			line.text = str(value)
			var is_name: bool = int(property["type"]) == TYPE_STRING_NAME
			line.text_submitted.connect(func(text: String) -> void:
				_write(key, StringName(text) if is_name else text))
			line.focus_exited.connect(func() -> void:
				var current: String = str(_resource.get(key))
				if line.text != current:
					_write(key, StringName(line.text) if is_name else line.text))
			return BenchForm.labelled(key, line)
		TYPE_COLOR:
			var picker: ColorPickerButton = ColorPickerButton.new()
			picker.color = value
			picker.custom_minimum_size = Vector2(40.0, 14.0)
			picker.color_changed.connect(func(color: Color) -> void: _write(key, color))
			return BenchForm.labelled(key, picker)
		TYPE_VECTOR2:
			return BenchForm.labelled(key, _vector(key, value as Vector2))
		TYPE_OBJECT:
			return _object_row(key, value as Resource)
		TYPE_ARRAY, TYPE_DICTIONARY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_FLOAT32_ARRAY:
			var label: Label = Label.new()
			label.text = "%d elementów" % _count_of(value)
			label.modulate = Color(1, 1, 1, 0.55)
			return BenchForm.labelled(key, label)
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
		empty.text = "(brak)"
		empty.modulate = Color(1, 1, 1, 0.55)
		return BenchForm.labelled(key, empty)
	if value.get_script() == null or _depth >= MAX_DEPTH or not value.resource_path.is_empty():
		var named: Label = Label.new()
		named.text = value.resource_path.get_file() if not value.resource_path.is_empty() \
				else value.get_class()
		named.clip_text = true
		named.modulate = Color(1, 1, 1, 0.55)
		return BenchForm.labelled(key, named)

	var box: VBoxContainer = VBoxContainer.new()
	var fold: Button = Button.new()
	fold.text = "▸ %s" % key
	fold.toggle_mode = true
	fold.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var inner: BenchResourceForm = BenchResourceForm.new()
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
func _write(key: String, value: Variant) -> void:
	_resource.set(key, value)
	_resource.emit_changed()
	edited.emit(_resource)
