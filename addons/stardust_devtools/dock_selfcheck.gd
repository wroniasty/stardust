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
	failures += _skin(hulls, presets)
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
	failures += _says(_has_splitter(dock), "with dividers that can be dragged")
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

	# The attribute form, and what it deliberately leaves out: the
	# outline and the slot lists belong to the canvas and to the
	# counters, and nine rows of "4 items" in front of three editable
	# fields is the noise this was built to avoid.
	var captions: Array[Label] = _labels_under(dock._attributes)
	var geometry: Array[String] = []
	for label: Label in captions:
		if label.text in ["outline", "legs", "drive_slots", "torque_slots"]:
			geometry.append(label.text)
	failures += _says(
		captions.size() > 0 and geometry.is_empty(),
		"the hull's own fields are editable (%d rows, %s)" % [
			captions.size(),
			"no geometry among them" if geometry.is_empty() else str(geometry),
		],
	)
	return failures


static func _preset_dock(dock: PresetEditor) -> int:
	var failures: int = 0
	failures += _says(dock != null and dock._canvas != null, "the preset dock built")
	failures += _says(_has_splitter(dock), "with dividers that can be dragged")
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
			"whose override panel has rows too (%d)" % _form_rows(dock._gun_rows),
		)
		_press_stats(dock._gun_rows, 0, false)

	# A filled bay, not simply the first: an empty hole has nothing to
	# override and its button is disabled on purpose.
	var filled: int = -1
	for index: int in range(dock._editing.bays.size()):
		if dock._editing.bays[index] != null and dock._editing.bays[index].installed != null:
			filled = index
			break
	# What the bay dropdown can actually offer. A kind with no `.tres`
	# anywhere is a kind a designed ship cannot carry, which is what the
	# flight computer was until `resources/computers` existed -- and
	# dropping the directory out of `MODULE_DIRS` would otherwise break
	# nothing that anybody notices.
	var kinds: Dictionary = {}
	for module: Resource in dock._modules:
		kinds[module.get_script()] = true
	var computers: int = 0
	for module: Resource in dock._modules:
		if module is FlightComputerData:
			computers += 1
	failures += _says(
		computers > 0 and kinds.size() >= 5,
		"the bay dropdown offers every kind, computers included (%d kinds, %d boxes)" % [
			kinds.size(), computers,
		],
	)

	failures += _says(filled >= 0, "the preset has a bay with a module in it")
	if filled >= 0:
		_press_stats(dock._bay_rows, filled)
		failures += _says(
			_form_rows(dock._bay_rows) > 0,
			"and the module can be overridden too (%d rows)" % _form_rows(dock._bay_rows),
		)
		_press_stats(dock._bay_rows, filled, false)
	return failures


## Czy skorka naprawde da sie narysowac w edytorze.
##
## The reason this is here and not only in the suite: a still is made of
## `LookTable`s and `SpriteStrip`s loaded from `.tres`, which is exactly
## the shape of thing that comes back as a placeholder in the editor.
## The suite runs as a game and structurally cannot see that -- it would
## report every picture present while the dock showed an empty canvas.
##
## So the pictures are counted here, and the switch is picked the way a
## mouse picks it rather than by writing to the canvas.
static func _skin(hulls: HullEditor, presets: PresetEditor) -> int:
	var failures: int = 0

	# Loud, if a table ever stops being a tool script: `pick` is a
	# method, and a method on a placeholder raises.
	var table: LookTable = ShipLook.table(ShipLook.HULL_TABLE)
	var drawn: SpriteStrip = null
	if table != null:
		drawn = table.pick(HullData.of(&"dart"), &"dart")
	failures += _says(
		drawn != null and drawn.is_valid() and drawn.frame_size().x > 0,
		"a look table hands out a usable strip in the editor (%s)" % [
			"none" if drawn == null else str(drawn.frame_size()),
		],
	)

	failures += _layer_switch(hulls, "kadlubow")
	failures += _layer_switch(presets, "presetow")
	return failures


## Picks every layer on one dock and says whether the pictures follow.
##
## The canvas is asked what it is actually holding rather than whether
## the enum changed, because the enum changing is not the thing that was
## broken when a previous check of mine set state and rebuilt by hand:
## the wiring was.
static func _layer_switch(dock: Node, which: String) -> int:
	var switch: OptionButton = dock.get("_layers") as OptionButton if dock != null else null
	var canvas: HullView = dock.get("_canvas") as HullView if dock != null else null
	if switch == null or canvas == null:
		return _says(false, "the %s dock has a layer switch" % which)

	var counts: Array[int] = []
	for index: int in range(switch.item_count):
		switch.select(index)
		# `select` deliberately does not emit, so this is the other half
		# of what a click does. Without it the handler never runs and
		# the check would be measuring an assignment it made itself.
		switch.item_selected.emit(index)
		counts.append((canvas.get("_still") as Array).size())
	var ok: bool = (
		counts.size() == 3 and counts[0] == 0
		and counts[1] > 0 and counts[2] > 0
	)
	var failures: int = _says(
		ok, "the %s dock draws pictures only when asked (%s)" % [which, str(counts)]
	)

	# And the view frames what it draws. A still that the framing does
	# not know about gets its plumes cropped at the edge of the dock.
	switch.select(HullView.Layer.SKIN)
	switch.item_selected.emit(HullView.Layer.SKIN)
	var with_art: int = canvas.framed_points().size()
	switch.select(HullView.Layer.SCHEMATIC)
	switch.item_selected.emit(HullView.Layer.SCHEMATIC)
	var without: int = canvas.framed_points().size()
	failures += _says(
		with_art > without,
		"and frames the art it draws (%d points against %d)" % [with_art, without],
	)

	# Left as it was found, since the next check shares the dock.
	switch.select(HullView.Layer.BOTH)
	switch.item_selected.emit(HullView.Layer.BOTH)
	return failures


## Presses the override toggle on one row, the way a mouse would, and
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
		if button != null and button.toggle_mode and button.text.begins_with("override"):
			return button
		var deeper: Button = _stats_toggle(child)
		if deeper != null:
			return deeper
	return null


## Whether this dock lays its columns out in something draggable.
##
## Both were `HBoxContainer`s, where the width of the side panel was a
## number somebody had to pick for everybody.
static func _has_splitter(where: Node) -> bool:
	for child: Node in where.get_children():
		if child is HSplitContainer:
			return true
		if _has_splitter(child):
			return true
	return false


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
