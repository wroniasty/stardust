class_name Projectile
extends Area2D
## Base class for anything a weapon throws.
##
## One type exists for now (a plain projectile). M2 turns the numbers into a
## Resource so the loot generator can roll them; the flight and impact logic
## stays here (see IDEAS.md section 4).
##
## Terrain is not a physics body, so the engine cannot report a hit against it.
## The projectile samples the crust along the segment it is about to travel,
## which also solves tunnelling: at 600 px/s a tick covers 10 px while a terrain
## texel is 1.5 px, so a single end-of-tick test would shoot straight through
## thin rock.
##
## Area2D rather than Node2D because ships and stations *are* physics bodies and
## M1.7 needs projectiles to hit the hull. Monitoring stays off until then.

## Distance between terrain samples along the flight path, in pixels. Must stay
## below the terrain texel size or thin walls can be missed.
const SAMPLE_STEP: float = 1.0

## Emitted wherever the projectile stops. `point` is in world space.
signal impacted(point: Vector2, damage: float)

## Seconds before an unspent round removes itself.
@export var lifetime: float = 4.0

## Damage dealt to a hull, on the same 0..1 scale as hull integrity. Twelve
## hits to kill a healthy ship.
@export var damage: float = 0.08

## Seconds before the round will hit the ship that fired it, as a floor.
##
## Not a blanket exemption: the muzzle sits inside the firing hull's own
## contact radius, so without a moment's grace every shot would kill the
## shooter -- but a round that loops back around a planet later absolutely
## should hit.
##
## A time alone is not enough now that guns turn and hulls vary. A turret
## firing backwards sends its round the length of the ship, and a slow
## missile crossing a large hull takes longer than any fixed grace: at
## 150 px/s across a 72 px hull that is half a second against this 0.2.
## So the real rule is below -- the time only covers the case where the
## shooter has gone.
@export var arming_time: float = 0.2

## Extra clearance past the hull before a round is live, in pixels.
const ARMING_CLEARANCE: float = 4.0

## Whether this round has ever been clear of the ship that fired it.
##
## Once, not currently: a round that has left is armed for good, so one that
## loops back around a planet comes home live. Being inside the hull again
## later is the shooter's own doing.
var _armed: bool = false

## Radius of the hole punched in the crust on impact.
@export var crater_radius: float = 14.0

## How many more things this round survives before it stops. Set by the
## hardpoint from the mods plugged into it: a behaviour is data the round
## reads at spawn, not another projectile scene, or every combination of
## mods would be a new file (IDEAS.md section 14).
var pierces: int = 0

## Radius over which the impact hurts things it did not actually hit, and
## the share of the damage the outermost edge gets. Zero when no mod asked
## for it, which is the common case and costs nothing.
var blast_radius: float = 0.0
const BLAST_EDGE_SHARE: float = 0.25

## Travel in world space, set by the hardpoint that fired it.
var velocity: Vector2 = Vector2.ZERO

## Who fired it, ignored until the round is armed.
var shooter: Node = null

var _planet: Planet = null
var _age: float = 0.0

## The aim cursor does **not** know about any of this, and that is a
## decision rather than an omission.
##
## It reports whether the gun can bear on the point, which is a question
## about the mount, and it draws no predicted path. Leading for gravity is
## the pilot's job: a cursor that solved the arc would turn every shot
## into pointing at a marker the game had already worked out, and the
## whole reason rounds fall is to give the pilot something to be good at.
## See IDEAS.md, "Pociski spadaja".


## How far a round lights the ground it passes over, in pixels, and how
## hard. Small and brief: a tracer is a spark, and a spark that floodlit
## the landscape would say the wrong thing about how much damage it does.
const GLOW_REACH: float = 55.0
const GLOW_STRENGTH: float = 0.6

## What this round is painted, and the colour of the light it throws.
##
## One field for both, because a glow should always be traceable to the
## thing casting it. It used to be read off the body polygon's colour,
## which worked right up until the body stopped being a polygon.
@export var tint: Color = Color(1.0, 0.86, 0.45)

## Which picture in `round.tres` this round wears. On the scene rather than
## in code, because what a round looks like is the scene's business -- and a
## test checks that every key here resolves to something.
@export var look_key: StringName = &"slug"

const ROUND_LOOKS: String = "res://resources/fx/looks/round.tres"

static var _looks: LookTable = null


## The table every round reads its picture from, loaded once.
##
## Cached rather than loaded per spawn. `load()` hits the resource cache
## after the first call and would probably be fine, but a round costs about
## seven microseconds and a dictionary lookup in the loader is a real share
## of that -- measured once already, and not worth measuring again.
static func looks() -> LookTable:
	if _looks == null:
		_looks = load(ROUND_LOOKS) as LookTable
	return _looks


func _ready() -> void:
	# Resolved once: a projectile lives for a few seconds and never outlives
	# the planet it was fired near. M3 will have to re-check as systems stream.
	_planet = Planet.nearest(get_tree(), global_position)
	body_entered.connect(_on_body_entered)
	# The round's own colour, so a glow always belongs to the thing that
	# is casting it rather than to a palette nobody can trace back.
	var body: StripSprite = get_node_or_null("Body") as StripSprite
	if body != null:
		body.show_strip(looks().pick(null, look_key))
		body.self_modulate = tint
	add_child(GlowLight.make(tint, GLOW_REACH, GLOW_STRENGTH))


func _physics_process(delta: float) -> void:
	_age += delta
	_check_armed()
	if _age >= lifetime:
		queue_free()
		return

	# Rounds fall. Everything else in the world already did -- the ship,
	# the crates, the line the predictor draws -- and a shell that flew
	# dead straight past a planet was the one thing in the game exempt
	# from the rule the whole game is about.
	#
	# Semi-implicit Euler, matching the solver and the predictor: the new
	# velocity moves this step. Three integrators disagreeing about the
	# same field is how a round ends up somewhere the line said it would
	# not.
	velocity += GravityWell.pull_at(get_tree(), global_position) * delta

	var start: Vector2 = global_position
	var step: Vector2 = velocity * delta

	var hit: Vector2 = _first_solid_along(start, step)
	if hit.is_finite():
		_impact(hit)
		return

	global_position = start + step
	rotation = velocity.angle() + PI * 0.5


## Walks the segment and returns the first point inside rock, or a non-finite
## vector when the path is clear.
func _first_solid_along(start: Vector2, step: Vector2) -> Vector2:
	if _planet == null:
		return Vector2.INF

	var samples: int = maxi(1, ceili(step.length() / SAMPLE_STEP))
	for i: int in range(1, samples + 1):
		var point: Vector2 = start + step * (float(i) / float(samples))
		if _planet.is_solid_at(point):
			return point
	return Vector2.INF


func _on_body_entered(body: Node2D) -> void:
	# Asked of what it can do rather than of what it is. See `Damage`:
	# a foe and a hull share nothing but being shootable, and the round
	# has no business knowing which of them it just hit.
	if body == shooter and not _armed:
		return
	if not Damage.deal(body, damage, "projectile"):
		return
	_impact(global_position)


func _impact(point: Vector2) -> void:
	global_position = point
	if _planet != null:
		_planet.carve(point, crater_radius)
	if blast_radius > 0.0:
		_blast(point)
	impacted.emit(point, damage)
	if pierces > 0:
		# Straight on through the hole it just made. Nudged past the crater
		# so the next tick does not find the same wall again and spend
		# another pierce on it.
		pierces -= 1
		global_position = point + velocity.normalized() * (crater_radius + SAMPLE_STEP)
		return
	queue_free()


## Hurts everything inside `blast_radius`, falling off with distance so that
## a near miss is worth less than a hit. Queried against the physics server
## rather than against a group, because what counts as damageable is whatever
## has a body here -- the same question the round already asks on contact.
func _blast(point: Vector2) -> void:
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = blast_radius
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.transform = Transform2D(0.0, point)
	query.collide_with_bodies = true

	for hit: Dictionary in space.intersect_shape(query, 16):
		var struck: Node2D = hit.get("collider") as Node2D
		if struck == null or not Damage.can_be_hurt(struck):
			continue
		var reach: float = clampf(
			struck.global_position.distance_to(point) / maxf(blast_radius, 0.0001), 0.0, 1.0
		)
		Damage.deal(struck, damage * lerpf(1.0, BLAST_EDGE_SHARE, reach), "blast")


## Arms the round once it is clear of the hull that fired it, or once the
## grace has run out with no shooter left to ask.
func _check_armed() -> void:
	if _armed:
		return
	var firing_ship: Ship = shooter as Ship
	if firing_ship == null or not is_instance_valid(firing_ship):
		_armed = _age >= arming_time
		return
	var clear: float = firing_ship.hull_extent() + ARMING_CLEARANCE
	_armed = global_position.distance_to(firing_ship.global_position) > clear
