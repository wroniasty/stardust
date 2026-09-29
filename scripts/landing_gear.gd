class_name LandingGear
extends Node2D
## Retractable legs, and the tolerances that decide whether a touchdown is a
## landing or a crash.
##
## Every threshold here is a stat, not a rule. The difficulty of landing is
## supposed to come out of the numbers (gravity, engine condition, air, terrain)
## rather than out of scripted special cases, so this component holds the
## numbers and nothing else decides (IDEAS.md section 7).
##
## M2 turns these exports into a Resource the loot generator rolls: wide legs
## and a low centre of mass make landing easier, which is exactly the kind of
## trade a module should be bought with.

## Emitted when the legs finish moving, so the HUD and sounds can react.
signal deployment_changed(deployed: bool)

## Contact points in the ship's local frame, used only while deployed. Two or
## three; the wider they are, the more slope the ship tolerates.
@export var legs: Array[Vector2] = [Vector2(-9, 13), Vector2(9, 13)]

## Fastest descent the legs absorb, in px/s along the local up.
## The legs fitted. When there is one, every tolerance below comes from it
## and the exported values are what the bare hull manages without.
##
## The geometry stays on the node: where the feet are is a fact about the
## hull, not about the part bolted to it, and swapping legs must not move
## the contact points out from under the solver.
@export var installed: GearData = null

@export var max_vertical_speed: float = 45.0

## Fastest sideways scrape the legs absorb, in px/s.
@export var max_lateral_speed: float = 22.0

## Largest angle between the ship's up and the terrain normal, in radians.
@export var max_tilt: float = deg_to_rad(15.0)

## Steepest ground the legs can stand on, in radians.
@export var max_slope: float = deg_to_rad(18.0)

## Extra linear damping while the legs are out. Deployed gear is a speed brake
## as well as a landing aid, which is the cost of leaving it out early.
@export var deployed_drag: float = 0.25

## Seconds for the legs to travel. Nothing counts as deployed until they finish.
@export var deploy_time: float = 0.5

## How the legs are drawn. A strut out to the contact point and a pad lying
## across it: the pad is the part that reads at this scale, and it is drawn
## where the solver will actually touch, so what the pilot lines up with is
## what the ground meets.
const STRUT: Color = Color(0.62, 0.67, 0.75)
const STRUT_WIDTH: float = 1.0
const PAD_HALF_WIDTH: float = 2.5

## 0 while stowed, 1 while fully out.
var extension: float = 0.0

var _wanted: bool = false


## Asks for the legs to go out or come in.
func set_deployed(wanted: bool) -> void:
	_wanted = wanted


func is_deployed() -> bool:
	return extension >= 1.0


func is_stowed() -> bool:
	return extension <= 0.0


func is_moving() -> bool:
	return not is_deployed() and not is_stowed()


func advance(delta: float) -> void:
	var was_deployed: bool = is_deployed()
	var was: float = extension
	var rate: float = delta / maxf(extend_time(), 0.001)
	extension = clampf(extension + (rate if _wanted else -rate), 0.0, 1.0)
	if not is_equal_approx(extension, was):
		queue_redraw()
	if is_deployed() != was_deployed:
		deployment_changed.emit(is_deployed())


## Pulls the legs in with no travel, for a respawn.
##
## A method rather than two lines at the call site, because setting
## `extension` from outside skips the redraw and leaves a dead ship's legs
## drawn under a live one.
func stow_instantly() -> void:
	_wanted = false
	extension = 0.0
	queue_redraw()


func _draw() -> void:
	if extension <= 0.0:
		return
	# Dimmer while travelling. Half-open gear must not read as gear you could
	# land on -- which is precisely what contact_points() refuses to hand out
	# until the timer finishes.
	var colour: Color = STRUT
	colour.a = lerpf(0.4, 1.0, extension)
	for leg: Vector2 in legs:
		# Drawn in this node's own frame. The legs are quoted in the ship's,
		# and the two coincide only while the gear sits at the hull origin.
		var hip: Vector2 = leg_root(leg) - position
		var foot: Vector2 = hip.lerp(leg - position, extension)
		draw_line(hip, foot, colour, STRUT_WIDTH)
		# The pad lies flat across the ship's own down, not square to the
		# strut: it is the part that meets the ground, and a ship standing
		# on its feet has the ground square to it.
		var across: Vector2 = Vector2.RIGHT * PAD_HALF_WIDTH
		draw_line(foot - across, foot + across, colour, STRUT_WIDTH)


## Where a leg meets the hull, in the ship's frame.
##
## Found on the outline rather than stored beside the leg, so legs stay
## attached to a hull the creative tool reshaped under them. A second copy of
## the hull's corners would go stale the first time somebody moved one.
func leg_root(leg: Vector2) -> Vector2:
	var ship: Ship = get_parent() as Ship
	if ship == null or ship.hull_outline.size() < 2:
		return leg * 0.5
	var outline: PackedVector2Array = ship.hull_outline
	var best: Vector2 = outline[0]
	var nearest: float = INF
	for i: int in range(outline.size()):
		var on_edge: Vector2 = Geometry2D.get_closest_point_to_segment(
			leg, outline[i], outline[(i + 1) % outline.size()]
		)
		var distance: float = leg.distance_squared_to(on_edge)
		if distance < nearest:
			nearest = distance
			best = on_edge
	return best


## Leg positions in the ship's local frame, or nothing while stowed.
##
## Only fully extended legs count. Half-open gear that could still be used to
## land on would make the deploy timer decorative.
func contact_points() -> Array[Vector2]:
	# Written as a branch rather than a ternary: the ternary handed back an
	# untyped Array at runtime despite the declared return type, which only
	# showed up when a caller tried to store it in a typed variable.
	if not is_deployed():
		var none: Array[Vector2] = []
		return none
	return legs


## Widest separation between legs, which is what sets the slope tolerance in
## the physical sense. Reported for the configuration readout in M2.
func track_width() -> float:
	var widest: float = 0.0
	for a: Vector2 in legs:
		for b: Vector2 in legs:
			widest = maxf(widest, a.distance_to(b))
	return widest


## What this gear will take, from the fitted part when there is one.
##
## Read through accessors rather than copied into the node at fit time: a
## copy is a second source of truth, and the landing check has been wrong
## once already for reading the wrong frame.
func vertical_limit() -> float:
	return installed.max_vertical_speed if installed != null else max_vertical_speed


func lateral_limit() -> float:
	return installed.max_lateral_speed if installed != null else max_lateral_speed


func tilt_limit() -> float:
	return installed.max_tilt if installed != null else max_tilt


func slope_limit() -> float:
	return installed.max_slope if installed != null else max_slope


func drag() -> float:
	return installed.deployed_drag if installed != null else deployed_drag


func extend_time() -> float:
	return installed.deploy_time if installed != null else deploy_time


func module_mass() -> float:
	return installed.bulk if installed != null else 0.0
