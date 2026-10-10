@tool
extends EditorPlugin
## Stardust devtools: trzy doki w edytorze. DEVTOOLS.md, D6.
##
## Three jobs now. Run the sandbox scene. Give hulls a dock, because a
## hull is a shape and the inspector shows it as a column of numbers
## (`hull_editor.gd`). And presets another, because a preset is four
## lines that build nine engines somewhere, and no column of dropdowns
## says where (`preset_editor.gd`).
##
## What it also used to do: list every game resource by kind and open it
## in the inspector, and forward each inspector edit to a running
## workbench over the debugger channel. Both went with the workbench.
## The list had become the worse way to reach a hull or a preset now
## that each has a dock of its own, and the channel had nothing at the
## far end once `BenchBridge` was gone. Both are in the history
## (`git show 6d8c67a:addons/stardust_devtools/plugin.gd`) for whenever
## the new sandbox wants a link back.

const SANDBOX_SCENE: String = "res://tools/sandbox/sandbox.tscn"

var _dock: VBoxContainer = null

## The hull editor's dock, in the bottom panel where a wide canvas fits.
##
## `add_dock` rather than the one-line `add_control_to_bottom_panel`,
## which 4.7 deprecates in favour of exactly this. `EditorDock` is marked
## experimental in return, which is a trade a dev tool can make and the
## game cannot: if a later Godot moves it, this file breaks and nothing
## that ships does.
var _hulls: EditorDock = null
var _presets: EditorDock = null


func _enter_tree() -> void:
	_build_dock()
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)

	_hulls = EditorDock.new()
	_hulls.title = "Kadluby"
	_hulls.icon_name = &"Polygon2D"
	_hulls.default_slot = EditorDock.DOCK_SLOT_BOTTOM
	_hulls.available_layouts = EditorDock.DOCK_LAYOUT_ALL
	var hull_editor: HullEditor = HullEditor.new()
	_hulls.add_child(hull_editor)
	add_dock(_hulls)

	_presets = EditorDock.new()
	_presets.title = "Presety"
	_presets.icon_name = &"PackedScene"
	_presets.default_slot = EditorDock.DOCK_SLOT_BOTTOM
	_presets.available_layouts = EditorDock.DOCK_LAYOUT_ALL
	var preset_editor: PresetEditor = PresetEditor.new()
	_presets.add_child(preset_editor)
	add_dock(_presets)

	# Asked for from the command line by `check.ps1`, and silent
	# otherwise. The docks only exist in the editor and the smoke test
	# runs as a game, so this is the only place their failures are
	# visible at all (DEVTOOLS.md rule 8).
	if DockSelfcheck.asked():
		DockSelfcheck.run(hull_editor, preset_editor)


func _exit_tree() -> void:
	for dock: EditorDock in [_presets, _hulls]:
		if dock != null:
			remove_dock(dock)
			dock.queue_free()
	_presets = null
	_hulls = null
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null


func _build_dock() -> void:
	_dock = VBoxContainer.new()
	_dock.name = "Stardust"

	var run: Button = Button.new()
	run.text = "Uruchom Sandbox"
	run.pressed.connect(func() -> void: EditorInterface.play_custom_scene(SANDBOX_SCENE))
	_dock.add_child(run)

	var stop: Button = Button.new()
	stop.text = "Zatrzymaj"
	stop.pressed.connect(func() -> void: EditorInterface.stop_playing_scene())
	_dock.add_child(stop)
