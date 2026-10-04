class_name SoundStrip
extends Resource
## How a thing sounds: sample, path, loudness, pitch range, response time.
##
## The counterpart to `SpriteStrip`, and built for the same reason. A
## sample on its own is not a sound: the same recording played through
## the hull and played through the air are two different things, and
## the same loop at two response times is a jet or a hum. Those
## decisions were scattered across three nodes as arguments; here they
## are one file per kind of noise.
##
## **`path` is the field this exists for.** Getting conducted and
## airborne the wrong way round is invisible in an atmosphere and wrong
## everywhere else -- a gun that fell silent in vacuum, a crater that
## did not. As an argument at the call site it was three chances to
## mistype; as a property of the sound it is a thing you can read.

## The recording. A strip with none is a strip that plays nothing,
## which is a legitimate entry: a table can say "this kind makes no
## noise" without the caller branching.
@export var stream: AudioStream = null

## How it reaches the ear. Conducted through the hull you sit in,
## airborne through whatever air there is, or neither -- the interface
## is not in the world and does not obey its weather.
@export var path: Soundscape.Path = Soundscape.Path.CONDUCTED

## How loud at full, before whatever the caller scales it by.
@export var volume: float = 1.0

## Pitch at nothing and at full, in that order.
##
## Falling is as ordinary as rising here and means something different:
## an impact drops in pitch as it gets harder, because that is most of
## what makes a hit read as mass rather than as volume, while an engine
## climbs as it spools. The order of the two numbers says which.
@export var pitch: Vector2 = Vector2.ONE

## Seconds for a running sound to follow the thing driving it. Ignored
## by one-shots.
##
## The one number that makes an impulse engine sound like one. The
## simulation switches a torque jet fully on and off tick by tick, so
## the modulation is already in the code and this decides whether it
## gets through: twelve milliseconds is a jet, a hundred is a hum.
@export var response: float = 0.1

## Whether it runs until stopped rather than playing once.
@export var loops: bool = false


func is_valid() -> bool:
	return stream != null


## The pitch for a reading of 0..1. Clamped, because a caller handing
## in a share over one is asking about boost, and the pitch range is
## not where boost belongs -- the loudness is.
func pitch_at(share: float) -> float:
	return lerpf(pitch.x, pitch.y, clampf(share, 0.0, 1.0))
