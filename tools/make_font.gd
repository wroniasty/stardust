extends SceneTree
## Rysuje pikselowy font 5x8 i zapisuje go jako FontFile. Uruchamianie:
##   godot --headless --path . --script res://tools/make_font.gd
##
## **A placeholder, and the last one the project needed.** UI_STYLE section 4
## already chose the real font -- Departure Mono (CC0), with Pixel Operator
## Mono as the fallback -- and neither is in the repository. This is what
## stands in until one of them is, so that everything round the font can be
## built and checked now: the theme, the three sizes, and every screen
## reading its face from one place instead of asking the OS for Consolas.
##
## Dropping the real font in replaces one resource. Nothing else moves.
##
## The box is five wide and eight tall, which is what an eight pixel line
## has room for. Rows are counted from the top:
##
##   row 0        accents -- the acute on o, the dot on z
##   rows 1..5    the letter itself, cap height five
##   rows 6..7    descenders and the ogonek on a and e
##
## Polish letters are **composed**, not drawn. An ogonek is a tail under a
## base letter and an acute is a mark above one, in Polish as much as in the
## bitmap, so there are nine marks plus eight base letters rather than
## eighteen more glyphs to keep in step with their plain versions.

const WIDTH: int = 5
const HEIGHT: int = 8

## One empty column between letters. Monospace, which UI_STYLE requires of
## anything with a number in it -- and in a HUD that is nearly everything.
const ADVANCE: int = WIDTH + 1

## Rows above the baseline. The baseline sits under row 5, so the two
## descender rows hang below it.
const ASCENT: int = 6
const DESCENT: int = HEIGHT - ASCENT

const COLUMNS: int = 16

const ATLAS: String = "res://assets/art/ui/font_5x8.png"
const FONT: String = "res://resources/ui/pixel_font.tres"

## The letter itself: five rows of five, landing on rows 1..5 of the box.
const BODY: Dictionary = {
	" ": ["     ", "     ", "     ", "     ", "     "],
	"!": ["  #  ", "  #  ", "  #  ", "     ", "  #  "],
	"\"": [" # # ", " # # ", "     ", "     ", "     "],
	"#": [" # # ", "#####", " # # ", "#####", " # # "],
	"$": [" ####", "##   ", " ### ", "   ##", "#### "],
	"%": ["##  #", "## # ", "  #  ", " # ##", "#  ##"],
	"&": [" ##  ", "#  # ", " ##  ", "#  # ", " ## #"],
	"'": ["  #  ", "  #  ", "     ", "     ", "     "],
	"(": ["   # ", "  #  ", "  #  ", "  #  ", "   # "],
	")": [" #   ", "  #  ", "  #  ", "  #  ", " #   "],
	"*": ["     ", "# # #", " ### ", "# # #", "     "],
	"+": ["     ", "  #  ", " ### ", "  #  ", "     "],
	",": ["     ", "     ", "     ", "     ", "  ## "],
	"-": ["     ", "     ", " ### ", "     ", "     "],
	".": ["     ", "     ", "     ", "     ", "  #  "],
	"/": ["    #", "   # ", "  #  ", " #   ", "#    "],
	"0": [" ### ", "#  ##", "# # #", "##  #", " ### "],
	"1": ["  #  ", " ##  ", "  #  ", "  #  ", " ### "],
	"2": [" ### ", "#   #", "  ## ", " #   ", "#####"],
	"3": ["#### ", "    #", " ### ", "    #", "#### "],
	"4": ["#  # ", "#  # ", "#####", "   # ", "   # "],
	"5": ["#####", "#    ", "#### ", "    #", "#### "],
	"6": [" ### ", "#    ", "#### ", "#   #", " ### "],
	"7": ["#####", "    #", "   # ", "  #  ", "  #  "],
	"8": [" ### ", "#   #", " ### ", "#   #", " ### "],
	"9": [" ### ", "#   #", " ####", "    #", " ### "],
	":": ["     ", "  #  ", "     ", "  #  ", "     "],
	";": ["     ", "  #  ", "     ", "  #  ", "  #  "],
	"<": ["   # ", "  #  ", " #   ", "  #  ", "   # "],
	"=": ["     ", " ### ", "     ", " ### ", "     "],
	">": [" #   ", "  #  ", "   # ", "  #  ", " #   "],
	"?": [" ### ", "#   #", "  ## ", "     ", "  #  "],
	"@": [" ### ", "#  ##", "# # #", "#    ", " ### "],
	"A": [" ### ", "#   #", "#####", "#   #", "#   #"],
	"B": ["#### ", "#   #", "#### ", "#   #", "#### "],
	"C": [" ####", "#    ", "#    ", "#    ", " ####"],
	"D": ["#### ", "#   #", "#   #", "#   #", "#### "],
	"E": ["#####", "#    ", "#### ", "#    ", "#####"],
	"F": ["#####", "#    ", "#### ", "#    ", "#    "],
	"G": [" ####", "#    ", "#  ##", "#   #", " ####"],
	"H": ["#   #", "#   #", "#####", "#   #", "#   #"],
	"I": [" ### ", "  #  ", "  #  ", "  #  ", " ### "],
	"J": ["  ###", "   # ", "   # ", "#  # ", " ##  "],
	"K": ["#   #", "#  # ", "###  ", "#  # ", "#   #"],
	"L": ["#    ", "#    ", "#    ", "#    ", "#####"],
	"M": ["#   #", "## ##", "# # #", "#   #", "#   #"],
	"N": ["#   #", "##  #", "# # #", "#  ##", "#   #"],
	"O": [" ### ", "#   #", "#   #", "#   #", " ### "],
	"P": ["#### ", "#   #", "#### ", "#    ", "#    "],
	"Q": [" ### ", "#   #", "#   #", "#  # ", " ## #"],
	"R": ["#### ", "#   #", "#### ", "#  # ", "#   #"],
	"S": [" ####", "#    ", " ### ", "    #", "#### "],
	"T": ["#####", "  #  ", "  #  ", "  #  ", "  #  "],
	"U": ["#   #", "#   #", "#   #", "#   #", " ### "],
	"V": ["#   #", "#   #", "#   #", " # # ", "  #  "],
	"W": ["#   #", "#   #", "# # #", "## ##", "#   #"],
	"X": ["#   #", " # # ", "  #  ", " # # ", "#   #"],
	"Y": ["#   #", " # # ", "  #  ", "  #  ", "  #  "],
	"Z": ["#####", "   # ", "  #  ", " #   ", "#####"],
	"[": ["  ## ", "  #  ", "  #  ", "  #  ", "  ## "],
	"\\": ["#    ", " #   ", "  #  ", "   # ", "    #"],
	"]": [" ##  ", "  #  ", "  #  ", "  #  ", " ##  "],
	"^": ["  #  ", " # # ", "     ", "     ", "     "],
	"_": ["     ", "     ", "     ", "     ", "#####"],
	"`": [" #   ", "  #  ", "     ", "     ", "     "],
	"a": ["     ", " ### ", "   # ", " ####", " ####"],
	"b": ["#    ", "#### ", "#   #", "#   #", "#### "],
	"c": ["     ", " ### ", "#    ", "#    ", " ### "],
	"d": ["    #", " ####", "#   #", "#   #", " ####"],
	"e": ["     ", " ### ", "#   #", "#### ", " ### "],
	"f": ["  ## ", "  #  ", " ### ", "  #  ", "  #  "],
	"g": ["     ", " ####", "#   #", "#   #", " ####"],
	"h": ["#    ", "#### ", "#   #", "#   #", "#   #"],
	"i": ["  #  ", "     ", " ##  ", "  #  ", " ### "],
	"j": ["   # ", "     ", "  ## ", "   # ", "   # "],
	"k": ["#    ", "#  # ", "# #  ", "##   ", "#  # "],
	"l": [" ##  ", "  #  ", "  #  ", "  #  ", " ### "],
	"m": ["     ", "## # ", "# # #", "# # #", "# # #"],
	"n": ["     ", "#### ", "#   #", "#   #", "#   #"],
	"o": ["     ", " ### ", "#   #", "#   #", " ### "],
	"p": ["     ", "#### ", "#   #", "#   #", "#### "],
	"q": ["     ", " ####", "#   #", "#   #", " ####"],
	"r": ["     ", "# ## ", "##   ", "#    ", "#    "],
	"s": ["     ", " ####", "##   ", "   ##", "#### "],
	"t": ["  #  ", " ### ", "  #  ", "  #  ", "   ##"],
	"u": ["     ", "#   #", "#   #", "#   #", " ####"],
	"v": ["     ", "#   #", "#   #", " # # ", "  #  "],
	"w": ["     ", "# # #", "# # #", "# # #", " # # "],
	"x": ["     ", "#   #", " ### ", " ### ", "#   #"],
	"y": ["     ", "#   #", "#   #", "#   #", " ####"],
	"z": ["     ", "#####", "  ## ", " #   ", "#####"],
	"{": ["   ##", "  #  ", " ##  ", "  #  ", "   ##"],
	"|": ["  #  ", "  #  ", "  #  ", "  #  ", "  #  "],
	"}": ["##   ", "  #  ", "  ## ", "  #  ", "##   "],
	"~": ["     ", " ##  ", "#  ##", "     ", "     "],
	# Not ASCII, but the only character outside it the interface uses:
	# eleven strings in the game are built round an em dash. Counted
	# rather than assumed -- every other non-ASCII character in a user
	# facing string turned out to be Polish, which is composed below.
	"—": ["     ", "     ", "#####", "     ", "     "],
	"–": ["     ", "     ", " ####", "     ", "     "],
}

## What hangs below the baseline, on rows 6 and 7.
const UNDER: Dictionary = {
	",": ["  #  ", "     "],
	";": ["  #  ", "     "],
	"g": ["    #", " ### "],
	"j": ["#  # ", " ##  "],
	"p": ["#    ", "#    "],
	"q": ["    #", "    #"],
	"y": ["    #", " ### "],
}

## Polish, as a base letter and a mark rather than as eighteen more glyphs.
##
## `acute` goes on row 0 over the middle, `dot` likewise; `ogonek` is a tail
## on rows 6 and 7 under the right-hand side. `stroke` is the bar through an
## l, and is the one that has to know where the stem is, so it carries the
## row it draws into.
const ACCENTS: Dictionary = {
	"acute": {"row": 0, "art": "   # "},
	"dot": {"row": 0, "art": "  #  "},
}

const OGONEK: Array[String] = ["   # ", "  ## "]

## base letter, mark, and for the slashed l which row the bar crosses.
const POLISH: Dictionary = {
	"ą": {"base": "a", "ogonek": true},
	"ć": {"base": "c", "mark": "acute"},
	"ę": {"base": "e", "ogonek": true},
	"ł": {"base": "l", "stroke": 3},
	"ń": {"base": "n", "mark": "acute"},
	"ó": {"base": "o", "mark": "acute"},
	"ś": {"base": "s", "mark": "acute"},
	"ź": {"base": "z", "mark": "acute"},
	"ż": {"base": "z", "mark": "dot"},
	"Ą": {"base": "A", "ogonek": true},
	"Ć": {"base": "C", "mark": "acute"},
	"Ę": {"base": "E", "ogonek": true},
	"Ł": {"base": "L", "stroke": 3},
	"Ń": {"base": "N", "mark": "acute"},
	"Ó": {"base": "O", "mark": "acute"},
	"Ś": {"base": "S", "mark": "acute"},
	"Ź": {"base": "Z", "mark": "acute"},
	"Ż": {"base": "Z", "mark": "dot"},
}

var _cells: Dictionary = {} ## character -> Rect2i in the atlas


func _initialize() -> void:
	var glyphs: Array[String] = _alphabet()
	var image: Image = _draw_atlas(glyphs)
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(ATLAS.get_base_dir())
	)
	var error: int = image.save_png(ProjectSettings.globalize_path(ATLAS))
	if error != OK:
		push_error("could not write the atlas (%d)" % error)
		quit(1)
		return
	print("font: %d glyphs, atlas %dx%d" % [glyphs.size(), image.get_width(), image.get_height()])

	# The resource has to point at an imported texture, so it cannot be
	# written in the same pass that draws one. Same two-step as the
	# placeholder sprites, and for the same reason.
	if not ResourceLoader.exists(ATLAS, "Texture2D"):
		print("font: run `--import`, then run this again to write the resource")
		quit(0)
		return
	_write_font(glyphs, image)
	quit(0)


## Every character the font covers, in code point order.
func _alphabet() -> Array[String]:
	var out: Array[String] = []
	for key: Variant in BODY:
		out.append(String(key))
	for key: Variant in POLISH:
		out.append(String(key))
	out.sort()
	return out


func _draw_atlas(glyphs: Array[String]) -> Image:
	var rows: int = int(ceil(float(glyphs.size()) / float(COLUMNS)))
	var image: Image = Image.create_empty(
		COLUMNS * WIDTH, rows * HEIGHT, false, Image.FORMAT_RGBA8
	)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	_cells.clear()
	for i: int in range(glyphs.size()):
		var at: Vector2i = Vector2i((i % COLUMNS) * WIDTH, (i / COLUMNS) * HEIGHT)
		_cells[glyphs[i]] = Rect2i(at, Vector2i(WIDTH, HEIGHT))
		_stamp(image, at, _rows_for(glyphs[i]))
	return image


## The eight rows of one character, accents and descenders folded in.
func _rows_for(glyph: String) -> PackedStringArray:
	var recipe: Dictionary = POLISH.get(glyph, {})
	var base: String = String(recipe.get("base", glyph))
	var rows: PackedStringArray = PackedStringArray(["     "])
	for line: Variant in BODY.get(base, BODY[" "]):
		rows.append(String(line))
	for line: Variant in UNDER.get(base, ["     ", "     "]):
		rows.append(String(line))

	if recipe.has("mark"):
		var mark: Dictionary = ACCENTS[recipe["mark"]]
		rows[int(mark["row"])] = String(mark["art"])
	if recipe.get("ogonek", false):
		rows[6] = OGONEK[0]
		rows[7] = OGONEK[1]
	if recipe.has("stroke"):
		# Drawn across whatever the stem is, rather than at a fixed column:
		# the bar on an l and the bar on an L start in different places.
		rows[int(recipe["stroke"])] = _barred(rows[int(recipe["stroke"])])
	return rows


## One row with a bar drawn through its stem.
func _barred(row: String) -> String:
	var stem: int = row.find("#")
	if stem < 0:
		return row
	var out: String = row
	for x: int in range(maxi(stem - 1, 0), mini(stem + 2, WIDTH)):
		out[x] = "#"
	return out


func _stamp(image: Image, at: Vector2i, rows: PackedStringArray) -> void:
	for y: int in range(mini(rows.size(), HEIGHT)):
		var row: String = rows[y]
		for x: int in range(mini(row.length(), WIDTH)):
			if row[x] == "#":
				image.set_pixel(at.x + x, at.y + y, Color(1.0, 1.0, 1.0, 1.0))


## Builds the FontFile around the imported atlas.
##
## The asymmetry in this API is worth naming because it is exactly the kind
## of thing that is wrong when guessed: the glyph setters take the size as a
## `Vector2i`, the cache setters and `set_glyph_advance` take it as an
## `int`. Checked against the 4.7 docs rather than tried until it stopped
## erroring.
##
## Glyph indices are character codes here. A FontFile with no face data
## behind it has no table to look them up in, so the code point is the index
## -- which is what Godot's own image-font importer does.
func _write_font(glyphs: Array[String], image: Image) -> void:
	var font: FontFile = FontFile.new()
	font.fixed_size = HEIGHT
	# Whole numbers only, which is the grid law enforced by the font itself
	# rather than by everyone remembering it. Without this a bitmap font
	# simply ignores the size it is asked for, and the 16 px heading came
	# out the same size as the 8 px body -- which is how this was found.
	font.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_INTEGER_ONLY
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	font.hinting = TextServer.HINTING_NONE
	font.multichannel_signed_distance_field = false
	# No falling back to whatever the machine happens to have: a glyph this
	# font does not own must look missing, not look like Arial.
	font.allow_system_fallback = false
	font.font_name = "Stardust Placeholder"

	var size: Vector2i = Vector2i(HEIGHT, 0)
	font.set_cache_ascent(0, HEIGHT, float(ASCENT))
	font.set_cache_descent(0, HEIGHT, float(DESCENT))
	font.set_cache_scale(0, HEIGHT, 1.0)
	font.set_texture_image(0, size, 0, image)

	for glyph: String in glyphs:
		var code: int = glyph.unicode_at(0)
		var cell: Rect2i = _cells[glyph]
		font.set_glyph_texture_idx(0, size, code, 0)
		font.set_glyph_uv_rect(0, size, code, Rect2(cell))
		font.set_glyph_size(0, size, code, Vector2(WIDTH, HEIGHT))
		font.set_glyph_offset(0, size, code, Vector2(0.0, -float(ASCENT)))
		font.set_glyph_advance(0, HEIGHT, code, Vector2(float(ADVANCE), 0.0))

	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(FONT.get_base_dir())
	)
	var error: int = ResourceSaver.save(font, FONT)
	if error != OK:
		push_error("could not write the font (%d)" % error)
		return
	print("font: wrote %s" % FONT)
