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
	var rate: float = delta / maxf(deploy_time, 0.001)
	extension = clampf(extension + (rate if _wanted else -rate), 0.0, 1.0)
	if is_deployed() != was_deployed:
		deployment_changed.emit(is_deployed())


## Leg positions in the ship's local frame, or nothing while stowed.
##
## Only fully extended legs count. Half-open gear that could still be used to
## land on would make the deploy timer decorative.
func contact_points() -> Array[Vector2]:
	return legs if is_deployed() else [] as Array[Vector2]


## Widest separation between legs, which is what sets the slope tolerance in
## the physical sense. Reported for the configuration readout in M2.
func track_width() -> float:
	var widest: float = 0.0
	for a: Vector2 in legs:
		for b: Vector2 in legs:
			widest = maxf(widest, a.distance_to(b))
	return widest
