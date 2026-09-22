extends Node
## Galaxy: pure data model of the universe. No nodes, no scene tree children.
##
## Holds the galaxy seed, generated system descriptors and the delta dictionary
## with every player-made change. Everything here must be reproducible from
## `galaxy_seed` alone, plus the deltas.
##
## Skeleton only (M0). Filled in M3 (system model) and M4 (galaxy generation).

## Seed every other seed in the game is derived from.
var galaxy_seed: int = 0

## Persisted changes that cannot be regenerated from a seed
## (terrain edits, looted crates, killed enemies). Keyed by object id.
var deltas: Dictionary = {}


func _ready() -> void:
	pass


## Reseeds the galaxy and drops all generated data. M4.
func reset(new_seed: int) -> void:
	galaxy_seed = new_seed
	deltas.clear()
