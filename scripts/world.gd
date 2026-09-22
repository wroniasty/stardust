class_name World
extends Node2D
## World: scene root. Everything that physically exists lives under this node.
##
## The player never becomes a child of a system: systems are instantiated and
## freed underneath a player that stays put (see IDEAS.md section 9).

## Container the StreamingManager instantiates the active system into.
@onready var systems: Node2D = $Systems

## The player, kept as a direct child of the world for the whole game.
@onready var player: Node2D = $Player


func _ready() -> void:
	pass
