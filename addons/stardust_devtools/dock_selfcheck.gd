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
	dock._open_rows["mounts:0"] = true
	dock._rebuild_rows()
	failures += _says(
		_form_rows(dock._mount_rows) > 0,
		"and a stats panel with rows in it (%d)" % _form_rows(dock._mount_rows),
	)
	dock._open_rows["mounts:0"] = false

	# And the same for a gun, which is the row the bug was reported on:
	# an engine kept working because `EngineData` happened to be fixed
	# first, so a check that only looked there would have passed.
	failures += _says(not dock._editing.guns.is_empty(), "the preset carries a gun")
	if not dock._editing.guns.is_empty():
		dock._open_rows["guns:0"] = true
		dock._rebuild_rows()
		failures += _says(
			_form_rows(dock._gun_rows) > 0,
			"whose stats panel has rows too (%d)" % _form_rows(dock._gun_rows),
		)
		dock._open_rows["guns:0"] = false
	dock._rebuild_rows()
	return failures


## How many rows the first `ResourceForm` under here has.
static func _form_rows(where: Node) -> int:
	for child: Node in where.get_children():
		if child is ResourceForm:
			return child.get_child_count()
		var deeper: int = _form_rows(child)
		if deeper > 0:
			return deeper
	return 0


static func _says(passed: bool, description: String) -> int:
	print("%s%s" % [GOOD if passed else BAD + " ", description])
	return 0 if passed else 1
