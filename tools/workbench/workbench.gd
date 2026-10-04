class_name Workbench
extends Node2D
## The laboratory: one real ship on an empty stage, and forms to change it.
##
##     godot --path . tools/workbench/workbench.tscn
##
## DEVTOOLS.md is the plan. The short version is that the bench builds
## nothing of its own: the ship is `ship.tscn`, the noises are the same
## `Soundscape`, `EngineChoir`, `HullVoice` and `OrdnanceVoice` the game
## runs, wired by `ship_path` exactly as `world.tscn` wires them. A preview
## that drew or played anything through different code would be previewing
## the preview.
##
## There is no planet, so the ship drifts in vacuum, which is the right
## background for judging engines. What a planet would have supplied (air,
## starlight) is supplied by pins instead.
##
## Nothing under `scripts/` knows this exists.

const SHIP_SCENE: PackedScene = preload("res://scenes/ship.tscn")
const STARFIELD_SCENE: PackedScene = preload("res://scenes/starfield.tscn")

const FONT_SIZE: int = 8
const PANEL_WIDTH: float = 232.0
const SCREEN_MARGIN: int = 6
const BACKGROUND: Color = Color(0.06, 0.07, 0.10, 0.97)
const BORDER: Color = Color(0.50, 0.45, 0.62, 1.0)

## How long a wreck lies about before the bench puts the ship back. Long
## enough to see and hear the death, short enough not to be in the way.
const RESPAWN_DELAY: float = 1.6

var ship: Ship = null
var pins: BenchPins = null
var dummies: BenchDummies = null
var bridge: BenchBridge = null

var _panel: PanelContainer = null
var _tabs: TabContainer = null
var _ship_panel: BenchShipPanel = null
var _state_panel: BenchStatePanel = null
var _fire_panel: BenchFirePanel = null
var _sound_panel: BenchSoundPanel = null
var _resource_panel: BenchResourcePanel = null

## Actions the bench is holding down for the pilot, so the hover guard below
## lets go of the mouse buttons without letting go of these.
var _held: Dictionary = {}


func _ready() -> void:
	# Before the ship, so anything the bench does to the input this tick is
	# done by the time the ship reads it.
	process_physics_priority = -10

	var stars: CanvasLayer = STARFIELD_SCENE.instantiate() as CanvasLayer
	stars.set("ship_path", NodePath("../Ship"))
	add_child(stars)

	var projectiles: Node2D = Node2D.new()
	projectiles.name = "Projectiles"
	projectiles.add_to_group(Ship.PROJECTILE_GROUP)
	add_child(projectiles)

	ship = SHIP_SCENE.instantiate() as Ship
	ship.name = "Ship"
	add_child(ship)
	ship.destroyed.connect(_on_ship_destroyed)

	pins = BenchPins.new()
	pins.name = "Pins"
	pins.ship = ship
	add_child(pins)

	dummies = BenchDummies.new()
	dummies.name = "Dummies"
	add_child(dummies)

	bridge = BenchBridge.new()
	bridge.name = "Bridge"
	add_child(bridge)
	bridge.bind(self)

	_build_presentation()
	_build_camera()
	_build_ui()


## The same presentation nodes `world.tscn` has, wired the same way.
func _build_presentation() -> void:
	var holder: Node2D = Node2D.new()
	holder.name = "Presentation"
	add_child(holder)
	var parts: Array[Array] = [
		["Soundscape", "res://scripts/fx/soundscape.gd"],
		["EngineChoir", "res://scripts/fx/engine_choir.gd"],
		["HullVoice", "res://scripts/fx/hull_voice.gd"],
		["OrdnanceVoice", "res://scripts/fx/ordnance_voice.gd"],
		["DebrisField", "res://scripts/fx/debris_field.gd"],
		["CameraShake", "res://scripts/fx/camera_shake.gd"],
	]
	for part: Array in parts:
		var script: GDScript = load(part[1] as String) as GDScript
		var node: Node = script.new() as Node
		node.name = part[0] as String
		if "ship_path" in node:
			node.set("ship_path", NodePath("../../Ship"))
		if "camera_path" in node:
			node.set("camera_path", NodePath("../../Camera"))
		holder.add_child(node)


func _build_camera() -> void:
	var camera: ShipCamera = ShipCamera.new()
	camera.name = "Camera"
	camera.target_path = NodePath("../Ship")
	add_child(camera)


func _build_ui() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 30
	add_child(layer)

	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Steps out of the way of the mouse: a full-rect container with the
	# default filter swallows every click on the whole screen, and the whole
	# point of the bench is to click on the stage and shoot.
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, SCREEN_MARGIN)
	layer.add_child(margin)

	var compact: Theme = Theme.new()
	compact.default_font_size = FONT_SIZE
	var background: StyleBoxFlat = StyleBoxFlat.new()
	background.bg_color = BACKGROUND
	background.border_color = BORDER
	background.set_border_width_all(1)
	background.set_content_margin_all(4)
	compact.set_stylebox("panel", "PanelContainer", background)

	_panel = PanelContainer.new()
	_panel.theme = compact
	_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	margin.add_child(_panel)

	_tabs = TabContainer.new()
	_tabs.custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
	_panel.add_child(_tabs)

	_ship_panel = BenchShipPanel.new()
	_add_tab("Statek", _ship_panel)
	_ship_panel.bind(self, ship)
	_state_panel = BenchStatePanel.new()
	_add_tab("Stany", _state_panel)
	_state_panel.bind(self, ship)
	_fire_panel = BenchFirePanel.new()
	_add_tab("Ogień", _fire_panel)
	_fire_panel.bind(self, ship)
	_sound_panel = BenchSoundPanel.new()
	_add_tab("Dźwięk", _sound_panel)
	_sound_panel.bind(self, ship)
	_resource_panel = BenchResourcePanel.new()
	_add_tab("Zasoby", _resource_panel)
	_resource_panel.bind(self, ship)


## One scrolling page per panel, so a long form scrolls under its tab header
## instead of pushing the header off the screen.
func _add_tab(title: String, content: Control) -> void:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	_tabs.add_child(scroll)


func _unhandled_input(_event: InputEvent) -> void:
	if Input.is_action_just_pressed(&"bench_toggle_panel") and _panel != null:
		_panel.visible = not _panel.visible


func _physics_process(_delta: float) -> void:
	# A click on a form is not a shot. The ship polls the mouse button
	# itself, so a press that landed on the panel would fire the guns; the
	# release is repeated every tick because the held button would otherwise
	# be read as pressed again.
	if get_viewport().gui_get_hovered_control() != null:
		for action: StringName in [&"ship_fire", &"ship_fire_secondary"]:
			if not _held.has(action):
				Input.action_release(action)


## Lets the ship notice that a resource it may be using has changed.
##
## Mounted weapons cache what they throw, and engines feed the control groups
## and the mass, so both are asked to recompute. A hull is not re-fitted on
## every nudge: reshaping the ship under a slider would throw away whatever
## was being tested, and the Zasoby tab has a button for it.
func refresh_for(resource: Resource) -> void:
	for hardpoint: Hardpoint in ship.hardpoints:
		if hardpoint.weapon == resource:
			hardpoint.fit(hardpoint.weapon)
	ship.rebuild_control_groups(false)


## Presses or releases an input action on the pilot's behalf, through the
## Input Map like a key would, so the ship's own reading of it is what is
## being tested rather than a shortcut around it.
func hold(action: StringName, on: bool) -> void:
	if on:
		_held[action] = true
		Input.action_press(action)
	else:
		_held.erase(action)
		Input.action_release(action)


## Reshapes the ship's hull and keeps everything bolted to it.
##
## The tool's own copy of `CreativeTool._on_reshape`, not a call into it:
## that one is tied to its panel. Both do what `ShipFitout.apply` does for
## the hull, and the drawn polygon follows so a reshaped hull shows the
## shape it actually got.
func apply_hull(hull: HullData, factor: float) -> void:
	var outline: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in hull.outline:
		outline.append(point * factor)
	ship.hull_outline = outline
	if hull.cargo_capacity > 0.0:
		ship.hull_cargo_capacity = hull.cargo_capacity
	if ship.gear != null and not hull.legs.is_empty():
		var legs: Array[Vector2] = []
		for leg: Vector2 in hull.legs:
			legs.append(leg * factor)
		ship.gear.legs = legs
	var drawn: Polygon2D = ship.get_node_or_null("Hull") as Polygon2D
	if drawn != null:
		drawn.polygon = outline
	ship._build_contact_points()
	ship._build_collision_shape()
	ship.rebuild_control_groups(false)


## Puts the ship back where it started, intact and at rest.
func reset_ship() -> void:
	ship.respawn(Vector2.ZERO, Vector2.ZERO)


func _on_ship_destroyed(_at: Vector2, _velocity: Vector2) -> void:
	# The world would spawn an explosion and respawn the ship; the bench only
	# does the second, because the first needs a scene it does not carry.
	get_tree().create_timer(RESPAWN_DELAY).timeout.connect(reset_ship)
