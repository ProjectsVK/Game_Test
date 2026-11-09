extends Node3D
## Construit le Secteur C : salles, murs de roche et de béton, mobilier, lumières.
## Fournit aussi la géographie aux habitants (salle d'un point, trajets, places).

const Mats := preload("res://scripts/materials.gd")

const WALL_H := 4.2
const WALL_T := 0.5
const DOOR_HALF := 1.3
const HUB := Vector3.ZERO

var beds: Array = []       # places debout devant chaque lit (Vector3)
var lockers: Array = []    # position de chaque casier (Vector3)
var crates := {}           # équipe -> position de la caisse (cachette possible)
var seats: Array = []      # places assises au réfectoire

var _static: StaticBody3D


func build() -> void:
	_static = StaticBody3D.new()
	_static.collision_layer = 1
	_static.collision_mask = 0
	add_child(_static)
	_build_rooms()
	_build_walls()
	_build_props()
	_build_lights()


# ---------------------------------------------------------------- géographie

func rect(room: String) -> Array:
	return GameData.ROOMS[room]["rect"]


func center(room: String) -> Vector3:
	var r := rect(room)
	return Vector3((r[0] + r[1]) * 0.5, 0.0, (r[2] + r[3]) * 0.5)


func room_at(p: Vector3) -> String:
	for id in GameData.ROOMS:
		var r: Array = GameData.ROOMS[id]["rect"]
		if p.x >= r[0] and p.x <= r[1] and p.z >= r[2] and p.z <= r[3]:
			return id
	return ""


func door_points(room: String) -> Dictionary:
	var d: Array = GameData.ROOMS[room]["door"]
	var door := Vector3(d[0], 0.0, d[1])
	var u := door.normalized()
	return {"inner": door + u * 1.4, "outer": door - u * 1.4}


## Trajet en points de passage : on traverse toujours le réfectoire par son centre.
func route(from: String, to: String, target: Vector3) -> Array:
	var pts: Array = []
	if from != to:
		if from != "" and from != "refectoire":
			var a := door_points(from)
			pts.append(a["inner"])
			pts.append(a["outer"])
		pts.append(HUB)
		if to != "refectoire":
			var b := door_points(to)
			pts.append(b["outer"])
			pts.append(b["inner"])
	pts.append(target)
	return pts


func room_spot(room: String, rng: RandomNumberGenerator) -> Vector3:
	if room == "refectoire":
		if rng.randf() < 0.5:
			return seats[rng.randi() % seats.size()]
		return Vector3(rng.randf_range(-5.0, 5.0), 0.0, rng.randf_range(-3.8, -1.2))
	var r := rect(room)
	var m := 2.6
	return Vector3(rng.randf_range(r[0] + m, r[1] - m), 0.0, rng.randf_range(r[2] + m, r[3] - m))


func crate_stand(team: String) -> Vector3:
	var c: Vector3 = crates[team]
	var room: String = GameData.TEAMS[team]["room"]
	return c + (center(room) - c).normalized() * 1.5


# ---------------------------------------------------------------- construction

func _box(size: Vector3, pos: Vector3, mat: Material, collide: bool = true, parent: Node = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	(parent if parent else self).add_child(mi)
	if collide:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		cs.position = pos
		_static.add_child(cs)
	return mi


func _cyl(radius: float, height: float, pos: Vector3, mat: Material, collide: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	if collide:
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = radius
		sh.height = height
		cs.shape = sh
		cs.position = pos
		_static.add_child(cs)
	return mi


func _rock(pos: Vector3, scale_v: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radial_segments = 7
	sm.rings = 4
	sm.radius = 1.0
	sm.height = 2.0
	mi.mesh = sm
	mi.material_override = Mats.toon(color, 0.4)
	mi.position = pos
	mi.scale = scale_v
	mi.rotation = Vector3(randf() * 0.6, randf() * TAU, randf() * 0.6)
	add_child(mi)


func _build_rooms() -> void:
	var ceiling := Mats.toon(Color(0.13, 0.15, 0.2), 0.45)
	for id in GameData.ROOMS:
		var r: Array = GameData.ROOMS[id]["rect"]
		var w: float = r[1] - r[0]
		var d: float = r[3] - r[2]
		var c := Vector3((r[0] + r[1]) * 0.5, 0.0, (r[2] + r[3]) * 0.5)
		_box(Vector3(w, 0.2, d), c + Vector3(0, -0.1, 0), Mats.toon(GameData.ROOMS[id]["floor"], 0.35))
		_box(Vector3(w + 1.0, 0.4, d + 1.0), c + Vector3(0, WALL_H + 0.2, 0), ceiling)
		# poutres métalliques sous la voûte
		var beam := Mats.toon(Color(0.32, 0.27, 0.22), 0.2)
		var n := int(w / 4.0)
		for i in range(1, n + 1):
			var x: float = r[0] + i * w / float(n + 1)
			_box(Vector3(0.3, 0.35, d), Vector3(x, WALL_H - 0.15, c.z), beam, false)


func _wall(a: Vector3, b: Vector3, gap: bool) -> void:
	var lower := Mats.toon(Color(0.36, 0.37, 0.4), 0.25)   # béton
	var upper := Mats.toon(Color(0.24, 0.24, 0.3), 0.5)    # roche
	var horiz: bool = absf(a.z - b.z) < 0.01
	var s: float = a.x if horiz else a.z
	var e: float = b.x if horiz else b.z
	var segs: Array = []
	if gap:
		var mid := (s + e) * 0.5
		segs = [[s, mid - DOOR_HALF], [mid + DOOR_HALF, e]]
	else:
		segs = [[s, e]]
	for seg in segs:
		var seg_len: float = seg[1] - seg[0]
		var m: float = (seg[0] + seg[1]) * 0.5
		var size_low := Vector3(seg_len + WALL_T, 2.2, WALL_T) if horiz else Vector3(WALL_T, 2.2, seg_len + WALL_T)
		var size_up := Vector3(seg_len + WALL_T, WALL_H - 2.2, WALL_T + 0.3) if horiz else Vector3(WALL_T + 0.3, WALL_H - 2.2, seg_len + WALL_T)
		var p := Vector3(m, 0, a.z) if horiz else Vector3(a.x, 0, m)
		_box(size_low, p + Vector3(0, 1.1, 0), lower)
		_box(size_up, p + Vector3(0, 2.2 + (WALL_H - 2.2) * 0.5, 0), upper)
		# bande de rivets et tuyau le long du mur
		var trim := Mats.toon(Color(0.45, 0.33, 0.22), 0.15)
		var tsize := Vector3(seg_len, 0.12, WALL_T + 0.08) if horiz else Vector3(WALL_T + 0.08, 0.12, seg_len)
		_box(tsize, p + Vector3(0, 2.22, 0), trim, false)
	if gap:
		var mid := (s + e) * 0.5
		var frame := Mats.toon(Color(0.5, 0.36, 0.2), 0.15, 0.0)
		var hazard := Mats.toon(Color(0.8, 0.6, 0.15), 0.2)
		for side in [-1.0, 1.0]:
			var off: float = mid + side * (DOOR_HALF + 0.15)
			var fp := Vector3(off, 1.5, a.z) if horiz else Vector3(a.x, 1.5, off)
			var fs := Vector3(0.3, 3.0, WALL_T + 0.25) if horiz else Vector3(WALL_T + 0.25, 3.0, 0.3)
			_box(fs, fp, frame, false)
		var lp := Vector3(mid, 3.05, a.z) if horiz else Vector3(a.x, 3.05, mid)
		var ls := Vector3(DOOR_HALF * 2 + 0.6, 0.3, WALL_T + 0.25) if horiz else Vector3(WALL_T + 0.25, 0.3, DOOR_HALF * 2 + 0.6)
		_box(ls, lp, hazard, false)


func _build_walls() -> void:
	# réfectoire : 4 portes
	_wall(Vector3(-7, 0, -6), Vector3(7, 0, -6), true)
	_wall(Vector3(-7, 0, 6), Vector3(7, 0, 6), false)
	_wall(Vector3(-7, 0, -6), Vector3(-7, 0, 6), true)
	_wall(Vector3(7, 0, -6), Vector3(7, 0, 6), true)
	# dortoir
	_wall(Vector3(-7, 0, -18), Vector3(7, 0, -18), false)
	_wall(Vector3(-7, 0, -18), Vector3(-7, 0, -6), false)
	_wall(Vector3(7, 0, -18), Vector3(7, 0, -6), false)
	# atelier
	_wall(Vector3(7, 0, -6), Vector3(19, 0, -6), false)
	_wall(Vector3(7, 0, 6), Vector3(19, 0, 6), false)
	_wall(Vector3(19, 0, -6), Vector3(19, 0, 6), false)
	# infirmerie
	_wall(Vector3(-19, 0, -6), Vector3(-7, 0, -6), false)
	_wall(Vector3(-19, 0, 6), Vector3(-7, 0, 6), false)
	_wall(Vector3(-19, 0, -6), Vector3(-19, 0, 6), false)
	# la grotte perce sous le bunker : rochers incrustés dans les coins
	var rock := Color(0.2, 0.21, 0.27)
	for p in [Vector3(-6.4, 0.4, 5.4), Vector3(6.4, 0.3, 5.3), Vector3(-6.3, 0.5, -17.4), Vector3(6.2, 0.4, -17.2),
			Vector3(18.4, 0.4, 5.4), Vector3(-18.4, 0.5, 5.3), Vector3(18.3, 0.3, -5.4), Vector3(-18.3, 0.4, -5.4)]:
		_rock(p, Vector3(1.3, 1.1, 1.2), rock)
		_rock(p + Vector3(0, 2.6, 0), Vector3(1.0, 1.4, 0.9), rock)


func _build_props() -> void:
	var wood := Mats.toon(Color(0.42, 0.27, 0.16), 0.3)
	var dark_wood := Mats.toon(Color(0.3, 0.19, 0.12), 0.3)
	var metal := Mats.toon(Color(0.36, 0.42, 0.46), 0.15)
	var copper := Mats.toon(Color(0.62, 0.36, 0.2), 0.2)
	var cloth := Mats.toon(Color(0.78, 0.72, 0.6), 0.25)
	var crate_mat := Mats.toon(Color(0.45, 0.32, 0.18), 0.35)

	# Réfectoire : tables au sud, cuisine au nord, l'axe central reste libre.
	for x in [-4.2, 4.2]:
		_box(Vector3(3.2, 0.12, 1.3), Vector3(x, 0.8, 3.0), wood)
		_box(Vector3(0.15, 0.75, 1.0), Vector3(x - 1.3, 0.38, 3.0), dark_wood, false)
		_box(Vector3(0.15, 0.75, 1.0), Vector3(x + 1.3, 0.38, 3.0), dark_wood, false)
		_box(Vector3(3.2, 0.1, 0.4), Vector3(x, 0.45, 2.05), dark_wood, false)
		_box(Vector3(3.2, 0.1, 0.4), Vector3(x, 0.45, 3.95), dark_wood, false)
		for k in [-0.8, 0.8]:
			seats.append(Vector3(x + k, 0.0, 1.55))
	for x in [-4.0, 4.0]:
		_box(Vector3(4.0, 1.0, 0.8), Vector3(x, 0.5, -5.35), metal)
	_cyl(0.45, 0.5, Vector3(-3.0, 1.25, -5.35), copper)
	_cyl(0.3, 0.6, Vector3(4.6, 1.3, -5.35), metal)
	crates["bleu"] = Vector3(-6.2, 0.0, -3.6)

	# Dortoir : 6 lits contre le mur nord, casiers à l'ouest.
	for i in 6:
		var x: float = [-5.5, -3.5, -1.5, 1.5, 3.5, 5.5][i]
		_box(Vector3(1.1, 0.5, 2.1), Vector3(x, 0.25, -16.5), dark_wood)
		_box(Vector3(1.0, 0.15, 1.5), Vector3(x, 0.57, -16.25), cloth, false)
		_box(Vector3(0.8, 0.2, 0.45), Vector3(x, 0.62, -17.2), Mats.toon(Color(0.88, 0.84, 0.76), 0.2), false)
		beds.append(Vector3(x, 0.0, -14.6))
	for i in 6:
		var z: float = -14.0 + i * 1.0
		_box(Vector3(0.6, 1.9, 0.9), Vector3(-6.45, 0.95, z), metal)
		_box(Vector3(0.05, 0.25, 0.08), Vector3(-6.13, 1.0, z + 0.3), copper, false)
		lockers.append(Vector3(-6.45, 0.0, z))

	# Atelier : établi, chaudière, tuyaux.
	_box(Vector3(1.2, 1.0, 5.0), Vector3(18.0, 0.5, 0.0), wood)
	_box(Vector3(0.9, 0.08, 0.5), Vector3(17.9, 1.05, -1.0), metal, false)
	_cyl(0.9, 2.8, Vector3(16.6, 1.4, 4.4), copper, true)
	_cyl(0.18, 12.0, Vector3(13.0, 3.3, -5.55), copper).rotation = Vector3(0, 0, PI / 2)
	_cyl(0.12, 12.0, Vector3(13.0, 3.0, -5.6), metal).rotation = Vector3(0, 0, PI / 2)
	crates["rouge"] = Vector3(17.8, 0.0, -4.7)

	# Infirmerie : lits de soin, armoire à pharmacie.
	for z in [-2.8, 0.2, 3.2]:
		_box(Vector3(1.0, 0.6, 2.0), Vector3(-17.9, 0.3, z), Mats.toon(Color(0.82, 0.86, 0.82), 0.15))
	_box(Vector3(3.0, 2.0, 0.6), Vector3(-12.5, 1.0, -5.55), Mats.toon(Color(0.3, 0.42, 0.4), 0.2))
	crates["jaune"] = Vector3(-17.8, 0.0, -4.9)

	for team in crates:
		var c: Vector3 = crates[team]
		_box(Vector3(1.0, 1.0, 1.0), c + Vector3(0, 0.5, 0), crate_mat)
		_box(Vector3(1.04, 0.1, 1.04), c + Vector3(0, 0.75, 0), dark_wood, false)


func _build_lights() -> void:
	for id in GameData.ROOMS:
		var col: Color = GameData.ROOMS[id]["light"]
		var c := center(id)
		var omni := OmniLight3D.new()
		omni.light_color = col
		omni.light_energy = 2.6
		omni.omni_range = 11.0
		omni.omni_attenuation = 1.2
		omni.shadow_enabled = true
		omni.position = c + Vector3(0, 3.4, 0)
		add_child(omni)
		# suspension visible
		_cyl(0.03, 0.8, c + Vector3(0, 3.95, 0), Mats.toon(Color(0.1, 0.1, 0.1), 0.0))
		var bulb := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.18
		sm.height = 0.36
		bulb.mesh = sm
		bulb.material_override = Mats.glow(col, 4.0)
		bulb.position = c + Vector3(0, 3.5, 0)
		add_child(bulb)
	# lumières d'ambiance : braises de la chaudière, veilleuses vertes de l'infirmerie
	var ember := OmniLight3D.new()
	ember.light_color = Color(1.0, 0.4, 0.12)
	ember.light_energy = 2.0
	ember.omni_range = 5.0
	ember.position = Vector3(16.0, 0.8, 3.4)
	add_child(ember)
	var ember_glow := _box(Vector3(0.6, 0.35, 0.05), Vector3(16.3, 0.7, 3.5), Mats.glow(Color(1.0, 0.45, 0.1), 5.0), false)
	ember_glow.rotation.y = -0.6
	for z in [-2.8, 0.2, 3.2]:
		var v := OmniLight3D.new()
		v.light_color = Color(0.3, 1.0, 0.6)
		v.light_energy = 1.2
		v.omni_range = 3.5
		v.position = Vector3(-16.9, 1.0, z)
		add_child(v)
		_cyl(0.06, 0.25, Vector3(-16.9, 0.75, z - 0.7), Mats.glow(Color(0.4, 1.0, 0.65), 4.0))
	var kitchen := OmniLight3D.new()
	kitchen.light_color = Color(1.0, 0.7, 0.35)
	kitchen.light_energy = 1.5
	kitchen.omni_range = 6.0
	kitchen.position = Vector3(-3.0, 2.0, -4.8)
	add_child(kitchen)
