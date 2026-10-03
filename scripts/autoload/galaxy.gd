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

## Which system the player is in, or -1 out in the gap between two.
##
## An index into `map`, and the address a save file stores -- not a
## scene path, because the scene is only the part of the system the
## pilot happens to be near.
var here: int = 0

## Where the player is, in light years. The **real** address, of which
## `here` is a convenience: a misjump can put a ship somewhere that is
## not on the map at all, and a scanner still works out there because it
## works off a point rather than off an entry in a list.
var at: Vector2 = Vector2.ZERO

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

## And the empty places, keyed by where they are.
var _sectors: Dictionary = {}


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


## The interstellar sector at a point: nothing, somewhere between two
## somewheres.
##
## Keyed by the place rather than by an index, because it has none.
## Rounded to a tenth of a light year first, so that asking twice about
## the same gap gives the same empty sector with the same name -- a
## misjump the player can fly back out of and return to.
func sector_at(point: Vector2) -> StarSystem:
	var key: Vector2i = Vector2i(roundi(point.x * 10.0), roundi(point.y * 10.0))
	if not _sectors.has(key):
		_sectors[key] = StarSystem.deep_space(
			StarSystem.derive(galaxy_seed, key.x * 7919 + key.y)
		)
	return _sectors[key]


## Where the player is, as a system: a real one, or the gap they fell
## into. The one call anything that needs "the system I am in" should
## make, so that nothing has to remember that -1 is a place too.
func current() -> StarSystem:
	return sector_at(at) if here < 0 else system(here)


## Reseeds the galaxy and drops everything derived from the old seed.
##
## Everything, which includes the layout: a new seed is a new galaxy, and
## keeping the old positions while regenerating the systems in them would
## be the one bug this whole model exists to make impossible.
func reset(new_seed: int) -> void:
	galaxy_seed = new_seed
	deltas.clear()
	_systems.clear()
	_sectors.clear()
	map = GalaxyMap.generate(new_seed)
	here = map.start_index()
	at = map.positions[here]
