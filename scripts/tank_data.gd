class_name TankData
extends ModuleData
## A tank: how much fuel it holds.
##
## One number, and it is the one that decides how far from home a pilot
## is willing to be. IDEAS.md section 14 draws the line that makes this
## worth having as its own module: energy paces combat in seconds and
## refills itself; fuel paces range in jumps and does not. A ship can
## shoot its way out of anywhere and still be stranded.
##
## Called `fuel_capacity` rather than `capacity` on purpose. The loot
## generator clamps fields by name across every kind of module, and a
## generator's capacity and a tank's are different quantities with
## different sane ranges -- one table key for both would have silently
## capped a tank at six hundred because a power cell should be.

## Most fuel it holds.
@export var fuel_capacity: float = 100.0


func stat_rows() -> Array[Dictionary]:
	return [
		row("capacity", fuel_capacity, 0, 1),
		row("bulk", bulk, 2, -1),
	]


func blurb() -> String:
	return "fuel measures range, energy measures a fight"
