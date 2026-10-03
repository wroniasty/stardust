class_name GeneratorBay
extends ModuleBay
## The slot a generator bolts into.
##
## Everything a slot does lives in `ModuleBay`; what is left is which kind
## of machine this one takes, which is the only thing that was ever
## different between the five of them.
func accepts(data: ModuleData) -> bool:
	return data is GeneratorData
