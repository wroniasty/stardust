class_name ShipFitout
extends RefCounted
## Zbudowanie statku z presetu: czyta `ShipPreset`, stawia mounty, dziala
## i zatoki.
##
## The verb, now that the nouns are resources. `ShipPreset` says what a
## ship is -- hull, engines, guns, module bays -- and this is the one
## function that turns one into nodes on a live `Ship`.
##
## There used to be a table here as well: seven dictionaries of
## dictionaries, with engines and weapons named by short strings resolved
## through two more tables beside them. It was the last thing about a
## ship that could only be changed by editing GDScript, which is the same
## complaint that moved hulls into `resources/hulls` and the torque jets
## into the hulls themselves. The table is now `resources/presets/*.tres`
## and nothing in this file knows how many ships there are.

const MOUNT_SCENE: String = "res://scenes/engine_mount.tscn"

## Every preset, as files. A directory listing rather than a const list,
## because a const list of paths is a second copy of the catalogue.
const DIRECTORY: String = "res://resources/presets"

## How big a socket each small-engine role has.
##
## Facts about the role rather than about the ship, which is why they are
## here once instead of repeated in every preset: every preset in the
## game used 0.8 for a torque jet, 1.0 for a strafe thruster and 2.5 for
## the nose reverse, because that is what those jobs take. A `MountFit`
## leaving `socket` at zero is asking for the figure below.
const TORQUE_SOCKET: float = 0.8
const STRAFE_SOCKET: float = 1.0
const RETRO_SOCKET: float = 2.5

## How much room a main drive socket has.
##
## The generator's own bulk ceiling, so **no engine the game can roll is
## ever too big for a main socket**. Measured before it was set: over
## 40000 engine rolls, 2.6% came out bigger than the 3.5 every main
## socket used to have -- every one of them the pilot's best find of the
## hour and none of them installable anywhere, because the loot table
## pays for thrust with bulk (`oversized`, `buffered`) and the sockets
## were sized for the stock engines rather than for the rolls.
##
## The same number on every hull, the interceptor included, because a
## socket that refuses a plain gimballed drive is not hull character, it
## is a hull that cannot be upgraded. What a big engine costs is still
## paid: bulk is mass (`EngineMount.MASS_PER_BULK`), mass is thrust per
## kilo and a shifted centre of mass, and the small sockets -- torque
## 0.8, strafe 1.0, nose retro 2.5 -- are untouched, so `compact` still
## has somewhere to matter.
const MAIN_DRIVE_SOCKET: float = 8.0

## And which socket size goes with which kind of place the hull offers.
## Also the predicate for "this place takes an engine": both the mount
## loop and the gun loop ask it, so the two cannot come to different
## conclusions about what a place is for.
const SOCKET_FOR: Dictionary = {
	HullData.SLOT_TORQUE: TORQUE_SOCKET,
	HullData.SLOT_STRAFE: STRAFE_SOCKET,
	HullData.SLOT_RETRO: RETRO_SOCKET,
	HullData.SLOT_DRIVE: MAIN_DRIVE_SOCKET,
}

## How much of a thrust increase is paid for in bulk.
##
## Not all of it: a bigger engine of the same design is heavier, and not
## in proportion, or there would be no reason to want one. Seven tenths,
## which is a decision and the only reason this number exists.
const BULK_SHARE: float = 0.7


## Where each of a hull's places is, by name. What a preset's `place`
## is looked up in.
static func places_of(hull: HullData) -> Dictionary:
	var out: Dictionary = {}
	if hull == null:
		return out
	for slot: Dictionary in hull.slots():
		out[String(slot["name"])] = slot
	return out


## How big a mount's socket actually is: its own figure, or the one its
## kind implies.
##
## One function because three callers ask and they must not disagree.
## `placements` sizes every socket with it and `fault_in` uses it to
## refuse a mount that would end up with no socket at all.
##
## Simpler than it was. While a preset named one place per entry, the
## main drive was a **role** rather than a place the hull names -- its
## places are MainDriveCenter, Left and Right -- so a lookup by name
## found nothing and called every shipped preset malformed. Binding by
## kind removes the special case: a drive is a kind like any other.
static func socket_for(places: Dictionary, fit: MountFit) -> float:
	if fit.socket > 0.0:
		return fit.socket
	if not String(fit.place).is_empty():
		return float(SOCKET_FOR.get(
			(places.get(String(fit.place), {}) as Dictionary).get("kind", &""), 0.0
		))
	return float(SOCKET_FOR.get(fit.kind, 0.0))


## Every preset on disk, in the order they should be offered.
##
## Cached, because the menu and the refit list both walk it and the
## alternative is a directory scan plus seven loads each time. Cleared by
## nothing: the catalogue is files on disk, and those do not change while
## the game runs.
static var _catalogue: Array[ShipPreset] = []


static func all() -> Array[ShipPreset]:
	if not _catalogue.is_empty():
		return _catalogue
	var found: Array[ShipPreset] = []
	var names: Array = Array(ResourceLoader.list_directory(DIRECTORY))
	names.sort()
	for file_name: String in names:
		if not file_name.ends_with(".tres"):
			continue
		var one: ShipPreset = load("%s/%s" % [DIRECTORY, file_name]) as ShipPreset
		if one != null:
			found.append(one)
	# Authored order, not the directory's. See `ShipPreset.order`.
	found.sort_custom(
		func(a: ShipPreset, b: ShipPreset) -> bool:
			if a.order != b.order:
				return a.order < b.order
			return a.display_name < b.display_name
	)
	_catalogue = found
	return _catalogue


## The preset with this display name or this id, or null.
##
## Both, because a setting written before the migration says
## `dart (stock)` and a file is called `dart_stock`. The id is what
## anything new should store.
static func preset(named: String) -> ShipPreset:
	for one: ShipPreset in all():
		if one.display_name == named or String(one.id) == named:
			return one
	return null


## What scaling an engine by `factor` does to its bulk.
##
## Its own function because **a blurb was written by hand against it and
## got it wrong**: a preset advertised as "50% heavier" at a thrust factor
## of 1.75 is 52.5% heavier, because the share is applied to the increase
## rather than to the whole. Now the sentence is computed from the same
## expression the engine is, so the two cannot disagree again.
static func bulk_factor(scale: float) -> float:
	return 1.0 + (scale - 1.0) * BULK_SHARE


## The sentence that goes with a scaled preset, in the figures it will
## actually fly with. Called by `ShipPreset.caption`.
static func scaled_blurb(factor: float) -> String:
	return "the same layout, every engine %.0f%% stronger and %.1f%% heavier" % [
		(factor - 1.0) * 100.0, (bulk_factor(factor) - 1.0) * 100.0,
	]


## Co ten preset stawia i gdzie, na tym kadlubie.
##
## Three callers needed this walk and would otherwise each do it:
## `apply` to build the mounts, `balance_of` to weigh them, and the
## preset dock to draw them. It is the whole of what binding by kind
## means -- one entry fills every place of its kind, a drive splits
## across the pair either side of the centre line -- and three copies of
## that rule would be three chances to disagree about what a preset is.
##
## Each entry is `{name, at, turn, kind, socket, engine, scale, share}`.
## `share` is the fraction of the engine this mount gets, which is less
## than one only for a drive split over several places.
static func placements(hull: HullData, wanted: ShipPreset) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if hull == null or wanted == null:
		return out
	var places: Dictionary = places_of(hull)
	for fit: MountFit in wanted.mounts:
		if fit == null or fit.engine == null:
			continue
		# A named place wins over a kind, for the one mount a kind cannot
		# describe: the forward-facing nozzle on the twin-gimbal ship.
		if not String(fit.place).is_empty():
			out.append(_placement(
				wanted, fit, String(fit.place),
				places.get(String(fit.place), {}), places, 1.0,
			))
			continue
		var filled: Array[Dictionary] = []
		for slot: Dictionary in hull.slots_of(fit.kind):
			# A drive is split across the pair either side of the centre
			# line, or sits whole on the centre one.
			if fit.kind != HullData.SLOT_DRIVE:
				filled.append(slot)
			elif is_zero_approx((slot["at"] as Vector2).x) == fit.centered:
				filled.append(slot)
		var share: float = 1.0
		if fit.kind == HullData.SLOT_DRIVE and not filled.is_empty():
			share = 1.0 / float(filled.size())
		for slot: Dictionary in filled:
			out.append(_placement(
				wanted, fit, String(slot["name"]), slot, places, share,
			))
	return out


static func _placement(
	wanted: ShipPreset, fit: MountFit, named: String,
	place: Dictionary, places: Dictionary, share: float
) -> Dictionary:
	# The hull decides where it sits and which way it faces; the preset's
	# own `at` and `turn` are read only for a place the hull does not
	# offer.
	return {
		"name": named,
		"at": place["at"] if not place.is_empty() else fit.at,
		"turn": float(place["turn"]) if not place.is_empty() else fit.turn,
		"kind": place.get("kind", fit.kind),
		"socket": socket_for(places, fit),
		"engine": fit.engine,
		"scale": wanted.scale_of(fit),
		"share": share,
	}


## Gdzie wypadnie srodek masy tego kadluba z tym wyposazeniem, i co z
## tego wynika dla sterowania.
##
## From data alone -- no `Ship`, no physics -- because the hull editor has
## to answer it while a slot is still under the cursor. The arithmetic is
## `Ship.mass_budget`, the same one the flying ship uses, so the dock
## cannot draw a centre of mass the ship does not have.
##
## Beyond `mass`, `centre` and `inertia` it returns the three figures that
## decide whether a hand-drawn hull flies straight. All of them are
## measured against the **centre of mass**, which is the thing a designer
## cannot see and the reason these are worth drawing:
##
##  - `torque_gap`: how far the torque cross is from balancing, in pixels
##    of arm. Zero means the forward jets and the aft jets have equal arms
##    about the centre of mass, which is the whole of what makes them a
##    couple. The stock dart's aft pair sits at y=13.5 and not at 10
##    exactly because of this.
##  - `strafe_gap`: how far the strafe row sits from the centre of mass.
##    Zero means a strafe burn is pure sideways; 2.5 px of offset is a
##    third of a radian per second of unasked-for spin.
##  - `leg_drop`: how far the lowest foot hangs below the hull's own
##    underside. Every shipped hull is between 0 and 3; ten leaves the
##    ship resting twenty-five pixels above the ground.
static func balance_of(hull: HullData, wanted: ShipPreset) -> Dictionary:
	var out: Dictionary = {
		"mass": 0.0, "centre": Vector2.ZERO, "inertia": 0.0,
		"torque_gap": 0.0, "strafe_gap": 0.0, "leg_drop": 0.0,
	}
	if hull == null or hull.outline.size() < 3:
		return out

	var parts: Array[Dictionary] = []
	if wanted != null:
		for spot: Dictionary in placements(hull, wanted):
			var engine: EngineData = spot["engine"]
			parts.append({
				"at": spot["at"],
				"mass": (
					engine.bulk * bulk_factor(float(spot["scale"]))
					* EngineMount.MASS_PER_BULK * float(spot["share"])
				),
			})
		for bay: BayFit in wanted.bays:
			if bay != null and bay.installed != null:
				parts.append({"at": bay.at, "mass": bay.installed.bulk})

	var budget: Dictionary = Ship.mass_budget(
		hull.outline, Ship.mass_of_outline(hull.outline), parts
	)
	out["mass"] = budget["mass"]
	out["centre"] = budget["centre"]
	out["inertia"] = budget["inertia"]

	var centre: Vector2 = budget["centre"]
	# The worst mismatch between a forward jet's arm and an aft one's.
	var forward: float = 0.0
	var aft: float = 0.0
	for slot: Dictionary in hull.slots_of(HullData.SLOT_TORQUE):
		var arm: float = (slot["at"] as Vector2).y - centre.y
		if arm < 0.0:
			forward = minf(forward, arm)
		else:
			aft = maxf(aft, arm)
	out["torque_gap"] = absf(absf(forward) - absf(aft))

	for slot: Dictionary in hull.slots_of(HullData.SLOT_STRAFE):
		out["strafe_gap"] = maxf(
			float(out["strafe_gap"]), absf((slot["at"] as Vector2).y - centre.y)
		)

	for leg: Vector2 in hull.legs:
		out["leg_drop"] = maxf(float(out["leg_drop"]), leg.y - hull.bounds().end.y)
	return out


## Rebuilds a ship as one of these, in place.
##
## In place rather than by swapping in another scene, because everything
## pointing at this ship -- the camera, the HUDs, the editor, the streaming
## manager -- would have to be told, and a sandbox that invalidates half
## the game's references is a sandbox that crashes instead of teaching.
static func apply(ship: Ship, wanted: ShipPreset) -> bool:
	# **Checked before anything comes off.** This used to strip the engines
	# and the guns and then look for the hull, so a preset naming a hull
	# that does not exist left the pilot with a bare fuselage and an error
	# in the log -- a refit that fails has to fail having changed nothing,
	# because the ship it was refitting is the one the player is flying.
	var fault: String = fault_in(wanted)
	if not fault.is_empty():
		# Reported and returned, not pushed as an engine error. A refused
		# refit is a refused operation carrying its reason -- the same
		# shape as `JumpController.blocked_by` -- and the guard against a
		# malformed preset shipping is the test that walks `all()` and
		# asks `fault_in` of each, which fails a build rather than
		# printing a line into a log nobody reads.
		print("refit refused: %s" % fault)
		return false

	var scene: PackedScene = load(MOUNT_SCENE) as PackedScene
	var hull: HullData = wanted.hull

	for child: Node in ship.get_children():
		if child is EngineMount or child is Hardpoint or child is ModuleBay:
			ship.remove_child(child)
			child.queue_free()

	# Where the hull says each of its places is, by name. A preset names a
	# role -- NoseLeftTorque, StrafeRightThruster -- and the hull decides
	# where that lands, exactly as it already did for drives and guns.
	for spot: Dictionary in placements(hull, wanted):
		var mount: EngineMount = scene.instantiate() as EngineMount
		mount.name = String(spot["name"])
		mount.size = float(spot["socket"])
		mount.position = spot["at"]
		mount.rotation = float(spot["turn"])
		mount.thrust_direction = Vector2.UP
		mount.installed = _engine_share(
			spot["engine"], float(spot["scale"]), float(spot["share"])
		)
		ship.add_child(mount)

	# Guns go in the hull's hardpoints and nowhere else. The preset says
	# which weapons it carries, in order; the hull says where the places
	# are, and the weapons fill them front first, then the sides, then
	# astern.
	var next_weapon: int = 0
	for slot: Dictionary in hull.slots():
		# Every place that takes an **engine** is skipped, not just the
		# drives: this read `== SLOT_DRIVE` until the hull learned about
		# torque jets, strafe thrusters and the nose reverse, and then
		# quietly fitted a gun to each of the seven.
		if SOCKET_FOR.has(slot["kind"]):
			continue
		var gun: Hardpoint = _hardpoint(slot)
		if next_weapon < wanted.guns.size():
			gun.weapon = wanted.guns[next_weapon]
			next_weapon += 1
		ship.add_child(gun)
	if next_weapon < wanted.guns.size():
		push_warning("preset %s has %d more guns than the hull has hardpoints" % [
			wanted.display_name, wanted.guns.size() - next_weapon,
		])

	_add_bays(ship, wanted)

	# The hull is named, not described. It used to be an outline, a hold
	# and a pair of feet written out in every preset -- three of which flew
	# the same dart and had to agree about it by hand.
	ship.hull = hull
	ship.look_key = wanted.skin_key()
	ship.hull_outline = hull.outline
	# Zero on a hull means "this shape does not say", which the hull's own
	# field documents and this used to ignore -- a refit onto one of the
	# creative-tool shapes handed the ship a hold of nothing.
	if hull.cargo_capacity > 0.0:
		ship.hull_cargo_capacity = hull.cargo_capacity
	if ship.gear != null and not hull.legs.is_empty():
		ship.gear.legs = hull.legs.duplicate()
	var drawn: Polygon2D = ship.get_node_or_null("Hull") as Polygon2D
	if drawn != null:
		drawn.polygon = ship.hull_outline

	add_hull_slots(ship, hull)

	ship.collect_parts()
	ship._build_contact_points()
	ship._build_collision_shape()
	ship.rebuild_control_groups(false)
	return true


## The module bays this ship has, built from the preset.
##
## These were five hand-placed nodes in `ship.tscn`, which meant every
## ship in the game had identical module capacity and no way to say
## otherwise -- the interceptor described as "a hold worth nothing"
## carried exactly the freighter's generator, scanner, drive and tank.
##
## Numbered rather than named by kind, because a bay has no kind (see
## `ModuleBay`): what distinguishes `Bay2` from `Bay3` is how big it is.
## The numbering is the preset's order, so it is stable for a given ship,
## which is what `SaveGame` keys the fitted modules on.
##
## What goes in is a **copy**. The preset's own `installed` resources are
## shared by every ship built from it, and a module that takes damage or
## gets an affix rolled onto it would otherwise write through into the
## catalogue for the rest of the session.
static func _add_bays(ship: Ship, wanted: ShipPreset) -> void:
	for i: int in range(wanted.bays.size()):
		var fit: BayFit = wanted.bays[i]
		var bay: ModuleBay = ModuleBay.new()
		bay.name = "Bay%d" % (i + 1)
		bay.size = fit.size
		bay.position = fit.at
		if fit.installed != null:
			bay.installed = fit.installed.duplicate() as ModuleData
		ship.add_child(bay)


## What is wrong with this preset, or "" when nothing is.
##
## One function, so `apply` and anything that wants to offer a preset
## cannot come to different conclusions about whether it is usable -- the
## same shape as `JumpController.blocked_by`. It checks everything `apply`
## is about to read and nothing else.
##
## Shorter than it was, because most of what it used to check is now the
## resource system's job: a preset cannot name an engine or a weapon that
## does not exist, since it holds the resource rather than a key into a
## table.
static func fault_in(wanted: ShipPreset) -> String:
	if wanted == null:
		return "no preset at all"
	var title: String = wanted.display_name
	if title.is_empty():
		return "a preset with no name"
	if wanted.hull == null:
		return "%s names no hull" % title
	# What the hull offers, by name, so a mount can be checked against it
	# rather than against a rule written out twice.
	var offered: Dictionary = places_of(wanted.hull)
	for fit: MountFit in wanted.mounts:
		if fit == null:
			return "%s has a mount that is not there" % title
		var named: String = String(fit.place)
		var describes: String = named if not named.is_empty() else String(fit.kind)
		if named.is_empty() and String(fit.kind).is_empty():
			return "%s has a mount that fills neither a kind nor a place" % title
		if fit.engine == null:
			return "%s has nothing to put in %s" % [title, describes]
		# A named place needs a position of its own only where the hull
		# does not offer it. A kind never does: the hull has the places.
		if not named.is_empty() and not offered.has(named) and fit.at.is_zero_approx():
			return "%s has a mount %s with nowhere to be" % [title, named]
		if socket_for(offered, fit) <= 0.0:
			return "%s has a mount %s with no socket size" % [title, describes]
	for gun: WeaponData in wanted.guns:
		if gun == null:
			return "%s carries a gun that is not there" % title
	for fit: BayFit in wanted.bays:
		if fit == null:
			return "%s has a bay that is not there" % title
		if fit.size <= 0.0:
			return "%s has a bay with no room in it" % title
		if fit.installed == null:
			continue
		# Asked of the bay's own rule rather than repeated here, so the
		# preset and the socket cannot disagree about what fits.
		if not ModuleBay.is_bay_module(fit.installed):
			return "%s puts a %s in a module bay, and that has its own socket" % [
				title, fit.installed.display_name,
			]
		if fit.installed.bulk > fit.size:
			return "%s puts a %s of %.2f into a bay of %.2f" % [
				title, fit.installed.display_name, fit.installed.bulk, fit.size,
			]
	return ""


## One part of an engine, for a drive that is split over several mounts.
static func _engine_share(base: EngineData, scale: float, share: float) -> EngineData:
	var whole: EngineData = _engine(base, scale)
	# A share of one is the whole engine, and handing back the shared
	# resource rather than a copy of it is what every mount that is not
	# a split drive used to get.
	if whole == null or is_equal_approx(share, 1.0):
		return whole
	var part: EngineData = whole.duplicate() as EngineData
	part.max_thrust *= share
	part.bulk *= share
	return part


## Gives the ship every place the hull offers that it does not already have:
## empty drive mounts and empty hardpoints, named by the hull.
##
## A place is filled when a node of its name exists, so the same call serves a
## preset that was just built and a ship that came with only some of them.
static func add_hull_slots(ship: Ship, hull: HullData) -> void:
	var scene: PackedScene = load(MOUNT_SCENE) as PackedScene
	for slot: Dictionary in hull.slots():
		if ship.has_node(NodePath(String(slot["name"]))):
			continue
		if SOCKET_FOR.has(slot["kind"]):
			# Every engine place the hull offers and the preset left
			# empty, drives included: a socket with nothing in it is the
			# ship telling the pilot where something could go.
			var mount: EngineMount = scene.instantiate() as EngineMount
			mount.name = String(slot["name"])
			mount.size = float(SOCKET_FOR[slot["kind"]])
			mount.position = slot["at"]
			mount.rotation = float(slot["turn"])
			mount.thrust_direction = Vector2.UP
			ship.add_child(mount)
		else:
			ship.add_child(_hardpoint(slot))


## An empty hardpoint at one of the hull's places.
static func _hardpoint(slot: Dictionary) -> Hardpoint:
	var gun: Hardpoint = Hardpoint.new()
	gun.name = String(slot["name"])
	gun.position = slot["at"]
	gun.rotation = float(slot["turn"])
	return gun


## An engine, scaled if the preset asked for a bigger one.
##
## Duplicated before scaling: the resources are shared by every preset
## that names them, and scaling the original would make every later ship
## in the session inherit the change.
static func _engine(base: EngineData, scale: float) -> EngineData:
	if base == null:
		return null
	if is_equal_approx(scale, 1.0):
		return base
	var copy: EngineData = base.duplicate() as EngineData
	copy.max_thrust *= scale
	# Heavier as well as stronger. Scaling only the thrust would be free
	# power, which is the one thing a sandbox must not quietly hand out.
	copy.bulk *= bulk_factor(scale)
	return copy
