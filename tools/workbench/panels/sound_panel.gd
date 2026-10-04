class_name BenchSoundPanel
extends VBoxContainer
## Every sound the game can make, one button each, through the game's own
## `Soundscape`.
##
## The tables are the same files the ship reads (`resources/fx/sounds/`), so
## what plays here is what plays in flight and a table edited in the editor
## is what is heard on the next press. The air slider is a pin on the ship's
## `air_density`: the low-pass on the Sfx bus and the airborne cut-off both
## follow it exactly as they do on arrival at a planet, which is the whole
## point of auditioning a sound in a scene with no planet.
##
## One-shots go through `Soundscape.play`, so the "vacuum is quiet" rule
## applies and a silent press means silence by rule rather than a broken
## button. Loops are run by this panel, on the same buses, and follow the
## sliders live.

const DIRECTORY: String = "res://resources/fx/sounds"

## The three ways a sound reaches the ear, and "as the table says".
const PATH_CHOICES: Array[String] = ["jak w tabeli", "przez kadłub", "przez powietrze", "interfejs"]

var _bench: Workbench = null
var _ship: Ship = null
var _sound: Soundscape = null

var _tables: Array[SoundTable] = []
var _table_names: Array[String] = []

var _table_pick: OptionButton = null
var _path_pick: OptionButton = null
var _share: HSlider = null
var _volume: HSlider = null
var _air: HSlider = null
var _status: Label = null
var _list: VBoxContainer = null

## Strip -> the player running its loop, for those that are on.
var _running: Dictionary = {}


func bind(bench: Workbench, ship: Ship) -> void:
	_bench = bench
	_ship = ship
	_sound = _find_soundscape()
	_load_tables()
	_build()
	_fill()


func _find_soundscape() -> Soundscape:
	return Soundscape.of()


func _load_tables() -> void:
	var names: Array = Array(ResourceLoader.list_directory(DIRECTORY))
	names.sort()
	for file_name: String in names:
		if not file_name.ends_with(".tres"):
			continue
		var table: SoundTable = load("%s/%s" % [DIRECTORY, file_name]) as SoundTable
		if table != null:
			_tables.append(table)
			_table_names.append(file_name.get_basename())


func _build() -> void:
	add_child(BenchForm.heading("tabela"))
	_table_pick = OptionButton.new()
	for table_name: String in _table_names:
		_table_pick.add_item(table_name)
	_table_pick.item_selected.connect(func(_i: int) -> void: _fill())
	add_child(_table_pick)

	add_child(BenchForm.heading("jak"))
	_share = BenchForm.slider(0.0, 1.0, 0.01, 1.0)
	add_child(BenchForm.labelled("siła 0..1", _share))
	_volume = BenchForm.slider(0.0, 2.0, 0.01, 1.0)
	add_child(BenchForm.labelled("głośność", _volume))
	_air = BenchForm.slider(0.0, 1.0, 0.01, 0.0)
	_air.value_changed.connect(func(v: float) -> void: _bench.pins.pin(&"air_density", v))
	add_child(BenchForm.labelled("powietrze", _air))
	_path_pick = OptionButton.new()
	for choice: String in PATH_CHOICES:
		_path_pick.add_item(choice)
	add_child(BenchForm.labelled("droga", _path_pick))
	add_child(BenchForm.button("zatrzymaj pętle", _stop_all))

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)

	add_child(BenchForm.heading("dźwięki"))
	_list = VBoxContainer.new()
	add_child(_list)


## The rows for the chosen table: every strip it can hand out, labelled with
## why it would be handed out.
func _fill() -> void:
	_stop_all()
	for child: Node in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	if _tables.is_empty():
		_list.add_child(BenchForm.note("brak tabel w %s" % DIRECTORY))
		return
	var table: SoundTable = _tables[_table_pick.selected]
	for entry: Dictionary in _entries(table):
		_list.add_child(_row(entry["label"] as String, entry["strip"] as SoundStrip))
	if table.stat != &"":
		_list.add_child(_measured_row(table))


## Every strip in a table with the reason it plays, in the table's own order.
func _entries(table: SoundTable) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in range(table.variants.size()):
		var from: float = table.thresholds[i] if i < table.thresholds.size() else 0.0
		out.append({"label": "%s >= %s" % [table.stat, str(from)], "strip": table.variants[i]})
	for key: Variant in table.by_key:
		out.append({"label": "klucz %s" % str(key), "strip": table.by_key[key]})
	for affix: Variant in table.by_affix:
		out.append({"label": "affix %s" % str(affix), "strip": table.by_affix[affix]})
	if table.fallback != null:
		out.append({"label": "domyślny", "strip": table.fallback})
	return out


func _row(label: String, strip: SoundStrip) -> Control:
	var button: Button = Button.new()
	button.clip_text = true
	if strip == null or not strip.is_valid():
		button.text = "%s (cisza)" % label
		button.disabled = true
		return button
	button.text = "%s %s" % ["pętla" if strip.loops else "▶", label]
	if strip.loops:
		button.toggle_mode = true
		button.toggled.connect(_on_loop.bind(strip))
	else:
		button.pressed.connect(_on_play.bind(strip))
	return button


## A table that chooses by measurement can be asked about a number directly,
## which is how "what does a bigger engine sound like" gets answered without
## fitting one.
func _measured_row(table: SoundTable) -> Control:
	var box: HBoxContainer = HBoxContainer.new()
	var value: SpinBox = SpinBox.new()
	value.min_value = -1000.0
	value.max_value = 100000.0
	value.step = 0.5
	value.custom_minimum_size = Vector2(70.0, 0.0)
	var go: Button = Button.new()
	go.text = "▶ %s =" % table.stat
	go.pressed.connect(func() -> void: _on_play(table.by_value(value.value)))
	box.add_child(go)
	box.add_child(value)
	return box


func _on_play(strip: SoundStrip) -> void:
	if _sound == null or strip == null:
		return
	var path: Soundscape.Path = _path_of(strip)
	var pitch: float = strip.pitch_at(_share.value)
	var played: bool = _sound.play(
		strip.stream, _ship.global_position, path, strip.volume * _volume.value, pitch
	)
	_status.text = "%s, droga %s: %s" % [
		_name_of(strip), Soundscape.Path.keys()[path],
		"zagrało" if played else "cisza (powietrza brak albo zbyt cicho)",
	]


func _on_loop(on: bool, strip: SoundStrip) -> void:
	if not on:
		_stop(strip)
		return
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.stream = strip.stream
	# A stream that does not loop by itself is restarted when it ends, so a
	# strip marked `loops` is heard as one whatever the sample says.
	player.finished.connect(func() -> void:
		if _running.has(strip):
			player.play())
	add_child(player)
	_running[strip] = player
	_follow(strip, player)
	player.play()


func _stop(strip: SoundStrip) -> void:
	var player: AudioStreamPlayer = _running.get(strip) as AudioStreamPlayer
	_running.erase(strip)
	if player != null:
		player.stop()
		remove_child(player)
		player.queue_free()


func _stop_all() -> void:
	for strip: SoundStrip in _running.keys():
		_stop(strip)
	if _list != null:
		for child: Node in _list.get_children():
			var button: Button = child as Button
			if button != null and button.toggle_mode:
				button.set_pressed_no_signal(false)


func _process(_delta: float) -> void:
	for strip: SoundStrip in _running:
		_follow(strip, _running[strip] as AudioStreamPlayer)


## Sets a running loop from the sliders and the air, the way the choir sets
## an engine's.
func _follow(strip: SoundStrip, player: AudioStreamPlayer) -> void:
	var path: Soundscape.Path = _path_of(strip)
	var carried: float = _sound.carries(path) if _sound != null else 1.0
	player.bus = String(Soundscape.BUS_UI if path == Soundscape.Path.INTERFACE else Soundscape.BUS_SFX)
	player.volume_db = linear_to_db(maxf(carried * strip.volume * _volume.value, 0.0001))
	player.pitch_scale = clampf(strip.pitch_at(_share.value), 0.1, 4.0)


func _path_of(strip: SoundStrip) -> Soundscape.Path:
	match _path_pick.selected:
		1:
			return Soundscape.Path.CONDUCTED
		2:
			return Soundscape.Path.AIRBORNE
		3:
			return Soundscape.Path.INTERFACE
		_:
			return strip.path


func _name_of(strip: SoundStrip) -> String:
	return strip.stream.resource_path.get_file().get_basename() if strip.stream != null else "-"


func _exit_tree() -> void:
	# A running loop still referenced at exit is a leak the check fails on.
	for strip: SoundStrip in _running.keys():
		_stop(strip)
