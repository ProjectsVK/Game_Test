extends AnimatableBody3D
## Un habitant du Secteur C. Sa journée est faite de tâches visibles : il va à un poste précis
## (fourneau, établi, lavabo…), fait le geste avec un objet en main, avec un petit effet et un son.
## Il garde aussi son trajet récent en mémoire (capacité Fil rouge) et laisse des empreintes.

const Visual := preload("res://scripts/character_visual.gd")

var data: Dictionary
var main
var id := ""
var display_name := ""
var role := ""
var team := ""
var shoe := ""
var alive := true
var confined := false
var bed_index := 0
var sched: Array = []
var phase := "wake"
var state := "idle"         # idle, travel, task
var station := ""           # poste visé ou occupé
var task_label := "Se réveille"
var path: Array = []
var hist: Array = []
var speed := 1.5
var visual
var label: Label3D
var talk_until := 0.0       # se tourne vers Lina pendant qu'elle lui parle

var _task_end := 0.0
var _task_i := 0
var _dist := 0.0
var _fx: Node3D
var _snd: AudioStreamPlayer3D
var _final_yaw := 0.0

static var _fx_mats := {}


func setup(d: Dictionary, m) -> void:
	data = d
	main = m
	id = d["id"]
	display_name = d["name"]
	role = d["role"]
	team = d["team"]
	shoe = d["shoe"]
	sync_to_physics = false
	collision_layer = 4      # visé par le regard de Lina, mais ne la bloque jamais
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	var h: float = d["look"].get("height", 1.0)
	cap.radius = 0.35
	cap.height = 1.8 * h
	cs.shape = cap
	cs.position = Vector3(0, 0.9 * h, 0)
	add_child(cs)
	visual = Visual.new()
	add_child(visual)
	visual.build_look(d["look"])
	visual.step.connect(_on_step)
	speed = 1.25 * float(d["look"]["gait"].get("speed", 1.0))

	label = Label3D.new()
	label.position = Vector3(0, 2.25 * h + 0.15, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.0032
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

	_snd = AudioStreamPlayer3D.new()
	_snd.bus = "SFX"
	_snd.volume_db = -9.0
	_snd.max_distance = 9.0
	_snd.unit_size = 3.0
	add_child(_snd)

	# routine personnelle : la routine commune décalée de quelques minutes
	var jit := Game.rng.randi_range(-12, 12)
	for row in GameData.BASE_SCHEDULE:
		var t: int = row[0] if row[0] == 360 else row[0] + jit
		sched.append([t, row[1]])
	_task_i = Game.rng.randi() % maxi(1, d["work"].size())


func sched_phase(m: float) -> String:
	var r := "sleep"
	for row in sched:
		if m >= row[0]:
			r = row[1]
		else:
			break
	return r


func is_present() -> bool:
	return alive and not confined


func color() -> Color:
	return GameData.TEAMS[team]["color"]


## Remet l'habitant debout devant son lit (chaque matin).
func place_at(p: Vector3) -> void:
	_leave_station()
	global_position = p
	path.clear()
	hist.clear()
	phase = "wake"
	state = "idle"
	task_label = "Se réveille"
	visual.walking = false


## Appelé à chaque image. time_scale = accélération du temps (touche F).
func tick(delta: float, time_scale: float) -> void:
	var now := Game.abs_time()
	var want := sched_phase(Game.minute)
	if want != phase:
		phase = want
		_plan_next()
	elif state == "task" and now >= _task_end and (phase == "work" or phase == "evening"):
		_plan_next()
	elif state == "idle" and now >= _task_end and phase != "wake" and phase != "sleep":
		_plan_next()

	if state == "travel":
		_walk(delta, time_scale)
	else:
		visual.walking = false
		if talk_until > Time.get_ticks_msec() / 1000.0 and main.player:
			var to: Vector3 = main.player.global_position - global_position
			to.y = 0.0
			visual.face(to, delta)
		else:
			visual.set_yaw(lerp_angle(visual.rotation.y, _final_yaw, 1.0 - exp(-8.0 * delta)))

	if hist.is_empty() or now - float(hist[-1]["t"]) >= 3.0:
		hist.append({"p": global_position, "t": now})
		if hist.size() > 30:
			hist.pop_front()


func _walk(delta: float, time_scale: float) -> void:
	if path.is_empty():
		_arrive()
		return
	var tgt: Vector3 = path[0]
	var to := tgt - global_position
	to.y = 0.0
	var step := speed * time_scale * delta
	if to.length() <= step:
		global_position = Vector3(tgt.x, 0.0, tgt.z)
		path.pop_front()
		if path.is_empty():
			_arrive()
	else:
		var dir := to.normalized()
		global_position += dir * step
		visual.face(dir, delta)
		_final_yaw = visual.rotation.y
		_dist += step
		if _dist > 0.8:
			_dist = 0.0
			main.add_print(global_position, shoe, atan2(dir.x, dir.z), false, false, id)
	visual.walking = true
	visual.speed_factor = clampf(time_scale, 1.0, 2.5)


# ---------------------------------------------------------------- choix des tâches

func _plan_next() -> void:
	_leave_station()
	var dest := Vector3.ZERO
	match phase:
		"wake", "sleep":
			dest = main.bed_spot(self)
			task_label = "Va se coucher" if phase == "sleep" else "Se réveille"
			_go(dest, "", "Va se coucher" if phase == "sleep" else "Se lève")
			return
		"meal":
			var seats: Array = []
			for k in GameData.STATIONS:
				if k.begins_with("seat_"):
					seats.append(k)
			seats.shuffle()
			for k in seats:
				if main.claim_station(k, self):
					_go_station(k)
					return
		"work", "evening":
			var list: Array = data["work"] if phase == "work" else data["evening"]
			for i in list.size():
				var k: String = list[(_task_i + i) % list.size()]
				if k != station and main.claim_station(k, self):
					_task_i = (_task_i + i + 1) % list.size()
					_go_station(k)
					return
	# rien de libre : il flâne dans sa salle d'équipe
	var room: String = GameData.TEAMS[team]["room"]
	var spot: Vector3 = main.bunker.center(room) + Vector3(Game.rng.randf_range(-1.5, 1.5), 0, Game.rng.randf_range(-1.5, 1.5))
	_go(spot, "", "Flâne " + GameData.ROOMS[room]["at"])
	_task_end = Game.abs_time() + Game.rng.randf_range(15.0, 30.0)


func _go_station(k: String) -> void:
	station = k
	var st: Dictionary = GameData.STATIONS[k]
	var pos := Vector3(st["pos"][0], 0, st["pos"][1])
	var face := Vector3(st["face"][0], 0, st["face"][1])
	# on arrive par l'arrière du poste, pour ne pas traverser le meuble
	var back := pos - (face - pos).normalized() * 0.9
	_go(pos, st["room"], "Se rend " + GameData.ROOMS[st["room"]]["at"], back)


func _go(target: Vector3, room_hint: String, label_text: String, approach: Variant = null) -> void:
	var from: String = main.bunker.room_at(global_position)
	var to: String = room_hint if room_hint != "" else main.bunker.room_at(target)
	if from == "":
		from = to
	var pts: Array = main.bunker.route(from, to, target)
	if approach != null:
		pts.insert(pts.size() - 1, approach)
	path = pts
	state = "travel"
	task_label = label_text


func _arrive() -> void:
	visual.walking = false
	if station == "":
		state = "idle"
		if phase == "sleep":
			task_label = "Se prépare à dormir"
		elif phase == "wake":
			task_label = "Fait son lit"
		_final_yaw = PI if main.bunker.room_at(global_position) == "dortoir" else _final_yaw
		if _task_end < Game.abs_time():
			_task_end = Game.abs_time() + Game.rng.randf_range(15.0, 30.0)
		return
	var st: Dictionary = GameData.STATIONS[station]
	var pos := Vector3(st["pos"][0], 0, st["pos"][1])
	var face := Vector3(st["face"][0], 0, st["face"][1])
	global_position = pos
	var d := face - pos
	_final_yaw = atan2(d.x, d.z)
	visual.set_yaw(_final_yaw)
	state = "task"
	task_label = st["label"]
	visual.task_anim = st["anim"]
	visual.sitting = st.get("sit", false)
	visual.set_prop(st["prop"])
	_task_end = Game.abs_time() + Game.rng.randf_range(35.0, 70.0)
	if st["sound"] != "":
		_snd.stream = Sfx.stream(st["sound"])
		if _snd.stream:
			_snd.play()
	if st["fx"] != "":
		_fx = make_fx(st["fx"])
		main.add_child(_fx)
		var y: float = {"steam": 1.4, "water": 1.0, "sparks": 1.05, "bubbles": 1.15, "dust": 0.08}.get(st["fx"], 1.0)
		_fx.global_position = pos + d.normalized() * 0.75 + Vector3(0, y, 0)


func _leave_station() -> void:
	if station != "":
		main.release_station(station, self)
	station = ""
	if visual:
		visual.task_anim = ""
		visual.sitting = false
		visual.set_prop("")
	if _snd:
		_snd.stop()
	if _fx and is_instance_valid(_fx):
		_fx.queue_free()
	_fx = null


func remove_from_play() -> void:
	_leave_station()
	visible = false
	collision_layer = 0
	label.visible = false


func _on_step() -> void:
	if not visible or main.player == null:
		return
	if Input.is_action_pressed("fast_time"):
		return
	if global_position.distance_to(main.player.global_position) > 12.0:
		return
	var g: String = main.bunker.ground_at(global_position)
	var bulk: float = data["look"].get("bulk", 1.0)
	Sfx.at("step_%s_%d" % [g, Game.rng.randi_range(1, 4)], global_position, -12.0, clampf(1.2 - bulk * 0.2, 0.8, 1.2), 12.0)


# ---------------------------------------------------------------- petits effets de tâche

static func _fx_mat(kind: String) -> Material:
	if _fx_mats.has(kind):
		return _fx_mats[kind]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	match kind:
		"sparks", "bubbles":
			m.emission_enabled = true
			m.emission = Color(1.0, 0.6, 0.2) if kind == "sparks" else Color(0.4, 1.0, 0.55)
			m.emission_energy_multiplier = 3.0
	_fx_mats[kind] = m
	return m


static func make_fx(kind: String) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var mesh := QuadMesh.new()
	p.mesh = mesh
	p.local_coords = false
	var ramp := Gradient.new()
	match kind:
		"steam":
			mesh.size = Vector2(0.22, 0.22)
			p.amount = 14
			p.lifetime = 2.2
			p.direction = Vector3.UP
			p.spread = 12.0
			p.initial_velocity_min = 0.25
			p.initial_velocity_max = 0.5
			p.gravity = Vector3(0, 0.15, 0)
			p.scale_amount_min = 0.6
			p.scale_amount_max = 1.6
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			p.emission_sphere_radius = 0.12
			ramp.set_color(0, Color(0.95, 0.95, 0.95, 0.45))
			ramp.set_color(1, Color(0.9, 0.92, 0.95, 0.0))
		"water":
			mesh.size = Vector2(0.03, 0.06)
			p.amount = 24
			p.lifetime = 0.45
			p.direction = Vector3.DOWN
			p.spread = 8.0
			p.initial_velocity_min = 0.3
			p.initial_velocity_max = 0.6
			p.gravity = Vector3(0, -7.0, 0)
			ramp.set_color(0, Color(0.6, 0.85, 1.0, 0.9))
			ramp.set_color(1, Color(0.6, 0.85, 1.0, 0.3))
		"sparks":
			mesh.size = Vector2(0.025, 0.025)
			p.amount = 28
			p.lifetime = 0.55
			p.direction = Vector3.UP
			p.spread = 75.0
			p.initial_velocity_min = 1.2
			p.initial_velocity_max = 2.6
			p.gravity = Vector3(0, -7.0, 0)
			ramp.set_color(0, Color(1.0, 0.95, 0.6, 1.0))
			ramp.set_color(1, Color(1.0, 0.35, 0.1, 0.0))
		"bubbles":
			mesh.size = Vector2(0.05, 0.05)
			p.amount = 10
			p.lifetime = 1.3
			p.direction = Vector3.UP
			p.spread = 20.0
			p.initial_velocity_min = 0.1
			p.initial_velocity_max = 0.25
			p.gravity = Vector3(0, 0.3, 0)
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			p.emission_sphere_radius = 0.08
			ramp.set_color(0, Color(0.5, 1.0, 0.6, 0.9))
			ramp.set_color(1, Color(0.5, 1.0, 0.6, 0.0))
		_:
			mesh.size = Vector2(0.16, 0.16)
			p.amount = 10
			p.lifetime = 1.6
			p.direction = Vector3.UP
			p.spread = 70.0
			p.initial_velocity_min = 0.15
			p.initial_velocity_max = 0.35
			p.gravity = Vector3(0, 0.05, 0)
			p.scale_amount_min = 0.5
			p.scale_amount_max = 1.4
			ramp.set_color(0, Color(0.7, 0.6, 0.45, 0.45))
			ramp.set_color(1, Color(0.7, 0.6, 0.45, 0.0))
	p.color_ramp = ramp
	p.material_override = _fx_mat(kind)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p
