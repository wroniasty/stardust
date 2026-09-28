class_name GeneratorBay
extends Node2D
## The slot a generator bolts into: where it sits, and how much of one fits.
##
## The same shape as EngineMount, and for the same reasons. The bay is a hole
## in the hull and weighs nothing; what is fitted into it is the mass, and it
## has to be no bulkier than the slot. Keeping the geometry here and the
## machine in the Resource is what lets a generator be loot.

## How much generator the bay has room for, against GeneratorData.bulk.
@export var size: float = 3.0

## The generator currently fitted, or null for an empty bay -- a ship running
## on the hull's own rail.
@export var installed: GeneratorData = null


func fits(data: GeneratorData) -> bool:
	return data != null and data.bulk <= size


## Mass the bay contributes: the generator's own bulk, nothing when empty.
func module_mass() -> float:
	return installed.bulk if installed != null else 0.0
