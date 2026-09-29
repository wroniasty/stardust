class_name GearData
extends ModuleData
## What a set of landing legs will and will not put up with.
##
## A module, so a hull can be refitted for the kind of ground it works over.
## Heavy legs take a harder arrival and cost mass and drag; light ones are
## cheap to carry and demand a gentle pilot. Nothing here is scripted
## difficulty -- every threshold is a number on the part, and the ship either
## meets it or does not (IDEAS.md section 7).

@export var display_name: String = "landing gear"

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
		row("opadanie", max_vertical_speed, 0, 1, " px/s"),
		row("w bok", max_lateral_speed, 0, 1, " px/s"),
		row("przechył", rad_to_deg(max_tilt), 0, 1, " st"),
		row("nachylenie", rad_to_deg(max_slope), 0, 1, " st"),
		row("opór", deployed_drag, 2, -1),
		row("wysuwanie", deploy_time, 2, -1, " s"),
		row("gabaryt", bulk, 2, -1),
	]
