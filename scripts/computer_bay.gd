class_name ComputerBay
extends ModuleBay
## The slot a flight computer goes in.
func accepts(data: ModuleData) -> bool:
	return data is FlightComputerData
