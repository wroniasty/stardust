class_name JumpDriveBay
extends ModuleBay
## The slot a jump drive goes in.
func accepts(data: ModuleData) -> bool:
	return data is JumpDriveData
