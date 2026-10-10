@tool
class_name GunFit
extends Resource
## Ktore dzialo i w ktorym hardpoincie kadluba.
##
## The guns used to be a bare list of weapons handed out in hull order:
## front places first, then the sides, then astern. That is still what
## most presets want and still what an entry with no `place` means -- but
## it left no way to say "the rocket goes in the rear hardpoint", which
## is a thing a ship design is allowed to be about.

## The hull place this fills, by the name `HullData.slots()` gives it.
##
## Empty means "the next gun place the hull offers that nothing else has
## claimed", which is how a list of weapons alone always behaved. A
## pinned gun takes its place before the loose ones are dealt out, so
## naming the rear hardpoint gets it even when an unpinned gun would
## otherwise have reached it first.
@export var place: StringName = &""

## What is bolted there.
@export var weapon: WeaponData = null
