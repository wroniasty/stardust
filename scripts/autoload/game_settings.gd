extends Node
## What the main menu decided, carried into the world.
##
## State on an autoload rather than an argument, because the menu and the world
## are two scenes and a scene change cannot hand anything across. `chosen` is
## false until the menu has run, so a world opened straight from the editor, a
## test or the `resume` argument keeps its own seed and its own ship.

## The seed the galaxy is made of. Everything procedural comes from this.
var galaxy_seed: int = 20260922

## The ShipFitout preset the player starts in.
var fitout_name: String = "dart (stock)"

## Whether the menu has been through, and so whether the world should listen.
var chosen: bool = false


## A fresh seed, for the menu's randomize button. Positive and short enough to
## type back in.
func random_seed() -> int:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	return rng.randi_range(1, 999999999)
