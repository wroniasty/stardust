extends Node
## StreamingManager: decides what exists as nodes around the player.
##
## Periodically measures the distance from the player to every object in the
## active system and switches it between activity levels 0..3 (see IDEAS.md
## section 9) with hysteresis. Owns the instantiation queue so that loading a
## planet never spikes a single frame.
##
## Skeleton only (M0). Filled in M3.

## How often the distance pass runs, in seconds.
const UPDATE_INTERVAL: float = 0.5

var _time_since_update: float = 0.0


func _ready() -> void:
	pass


func _process(delta: float) -> void:
	_time_since_update += delta
	if _time_since_update < UPDATE_INTERVAL:
		return
	_time_since_update = 0.0
	_update_activity_levels()


## Recomputes activity levels for everything in the active system. M3.
func _update_activity_levels() -> void:
	pass
