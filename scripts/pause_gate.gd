class_name PauseGate
extends RefCounted
## Who is currently holding the game paused, so that two screens cannot
## cancel each other out.
##
## Every screen that pauses also wants a guard against leaving the tree
## paused with nothing on screen to explain it -- a paused tree stops
## delivering input and looks exactly like a dead keyboard. The obvious guard
## is "if my panel is shut and the tree is paused, unpause it", and it is
## wrong the moment there are two such screens: the planet configurator
## dutifully released the pause the ship editor had just taken, the editor
## opened over a still-running game, and the ship fell out of the sky while
## its own schematic was on screen.
##
## So a pause is a claim held by a named holder, and the tree runs again only
## when the last claim is dropped. Each screen releases its own and never
## anyone else's.
##
## Static state on purpose, rather than an autoload: this has to work in the
## smoke test too, and autoloads do not exist under `--script`.

static var _holders: Array[Object] = []


## Claims a pause for `who`. Claiming twice is the same as claiming once.
static func hold(who: Object, tree: SceneTree) -> void:
	if not _holders.has(who):
		_holders.append(who)
	_apply(tree)


## Drops `who`'s claim. Safe to call when it never had one, which is what
## lets a screen call it unconditionally from _process as its own guard.
static func release(who: Object, tree: SceneTree) -> void:
	_holders.erase(who)
	_apply(tree)


static func held() -> bool:
	_forget_freed()
	return not _holders.is_empty()


static func _apply(tree: SceneTree) -> void:
	_forget_freed()
	if tree != null:
		tree.paused = not _holders.is_empty()


## A screen freed while holding a claim would otherwise keep the game paused
## for ever, with nothing left that could release it.
static func _forget_freed() -> void:
	var live: Array[Object] = []
	for holder: Object in _holders:
		if is_instance_valid(holder):
			live.append(holder)
	_holders = live
