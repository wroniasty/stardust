class_name Presentation
extends RefCounted
## Jeden wyłącznik na całą warstwę prezentacji.
##
## VISUALS.md section 1, point 4: a broken effect must not be able to block
## the main line or the tests. So every presentation node asks here before it
## shows anything, and `F8` turns the whole lot off at once -- which is also
## the fastest way to answer "is that glitch the simulation or the paint".
##
## Asked rather than announced. A signal would need an Object to hang off and
## a connection per node to keep alive; the nodes that care are all ticking
## anyway, and a bool read per tick is cheaper than either.
##
## Headless is off and cannot be turned on. Not a convenience: the smoke test
## runs headless and has to be testing the game rather than the paint, so a
## texture that fails to load must not be able to fail a flight check. A test
## that wants to exercise the layer builds it by hand -- see `_check_art()`.

## Whether the player has asked for it. The headless gate below outranks this.
static var wanted: bool = true


## Whether the presentation layer should be visible at all.
static func is_on() -> bool:
	return wanted and DisplayServer.get_name() != "headless"


## Which physics frame the key was last acted on.
static var _toggled_on: int = -1


## Handles the toggle key, and says whether it was pressed.
##
## Here rather than in each node, so the layer has one switch rather than one
## per subtree quietly disagreeing about its state. Latched on the frame
## number, not on the key: `is_action_just_pressed` answers yes to every
## caller in the same tick, so two ships on screen would toggle twice and the
## key would do nothing. A condition still true the instant after you act on
## it needs a latch, which is the fourth time that has come up in this
## project.
static func read_toggle() -> bool:
	if not Input.is_action_just_pressed(&"toggle_presentation"):
		return false
	var frame: int = Engine.get_physics_frames()
	if frame == _toggled_on:
		return false
	_toggled_on = frame
	wanted = not wanted
	return true
