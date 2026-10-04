@tool
class_name StardustBenchDebugger
extends EditorDebuggerPlugin
## The editor's end of the link to a running workbench. DEVTOOLS.md, D6.
##
## Remembers which debug sessions are a bench (they say hello when they
## start) and sends property edits only to those. A game started from the
## editor that is not the bench has nobody listening on this channel.

const CHANNEL: String = "stardust"

## Emitted when a bench connects or goes away, so the dock can say so.
signal link_changed(connected: bool)

var _live: Array[int] = []


func _has_capture(capture: String) -> bool:
	return capture == CHANNEL


func _capture(message: String, _data: Array, session_id: int) -> bool:
	if message != "%s:hello" % CHANNEL:
		return false
	if not _live.has(session_id):
		_live.append(session_id)
	link_changed.emit(true)
	return true


func _setup_session(session_id: int) -> void:
	get_session(session_id).stopped.connect(func() -> void:
		_live.erase(session_id)
		link_changed.emit(not _live.is_empty()))


func is_linked() -> bool:
	return not _live.is_empty()


## Sends one property of a resource to every connected bench.
func send_set(path: String, property: String, value: Variant) -> void:
	for session_id: int in _live:
		var session: EditorDebuggerSession = get_session(session_id)
		if session != null and session.is_active():
			session.send_message("%s:set" % CHANNEL, [path, property, value])
