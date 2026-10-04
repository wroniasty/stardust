class_name BenchForm
extends RefCounted
## The few widgets every bench panel builds, written once.
##
## Static and stateless on purpose: a panel is a column of labelled
## controls, and the only thing worth sharing between panels is how one row
## of that column is put together, so they all line up.

const HEADING_COLOR: Color = Color(0.72, 0.68, 0.92)
const LABEL_WIDTH: float = 78.0


static func heading(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_color_override("font_color", HEADING_COLOR)
	return label


static func note(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.modulate = Color(1, 1, 1, 0.55)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


## `control` beside a fixed-width caption, taking the rest of the row.
static func labelled(text: String, control: Control) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	var label: Label = Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(LABEL_WIDTH, 0.0)
	label.clip_text = true
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


static func button(text: String, handler: Callable) -> Button:
	var made: Button = Button.new()
	made.text = text
	made.pressed.connect(handler)
	return made


static func check(text: String, handler: Callable, on: bool = false) -> CheckBox:
	var made: CheckBox = CheckBox.new()
	made.text = text
	made.button_pressed = on
	made.toggled.connect(handler)
	return made


## A slider that reports its value and nothing else.
static func slider(low: float, high: float, step: float, value: float) -> HSlider:
	var made: HSlider = HSlider.new()
	made.min_value = low
	made.max_value = high
	made.step = step
	made.value = value
	made.custom_minimum_size = Vector2(60.0, 14.0)
	made.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return made
