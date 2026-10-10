@tool
class_name DockSelfcheck
extends RefCounted
## Czy doki naprawde dzialaja w edytorze -- sprawdzane w edytorze.
##
## The smoke test runs as a game, where every scripted resource is a
## real instance. In the editor a `.tres` whose script is not `@tool`
## loads as a placeholder, and a placeholder breaks two ways: calling a
## method on it fails outright, and `get_property_list()` reports its
## exported fields without `PROPERTY_USAGE_SCRIPT_VARIABLE`. The second
## one is silent -- it emptied the stats form and nothing was printed.
##
## Both were found by hand, with a probe pasted into the plugin and
## taken out again, three times. This is that probe kept: the gate runs
## the editor once with `--dock-selfcheck` and scans what it says.
##
## Deliberately read-only. It opens files and builds controls; it never
## saves, because a check that edits the project is a check nobody will
## leave switched on.

## What `check.ps1` passes after `--` to ask for this.
const FLAG: String = "--dock-selfcheck"

## What the gate greps for.
const BAD: String = "DOCK FAIL"
const GOOD: String = "DOCK ok  "


## Whether this run was asked to check itself.
static func asked() -> bool:
	return OS.get_cmdline_user_args().has(FLAG)


## Runs every check against the docks the plugin just built, and
## returns how many failed.
static func run(hulls: HullEditor, presets: PresetEditor) -> int:
	var failures: int = 0
	failures += _placeholders()
	failures += _captions()
	failures += _hull_dock(hulls)
	failures += _preset_dock(presets)
	print("DOCK %s" % (
		"all checks passed" if failures == 0 else "%d check(s) failed" % failures
	))
	return failures


## The two ways a placeholder lies, asked directly.
static func _placeholders() -> int:
	var failures: int = 0
	# Loud: a method on a loaded resource. On a placeholder this raises
	# "Attempt to call a method on a placeholder instance", which the
	# gate catches as a SCRIPT ERROR even if the count below passes.
	var hull: HullData = HullData.of(&"dart")
	failures += _says(
		hull != null and hull.slots().size() > 0,
		"a loaded hull answers its own methods (%d places)" % [
			0 if hull == null else hull.slots().size(),
		],
	)

	# Silent: the property list. This is the one that emptied the stats
	# form with nothing reported -- the fields are all there, they just
	# come back without the script-variable bit.
	var gun: Resource = load("res://resources/weapons/autocannon.tres")
	var script_vars: int = 0
	if gun != null:
		for property: Dictionary in gun.get_property_list():
			if (int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
				script_vars += 1
	failures += _says(
		script_vars > 0,
		"a loaded weapon reports its exported fields (%d)" % script_vars,
	)
	return failures


## Czy podpisy pol sie miesczcza.
##
## Reported from the dock as fifteen rows reading "damag", "rounds",
## "travers", "travers": the caption column was a flat 78 px and the
## names were clipped to nonsense. It is measured from the names now,
## and this is what stops it being a constant again.
static func _captions() -> int:
	var gun: Resource = load("res://resources/weapons/autocannon.tres")
	var form: ResourceForm = ResourceForm.new()
	# Sized first: the column is a share of the form's width now, so a
	# form of no width would clamp every caption to the floor and this
	# would have nothing to measure.
	form.size = Vector2(400.0, 300.0)
	form.show_resource(gun)
	var font: Font = form.get_theme_default_font()
	var size: int = form.get_theme_default_font_size()
	var clipped: Array[String] = []
	for label: Label in _labels_under(form):
		var needs: float = font.get_string_size(
			label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size
		).x
		# The ceiling worked out here rather than asked of the form:
		# `caption_width()` is what sets these labels, so comparing
		# against it compares the answer with itself. Pinning the column
		# to the floor passed a check written that way.
		var ceiling: float = maxf(
			ResourceForm.LABEL_MIN, form.size.x * ResourceForm.CAPTION_SHARE
		)
		# At the ceiling the name is clipped on purpose and the tooltip
		# carries it; below it the name has to fit.
		if label.custom_minimum_size.x < needs and label.custom_minimum_size.x < ceiling:
			clipped.append(label.text)
	var rows: int = _labels_under(form).size()
	form.free()
	return _says(
		rows > 0 and clipped.is_empty(),
		"every field name fits its column (%d rows, %s)" % [
			rows, "none clipped" if clipped.is_empty() else str(clipped),
		],
	)


static func _labels_under(where: Node) -> Array[Label]:
	var out: Array[Label] = []
	for child: Node in where.get_children():
		# Captions only: a label showing a value has no column to fit.
		if child is Label and child.name == ResourceForm.CAPTION:
			out.append(child)
		out.append_array(_labels_under(child))
	return out


static func _hull_dock(dock: HullEditor) -> int:
	var failures: int = 0
	failures += _says(dock != null and dock._canvas != null, "the hull dock built")
	if dock == null or dock._canvas == null:
		return failures
	dock._canvas.size = Vector2(400.0, 300.0)
	dock._open(0)
	failures += _says(dock._editing != null, "and opened a hull")
	if dock._editing == null:
		return failures
	failures += _says(
		HullHandles.of(dock._editing).size() > 0,
		"with places to drag (%d)" % HullHandles.of(dock._editing).size(),
	)
	failures += _says(
		dock._canvas.balance.has("centre"),
		"and a centre of mass to draw",
	)
	return failures


static func _preset_dock(dock: PresetEditor) -> int:
	var failures: int = 0
	failures += _says(dock != null and dock._canvas != null, "the preset dock built")
	if dock == null or dock._canvas == null:
		return failures
	dock._canvas.size = Vector2(400.0, 300.0)
	# The first preset that carries a gun, not simply the first file:
	# the alphabetically first is the bare hull, which has none, and the
	# gun row is where the placeholder bug actually showed.
	for index: int in range(dock._files.item_count):
		dock._open(index)
		if dock._editing != null and not dock._editing.guns.is_empty():
			break
	failures += _says(dock._editing != null, "and opened a preset")
	if dock._editing == null or dock._editing.mounts.is_empty():
		return failures
	failures += _says(
		ShipFitout.placements(dock._editing.hull, dock._editing).size() > 0,
		"with engines to draw (%d)" % ShipFitout.placements(
			dock._editing.hull, dock._editing
		).size(),
	)

	# The stats panel, which is what the placeholder bug emptied. Opened
	# the way the button opens it, so this fails if the wiring changes
	# and not only if the form does.
	#
	# Every row, not only the first: a mount bound to a named place is
	# a different path through `_mount_row` from one bound to a kind,
	# and the first row is whichever the preset happens to list first.
	var empty_mounts: Array[String] = []
	for index: int in range(dock._editing.mounts.size()):
		# Pressed, not set. The handler rebuilds every row, which frees
		# the very button that is emitting -- and that is the part a
		# check which only wrote `_open_rows` would never exercise.
		if not _press_stats(dock._mount_rows, index):
			empty_mounts.append("mounts:%d no button" % index)
			continue
		if _form_rows(dock._mount_rows) == 0:
			empty_mounts.append("mounts:%d" % index)
		# Pressed again to close it, the same way, so the next row is
		# measured on its own.
		_press_stats(dock._mount_rows, index, false)
	failures += _says(
		empty_mounts.is_empty(),
		"every engine row opens a stats panel (%d rows, %s)" % [
			dock._editing.mounts.size(),
			"all filled" if empty_mounts.is_empty() else str(empty_mounts),
		],
	)

	# And the same for a gun, which is the row the bug was reported on:
	# an engine kept working because `EngineData` happened to be fixed
	# first, so a check that only looked there would have passed.
	failures += _says(not dock._editing.guns.is_empty(), "the preset carries a gun")
	if not dock._editing.guns.is_empty():
		_press_stats(dock._gun_rows, 0)
		failures += _says(
			_form_rows(dock._gun_rows) > 0,
			"whose stats panel has rows too (%d)" % _form_rows(dock._gun_rows),
		)
		_press_stats(dock._gun_rows, 0, false)
	return failures


## Presses the stats toggle on one row, the way a mouse would, and
## says whether there was one to press.
static func _press_stats(rows: Node, index: int, on: bool = true) -> bool:
	var row: Node = rows.get_child(index) if index < rows.get_child_count() else null
	if row == null:
		return false
	var button: Button = _stats_toggle(row)
	if button == null:
		return false
	button.button_pressed = on
	return true


static func _stats_toggle(where: Node) -> Button:
	for child: Node in where.get_children():
		var button: Button = child as Button
		if button != null and button.toggle_mode and button.text.begins_with("staty"):
			return button
		var deeper: Button = _stats_toggle(child)
		if deeper != null:
			return deeper
	return null


## How many rows the first **shown** `ResourceForm` under here has.
##
## Visibility counts. The panel is hidden rather than destroyed when the
## toggle is off, so a check that merely found the form would pass on a
## panel nobody can see -- which is the shape of the bug it is here to
## catch.
static func _form_rows(where: Node) -> int:
	for child: Node in where.get_children():
		var control: Control = child as Control
		if control != null and not control.visible:
			continue
		if child is ResourceForm:
			return child.get_child_count()
		var deeper: int = _form_rows(child)
		if deeper > 0:
			return deeper
	return 0


static func _says(passed: bool, description: String) -> int:
	print("%s%s" % [GOOD if passed else BAD + " ", description])
	return 0 if passed else 1
