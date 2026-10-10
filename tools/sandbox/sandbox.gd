class_name Sandbox
extends Node2D
## Pusta scena, od ktorej zaczyna sie nowy warsztat.
##
## The workbench that stood here was five panels, a form, a pin system
## and a debugger channel, grown one question at a time until the
## cheapest way forward was to start again. It is in the history rather
## than in a folder nobody opens: `git show 6d8c67a:tools/workbench/`.
##
## What it leaves behind is the one piece that had stopped being its
## own: `ResourceForm`, which the preset dock builds its rows from.
##
## Deliberately empty. The next thing put here should be put here
## because something needs it, not because the old bench had one.

## What the screen says while there is nothing on it, so a run that
## works is told apart from a run that failed to load.
const GREETING: String = "Sandbox: pusto. Esc konczy."


func _ready() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	var label: Label = Label.new()
	label.text = GREETING
	label.position = Vector2(8.0, 8.0)
	layer.add_child(label)
	add_child(layer)
