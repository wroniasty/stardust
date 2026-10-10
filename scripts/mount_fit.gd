@tool
class_name MountFit
extends Resource
## Jaki silnik idzie w ktore miejsca kadluba.
##
## By **kind**, not by name. One entry says "a torque jet in every torque
## place this hull offers", so the same preset builds a ship on a hull
## with two jets and on a hull with six, and the number of jets is a fact
## about the hull's `.tres` alone.
##
## It used to name one place per entry -- `NoseLeftTorque`,
## `StrafeRightThruster` -- which made a preset quietly hull-specific: a
## hull drawn with three torque places left one empty and nothing
## reported it, because the preset had two names and the hull had three.
## The stock dart went from eight entries to four when this changed, and
## the four say what the ship actually is.

## Which of the hull's kinds this fills: `HullData.SLOT_DRIVE`,
## `SLOT_TORQUE`, `SLOT_STRAFE`, `SLOT_RETRO`. Every place the hull offers
## of this kind gets one of these engines.
@export var kind: StringName = &""

## One named place instead of a whole kind, for the mount a kind cannot
## describe.
##
## Takes precedence over `kind` when set. The game has one: the
## forward-facing nozzle on the twin-gimbal ship, which is a second drive
## pointing the other way and which no hull offers a place for -- so it
## carries its own `at` and `turn` as well.
@export var place: StringName = &""

## What goes in.
@export var engine: EngineData = null

## Multiplies the engine's thrust **and** its bulk, so a bigger engine is
## a heavier one: scaling only the thrust would be free power, which is
## the one thing a sandbox must not quietly hand out (IDEAS.md 14). How
## much of the increase is paid in bulk is `ShipFitout.BULK_SHARE`.
@export var scale: float = 1.0

## How big the socket is. Zero means "whatever this kind takes", which is
## `ShipFitout.SOCKET_FOR` -- a fact about the job rather than about the
## ship, which is why almost every mount leaves this alone.
@export var socket: float = 0.0

## A main drive that swings on the centre line instead of being split
## across the pair either side of it. A different ship, not a different
## number: the twin-gimbal preset is built on it.
@export var centered: bool = false

## Pola tego zasobu, ktore ten wpis nadpisuje: nazwa pola -> wartosc.
##
## A preset that wants a weaker autocannon says `{"damage": 4.0}`, not a
## copy of the autocannon. The difference matters when the catalogue
## moves: an outright copy freezes all twenty-three of a weapon's fields
## at the values they had the day it was made, so retuning the shared
## file later changes every ship except the ones that meant to differ
## in one number. Everything unpinned here follows the file.
##
## Also the readable form. The `.tres` ends up saying `overrides = {
## "damage": 4.0 }`, which is the decision; an embedded copy says
## twenty-three numbers and leaves the reader to diff them.
@export var overrides: Dictionary = {}


## Where to put it, and which way to face, when `place` names somewhere
## the hull does not offer. Ignored otherwise: the hull decides.
@export var at: Vector2 = Vector2.ZERO
@export var turn: float = 0.0
