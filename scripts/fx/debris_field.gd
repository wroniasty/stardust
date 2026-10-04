class_name DebrisField
extends Node2D
## Rzeczy odpryskujące: od uderzenia w kadłub i od kopania w gruncie.
##
## Two events, one shape. Something gives way at a point, and bits of it
## leave in a hurry -- the difference between a hull strike and a shell
## going into rock is which way they leave and how bright they are, which
## is two arguments rather than two systems.
##
## Both are already announced. `Ship.hull_impact` has carried the arrival
## speed since M1 and `Planet.carved` the point and the radius since M1.3;
## neither had a listener until now. Nothing in the simulation learns that
## this exists.

## How many bursts can overlap. A pool, because a game that allocates an
## emitter per impact allocates an emitter per impact -- and the one place
## that is certain to happen at once is a ship skidding along a slope.
const BURSTS: int = 8

## Impact speed at which a strike throws everything it has. Shared with
## `CameraShake.REFERENCE_SPEED` in spirit rather than by import: that one
## is about how hard the view is thrown and this is about how much comes
## off the hull, and tying them together would be tying two tunings to one
## number for no reason beyond their happening to agree today.
const REFERENCE_SPEED: float = 300.0

## Particles at full. Few: this is grit coming off a sixteen pixel ship,
## and a shower reads as an explosion.
const MOST_SPARKS: int = 14

## How big one bit of debris is, in design pixels.
##
## One range for every kind, converted to a scale from whatever strip is
## being thrown. A chip off the hull and a grain out of a crater are the
## same size on screen, so this is one decision rather than one per
## emitter -- and a replaced texture does not drag a retuned number behind
## it, which the first version did: the dot is authored at 24 texels and
## the chips at 9, so the single scale range that suited one of them made
## the other invisible.
const GRIT: Vector2 = Vector2(1.5, 4.0)

## And how fast they leave, in design pixels a second.
const SPARK_SPEED: Vector2 = Vector2(60.0, 170.0)

## Dust thrown by a shot going into rock. Slower and more of it: rock does
## not spark, it crumbles.
const MOST_GRAINS: int = 20
const GRAIN_SPEED: Vector2 = Vector2(25.0, 90.0)

## What the chips are tinted to.
##
## Over one, which looks wrong written down and is right on screen. The
## strip is authored at the plate's own value (`METAL`, a mid grey), and
## a bit knocked off a plate is a bit **catching the light** -- tinted
## down it lands within a shade of the sky and reads as a smudge on the
## monitor, which is what the first pass of this looked like.
const CHIP_TINT: Color = Color(1.35, 1.30, 1.24)
const GRAIN_TINT: Color = Color(1.45, 1.30, 1.10)
const SPARK_TINT: Color = Color(1.00, 0.85, 0.55)

## How long either lives.
const SPARK_LIFE: float = 0.45
const GRAIN_LIFE: float = 0.9

## How high the exhaust still stirs the ground, in design pixels. Beyond
## this a landing burn is a burn in mid-air and the ground does not know
## about it.
const DUST_REACH: float = 130.0

## Most grains of ground dust at once, and how fast they come up. Slower
## than anything blown out of a crater: this is dust being pushed, not
## rock being broken. More of them than either burst, because this one is
## continuous -- it has a whole lifetime of them in the air at once rather
## than one instant's worth, and a trickle reads as dirt on the monitor.
const MOST_DUST: int = 40
const DUST_SPEED: Vector2 = Vector2(18.0, 55.0)
const DUST_LIFE: float = 1.1

## How wide a patch of ground the wash disturbs, in design pixels.
##
## A strip rather than a point, and narrower than the ship: the exhaust
## arrives in a cone and the ground it reaches is a patch, so dust coming
## out of one spot under a sixteen pixel hull reads as a leak.
const DUST_PATCH: float = 9.0

## How quickly a grain gives up, in pixels a second a second. Dust pushed
## sideways by exhaust slows and settles; it does not sail off.
const DUST_DRAG: float = 45.0

## Below this the cloud is not worth drawing. A ship high up in thin air
## on a quarter throttle multiplies three small numbers together, and the
## result is a few grains a second that read as dirt on the screen.
const DUST_FAINTEST: float = 0.02

@export var ship_path: NodePath

var _ship: Ship = null
var _pool: Array[GPUParticles2D] = []
var _next: int = 0

var _spark: SpriteStrip = null
var _grain: SpriteStrip = null

## Alpha against age, shared by everything here. Without it a grain is at
## full strength for its whole life and then gone between two frames,
## which reads as the effect being switched off rather than as dust
## settling -- and at a fortieth of a second it is a flicker, which is
## the one thing a pixel screen shows most clearly.
var _fade: CurveTexture = null

## The cloud a landing burn raises, which is continuous rather than a
## burst and so is not in the pool.
var _dust: GPUParticles2D = null


func _ready() -> void:
	_ship = get_node_or_null(ship_path) as Ship
	var dying: Curve = Curve.new()
	dying.add_point(Vector2(0.0, 1.0))
	dying.add_point(Vector2(0.65, 0.85))
	dying.add_point(Vector2(1.0, 0.0))
	_fade = CurveTexture.new()
	_fade.curve = dying
	var motes: LookTable = load("res://resources/fx/looks/particle.tres") as LookTable
	if motes != null:
		_spark = motes.pick(null, &"dot")
		_grain = motes.pick(null, &"debris")
	for i: int in range(BURSTS):
		var pooled: GPUParticles2D = GPUParticles2D.new()
		pooled.emitting = false
		pooled.one_shot = true
		pooled.local_coords = false
		# All at once. A one-shot emitter spreads its particles over the
		# lifetime by default, which for a burst means a trickle: the
		# first version showed four grains of the eleven it had asked for,
		# because the other seven had not left yet.
		pooled.explosiveness = 1.0
		var leaving: ParticleProcessMaterial = ParticleProcessMaterial.new()
		leaving.alpha_curve = _fade
		pooled.process_material = leaving
		pooled.material = CanvasItemMaterial.new()
		add_child(pooled)
		_pool.append(pooled)

	_dust = GPUParticles2D.new()
	_dust.emitting = false
	_dust.local_coords = false
	_dust.texture = _grain.texture if _grain != null else null
	_dust.lifetime = DUST_LIFE
	_dust.amount = MOST_DUST
	_dust.material = _chip_sheet(_grain)
	var raised: ParticleProcessMaterial = ParticleProcessMaterial.new()
	raised.alpha_curve = _fade
	_sprinkle(raised, _grain)
	raised.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	raised.emission_box_extents = Vector3(DUST_PATCH, 1.0, 1.0)
	raised.damping_min = DUST_DRAG * 0.5
	raised.damping_max = DUST_DRAG
	raised.spread = 70.0
	raised.initial_velocity_min = DUST_SPEED.x
	raised.initial_velocity_max = DUST_SPEED.y
	raised.gravity = Vector3.ZERO
	raised.color = Color(GRAIN_TINT, 0.75)
	_dust.process_material = raised
	add_child(_dust)

	if _ship != null:
		_ship.hull_impact.connect(_on_hull_impact)
	# Planets come and go with the streaming, so the connection is made as
	# each one wakes rather than once at startup -- a planet built two
	# systems later would otherwise dig in silence.
	var manager: Node = get_node_or_null("/root/StreamingManager")
	if manager != null and manager.has_signal("body_awake"):
		manager.body_awake.connect(_on_body_awake)
	for planet: Node in get_tree().get_nodes_in_group(GravityWell.GROUP):
		_watch(planet)


func _on_body_awake(_body: SystemBody, node: Node2D) -> void:
	_watch(node)


func _watch(node: Node) -> void:
	var planet: Planet = node as Planet
	if planet != null and not planet.carved.is_connected(_on_carved):
		planet.carved.connect(_on_carved)


## Shows or hides the layer, and keeps the landing cloud up to date.
func _physics_process(_delta: float) -> void:
	# One switch for the whole layer, thrown at the node rather than inside
	# every decision below -- the same move `Soundscape` makes at the master
	# bus, for the same two reasons. It catches a burst already in flight,
	# which a gate at the call site would not; and it leaves everything
	# underneath it ungated and therefore measurable headless.
	visible = Presentation.is_on()
	if not visible:
		if _dust != null:
			_dust.emitting = false
		return
	stir()


## How hard the exhaust is working the ground right now, 0..1, with the
## cloud set to match.
##
## Three things have to be true at once and each kills it on its own: the
## ground has to be close enough for the exhaust to reach, there has to be
## air for the dust to hang in, and something has to actually be blowing
## downwards. A ship hovering with its engines shut raises nothing, and
## neither does one burning hard over an airless moon.
##
## Drawn at the ground rather than at the nozzles, because that is where
## the dust is: it is the surface being disturbed, not the engine making
## smoke.
##
## Ungated and returning its answer, like `ShipSkin.paint()` and
## `CameraShake.throw()` before it: the gate belongs to the tick above, and
## a headless test that could only call the gated version would be
## measuring a cloud that had never been asked for.
func stir() -> float:
	var well: GravityWell = (
		null if _ship == null
		else GravityWell.local_at(get_tree(), _ship.global_position)
	)
	if well == null or not well.has_ground():
		return _raise(Vector2.UP, Vector2.ZERO, 0.0)

	# The drawn position again: the cloud sits under the ship, and
	# "under the ship" means under where the pilot can see it.
	var hull_at: Vector2 = _ship.drawn_position()
	var up: Vector2 = (hull_at - well.global_position).normalized()
	var height: float = well.height_above_terrain(hull_at)
	var closeness: float = 1.0 - clampf(height / DUST_REACH, 0.0, 1.0)
	# The ground directly below, found by walking back down the height the
	# well just reported rather than out to the nominal radius -- on a world
	# with mountains those are different places, and the dust belongs at the
	# one the ship is actually hovering over.
	var ground: Vector2 = hull_at - up * maxf(height, 0.0)
	return _raise(
		up, ground, closeness * clampf(_ship.air_density, 0.0, 1.0) * _downwash(up)
	)


## Points the cloud and sets how much of it there is. Returns the share it
## was given, so `stir()` is a one-liner either way.
func _raise(up: Vector2, at: Vector2, share: float) -> float:
	if _dust == null:
		return share
	_dust.emitting = share > DUST_FAINTEST
	if _dust.emitting:
		_dust.global_position = at
		# The node is turned so its own up is the planet's, and the patch
		# and the direction are then stated in its frame. Simpler than
		# rotating a box by hand, and it keeps "up" meaning one thing.
		_dust.global_rotation = up.angle() - Vector2.UP.angle()
		var how: ParticleProcessMaterial = _dust.process_material
		how.direction = Vector3(0.0, -1.0, 0.0)
		_dust.amount_ratio = clampf(share, 0.0, 1.0)
	return share


## How hard the ship is blowing at the ground, 0..1.
##
## Weighted twice, by direction and by size, and both matter. Direction,
## because a ship strafing sideways two metres up is not blasting the
## surface and counting any engine that is lit would have it raising dust
## it is not causing. Size, because the first version divided by the
## engines facing the right way and so read a single attitude thruster
## nudging the nose as a full landing burn -- the ratio was right and the
## magnitude had gone.
##
## One against the strongest engine fitted, because a landing burn *is*
## the main drive: that is the thing the tuning should read as full, and
## a ship with four spare thrusters should not raise less dust than the
## same hull without them.
func _downwash(up: Vector2) -> float:
	var strongest: float = 0.0
	var pushed: float = 0.0
	for engine: EngineInstance in _ship.engines:
		strongest = maxf(strongest, engine.data.max_thrust)
		# Pushing away from the planet is what throws exhaust at it, so the
		# dot is taken against the thrust and not against the plume. And in
		# the world's frame: `thrust_direction()` is the ship's.
		var pushes: Vector2 = engine.thrust_direction().rotated(_ship.global_rotation)
		pushed += (
			engine.exhaust_flow() * engine.data.max_thrust * maxf(pushes.dot(up), 0.0)
		)
	return 0.0 if strongest <= 0.0 else clampf(pushed / strongest, 0.0, 1.0)


## Grit off the hull, thrown back along the way the ship was going.
func _on_hull_impact(impact_speed: float, _damage: float) -> void:
	var share: float = clampf(impact_speed / REFERENCE_SPEED, 0.0, 1.0)
	if share <= 0.05 or _ship == null:
		return
	# Away from the direction of travel, because that is the direction the
	# thing it hit pushed back in.
	var away: Vector2 = -_ship.linear_velocity.normalized()
	if away.is_zero_approx():
		away = Vector2.UP
	# Where the hull is **drawn**, not where it has got to. A burst
	# placed from `global_position` appears up to a tick of travel
	# ahead of the ship it came off -- thirty pixels at 1800 px/s,
	# which reads as a second ship shedding sparks.
	var off_the_hull: Vector2 = _ship.drawn_position()
	# Two throws, not one. ASSETLIST has both a hot additive dot and a
	# three frame strip of chips, and a strike is both: the light comes
	# off instantly and the pieces it lit are still there afterwards.
	# Which is also why the chips outlive the sparks.
	burst(
		off_the_hull, away, _spark,
		int(ceilf(MOST_SPARKS * share)), SPARK_SPEED * share, SPARK_LIFE,
		SPARK_TINT
	)
	burst(
		off_the_hull, away, _grain,
		int(ceilf(MOST_SPARKS * 0.5 * share)), SPARK_SPEED * share * 0.6, GRAIN_LIFE,
		CHIP_TINT
	)


## Dust out of a fresh hole, thrown along the local up.
##
## Up, not outwards from the shot: rock blown out of a crater leaves along
## the surface normal, and on a round world that is the way away from the
## centre -- which is also the way it will fall back.
func _on_carved(point: Vector2, radius: float) -> void:
	var well: GravityWell = GravityWell.local_at(get_tree(), point)
	var up: Vector2 = Vector2.UP
	if well != null:
		up = (point - well.global_position).normalized()
	var share: float = clampf(radius / 40.0, 0.2, 1.5)
	burst(
		point, up, _grain,
		int(ceilf(MOST_GRAINS * minf(share, 1.0))), GRAIN_SPEED * share, GRAIN_LIFE,
		GRAIN_TINT
	)


## Fires one burst from the pool. Returns whether there was anything to
## throw, which is what the tests read: "did you see that" does not work
## headless any more than "did you hear that" did.
func burst(
	at: Vector2,
	away: Vector2,
	strip: SpriteStrip,
	count: int,
	speed: Vector2,
	life: float,
	tint: Color,
) -> bool:
	if count <= 0 or strip == null or not strip.is_valid():
		return false
	var shot: GPUParticles2D = _pool[_next % maxi(_pool.size(), 1)]
	_next += 1

	var how: ParticleProcessMaterial = shot.process_material
	how.direction = Vector3(away.x, away.y, 0.0)
	# Wide, because debris does not come off in a beam. Not a full circle
	# either: the side that was hit is the side things leave from.
	how.spread = 55.0
	how.initial_velocity_min = speed.x
	how.initial_velocity_max = speed.y
	how.gravity = Vector3.ZERO
	how.color = tint
	_sprinkle(how, strip)

	shot.material = _chip_sheet(strip)
	shot.texture = strip.texture
	shot.texture_filter = Art.WORLD_FILTER
	shot.amount = maxi(count, 1)
	shot.lifetime = life
	shot.global_position = at
	shot.restart()
	shot.emitting = true
	return true


## Sizes the grains, and hands each one its own frame of the strip.
##
## Both are the strip's business rather than the caller's. The size comes
## from `GRIT` divided by how the strip was authored, so the same wanted
## size works for a 24 texel dot and a 9 texel chip; the frame comes from
## a random animation offset held still, which is what a strip of three
## chips is for -- without it every grain in the burst is the same chip,
## and a burst of one chip repeated reads as a tiling error.
##
## Not how they end, though. That is set once when the emitter is built,
## because it is a property of this field rather than of an emitter having
## been fired at least once -- set here, it left the emitters nobody had
## reached yet snapping out instead of fading, which is a fault that first
## shows on the ninth impact of a session.
func _sprinkle(how: ParticleProcessMaterial, strip: SpriteStrip) -> void:
	if strip == null or not strip.is_valid():
		return
	var frame: Vector2i = strip.frame_size()
	var unit: float = float(maxi(maxi(frame.x, frame.y), 1))
	how.scale_min = GRIT.x / unit
	how.scale_max = GRIT.y / unit
	how.anim_speed_min = 0.0
	how.anim_speed_max = 0.0
	how.anim_offset_min = 0.0
	how.anim_offset_max = 1.0


## The sheet settings one strip needs: how to blend it, and how to cut it.
func _chip_sheet(strip: SpriteStrip) -> CanvasItemMaterial:
	var skin: CanvasItemMaterial = CanvasItemMaterial.new()
	skin.blend_mode = (
		CanvasItemMaterial.BLEND_MODE_ADD if strip != null and strip.additive
		else CanvasItemMaterial.BLEND_MODE_MIX
	)
	if strip != null and strip.frames > 1:
		skin.particles_animation = true
		skin.particles_anim_h_frames = strip.frames
		skin.particles_anim_v_frames = 1
		skin.particles_anim_loop = false
	return skin
