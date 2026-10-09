class_name MountFit
extends Resource
## Jeden silnik w jednym miejscu kadluba, jako dane.
##
## One entry of what used to be a dictionary in `ShipFitout`'s table. The
## fields are the same ones `apply` always read; what changed is that an
## engine is now the resource itself rather than a short name looked up in
## a second table, so a preset cannot name an engine that does not exist.

## Which of the hull's places this fills, by the name `HullData.slots()`
## gives it: `NoseLeftTorque`, `StrafeRightThruster`, `MainDrive`.
##
## A role, not a position. The hull decides where that lands, which is
## what lets a hull be reshaped without touching any preset.
@export var place: StringName = &""

## What goes in it.
@export var engine: EngineData = null

## Multiplies the engine's thrust **and** its bulk, so a bigger engine is
## a heavier one: scaling only the thrust would be free power, which is
## the one thing a sandbox must not quietly hand out (IDEAS.md 14). How
## much of the increase is paid in bulk is `ShipFitout.BULK_SHARE`.
@export var scale: float = 1.0

## How big the socket is. Zero means "whatever this role takes", which is
## `ShipFitout.SOCKET_FOR` -- a fact about the job rather than about the
## ship, which is why almost every mount leaves this alone.
@export var socket: float = 0.0

## A main drive that swings on the centre line instead of being split
## across the pair either side of it. A different ship, not a different
## number: the twin-gimbal preset is built on it.
@export var centered: bool = false

## Where to put it when the hull has no place by this name, and which way
## to face.
##
## The last of the hand-written positions. One mount in the game needs it
## -- the forward-facing nozzle on the twin-gimbal ship, which no hull can
## describe yet -- and `ShipFitout.fault_in` asks for it only there.
@export var at: Vector2 = Vector2.ZERO
@export var turn: float = 0.0
