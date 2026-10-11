@tool
class_name FlightComputerData
extends ModuleData
## The box that decides which engine does what, and what else it will do for
## the pilot.
##
## A module, so not every ship has one and not every one is the same. The
## stock hull flies on the weight heuristic built into ShipControl; a computer
## that allocates properly is something the pilot finds, and the difference
## shows most on a ship that is damaged or asymmetric -- exactly when it is
## hardest to fly without help (IDEAS.md sections 3 and 8).

enum Allocation {
	## The built-in weights: engines sorted into groups by how cleanly they
	## push. Fine on a symmetric ship in good repair.
	HEURISTIC,
	## Bounded least squares against the real thrusts and the real condition
	## of every engine. Turns cleanly with a jet half dead.
	NNLS,
}

@export var allocation: Allocation = Allocation.NNLS

## Holds an orbit by itself, given a gravity well and no air. Optional on
## purpose: some computers have it and some do not, and finding one that does
## is a real upgrade rather than a number going up (IDEAS.md section 8).
@export var has_auto_orbit: bool = false

## Keeps the nose level with the horizon on approach.
@export var has_auto_level: bool = false

## Holds whatever height it was engaged at, trading thrust against gravity.
## The assist a pilot wants while reading the ground for somewhere to land.
@export var has_altitude_hold: bool = false

## Brings the low point of the orbit down into the air, and no further. A
## deorbit is the one manoeuvre where overshooting is expensive and the
## arithmetic is dull, which is exactly what a computer is for.
@export var has_deorbit: bool = false

## Stops the spin on its own, as soon as the pilot stops asking for one.
##
## The difference from the `kill_rotation` key is that this is not a
## command: the pilot never asks for it, it happens in the gap after
## they let go. So it runs at `Ship.AUTO_KILL_SHARE` of the demand the
## key makes -- enough that a nudge settles by itself, short of the
## authority a pilot gets by asking, because an assist that stopped the
## ship as hard as the key does would make the key pointless and would
## take the drift out of flying entirely.
##
## It also stands aside for every assist that steers: auto-level,
## auto-orbit, deorbit and the heading holds all turn the ship on
## purpose, and a rotation kill fighting them would hold the nose
## halfway to where it was going.
@export var has_rotation_kill: bool = false

## Constant draw while any assist is engaged, in energy per second.
##
## Subtracted from the recharge rate rather than resetting the silence: an
## assist should shorten bursts, not forbid shooting. On the HUD it shows as
## a bar that fills more slowly, not as a second bar (IDEAS.md section 14).
@export var idle_draw: float = 0.0


func stat_rows() -> Array[Dictionary]:
	return [
		row("thrust split", 1.0 if allocation == Allocation.NNLS else 0.0, 0, 1),
		row("spin kill", 1.0 if has_rotation_kill else 0.0, 0, 1),
		row("auto-level", 1.0 if has_auto_level else 0.0, 0, 1),
		row("auto-orbit", 1.0 if has_auto_orbit else 0.0, 0, 1),
		row("altitude hold", 1.0 if has_altitude_hold else 0.0, 0, 1),
		row("deorbit", 1.0 if has_deorbit else 0.0, 0, 1),
		row("draw", idle_draw, 1, -1, "/s"),
		row("bulk", bulk, 2, -1),
	]


func blurb() -> String:
	return "functions are what rarity buys, not bigger numbers"
