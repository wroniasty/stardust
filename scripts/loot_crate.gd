class_name LootCrate
extends Area2D
## A module lying on a planet, waiting to be flown into.
##
## The crate holds what the generator rolled for it, not a promise to roll
## something later: a container is its seed, and the seed is spent when the
## world builds it, so the same planet always offers the same finds (see
## IDEAS.md section 4).
##
## Parented to the planet rather than to the world, so it turns with the
## ground it sits on and a pilot who leaves and comes back finds it where
## they left it.

## Emitted when a ship touches the crate. The crate does not decide whether
## the ship can take it -- the hold might be full -- so it waits to be told.
signal touched(crate: LootCrate, body: Node)

## Every crate joins this, so anything that wants to find loot -- the scanner
## now, salvage and cargo later -- asks the group rather than walking the
## planet's children. The same shape as Planet.GRAVITY_GROUP, and for the same
## reason: the day crates stop hanging off planets, one line changes.
const LOOT_GROUP: StringName = &"loot"

## What is inside. Rarity comes off the module itself now, so a crate
## cannot be painted a different colour from the thing in it.
var item: Resource = null

## The one list, on ModuleData. Kept here as a name because the scanner and
## the editor already say LootCrate.RARITY_COLORS and there is no reason for
## them to care where it moved to.
const RARITY_COLORS: Array[Color] = ModuleData.RARITY_COLORS

## Seconds before the crate will answer a ship at all. A jettisoned module
## is dropped by a ship that is still sitting on top of it, and without this
## the pilot picks it straight back up in the same frame -- which turns
## throwing something overboard into a no-op.
var grace: float = 0.0

@onready var _body: Polygon2D = $Body
@onready var _glow: Polygon2D = $Glow


func _ready() -> void:
	add_to_group(LOOT_GROUP)
	body_entered.connect(_on_body_entered)
	_paint()


## Fills the crate. Called by whoever placed it, before it enters the tree or
## right after.
func hold(new_item: Resource, new_rarity: int = -1) -> void:
	item = new_item
	# Told, or asked. A caller that knows better may still say so; one that
	# just found the thing does not have to remember to.
	if new_rarity >= 0 and new_item is ModuleData:
		(new_item as ModuleData).rarity = new_rarity
	if is_node_ready():
		_paint()


## How good what is inside is, or the dullest grade when there is nothing.
## The colour this crate is painted, which is the one thing readable from
## orbit. Exposed so a test can check the crate and the grade agree rather
## than re-deriving the lookup and agreeing with itself.
func rarity_color_of() -> Color:
	return RARITY_COLORS[clampi(rarity(), 0, RARITY_COLORS.size() - 1)]


func rarity() -> int:
	var module: ModuleData = item as ModuleData
	return module.rarity if module != null else 0


## What the pilot is told they have found.
func label() -> String:
	if item == null:
		return "empty crate"
	if item is WeaponData:
		return (item as WeaponData).display_name
	if item is EngineData:
		return "%s engine" % EngineData.Type.keys()[(item as EngineData).type].to_lower()
	return "module"


func _paint() -> void:
	if _body == null:
		return
	var colour: Color = RARITY_COLORS[clampi(rarity(), 0, RARITY_COLORS.size() - 1)]
	_body.color = colour
	_glow.color = Color(colour.r, colour.g, colour.b, 0.25)


func _process(delta: float) -> void:
	if grace <= 0.0:
		return
	grace = maxf(grace - delta, 0.0)
	if grace <= 0.0:
		# Whoever was standing in it while it was inert has to be noticed now,
		# or a crate dropped and left alone would stay invisible to a ship
		# that never re-entered the area.
		for body: Node2D in get_overlapping_bodies():
			touched.emit(self, body)


func _on_body_entered(body: Node2D) -> void:
	if grace > 0.0:
		return
	touched.emit(self, body)
