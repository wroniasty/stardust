extends SceneTree
## Rysuje komplet placeholderów i zapisuje do nich zasoby. Uruchamianie:
##   godot --headless --path . --script res://tools/make_placeholders.gd
##   godot --headless --path . --import
##   godot --headless --path . --script res://tools/make_placeholders.gd
##
## Twice, on purpose. The first pass writes PNGs, the import turns them into
## textures, and the second pass writes the `.tres` files that point at them.
## A resource cannot reference a texture that has not been imported yet, and
## pretending otherwise produces a `.tres` full of nulls that loads without
## complaining.
##
## **Why the placeholders are generated rather than drawn.** Every one of them
## is throwaway: the point is to have the right number of files, at the right
## sizes, with the right pivots, so the migration onto sprites can be written
## and tested before a single real pixel exists. Generating them means the
## sizes come from the same catalogues the game uses -- a hull placeholder is
## literally its own collision outline filled in, so it cannot be the wrong
## shape -- and means regenerating after the hull list changes is one command.
##
## When real art arrives it replaces the PNGs file for file. Nothing else
## changes: the resources, the pivots and the code all stay.

## The placeholder palette. Separate constants rather than a dictionary, so
## every colour arrives at a drawing routine already typed: a Variant out of a
## dictionary is an unsafe argument on every call, and there are a hundred of
## them below.
const PLATE: Color = Color(0.42, 0.46, 0.55) ## hull body
const SPINE: Color = Color(0.61, 0.66, 0.74) ## lit keel down the middle
const DECK: Color = Color(0.27, 0.30, 0.37) ## engine deck at the stern
const EDGE: Color = Color(0.11, 0.12, 0.16) ## one-texel border on everything
const GLASS: Color = Color(0.35, 0.62, 1.00) ## cockpit, lenses, screens
const METAL: Color = Color(0.54, 0.58, 0.65) ## bolted-on parts
const SHADOW: Color = Color(0.23, 0.25, 0.32) ## their undersides
const HOT: Color = Color(1.00, 0.95, 0.82) ## flame core
const FLAME: Color = Color(1.00, 0.72, 0.42)
const EMBER: Color = Color(1.00, 0.44, 0.16)
const PAPER: Color = Color(1.00, 1.00, 1.00, 1.00) ## icons, before modulate

## Crates and rounds are painted in greys, because what colours them is a
## fact the game already holds: a crate is painted by what is inside it and
## a round by the gun that fired it. A hue baked into the file would be a
## second opinion about both.
const SHELL: Color = Color(0.92, 0.94, 0.97)
const SHELL_DARK: Color = Color(0.45, 0.47, 0.52)

## Texels of empty space round every sprite. The rule and the reason for it
## live on Art, because the skin has to know it too.
const MARGIN: int = Art.MARGIN

## Short, file-safe names for the hulls the game already has, keyed by the
## display name the catalogues use.
##
## A map rather than a field on the catalogues, because the catalogues are
## what is being migrated: adding an `id` to CreativeTool.SHAPES now would be
## editing the copy that is on its way out.
const HULL_IDS: Dictionary = {
	"dart (stock)": &"dart",
	"wide delta": &"wide_delta",
	"long lance": &"long_lance",
	"hexagon": &"hexagon",
	"brick": &"brick",
	"sliver (bad)": &"sliver",
	"gimbal podwójny (para sił)": &"rhombus",
	"gimbal pojedynczy (dryfuje)": &"broad_dart",
	"przechwytujący": &"interceptor",
	"frachtowiec": &"freighter",
}

## Icons are laid out as text because at eleven pixels across that is the only
## honest way to say what they look like. '#' is opaque white, anything else
## is nothing, and colour arrives through `modulate` as ASSETLIST.md requires.
const ICONS: Dictionary = {
	"engine": [
		"..#######..",
		"..#.....#..",
		"..#.....#..",
		".#.......#.",
		".#.......#.",
		"#.........#",
		"#.........#",
		"###########",
		"...#...#...",
		"....#.#....",
		".....#.....",
	],
	"weapon": [
		".....#.....",
		".....#.....",
		"....###....",
		"....###....",
		"....###....",
		"....###....",
		"...#####...",
		"..#######..",
		"..#######..",
		"..#.....#..",
		"..#######..",
	],
	"generator": [
		".#########.",
		".#.......#.",
		".#...##..#.",
		".#..##...#.",
		".#.####..#.",
		".#...##..#.",
		".#..##...#.",
		".#.##....#.",
		".#.......#.",
		".#########.",
		"...##.##...",
	],
	"computer": [
		"..#.#.#.#..",
		".#########.",
		".#.......#.",
		"##.#####.##",
		".#.#...#.#.",
		"##.#...#.##",
		".#.#####.#.",
		"##.......##",
		".#########.",
		"..#.#.#.#..",
		"...........",
	],
	"gear": [
		".....#.....",
		".....#.....",
		".....#.....",
		"....#.#....",
		"....#.#....",
		"...#...#...",
		"...#...#...",
		"..#.....#..",
		"..#.....#..",
		".#########.",
		".#########.",
	],
	"mod": [
		"...#...#...",
		"...#...#...",
		".#########.",
		".#########.",
		".#.......#.",
		".#.......#.",
		".#.......#.",
		"..#######..",
		"...#####...",
		"....###....",
		".....#.....",
	],
	"empty": [
		".##.###.##.",
		".#.......#.",
		"...........",
		"#.........#",
		"#.........#",
		"...........",
		"#.........#",
		"#.........#",
		"...........",
		".#.......#.",
		".##.###.##.",
	],
	"rarity_frame": [
		"###.......###",
		"#...........#",
		"#...........#",
		".............",
		".............",
		".............",
		".............",
		".............",
		".............",
		".............",
		"#...........#",
		"#...........#",
		"###.......###",
	],
}

var _written: int = 0
var _missing: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	_make_dirs()

	var hulls: Array[Dictionary] = _hull_catalogue()
	for hull: Dictionary in hulls:
		_draw_hull(hull)
	_draw_nozzles()
	_draw_plumes()
	_draw_guns()
	_draw_boxes()
	_draw_gear()
	_draw_rounds()
	_draw_particles()
	_draw_icons()
	print("placeholders: %d images written" % _written)

	# Second pass, and only if the first one's output has been imported.
	if not _textures_ready():
		print("placeholders: run `--import`, then run this again to write the resources")
		quit(0)
		return
	_write_hull_resources(hulls)
	_write_look_tables()
	if _missing.is_empty():
		print("placeholders: resources written")
	else:
		# Named rather than counted: a resource that quietly lost one
		# texture loads without complaining and draws nothing.
		push_error("placeholders: %d textures did not load" % _missing.size())
		for path: String in _missing:
			print("  missing %s" % path)
	quit(0)


## Every distinct hull the game knows, from the two catalogues that hold them.
##
## Read rather than restated. The sprite for a hull is its own outline filled
## in, so a placeholder cannot be the wrong shape for the ship it is on, and
## when the hull list changes the pictures change with it.
func _hull_catalogue() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen: Array[PackedVector2Array] = []

	for shape: Dictionary in CreativeTool.SHAPES:
		var outline: PackedVector2Array = PackedVector2Array(shape["outline"])
		seen.append(outline)
		out.append({
			"id": HULL_IDS.get(shape["name"], StringName(shape["name"])),
			"name": String(shape["name"]),
			"outline": outline,
			"legs": [] as Array[Vector2],
		})

	# Presets carry hulls the reshape menu does not offer, and legs the
	# reshape menu has no opinion about. Matched by outline, not by name:
	# three presets fly the stock dart under three different names.
	for preset: Dictionary in ShipFitout.all():
		var outline: PackedVector2Array = PackedVector2Array(preset["hull"])
		if _has_outline(seen, outline):
			continue
		seen.append(outline)
		var legs: Array[Vector2] = []
		for leg: Variant in preset.get("legs", []):
			legs.append(leg as Vector2)
		out.append({
			"id": HULL_IDS.get(preset["name"], StringName(preset["name"])),
			"name": String(preset["name"]),
			"outline": outline,
			"legs": legs,
		})
	return out


func _has_outline(seen: Array[PackedVector2Array], outline: PackedVector2Array) -> bool:
	for known: PackedVector2Array in seen:
		if known == outline:
			return true
	return false


# --- drawing ----------------------------------------------------------------


## A hull: its own collision outline, filled, with a lit keel, a dark stern
## deck and a cockpit. Nothing a real sprite would keep, and every dimension
## one a real sprite has to match.
func _draw_hull(hull: Dictionary) -> void:
	var outline: PackedVector2Array = hull["outline"]
	var box: Rect2 = _bounds(outline)
	var width: int = int(ceilf(box.size.x * Art.FACTOR)) + MARGIN * 2
	var height: int = int(ceilf(box.size.y * Art.FACTOR)) + MARGIN * 2
	var pivot: Vector2 = Vector2(
		-box.position.x * Art.FACTOR + MARGIN, -box.position.y * Art.FACTOR + MARGIN
	)

	var scaled: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in outline:
		scaled.append(point * Art.FACTOR + pivot)

	var image: Image = _blank(width, height)
	_fill_polygon(image, scaled, PLATE)

	# A keel down the middle, so a rotating silhouette has something that
	# shows which way it is turning. A flat fill does not.
	var keel: int = maxi(1, int(round(float(width) * 0.09)))
	for y: int in range(height):
		for x: int in range(int(pivot.x) - keel, int(pivot.x) + keel + 1):
			if _inside(image, x, y) and _opaque(image, x, y):
				image.set_pixel(x, y, SPINE)

	var deck: int = height - MARGIN - maxi(2, int(round(float(height - MARGIN * 2) * 0.14)))
	for y: int in range(deck, height):
		for x: int in range(width):
			if _opaque(image, x, y):
				image.set_pixel(x, y, DECK)

	var glass: int = maxi(2, int(round(float(mini(width, height)) * 0.11)))
	_disc(
		image,
		Vector2(pivot.x, float(MARGIN) + float(height - MARGIN * 2) * 0.28),
		float(glass),
		GLASS,
		true,
	)
	_border(image, EDGE)
	_save(image, "%s/hulls/%s.png" % [Art.WORLD_DIR, hull["id"]])


## Three nozzles by engine type, plus the one an affix brings.
##
## The mount point is at the top of the frame and the bell opens downward,
## because EngineMount.thrust_direction is the direction of the **force** --
## the exhaust goes the other way, and a nozzle drawn the way the force points
## is a nozzle bolted on backwards.
func _draw_nozzles() -> void:
	_save(_bell(8.0, 7.0, false), "%s/nozzles/main.png" % Art.WORLD_DIR)
	_save(_bell(8.0, 7.0, true), "%s/nozzles/gimbal.png" % Art.WORLD_DIR)
	_save(_bell(4.0, 4.0, false), "%s/nozzles/torque.png" % Art.WORLD_DIR)
	_save(_bell(6.0, 3.5, false), "%s/nozzles/thruster.png" % Art.WORLD_DIR)


## One bell, `mouth` design pixels across and `length` long, with the throat
## at the top. `jointed` adds the ball the gimbal swings on.
func _bell(mouth: float, length: float, jointed: bool) -> Image:
	var width: int = int(ceilf(mouth * Art.FACTOR)) + MARGIN * 2
	var height: int = int(ceilf(length * Art.FACTOR)) + MARGIN * 2
	var image: Image = _blank(width, height)
	var centre: float = float(width) * 0.5
	var throat: float = mouth * 0.35 * Art.FACTOR * 0.5
	var lip: float = mouth * Art.FACTOR * 0.5
	var top: float = float(MARGIN)
	var bottom: float = float(height - MARGIN)
	_fill_polygon(image, PackedVector2Array([
		Vector2(centre - throat, top), Vector2(centre + throat, top),
		Vector2(centre + lip, bottom), Vector2(centre - lip, bottom),
	]), METAL)
	# The mouth, so a nozzle pointing at the camera is not a solid blob.
	_fill_polygon(image, PackedVector2Array([
		Vector2(centre - lip + 2.0, bottom - 2.0), Vector2(centre + lip - 2.0, bottom - 2.0),
		Vector2(centre + lip - 2.0, bottom), Vector2(centre - lip + 2.0, bottom),
	]), SHADOW)
	if jointed:
		_disc(image, Vector2(centre, top + 1.0), float(Art.FACTOR), SHADOW, false)
	_border(image, EDGE)
	return image


## Three plumes, chosen by how much thrust the engine makes, each a strip of
## six frames. Additive, so they add light rather than paint over it.
func _draw_plumes() -> void:
	_save(_plume(5.0, 9.0), "%s/plumes/spark_strip6.png" % Art.WORLD_DIR)
	_save(_plume(7.0, 14.0), "%s/plumes/cone_strip6.png" % Art.WORLD_DIR)
	_save(_plume(9.0, 20.0), "%s/plumes/flame_strip6.png" % Art.WORLD_DIR)


const PLUME_FRAMES: int = 6


## A flame `across` design pixels wide and `long` long, as six frames side by
## side. The frames differ only in a per-row wobble, which is the whole trick:
## a flame reads as a flame because its edge moves, not because its shape is
## interesting.
func _plume(across: float, long: float) -> Image:
	var frame_width: int = int(ceilf(across * Art.FACTOR)) + MARGIN * 2
	var height: int = int(ceilf(long * Art.FACTOR)) + MARGIN
	var image: Image = _blank(frame_width * PLUME_FRAMES, height)
	var half: float = across * Art.FACTOR * 0.5
	var body: float = float(height - MARGIN)

	for frame: int in range(PLUME_FRAMES):
		var origin: int = frame * frame_width
		var centre: float = float(origin) + float(frame_width) * 0.5
		for y: int in range(height):
			var along: float = clampf(float(y) / maxf(body, 1.0), 0.0, 1.0)
			# Fat at the throat, tapering to nothing: 1.6 rather than 1 so
			# the taper starts slowly and then gives way, which is what a
			# nozzle actually throws.
			var wobble: float = 1.0 + 0.18 * sin(
				float(frame) * 1.7 + float(y) * 0.45
			)
			var reach: float = half * (1.0 - pow(along, 1.6)) * wobble
			var shade: Color = _flame_colour(along)
			for x: int in range(origin, origin + frame_width):
				if absf(float(x) + 0.5 - centre) <= reach:
					image.set_pixel(x, y, shade)
	return image


## White at the throat through orange to a dark fading tip.
##
## The white core is an eighth of the length, not half. Length is not area:
## the root is the widest part, so at half the flame came out cream all
## over and read as steam. A flame is orange with a white root, and the
## root is short.
const FLAME_CORE: float = 0.12


func _flame_colour(along: float) -> Color:
	var shade: Color = (
		HOT.lerp(FLAME, along / FLAME_CORE) if along < FLAME_CORE
		else FLAME.lerp(EMBER, (along - FLAME_CORE) / (1.0 - FLAME_CORE))
	)
	shade.a = 1.0 - along * 0.8
	return shade


## One gun per WeaponData.Type, in that order, so the look table can index by
## the enum instead of by a name that has to be kept in step with it.
func _draw_guns() -> void:
	_save(_gun("projectile"), "%s/guns/projectile.png" % Art.WORLD_DIR)
	_save(_gun("laser"), "%s/guns/laser.png" % Art.WORLD_DIR)
	_save(_gun("dumb_missile"), "%s/guns/dumb_missile.png" % Art.WORLD_DIR)
	_save(_gun("homing_missile"), "%s/guns/homing_missile.png" % Art.WORLD_DIR)
	_save(_gun("aoe"), "%s/guns/aoe.png" % Art.WORLD_DIR)
	_save(_gun("pulse"), "%s/guns/pulse.png" % Art.WORLD_DIR)


const GUN_SIZE: Vector2i = Vector2i(24, 30)

## Where the hardpoint sits inside a gun frame: two thirds up, so the barrel
## stands forward of the mount and the breech sits behind it.
const GUN_PIVOT: Vector2 = Vector2(12.0, 20.0)


func _gun(kind: String) -> Image:
	var image: Image = _blank(GUN_SIZE.x, GUN_SIZE.y)
	var breech: Rect2i = Rect2i(6, 16, 12, 11)
	match kind:
		"projectile":
			_box(image, Rect2i(10, 2, 4, 18), METAL)
		"laser":
			_box(image, Rect2i(11, 1, 2, 18), METAL)
			_disc(image, Vector2(12.0, 4.0), 3.0, GLASS, false)
			breech = Rect2i(7, 17, 10, 10)
		"dumb_missile":
			_box(image, Rect2i(10, 5, 4, 15), SHADOW)
			_box(image, Rect2i(9, 2, 6, 12), METAL)
			breech = Rect2i(7, 19, 10, 8)
		"homing_missile":
			_box(image, Rect2i(10, 5, 4, 15), SHADOW)
			_box(image, Rect2i(9, 4, 6, 10), METAL)
			_box(image, Rect2i(6, 10, 3, 6), METAL)
			_box(image, Rect2i(15, 10, 3, 6), METAL)
			_disc(image, Vector2(12.0, 4.0), 3.0, GLASS, false)
			breech = Rect2i(7, 19, 10, 8)
		"aoe":
			_box(image, Rect2i(7, 4, 10, 16), METAL)
			_box(image, Rect2i(5, 2, 14, 4), SHADOW)
			breech = Rect2i(6, 18, 12, 9)
		"pulse":
			for column: int in [8, 11, 14]:
				_box(image, Rect2i(column, 6, 2, 12), METAL)
	_box(image, breech, SHADOW)
	_border(image, EDGE)
	return image


## The modules that are visible from outside: a cell, a computer and a hold.
func _draw_boxes() -> void:
	_save(_box_module("generator"), "%s/modules/generator.png" % Art.WORLD_DIR)
	_save(_box_module("computer"), "%s/modules/computer.png" % Art.WORLD_DIR)
	_save(_box_module("cargo"), "%s/modules/cargo.png" % Art.WORLD_DIR)


const BOX_SIZE: int = 7 * Art.FACTOR + MARGIN * 2


func _box_module(kind: String) -> Image:
	var image: Image = _blank(BOX_SIZE, BOX_SIZE)
	var inner: Rect2i = Rect2i(MARGIN, MARGIN, BOX_SIZE - MARGIN * 2, BOX_SIZE - MARGIN * 2)
	_box(image, inner, METAL)
	match kind:
		"generator":
			_box(image, Rect2i(inner.position.x + 4, inner.position.y + 3, 3, 9),
				EMBER)
			_box(image, Rect2i(inner.position.x + 9, inner.position.y + 6, 3, 9),
				EMBER)
		"computer":
			for row: int in range(2):
				for column: int in range(2):
					_box(image, Rect2i(
						inner.position.x + 3 + column * 8, inner.position.y + 3 + row * 8, 5, 5
					), GLASS)
		"cargo":
			_box(image, Rect2i(inner.position.x, inner.position.y + 6, inner.size.x, 4),
				SHADOW)
	_border(image, EDGE)
	return image


## A leg is two sprites, because the strut lengthens as the gear comes down
## and the pad does not. One sprite for both would have to stretch the pad.
##
## Narrower than ASSETLIST first said. On the stock dart the feet sit three
## design pixels off the hull, so a strut three wide came out square and
## read as a block bolted on rather than as a leg -- the sprite has to be
## thinner than the shortest travel it will ever be stretched over.
func _draw_gear() -> void:
	var strut: Image = _blank(2 * Art.FACTOR, 9 * Art.FACTOR + 2)
	_box(strut, Rect2i(1, 1, strut.get_width() - 2, strut.get_height() - 2), METAL)
	_border(strut, EDGE)
	_save(strut, "%s/gear/strut.png" % Art.WORLD_DIR)

	var pad: Image = _blank(6 * Art.FACTOR + 2, 2 * Art.FACTOR)
	_box(pad, Rect2i(1, 1, pad.get_width() - 2, pad.get_height() - 2), SHADOW)
	_border(pad, EDGE)
	_save(pad, "%s/gear/pad.png" % Art.WORLD_DIR)


## What a weapon throws, and what a kill leaves behind.
func _draw_rounds() -> void:
	var slug: Image = _blank(3 * Art.FACTOR + 2, 7 * Art.FACTOR + 2)
	_box(slug, Rect2i(1, 1, slug.get_width() - 2, slug.get_height() - 2), HOT)
	_save(slug, "%s/rounds/slug.png" % Art.WORLD_DIR)

	var missile: Image = _blank(5 * Art.FACTOR + 2, 11 * Art.FACTOR + 2)
	var body: int = missile.get_width()
	_fill_polygon(missile, PackedVector2Array([
		Vector2(float(body) * 0.5, 1.0),
		Vector2(float(body) - 2.0, 8.0),
		Vector2(float(body) - 2.0, float(missile.get_height()) - 2.0),
		Vector2(2.0, float(missile.get_height()) - 2.0),
		Vector2(2.0, 8.0),
	]), SHELL)
	_box(missile, Rect2i(0, missile.get_height() - 10, 3, 8), SHELL_DARK)
	_box(missile, Rect2i(body - 3, missile.get_height() - 10, 3, 8), SHELL_DARK)
	_border(missile, EDGE)
	_save(missile, "%s/rounds/missile.png" % Art.WORLD_DIR)

	var crate: Image = _blank(12 * Art.FACTOR + 2, 12 * Art.FACTOR + 2)
	_box(crate, Rect2i(1, 1, crate.get_width() - 2, crate.get_height() - 2), SHELL)
	_box(crate, Rect2i(1, crate.get_height() / 2 - 2, crate.get_width() - 2, 4),
		SHELL_DARK)
	_border(crate, EDGE)
	_save(crate, "%s/rounds/crate.png" % Art.WORLD_DIR)


## The two particle textures the engine is currently making do without.
##
## Without the first one a flame is a grid of squares, which is what it looks
## like today: GPUParticles2D with no texture draws literal quads.
func _draw_particles() -> void:
	var size: int = 8 * Art.FACTOR
	var dot: Image = _blank(size, size)
	var middle: float = float(size) * 0.5
	for y: int in range(size):
		for x: int in range(size):
			var away: float = Vector2(float(x) + 0.5, float(y) + 0.5).distance_to(
				Vector2(middle, middle)
			) / middle
			if away >= 1.0:
				continue
			var shade: Color = PAPER
			# Squared falloff, so the dot has a core instead of being a
			# uniformly grey disc with a soft edge.
			shade.a = pow(1.0 - away, 2.0)
			dot.set_pixel(x, y, shade)
	_save(dot, "%s/particles/dot.png" % Art.WORLD_DIR)

	var chip: int = 3 * Art.FACTOR
	var debris: Image = _blank(chip * 3, chip)
	# Three different chips rather than one rotated: at nine texels a
	# rotation is not a rotation, it is a different shape, so each one is
	# drawn as one. A corner knocked off, in a different corner each time.
	var knocked: Array[Vector2i] = [Vector2i(1, 1), Vector2i(0, 1), Vector2i(1, 0)]
	for variant: int in range(3):
		var bite: Vector2i = knocked[variant]
		for y: int in range(chip):
			for x: int in range(chip):
				var in_bite: bool = (
					(x >= chip / 2) == (bite.x == 1) and (y >= chip / 2) == (bite.y == 1)
				)
				if in_bite:
					continue
				debris.set_pixel(variant * chip + x, y, METAL)
	_save(debris, "%s/particles/debris_strip3.png" % Art.WORLD_DIR)


## Interface glyphs, authored 1:1 because that is what Art.UI_FILTER expects.
func _draw_icons() -> void:
	for name: Variant in ICONS:
		var rows: Array = ICONS[name]
		var image: Image = _blank(String(rows[0]).length(), rows.size())
		for y: int in range(rows.size()):
			var row: String = String(rows[y])
			for x: int in range(row.length()):
				if row[x] == "#":
					image.set_pixel(x, y, PAPER)
		_save(image, "%s/icons/%s.png" % [Art.UI_DIR, name])


# --- resources --------------------------------------------------------------


func _write_hull_resources(hulls: Array[Dictionary]) -> void:
	for entry: Dictionary in hulls:
		var hull: HullData = HullData.new()
		hull.id = entry["id"]
		hull.display_name = entry["name"]
		hull.outline = entry["outline"]
		hull.legs = entry["legs"]
		_store(hull, "%s/%s.tres" % [HullData.DIRECTORY, hull.id])


func _write_look_tables() -> void:
	var hulls: LookTable = LookTable.new()
	for entry: Dictionary in _hull_catalogue():
		var id: StringName = entry["id"]
		var box: Rect2 = _bounds(entry["outline"])
		hulls.by_key[id] = _strip(
			"%s/hulls/%s.png" % [Art.WORLD_DIR, id],
			1,
			Vector2(-box.position.x * Art.FACTOR + MARGIN, -box.position.y * Art.FACTOR + MARGIN)
		)
	_store(hulls, "res://resources/fx/looks/hull.tres")

	# Nozzles by EngineData.Type: MAIN 0, TORQUE 1, THRUSTER 2. The thresholds
	# are the enum, which is the same mechanism as a threshold on thrust --
	# "pick by a number on the item" covers both.
	var nozzles: LookTable = LookTable.new()
	nozzles.stat = &"type"
	nozzles.thresholds = PackedFloat32Array([0.0, 1.0, 2.0])
	nozzles.variants.append(_nozzle_strip("main", 8.0, 7.0))
	nozzles.variants.append(_nozzle_strip("torque", 4.0, 4.0))
	nozzles.variants.append(_nozzle_strip("thruster", 6.0, 3.5))
	nozzles.by_affix[&"steerable"] = _nozzle_strip("gimbal", 8.0, 7.0)
	nozzles.fallback = nozzles.variants[2]
	_store(nozzles, "res://resources/fx/looks/engine_nozzle.tres")

	# Plumes by thrust. The thresholds come from the engines that exist: the
	# manoeuvring pods sit at 180, the retro at 500 and the main drive at 900,
	# so 250 and 600 put one tier in each and leave room either side.
	var plumes: LookTable = LookTable.new()
	plumes.stat = &"max_thrust"
	plumes.thresholds = PackedFloat32Array([0.0, 250.0, 600.0])
	plumes.variants.append(_plume_strip("spark", 5.0))
	plumes.variants.append(_plume_strip("cone", 7.0))
	plumes.variants.append(_plume_strip("flame", 9.0))
	plumes.fallback = plumes.variants[0]
	_store(plumes, "res://resources/fx/looks/engine_plume.tres")

	var guns: LookTable = LookTable.new()
	guns.stat = &"type"
	guns.thresholds = PackedFloat32Array([0.0, 1.0, 2.0, 3.0, 4.0, 5.0])
	for kind: String in [
		"projectile", "laser", "dumb_missile", "homing_missile", "aoe", "pulse",
	]:
		guns.variants.append(
			_strip("%s/guns/%s.png" % [Art.WORLD_DIR, kind], 1, GUN_PIVOT)
		)
	guns.fallback = guns.variants[0]
	_store(guns, "res://resources/fx/looks/weapon_muzzle.tres")

	var boxes: LookTable = LookTable.new()
	for kind: String in ["generator", "computer", "cargo"]:
		boxes.by_key[StringName(kind)] = _strip(
			"%s/modules/%s.png" % [Art.WORLD_DIR, kind], 1,
			Vector2.ONE * (float(BOX_SIZE) * 0.5)
		)
	boxes.fallback = boxes.by_key[&"generator"]
	_store(boxes, "res://resources/fx/looks/module_box.tres")

	var gear: LookTable = LookTable.new()
	gear.by_key[&"strut"] = _strip(
		"%s/gear/strut.png" % Art.WORLD_DIR, 1,
		Vector2(float(2 * Art.FACTOR) * 0.5, 0.0)
	)
	gear.by_key[&"pad"] = _strip(
		"%s/gear/pad.png" % Art.WORLD_DIR, 1,
		Vector2(float(6 * Art.FACTOR + 2) * 0.5, float(2 * Art.FACTOR) * 0.5)
	)
	gear.fallback = gear.by_key[&"strut"]
	_store(gear, "res://resources/fx/looks/gear_leg.tres")

	var flying: LookTable = LookTable.new()
	for kind: String in ["slug", "missile", "crate"]:
		flying.by_key[StringName(kind)] = _centred(
			"%s/rounds/%s.png" % [Art.WORLD_DIR, kind]
		)
	flying.fallback = flying.by_key[&"slug"]
	_store(flying, "res://resources/fx/looks/round.tres")

	var motes: LookTable = LookTable.new()
	var dot: SpriteStrip = _centred("%s/particles/dot.png" % Art.WORLD_DIR)
	if dot != null:
		dot.additive = true
	motes.by_key[&"dot"] = dot
	motes.by_key[&"debris"] = _strip(
		"%s/particles/debris_strip3.png" % Art.WORLD_DIR, 3,
		Vector2.ONE * (float(3 * Art.FACTOR) * 0.5)
	)
	motes.fallback = dot
	_store(motes, "res://resources/fx/looks/particle.tres")

	# Interface glyphs: authored 1:1, filtered Nearest, never rotated. The
	# one family in the game the grid law still governs exactly as written.
	var glyphs: LookTable = LookTable.new()
	for name: Variant in ICONS:
		var icon: SpriteStrip = _strip(
			"%s/icons/%s.png" % [Art.UI_DIR, name], 1, Vector2.ZERO
		)
		if icon != null:
			icon.in_world = false
			icon.full_rate = 0.0
		glyphs.by_key[StringName(name)] = icon
	glyphs.fallback = glyphs.by_key[&"empty"]
	_store(glyphs, "res://resources/fx/looks/module_icon.tres")


func _nozzle_strip(kind: String, mouth: float, length: float) -> SpriteStrip:
	var strip: SpriteStrip = _strip(
		"%s/nozzles/%s.png" % [Art.WORLD_DIR, kind], 1,
		Vector2(float(int(ceilf(mouth * Art.FACTOR)) + MARGIN * 2) * 0.5, float(MARGIN))
	)
	if strip != null:
		# Where the flame starts. The bell runs from the pivot to one
		# margin short of the bottom edge, which is the one fact about
		# these placeholders the skin is allowed to rely on.
		strip.exit = length
	return strip


func _plume_strip(kind: String, across: float) -> SpriteStrip:
	var width: int = int(ceilf(across * Art.FACTOR)) + MARGIN * 2
	var strip: SpriteStrip = _strip(
		"%s/plumes/%s_strip%d.png" % [Art.WORLD_DIR, kind, PLUME_FRAMES],
		PLUME_FRAMES,
		Vector2(float(width) * 0.5, 0.0)
	)
	if strip != null:
		strip.additive = true
		# Fast. A flame that flickers at walking pace reads as a flag.
		strip.full_rate = 18.0
	return strip


## A strip whose pivot is the middle of its frame.
func _centred(path: String) -> SpriteStrip:
	var texture: Texture2D = load(path) as Texture2D
	if texture == null:
		_missing.append(path)
		return null
	return _strip(path, 1, Vector2(texture.get_size()) * 0.5)


func _strip(path: String, frames: int, pivot: Vector2) -> SpriteStrip:
	var texture: Texture2D = load(path) as Texture2D
	if texture == null:
		_missing.append(path)
		return null
	var strip: SpriteStrip = SpriteStrip.new()
	strip.texture = texture
	strip.frames = frames
	strip.pivot = pivot
	strip.full_rate = 0.0 if frames <= 1 else 12.0
	return strip


# --- plumbing ---------------------------------------------------------------


## Whether the first pass's output has been through the importer yet.
func _textures_ready() -> bool:
	return ResourceLoader.exists("%s/hulls/dart.png" % Art.WORLD_DIR, "Texture2D")


func _make_dirs() -> void:
	for path: String in [
		"%s/hulls" % Art.WORLD_DIR, "%s/nozzles" % Art.WORLD_DIR,
		"%s/plumes" % Art.WORLD_DIR, "%s/guns" % Art.WORLD_DIR,
		"%s/modules" % Art.WORLD_DIR, "%s/gear" % Art.WORLD_DIR,
		"%s/rounds" % Art.WORLD_DIR, "%s/particles" % Art.WORLD_DIR,
		"%s/icons" % Art.UI_DIR, "res://resources/fx/looks", HullData.DIRECTORY,
	]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))


func _blank(width: int, height: int) -> Image:
	var image: Image = Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	return image


func _save(image: Image, path: String) -> void:
	var error: int = image.save_png(ProjectSettings.globalize_path(path))
	if error != OK:
		push_error("could not write %s (%d)" % [path, error])
		return
	_written += 1


func _store(resource: Resource, path: String) -> void:
	var error: int = ResourceSaver.save(resource, path)
	if error != OK:
		push_error("could not write %s (%d)" % [path, error])


func _bounds(points: PackedVector2Array) -> Rect2:
	if points.is_empty():
		return Rect2()
	var box: Rect2 = Rect2(points[0], Vector2.ZERO)
	for point: Vector2 in points:
		box = box.expand(point)
	return box


func _inside(image: Image, x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height()


func _opaque(image: Image, x: int, y: int) -> bool:
	return _inside(image, x, y) and image.get_pixel(x, y).a > 0.0


## Scanline-free polygon fill: every pixel centre tested against the outline.
## Slow and exactly right, which is the correct trade for a build step that
## runs once and draws a few thousand pixels.
func _fill_polygon(image: Image, polygon: PackedVector2Array, colour: Color) -> void:
	if polygon.size() < 3:
		return
	var box: Rect2 = _bounds(polygon)
	for y: int in range(maxi(0, int(box.position.y)), mini(
		image.get_height(), int(ceilf(box.end.y)) + 1
	)):
		for x: int in range(maxi(0, int(box.position.x)), mini(
			image.get_width(), int(ceilf(box.end.x)) + 1
		)):
			if Geometry2D.is_point_in_polygon(
				Vector2(float(x) + 0.5, float(y) + 0.5), polygon
			):
				image.set_pixel(x, y, colour)


func _box(image: Image, rect: Rect2i, colour: Color) -> void:
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			if _inside(image, x, y):
				image.set_pixel(x, y, colour)


## A filled circle. `only_over_paint` leaves transparent pixels alone, which
## is how a cockpit stays inside the hull it is drawn on.
func _disc(
	image: Image, centre: Vector2, radius: float, colour: Color, only_over_paint: bool
) -> void:
	for y: int in range(int(centre.y - radius) - 1, int(centre.y + radius) + 2):
		for x: int in range(int(centre.x - radius) - 1, int(centre.x + radius) + 2):
			if not _inside(image, x, y):
				continue
			if only_over_paint and not _opaque(image, x, y):
				continue
			if Vector2(float(x) + 0.5, float(y) + 0.5).distance_to(centre) <= radius:
				image.set_pixel(x, y, colour)


## One texel of `colour` round every opaque region.
##
## Read from a copy, not from the image being written: outlining in place
## walks its own output and eats the shape from the edge inward, which on the
## first attempt turned the smaller sprites into solid blocks of border.
func _border(image: Image, colour: Color) -> void:
	var before: Image = image.duplicate() as Image
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			if not _opaque(before, x, y):
				continue
			var exposed: bool = false
			for step: Vector2i in [
				Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
			]:
				if not _opaque(before, x + step.x, y + step.y):
					exposed = true
					break
			if exposed:
				image.set_pixel(x, y, colour)
