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
static func run(
	hulls: HullEditor, presets: PresetEditor, items: ItemEditor
) -> int:
	var failures: int = 0
	failures += _placeholders()
	failures += _captions()
	failures += _hull_dock(hulls)
	failures += _preset_dock(presets)
	failures += _skin(hulls, presets)
	failures += _item_dock(items)
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


## Dok modulow: wiersze zakresow, probki i zapis bez zapisywania.
##
## Everything here is a thing that can only be checked in the editor,
## and the dock is **all** of those: it reads `get_property_list()` to
## decide which fields may carry a band, which is the call a placeholder
## lies about, and it previews a roll by calling the generator, which in
## a non-`@tool` world would be a placeholder refusing a method.
##
## It never saves. The sample panel and the band rows are built, read
## and thrown away; what the file on disk says is what it said before.
static func _item_dock(dock: ItemEditor) -> int:
	var failures: int = 0
	failures += _says(dock != null and dock._files != null, "the item dock built")
	failures += _says(_has_splitter(dock), "with dividers that can be dragged")
	if dock == null or dock._files == null:
		return failures

	# Every kind in the catalogue is offered, and every kind has files.
	failures += _says(
		dock._kinds.item_count == ModuleData.CATALOGUE.size(),
		"one kind per catalogue entry (%d)" % dock._kinds.item_count,
	)
	var empty: Array[String] = []
	for entry: Dictionary in ModuleData.CATALOGUE:
		if ModuleData.files_of(entry["id"]).is_empty():
			empty.append(String(entry["id"]))
	failures += _says(
		empty.is_empty(),
		"and every kind has files (%s)" % [
			"all seven" if empty.is_empty() else str(empty),
		],
	)

	# A weapon, which is the kind with the most bandable fields.
	dock._on_kind_picked(0)
	dock._open(0)
	failures += _says(dock._editing != null, "and opened an item")
	if dock._editing == null:
		return failures
	failures += _says(
		dock._editing != dock._on_disk,
		"on a loose copy rather than on the file the game is using",
	)
	var fields: Array[String] = ItemEditor.bandable_fields(dock._editing)
	failures += _says(
		fields.size() >= 8 and fields.has("damage") and fields.has("bulk"),
		"with a band row per rollable field (%d, damage and bulk among them)" % fields.size(),
	)
	failures += _says(
		dock._rows.size() == fields.size(),
		"all of them built (%d rows)" % dock._rows.size(),
	)

	# Turning a band on seeds it from the file, so switching it on is
	# not a change. Then the samples: five grades, and the dull end of
	# a band must not come out above the good end.
	var was: float = float(dock._editing.get("damage"))
	dock._on_band_toggled(true, "damage")
	var seeded: Vector2 = dock._editing.roll_ranges.get("damage", Vector2.ZERO)
	failures += _says(
		is_equal_approx(seeded.x, was) and is_equal_approx(seeded.y, was),
		"switching a band on seeds both ends from the file (%.4f)" % was,
	)
	(dock._rows["damage"]["dull"] as SpinBox).value = was * 0.5
	(dock._rows["damage"]["good"] as SpinBox).value = was * 2.0
	dock._on_band_edited(0.0, "damage")
	dock._refresh()
	failures += _says(
		dock._samples.get_child_count() == ModuleData.RARITY_NAMES.size(),
		"one sample per grade (%d)" % dock._samples.get_child_count(),
	)
	var dull: ModuleData = dock._loot.sample(
		dock._editing, dock._kind, 0, dock._seed
	) as ModuleData
	var best: ModuleData = dock._loot.sample(
		dock._editing, dock._kind, ModuleData.RARITY_NAMES.size() - 1, dock._seed
	) as ModuleData
	failures += _says(
		dull != null and best != null and dull.damage < best.damage,
		"and a legendary rolls above a common on a banded field (%.4f vs %.4f)" % [
			0.0 if dull == null else dull.damage, 0.0 if best == null else best.damage,
		],
	)
	# The note is the dock explaining itself, and the one case worth
	# checking is the kind the generator does not read at all.
	var computers: int = 0
	for i: int in range(ModuleData.CATALOGUE.size()):
		if ModuleData.CATALOGUE[i]["id"] == &"computer":
			computers = i
	dock._on_kind_picked(computers)
	dock._open(0)
	failures += _says(
		dock._note.text.contains("wlasnej tabeli"),
		"and the computers say the generator does not read them",
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

	failures += _swapping_a_row(dock)

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

	failures += _computer_form()
	failures += _layer_switch(hulls, "kadlubow")
	failures += _layer_switch(presets, "presetow")
	return failures


## Czy komputer pokladowy da sie nadpisac w doku.
##
## The bay rows got an override panel with the other two, and a
## generator's fields are all floats -- so "a bay can be overridden" was
## measured on the easiest possible module. A flight computer is the
## awkward one: an **enum** and five **booleans**, which are two row
## types the float path never exercises. Either the form builds them or
## the panel opens on a computer with most of it missing, and nothing
## would say which.
##
## Built here rather than through a dock, because no shipped preset
## carries a computer and the catalogue is what a designer would reach
## for. What is being checked is the form, and the form is what the dock
## hands a module to.
static func _computer_form() -> int:
	var box: FlightComputerData = load(
		"res://resources/computers/orbital_pilot.tres"
	) as FlightComputerData
	if box == null:
		return _says(false, "the catalogue has a computer to override")

	var form: ResourceForm = ResourceForm.new()
	# Parented, because a form sizes its caption column off the theme and
	# an orphan control has no theme to ask.
	var holder: Control = Control.new()
	holder.add_child(form)
	form.show_overrides(box, {})

	var wanted: Array[String] = [
		"allocation", "has_rotation_kill", "has_auto_level", "has_auto_orbit",
		"has_altitude_hold", "has_deorbit", "idle_draw", "bulk",
	]
	var seen: Dictionary = {}
	for label: Label in _labels_under(form):
		seen[label.text] = true
	var missing: Array[String] = []
	for field: String in wanted:
		if not seen.has(field):
			missing.append(field)
	var failures: int = _says(
		missing.is_empty(),
		"a computer's own fields are all overridable (%d rows, %s)" % [
			form.get_child_count(),
			"none missing" if missing.is_empty() else str(missing),
		],
	)

	# And the two row types a generator could not have reached: the
	# allocation is a dropdown, the functions are checkboxes.
	var drops: int = 0
	var ticks: int = 0
	for child: Node in _everything_under(form):
		if child is OptionButton:
			drops += 1
		elif child is CheckBox:
			ticks += 1
	failures += _says(
		drops >= 1 and ticks >= wanted.size(),
		"with the enum as a dropdown and a pin box per field (%d dropdowns, %d boxes)" % [
			drops, ticks,
		],
	)
	holder.queue_free()
	return failures


## Every node below `where`, flattened.
static func _everything_under(where: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child: Node in where.get_children():
		out.append(child)
		out.append_array(_everything_under(child))
	return out


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


## Czy podmiana rzeczy w wierszu przebudowuje ten wiersz.
##
## Reported from the editor: an empty bay given a module out of the
## dropdown kept its override button greyed out. The row had captured
## `bay.installed` when it was built -- null at the time -- and nothing
## rebuilt it, so the button, the panel and the pin boxes all still
## belonged to the module that was not there.
##
## The bay is where it showed, and the engine row is where it mattered:
## there the button stays enabled across a swap, the panel opens, and
## what it shows is the **previous** engine's fields. A check that only
## looked at the reported symptom would have left that.
##
## Picked through the dropdown's own signal rather than by writing to
## the fit, because what was broken is the wiring between the two.
static func _swapping_a_row(dock: PresetEditor) -> int:
	var failures: int = 0
	var index: int = -1
	for i: int in range(dock._editing.bays.size()):
		if dock._editing.bays[i] != null and dock._editing.bays[i].installed == null:
			index = i
			break
	if index < 0:
		return _says(false, "the preset has an empty bay to fill")

	var pick: OptionButton = _first_option(dock._bay_rows.get_child(index))
	var button: Button = _stats_toggle(dock._bay_rows.get_child(index))
	failures += _says(
		pick != null and button != null and button.disabled,
		"an empty bay offers nothing to override",
	)
	if pick == null:
		return failures

	# The second entry: the first is "(pusta)".
	pick.select(1)
	pick.item_selected.emit(1)
	failures += _says(
		dock._editing.bays[index].installed != null,
		"picking a module puts it in the bay",
	)
	# The same button object, not a new one: nothing was rebuilt, which
	# is why this needs no waiting for a deferred call and why the
	# dropdown that emitted is still alive to be clicked again.
	var after: Button = _stats_toggle(dock._bay_rows.get_child(index))
	failures += _says(
		after == button and not after.disabled,
		"and the override button on that very row wakes up with it",
	)

	# And the pins. A field the new thing has not got is invisible in
	# the panel and fatal at `fault_in`, so it goes.
	var fit: BayFit = dock._editing.bays[index]
	fit.overrides = {"bulk": 9.0, "no_such_field": 1.0}
	dock.refresh_stats("bays:%d" % index)
	failures += _says(
		after.text.begins_with("override ("),
		"pinning a field shows on the shut button (%s)" % after.text,
	)
	pick.select(0)
	pick.item_selected.emit(0)
	failures += _says(
		fit.overrides.is_empty(),
		"emptying the bay drops the pins that had nothing to pin to (%s)" % fit.overrides,
	)

	# And the case nobody reported, because it does not look broken: an
	# engine row keeps its button enabled across a swap, so the panel
	# opens and shows fields. Which engine's fields is the question, and
	# every `EngineData` has the same field **names** -- so this asks the
	# form what resource it is showing rather than reading its captions,
	# which would agree with either answer.
	failures += _engine_row_follows_its_engine(dock)
	return failures


static func _engine_row_follows_its_engine(dock: PresetEditor) -> int:
	var key: String = "mounts:0"
	if dock._editing.mounts.is_empty() or not dock._stats_rows.has(key):
		return _says(false, "the preset has an engine row to swap")
	# The **second** dropdown. An engine row carries two -- where the
	# mount goes, then which engine -- and taking the first one changed
	# the place and left the engine alone, which this check caught by
	# reporting that the panel had not followed a swap that never
	# happened.
	var picks: Array[OptionButton] = _options_under(dock._mount_rows.get_child(0))
	if picks.size() < 2:
		return _says(false, "the engine row has a catalogue dropdown (%d)" % picks.size())
	var pick: OptionButton = picks[1]

	# Opened the way the mouse opens it, so the panel under test is the
	# one a designer is looking at.
	_press_stats(dock._mount_rows, 0)
	var was: Resource = _form_subject(dock._stats_rows[key]["indent"])
	var failures: int = _says(
		was != null and was == dock._editing.mounts[0].engine,
		"an open engine panel shows the engine that is in the mount",
	)

	# Something else out of the catalogue: whichever entry is not the
	# one already fitted.
	var other: int = 1 if pick.selected == 0 else 0
	pick.select(other)
	pick.item_selected.emit(other)
	var now: Resource = _form_subject(dock._stats_rows[key]["indent"])
	failures += _says(
		now != null and now == dock._editing.mounts[0].engine and now != was,
		"and follows the swap instead of showing the one that left",
	)
	_press_stats(dock._mount_rows, 0, false)
	return failures


## Which resource the form inside a row's panel is built on.
static func _form_subject(where: Node) -> Resource:
	for child: Node in where.get_children():
		if child is ResourceForm:
			return child._resource
		var deeper: Resource = _form_subject(child)
		if deeper != null:
			return deeper
	return null


## Every dropdown in a row, in the order they were added.
static func _options_under(where: Node) -> Array[OptionButton]:
	var out: Array[OptionButton] = []
	for child: Node in where.get_children():
		var pick: OptionButton = child as OptionButton
		if pick != null:
			out.append(pick)
		out.append_array(_options_under(child))
	return out


static func _first_option(where: Node) -> OptionButton:
	var all: Array[OptionButton] = _options_under(where)
	return all[0] if not all.is_empty() else null


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
