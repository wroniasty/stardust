class_name ComputerBay
extends Node2D
## The slot a flight computer goes in. Same shape as GeneratorBay and
## EngineMount: the slot is a hole in the hull and weighs nothing, what is
## fitted is the mass and has to fit.


@export var size: float = 1.5
@export var installed: FlightComputerData = null


func fits(data: FlightComputerData) -> bool:
	return data != null and data.bulk <= size


func module_mass() -> float:
	return installed.bulk if installed != null else 0.0
