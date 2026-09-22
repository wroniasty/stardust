class_name ShipCamera
extends Camera2D
## Camera that follows the ship without rolling with it.
##
## Kept outside the ship so it survives the ship being destroyed and respawned
## (M1.7), and so the view never rotates when the ship spins.

@export var target_path: NodePath

## Zoom when standing still and at reference_speed. Higher zoom is closer in,
## so pulling back on speed means a smaller number.
@export var zoom_at_rest: float = 1.0
@export var zoom_at_speed: float = 0.7

## Speed at which the camera has pulled all the way back, in pixels per second.
@export var reference_speed: float = 400.0

## How fast the zoom follows the speed, per second.
@export var zoom_response: float = 2.5

var _target: Node2D = null


func _ready() -> void:
	if not target_path.is_empty():
		_target = get_node_or_null(target_path) as Node2D
	position_smoothing_enabled = true
	position_smoothing_speed = 10.0
	zoom = Vector2(zoom_at_rest, zoom_at_rest)


func _physics_process(delta: float) -> void:
	if _target == null:
		return

	global_position = _target.global_position

	var speed: float = 0.0
	var body: RigidBody2D = _target as RigidBody2D
	if body != null:
		speed = body.linear_velocity.length()

	var wanted: float = lerpf(zoom_at_rest, zoom_at_speed, clampf(speed / reference_speed, 0.0, 1.0))
	var next: float = lerpf(zoom.x, wanted, clampf(zoom_response * delta, 0.0, 1.0))
	zoom = Vector2(next, next)


## Retargets the camera, e.g. after a respawn.
func set_target(target: Node2D) -> void:
	_target = target
