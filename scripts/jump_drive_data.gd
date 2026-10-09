class_name JumpDriveData
extends ModuleData
## A jump drive: how far it reaches, how long it charges, what it burns.
##
## Range is the headline and the other two are what it costs. IDEAS.md
## section 10 puts the charge at two to four seconds -- long enough that
## a jump is a decision taken in advance rather than an escape key, since
## damage interrupts it.
##
## The fuel bill is the part worth getting right, because a shortfall is
## not a refusal: a jump you cannot quite pay for is a jump you may still
## take, with the missing fraction as the chance of a misjump. So the
## cost has to be a number the pilot can read off a card and compare to
## what is in the tank, which is why it is stated per light year at a
## reference mass rather than as a curve.

## What a laden hull is measured against, in the engine's mass units.
##
## The stock dart comes out near sixteen with a full fitout, so a ship
## that has not been loaded up pays about what the card says. Heavier
## ships pay more, which is the only place mass has ever cost a pilot
## anything outside the handling.
const REFERENCE_MASS: float = 16.0

## How far it jumps, in light years.
@export var reach: float = 10.5

## Seconds of charging before the jump goes, during which damage or a
## released key cancels it.
@export var charge_time: float = 3.0

## Fuel per light year, at `REFERENCE_MASS`. What a jump costs when
## there is not enough in the tank to do it properly.
@export var fuel_per_ly: float = 2.0



## What a jump of this length would cost a hull of this mass.
##
## Linear in both, which is arcade rather than correct and is the whole
## of the rule a pilot has to hold in their head: twice as far is twice
## as much, twice as heavy is twice as much.
func fuel_for(distance: float, hull_mass: float) -> float:
	if distance <= 0.0:
		return 0.0
	return fuel_per_ly * distance * maxf(hull_mass, 0.0) / REFERENCE_MASS


## Whether this drive could cross a gap at all, fuel aside.
func can_cross(distance: float) -> bool:
	return distance <= reach


func stat_rows() -> Array[Dictionary]:
	return [
		row("range", reach, 1, 1, " ly"),
		row("charge", charge_time, 1, -1, " s"),
		row("burn", fuel_per_ly, 2, -1, "/ly"),
		row("full jump", fuel_for(reach, REFERENCE_MASS), 0, -1),
		row("bulk", bulk, 2, -1),
	]


func blurb() -> String:
	return "the cost rises with hull mass"
