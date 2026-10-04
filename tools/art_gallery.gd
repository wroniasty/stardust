extends Node2D
## Wszystkie paski obok siebie, z zaznaczonym punktem zaczepienia.
##
##     godot --path . tools/art_gallery.tscn
##     godot --path . tools/art_gallery.tscn -- <katalog na PNG>
##
## Why this exists, and it is one reason rather than several: **a pivot two
## texels out does not look like a wrong pivot.** It looks like the nozzle is
## bolted on crooked, or the gun is floating, or the leg is sunk into the
## hull -- which reads as a bug in the physics, and gets debugged there. The
## only way to see that the pivot is the problem is to draw it.
##
## So every sprite is shown at the size it will be in the world, with a cross
## on its origin and a box round its frame, and the animated ones run. If a
## strip looks right here and wrong on the ship, the fault is in the skin; if
## it looks wrong here, the fault is in the file.
##
## The second pass of the shot is also the cheap way to review new art: one
## command, one picture, every part the game owns.

## Tables in the order a reader wants them: the ship first, then what it
## throws, then the interface.
const TABLES: Array[String] = [
	"res://resources/fx/looks/hull.tres",
	"res://resources/fx/looks/engine_nozzle.tres",
	"res://resources/fx/looks/engine_plume.tres",
	"res://resources/fx/looks/weapon_muzzle.tres",
	"res://resources/fx/looks/module_box.tres",
	"res://resources/fx/looks/gear_leg.tres",
	"res://resources/fx/looks/round.tres",
	"res://resources/fx/looks/particle.tres",
	"res://resources/fx/looks/module_icon.tres",
]

## The grid, in design pixels. Wide enough for the long lance, which is the
## tallest thing in the catalogue at fifty.
const CELL: Vector2 = Vector2(58.0, 58.0)
const COLUMNS: int = 10
const MARGIN: Vector2 = Vector2(30.0, 34.0)

## How the pivot is marked, and how big the mark is.
## Dark, because most of the art is light and all of it is shown against
## space in the game. On a default grey background a pale hull is invisible
## and a bright flame looks washed out -- the gallery would be lying about
## both.
const BACKDROP: Color = Color(0.07, 0.08, 0.11)

## How big a window to open when the gallery is being saved rather than
## looked at. Forty-one sprites at a readable size do not fit in 1280x720,
## and a sheet nobody can read is a sheet nobody checks.
const SHEET: Vector2i = Vector2i(1500, 1100)

const PIVOT_COLOUR: Color = Color(1.0, 0.25, 0.35)
const FRAME_COLOUR: Color = Color(0.35, 0.40, 0.52)
const LABEL_COLOUR: Color = Color(0.62, 0.68, 0.80)
const CROSS: float = 3.0

## Everything animated runs at full, because the point here is to see every
## frame rather than to see an idling engine.
const DRIVE: float = 1.0

## The font, shown on the kind of text the game actually sets: a column of
## readings, a rolled item name, and a sentence in Polish with every
## accented letter in it.
##
## Here rather than in a tool of its own, because this is the place you
## come to look at what the game is made of, and a typeface is one of the
## things it is made of. The pangram is the test that matters: a font whose
## alphabet looks fine can still fall apart the moment an ogonek meets a
## descender.
const SPECIMEN: Array[String] = [
	"ABCDEFGHIJKLMNOPQRSTUVWXYZ  0123456789",
	"abcdefghijklmnopqrstuvwxyz  !?,.:;-+/()[]",
	"ĄĆĘŁŃÓŚŹŻ  ągćzęłńóśźż  — zażółć gęślą jaźń",
	"PERI  -1107   APO  1400   ALT  1414   V/S  +0.0",
	"efficient wide precise rapid dumb rocket",
	"DOCKED - fitting available.  Refused: too fast",
]

var _shown: Array[Dictionary] = []
var _output_dir: String = ""

## Everything the gallery covers, for the backdrop and the camera.
var _frame: Rect2 = Rect2()

@onready var _camera: Camera2D = $Camera


func _ready() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.size() > 0:
		_output_dir = arguments[0]
		DisplayServer.window_set_size(SHEET)
	_build()
	_frame_everything()
	if not _output_dir.is_empty():
		_save()


## One cell per strip, laid out in reading order.
##
## Each table's strips are taken once, by identity: a look table hands the
## same strip out under several keys -- the nozzle fallback is the thruster,
## the plume fallback is the spark -- and showing it twice would say there
## are more pictures than there are.
func _build() -> void:
	var seen: Array[SpriteStrip] = []
	var column: int = 0
	var row: int = 0
	for path: String in TABLES:
		var table: LookTable = load(path) as LookTable
		if table == null:
			continue
		if column > 0:
			column = 0
			row += 1
		for strip: SpriteStrip in table.every_strip():
			if strip == null or not strip.is_valid() or seen.has(strip):
				continue
			seen.append(strip)
			var at: Vector2 = MARGIN + Vector2(float(column), float(row)) * CELL
			var sprite: StripSprite = StripSprite.new()
			add_child(sprite)
			sprite.show_strip(strip)
			sprite.position = at
			sprite.z_index = 1
			_shown.append({
				"sprite": sprite,
				"at": at,
				"strip": strip,
				"name": _name_of(strip),
			})
			column += 1
			if column >= COLUMNS:
				column = 0
				row += 1
	queue_redraw()


func _name_of(strip: SpriteStrip) -> String:
	if strip.texture == null:
		return "?"
	return strip.texture.resource_path.get_file().get_basename()


## Fits the camera round whatever got laid out, so adding art does not mean
## re-aiming the camera by hand.
func _frame_everything() -> void:
	if _shown.is_empty():
		return
	# Over what is actually drawn, not over the cell centres. A sprite hangs
	# off its pivot, so a tall one reaches well above the point it was placed
	# at -- framing on the centres cut the top row off the first sheet.
	var box: Rect2 = Rect2(_shown[0]["at"], Vector2.ZERO)
	for entry: Dictionary in _shown:
		box = box.expand(_corner_of(entry))
		box = box.expand(_corner_of(entry) + (entry["strip"] as SpriteStrip).design_size())
		box = box.expand(Vector2(entry["at"]) + CELL * 0.5)
		box = box.expand(Vector2(entry["at"]) - CELL * 0.5)
	_frame = box.grow(8.0)
	# Room under the sprites for the type specimen.
	_frame.size.y += float(SPECIMEN.size()) * float(UiFont.BODY + 3) + float(
		UiFont.HEADLINE
	) + 16.0
	_camera.position = _frame.get_center()
	var view: Vector2 = get_viewport().get_visible_rect().size
	_camera.zoom = Vector2.ONE * minf(
		view.x / _frame.size.x, view.y / _frame.size.y
	)


func _process(delta: float) -> void:
	for entry: Dictionary in _shown:
		var sprite: StripSprite = entry["sprite"]
		sprite.drive(DRIVE)
		sprite.advance(delta)


## Where a strip's own frame starts: the pivot sits at the cell point, so
## the frame begins a pivot's worth up and to the left of it.
func _corner_of(entry: Dictionary) -> Vector2:
	var strip: SpriteStrip = entry["strip"]
	var scale: float = Art.WORLD_SCALE if strip.in_world else 1.0
	return Vector2(entry["at"]) - strip.pivot * scale


func _draw() -> void:
	draw_rect(_frame, BACKDROP, true)
	var font: Font = UiFont.face()
	_draw_specimen(font)
	for entry: Dictionary in _shown:
		var at: Vector2 = entry["at"]
		var strip: SpriteStrip = entry["strip"]
		var size: Vector2 = strip.design_size()
		var corner: Vector2 = _corner_of(entry)
		draw_rect(Rect2(corner, size), FRAME_COLOUR, false, 0.5)
		# And the origin itself, which is the thing worth looking at.
		draw_line(at - Vector2(CROSS, 0.0), at + Vector2(CROSS, 0.0), PIVOT_COLOUR, 0.5)
		draw_line(at - Vector2(0.0, CROSS), at + Vector2(0.0, CROSS), PIVOT_COLOUR, 0.5)
		draw_string(
			font, at + Vector2(-CELL.x * 0.5 + 2.0, CELL.y * 0.5 - 4.0),
			"%s  %dx%d%s" % [
				entry["name"], int(size.x), int(size.y),
				"" if strip.frames <= 1 else "  x%d" % strip.frames,
			],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 5, LABEL_COLOUR
		)


## The font, under everything else.
func _draw_specimen(font: Font) -> void:
	var at: Vector2 = Vector2(_frame.position.x + 10.0, _frame.end.y - 4.0)
	at.y -= float(SPECIMEN.size()) * float(UiFont.BODY + 3) + float(UiFont.HEADLINE) + 10.0
	draw_string(
		font, at, "STARDUST", HORIZONTAL_ALIGNMENT_LEFT, -1,
		UiFont.HEADLINE, LABEL_COLOUR
	)
	at.y += float(UiFont.HEADLINE) + 6.0
	for line: String in SPECIMEN:
		draw_string(
			font, at, line, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.BODY, LABEL_COLOUR
		)
		at.y += float(UiFont.BODY + 3)


func _save() -> void:
	DirAccess.make_dir_recursive_absolute(_output_dir)
	# Two frames: one for the camera to take effect, one to draw with it.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png("%s/gallery.png" % _output_dir)
	print("gallery: %d sprites -> %s/gallery.png" % [_shown.size(), _output_dir])
	get_tree().quit()
