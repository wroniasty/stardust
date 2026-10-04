class_name UiValue
extends RefCounted
## One reading, two ways out: a needle and a number.
##
## UI_STYLE section 7 is the whole brief, and the point of it is that the
## same quantity has two incompatible requirements on it. A bar or a
## ladder has to be **continuous** -- it is a shape, and a shape that
## jumps reads as the render having glitched. A printed figure has to be
## **still** -- a digit that changes sixty times a second is unreadable
## even when every one of those values is true. One number cannot satisfy
## both, so this hands out two.
##
## `smooth()` is for geometry: exponentially eased, half gone in 120 ms.
## `stepped()` is for text: quantised, and allowed to change ten times a
## second at the most.
##
## Kept as an object per reading rather than a static helper, because
## both answers are made of history. A function cannot smooth anything.

## How long the smoothed value takes to close half the gap to the truth.
##
## Specified as a half-life rather than as a per-tick fraction, and that
## is not pedantry: a fraction is a different curve at 60 fps and at 144,
## and this is read by the HUD, which is drawn at frame rate rather than
## at tick rate. The test for it feeds the same second of time in two
## different step sizes and expects the same answer.
const HALF_LIFE: float = 0.12

## How often the printed figure may change.
const STEPS_PER_SECOND: float = 10.0

## How far the truth has to move past the shown figure before it changes,
## as a share of one step.
##
## Three quarters rather than a half, which would be the obvious answer
## and would be wrong. Exactly on a boundary a half is no hysteresis at
## all: a reading that is not moving still alternates between two
## numbers, ten times a second, which is the complaint this class exists
## to answer arriving by a different door.
const STICK: float = 0.75

var _quantum: float = 1.0
var _smooth: float = 0.0
var _shown: float = 0.0
var _wait: float = 0.0
var _started: bool = false


## `quantum` is the step the printed figure moves in: 1 for an altitude
## in pixels, 0.1 for a rate of climb.
func _init(quantum: float = 1.0) -> void:
	_quantum = maxf(quantum, 0.000001)


## Hands the instrument what is true now. Both readings are taken off it
## afterwards.
func feed(truth: float, delta: float) -> void:
	if not _started:
		jump(truth)
		return

	_smooth = lerpf(truth, _smooth, pow(0.5, delta / HALF_LIFE))

	_wait -= delta
	if _wait > 0.0:
		return
	_wait = 1.0 / STEPS_PER_SECOND
	# Quantised off the smoothed value rather than off the truth. The
	# truth is what the digit is about, but it is also what is noisy,
	# and a figure sampled from noise ten times a second is a figure
	# that disagrees with itself. The smoothing costs about one step of
	# lag at this half-life, which on a number nobody reads to the
	# frame is not a cost at all.
	if absf(_smooth - _shown) >= _quantum * STICK:
		_shown = snappedf(_smooth, _quantum)


## Puts both readings on a value with no easing and no delay, for the
## moments where there is nothing to ease from: the first frame, a
## respawn, a jump to another system. Without it an instrument spends
## its first tenth of a second sliding in from whatever the last ship
## was doing.
func jump(truth: float) -> void:
	_started = true
	_smooth = truth
	_shown = snappedf(truth, _quantum)
	_wait = 1.0 / STEPS_PER_SECOND


## For a bar, a ladder, a needle: continuous, and never ahead of itself.
func smooth() -> float:
	return _smooth


## For a printed figure: quantised, and still long enough to read.
func stepped() -> float:
	return _shown


## The step the printed figure moves in.
func quantum() -> float:
	return _quantum
