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

## What is inside, and how good it is. Rarity travels alongside the item
## because neither WeaponData nor EngineData carries it: rarity is a fact
## about the roll, not about the module.
var item: Resource = null
var rarity: int = 0

## Colour per rarity, dullest to brightest. The only thing a pilot can read
## from orbit is how interesting the box is.
const RARITY_COLORS: Array[Color] = [
	Color(0.62, 0.64, 0.66),
	Color(0.45, 0.85, 0.50),
	Color(0.40, 0.65, 1.00),
	Color(0.75, 0.45, 1.00),
	Color(1.00, 0.70, 0.25),
]

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
func hold(new_item: Resource, new_rarity: int) -> void:
	item = new_item
	rarity = new_rarity
	if is_node_ready():
		_paint()


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
	var colour: Color = RARITY_COLORS[clampi(rarity, 0, RARITY_COLORS.size() - 1)]
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
