extends SceneTree
## Writes every hull's default slot positions into its .tres, so they are data
## on the resource rather than something worked out at load. Run once after
## adding a hull, then move the numbers by hand if a layout wants it:
##   godot --headless --path . --script res://tools/bake_hull_slots.gd
##
## Only fills a list that is empty, so a hand-placed layout survives a re-run.


func _init() -> void:
	for file_name: String in ResourceLoader.list_directory(HullData.DIRECTORY):
		if not file_name.ends_with(".tres"):
			continue
		var path: String = "%s/%s" % [HullData.DIRECTORY, file_name]
		var hull: HullData = load(path) as HullData
		if hull == null:
			continue
		var defaults: Dictionary = hull.default_positions()
		_fill(hull.drive_slots, defaults[HullData.SLOT_DRIVE])
		_fill(hull.front_slots, defaults[HullData.SLOT_FRONT])
		_fill(hull.side_slots, defaults[HullData.SLOT_SIDE])
		_fill(hull.rear_slots, defaults[HullData.SLOT_REAR])
		var error: Error = ResourceSaver.save(hull, path)
		print("%s: %s" % [path, "saved" if error == OK else "FAILED (%d)" % error])
	quit()


## Rounded to a quarter pixel: a layout somebody will read and nudge by hand.
func _fill(into: Array[Vector2], from: Array) -> void:
	if not into.is_empty():
		return
	for point: Vector2 in from:
		into.append(Vector2(snappedf(point.x, 0.25), snappedf(point.y, 0.25)))
