class_name ModuleBay
extends Node2D
## A socket in the hull: where a module sits, and how much of one fits there.
##
## The slot is a hole in the hull. It weighs nothing; what is fitted into
## it is the mass, and it has to be no bulkier than the hole. Keeping the
## geometry here and the machine in a `Resource` is what lets a module be
## loot -- the same split as `EngineMount` and `Hardpoint`.
##
## **A hole has no opinion about what goes in it.** There used to be one
## class per kind, and then one class with five subclasses whose whole job
## was an `accepts()` returning `data is GeneratorData`. Both encoded the
## same idea: that a ship is born with one generator socket and one tank
## socket, and that no amount of refitting could ever make it a ship with
## two tanks and no scanner. How many sockets a ship has and how big they
## are is a property of the ship, so it belongs to the preset that
## describes one; which machine goes in which is the pilot's business.
##
## What a bay does still refuse is a machine that has a socket of its own.
## Guns go in hardpoints, engines in mounts, legs in the landing gear --
## and `WeaponData`, `EngineData` and `GearData` are all `ModuleData`
## subclasses, so without that rule a generic bay would cheerfully
## swallow a main drive.

## How much module fits, against `ModuleData.bulk`. Set by whoever builds
## the bay: `ShipPreset` for a ship out of the catalogue.
@export var size: float = 1.0

## What is in it, or null for an empty slot.
@export var installed: ModuleData = null


## Whether a bay is the right sort of place for this machine at all.
##
## Written as the exclusion rather than as a list of the kinds that do
## fit, because the point of a bay without a kind is that a sixth sort of
## module works without being added to a table here. The three that are
## excluded are excluded for a reason that will not change: they already
## have somewhere to go.
func takes(data: ModuleData) -> bool:
	return data != null and not (
		data is WeaponData or data is EngineData or data is GearData
	)


## Whether this module could go in: somewhere it belongs, and small
## enough for the hole.
func fits(data: ModuleData) -> bool:
	return takes(data) and data.bulk <= size


## Mass the slot contributes: the module's own bulk, nothing when empty.
func module_mass() -> float:
	return installed.bulk if installed != null else 0.0
