class_name AimHud
extends CanvasLayer
## The crosshair, and what it says about whether shooting will achieve
## anything.
##
## Three states, and they answer one question each. Grey: nothing on this
## trigger can reach there, so pulling it wastes energy. Amber: something
## could, once it has finished turning. Green: fire.
##
## The colour is taken from the best gun on the trigger rather than the
## worst, because the question a pilot is asking is "will pulling this do
## anything", and one gun that bears is a yes.
##
## Two rings, one per trigger, so a pilot with guns on both can see both
## answers without switching. A trigger nothing is wired to draws nothing.

const BLOCKED: Color = Color(0.45, 0.47, 0.52)
const TURNING: Color = Color(1.00, 0.78, 0.25)
const READY: Color = Color(0.36, 0.92, 0.50)

## Radius of the primary ring and the gap out to the secondary one. The
## secondary sits outside so the two never overlap into a single blob at the
## 640x360 the game is drawn at.
const PRIMARY_RADIUS: float = 5.0
const SECONDARY_GAP: float = 3.0

## Length of the tick marks that make the ring readable against terrain, and
## how far in from the ring they start.
const TICK: float = 3.0

var _ship: Ship = null
var _canvas: Control = null


func _ready() -> void:
	layer = 11
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_cursor)
	add_child(_canvas)


func bind(ship: Ship) -> void:
	_ship = ship


func _process(_delta: float) -> void:
	if _canvas != null:
		_canvas.queue_redraw()


## Colour for a state. Public so the test can check the mapping rather than
## re-deriving it and agreeing with itself.
static func state_color(state: Hardpoint.Aim) -> Color:
	match state:
		Hardpoint.Aim.ON_TARGET:
			return READY
		Hardpoint.Aim.TURNING:
			return TURNING
		_:
			return BLOCKED


## Where the crosshair goes, in screen pixels.
##
## **The pointer is a screen fact, so it is read as one.** It used to
## be read back out of the world: the ship turns the pointer into
## `aim_point` with the canvas transform in `_physics_process`, and
## this turned it back with the canvas transform in `_process`. Those
## are two different transforms whenever the camera has moved between
## the tick and the frame, which with physics interpolation and a
## render rate above the physics rate is nearly every frame.
##
## Measured on a stationary pointer: 0.05 px of wander at rest, 12 px
## at 1200 px/s, 33 px at 2400, and 218 px during the camera's zoom
## ease. At 97 frames against 60 ticks the crosshair snapped back
## every tick, which is seen as two crosshairs rather than as one
## moving -- and the real pointer is sitting still next to it the
## whole time.
##
## The guns keep aiming at the world point, and should: they fire in
## physics time, and a sub-tick of lag there is invisible. It is only
## the drawing that has to agree with the pointer.
func cursor_at() -> Vector2:
	# Only when there is a pointer driving it. An AI ship, a test or
	# the sandbox sets `aim_point` directly and has no mouse, and for
	# those the round trip is the right answer rather than the wrong
	# one -- there is no second transform to disagree with.
	if _ship != null and is_instance_valid(_ship) and _ship.use_player_input:
		return _canvas.get_local_mouse_position()
	var sight: Vector2 = _ship.aim_point if _ship != null else Vector2.ZERO
	return get_viewport().get_canvas_transform() * sight


func _draw_cursor() -> void:
	if _ship == null or not is_instance_valid(_ship):
		return
	var at: Vector2 = cursor_at()

	for trigger: int in [0, 1]:
		if not _ship.has_trigger(trigger):
			continue
		var radius: float = PRIMARY_RADIUS + float(trigger) * SECONDARY_GAP
		var colour: Color = state_color(_ship.aim_state(trigger))
		_canvas.draw_arc(at, radius, 0.0, TAU, 20, colour, 1.0)

	# Four ticks rather than a filled dot: a dot vanishes against bright
	# terrain, and the gap in the middle keeps the thing being aimed at
	# visible, which is the entire point of a crosshair.
	var outer: float = PRIMARY_RADIUS + SECONDARY_GAP + TICK + 1.0
	var inner: float = PRIMARY_RADIUS + SECONDARY_GAP + 1.0
	var edge: Color = state_color(_ship.aim_state(0))
	for step: int in range(4):
		var along: Vector2 = Vector2.RIGHT.rotated(float(step) * PI * 0.5)
		_canvas.draw_line(at + along * inner, at + along * outer, edge, 1.0)
