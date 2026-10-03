extends Node
## Galaxy: pure data model of the universe. No nodes, no scene tree children.
##
## Holds the galaxy seed, where the systems are, the systems themselves and
## the delta dictionary with every player-made change. Everything here must
## be reproducible from `galaxy_seed` alone, plus the deltas.
##
## Two layers, kept apart on purpose. `GalaxyMap` is where systems stand and
## which can reach which -- a plane in light years, a hundred-odd points, a
## graph. `StarSystem` is what one of them contains -- a star, planets,
## moons, stations, in pixels. The scanner and the jump drive ask the first;
## everything that flies asks the second; neither needs the other's units.

## Seed every other seed in the game is derived from.
var galaxy_seed: int = 0

## Where the systems are, and which can reach which. Built from the seed.
var map: GalaxyMap = null

## Which system the player is in. An index into `map`, and the address a
## save file stores -- not a scene path, because the scene is only the
## part of the system the pilot happens to be near.
var here: int = 0

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


## Where a system stands, in light years.
func position_of(index: int) -> Vector2:
	if map == null or index < 0 or index >= map.count():
		return Vector2.ZERO
	return map.positions[index]


## How far apart two systems are, in light years. The number a jump costs
## fuel by and a drive is measured against.
func distance_between(from: int, to: int) -> float:
	return position_of(from).distance_to(position_of(to))


## Reseeds the galaxy and drops everything derived from the old seed.
##
## Everything, which includes the layout: a new seed is a new galaxy, and
## keeping the old positions while regenerating the systems in them would
## be the one bug this whole model exists to make impossible.
func reset(new_seed: int) -> void:
	galaxy_seed = new_seed
	deltas.clear()
	_systems.clear()
	map = GalaxyMap.generate(new_seed)
	here = map.start_index()
