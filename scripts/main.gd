extends Node3D
## Chef d'orchestre : construit le monde, fait tourner les journées et les nuits,
## gère les capacités de Lina, les indices, la fin de partie et le test automatique.

const Bunker := preload("res://scripts/bunker.gd")
const PlayerScript := preload("res://scripts/player.gd")
const NpcScript := preload("res://scripts/npc.gd")
const HudScript := preload("res://scripts/hud.gd")
const RigScript := preload("res://scripts/camera_rig.gd")
const Mats := preload("res://scripts/materials.gd")
const Visual := preload("res://scripts/character_visual.gd")

const SHOE_W := {"S": 0.11, "L": 0.16}
const START := Vector3(0, 0, -9.0)

var bunker
var rig
var hud
var player
var npcs: Array = []
var npc_by_id := {}
var killer
var crimes: Array = []
var prints: Array = []       # {"pos", "shoe", "ang", "night", "day", "crime", "owner", "t"}
var timers := {"echo": 0.0, "thread": 0.0, "mark": 0.0}
var marked_id := ""
var crochet_left := 3
var acc_arm := ""
var target = null            # habitant que Lina regarde
var autotest := false
var time_boost := 1.0

var _taken := {}             # position de poste -> habitant
var _print_pool: Array = []
var _fx := {}
var _body: Node3D
var _mark_icon: Node3D
var _sleep_arm := -10.0
var _mat_print_day: StandardMaterial3D
var _mat_print_night: StandardMaterial3D
var _music: AudioStreamPlayer
var _searched := {}


# ================================================================ mise en place

func _ready() -> void:
	autotest = "--autotest" in OS.get_cmdline_user_args()
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

	player = PlayerScript.new()
	add_child(player)
	player.setup(self)
	rig = RigScript.new()
	add_child(rig)
	rig.set_paint(Game.paint_filter)

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

	_music = AudioStreamPlayer.new()
	_music.stream = Sfx.stream("music_bunker")
	_music.bus = "Music"
	_music.volume_db = -4.0
	add_child(_music)
	if _music.stream:
		_music.play()

	# la première nuit a déjà eu lieu quand la partie commence
	Game.day = 0
	_resolve_night()
	Game.day = 1
	for p in prints:
		p["day"] = 1
	crimes[0]["day"] = 1
	_reset_morning()
	rig.snap_to(player)
	hud.refresh_abilities()
	if autotest:
		_autotest.call_deferred()
	else:
		hud.show_title(func(): _morning_screen(true))


func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.03, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.22, 0.28, 0.42)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.15
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 0.95
	env.fog_enabled = true
	env.fog_light_color = Color(0.16, 0.2, 0.28)
	env.fog_density = 0.022
	env.fog_aerial_perspective = 0.2
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.1
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


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
	if autotest:
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE


## Postes de travail : deux postes au même endroit (une chaise, un tabouret) comptent pour un.
func _skey(k: String) -> String:
	var p: Array = GameData.STATIONS[k]["pos"]
	return "%.1f,%.1f" % [p[0], p[1]]


func claim_station(k: String, n) -> bool:
	var key := _skey(k)
	var cur = _taken.get(key)
	if cur != null and cur != n and is_instance_valid(cur) and cur.is_present() and cur.station != "" and _skey(cur.station) == key:
		return false
	_taken[key] = n
	return true


func release_station(k: String, n) -> void:
	var key := _skey(k)
	if _taken.get(key) == n:
		_taken.erase(key)


# ================================================================ boucle

func _process(delta: float) -> void:
	if not Game.paused and not Game.over:
		var fast := Input.is_action_pressed("fast_time")
		var time_scale := (6.0 if fast else 1.0) * time_boost
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
		if Game.minute >= GameData.CONFIG["day_end"] and not autotest:
			_end_day()
	_update_target()
	_update_labels()
	_update_prints()
	_update_prompt()
	bunker.update_ambience(player.global_position, delta)
	hud.update_hud()
	if _mark_icon and is_instance_valid(_mark_icon):
		_mark_icon.rotation.y += delta * 2.0


func _on_timer_end(k: String) -> void:
	match k:
		"thread":
			_clear_fx("thread")
		"mark":
			marked_id = ""
			if _mark_icon and is_instance_valid(_mark_icon):
				_mark_icon.queue_free()
			_mark_icon = null


func menus_open() -> bool:
	return hud.notebook_visible() or hud.screen_visible() or hud.pause_visible()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and not Game.paused and not Game.over and not menus_open():
		set_capture(true)
	if event.is_action_pressed("cancel"):
		if hud.notebook_visible():
			hud.toggle_notebook()
		elif hud.pause_visible():
			hud.hide_pause()
		elif hud.dialog_visible():
			hud.hide_dialog()
		elif not hud.screen_visible() and not Game.over:
			hud.show_pause()
		return
	if event.is_action_pressed("toggle_paint"):
		set_paint(not Game.paint_filter)
		return
	if event.is_action_pressed("notebook"):
		if not hud.screen_visible() and not hud.pause_visible():
			hud.toggle_notebook()
		return
	if Game.paused or Game.over:
		return
	if event.is_action_pressed("interact"):
		_interact()
	elif event.is_action_pressed("end_day"):
		_try_sleep()
	else:
		for i in 4:
			if event.is_action_pressed("ability_%d" % (i + 1)):
				use_ability(i)


func set_paint(on: bool) -> void:
	Game.paint_filter = on
	rig.set_paint(on)


func unstuck() -> void:
	player.unstuck(true)
	rig.snap_to(player)


# ================================================================ regard de Lina

func _update_target() -> void:
	var best = null
	if not Game.paused and rig.cam:
		var from: Vector3 = rig.cam.global_position
		var dir: Vector3 = -rig.cam.global_transform.basis.z
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * 16.0, 1 | 4)
		q.exclude = [player.get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if hit and hit["collider"] in npcs and hit["collider"].is_present():
			best = hit["collider"]
		if best == null:
			best = nearest_npc(2.2)
	if best != target:
		target = best
	hud.set_target(target)


func nearest_npc(r: float):
	var fwd: Vector3 = rig.forward()
	var best = null
	var bd := r
	for n in npcs:
		if not n.is_present():
			continue
		var to: Vector3 = n.global_position - player.global_position
		to.y = 0.0
		var d := to.length()
		if d < bd and (d < 1.3 or to.normalized().dot(fwd) > 0.3):
			bd = d
			best = n
	return best


func _dist_to(n) -> float:
	return n.global_position.distance_to(player.global_position)


# ================================================================ empreintes et effets

func add_print(pos: Vector3, shoe: String, ang: float, night: bool, crime_of: bool, owner: String) -> void:
	prints.append({"pos": pos, "shoe": shoe, "ang": ang, "night": night, "crime": crime_of,
		"owner": owner, "day": Game.day, "t": Game.abs_time()})


func _update_prints() -> void:
	var used := 0
	if timers["echo"] > 0.0:
		var near: Array = []
		for p in prints:
			if p["pos"].distance_to(player.global_position) < 9.0:
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
			mi.position = p["pos"] + Vector3(0, 0.035, 0)
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
		if absf((b - a).normalized().y) < 0.99:
			mi.look_at(b, Vector3.UP)
		_fx[tag].append(mi)
		# perles lumineuses qui avancent le long du fil
		var bead := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.07
		sm.height = 0.14
		bead.mesh = sm
		bead.material_override = Mats.glow(color.lightened(0.3), 6.0)
		add_child(bead)
		bead.global_position = a
		var tw := bead.create_tween().set_loops()
		tw.tween_property(bead, "global_position", b, maxf(seg_len / 3.0, 0.2)).from(a)
		_fx[tag].append(bead)


func _clear_fx(tag: String) -> void:
	if not _fx.has(tag):
		return
	for n in _fx[tag]:
		if is_instance_valid(n):
			n.queue_free()
	_fx[tag] = []


## Onde lumineuse qui s'étend depuis un point, puis s'efface.
func _ring(pos: Vector3, color: Color, radius: float, dur: float) -> void:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.92
	tm.outer_radius = 1.0
	tm.rings = 48
	mi.mesh = tm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 4.0
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = pos + Vector3(0, 0.1, 0)
	mi.scale = Vector3(0.2, 1.0, 0.2)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(radius, 1.0, radius), dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(m, "albedo_color:a", 0.0, dur).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(mi.queue_free)


func _burst(pos: Vector3, color: Color) -> void:
	var p := CPUParticles3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.06, 0.06)
	p.mesh = qm
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = 30
	p.lifetime = 1.0
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.4
	p.gravity = Vector3(0, 0.6, 0)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(color, 1.0))
	ramp.set_color(1, Color(color, 0.0))
	p.color_ramp = ramp
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 3.0
	p.material_override = m
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(1.6).timeout.connect(p.queue_free)


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
	var look: Dictionary = v.data["look"].duplicate()
	look["skin"] = (look["skin"] as Color).darkened(0.25)
	var vis = Visual.new()
	_body.add_child(vis)
	vis.build_look(look)
	vis.set_process(false)
	vis.rotation = Vector3(0, 0, -PI / 2)
	vis.position = Vector3(-0.9, 0.3, 0)
	var sheet := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.4, 0.05, 1.0)
	sheet.mesh = bm
	sheet.material_override = Mats.toon(Color(0.82, 0.78, 0.7), 0.3)
	sheet.position = Vector3(-0.3, 0.62, 0)
	sheet.rotation = Vector3(0, 0, 0.05)
	_body.add_child(sheet)
	_body.global_position = cr["pos"]
	_body.rotation.y = Game.rng.randf() * TAU


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
	victim.remove_from_play()
	var radio_names: Array = []
	for n in [killer, victim, herring]:
		if n != null:
			radio_names.append(n.display_name)
	radio_names.shuffle()
	crimes.append({"day": Game.day + 1, "victim": victim, "room": room_id, "pos": pos, "cache_room": cache_room,
		"to_cache": to_cache, "fiber": Game.rng.randf() < 0.7, "radio": radio_names, "testi": testi})


func _reset_morning() -> void:
	for n in npcs:
		if not n.is_present():
			n.remove_from_play()
			continue
		n.visible = true
		n.place_at(bed_spot(n))
		n.visual.set_yaw(PI)
	_taken.clear()
	player.global_position = START
	player.safe_pos = START
	player.visual.set_yaw(0.0)
	rig.yaw = PI
	rig.snap_to(player)
	crochet_left = GameData.CONFIG["lockpicks_per_day"]
	marked_id = ""
	_searched.clear()
	for k in timers:
		timers[k] = 0.0
		_on_timer_end(k)
	for tag in _fx.keys():
		_clear_fx(tag)
	prints = prints.filter(func(p): return p["night"] and p["day"] == Game.day)
	_place_body(crime())


func _morning_screen(first: bool) -> void:
	var cr := crime()
	var v = cr["victim"]
	var room: Dictionary = GameData.ROOMS[cr["room"]]
	var body := "%s\n\n" % v.data["bond"]
	var left: int = GameData.CONFIG["days"] - Game.day + 1
	body += "Il te reste [b]%d jour%s[/b] avant que le conseil scelle le secteur." % [left, "s" if left > 1 else ""]
	Game.add_clue("%s (%s, équipe %s) retrouvé·e sans vie %s." % [v.display_name, v.role.to_lower(), GameData.TEAMS[v.team]["name"], room["at"]], "v%d" % Game.day)
	Sfx.ui("sting_body", -3.0)
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
	Sfx.ui("sting_night", -3.0)
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
	n.remove_from_play()
	Game.wrong += 1
	if Game.wrong >= GameData.CONFIG["max_wrong"]:
		_end_game(false, "wrong", n)
		return
	set_capture(false)
	hud.show_screen("Accusation", "%s est enfermé·e" % n.display_name,
		"Les gardes l'emmènent pendant qu'%s répète n'avoir rien fait. Les regards se détournent de Lina.\n\nSi c'était un innocent, le meurtrier frappera encore cette nuit. Il te reste [b]%d accusation[/b]." % [n.display_name, GameData.CONFIG["max_wrong"] - Game.wrong],
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
		var head := "Le bunker ne te croit plus" if why == "wrong" else "Le temps est écoulé"
		var start := ("Après l'arrestation %s, le conseil retire l'enquête à Lina." % Game.de(wrong_n.display_name)) if why == "wrong" else "Le conseil scelle le Secteur C."
		hud.show_screen("Défaite", head,
			"%s Le meurtrier était [b]%s[/b], %s, équipe %s, pointure %s.\n\n%s" % [start, killer.display_name, killer.role.to_lower(), team["name"], killer.shoe, killer.data["motive"]],
			"Rejouer avec un autre meurtrier", func(): _restart())


func _restart() -> void:
	Game.reset()
	get_tree().reload_current_scene()


# ================================================================ interactions (E)

func _near_body(r: float) -> bool:
	return crime()["pos"].distance_to(player.global_position) < r


func _near_locker():
	var best = null
	var bd := 1.6
	for n in npcs:
		var d: float = bunker.lockers[n.bed_index].distance_to(player.global_position)
		if d < bd:
			bd = d
			best = n
	return best


func _near_crate() -> String:
	for t in bunker.crates:
		if bunker.crates[t].distance_to(player.global_position) < 2.0:
			return t
	return ""


func _near_radio() -> bool:
	return bunker.radio.distance_to(player.global_position) < 2.0


## Ce que Lina ferait avec E ici, par ordre de priorité.
func _interaction() -> String:
	if target and _dist_to(target) < 3.2:
		return "talk"
	if _near_body(2.6):
		return "body"
	if _near_locker() != null:
		return "locker"
	if _near_crate() != "":
		return "crate"
	if _near_radio():
		return "radio"
	return ""


func _interact() -> void:
	match _interaction():
		"talk":
			var n = target
			n.talk_until = Time.get_ticks_msec() / 1000.0 + 6.0
			Sfx.ui("ui_open", -6.0)
			hud.show_dialog(n.display_name, n.color(), n.data["chat"])
		"body":
			var cr := crime()
			Sfx.ui("task_paper", -4.0)
			if cr["fiber"]:
				Game.add_clue("Sous les ongles %s : une fibre de tunique %s." % [Game.de(cr["victim"].display_name), GameData.TEAMS[killer.team]["name"].to_lower()], "fi%d" % Game.day)
			else:
				Game.say("Rien de plus que du sang séché. Le tueur a été prudent.")
		"locker":
			_pick_locker(_near_locker())
		"crate":
			var t := _near_crate()
			var team: Dictionary = GameData.TEAMS[t]
			Sfx.ui("task_glass", -4.0)
			if t == killer.team:
				Game.add_clue("Dans la caisse %s : %s, avec des traces de sang." % [GameData.ROOMS[team["room"]]["at"], team["weapon"]], "w" + t)
			else:
				Game.say("Des outils, de la poussière. Rien d'anormal.")
		"radio":
			Sfx.ui("ui_open", -4.0)
			Game.add_clue("Radio, ronde de 2 h : lits vides cette nuit : %s." % ", ".join(PackedStringArray(crime()["radio"])), "ra%d" % Game.day)


func _pick_locker(n) -> void:
	if crochet_left <= 0:
		Sfx.ui("ui_error")
		Game.say("Plus de crochetage aujourd'hui, les gardes se méfient.")
		return
	crochet_left -= 1
	Sfx.ui("task_hammer", -6.0, 1.6)
	if n == killer:
		var keeps: Array = npcs.filter(func(m): return not m.alive).map(func(m): return m.data["keepsake"])
		Game.add_clue("Casier %s : %s, et cachés au fond, %s." % [Game.de(n.display_name), n.data["locker"], ", ".join(PackedStringArray(keeps))], "lk%s%d" % [n.id, Game.day])
	else:
		Game.add_clue("Casier %s : %s. Rien qui le relie aux meurtres." % [Game.de(n.display_name), n.data["locker"]], "lk" + n.id)


# ================================================================ capacités (1 à 4)

func use_ability(i: int) -> void:
	var a: Dictionary = GameData.PLAYER["abilities"][i]
	if player.cd[i] > 0.0:
		Sfx.ui("ui_error", -8.0)
		return
	if call("_ab_" + a["id"]):
		player.cd[i] = a["cd"]
		hud.flash_ability(i)
		Sfx.ui(a["sound"], -2.0)
	else:
		Sfx.ui("ui_error", -6.0)


## 1. Écho : une onde part de Lina et révèle les empreintes autour d'elle pendant 10 s.
func _ab_echo() -> bool:
	timers["echo"] = 10.0
	_ring(player.global_position, Color(0.35, 0.9, 0.85), 9.0, 0.9)
	var c := {"S": 0, "L": 0}
	var night := 0
	for p in prints:
		if p["pos"].distance_to(player.global_position) < 9.0:
			c[p["shoe"]] += 1
			if p["night"]:
				night += 1
	if _near_body(6.0):
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
	Game.say("Écho : %d empreintes ici (S %d, L %d)%s." % [c["S"] + c["L"], c["S"], c["L"], (", dont %d de la nuit, en rouge" % night) if night > 0 else ""])
	return true


## 2. Fil rouge : près du corps, la piste du tueur. Ailleurs, les trajets récents des habitants.
func _ab_thread() -> bool:
	_clear_fx("thread")
	if _near_body(6.0):
		var cr := crime()
		_draw_path(cr["to_cache"], Color(1.0, 0.3, 0.2), "thread")
		timers["thread"] = 20.0
		Game.add_clue("Le fil rouge part du corps et mène %s." % GameData.ROOMS[cr["cache_room"]]["at"], "pi%d" % Game.day)
		return true
	var now := Game.abs_time()
	for n in npcs:
		if not n.is_present():
			continue
		var pts: Array = []
		for h in n.hist:
			if now - h["t"] <= 60.0:
				pts.append(h["p"])
		pts.append(n.global_position)
		_draw_path(pts, n.color().lightened(0.25), "thread")
	timers["thread"] = 10.0
	Game.say("Fil rouge : les trajets de la dernière heure apparaissent, à la couleur de chaque équipe.")
	return true


## 3. Regard : marque la personne visée. Sa pointure s'affiche et on la voit à travers les murs.
func _ab_mark() -> bool:
	var n = target
	if n == null:
		Game.say("Vise quelqu'un avec le point au centre de l'écran.")
		return false
	marked_id = n.id
	timers["mark"] = 60.0
	Game.know_of(n.id)["seen"] = n.shoe
	Game.add_clue("Lina a observé les chaussures %s : pointure %s." % [Game.de(n.display_name), n.shoe], "sh" + n.id)
	if _mark_icon and is_instance_valid(_mark_icon):
		_mark_icon.queue_free()
	_mark_icon = MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(0.22, 0.3, 0.06)
	_mark_icon.mesh = pm
	var m: StandardMaterial3D = Mats.glow(Color(1.0, 0.7, 0.3), 4.0).duplicate()
	m.no_depth_test = true
	_mark_icon.material_override = m
	_mark_icon.rotation.x = PI
	n.add_child(_mark_icon)
	_mark_icon.position = Vector3(0, n.label.position.y + 0.3, 0)
	_burst(n.global_position + Vector3(0, 1.6, 0), Color(1.0, 0.7, 0.3))
	Game.say("%s est marqué·e pendant une minute." % n.display_name)
	return true


## 4. Confidence : la personne visée, proche, livre son alibi de la nuit et un secret.
func _ab_confide() -> bool:
	var n = target
	if n == null or _dist_to(n) > 3.5:
		Game.say("Approche-toi de quelqu'un et regarde-le pour qu'il se confie.")
		return false
	var shoe: String = n.shoe
	if n == killer:
		shoe = "S" if n.shoe == "L" else "L"   # le meurtrier ment
	var t: String = crime()["testi"].get(n.id, "Je ne sais rien. Laissez-moi tranquille.")
	n.talk_until = Time.get_ticks_msec() / 1000.0 + 8.0
	hud.show_dialog(n.display_name, n.color(), "%s\n%s Et oui, je chausse du %s." % [t, n.data["secret"], shoe])
	Game.know_of(n.id)["claim"] = shoe
	Game.add_clue("%s : « %s »" % [n.display_name, t], "t%d%s" % [Game.day, n.id])
	Game.add_clue("%s dit chausser du %s." % [n.display_name, shoe], "cl" + n.id)
	_ring(n.global_position, Color(0.95, 0.6, 0.8), 1.6, 0.8)
	_burst(n.global_position + Vector3(0, 1.4, 0), Color(0.95, 0.6, 0.8))
	return true


# ================================================================ étiquettes et invites

func _update_labels() -> void:
	for n in npcs:
		if not n.is_present():
			n.label.visible = false
			continue
		var d: float = _dist_to(n)
		var marked: bool = marked_id == n.id
		n.label.visible = marked or d < 9.0
		n.label.no_depth_test = marked
		var txt: String = n.display_name
		if marked:
			txt += " · pointure " + n.shoe
		n.label.text = txt
		n.label.modulate = Color(1.0, 0.75, 0.35) if marked else (Color(1, 1, 1) if n == target else Color(0.92, 0.88, 0.8, 0.85))


func _update_prompt() -> void:
	if Game.paused or Game.over:
		hud.set_prompt("")
		return
	var txt := ""
	match _interaction():
		"talk":
			if not hud.dialog_visible():
				txt = "[E] Parler à %s   [4] Confidence   [3] Regard" % target.display_name
		"body":
			txt = "Corps %s   [E] Fouiller   [1] Écho   [2] Fil rouge" % Game.de(crime()["victim"].display_name)
		"locker":
			txt = "Casier %s   [E] Crocheter (%d restant%s)" % [Game.de(_near_locker().display_name), crochet_left, "s" if crochet_left > 1 else ""]
		"crate":
			txt = "Caisse de l'équipe %s   [E] Fouiller" % GameData.TEAMS[_near_crate()]["name"]
		"radio":
			txt = "Radio du secteur   [E] Écouter la ronde de nuit"
	hud.set_prompt(txt)


# ================================================================ test automatique
## Lancement : Godot --path . -- --autotest   (ajouter --headless pour ne pas ouvrir de fenêtre)
## Vérifie les salles, les routines, les capacités et l'anti-blocage, puis écrit le résultat.

func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _shot(tag: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img:
		img.save_png("user://autotest_%s.png" % tag)


func _autotest() -> void:
	var fails: Array = []
	var notes: Array = []
	_morning_screen(true)
	hud.dismiss_screen()
	Game.paused = false
	await _wait(0.5)

	# 1. chaque salle : le centre est dégagé (point de repli de « Débloquer »)
	for id in GameData.ROOMS:
		var c: Vector3 = bunker.center(id)
		player.global_position = c
		rig.snap_to(player)
		await _wait(0.4)
		if not player.is_free(c):
			fails.append("centre encombré : " + id)
		await _shot("salle_" + id)
	notes.append("salles ok")

	# 2. une journée en accéléré : chaque habitant doit faire plusieurs tâches différentes
	var seen := {}
	for n in npcs:
		seen[n.id] = {}
	time_boost = 25.0
	player.global_position = Vector3.ZERO
	var shot_done := {}
	while Game.minute < 1250.0:
		await _wait(0.1)
		for n in npcs:
			if n.is_present() and n.state == "task":
				seen[n.id][n.station] = true
				if not shot_done.has(n.station) and shot_done.size() < 6 and GameData.STATIONS[n.station]["fx"] != "":
					shot_done[n.station] = true
	time_boost = 1.0
	for n in npcs:
		if not n.is_present():
			continue
		var k: Array = seen[n.id].keys()
		notes.append("%s : %s" % [n.display_name, ", ".join(PackedStringArray(k))])
		if k.size() < 2:
			fails.append("%s n'a fait que %d tâche(s)" % [n.display_name, k.size()])
	# photo d'un habitant au travail
	for n in npcs:
		if n.is_present() and n.state == "task":
			Game.paused = true
			player.global_position = n.global_position + Vector3(1.6, 0, 1.6)
			rig.snap_to(player)
			rig.yaw = atan2(-(n.global_position.x - player.global_position.x), -(n.global_position.z - player.global_position.z))
			Game.paused = false
			await _wait(0.5)
			await _shot("tache_" + n.id)
			break

	# 3. capacités
	var before := Game.clues.size()
	player.global_position = crime()["pos"] + Vector3(1.2, 0, 0)
	if not player.is_free(player.global_position):
		player.global_position = crime()["pos"]
	rig.snap_to(player)
	await _wait(0.3)
	if not _ab_echo():
		fails.append("Écho a échoué")
	if not _ab_thread():
		fails.append("Fil rouge a échoué")
	await _wait(0.4)
	await _shot("capacites")
	var someone = null
	for n in npcs:
		if n.is_present():
			someone = n
			break
	if someone:
		player.global_position = someone.global_position + Vector3(1.0, 0, 0)
		await _wait(0.2)
		target = someone
		if not _ab_mark():
			fails.append("Regard a échoué")
		target = someone
		if not _ab_confide():
			fails.append("Confidence a échoué")
	if Game.clues.size() <= before:
		fails.append("aucun indice gagné avec les capacités")
	hud.hide_dialog()

	# 4. anti-blocage : coincée dans un casier, Lina doit se dégager seule
	player.global_position = Vector3(-6.45, 0, -11.0)
	Input.action_press("move_forward")
	await _wait(3.6)
	Input.action_release("move_forward")
	await _wait(0.2)
	if not player.is_free(player.global_position, -0.05):
		fails.append("Lina reste coincée dans un casier")
	player.global_position = Vector3(40, 0, 40)
	await _wait(0.3)
	if bunker.room_at(player.global_position) == "":
		fails.append("Lina reste hors de la carte")
	hud.show_pause()
	unstuck()
	hud.hide_pause()
	if not player.is_free(player.global_position):
		fails.append("Débloquer ne mène pas à un endroit dégagé")
	notes.append("anti-blocage vérifié")

	var out := "\n".join(PackedStringArray(notes))
	if fails.is_empty():
		out += "\nAUTOTEST OK"
	else:
		out += "\nAUTOTEST ÉCHEC :\n- " + "\n- ".join(PackedStringArray(fails))
	print(out)
	var f := FileAccess.open("user://autotest.txt", FileAccess.WRITE)
	if f:
		f.store_string(out)
		f.close()
	get_tree().quit(0 if fails.is_empty() else 1)
