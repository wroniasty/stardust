class_name ShipCamera
extends Camera2D
## Camera that follows the ship without rolling with it, and that the pilot
## can frame for themselves.
##
## Kept outside the ship so it survives the ship being destroyed and respawned
## (M1.7), and so the view never rotates when the ship spins. What the pilot
## does with + / - and the arrows is a separate thing entirely: a framing they
## chose, which the ship's own tumbling must not disturb.

@export var target_path: NodePath

## Zoom when standing still and at reference_speed. Higher zoom is closer in,
## so pulling back on speed means a smaller number.
@export var zoom_at_rest: float = 1.0
@export var zoom_at_speed: float = 0.7

## The three framings the pilot picks between, closest first. A multiplier on
## the speed curve rather than a replacement for it: the pull-back when
## moving fast exists so you can see where you are going, and that is just as
## true whichever framing you chose. The middle one is 1.0, so the default
## camera behaves exactly as it did before there were levels.
const ZOOM_LEVELS: Array[float] = [1.7, 1.0, 0.55]
const DEFAULT_LEVEL: int = 1

## How fast the arrows turn the view, in radians per second. A full turn in
## about five seconds: slow enough to stop where you meant to.
@export var rotate_rate: float = 1.2

## How quickly the view catches up with the rotation being asked for. Held
## input therefore trails by about rotate_rate / this, some eight degrees,
## which reads as weight rather than as lag, and a snap to level eases
## instead of jumping.
@export var rotation_response: float = 8.0

## Height above the ground at which the approach starts taking the view over,
## and how fast it closes the remaining angle once it has all the weight.
##
## The rate is under the camera's own rotation smoothing, so what is felt is
## the two in series -- deliberately slower than a press of H, because this
## turn was not asked for and a view that snaps on its own is a view that
## startles.
const LOCK_ALTITUDE: float = 300.0
const LOCK_RATE: float = 2.5

## Speed at which the camera has pulled all the way back, in pixels per second.
@export var reference_speed: float = 400.0

## How fast the zoom follows the speed, per second.
@export var zoom_response: float = 2.5

var _target: Node2D = null

## Index into ZOOM_LEVELS.
var _level: int = DEFAULT_LEVEL


func _ready() -> void:
	if not target_path.is_empty():
		_target = get_node_or_null(target_path) as Node2D
	position_smoothing_enabled = true
	position_smoothing_speed = 10.0
	# Rotation has to be honoured for any of this to show: with
	# ignore_rotation true -- the default -- the node's rotation is simply not
	# applied to the view, and rotation smoothing is ignored with it. Starting
	# at zero, so a camera nobody touches looks exactly as it did.
	ignore_rotation = false
	rotation_smoothing_enabled = true
	rotation_smoothing_speed = rotation_response
	rotation = 0.0
	# The process mode is left alone: with physics interpolation on, Godot
	# forces every Camera2D to physics processing anyway, which is what this
	# camera wants. Setting it here as well would just be a lie about who
	# decides.
	zoom = Vector2(zoom_at_rest, zoom_at_rest)


func _physics_process(delta: float) -> void:
	if _target == null:
		return

	global_position = _target.global_position

	var speed: float = 0.0
	var body: RigidBody2D = _target as RigidBody2D
	if body != null:
		speed = body.linear_velocity.length()

	var wanted: float = ZOOM_LEVELS[_level] * lerpf(
		zoom_at_rest, zoom_at_speed, clampf(speed / reference_speed, 0.0, 1.0),
	)
	var next: float = lerpf(zoom.x, wanted, clampf(zoom_response * delta, 0.0, 1.0))
	zoom = Vector2(next, next)

	# Accumulated rather than wrapped into -PI..PI: the smoothing lerps
	# towards whatever `rotation` holds, and a value that jumps from 6.2 to
	# 0.1 would send the view the long way round.
	var turn: float = Input.get_axis(&"camera_rotate_left", &"camera_rotate_right")
	if not is_zero_approx(turn):
		rotation += turn * rotate_rate * delta
	else:
		# The pilot's hand outranks the approach. Not a mode to leave and
		# re-enter, just a frame the lock sits out: let go of the arrow and
		# it goes back to pulling.
		hold_planet_down(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"camera_zoom_in"):
		set_zoom_level(_level - 1)
	elif event.is_action_pressed(&"camera_zoom_out"):
		set_zoom_level(_level + 1)
	elif event.is_action_pressed(&"camera_level"):
		level_view()
	else:
		return
	get_viewport().set_input_as_handled()


## Picks one of the three framings. Clamped rather than wrapped: running off
## the end of the list should stop, not jump to the opposite extreme.
func set_zoom_level(level: int) -> void:
	_level = clampi(level, 0, ZOOM_LEVELS.size() - 1)


func zoom_level() -> int:
	return _level


## Puts the nearest planet at the bottom of the screen, or levels the view
## when there is no planet to be below.
##
## The way back from a rotation the pilot no longer wants, and the thing they
## were going to want anyway: on approach, "planet down" is the framing that
## makes a landing readable (VISUALS V4 does this continuously; this is the
## same answer asked for one press at a time).
func level_view() -> void:
	rotation += angle_difference(rotation, _level_target())


func _level_target() -> float:
	if _target == null:
		return 0.0
	var planet: Planet = Planet.nearest(get_tree(), _target.global_position)
	if planet == null:
		return 0.0
	var up: Vector2 = _target.global_position - planet.global_position
	if up.is_zero_approx():
		return 0.0
	# The same expression the landing code uses to stand a ship on its feet,
	# so "up" means one thing in this game.
	return up.angle() + PI * 0.5


## How much of the view the approach has taken over, 0 to 1.
##
## Two conditions, saying different things. **The gear is the pilot declaring
## an intention to land** -- flying low over a ridge with the legs up is not
## an approach, and a camera that rolled every time the ground came close
## would be seasick. **The altitude is how far along that intention is**, so
## the weight is continuous rather than a switch: at three hundred the lock
## barely leans on the view, on short finals it holds it.
##
## Measured against the terrain, not the nominal radius, because that is the
## altitude the pilot is reading off the landing panel while deciding.
func lock_weight() -> float:
	var ship: Ship = _target as Ship
	if ship == null or ship.gear == null or not ship.gear.is_deployed():
		return 0.0
	var planet: Planet = Planet.nearest(get_tree(), ship.global_position)
	if planet == null:
		return 0.0
	return clampf(
		inverse_lerp(LOCK_ALTITUDE, 0.0, planet.height_above_terrain(ship.global_position)),
		0.0,
		1.0,
	)


## Turns the view towards "planet down" by however much the approach has
## earned this frame. Public so the test can step it without a physics tick.
func hold_planet_down(delta: float) -> void:
	var weight: float = lock_weight()
	if weight <= 0.0:
		return
	rotation += angle_difference(rotation, _level_target()) * clampf(
		weight * LOCK_RATE * delta, 0.0, 1.0
	)


## Retargets the camera, e.g. after a respawn.
func set_target(target: Node2D) -> void:
	_target = target
