class_name Player
extends Node2D
## Player: the pilot. Owns the ship the camera follows and the streaming
## distances are measured from.

@onready var ship: Ship = $Ship


func _ready() -> void:
	pass
