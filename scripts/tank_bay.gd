class_name TankBay
extends ModuleBay
## The slot a fuel tank goes in.
func accepts(data: ModuleData) -> bool:
	return data is TankData
