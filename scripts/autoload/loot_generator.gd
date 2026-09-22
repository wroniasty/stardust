extends Node
## LootGenerator: procedural weapons, engines and modules.
##
## Base template plus 0..N affixes, rarity drives affix count and magnitude
## (see IDEAS.md section 4). Every roll is derived from an explicit seed so
## the same container always yields the same loot.
##
## Skeleton only (M0). Filled in M2.

enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	pass


## Rolls a single item from the given seed. M2.
func generate(item_seed: int, rarity: Rarity = Rarity.COMMON) -> Resource:
	_rng.seed = item_seed
	var _unused_rarity: Rarity = rarity
	return null
