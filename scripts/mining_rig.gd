class_name MiningRig
extends Node
## Taking ore out of the ground, and nothing else.
##
## The model half is `Deposits`: what is under which bearing, how deep,
## and how much is left. This is the half that turns a held key into
## units in the hold.
##
## **It needs no streaming of its own**, for the same reason the garrison
## spawner does not: a deposit belongs to a body, the pilot can only dig
## at the body they are standing on, and the ship already knows which
## one that is. So there is no distance pass and nothing that can
## disagree with where the planets are -- the question "what am I
## standing on" is asked once a tick and answered by `Ship.landed_on`.
##
## Everything is handed in. `Galaxy` and `StreamingManager` are autoloads
## and do not exist in a `--script` run, and a rig that reached for them
## by name would be a rig with no tests.
##
## ## Why the ship digs rather than a drone
##
## Drones are the next milestone and they will do this better. Until
## then the ship does it, which costs one key and no new machinery, and
## means the resource loop can be played and judged before the thing
## that is supposed to make it comfortable exists. A loop nobody has
## played is a loop nobody knows is worth automating.

## Units a second, with the ship on the ground.
##
## Measured against the hold rather than chosen: the stock hold takes
## twenty-five iron ore, so filling it from a middling patch is about
## twelve seconds of holding a key. Long enough to be a thing you decide
## to do and short enough that the decision is about whether to stay,
## not about whether to go and make tea.
const UNITS_PER_SECOND: float = 2.0

## Why a held key is producing nothing. One of these, in this order, so
## the readout names the nearest problem rather than the first one it
## happens to check.
enum Snag { NONE, NOT_LANDED, NO_PATCH, BURIED, EXHAUSTED, HOLD_FULL, NO_SCOOP, THIN }

const SNAG_NAMES: Array[String] = [
	"", "not landed", "no ore here", "buried", "worked out", "hold full",
	"no scoop", "thin",
]

## Ore came out. The world turns this into a line in the log and, one
## day, into dust and noise at the legs.
signal struck(kind: int, units: int, at: Vector2)

var _tier: int = 1
var _galaxy: Node = null
var _manager: Node = null
var _ship: Ship = null

## body -> its patches, rolled once per visit. Cached because `on()`
## walks a fresh RNG and this is asked every tick by the readout; the
## cache is dropped when the body is, which is the same life a
## garrison's roster has.
var _patches: Dictionary = {}

## Fractional progress towards the next whole unit. Units are whole
## things (`Stores`), so the rate has to be remembered between ticks or
## two units a second at sixty ticks a second would floor to nothing
## sixty times.
var _progress: float = 0.0

var _snag: Snag = Snag.NOT_LANDED

## The star of the system, for the corona. Handed in like everything
## else, and allowed to be null: a rig with no star simply has no wind
## to offer.
var _star: Star = null

## Fractional progress on the scoop, kept for the same reason the
## digging's is.
var _caught: float = 0.0


## The star whose wind this rig can scoop. A new system is a new star.
func watch_star(star: Star) -> void:
	_star = star
	_caught = 0.0


## How much of a star's wind the ship is sitting in, and why none if
## none. The other half of the resource loop: the ground gives ore and
## wants the legs down, the corona gives stardust straight and wants the
## heat bar climbing.
func wind() -> Dictionary:
	if _ship == null or not is_instance_valid(_ship):
		return {"rate": 0.0, "snag": Snag.NO_SCOOP, "density": 0.0}
	var scoop: float = _ship.dust_scoop()
	if scoop <= 0.0:
		return {"rate": 0.0, "snag": Snag.NO_SCOOP, "density": 0.0}
	if _star == null or not is_instance_valid(_star):
		return {"rate": 0.0, "snag": Snag.THIN, "density": 0.0}
	var burn: float = Ship.burn_radius(_star)
	var away: float = _ship.global_position.distance_to(_star.global_position)
	var thick: float = Corona.density_at(away, burn)
	var rate: float = Corona.units_per_second(scoop, away, burn)
	var trouble: Snag = Snag.NONE
	if rate <= 0.0:
		trouble = Snag.THIN
	elif Stores.fits_in(Stores.Kind.STARDUST, _ship.cargo_free()) <= 0:
		trouble = Snag.HOLD_FULL
	return {
		"rate": rate,
		"snag": trouble,
		"density": thick,
		"best": Corona.best_radius(burn),
		"away": away,
	}


func bind(tier: int, galaxy: Node, manager: Node, ship: Ship) -> void:
	_tier = tier
	_galaxy = galaxy
	_ship = ship
	# A new system is new ground. Nothing here survives a jump, and the
	# patches it held are re-rolled from the seed on arrival anyway.
	_patches.clear()
	_progress = 0.0
	if _manager == manager:
		return
	if _manager != null and is_instance_valid(_manager):
		_manager.body_asleep.disconnect(_on_body_asleep)
	_manager = manager
	if _manager == null:
		return
	_manager.body_asleep.connect(_on_body_asleep)


## The body the ship is standing on, as a model rather than a node.
func body_here() -> SystemBody:
	if _ship == null or not is_instance_valid(_ship):
		return null
	var planet: Planet = _ship.landed_on()
	if planet == null:
		return null
	return planet.body if "body" in planet else null


## Every patch still worth digging on the body underfoot.
func patches() -> Array[Dictionary]:
	var body: SystemBody = body_here()
	if body == null:
		return []
	if not _patches.has(body):
		_patches[body] = Deposits.on(body, _tier, _deltas())
	return _patches[body]


## The patch under the ship, or an empty dictionary.
func under() -> Dictionary:
	if _ship == null or not is_instance_valid(_ship):
		return {}
	return Deposits.under(patches(), _ship.landed_bearing())


## What is stopping the digging, or `Snag.NONE`. For the readout, which
## has to say "buried" rather than "nothing is happening".
func snag() -> Snag:
	return _snag


## What the readout shows: the patch underfoot, what is left of it, and
## why nothing is coming out if nothing is.
##
## One call rather than four, because a HUD asking four questions a
## frame would roll the patches four times on the frame a body wakes.
func readout() -> Dictionary:
	var patch: Dictionary = under()
	return {
		"patch": patch,
		"kind": int(patch.get("kind", -1)),
		"left": int(patch.get("left", 0)),
		"depth": float(patch.get("depth", 0.0)),
		"snag": _assess(patch),
		"digging": _ship != null and is_instance_valid(_ship) and _ship.mining,
	}


func _physics_process(delta: float) -> void:
	if _ship == null or not is_instance_valid(_ship):
		return
	var patch: Dictionary = under()
	_snag = _assess(patch)
	if not _ship.mine_command or _snag != Snag.NONE:
		_ship.mining = false
		_progress = 0.0
		# The same key works the scoop, because it is the same verb and a
		# ship cannot be landed and in a corona at once. Which one it
		# means is decided by where the ship is, not by a second binding.
		if _ship.mine_command:
			_scoop(delta)
		return
	_ship.mining = true
	_progress += UNITS_PER_SECOND * delta
	var whole: int = int(floor(_progress))
	if whole <= 0:
		return
	_progress -= float(whole)
	# Asked of the ground first and the hold second, so a patch is never
	# emptied into a hold that could not take it: `take` writes to
	# `deltas` and a unit written off and not carried is a unit nobody
	# will ever find again.
	var room: int = Stores.fits_in(int(patch["kind"]), _ship.cargo_free())
	var got: int = Deposits.take(_deltas(), patch, mini(whole, room))
	if got <= 0:
		return
	var loaded: int = _ship.load_units(int(patch["kind"]) as Stores.Kind, got)
	struck.emit(int(patch["kind"]), loaded, _ship.global_position)


## One tick of the scoop. Stardust straight, not ore: there is nothing
## to refine out of a wind, and a second raw kind for it would be a kind
## whose only sink is the one the wind already gives.
func _scoop(delta: float) -> void:
	var found: Dictionary = wind()
	if int(found["snag"]) != Snag.NONE:
		_caught = 0.0
		return
	_ship.mining = true
	_caught += float(found["rate"]) * delta
	var whole: int = int(floor(_caught))
	if whole <= 0:
		return
	_caught -= float(whole)
	var loaded: int = _ship.load_units(Stores.Kind.STARDUST, whole)
	if loaded > 0:
		struck.emit(Stores.Kind.STARDUST, loaded, _ship.global_position)


## Why this patch is not giving anything. Nearest reason first.
func _assess(patch: Dictionary) -> Snag:
	if _ship == null or not is_instance_valid(_ship) or _ship.landed_on() == null:
		return Snag.NOT_LANDED
	if patch.is_empty():
		return Snag.NO_PATCH
	if int(patch.get("left", 0)) <= 0:
		return Snag.EXHAUSTED
	var body: SystemBody = body_here()
	var planet: Planet = _ship.landed_on()
	if body != null and not Deposits.reachable(
		patch, planet.surface_radius_at(_ship.global_position), body.radius
	):
		return Snag.BURIED
	if Stores.fits_in(int(patch["kind"]), _ship.cargo_free()) <= 0:
		return Snag.HOLD_FULL
	return Snag.NONE


## A body going to sleep takes its patches with it. They come back from
## the seed, minus whatever `deltas` says was taken -- the same rule the
## garrison's minors come back under.
func _on_body_asleep(body: SystemBody) -> void:
	_patches.erase(body)


func _deltas() -> Dictionary:
	if _galaxy != null and is_instance_valid(_galaxy) and "deltas" in _galaxy:
		return _galaxy.deltas
	return {}


static func snag_name(which: int) -> String:
	return SNAG_NAMES[clampi(which, 0, SNAG_NAMES.size() - 1)]
