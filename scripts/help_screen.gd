class_name HelpScreen
extends CanvasLayer
## Every key the game answers to, on one screen.
##
## **Read out of the InputMap, not written down here.** A list of bindings
## typed into a help screen is a list that is wrong by the second patch --
## and wrong in the worst way, because the pilot believes it. What is
## written down here is only what each action *means*; which key does it
## comes from the same table the game reads when it asks whether the key is
## down, so the screen cannot disagree with the ship.
##
## The chords come from `ControlChords.CHORDS` for the same reason. They
## are not in the InputMap -- they are combinations of actions that are --
## so the screen spells them out of the same array the matcher uses.
##
## A test pins the one thing this cannot check itself: that every action in
## the map has an entry in LABELS. Add a binding without documenting it and
## the suite fails, which is the only way a help screen stays honest.

const FONT_SIZE: int = 8
const ROW: float = 10.0
const MARGIN: float = 10.0
const COLUMN_GAP: float = 14.0

## Room for the key names before the description starts. Wide enough for
## the longest of them -- an action with two keys on it prints both, and
## "Equal / Kp Add" ran straight through its own description at the first
## guess.
const KEY_WIDTH: float = 92.0

const SCRIM: Color = Color(0.03, 0.04, 0.06, 0.97)
const HEADING: Color = Color(0.55, 0.78, 1.00)
const KEY: Color = Color(1.00, 0.86, 0.45)
const TEXT: Color = Color(0.80, 0.84, 0.90)
const DIM: Color = Color(0.45, 0.50, 0.58)
const BAD: Color = Color(1.00, 0.40, 0.35)

## What each action is for, and which block it belongs in. The order here
## is the order on screen: blocks in the order they first appear, actions
## in the order they are listed.
##
## English, like the rest of what the pilot reads.
const LABELS: Array[Dictionary] = [
	{"block": "FLIGHT", "action": &"thrust_forward", "says": "thrust forward"},
	{"block": "FLIGHT", "action": &"thrust_reverse", "says": "thrust reverse"},
	{"block": "FLIGHT", "action": &"rotate_left", "says": "rotate left"},
	{"block": "FLIGHT", "action": &"rotate_right", "says": "rotate right"},
	{"block": "FLIGHT", "action": &"strafe_left", "says": "strafe left"},
	{"block": "FLIGHT", "action": &"strafe_right", "says": "strafe right"},
	{"block": "FLIGHT", "action": &"brake", "says": "brake (in vacuum: turn, then burn)"},
	{"block": "FLIGHT", "action": &"boost", "says": "boost (burns the pool)"},
	{"block": "FLIGHT", "action": &"jump", "says": "jump: aim the nose and hold"},
	{"block": "FLIGHT", "action": &"toggle_gear", "says": "landing gear"},
	{"block": "FLIGHT", "action": &"ship_fire", "says": "fire"},
	{"block": "FLIGHT", "action": &"ship_fire_secondary", "says": "fire, second group"},

	{"block": "COMPUTER", "action": &"hold_prograde", "says": "nose into the motion"},
	{"block": "COMPUTER", "action": &"hold_retrograde", "says": "nose against the motion"},
	{"block": "COMPUTER", "action": &"kill_rotation", "says": "kill rotation"},

	{"block": "VIEW", "action": &"camera_zoom_in", "says": "zoom in"},
	{"block": "VIEW", "action": &"camera_zoom_out", "says": "zoom out"},
	{"block": "VIEW", "action": &"camera_rotate_left", "says": "turn the view left"},
	{"block": "VIEW", "action": &"camera_rotate_right", "says": "turn the view right"},
	{"block": "VIEW", "action": &"camera_level", "says": "level the view"},

	{"block": "SCREENS", "action": &"toggle_help", "says": "this screen"},
	{"block": "SCREENS", "action": &"toggle_map", "says": "system map"},
	{"block": "SCREENS", "action": &"toggle_loadout", "says": "hold"},
	{"block": "SCREENS", "action": &"loadout_next", "says": "hold: next"},
	{"block": "SCREENS", "action": &"loadout_fit", "says": "hold: fit"},
	{"block": "SCREENS", "action": &"loadout_drop", "says": "hold: drop"},
	{"block": "SCREENS", "action": &"toggle_editor", "says": "ship editor"},
	{"block": "SCREENS", "action": &"editor_stow", "says": "editor: stow"},
	{"block": "SCREENS", "action": &"editor_aim_ccw", "says": "editor: turn the mount left"},
	{"block": "SCREENS", "action": &"editor_aim_cw", "says": "editor: turn the mount right"},
	{"block": "SCREENS", "action": &"editor_trigger", "says": "editor: change the trigger"},

	{"block": "DEBUG", "action": &"debug_toggle", "says": "debug overlay"},
	{"block": "DEBUG", "action": &"debug_creative", "says": "sandbox"},
	{"block": "DEBUG", "action": &"debug_planet", "says": "planet configurator"},
	{"block": "DEBUG", "action": &"bench_toggle_panel", "says": "workbench: hide the panel"},
	{"block": "DEBUG", "action": &"debug_carve", "says": "carve a crater"},
	{"block": "DEBUG", "action": &"debug_damage_engine", "says": "damage an engine"},
	{"block": "DEBUG", "action": &"debug_repair", "says": "repair the engines"},
	{"block": "DEBUG", "action": &"toggle_presentation", "says": "presentation layer"},
]

## What each chord is for. Keyed by `ControlChords.Chord`.
const CHORD_SAYS: Dictionary = {
	ControlChords.Chord.KILL_ROTATION: "kill rotation",
	ControlChords.Chord.PROGRADE: "nose into the motion",
	ControlChords.Chord.RETROGRADE: "nose against the motion",
	ControlChords.Chord.AUTO_ORBIT: "hold a circular orbit",
	ControlChords.Chord.AUTO_LEVEL: "nose along the horizon",
	ControlChords.Chord.ALTITUDE_HOLD: "hold altitude",
	ControlChords.Chord.DEORBIT: "lower the orbit",
}

var _canvas: Control = null


func _ready() -> void:
	# Above every other panel: this is the one a pilot opens when they are
	# lost in one of the others.
	layer = 26
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_help)
	add_child(_canvas)
	_canvas.hide()


func is_open() -> bool:
	return _canvas.visible


func toggle() -> void:
	if is_open():
		close()
		return
	_canvas.show()
	PauseGate.hold_exclusive(self, get_tree())
	_canvas.queue_redraw()


func close() -> void:
	_canvas.hide()
	PauseGate.release(self, get_tree())


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_help"):
		toggle()
		get_viewport().set_input_as_handled()
	elif is_open() and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


## Every line the screen will draw, as (kind, key, text).
##
## Built as data so the test can read it without a viewport, and so the
## two-column split below is a layout decision rather than a second pass
## over the content.
func lines() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var block: String = ""
	for entry: Dictionary in LABELS:
		if entry["block"] != block:
			block = entry["block"]
			out.append({"kind": "head", "key": "", "text": block})
		out.append({
			"kind": "bind",
			"key": keys_for(entry["action"]),
			"text": entry["says"],
		})

	out.append({"kind": "head", "key": "", "text": "CHORDS"})
	for chord: Dictionary in ControlChords.CHORDS:
		var pressed: Array[String] = []
		for action: StringName in chord["keys"]:
			pressed.append(keys_for(action))
		out.append({
			"kind": "bind",
			"key": "+".join(pressed),
			"text": String(CHORD_SAYS.get(chord["chord"], "?")),
		})
	return out


## The keys bound to `action`, as the pilot would name them.
##
## First event only when there are several, plus the count: "Z" is more
## use on a crowded screen than "Z / DELETE", and the pilot who wants the
## other one can find it in the settings the day there are settings.
static func keys_for(action: StringName) -> String:
	if not InputMap.has_action(action):
		return "?"
	var names: Array[String] = []
	for event: InputEvent in InputMap.action_get_events(action):
		var key: InputEventKey = event as InputEventKey
		if key != null:
			names.append(OS.get_keycode_string(key.physical_keycode))
			continue
		var click: InputEventMouseButton = event as InputEventMouseButton
		if click != null:
			names.append("LMB" if click.button_index == MOUSE_BUTTON_LEFT else "RMB")
	if names.is_empty():
		return "?"
	return names[0] if names.size() == 1 else "%s / %s" % [names[0], names[1]]


## Which actions the game knows about but this screen does not. Empty, or
## the suite fails: see the class comment.
static func undocumented() -> Array[StringName]:
	var known: Dictionary = {}
	for entry: Dictionary in LABELS:
		known[entry["action"]] = true
	var missing: Array[StringName] = []
	for action: StringName in InputMap.get_actions():
		# Godot's own ui_* actions are the engine's, not the game's.
		if String(action).begins_with("ui_"):
			continue
		if not known.has(action):
			missing.append(action)
	return missing


func _draw_help() -> void:
	var font: Font = ModuleData.card_font()
	var view: Vector2 = _canvas.size
	_canvas.draw_rect(Rect2(Vector2.ZERO, view), SCRIM, true)

	var rows: Array[Dictionary] = lines()
	# Split so the two columns come out level, and never in the middle of
	# a block's heading.
	var half: int = _split_at(rows)
	var column: float = (view.x - MARGIN * 2.0 - COLUMN_GAP) * 0.5
	_draw_column(font, rows.slice(0, half), Vector2(MARGIN, MARGIN + ROW))
	_draw_column(
		font, rows.slice(half), Vector2(MARGIN + column + COLUMN_GAP, MARGIN + ROW)
	)

	var missing: Array[StringName] = undocumented()
	if not missing.is_empty():
		_text(
			font,
			Vector2(MARGIN, view.y - MARGIN),
			"undocumented: %s" % ", ".join(missing),
			BAD,
		)
	else:
		_text(font, Vector2(MARGIN, view.y - MARGIN), "ESC or ? closes", DIM)


## Where to break the list into two columns: at the block boundary that
## leaves the two columns closest to the same length.
##
## On a boundary, so a heading is never stranded at the foot of a column
## with its first line overleaf; closest to even, because the obvious
## "first boundary past the middle" left one column seven rows short of
## the other and the screen looked like it had been cut off.
func _split_at(rows: Array[Dictionary]) -> int:
	var best: int = int(ceilf(float(rows.size()) * 0.5))
	var closest: int = rows.size()
	for at: int in range(1, rows.size()):
		if rows[at]["kind"] != "head":
			continue
		var gap: int = absi(rows.size() - at * 2)
		if gap < closest:
			closest = gap
			best = at
	return best


func _draw_column(font: Font, rows: Array[Dictionary], at: Vector2) -> void:
	var y: float = at.y
	for row: Dictionary in rows:
		if row["kind"] == "head":
			y += ROW * 0.4
			_text(font, Vector2(at.x, y), String(row["text"]), HEADING)
		else:
			_text(font, Vector2(at.x, y), String(row["key"]), KEY)
			_text(font, Vector2(at.x + KEY_WIDTH, y), String(row["text"]), TEXT)
		y += ROW


func _text(font: Font, at: Vector2, text: String, colour: Color) -> void:
	_canvas.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, colour)
