class_name Hardpoint
extends Node2D
## A weapon mount on a ship: where a gun sits, which way it points, and how
## fast it can shoot.
##
## Same idea as ShipEngine: the node's own transform is the mount. Rotate the
## node in the editor and the gun points elsewhere, with no code to change.
##
## The hardpoint owns the trigger timing but not the trigger. The ship decides
## when to pull it, so an AI or an autopilot uses exactly the same path as the
## player (M5).
##
## The numbers live in the fitted WeaponData, not here: a mount is a place, and
## what stands in it is loot (M2).

## Direction the gun points in its own frame, matching the ship's nose.
const MUZZLE_DIRECTION: Vector2 = Vector2.UP

## What is bolted on. Empty mounts are normal -- a hull can carry more
## hardpoints than the pilot has guns for.
@export var weapon: WeaponData = null

## Weapon types this mount will take. Empty means anything, which is what a
## general purpose mount is; a missile rack lists what it can hold.
@export var accepts: Array[WeaponData.Type] = []

## Mods plugged into this weapon, at most `weapon.mod_slots` of them.
var mods: Array[ShotModData] = []

## The weapon as it actually fires, base times every mod. Rebuilt when a mod
## or the weapon changes and read at every shot, never recomputed per round.
var _effective: WeaponData = null
var _effective_energy: float = 0.0

var _cooldown: float = 0.0


## Advances the cooldown. Driven by the ship so the order is deterministic.
func tick(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)


func can_fire() -> bool:
	if _cooldown > 0.0 or weapon == null:
		return false
	# A beam has no projectile scene because nothing travels. Demanding one
	# meant a laser could never fire at all -- it failed this check every
	# tick and returned quietly, which is the worst way for a weapon to be
	# broken.
	return weapon.is_beam() or weapon.projectile_scene != null


## The weapon as it fires, with every mod folded in. The base weapon when
## nothing is plugged in, so the common case allocates nothing.
func effective() -> WeaponData:
	if _effective == null:
		_rebuild_effective()
	return _effective


## What one shot costs with the mods that are in it.
func energy_cost() -> float:
	if _effective == null:
		_rebuild_effective()
	return _effective_energy


## Plugs a mod in, if there is a slot free. Returns whether it went in.
func add_mod(mod: ShotModData) -> bool:
	if weapon == null or mod == null or mods.size() >= weapon.mod_slots:
		return false
	mods.append(mod)
	_rebuild_effective()
	return true


## Pulls one out and hands it back.
func remove_mod(index: int) -> ShotModData:
	if index < 0 or index >= mods.size():
		return null
	var mod: ShotModData = mods[index]
	mods.remove_at(index)
	_rebuild_effective()
	return mod


## Every behaviour the mods add, for the round to read at spawn.
func effects() -> Array[ShotModData.Effect]:
	var out: Array[ShotModData.Effect] = []
	for mod: ShotModData in mods:
		if mod.effect != ShotModData.Effect.NONE:
			out.append(mod.effect)
	return out


## Base times every mod, in any order: all of them are multipliers, and
## multiplication does not care. That is why order is allowed to be
## irrelevant rather than merely declared so.
func _rebuild_effective() -> void:
	if weapon == null:
		_effective = null
		_effective_energy = 0.0
		return
	if mods.is_empty():
		_effective = weapon
		_effective_energy = weapon.energy_cost
		return

	var combined: WeaponData = weapon.duplicate() as WeaponData
	var energy: float = weapon.energy_cost
	for mod: ShotModData in mods:
		combined.damage *= mod.damage_multiplier
		combined.rounds_per_second *= mod.rate_multiplier
		combined.spread_degrees *= mod.spread_multiplier
		combined.crater_radius *= mod.crater_multiplier
		combined.range_px *= mod.range_multiplier
		combined.muzzle_speed *= mod.speed_multiplier
		energy *= mod.energy_multiplier
	combined.energy_cost = energy
	_effective = combined
	_effective_energy = energy


## Whether this mount will take `candidate`. A mount that lists nothing takes
## anything; the check is here rather than in the loot generator so that a
## weapon found in the world can be offered against the ship that has to hold
## it (IDEAS.md section 4).
func can_fit(candidate: WeaponData) -> bool:
	if candidate == null:
		return false
	return accepts.is_empty() or accepts.has(candidate.type)


## Fits `candidate` if this mount will take it. Returns what was there before,
## so a swap in flight can hand the old gun back to the pilot.
func fit(candidate: WeaponData) -> WeaponData:
	if not can_fit(candidate):
		return candidate
	var previous: WeaponData = weapon
	weapon = candidate
	_cooldown = 0.0
	# The mods stay with the mount, not with the gun, but a new gun may have
	# fewer slots than the old one had filled.
	while mods.size() > weapon.mod_slots:
		mods.pop_back()
	_rebuild_effective()
	return previous


## Spawns one round into `container`. Returns it, or null if still cooling down.
##
## The round is parented to the world, never to the ship: a projectile must not
## inherit the ship's motion after it leaves the barrel.
func fire(carrier_velocity: Vector2, container: Node, shooter: Node = null) -> Projectile:
	if not can_fire() or container == null:
		return null
	var firing: WeaponData = effective()
	_cooldown = 1.0 / maxf(firing.rounds_per_second, 0.001)

	var spread: float = deg_to_rad(firing.spread_degrees)
	var aim: float = global_rotation + randf_range(-spread * 0.5, spread * 0.5)
	var direction: Vector2 = MUZZLE_DIRECTION.rotated(aim)

	if firing.is_beam():
		_fire_beam(firing, direction, container, shooter)
		return null

	var round_instance: Projectile = firing.projectile_scene.instantiate() as Projectile
	if round_instance == null:
		return null

	# The round carries the weapon's numbers rather than its own defaults: a
	# projectile scene is a chassis, and what it hits for is loot.
	round_instance.damage = firing.damage
	round_instance.crater_radius = firing.crater_radius
	round_instance.lifetime = firing.lifetime()
	round_instance.pierces = _pierces()
	# The weapon's own blast and the mods' both count; a shrapnel shell in an
	# AoE launcher should be worse than either alone.
	round_instance.blast_radius = maxf(firing.blast_radius, _blast_radius(firing))

	var missile: Missile = round_instance as Missile
	if missile != null:
		missile.thrust = firing.missile_thrust
		missile.turn_rate = firing.missile_turn_rate
		if firing.type == WeaponData.Type.HOMING_MISSILE:
			missile.target = Missile.find_target(global_position, shooter, get_tree())

	round_instance.shooter = shooter
	round_instance.global_position = global_position
	round_instance.velocity = direction * firing.muzzle_speed
	if firing.inherit_velocity:
		round_instance.velocity += carrier_velocity
	round_instance.rotation = round_instance.velocity.angle() + PI * 0.5

	container.add_child(round_instance)
	return round_instance


## How many extra things a round from this mount survives.
func _pierces() -> int:
	var total: int = 0
	for mod: ShotModData in mods:
		if mod.effect == ShotModData.Effect.PIERCE:
			total += mod.pierce_count
	return total


## How far an impact from this mount reaches beyond what it hit. Scaled off
## the crater so a bigger round blasts wider without a second number to tune.
func _blast_radius(firing: WeaponData) -> float:
	for mod: ShotModData in mods:
		if mod.effect == ShotModData.Effect.BLAST:
			return firing.crater_radius * 2.0
	return 0.0


## Resolves a laser along its ray: the first thing it meets takes the damage,
## and a line is left behind to show where it went.
##
## Range rather than lifetime, because nothing is travelling. Stepped at the
## same interval the terrain is sampled at, so a beam cannot slip through a
## wall a round would have hit.
func _fire_beam(
	firing: WeaponData, direction: Vector2, container: Node, shooter: Node
) -> void:
	var reach: float = firing.range_px
	var hit_at: Vector2 = global_position + direction * reach
	var planet: Planet = Planet.nearest(get_tree(), global_position)

	var struck: Ship = null
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(
		global_position, hit_at
	)
	query.collide_with_bodies = true
	if shooter is CollisionObject2D:
		query.exclude = [(shooter as CollisionObject2D).get_rid()]
	var body_hit: Dictionary = space.intersect_ray(query)
	if not body_hit.is_empty():
		hit_at = body_hit["position"]
		struck = body_hit.get("collider") as Ship

	if planet != null:
		var travelled: float = 0.0
		var limit: float = global_position.distance_to(hit_at)
		while travelled < limit:
			travelled += Projectile.SAMPLE_STEP
			var probe: Vector2 = global_position + direction * travelled
			if planet.is_solid_at(probe):
				hit_at = probe
				struck = null
				break

	if struck != null:
		struck.take_damage(firing.damage, "beam")
	elif planet != null and firing.crater_radius > 0.0:
		planet.carve(hit_at, firing.crater_radius)

	var line: Beam = Beam.new()
	line.from = global_position
	line.to = hit_at
	line.seconds = firing.beam_seconds
	container.add_child(line)
