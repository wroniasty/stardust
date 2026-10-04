class_name NavMarker
extends RefCounted
## The pin the pilot puts in the system map, and the one thing on the
## scanner that is there because somebody put it there.
##
## One marker, held statically, and both of those are decisions worth
## writing down.
##
## **One** because the gesture is one: right click puts it somewhere,
## right click on it takes it away. A list would need a way to say which
## one you meant, which is a second gesture to invent and a second thing
## to draw, for a feature whose whole value is that it is the place you
## are going. When there is a reason for two there will be a reason for
## naming them, and that is a different feature.
##
## **Static** rather than a field on the `Galaxy` autoload, where the
## player's other addresses live, and that was measured rather than
## preferred: an autoload does not exist in a `godot --script` run, so a
## map or a scanner that read one would be a map or a scanner the smoke
## test cannot even compile. The same reason `Palette` holds its loaded
## copy this way. It is the project's own rule about presentation gates
## wearing another coat -- state the instruments read has to be reachable
## from a headless test, or the instruments have no tests.
##
## The point is in **system pixels**, which is why crossing to another
## system drops it: the same numbers over a different star are a pin in
## the wrong place, and a pin in the wrong place is worse than none.

## Where the pin is, or `INF` for no pin.
static var marked: Vector2 = Vector2.INF


static func mark(point: Vector2) -> void:
	marked = point


static func unmark() -> void:
	marked = Vector2.INF


static func is_marked() -> bool:
	return marked != Vector2.INF


## How far a point is from the pin, or -1 when there is none. For a
## readout that would otherwise have to ask twice.
static func distance_from(point: Vector2) -> float:
	return -1.0 if not is_marked() else point.distance_to(marked)
