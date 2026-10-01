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
##     Q + E + D      hold a circular orbit
##     Q + E + A      keep the nose level with the horizon
##     W + S + A      hold this height
##     W + S + D      bring the orbit down into the air
##
## W and S cancel each other exactly as Q and E do, so they are a second free
## modifier and the fourth key picks the function again. Keys that are read
## as a press rather than a hold -- the landing gear toggle -- cannot be part
## of a chord: the press is handled outside the suppression and would fire
## anyway.
##
## Q and E together are the modifier and the fourth key picks the function,
## which is why this scales: the flight computer has a long list of things it
## will want to be told, and none of them needs a key of its own.
##
## A chord consumes the keys it is made of. Otherwise Q+E+S would aim
## backwards along the velocity and fire the reverse thruster at the same
## time, which is not braking -- it is speeding up the way you came.
##
## Deliberately free of Input: the caller passes the held actions, so the
## behaviour can be driven in a test without a keyboard.

enum Chord { NONE, KILL_ROTATION, PROGRADE, RETROGRADE, AUTO_ORBIT, AUTO_LEVEL,
	ALTITUDE_HOLD, DEORBIT }

## How long every key of a chord must be held together before it engages.
##
## Rolling a finger from A to D overlaps the two for a few tens of
## milliseconds, and without this that reads as "stop turning" in the middle
## of a turn the pilot is still making.
##
## The chord itself still ends the instant one key comes up -- letting go
## has to be believed immediately. What does not end with it is the hold
## on the keys; see `_locked`.
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
	{
		"chord": Chord.AUTO_ORBIT,
		"keys": [&"strafe_left", &"strafe_right", &"rotate_right"],
	},
	{
		"chord": Chord.AUTO_LEVEL,
		"keys": [&"strafe_left", &"strafe_right", &"rotate_left"],
	},
	{
		"chord": Chord.ALTITUDE_HOLD,
		"keys": [&"thrust_forward", &"thrust_reverse", &"rotate_left"],
	},
	{
		"chord": Chord.DEORBIT,
		"keys": [&"thrust_forward", &"thrust_reverse", &"rotate_right"],
	},
]

var _candidate: Chord = Chord.NONE
var _held_for: float = 0.0
var _active: Chord = Chord.NONE

## Keys that were part of a chord and have not been let go of yet.
##
## Fingers do not come off a chord together any more than they go onto
## one together. Releasing A+D, one of them outlasts the other by a few
## tens of milliseconds, and for those milliseconds the survivor reads as
## a plain turn command: the ship starts spinning again at the exact
## moment the pilot stopped telling it to stop. On the panic gesture.
##
## SETTLE is the guard on the way in and the mirror of it would be a
## window on the way out -- and a window is a guess. Too short and a slow
## release still spins the ship; too long and a deliberate press landing
## inside it is eaten; and either way the number is wrong for somebody's
## hands. So there is no number here. A key that was part of a chord
## stays spent until it is released, which cannot be tuned wrong.
##
## What it costs: rolling out of A+D into a deliberate turn needs a fresh
## press rather than just letting one finger up. A tap, weighed against a
## panic gesture that used to undo itself.
var _locked: Dictionary = {}


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

	# A lock lasts exactly as long as the finger does. Clearing first and
	# re-arming after means a chord that is still engaged keeps its keys
	# locked without the two rules having to agree about ordering.
	for key: StringName in _locked.keys():
		if not bool(held.get(key, false)):
			_locked.erase(key)
	for key: StringName in _keys_of(_active):
		_locked[key] = true
	return _active


func active() -> Chord:
	return _active


## The actions the chord in force has taken over, which the ship must not
## also read as ordinary commands.
## The keys the ship must not read as commands this tick: the ones making
## up the chord in force, plus any left over from one that has just ended
## and is still being let go of.
##
## Read off `_locked`, which `update` fills, so calling this without
## having called `update` first answers about the previous tick -- which
## is the only sensible thing it could do.
func consumed() -> Array[StringName]:
	var keys: Array[StringName] = []
	for key: StringName in _locked:
		keys.append(key)
	return keys


## The actions a chord is made of, or nothing for NONE.
func _keys_of(chord: Chord) -> Array[StringName]:
	for entry: Dictionary in CHORDS:
		if entry["chord"] == chord:
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
