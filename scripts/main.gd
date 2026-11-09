extends Node3D
## Chef d'orchestre : construit le monde, fait tourner les journées et les nuits,
## gère les capacités, les indices et la fin de partie.

const Bunker := preload("res://scripts/bunker.gd")
const FriendScript := preload("res://scripts/friend.gd")
const NpcScript := preload("res://scripts/npc.gd")
const HudScript := preload("res://scripts/hud.gd")
const RigScript := preload("res://scripts/camera_rig.gd")
const Mats := preload("res://scripts/materials.gd")

var bunker
var rig
var hud
var friends: Array = []
var npcs: Array = []
var npc_by_id := {}
var killer
var active := 0
var trail: Array = []
var crimes: Array = []
var cameras: Array = []      # {"pos", "room", "node"}
var prints: Array = []       # {"pos", "shoe", "ang", "night", "day", "crime", "owner"}
var timers := {"ecoute": 0.0, "traces": 0.0, "souvenir": 0.0, "pister": 0.0, "sprint": 0.0, "mark": 0.0}
var marked_id := ""
var crochet_left := 3
var acc_arm := ""

var _print_pool: Array = []
var _fx := {}
var _body: Node3D
var _sleep_arm := -10.0
var _mat_print_day: StandardMaterial3D
var _mat_print_night: StandardMaterial3D

const SHOE_W := {"S": 0.11, "L": 0.16}


# ================================================================ mise en place

func _ready() -> void:
	_setup_environment()
	bunker = Bunker.new()
	add_child(bunker)
	bunker.build()

	var order := range(GameData.NPCS.size())
	order.shuffle()
	for i in GameData.NPCS.size():
		var n = NpcScript.new()
		add_child(n)
		n.setup(GameData.NPCS[i], self)
		n.bed_index = order[i]
		npcs.append(n)
		npc_by_id[n.id] = n
	killer = npcs[Game.rng.randi() % npcs.size()]

	for i in GameData.FRIENDS.size():
		var f = FriendScript.new()
		add_child(f)
		f.setup(GameData.FRIENDS[i], self, i)
		friends.append(f)
	friends[0].is_active = true

	rig = RigScript.new()
	add_child(rig)

	_mat_print_day = Mats.flat(Color(0.95, 0.85, 0.62, 0.85), true)
	_mat_print_night = Mats.glow(Color(1.0, 0.22, 0.15), 2.5)
	var pm := PlaneMesh.new()
	pm.size = Vector2(1, 1)
	for i in 220:
		var mi := MeshInstance3D.new()
		mi.mesh = pm
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_print_pool.append(mi)

	hud = HudScript.new()
	add_child(hud)
	hud.build(self)
	Game.toast.connect(hud.toast)

	# la première nuit a déjà eu lieu quand la partie commence
	Game.day = 0
	_resolve_night()
	Game.day = 1
	for p in prints:
		p["day"] = 1
	crimes[0]["day"] = 1
	_reset_morning()
	rig.snap_to(friends[0])
	hud.refresh_party()
	hud.refresh_abilities()
	hud.show_title(func(): _morning_screen(true))


func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.03, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.22, 0.28, 0.42)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.15
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 0.95
	# brouillard classique : léger pour la carte graphique, sans grain
	env.fog_enabled = true
	env.fog_light_color = Color(0.16, 0.2, 0.28)
	env.fog_density = 0.025
	env.fog_aerial_perspective = 0.2
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.1
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func active_friend():
	return friends[active]


func bed_spot(n) -> Vector3:
	return bunker.beds[n.bed_index]


func partner(n):
	var want: int = n.bed_index ^ 1
	for m in npcs:
		if m.bed_index == want:
			return m
	return null


func crime() -> Dictionary:
	return crimes[-1]


func set_capture(on: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE


# ================================================================ boucle

func _process(delta: float) -> void:
	if not Game.paused and not Game.over:
		var fast := Input.is_action_pressed("fast_time")
		var time_scale := 6.0 if fast else 1.0
		Game.minute += delta * GameData.CONFIG["minutes_per_second"] * time_scale
		for n in npcs:
			if n.is_present():
				n.tick(delta, time_scale)
		for k in timers:
			if timers[k] > 0.0:
				timers[k] = maxf(0.0, timers[k] - delta)
				if timers[k] == 0.0:
					_on_timer_end(k)
		if prints.size() > 3000:
			var now := Game.abs_time()
			prints = prints.filter(func(p): return p["night"] or now - p["t"] < 180.0)
		if Game.minute >= GameData.CONFIG["day_end"]:
			_end_day()
	_update_labels()
	_update_prints()
	_update_prompt()
	hud.update_hud()
	for c in cameras:
		c["node"].get_node("Led").visible = fmod(Time.get_ticks_msec() / 500.0, 2.0) < 1.0


func _on_timer_end(k: String) -> void:
	match k:
		"souvenir":
			_clear_fx("souvenir")
		"pister":
			_clear_fx("pister")
		"mark":
			marked_id = ""


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and not Game.paused and not Game.over:
		set_capture(true)
	if event.is_action_pressed("cancel"):
		if hud.notebook_visible():
			hud.toggle_notebook()
		elif hud.dialog_visible():
			hud.hide_dialog()
		else:
			set_capture(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED)
		return
	if event.is_action_pressed("notebook"):
		if not hud.screen_visible():
			hud.toggle_notebook()
		return
	if Game.paused or Game.over:
		return
	if event.is_action_pressed("switch_friend"):
		_switch_friend()
	elif event.is_action_pressed("interact"):
		_talk()
	elif event.is_action_pressed("end_day"):
		_try_sleep()
	else:
		for i in 4:
			if event.is_action_pressed("ability_%d" % (i + 1)):
				use_ability(i)


func _switch_friend() -> void:
	friends[active].is_active = false
	active = (active + 1) % friends.size()
	friends[active].is_active = true
	trail.clear()
	rig.target = friends[active]
	hud.refresh_party()
	hud.refresh_abilities()


# ================================================================ empreintes et effets

func add_print(pos: Vector3, shoe: String, ang: float, night: bool, crime_of: bool, owner: String) -> void:
	prints.append({"pos": pos, "shoe": shoe, "ang": ang, "night": night, "crime": crime_of,
		"owner": owner, "day": Game.day, "t": Game.abs_time()})


func _update_prints() -> void:
	var used := 0
	if timers["traces"] > 0.0:
		var f = active_friend()
		var near: Array = []
		for p in prints:
			if p["pos"].distance_to(f.global_position) < 8.0:
				near.append(p)
		near.sort_custom(func(a, b): return int(a["night"]) > int(b["night"]))
		for p in near:
			if used >= _print_pool.size():
				break
			var mi: MeshInstance3D = _print_pool[used]
			used += 1
			var w: float = SHOE_W[p["shoe"]]
			mi.visible = true
			mi.material_override = _mat_print_night if (p["night"] and p["day"] == Game.day) else _mat_print_day
			mi.position = p["pos"] + Vector3(0, 0.03, 0)
			mi.rotation = Vector3(0, p["ang"], 0)
			mi.scale = Vector3(w, 1, w * 2.2)
	for i in range(used, _print_pool.size()):
		if not _print_pool[i].visible:
			break
		_print_pool[i].visible = false


func _draw_path(points: Array, color: Color, tag: String) -> void:
	if not _fx.has(tag):
		_fx[tag] = []
	var mat := Mats.glow(color, 3.0)
	for i in range(points.size() - 1):
		var a: Vector3 = points[i] + Vector3(0, 0.12, 0)
		var b: Vector3 = points[i + 1] + Vector3(0, 0.12, 0)
		var seg_len := a.distance_to(b)
		if seg_len < 0.05:
			continue
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.08, 0.04, seg_len)
		mi.mesh = bm
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		mi.global_position = (a + b) * 0.5
		mi.look_at(b, Vector3.UP)
		_fx[tag].append(mi)


func _clear_fx(tag: String) -> void:
	if not _fx.has(tag):
		return
	for n in _fx[tag]:
		n.queue_free()
	_fx[tag] = []


func _place_body(cr: Dictionary) -> void:
	if _body:
		_body.queue_free()
	_body = Node3D.new()
	add_child(_body)
	var v = cr["victim"]
	var stain := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 0.02
	stain.mesh = cm
	stain.material_override = Mats.toon(Color(0.32, 0.05, 0.04), 0.4)
	stain.position = Vector3(0.2, 0.01, 0)
	stain.scale = Vector3(1.2, 1, 0.8)
	_body.add_child(stain)
	var vis = load("res://scripts/character_visual.gd").new()
	_body.add_child(vis)
	vis.build(GameData.TEAMS[v.team]["color"].darkened(0.2), v.data["hair"], v.data["skin"].darkened(0.25))
	vis.rotation = Vector3(0, 0, -PI / 2)
	vis.position = Vector3(-0.9, 0.3, 0)
	var sheet := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.7, 0.05, 1.0)
	sheet.mesh = bm
	sheet.material_override = Mats.toon(Color(0.82, 0.78, 0.7), 0.3)
	sheet.position = Vector3(0.1, 0.62, 0)
	sheet.rotation = Vector3(0, 0, 0.05)
	_body.add_child(sheet)
	_body.global_position = cr["pos"]
	_body.rotation.y = Game.rng.randf() * TAU


func _place_camera_node(pos: Vector3) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.global_position = pos
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.03
	pm.bottom_radius = 0.05
	pm.height = 1.9
	pole.mesh = pm
	pole.material_override = Mats.toon(Color(0.35, 0.38, 0.42), 0.1)
	pole.position = Vector3(0, 0.95, 0)
	root.add_child(pole)
	var head := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.3, 0.25, 0.45)
	head.mesh = hm
	head.material_override = Mats.toon(Color(0.2, 0.22, 0.26), 0.1, 0.015)
	head.position = Vector3(0, 1.95, 0)
	root.add_child(head)
	var led := MeshInstance3D.new()
	led.name = "Led"
	var lm := SphereMesh.new()
	lm.radius = 0.05
	lm.height = 0.1
	led.mesh = lm
	led.material_override = Mats.glow(Color(1.0, 0.1, 0.08), 6.0)
	led.position = Vector3(0, 2.02, 0.23)
	root.add_child(led)
	return root


# ================================================================ la nuit

func _walk_samples(pts: Array, t0: float) -> Array:
	var out: Array = []
	var t := t0
	for i in range(pts.size() - 1):
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var seg_len := a.distance_to(b)
		var steps := maxi(1, int(seg_len / 0.85))
		var dir := (b - a).normalized() if seg_len > 0.001 else Vector3.FORWARD
		var side := Vector3(dir.z, 0, -dir.x)
		for k in steps:
			var f := float(k) / float(steps)
			var off := 0.12 if k % 2 == 0 else -0.12
			out.append({"pos": a.lerp(b, f) + side * off, "t": t, "ang": atan2(dir.x, dir.z)})
			t += 0.3
	return out


func _resolve_night() -> void:
	var living: Array = npcs.filter(func(n): return n.is_present())
	var candidates: Array = living.filter(func(n): return n != killer)
	if candidates.is_empty():
		return
	var victim = candidates[Game.rng.randi() % candidates.size()]
	var rooms := ["atelier", "infirmerie", "refectoire"]
	var room_id: String = rooms[Game.rng.randi() % rooms.size()]
	var pos: Vector3 = bunker.room_spot(room_id, Game.rng)
	var team: Dictionary = GameData.TEAMS[killer.team]
	var cache_room: String = team["room"]
	var cache_stand: Vector3 = bunker.crate_stand(killer.team)
	var t0 := Game.rng.randf_range(80.0, 110.0)

	var v_path: Array = [bed_spot(victim)] + bunker.route("dortoir", room_id, pos)
	var to_cache: Array = [pos] + bunker.route(room_id, cache_room, cache_stand)
	var k_path: Array = [bed_spot(killer)] + bunker.route("dortoir", room_id, pos) + bunker.route(room_id, cache_room, cache_stand) + bunker.route(cache_room, "dortoir", bed_spot(killer))
	var others: Array = living.filter(func(n): return n != killer and n != victim)
	var herring = others[Game.rng.randi() % others.size()] if others.size() > 0 else null

	var walkers: Array = [
		{"n": killer, "s": _walk_samples(k_path, t0 + 4.0)},
		{"n": victim, "s": _walk_samples(v_path, t0 - 6.0)},
	]
	if herring:
		var h_path: Array = [bed_spot(herring)] + bunker.route("dortoir", "infirmerie", Vector3(-13, 0, 2)) + bunker.route("infirmerie", "dortoir", bed_spot(herring))
		walkers.append({"n": herring, "s": _walk_samples(h_path, Game.rng.randf_range(110.0, 124.0))})
	for w in walkers:
		for s in w["s"]:
			prints.append({"pos": s["pos"], "shoe": w["n"].shoe, "ang": s["ang"], "night": true,
				"crime": w["n"] == killer, "owner": w["n"].id, "day": Game.day + 1, "t": Game.abs_time()})

	# caméras posées par Sacha
	var cam_log: Array = []
	for ci in cameras.size():
		var c: Dictionary = cameras[ci]
		for w in walkers:
			for s in w["s"]:
				if s["pos"].distance_to(c["pos"]) < 3.6:
					var who: String
					if w["n"] == victim:
						who = "%s, seul·e, qui marche vite" % victim.display_name
					else:
						who = "une silhouette en tunique %s, capuche baissée" % GameData.TEAMS[w["n"].team]["name"].to_lower()
					cam_log.append({"cam": ci + 1, "room": GameData.ROOMS[c["room"]]["name"], "t": s["t"],
						"text": "%s : %s" % [Game.hhmm(s["t"]), who]})
					break
	cam_log.sort_custom(func(a, b): return a["t"] < b["t"])

	# témoignages du lendemain
	var testi := {}
	for n in living:
		if n == victim:
			continue
		if n == killer:
			var pool: Array = living.filter(func(m): return m != killer and m != victim)
			var y = pool[Game.rng.randi() % pool.size()] if pool.size() > 0 else null
			testi[n.id] = "J'ai dormi d'une traite. Par contre, hier soir, j'ai vu %s traîner %s." % [y.display_name if y else "quelqu'un", GameData.ROOMS[room_id]["at"]]
			continue
		if n == herring:
			testi[n.id] = "J'avais une fièvre terrible. Je suis allé·e à l'infirmerie vers 2 h, puis je suis revenu·e me coucher. Je n'ai croisé personne."
			continue
		var p = partner(n)
		var obs: String
		if p == killer and Game.rng.randf() < 0.8:
			obs = "Le lit %s, à côté du mien, était vide quand je me suis réveillé·e vers 2 h." % Game.de(killer.display_name)
		elif p == victim:
			obs = "%s s'est levé·e en pleine nuit, sans un mot. J'ai cru que c'était pour boire." % victim.display_name
		elif p == herring and herring != null:
			obs = "%s toussait. Je l'ai entendu·e se lever vers 2 h." % herring.display_name
		else:
			obs = GameData.RUMORS[Game.rng.randi() % GameData.RUMORS.size()]
		testi[n.id] = "J'ai dormi au dortoir. " + obs

	victim.alive = false
	victim.visible = false
	victim.collision_layer = 0
	var radio_names: Array = []
	for n in [killer, victim, herring]:
		if n != null:
			radio_names.append(n.display_name)
	radio_names.shuffle()
	crimes.append({"day": Game.day + 1, "victim": victim, "room": room_id, "pos": pos, "cache_room": cache_room,
		"to_cache": to_cache, "fiber": Game.rng.randf() < 0.7, "cam_log": cam_log, "radio": radio_names,
		"testi": testi})


func _reset_morning() -> void:
	for n in npcs:
		if not n.is_present():
			n.visible = false
			continue
		n.visible = true
		n.place_at(bed_spot(n))
		n.visual.set_yaw(PI)
	for i in friends.size():
		friends[i].global_position = Vector3(-1.4 + i * 1.4, 0, -8.6)
		friends[i].visual.set_yaw(0.0)
	trail.clear()
	crochet_left = 3
	marked_id = ""
	for k in timers:
		timers[k] = 0.0
	for tag in _fx.keys():
		_clear_fx(tag)
	prints = prints.filter(func(p): return p["night"] and p["day"] == Game.day)
	_place_body(crime())


func _morning_screen(first: bool) -> void:
	var cr := crime()
	var v = cr["victim"]
	var room: Dictionary = GameData.ROOMS[cr["room"]]
	var body := "%s\n\n" % v.data["bond"]
	if cr["cam_log"].size() > 0:
		body += "[b]Vos caméras ont filmé[/b]\n"
		for c in cr["cam_log"]:
			body += "Caméra %d (%s) · %s\n" % [c["cam"], c["room"], c["text"]]
			Game.add_clue("Caméra %d (%s), nuit %d : %s" % [c["cam"], c["room"], Game.day - 1, c["text"]], "cam%d_%d_%s" % [Game.day, c["cam"], c["t"]])
		body += "\n"
	elif cameras.size() > 0:
		body += "Rien n'est passé devant vos caméras cette nuit.\n\n"
	var left: int = GameData.CONFIG["days"] - Game.day + 1
	body += "Il vous reste [b]%d jour%s[/b] avant que le conseil scelle le secteur." % [left, "s" if left > 1 else ""]
	Game.add_clue("%s (équipe %s) retrouvé·e sans vie %s." % [v.display_name, GameData.TEAMS[v.team]["name"], room["at"]], "v%d" % Game.day)
	hud.show_screen("Secteur C · Sirène de 6 h" if first else "La sirène de 6 h",
		"Jour %d. %s a été retrouvé·e %s." % [Game.day, v.display_name, room["at"]], body, "Commencer la journée",
		func(): set_capture(true))


func _try_sleep() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _sleep_arm < 3.0:
		_sleep_arm = -10.0
		_end_day()
	else:
		_sleep_arm = now
		Game.say("Appuie encore sur N pour passer directement à la nuit.")


func _end_day() -> void:
	if Game.over or Game.paused:
		return
	hud.hide_dialog()
	if Game.day >= GameData.CONFIG["days"]:
		_end_game(false, "week", null)
		return
	set_capture(false)
	hud.show_screen("22 h · Extinction des feux", "Nuit %d" % Game.day,
		"Le Secteur C s'endort. Quelque part, quelqu'un fait semblant.", "", Callable())
	await get_tree().create_timer(2.4).timeout
	_resolve_night()
	Game.day += 1
	Game.minute = GameData.CONFIG["day_start"]
	_reset_morning()
	_morning_screen(false)


# ================================================================ accusation et fin

func accuse(n) -> void:
	acc_arm = ""
	if hud.notebook_visible():
		hud.toggle_notebook()
	if n == killer:
		_end_game(true, "", null)
		return
	n.confined = true
	n.visible = false
	n.collision_layer = 0
	Game.wrong += 1
	if Game.wrong >= GameData.CONFIG["max_wrong"]:
		_end_game(false, "wrong", n)
		return
	set_capture(false)
	hud.show_screen("Accusation", "%s est enfermé·e" % n.display_name,
		"Les gardes l'emmènent pendant qu'%s répète qu'il ou elle n'a rien fait. Les regards se détournent de vous trois.\n\nSi c'était un innocent, le meurtrier frappera encore cette nuit. Il vous reste [b]%d accusation[/b]." % [n.display_name, GameData.CONFIG["max_wrong"] - Game.wrong],
		"Continuer", func(): set_capture(true))


func _end_game(win: bool, why: String, wrong_n) -> void:
	Game.over = true
	set_capture(false)
	var victims: Array = npcs.filter(func(n): return not n.alive)
	var keeps: Array = victims.map(func(n): return n.data["keepsake"])
	var team: Dictionary = GameData.TEAMS[killer.team]
	if win:
		hud.show_screen("Victoire", "C'était %s" % killer.display_name,
			"Dans le casier %s : %s.\n\n%s\n\nLe Secteur C respire à nouveau. Mais %d lit%s, et personne ne dort tout à fait tranquille." % [
				Game.de(killer.display_name), ", ".join(PackedStringArray(keeps)), killer.data["motive"], victims.size(), "s restent vides" if victims.size() > 1 else " reste vide"],
			"Rejouer avec un autre meurtrier", func(): _restart())
	else:
		var head := "Le bunker ne vous croit plus" if why == "wrong" else "Le temps est écoulé"
		var start := ("Après l'arrestation %s, le conseil vous retire l'enquête." % Game.de(wrong_n.display_name)) if why == "wrong" else "Le conseil scelle le Secteur C."
		hud.show_screen("Défaite", head,
			"%s Le meurtrier était [b]%s[/b], de l'équipe %s, pointure %s.\n\n%s" % [start, killer.display_name, team["name"], killer.shoe, killer.data["motive"]],
			"Rejouer avec un autre meurtrier", func(): _restart())


func _restart() -> void:
	Game.reset()
	get_tree().reload_current_scene()


# ================================================================ capacités

func nearest_npc(r: float):
	var f = active_friend()
	var fwd: Vector3 = rig.forward()
	var best = null
	var bd := r
	for n in npcs:
		if not n.is_present():
			continue
		var to: Vector3 = n.global_position - f.global_position
		to.y = 0.0
		var d := to.length()
		if d < bd and (d < 1.6 or to.normalized().dot(fwd) > 0.2):
			bd = d
			best = n
	return best


func _near_body(r: float) -> bool:
	return crime()["pos"].distance_to(active_friend().global_position) < r


func _near_locker():
	var f = active_friend()
	var best = null
	var bd := 1.8
	for n in npcs:
		var d: float = bunker.lockers[n.bed_index].distance_to(f.global_position)
		if d < bd:
			bd = d
			best = n
	return best


func _near_crate() -> String:
	var f = active_friend()
	for t in bunker.crates:
		if bunker.crates[t].distance_to(f.global_position) < 2.4:
			return t
	return ""


func use_ability(i: int) -> void:
	var f = active_friend()
	if f.cd[i] > 0.0:
		return
	var a: Dictionary = f.data["abilities"][i]
	if call("_ab_" + a["id"]):
		f.cd[i] = a["cd"]
		hud.flash_ability(i)


func _talk() -> void:
	var n = nearest_npc(2.8)
	if n:
		hud.show_dialog(n.display_name, GameData.TEAMS[n.team]["color"], n.data["chat"])


func _ab_interroger() -> bool:
	var n = nearest_npc(2.8)
	if n == null:
		Game.say("Approche-toi de quelqu'un pour l'interroger.")
		return false
	var t: String = crime()["testi"].get(n.id, "Je ne sais rien. Laissez-moi tranquille.")
	hud.show_dialog(n.display_name, GameData.TEAMS[n.team]["color"], t)
	Game.add_clue("%s : « %s »" % [n.display_name, t], "t%d%s" % [Game.day, n.id])
	return true


func _ab_ecoute() -> bool:
	timers["ecoute"] = 8.0
	Game.say("Lina tend l'oreille : tout le secteur apparaît à travers les murs pendant 8 s.")
	return true


func _ab_reconfort() -> bool:
	var n = nearest_npc(2.8)
	if n == null:
		Game.say("Approche-toi de quelqu'un.")
		return false
	var shoe: String = n.shoe
	if n == killer:
		shoe = "S" if n.shoe == "L" else "L"   # le meurtrier ment
	hud.show_dialog(n.display_name, GameData.TEAMS[n.team]["color"], "%s … Et oui, je chausse du %s." % [n.data["secret"], shoe])
	Game.know_of(n.id)["claim"] = shoe
	Game.add_clue("%s dit chausser du %s." % [n.display_name, shoe], "cl" + n.id)
	return true


func _ab_souvenir() -> bool:
	_clear_fx("souvenir")
	var now := Game.abs_time()
	for n in npcs:
		if not n.is_present():
			continue
		var pts: Array = []
		for h in n.hist:
			if now - h["t"] <= 60.0:
				pts.append(h["p"])
		pts.append(n.global_position)
		_draw_path(pts, GameData.TEAMS[n.team]["color"].lightened(0.2), "souvenir")
	timers["souvenir"] = 8.0
	Game.say("Souvenir : les trajets de la dernière heure apparaissent.")
	return true


func _ab_traces() -> bool:
	timers["traces"] = 10.0
	var f = active_friend()
	if _near_body(5.0):
		var cr := crime()
		var found := false
		for p in prints:
			if p["night"] and p["crime"] and p["day"] == Game.day and p["pos"].distance_to(cr["pos"]) < 3.0:
				found = true
				break
		if found:
			Game.add_clue("Près du corps %s, deux séries d'empreintes de la nuit : celles de la victime (pointure %s) et d'autres en pointure %s." % [
				Game.de(cr["victim"].display_name), cr["victim"].shoe, killer.shoe], "pr%d" % Game.day)
		return true
	var c := {"S": 0, "L": 0}
	var night := 0
	for p in prints:
		if p["pos"].distance_to(f.global_position) < 8.0:
			c[p["shoe"]] += 1
			if p["night"]:
				night += 1
	Game.say("Traces : %d empreintes ici (S %d, L %d)%s." % [c["S"] + c["L"], c["S"], c["L"], (", dont %d de la nuit, en rouge" % night) if night > 0 else ""])
	return true


func _ab_sprint() -> bool:
	timers["sprint"] = 3.0
	return true


func _ab_marquer() -> bool:
	var n = nearest_npc(3.5)
	if n == null:
		Game.say("Approche-toi de quelqu'un pour le marquer.")
		return false
	marked_id = n.id
	timers["mark"] = 60.0
	Game.know_of(n.id)["seen"] = n.shoe
	Game.add_clue("Maël a observé les chaussures %s : pointure %s." % [Game.de(n.display_name), n.shoe], "sh" + n.id)
	Game.say("%s est marqué·e pendant une minute." % n.display_name)
	return true


func _ab_pister() -> bool:
	if not _near_body(5.0):
		Game.say("Pister ne marche que près du corps.")
		return false
	var cr := crime()
	_clear_fx("pister")
	_draw_path(cr["to_cache"], Color(1.0, 0.7, 0.25), "pister")
	timers["pister"] = 20.0
	Game.add_clue("La piste du tueur part du corps et mène %s." % GameData.ROOMS[cr["cache_room"]]["at"], "pi%d" % Game.day)
	return true


func _ab_fouiller() -> bool:
	var cr := crime()
	if _near_body(3.0):
		if cr["fiber"]:
			Game.add_clue("Sous les ongles %s : une fibre de tunique %s." % [Game.de(cr["victim"].display_name), GameData.TEAMS[killer.team]["name"].to_lower()], "fi%d" % Game.day)
		else:
			Game.say("Rien de plus que du sang séché. Le tueur a été prudent.")
		return true
	var t := _near_crate()
	if t != "":
		var team: Dictionary = GameData.TEAMS[t]
		if t == killer.team:
			Game.add_clue("Dans la caisse %s : %s, avec des traces de sang." % [GameData.ROOMS[team["room"]]["at"], team["weapon"]], "w" + t)
		else:
			Game.say("Des outils, de la poussière. Rien d'anormal.")
		return true
	Game.say("Rien d'intéressant ici. Fouille près du corps ou des caisses.")
	return false


func _ab_camera() -> bool:
	var f = active_friend()
	var room: String = bunker.room_at(f.global_position)
	if room == "":
		Game.say("Pose la caméra dans une salle.")
		return false
	if cameras.size() >= 2:
		var old: Dictionary = cameras.pop_front()
		old["node"].queue_free()
	var pos: Vector3 = f.global_position
	cameras.append({"pos": pos, "room": room, "node": _place_camera_node(pos)})
	Game.say("Caméra posée %s. Elle filmera la nuit prochaine." % GameData.ROOMS[room]["at"])
	return true


func _ab_crocheter() -> bool:
	if crochet_left <= 0:
		Game.say("Plus de crochetage aujourd'hui, les gardes se méfient.")
		return false
	var n = _near_locker()
	if n == null:
		Game.say("Approche-toi d'un casier, au dortoir.")
		return false
	crochet_left -= 1
	if n == killer:
		var keeps: Array = npcs.filter(func(m): return not m.alive).map(func(m): return m.data["keepsake"])
		Game.add_clue("Casier %s : %s, et cachés au fond, %s." % [Game.de(n.display_name), n.data["locker"], ", ".join(PackedStringArray(keeps))], "lk%s%d" % [n.id, Game.day])
	else:
		Game.add_clue("Casier %s : %s. Rien qui le relie aux meurtres." % [Game.de(n.display_name), n.data["locker"]], "lk" + n.id)
	return true


func _ab_radio() -> bool:
	Game.add_clue("Radio, ronde de 2 h : lits vides cette nuit : %s." % ", ".join(PackedStringArray(crime()["radio"])), "ra%d" % Game.day)
	return true


# ================================================================ étiquettes et invites

func _update_labels() -> void:
	var f = active_friend()
	var xray: bool = timers["ecoute"] > 0.0
	for n in npcs:
		if not n.is_present():
			n.label.visible = false
			continue
		var d: float = n.global_position.distance_to(f.global_position)
		var marked: bool = marked_id == n.id
		n.label.visible = xray or marked or d < 8.0
		n.label.no_depth_test = xray or marked
		var txt: String = n.display_name
		if marked:
			txt += " · pointure " + n.shoe
		if xray:
			var r: String = bunker.room_at(n.global_position)
			txt += "\n" + (GameData.ROOMS[r]["at"] if r != "" else "en chemin")
		n.label.text = txt
		n.label.modulate = Color(1.0, 0.75, 0.35) if marked else Color(0.95, 0.9, 0.82)


func _update_prompt() -> void:
	if Game.paused or Game.over:
		hud.set_prompt("")
		return
	var f = active_friend()
	var id: String = f.data["id"]
	var txt := ""
	var n = nearest_npc(2.8)
	if n and not hud.dialog_visible():
		match id:
			"lina":
				txt = "%s   [E] Parler   [1] Interroger   [3] Réconfort" % n.display_name
			"mael":
				txt = "%s   [E] Parler   [3] Marquer" % n.display_name
			_:
				txt = "%s   [E] Parler   (Tab : Lina pour interroger)" % n.display_name
	elif _near_body(3.0):
		var v = crime()["victim"]
		match id:
			"mael":
				txt = "Corps %s   [1] Traces   [4] Pister" % Game.de(v.display_name)
			"sacha":
				txt = "Corps %s   [1] Fouiller" % Game.de(v.display_name)
			_:
				txt = "Corps %s   Maël et Sacha peuvent examiner la scène" % Game.de(v.display_name)
	elif id == "sacha" and _near_locker() != null:
		txt = "Casier %s   [3] Crocheter (%d restant%s)" % [Game.de(_near_locker().display_name), crochet_left, "s" if crochet_left > 1 else ""]
	elif id == "sacha" and _near_crate() != "":
		txt = "Caisse   [1] Fouiller"
	hud.set_prompt(txt)
