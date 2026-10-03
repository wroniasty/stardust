class_name ScannerBay
extends ModuleBay
## The slot a survey scanner goes in.
func accepts(data: ModuleData) -> bool:
	return data is ScannerData
