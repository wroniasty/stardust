class_name GearData
extends ModuleData
## What a set of landing legs will and will not put up with.
##
## A module, so a hull can be refitted for the kind of ground it works over.
## Heavy legs take a harder arrival and cost mass and drag; light ones are
## cheap to carry and demand a gentle pilot. Nothing here is scripted
## difficulty -- every threshold is a number on the part, and the ship either
## meets it or does not (IDEAS.md section 7).

## Fastest arrival the legs absorb, straight down and sideways.
@export var max_vertical_speed: float = 45.0
@export var max_lateral_speed: float = 22.0

## How far off level the ship may be, and how steep the ground may be.
@export var max_tilt: float = deg_to_rad(15.0)
@export var max_slope: float = deg_to_rad(18.0)

## Drag while extended, scaled by air density: a speed brake that is worth
## nothing in vacuum, where a drag penalty would be nonsense.
@export var deployed_drag: float = 0.25

## Seconds from stowed to down.
@export var deploy_time: float = 0.5


func stat_rows() -> Array[Dictionary]:
	return [
		row("descent", max_vertical_speed, 0, 1, " px/s"),
		row("sideways", max_lateral_speed, 0, 1, " px/s"),
		row("tilt", rad_to_deg(max_tilt), 0, 1, " deg"),
		row("slope", rad_to_deg(max_slope), 0, 1, " deg"),
		row("drag", deployed_drag, 2, -1),
		row("deploy", deploy_time, 2, -1, " s"),
		row("bulk", bulk, 2, -1),
	]
