extends Node
## Galaxy: pure data model of the universe. No nodes, no scene tree children.
##
## Holds the galaxy seed, generated system descriptors and the delta dictionary
## with every player-made change. Everything here must be reproducible from
## `galaxy_seed` alone, plus the deltas.
##
## Systems are here (M3); laying them out across a galaxy is M4, so for now
## index 0 is the one system there is.

## Seed every other seed in the game is derived from.
var galaxy_seed: int = 0

## Persisted changes that cannot be regenerated from a seed
## (terrain edits, looted crates, killed enemies). Keyed by object id.
var deltas: Dictionary = {}

## The clock every orbit is read against, in seconds since the world began.
##
## One clock, and every body's position is a pure function of it. That is
## what makes streaming free: a planet switched off for ten minutes and
## switched back on is exactly where it would have been, because nothing
## was integrating it and there is no missed update to catch up on.
var time: float = 0.0

## Generated systems, keyed by index. Cached rather than regenerated,
## because generation is deterministic and therefore pointless to repeat.
var _systems: Dictionary = {}


func _process(delta: float) -> void:
	time += delta


## The system at `index`, generated on first ask.
func system(index: int) -> StarSystem:
	if not _systems.has(index):
		_systems[index] = StarSystem.generate(StarSystem.derive(galaxy_seed, index))
	return _systems[index]


## Reseeds the galaxy and drops everything derived from the old seed. M4.
func reset(new_seed: int) -> void:
	galaxy_seed = new_seed
	deltas.clear()
	_systems.clear()
