extends Node
## État de la partie (temps, indices, connaissances) et touches du jeu.

signal toast(text: String, kind: String)

var day := 1
var minute := 360.0
var paused := true
var over := false
var wrong := 0
var clues: Array = []
var clue_keys := {}
var know := {}     # id habitant -> {"seen": "L", "claim": "S"}
var struck := {}   # id habitant -> true si écarté dans le carnet
var rng := RandomNumberGenerator.new()


var volumes := {"Master": 0.8, "Music": 0.45, "SFX": 0.8, "Ambience": 0.6}
var paint_filter := true


func _ready() -> void:
	rng.randomize()
	_setup_inputs()
	_setup_buses()


## Bus audio : musique, effets et ambiance se règlent séparément dans le menu pause.
func _setup_buses() -> void:
	for bus in ["Music", "SFX", "Ambience"]:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus)
			AudioServer.set_bus_send(idx, "Master")
	for bus in volumes:
		set_volume(bus, volumes[bus])


func set_volume(bus: String, linear: float) -> void:
	volumes[bus] = linear
	var idx := AudioServer.get_bus_index(bus)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
		AudioServer.set_bus_mute(idx, linear <= 0.001)


## Touches physiques : Z/Q/S/D sur AZERTY et W/A/S/D sur QWERTY tombent au même endroit.
func _setup_inputs() -> void:
	var map := {
		"move_forward": [KEY_W, KEY_UP],
		"move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"sprint": [KEY_SHIFT],
		"ability_1": [KEY_1, KEY_KP_1],
		"ability_2": [KEY_2, KEY_KP_2],
		"ability_3": [KEY_3, KEY_KP_3],
		"ability_4": [KEY_4, KEY_KP_4],
				"notebook": [KEY_C],
		"interact": [KEY_E],
		"fast_time": [KEY_F],
		"end_day": [KEY_N],
		"cancel": [KEY_ESCAPE],
		"toggle_paint": [KEY_P],
	}
	for action in map:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for code in map[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = code
			InputMap.action_add_event(action, ev)


func reset() -> void:
	day = 1
	minute = 360.0
	paused = true
	over = false
	wrong = 0
	clues.clear()
	clue_keys.clear()
	know.clear()
	struck.clear()
	rng.randomize()


func abs_time() -> float:
	return day * 1440.0 + minute


func hhmm(m: float) -> String:
	var t := int(floor(m)) % 1440
	if t < 0:
		t += 1440
	return "%02d:%02d" % [t / 60, t % 60]


func add_clue(text: String, key: String = "") -> bool:
	if key != "" and clue_keys.has(key):
		return false
	if key != "":
		clue_keys[key] = true
	clues.append({"day": day, "text": text})
	toast.emit("Indice : " + text, "clue")
	Sfx.ui("ui_clue")
	return true


func say(text: String, kind: String = "") -> void:
	toast.emit(text, kind)


func know_of(id: String) -> Dictionary:
	if not know.has(id):
		know[id] = {}
	return know[id]


## « de Elio » devient « d'Elio ».
func de(who: String) -> String:
	var first := who.substr(0, 1).to_lower()
	if first in ["a", "e", "i", "o", "u", "y", "é", "è"]:
		return "d'" + who
	return "de " + who
