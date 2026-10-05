extends Node2D
## Every interface primitive on one sheet, twice.
##
##     godot --path . tools/widget_gallery.tscn
##     godot --path . tools/widget_gallery.tscn -- <directory for the PNGs>
##
## UI_STYLE section 9 asks for this before the second widget rather than
## after the last one, and the reason turned up the same day it was
## written: the star's surface needed looking at, there was nowhere to
## look at it, so a throwaway renderer got written and deleted inside an
## hour. A style you cannot see is a style you argue about.
##
## Two sheets, because half of this vocabulary only exists to say
## something is wrong, and a widget that is only ever drawn calm has
## never been checked in the state it was built for.
##
## Drawn at 1:1 on a 640x360 sheet, like the real thing. No zoom, no
## scaling -- UI_STYLE section 2 forbids an interface element at any
## scale but 1.0, and a gallery that broke that rule to show the rule
## would be worth nothing.

const SHEET: Vector2i = Vector2i(640, 360)
const MARGIN: float = 10.0
const LINE: float = 11.0

## Width of a specimen reading row.
const ROW_WIDTH: float = 120.0

var _ink: Palette = Palette.current()
var _alarm: bool = false
var _output_dir: String = ""


func _ready() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.size() > 0:
		_output_dir = arguments[0]
		DisplayServer.window_set_size(SHEET)
	RenderingServer.set_default_clear_color(_ink.scrim)
	if not _output_dir.is_empty():
		await _save()


func _draw() -> void:
	var font: Font = UiFont.face()
	if font == null:
		return
	var at: Vector2 = Vector2(MARGIN, MARGIN + float(UiFont.BODY))
	_title(font, at, "WIDGETS - %s" % ("ALARM" if _alarm else "NORMAL"))
	at.y += LINE * 2.0

	at.y = _rows(font, at)
	at.y += LINE
	at.y = _brackets(font, at)
	at.y += LINE
	_panels(font, at)
	_pulse(font, Vector2(MARGIN + 330.0, MARGIN + LINE * 3.0))


## Primitive 1: the reading row. Eighty per cent of the interface, and
## it is meant to be boring.
func _rows(font: Font, at: Vector2) -> float:
	_title(font, at, "1  ROW")
	var y: float = at.y + LINE
	var specimens: Array = [
		["ALT", "  1420", "px", _ink.value],
		["V/S", "  -3.4", "", _ink.ok],
		["FUEL", "    18", "%", _ink.caution],
		["HEAT", "  0.92", "", _ink.alarm],
		["GEAR", "    --", "", _ink.inert],
	]
	for entry: Array in specimens:
		var ink: Color = entry[3]
		# In the alarm sheet every row that can carry a state carries
		# the worst one, which is the only way to see whether five
		# alarms at once are readable or are a wall of red.
		if _alarm and ink != _ink.inert:
			ink = _ink.alarm
		UiDraw.row(
			self, font, Vector2(at.x, y), ROW_WIDTH,
			entry[0], entry[1], ink, _ink.label, entry[2],
		)
		y += LINE
	return y


## Primitive 5: the bracket. Three sizes, because the arm is fixed and a
## small bracket is nearly a box while a large one is four ticks.
func _brackets(font: Font, at: Vector2) -> float:
	_title(font, at, "5  BRACKET")
	var y: float = at.y + LINE
	var ink: Color = _ink.alarm if _alarm else _ink.nav
	var x: float = at.x
	for size: float in [12.0, 22.0, 40.0]:
		UiDraw.bracket(self, Rect2(Vector2(x, y), Vector2(size, size)), ink)
		x += size + 14.0
	return y + 44.0


## The panel, one per corner, so where the brackets land is visible
## rather than described. The last one is the edged exception: the
## flight instruments lie over terrain and get a full frame.
func _panels(font: Font, at: Vector2) -> void:
	_title(font, at, "PANEL  (corner brackets, and the one full edge)")
	var y: float = at.y + LINE
	# `grid` and not `edge`, which was the first choice and which the
	# first sheet out of this gallery threw out: a 4 px tick in `edge`
	# over a dark panel is invisible. `edge` is for a line that divides
	# one region from another and has a whole side to say it with; a
	# corner mark is fine structure, which is what `grid` is for.
	var ink: Color = _ink.alarm if _alarm else _ink.grid
	var fill: Color = _ink.over(_ink.panel, 0.86)
	var corners: Array = [
		[UiDraw.Corner.TOP_LEFT, "TL"],
		[UiDraw.Corner.TOP_RIGHT, "TR"],
		[UiDraw.Corner.BOTTOM_LEFT, "BL"],
		[UiDraw.Corner.BOTTOM_RIGHT, "BR"],
	]
	var x: float = at.x
	for entry: Array in corners:
		var box: Rect2 = Rect2(Vector2(x, y), Vector2(112.0, 62.0))
		UiDraw.panel(self, box, fill, ink, entry[0])
		draw_string(
			font, box.position + Vector2(UiDraw.PAD, UiDraw.PAD + float(UiFont.BODY)),
			entry[1], HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.BODY, _ink.label,
		)
		x += 122.0
	var edged: Rect2 = Rect2(Vector2(x, y), Vector2(112.0, 62.0))
	UiDraw.panel(self, edged, fill, ink, UiDraw.Corner.BOTTOM_RIGHT, true)
	draw_string(
		font, edged.position + Vector2(UiDraw.PAD, UiDraw.PAD + float(UiFont.BODY)),
		"EDGED", HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.BODY, _ink.label,
	)


## The alarm pulse, both halves of it in one still. A square wave cannot
## be photographed, so the gallery shows the two states side by side and
## labels which is which.
func _pulse(font: Font, at: Vector2) -> void:
	_title(font, at, "WARNING BAND  2 Hz, square, ground only")
	var y: float = at.y + LINE
	# Three states of the one band, because a square wave cannot be
	# photographed: amber steady, red lit, red between pulses. The rule
	# they are here to show is that the **ground** moves and the word
	# never does -- a word missing half the time is missing exactly when
	# it is wanted -- and that only red pulses at all, because if amber
	# flashed too the pulse would stop meaning "now".
	var states: Array = [
		["HEAT", _ink.caution, 0.42, "amber, steady"],
		["HULL", _ink.alarm, 0.42, "red, lit"],
		["HULL", _ink.alarm, 0.14, "red, between"],
	]
	var x: float = at.x
	for entry: Array in states:
		var ink: Color = entry[1]
		var says: String = entry[0]
		var width: float = UiDraw.text_width(font, says) + 8.0
		var box: Rect2 = Rect2(Vector2(x, y), Vector2(width, 11.0))
		draw_rect(box, Color(ink, float(entry[2])), true)
		UiDraw.bracket(self, box, ink)
		draw_string(
			font, box.position + Vector2(4.0, 8.0), says,
			HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.BODY, _ink.value,
		)
		draw_string(
			font, Vector2(x, y + 24.0), entry[3],
			HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.BODY, _ink.label,
		)
		x += maxf(width, UiDraw.text_width(font, entry[3])) + 12.0


func _title(font: Font, at: Vector2, text: String) -> void:
	draw_string(
		font, at.round(), text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.BODY, _ink.label
	)


## Both sheets, one run. The alarm pass is a redraw rather than a second
## scene, so the two pictures cannot drift apart.
func _save() -> void:
	DirAccess.make_dir_recursive_absolute(_output_dir)
	for alarm: bool in [false, true]:
		_alarm = alarm
		queue_redraw()
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var image: Image = get_viewport().get_texture().get_image()
		var name: String = "widgets_alarm.png" if alarm else "widgets.png"
		image.save_png("%s/%s" % [_output_dir, name])
		print("gallery: %s/%s" % [_output_dir, name])
	get_tree().quit()
