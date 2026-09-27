class_name ControlChords
extends RefCounted
## Commands made by pressing keys together, instead of by spending another key.
##
## The keyboard is nearly full and the flight computer has a long list of
## things it will want to be told (IDEAS.md section 8). Chords buy room, but
## only where the combination already means nothing: A and D are opposite
## torque commands that cancel, so holding both has no other reading, and
## "press both brakes" is a fair way to say stop turning. Q and E cancel the
## same way, which leaves W or S free to pick a direction.
##
##     A + D          stop turning
##     Q + E + W      point along the way we are going
##     Q + E + S      point back along it
##
## A chord consumes the keys it is made of. Otherwise Q+E+S would aim
## backwards along the velocity and fire the reverse thruster at the same
## time, which is not braking -- it is speeding up the way you came.
##
## Deliberately free of Input: the caller passes the held actions, so the
## behaviour can be driven in a test without a keyboard.

enum Chord { NONE, KILL_ROTATION, PROGRADE, RETROGRADE }

## How long every key of a chord must be held together before it engages.
##
## Rolling a finger from A to D overlaps the two for a few tens of
## milliseconds, and without this that reads as "stop turning" in the middle
## of a turn the pilot is still making. Releasing is instant: letting go has
## to be believed immediately.
const SETTLE: float = 0.06

## Checked in order, first match wins. Kill rotation is first on purpose: it
## is the panic gesture, and a pilot who grabs A and D while already holding
## something else means stop, whatever else their hands are doing.
const CHORDS: Array[Dictionary] = [
	{
		"chord": Chord.KILL_ROTATION,
		"keys": [&"rotate_left", &"rotate_right"],
	},
	{
		"chord": Chord.PROGRADE,
		"keys": [&"strafe_left", &"strafe_right", &"thrust_forward"],
	},
	{
		"chord": Chord.RETROGRADE,
		"keys": [&"strafe_left", &"strafe_right", &"thrust_reverse"],
	},
]

var _candidate: Chord = Chord.NONE
var _held_for: float = 0.0
var _active: Chord = Chord.NONE


## `held` maps action names to whether they are down. Returns the chord in
## force this tick, which is NONE until one has survived the settle window.
func update(held: Dictionary, delta: float) -> Chord:
	var found: Chord = _match(held)
	if found != _candidate:
		_candidate = found
		# This tick counts towards the window. Starting at zero instead makes
		# the wait one frame longer than SETTLE says, and means a single call
		# can never engage a chord however long its delta.
		_held_for = delta
	else:
		_held_for += delta

	if found == Chord.NONE:
		_active = Chord.NONE
	elif _held_for >= SETTLE:
		_active = found
	return _active


func active() -> Chord:
	return _active


## The actions the chord in force has taken over, which the ship must not
## also read as ordinary commands.
func consumed() -> Array[StringName]:
	for entry: Dictionary in CHORDS:
		if entry["chord"] == _active:
			var keys: Array[StringName] = []
			for key: StringName in entry["keys"]:
				keys.append(key)
			return keys
	return []


## Builds the held set from the real keyboard. Split from update() so that
## everything above this line can be tested without one.
static func poll() -> Dictionary:
	var held: Dictionary = {}
	for entry: Dictionary in CHORDS:
		for key: StringName in entry["keys"]:
			held[key] = Input.is_action_pressed(key)
	return held


func _match(held: Dictionary) -> Chord:
	for entry: Dictionary in CHORDS:
		var all_down: bool = true
		for key: StringName in entry["keys"]:
			if not bool(held.get(key, false)):
				all_down = false
				break
		if all_down:
			return entry["chord"]
	return Chord.NONE
