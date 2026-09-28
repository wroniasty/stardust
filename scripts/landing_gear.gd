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
	var rate: float = delta / maxf(extend_time(), 0.001)
	extension = clampf(extension + (rate if _wanted else -rate), 0.0, 1.0)
	if is_deployed() != was_deployed:
		deployment_changed.emit(is_deployed())


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
