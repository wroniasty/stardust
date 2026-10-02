class_name Station
extends Node2D
## Somewhere to dock: a hub you can tie up to, mend a hull at and leave.
##
## Not a GravityWell. The model has said since it was written that a station
## has no well worth the name -- you dock with it, you do not orbit it --
## and a source that small would only add noise to the ship's solver. What
## it has instead is a radius you have to be inside and a speed you have to
## be under, which is the same shape as a landing and deliberately so: the
## pilot already knows how to arrive somewhere slowly.
##
## Drawn rather than drawn from a sprite, like everything else here. A hub,
## a ring and some spokes, rolled from the body's seed so the dock at one
## planet is not the dock at the next.

## How far out the dock will take you, as a multiple of the station radius.
## Generous: this is an arcade dock, and hunting for a pixel is not the
## skill being asked for.
const DOCK_REACH: float = 2.6

## Fastest you may be moving when you arrive, in px/s.
##
## Slower than a landing on legs, because there is no suspension here and
## nothing to absorb anything: a dock is a handshake. Fast enough that a
## pilot who has killed their velocity does not have to creep the last
## hundred pixels.
const DOCK_SPEED: float = 30.0

## Spokes a station can have, and how fat the ring is against the radius.
const SPOKES: Vector2i = Vector2i(3, 6)
const RING_WIDTH: Vector2 = Vector2(0.14, 0.26)

## Turns at this many radians per second. A station spins for the same
## reason a real one would, and slowly enough that it is scenery rather
## than something to time an approach against.
const SPIN: Vector2 = Vector2(0.05, 0.14)

## What it is lit by. Stations are the one built thing in the game, so they
## get the one light that is not a flame: a navigation lamp, visible from
## further out than the structure itself.
## Modest on purpose: at the first try it washed the whole ring white and
## took the station's own rolled colour with it. A navigation lamp marks
## where the dock is from a distance; it does not light the structure.
const LAMP_REACH: float = 150.0
const LAMP_STRENGTH: float = 0.35

const HULL: Color = Color(0.62, 0.66, 0.72)
const LAMP: Color = Color(0.55, 0.85, 1.00)

## The descriptor this station was built from, as on Planet and Star.
var body: SystemBody = null

## Radius of the structure in pixels, and how it is put together. All
## rolled from the seed.
var radius: float = 80.0
var spokes: int = 4
var ring_width: float = 0.2
var spin_rate: float = 0.1
var hue: Color = HULL


## Builds this station as the body the system says it is.
func adopt(descriptor: SystemBody, at_time: float = 0.0) -> void:
	body = descriptor
	radius = descriptor.radius
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = descriptor.seed
	spokes = rng.randi_range(SPOKES.x, SPOKES.y)
	ring_width = rng.randf_range(RING_WIDTH.x, RING_WIDTH.y)
	spin_rate = rng.randf_range(SPIN.x, SPIN.y) * (1.0 if rng.randf() < 0.5 else -1.0)
	hue = HULL.lerp(Color.from_hsv(rng.randf(), 0.25, 0.8), 0.35)
	global_position = descriptor.position_at(at_time)
	queue_redraw()


func _ready() -> void:
	var lamp: GlowLight = GlowLight.make(LAMP, LAMP_REACH, LAMP_STRENGTH)
	add_child(lamp)


func _process(delta: float) -> void:
	rotation = wrapf(rotation + spin_rate * delta, -PI, PI)


## How close you have to be, in pixels from the middle.
func dock_radius() -> float:
	return radius * DOCK_REACH


## What to call it in a readout.
func catalogue_name() -> String:
	return name if body == null else body.display_name


## Why `ship` cannot dock from where it is, or "" if it can.
##
## Returns the reason rather than a bool, for the same reason the landing
## check does: "no" is not an answer a pilot can act on, and the one thing
## they need to know is which of the two numbers they are failing.
func refusal(ship: Ship) -> String:
	if ship == null or ship.is_destroyed():
		return "wrak"
	if ship.global_position.distance_to(global_position) > dock_radius():
		return "za daleko"
	if ship.linear_velocity.length() > DOCK_SPEED:
		return "za szybko"
	return ""


## The nearest station in the world, or null. Stations are rare and the
## group is tiny, so this is a walk rather than a structure.
static func nearest(tree: SceneTree, point: Vector2) -> Station:
	var best: Station = null
	var closest: float = INF
	for node: Node in tree.get_nodes_in_group(GROUP):
		var station: Station = node as Station
		if station == null:
			continue
		var gap: float = station.global_position.distance_squared_to(point)
		if gap < closest:
			closest = gap
			best = station
	return best


## Stations publish themselves here, the way gravity sources do, so that
## nothing has to know a scene path to find one.
const GROUP: StringName = &"stations"


func _enter_tree() -> void:
	add_to_group(GROUP)


func _draw() -> void:
	var inner: float = radius * (1.0 - ring_width)
	# The ring, as a thick arc rather than two circles: one call, and the
	# width is the structure rather than a gap between two outlines.
	draw_arc(Vector2.ZERO, (radius + inner) * 0.5, 0.0, TAU, 40, hue, radius - inner)
	for i: int in range(spokes):
		var along: Vector2 = Vector2.from_angle(TAU * float(i) / float(spokes))
		draw_line(along * radius * 0.18, along * inner, hue, radius * 0.07)
	# The hub, brighter, so the middle reads as the part you dock with.
	draw_circle(Vector2.ZERO, radius * 0.22, hue.lightened(0.3))
	# And the lamp, which is what you actually see from a long way out.
	draw_circle(Vector2.ZERO, radius * 0.09, LAMP)
