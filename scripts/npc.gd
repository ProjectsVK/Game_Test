extends AnimatableBody3D
## Un habitant du Secteur C : suit sa routine heure par heure, laisse des empreintes,
## garde en mémoire son trajet récent (pour la capacité Souvenir de Lina).

const Visual := preload("res://scripts/character_visual.gd")

var data: Dictionary
var main
var id := ""
var display_name := ""
var team := ""
var shoe := ""
var alive := true
var confined := false
var bed_index := 0
var sched: Array = []
var room := "dortoir"
var goal := "dortoir"
var path: Array = []
var hist: Array = []
var next_wander := 0.0
var speed := 1.5
var visual
var label: Label3D
var _dist := 0.0


func setup(d: Dictionary, m) -> void:
	data = d
	main = m
	id = d["id"]
	display_name = d["name"]
	team = d["team"]
	shoe = d["shoe"]
	sync_to_physics = false
	collision_layer = 4
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	cs.position = Vector3(0, 0.9, 0)
	add_child(cs)
	visual = Visual.new()
	add_child(visual)
	visual.build(GameData.TEAMS[team]["color"], d["hair"], d["skin"])

	label = Label3D.new()
	label.position = Vector3(0, 2.45, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.0035
	label.font_size = 44
	label.outline_size = 14
	label.outline_modulate = Color(0.02, 0.03, 0.05, 0.9)
	label.modulate = Color(0.95, 0.9, 0.82)
	label.text = display_name
	label.visible = false
	var f = load("res://assets/fonts/AlegreyaSans-Bold.woff2")
	if f:
		label.font = f
	add_child(label)

	# routine personnelle : la routine commune décalée de quelques minutes, plus ses habitudes
	var jit := Game.rng.randi_range(-15, 15)
	for row in GameData.BASE_SCHEDULE:
		var t: int = row[0] if row[0] == 360 else row[0] + jit
		sched.append([t, _resolve_room(row[1])])
	for row in d["extra"]:
		sched.append([int(row[0]) + jit, _resolve_room(row[1])])
	sched.sort_custom(func(a, b): return a[0] < b[0])


func _resolve_room(r: String) -> String:
	if r == "TEAM":
		return GameData.TEAMS[team]["room"]
	if r == "EVENING":
		return data["evening"]
	return r


func sched_room(m: float) -> String:
	var r := "dortoir"
	for row in sched:
		if m >= row[0]:
			r = row[1]
		else:
			break
	return r


func is_present() -> bool:
	return alive and not confined


func place_at(p: Vector3) -> void:
	global_position = p
	room = main.bunker.room_at(p)
	if room == "":
		room = "dortoir"
	goal = room
	path.clear()
	hist.clear()


## Appelé par le jeu à chaque image. time_scale = accélération du temps (touche F).
func tick(delta: float, time_scale: float) -> void:
	var want := sched_room(Game.minute)
	if want != goal:
		goal = want
		var from: String = main.bunker.room_at(global_position)
		if from == "":
			from = room
		var spot: Vector3 = main.bed_spot(self) if want == "dortoir" else main.bunker.room_spot(want, Game.rng)
		path = main.bunker.route(from, want, spot)
	if path.size() > 0:
		var tgt: Vector3 = path[0]
		var to := tgt - global_position
		to.y = 0.0
		var step := speed * time_scale * delta
		if to.length() <= step:
			global_position = Vector3(tgt.x, 0.0, tgt.z)
			path.pop_front()
			if path.is_empty():
				room = goal
				next_wander = Game.abs_time() + Game.rng.randf_range(25.0, 80.0)
		else:
			var dir := to.normalized()
			global_position += dir * step
			visual.face(dir, delta)
			_dist += step
			if _dist > 0.8:
				_dist = 0.0
				main.add_print(global_position, shoe, atan2(dir.x, dir.z), false, false, id)
		visual.walking = true
		visual.speed_factor = clampf(time_scale, 1.0, 3.0)
	else:
		visual.walking = false
		if room != "dortoir" and Game.abs_time() > next_wander:
			path = [main.bunker.room_spot(room, Game.rng)]
			next_wander = Game.abs_time() + Game.rng.randf_range(30.0, 90.0)
	var now := Game.abs_time()
	if hist.is_empty() or now - float(hist[-1]["t"]) >= 3.0:
		hist.append({"p": global_position, "t": now})
		if hist.size() > 30:
			hist.pop_front()
