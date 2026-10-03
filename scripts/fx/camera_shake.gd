class_name CameraShake
extends Node
## Trzęsie kamerą, kiedy kadłub w coś uderzy.
##
## VISUALS.md section 1 says presentation listens and the simulation emits,
## and section 6 calls the first such receiver **the proof that the seam
## works**. This is it: one node, one connection, and nothing added to
## `ship.gd`. `hull_impact` was already there, already carrying the speed of
## the arrival, and nothing had ever listened to it.
##
## One source, scaled by energy, rather than a number per event (V3). An
## impact is a kinetic event and kinetic energy goes as the square of the
## speed, so a graze is nothing and an arrival that nearly kills you is a
## slam. A table of "this much for a landing, that much for a crash" would
## be the same decision taken repeatedly and inconsistently.

## Impact speed at which the shake is at full. Taken from the hull: a little
## over 300 px/s is lethal, so a shake that saturates there is one the pilot
## never sees at full without also dying.
const REFERENCE_SPEED: float = 300.0

## Widest the view is thrown, in design pixels at the shake's peak.
##
## Four, which is small on purpose. The camera already moves with a ship
## that is itself bouncing, and a shake big enough to be impressive on its
## own is one that hides the ground during the half second the pilot most
## needs to see it.
const MAX_THROW: float = 4.0

## Seconds for the shake to fall to a tenth. Short: a camera still ringing
## when the ship has stopped reads as a camera fault.
const DECAY: float = 0.28

## Below this the offset is cleared outright, so the view settles exactly
## where it belongs rather than creeping towards it.
const SETTLED: float = 0.02

@export var ship_path: NodePath
@export var camera_path: NodePath

var _ship: Ship = null
var _camera: Camera2D = null

## How hard it is shaking, 0..1.
var energy: float = 0.0

## Its own, seeded from nothing in particular: two ships shaking in step
## would read as the world shaking rather than as either of them being hit.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_ship = get_node_or_null(ship_path) as Ship
	_camera = get_node_or_null(camera_path) as Camera2D
	if _ship == null or _camera == null:
		set_physics_process(false)
		return
	_ship.hull_impact.connect(_on_impact)


## What an arrival at `speed` is worth, 0..1.
##
## Squared, and then taken as the larger of what is already running: two
## bounces in quick succession should not add up to more than the harder of
## them, or a ship skidding along a slope works itself into a shake nothing
## about the landing justifies.
func _on_impact(impact_speed: float, _damage: float) -> void:
	var share: float = clampf(impact_speed / REFERENCE_SPEED, 0.0, 1.0)
	energy = maxf(energy, share * share)


func _physics_process(delta: float) -> void:
	advance(delta)


## One tick, gated on the switch.
##
## The energy runs down whether or not it is being drawn: with the layer
## off the shake still has to end, or turning it back on would show a ship
## ringing from an impact it took a minute ago.
func advance(delta: float) -> void:
	if energy <= 0.0:
		return
	energy *= pow(0.1, delta / maxf(DECAY, 0.001))
	if energy <= SETTLED:
		energy = 0.0
	if not Presentation.is_on() or energy <= 0.0:
		_camera.offset = Vector2.ZERO
		return
	throw()


## Displaces the view by whatever the current energy is worth.
##
## Split out from `advance()` with no gate on it, for the same reason
## `ShipSkin.paint()` is: the layer is never shown without a window, so a
## headless test driving the tick would only ever measure a cleared
## offset. That is exactly how the first version of the test for this came
## out -- zero against zero, and passing the comparison it was given.
func throw() -> void:
	# Divided by the zoom, because `Camera2D.offset` is in world units and
	# the view is between 0.385 and 1.7 of them to the pixel. Without this
	# the same impact is a twitch close in and a lurch zoomed out, which is
	# backwards: the shake belongs to the screen, not to the world.
	var reach: float = MAX_THROW * energy / maxf(_camera.zoom.x, 0.001)
	_camera.offset = Vector2(
		_rng.randf_range(-reach, reach), _rng.randf_range(-reach, reach)
	)
