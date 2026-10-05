class_name GalaxyMap
extends RefCounted
## Where the systems stand in the galaxy, and which can be reached from which.
##
## Pure data, like `StarSystem`: the layout exists whether or not anything
## has been instantiated, and the same seed gives the same galaxy down to
## the last system. A save is the galaxy seed plus deltas (IDEAS.md
## section 10), so a layout that came out differently on the second load
## would take the save file with it.
##
## Two coordinate spaces, and this is the outer one. A system is a point
## on a plane in light years; inside a system everything is in pixels.
## Both are the same plane, which is the whole trick behind jumping
## without gates: the direction to another system on the map is the
## direction you point the nose in (IDEAS.md section 10).

## How far the galaxy reaches from its centre, in light years.
const RADIUS: float = 60.0

## Closest two systems may sit, in light years, at the galactic centre.
##
## This is the number everything else is measured against. A jump range
## is only meaningful as a multiple of it: a drive that reaches less than
## this reaches nothing, and one that reaches twice it reaches most
## things.
const SPACING: float = 6.0

## How much further apart systems stand at the rim than at the core.
##
## The gradient is the point, not decoration. A uniform scatter makes one
## galaxy that is the same everywhere, and then "islands past the graph as
## late game behind a better drive" (IDEAS.md section 10) has nowhere to
## happen. With the rim nearly twice as thin, the core is connected for
## the starting drive and the edge is not -- so range on a jump drive buys
## somewhere to go rather than a shorter trip to where you already went.
const RIM_SPREAD: float = 1.9

## How many places Bridson tries around a point before giving up on it.
## Twelve is the usual recommendation; this is well past the knee and the
## whole galaxy is generated once.
const CANDIDATES: int = 24

## What the starting jump drive reaches, in light years.
##
## Here rather than on the drive resource because the layout is checked
## against it: `largest_component()` at this reach is the galaxy the
## player can actually use, and a number that disagreed with the drive
## would be a check of a galaxy nobody is flying. When the jump drive
## module arrives (M4) it reads this; it does not restate it.
##
## Stated as a multiple of the spacing because that is the only way it
## means anything, and **measured**, not guessed. A graph like this does
## not start connecting until the reach is about one and a half times the
## local spacing: at 1.5 the starting galaxy was a seventh of itself, and
## the first pass of this file had it at 1.5 for exactly that reason. At
## 1.75 three quarters of the systems are one component and the remaining
## quarter is the rim, in islands, which is the shape IDEAS.md section 10
## asks for.
const BASE_REACH: float = SPACING * 1.75

## Cell size for the lookup grid. `SPACING / sqrt(2)` guarantees at most
## one system per cell, because no two are closer than `SPACING`.
const CELL: float = SPACING * 0.70710678

## How many concentric bands the galaxy is cut into.
##
## Tier 1 is the rim and tier `TIERS` is the centre, counting **up** the
## way the player travels: the premise is a flight inwards, and a number
## that fell as the game got harder would be a number read backwards
## every time it was used.
const TIERS: int = 10

## Where every system stands, indexed the way the rest of the game indexes
## them: `Galaxy.system(i)` is the system at `positions[i]`.
var positions: PackedVector2Array = PackedVector2Array()

var seed: int = 0

## Cell coordinate -> index of the one system in it.
var _grid: Dictionary = {}


## Lays out a galaxy. The only way to make one.
static func generate(galaxy_seed: int) -> GalaxyMap:
	var map: GalaxyMap = GalaxyMap.new()
	map.seed = galaxy_seed
	map._scatter()
	return map


## Bridson's Poisson disk sampling, with the radius varying by place.
##
## Grown from the centre outwards, which the variable radius wants anyway:
## each new system is thrown into the ring between one and two spacings
## from an existing one, so the dense core is laid down first and the
## thin rim fills in from it.
func _scatter() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed

	_keep(Vector2.ZERO)
	var active: PackedInt32Array = PackedInt32Array([0])

	while not active.is_empty():
		var slot: int = rng.randi_range(0, active.size() - 1)
		var from: Vector2 = positions[active[slot]]
		var reach: float = spacing_at(from)
		var placed: bool = false
		for attempt: int in range(CANDIDATES):
			# Uniform in the annulus by area, not by radius: sampling the
			# radius flat crowds candidates towards the inner edge, which
			# biases the whole layout inwards.
			var inner: float = reach * reach
			var outer: float = 4.0 * reach * reach
			var away: float = sqrt(rng.randf_range(inner, outer))
			var tried: Vector2 = from + Vector2.RIGHT.rotated(
				rng.randf_range(0.0, TAU)
			) * away
			if tried.length() > RADIUS or not _has_room(tried):
				continue
			active.append(_keep(tried))
			placed = true
			break
		if not placed:
			# Swap and drop, rather than erase: the order of the active
			# list is not meaningful and erasing from the middle is the
			# one way to make this quadratic.
			active[slot] = active[active.size() - 1]
			active.resize(active.size() - 1)


## How much room a system wants around it, here.
##
## Public because the tests check the layout against it and the map
## drawing will want it. Linear in the distance from the centre: nothing
## claims that is how galaxies work, and it is the cheapest thing that
## gives a dense core and a thin rim.
func spacing_at(point: Vector2) -> float:
	var out: float = clampf(point.length() / RADIUS, 0.0, 1.0)
	return SPACING * lerpf(1.0, RIM_SPREAD, out * out * out)


## Whether a system could stand here without crowding one already placed.
##
## Against the **larger** of the two claims. A system near the rim wants
## more room than one in the core, and a test that used only the
## candidate's own figure would let a rim system be crowded by a core one
## that was placed first.
func _has_room(point: Vector2) -> bool:
	var wants: float = spacing_at(point)
	# Far enough out that nothing inside the widest possible claim can be
	# missed, whichever of the two claims turns out to be the larger.
	var steps: int = int(ceil(SPACING * RIM_SPREAD / CELL))
	var home: Vector2i = _cell_of(point)
	for dy: int in range(-steps, steps + 1):
		for dx: int in range(-steps, steps + 1):
			var at: Vector2i = home + Vector2i(dx, dy)
			if not _grid.has(at):
				continue
			var other: Vector2 = positions[int(_grid[at])]
			if point.distance_to(other) < maxf(wants, spacing_at(other)):
				return false
	return true


## Files a system and returns its index.
func _keep(point: Vector2) -> int:
	var index: int = positions.size()
	positions.append(point)
	_grid[_cell_of(point)] = index
	return index


func _cell_of(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / CELL), floori(point.y / CELL))


func count() -> int:
	return positions.size()


## Every system within `reach` light years of a point, nearest first.
##
## Through the grid rather than over the whole list: this is what the
## scanner asks every time the HUD redraws, and a galaxy-wide scan per
## frame is a galaxy-wide scan per frame.
func within(at: Vector2, reach: float) -> PackedInt32Array:
	var found: Array[int] = []
	var steps: int = int(ceil(maxf(reach, 0.0) / CELL))
	var home: Vector2i = _cell_of(at)
	for dy: int in range(-steps - 1, steps + 2):
		for dx: int in range(-steps - 1, steps + 2):
			var cell: Vector2i = home + Vector2i(dx, dy)
			if not _grid.has(cell):
				continue
			var index: int = int(_grid[cell])
			if at.distance_to(positions[index]) <= reach:
				found.append(index)
	found.sort_custom(func(a: int, b: int) -> bool:
		return at.distance_squared_to(positions[a]) < at.distance_squared_to(positions[b])
	)
	return PackedInt32Array(found)


## Where a jump of `reach` can go from `index`. Itself is not included.
func neighbours(index: int, reach: float) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for other: int in within(positions[index], reach):
		if other != index:
			out.append(other)
	return out


## Everything reachable from `index` by jumps of `reach`, in any number of
## hops. Breadth first, so the order is by hop count: a caller that wants
## "how far away is this really" can read it off the order.
func reachable_from(index: int, reach: float) -> PackedInt32Array:
	var seen: Dictionary = {index: true}
	var order: PackedInt32Array = PackedInt32Array([index])
	var at: int = 0
	while at < order.size():
		for next: int in neighbours(order[at], reach):
			if not seen.has(next):
				seen[next] = true
				order.append(next)
		at += 1
	return order


## The biggest group of systems that can all get to each other.
##
## What "the galaxy" means for a given drive. Everything outside it is an
## island: visible on a scanner that reaches, unreachable until the drive
## does (IDEAS.md section 10).
func largest_component(reach: float) -> PackedInt32Array:
	var placed: Dictionary = {}
	var best: PackedInt32Array = PackedInt32Array()
	for index: int in range(positions.size()):
		if placed.has(index):
			continue
		var group: PackedInt32Array = reachable_from(index, reach)
		for member: int in group:
			placed[member] = true
		if group.size() > best.size():
			best = group
	return best


## Which band a system sits in: 1 at the rim, `TIERS` at the centre.
##
## One number, and everything that scales with difficulty reads it
## rather than keeping a scale of its own. Three separate scales --
## enemies, rarity, price -- drift apart at the first tuning pass, and
## then "a harder system" and "a better haul" stop meaning the same
## place, which is the one thing the premise needs them to mean.
##
## Bands of equal width, so the tiers hold unequal numbers of systems:
## on the test seed, one at the centre and eighteen in the eighth band.
## That is not a fault to even out. The finale is meant to be one place,
## and the middle of the journey is meant to be where most of the
## flying happens.
func tier_of(index: int) -> int:
	if index < 0 or index >= positions.size():
		return 0
	var out: float = positions[index].length() / maxf(RADIUS, 0.0001)
	var band: int = clampi(int(out * float(TIERS)), 0, TIERS - 1)
	return TIERS - band


## Where a new game starts: the furthest system that is still in the
## galaxy the starting drive can fly.
##
## The rim, because the premise is a flight inwards. Not the furthest
## system outright -- that one is an island **by construction**, which
## is what the density gradient is for, and it reaches nothing. In this
## galaxy "the furthest system" and "the furthest system you can get
## to" are two different places, and only the second is a start.
##
## Measured over five seeds: 51 to 55 light years out of 60, the ninth
## or tenth band, and from every one of them the starting drive reaches
## the whole main component with the centre in it (IDEAS.md section 10).
##
## Deliberate rather than random, which is the half of the old reason
## that survives the premise reversing: a start that could land on an
## island would be a new game that cannot jump, and "check the graph is
## connected" is not a check if the one system that has to be in it is
## picked afterwards.
func start_index() -> int:
	var main: PackedInt32Array = largest_component(BASE_REACH)
	# A first jump inside the comfortable part of the range, which is
	# the half of this that cost a measurement. Taking simply the
	# outermost member put the nearest system at 93% of the drive's
	# reach, and `JumpController.STRAIN_FROM` starts charging risk at
	# 85% -- so a new game opened with a 56% chance of misjumping, on
	# its very first act, with a tank that covered the fare six times
	# over. The rule was right and had never been aimed at a starting
	# position before.
	var easy: float = BASE_REACH * JumpController.STRAIN_FROM
	var best: int = -1
	var furthest: float = -1.0
	var fallback: int = -1
	var fallback_out: float = -1.0
	for index: int in main:
		var away: float = positions[index].length_squared()
		if away > fallback_out:
			fallback_out = away
			fallback = index
		if nearest_gap(index, main) > easy:
			continue
		if away > furthest:
			furthest = away
			best = index
	# The fallback cannot be hit on any galaxy this generator makes --
	# the core is dense enough that something always qualifies -- but a
	# start of -1 would be a new game with no system at all, and that is
	# too quiet a way to fail.
	return best if best >= 0 else fallback


## How far the nearest of `group` is from `index`, or `INF` when it
## stands alone.
func nearest_gap(index: int, group: PackedInt32Array) -> float:
	var nearest: float = INF
	for other: int in group:
		if other == index:
			continue
		nearest = minf(nearest, positions[index].distance_to(positions[other]))
	return nearest
