class_name BenchBridge
extends Node
## The game's end of the link to the Godot editor.
##
## The editor is a different process from the bench, so an edit made in its
## inspector cannot reach the ship by reference. The editor plugin
## (`addons/stardust_devtools`) sends each changed property over the
## debugger channel instead, and this applies it to the same cached resource
## the ship is flying -- which is what makes a slider in the inspector
## audible on the next shot.
##
## Inert outside a debug session started from the editor: `EngineDebugger`
## is not active then, and the bench works as it always did.

## The prefix both ends agree on. Messages are "stardust:<what>".
const CHANNEL: StringName = &"stardust"

var _bench: Workbench = null


func bind(bench: Workbench) -> void:
	_bench = bench
	if not EngineDebugger.is_active():
		return
	EngineDebugger.register_message_capture(CHANNEL, _on_message)
	# Tells the plugin this session is a bench, so it does not send property
	# edits to a running game that has no idea what to do with them.
	EngineDebugger.send_message("%s:hello" % CHANNEL, [])


func _exit_tree() -> void:
	if EngineDebugger.is_active() and EngineDebugger.has_capture(CHANNEL):
		EngineDebugger.unregister_message_capture(CHANNEL)


## `message` arrives with the channel prefix already stripped.
func _on_message(message: String, data: Array) -> bool:
	if message != "set" or data.size() < 3:
		return false
	return apply(String(data[0]), String(data[1]), data[2])


## Writes one property of the resource at `path` and lets the ship notice.
## Public so a test can drive it without a debugger.
func apply(path: String, property: String, value: Variant) -> bool:
	var resource: Resource = load(path)
	if resource == null or not (property in resource):
		return false
	resource.set(property, value)
	resource.emit_changed()
	_bench.refresh_for(resource)
	return true
