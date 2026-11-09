extends Node
## Lecture des sons. Tous les fichiers sont dans assets/audio (générés par tools/gen_audio.py).

var _cache := {}


func stream(sound: String) -> AudioStream:
	if sound == "":
		return null
	if _cache.has(sound):
		return _cache[sound]
	var path := "res://assets/audio/%s.ogg" % sound
	if not ResourceLoader.exists(path):
		push_warning("Son introuvable : " + path)
		_cache[sound] = null
		return null
	var st = load(path)
	if st is AudioStreamOggVorbis and (sound.begins_with("amb_") or sound.begins_with("task_") or sound.begins_with("music_")):
		st = st.duplicate()
		st.loop = true
	_cache[sound] = st
	return st


## Son d'interface ou non spatialisé.
func ui(sound: String, volume_db: float = 0.0, pitch: float = 1.0, bus: String = "SFX") -> void:
	var st := stream(sound)
	if st == null or not is_inside_tree():
		return
	var p := AudioStreamPlayer.new()
	p.stream = st
	p.bus = bus
	p.volume_db = volume_db
	p.pitch_scale = pitch
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


## Son ponctuel placé dans le monde.
func at(sound: String, pos: Vector3, volume_db: float = 0.0, pitch: float = 1.0, max_dist: float = 16.0) -> void:
	var st := stream(sound)
	var scene := get_tree().current_scene if is_inside_tree() else null
	if st == null or scene == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = st
	p.bus = "SFX"
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.max_distance = max_dist
	p.unit_size = 4.0
	scene.add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)


## Lecteur en boucle attaché à un nœud (ambiance d'une pièce, bruit d'une tâche).
func loop_player(parent: Node, sound: String, bus: String, volume_db: float, max_dist: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream(sound)
	p.bus = bus
	p.volume_db = volume_db
	p.max_distance = max_dist
	p.unit_size = 5.0
	parent.add_child(p)
	return p
