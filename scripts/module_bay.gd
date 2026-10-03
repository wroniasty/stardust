class_name ModuleBay
extends Node2D
## Gniazdo w kadłubie: gdzie siedzi moduł i ile go się tam mieści.
##
## The slot is a hole in the hull. It weighs nothing; what is fitted into
## it is the mass, and it has to be no bulkier than the hole. Keeping the
## geometry here and the machine in a `Resource` is what lets a module be
## loot -- the same split as `EngineMount` and `Hardpoint`.
##
## One class, five slots. There used to be one class per kind, each
## seventeen lines and sixteen of them the same, and every list in the
## ship and the editor named them one at a time. Two of those was a
## pattern; five would have been four places in `ship.gd` naming eight
## bays by hand and a sixth kind arriving to be forgotten in one of them.
## What differs between slots is which modules they take, and that is one
## overridden method.
##
## How big the hole is belongs to the **hull**, not to the kind of slot:
## two ships with a generator bay are allowed to disagree about how much
## generator fits. So `size` is set in the scene rather than defaulted per
## subclass, which is also the only way it could be, now that there is one
## subclass-shaped thing left and it is a type check.

## How much module fits, against `ModuleData.bulk`.
@export var size: float = 1.0

## What is in it, or null for an empty slot.
@export var installed: ModuleData = null


## Whether this kind of slot takes this kind of module. Overridden by each
## slot; the base takes anything, which is what a test bay wants.
func accepts(_data: ModuleData) -> bool:
	return true


## Whether this module could go in: right kind, and small enough.
##
## Both halves, which the per-kind classes never checked: each was typed
## to its own data class, so the kind test was done by the caller and
## anything that reached `fits` was already the right sort. Now that the
## slots are one class the kind has to be asked about here, which is the
## better place for it anyway -- the editor was the one deciding what goes
## where, and that is the hull's business.
func fits(data: ModuleData) -> bool:
	return data != null and data.bulk <= size and accepts(data)


## Mass the slot contributes: the module's own bulk, nothing when empty.
func module_mass() -> float:
	return installed.bulk if installed != null else 0.0
