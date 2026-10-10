@tool
class_name GeneratorData
extends ModuleData
## What a power generator is: how much it holds, how fast it refills, and how
## long it sulks after being drawn on.
##
## Energy paces combat, in seconds. Fuel paces range, in minutes and jumps.
## The two never mix, so a long burst can never leave a ship unable to slow
## down: a ship that cannot land after a fight is hostile, not hard
## (IDEAS.md section 14).
##
## The whole model is four numbers and one rule: a spend resets the clock,
## and after `recharge_delay` seconds of silence the pool grows at
## `recharge_rate` up to `capacity`.

## Most energy the pool can hold.
@export var capacity: float = 100.0

## Units per second, once recharging has begun.
@export var recharge_rate: float = 40.0

## Seconds of silence before it begins. Measured from the last spend, not the
## last burst: every shot pushes the start back, so a gun that is firing is a
## generator that is not charging at all.
##
## Continuous regen was rejected for exactly that reason. With it, any weapon
## draining less than recharge_rate fires for ever and energy becomes a tax
## rather than a decision. "The gun goes quiet" is the point, not a side
## effect.
@export var recharge_delay: float = 0.8


## Energy this generator can sustain indefinitely against a given drain, in
## units per second. The three terms add like resistors in parallel because
## the cycle is drain, then wait, then refill.
##
## Here rather than in the ship because it is a fact about the machine, and
## because it is what the configuration report will quote when comparing two
## of them.
func sustained_throughput(drain: float) -> float:
	if drain <= 0.0 or recharge_rate <= 0.0 or capacity <= 0.0:
		return 0.0
	return 1.0 / (1.0 / drain + 1.0 / recharge_rate + recharge_delay / capacity)


func stat_rows() -> Array[Dictionary]:
	return [
		row("capacity", capacity, 0, 1),
		row("charge", recharge_rate, 0, 1, "/s"),
		row("quiet", recharge_delay, 2, -1, " s"),
		row("ceiling", sustained_throughput(INF), 1, 1, "/s"),
		row("bulk", bulk, 2, -1),
	]


func blurb() -> String:
	return "the quiet is counted from the last spend, not from the burst"
