extends Node3D
## Construit le Secteur C : salles, murs, mobilier détaillé, lumières et ambiances sonores.
## Fournit aussi la géographie aux habitants (salle d'un point, trajets, places).
## Règle anti-blocage : seuls les gros meubles ont une collision, toujours en boîtes simples,
## et le centre de chaque salle reste libre (point de repli du bouton « Débloquer »).

const Mats := preload("res://scripts/materials.gd")

const WALL_H := 4.2
const WALL_T := 0.5
const DOOR_HALF := 1.4
const HUB := Vector3.ZERO
const OL := 0.012   # contour des gros meubles

var beds: Array = []       # places debout devant chaque lit (Vector3)
var lockers: Array = []    # position de chaque casier (Vector3)
var crates := {}           # équipe -> position de la caisse (cachette possible)
var radio := Vector3(0, 0, 4.7)
var ambience := {}         # salle -> AudioStreamPlayer

var _static: StaticBody3D
var _rng := RandomNumberGenerator.new()
var M := {}


func build() -> void:
	_rng.seed = 1013
	_static = StaticBody3D.new()
	_static.collision_layer = 1
	_static.collision_mask = 0
	add_child(_static)
	_make_materials()
	_build_rooms()
	_build_walls()
	_build_refectoire()
	_build_dortoir()
	_build_atelier()
	_build_infirmerie()
	_build_crates()
	_build_lights()
	_build_ambience()


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


func ground_at(p: Vector3) -> String:
	var r := room_at(p)
	return GameData.ROOMS[r]["ground"] if r != "" else "concrete"


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


## Un endroit dégagé au sol (pour le corps de la victime).
func room_spot(room: String, rng: RandomNumberGenerator) -> Vector3:
	match room:
		"refectoire":
			return Vector3(rng.randf_range(-4.5, 4.5), 0.0, rng.randf_range(-3.4, -1.6))
		"atelier":
			return Vector3(rng.randf_range(10.0, 14.5), 0.0, rng.randf_range(-3.0, 2.5))
		"infirmerie":
			return Vector3(rng.randf_range(-15.5, -10.0), 0.0, rng.randf_range(-3.0, 2.5))
	var r := rect(room)
	return Vector3(rng.randf_range(r[0] + 2.6, r[1] - 2.6), 0.0, rng.randf_range(r[2] + 2.6, r[3] - 2.6))


func crate_stand(team: String) -> Vector3:
	var c: Vector3 = crates[team]
	var room: String = GameData.TEAMS[team]["room"]
	return c + (center(room) - c).normalized() * 1.5


## Fondu des ambiances : seule la salle où se trouve le joueur est audible.
func update_ambience(p: Vector3, delta: float) -> void:
	var here := room_at(p)
	for id in ambience:
		var pl: AudioStreamPlayer = ambience[id]
		var want := 0.0 if id == here else -40.0
		pl.volume_db = lerpf(pl.volume_db, want, 1.0 - exp(-2.5 * delta))


# ---------------------------------------------------------------- briques

func _make_materials() -> void:
	M = {
		"wood": Mats.toon(Color(0.45, 0.29, 0.17), 0.3, OL),
		"wood_dark": Mats.toon(Color(0.3, 0.19, 0.12), 0.3, OL),
		"wood_light": Mats.toon(Color(0.62, 0.45, 0.28), 0.3),
		"metal": Mats.toon(Color(0.38, 0.43, 0.47), 0.15, OL),
		"metal_dark": Mats.toon(Color(0.2, 0.22, 0.25), 0.15, OL),
		"rust": Mats.toon(Color(0.5, 0.28, 0.17), 0.4, OL),
		"copper": Mats.toon(Color(0.68, 0.4, 0.22), 0.2, OL),
		"brass": Mats.toon(Color(0.78, 0.6, 0.28), 0.15),
		"cloth": Mats.toon(Color(0.8, 0.74, 0.62), 0.25),
		"paper": Mats.toon(Color(0.93, 0.89, 0.78), 0.1),
		"white": Mats.toon(Color(0.9, 0.9, 0.86), 0.12, OL),
		"ceramic": Mats.toon(Color(0.86, 0.84, 0.78), 0.05),
		"black": Mats.toon(Color(0.08, 0.08, 0.09), 0.1),
		"green": Mats.toon(Color(0.28, 0.5, 0.3), 0.4),
		"leaf": Mats.toon(Color(0.36, 0.58, 0.32), 0.45),
		"soil": Mats.toon(Color(0.22, 0.15, 0.1), 0.5),
		"glass": Mats.toon(Color(0.55, 0.75, 0.78), 0.0),
		"hazard": Mats.toon(Color(0.85, 0.62, 0.15), 0.2),
		"rock": Mats.toon(Color(0.2, 0.21, 0.27), 0.45),
		"ceiling": Mats.toon(Color(0.13, 0.15, 0.2), 0.45),
		"beam": Mats.toon(Color(0.32, 0.27, 0.22), 0.2),
	}


func _box(size: Vector3, pos: Vector3, mat: Material, collide: bool = false, parent: Node3D = null, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	(parent if parent else self).add_child(mi)
	if collide and parent == null:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		cs.position = pos
		cs.rotation = rot
		_static.add_child(cs)
	return mi


func _cyl(top: float, bottom: float, h: float, pos: Vector3, mat: Material, collide: bool = false, parent: Node3D = null, rot: Vector3 = Vector3.ZERO, seg: int = 16) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = top
	cm.bottom_radius = bottom
	cm.height = h
	cm.radial_segments = seg
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	(parent if parent else self).add_child(mi)
	if collide and parent == null:
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = maxf(top, bottom)
		sh.height = h
		cs.shape = sh
		cs.position = pos
		_static.add_child(cs)
	return mi


func _ball(r: float, pos: Vector3, mat: Material, scl: Vector3 = Vector3.ONE, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 12
	sm.rings = 6
	mi.mesh = sm
	mi.material_override = mat
	mi.position = pos
	mi.scale = scl
	(parent if parent else self).add_child(mi)
	return mi


func _glow(r: float, pos: Vector3, color: Color, energy: float = 4.0) -> MeshInstance3D:
	return _ball(r, pos, Mats.glow(color, energy))


func _light(pos: Vector3, color: Color, energy: float, rng: float) -> OmniLight3D:
	var o := OmniLight3D.new()
	o.light_color = color
	o.light_energy = energy
	o.omni_range = rng
	o.omni_attenuation = 1.3
	o.shadow_enabled = false
	o.position = pos
	add_child(o)
	return o


## Groupe tourné (chaise, fauteuil…) : face = direction vers laquelle on regarde quand on est assis.
func _group(pos: Vector3, face: Vector3) -> Node3D:
	var g := Node3D.new()
	add_child(g)
	g.position = pos
	var d := face - pos
	g.rotation.y = atan2(d.x, d.z)
	return g


func _chair(pos: Vector3, face: Vector3, mat: Material) -> void:
	var g := _group(pos, face)
	_box(Vector3(0.46, 0.06, 0.44), Vector3(0, 0.45, 0), mat, false, g)
	for x in [-0.19, 0.19]:
		for z in [-0.18, 0.18]:
			_box(Vector3(0.05, 0.45, 0.05), Vector3(x, 0.22, z), mat, false, g)
	_box(Vector3(0.46, 0.5, 0.05), Vector3(0, 0.75, -0.22), mat, false, g)


func _stool(pos: Vector3, mat: Material) -> void:
	_cyl(0.2, 0.2, 0.06, pos + Vector3(0, 0.45, 0), mat)
	_cyl(0.04, 0.06, 0.43, pos + Vector3(0, 0.22, 0), M["metal_dark"])


func _plant(pos: Vector3, big: bool = false) -> void:
	var s := 1.4 if big else 1.0
	_cyl(0.2 * s, 0.15 * s, 0.35 * s, pos + Vector3(0, 0.175 * s, 0), M["rust"])
	_cyl(0.18 * s, 0.18 * s, 0.03, pos + Vector3(0, 0.35 * s, 0), M["soil"])
	for i in 5:
		var a := i * TAU / 5.0 + _rng.randf() * 0.5
		_ball(0.15 * s, pos + Vector3(cos(a) * 0.12 * s, (0.5 + _rng.randf() * 0.25) * s, sin(a) * 0.12 * s), M["leaf"], Vector3(1, 1.4, 1))
	# champignons lumineux : seules plantes qui poussent si loin sous terre
	_glow(0.04 * s, pos + Vector3(0.1 * s, 0.4 * s, 0.05), Color(0.5, 0.9, 1.0), 2.0)


func _cans(origin: Vector3, n: int, along: Vector3, palette: Array) -> void:
	for i in n:
		var c: Color = palette[i % palette.size()]
		var h := 0.12 + _rng.randf() * 0.12
		_cyl(0.05, 0.05, h, origin + along * (float(i) * 0.13) + Vector3(0, h * 0.5, 0), Mats.toon(c, 0.2))


func _books(origin: Vector3, n: int, along: Vector3) -> void:
	var cols := [Color(0.5, 0.16, 0.12), Color(0.18, 0.3, 0.42), Color(0.3, 0.38, 0.2), Color(0.55, 0.42, 0.2), Color(0.32, 0.2, 0.3)]
	for i in n:
		var h := 0.2 + _rng.randf() * 0.08
		var m := Mats.toon(cols[_rng.randi() % cols.size()], 0.15)
		var size := Vector3(0.06, h, 0.18) if absf(along.x) > 0.5 else Vector3(0.18, h, 0.06)
		_box(size, origin + along * (float(i) * 0.07) + Vector3(0, h * 0.5, 0), m)


## Tableau ou affiche accroché au mur. normal = direction vers l'intérieur de la pièce.
func _frame(pos: Vector3, normal: Vector3, size: Vector2, color: Color, frame_mat: Material = null) -> void:
	var g := _group(pos, pos + normal)
	_box(Vector3(size.x + 0.08, size.y + 0.08, 0.03), Vector3(0, 0, 0), frame_mat if frame_mat else M["wood_dark"], false, g)
	_box(Vector3(size.x, size.y, 0.035), Vector3(0, 0, 0.005), Mats.toon(color, 0.5), false, g)
	# quelques coups de pinceau pour suggérer un dessin
	_box(Vector3(size.x * 0.5, size.y * 0.12, 0.04), Vector3(-size.x * 0.1, size.y * 0.15, 0.008), Mats.toon(color.darkened(0.35), 0.5), false, g)
	_ball(size.y * 0.16, Vector3(size.x * 0.22, -size.y * 0.12, 0.01), Mats.toon(color.lightened(0.3), 0.4), Vector3(1, 1, 0.1), g)


func _rug(pos: Vector3, size: Vector2, color: Color, border: Color) -> void:
	_box(Vector3(size.x, 0.02, size.y), pos + Vector3(0, 0.012, 0), Mats.toon(border, 0.4))
	_box(Vector3(size.x - 0.3, 0.022, size.y - 0.3), pos + Vector3(0, 0.014, 0), Mats.toon(color, 0.5))
	_box(Vector3(size.x - 0.8, 0.024, size.y - 0.8), pos + Vector3(0, 0.016, 0), Mats.toon(color.lightened(0.15), 0.5))


func _shelf_unit(pos: Vector3, size: Vector3, levels: int, mat: Material, collide: bool = true) -> Array:
	## Étagère contre un mur. Renvoie la hauteur de chaque planche (pour la remplir).
	var heights: Array = []
	var along_x := size.x > size.z
	_box(Vector3(size.x, 0.04, size.z), pos + Vector3(0, size.y, 0), mat)
	for side in [-1.0, 1.0]:
		var p := pos + (Vector3(side * size.x * 0.5, size.y * 0.5, 0) if along_x else Vector3(0, size.y * 0.5, side * size.z * 0.5))
		_box(Vector3(0.05, size.y, size.z) if along_x else Vector3(size.x, size.y, 0.05), p, mat)
	for i in levels:
		var h := 0.15 + i * (size.y - 0.2) / float(levels)
		_box(Vector3(size.x, 0.04, size.z), pos + Vector3(0, h, 0), mat)
		heights.append(h + 0.02)
	if collide:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		cs.position = pos + Vector3(0, size.y * 0.5, 0)
		_static.add_child(cs)
	return heights


func _lamp_hanging(pos: Vector3, color: Color, energy: float, rng: float) -> void:
	_cyl(0.01, 0.01, WALL_H - pos.y, Vector3(pos.x, (WALL_H + pos.y) * 0.5, pos.z), M["black"])
	_cyl(0.08, 0.3, 0.22, pos + Vector3(0, 0.08, 0), M["metal_dark"])
	_glow(0.08, pos - Vector3(0, 0.02, 0), color, 5.0)
	_light(pos - Vector3(0, 0.2, 0), color, energy, rng)


# ---------------------------------------------------------------- sols, plafonds, murs

func _build_rooms() -> void:
	for id in GameData.ROOMS:
		var r: Array = GameData.ROOMS[id]["rect"]
		var w: float = r[1] - r[0]
		var d: float = r[3] - r[2]
		var c := Vector3((r[0] + r[1]) * 0.5, 0.0, (r[2] + r[3]) * 0.5)
		var floor_c: Color = GameData.ROOMS[id]["floor"]
		_box(Vector3(w, 0.2, d), c + Vector3(0, -0.1, 0), Mats.toon(floor_c, 0.35), true)
		_box(Vector3(w + 1.0, 0.4, d + 1.0), c + Vector3(0, WALL_H + 0.2, 0), M["ceiling"], true)
		var n := int(w / 4.0)
		for i in range(1, n + 1):
			var x: float = r[0] + i * w / float(n + 1)
			_box(Vector3(0.3, 0.35, d), Vector3(x, WALL_H - 0.15, c.z), M["beam"])
		match id:
			"refectoire":
				# dalles de béton jointoyées
				var seam := Mats.toon(floor_c.darkened(0.35), 0.2)
				for i in range(1, 7):
					_box(Vector3(0.04, 0.01, d), Vector3(r[0] + i * 2.0, 0.005, c.z), seam)
				for i in range(1, 6):
					_box(Vector3(w, 0.01, 0.04), Vector3(c.x, 0.005, r[2] + i * 2.0), seam)
			"dortoir":
				# parquet de planches récupérées
				for i in int(d / 0.5):
					var tone := floor_c.lightened(0.06) if i % 2 == 0 else floor_c.darkened(0.08)
					_box(Vector3(w, 0.01, 0.46), Vector3(c.x, 0.005, r[2] + 0.25 + i * 0.5), Mats.toon(tone, 0.4))
			"atelier":
				var seam := Mats.toon(floor_c.darkened(0.4), 0.2)
				for i in range(1, 6):
					_box(Vector3(0.05, 0.012, d), Vector3(r[0] + i * 2.0, 0.006, c.z), seam)
				for i in range(1, 6):
					_box(Vector3(w, 0.012, 0.05), Vector3(c.x, 0.006, r[2] + i * 2.0), seam)
				var oil := Mats.toon(Color(0.1, 0.1, 0.11), 0.6)
				for p in [Vector3(11.5, 0, -2.5), Vector3(15.0, 0, -0.5), Vector3(9.5, 0, 2.5)]:
					_cyl(0.6, 0.6, 0.01, p + Vector3(0, 0.008, 0), oil).scale = Vector3(1.3, 1, 0.8)
			"infirmerie":
				# carrelage en damier
				var tile := Mats.toon(floor_c.darkened(0.18), 0.15)
				for ix in int(w):
					for iz in int(d):
						if (ix + iz) % 2 == 0:
							_box(Vector3(0.98, 0.01, 0.98), Vector3(r[0] + 0.5 + ix, 0.005, r[2] + 0.5 + iz), tile)


func _wall_mat(room: String) -> Material:
	match room:
		"refectoire":
			return Mats.toon(Color(0.45, 0.37, 0.3), 0.3)
		"dortoir":
			return Mats.toon(Color(0.4, 0.27, 0.18), 0.35)
		"atelier":
			return Mats.toon(Color(0.33, 0.3, 0.28), 0.4)
		"infirmerie":
			return Mats.toon(Color(0.62, 0.7, 0.66), 0.15)
	return Mats.toon(Color(0.3, 0.31, 0.34), 0.25)


## Mur entre deux zones. neg = salle du côté -z (mur horizontal) ou -x (mur vertical).
## Chaque face prend la matière de sa salle ; la collision est une seule boîte pleine.
func _wall(a: Vector3, b: Vector3, gap: bool, neg: String, pos: String) -> void:
	var upper: Material = M["rock"]
	var horiz: bool = absf(a.z - b.z) < 0.01
	var s: float = a.x if horiz else a.z
	var e: float = b.x if horiz else b.z
	var segs: Array = []
	var mid := (s + e) * 0.5
	if gap:
		segs = [[s, mid - DOOR_HALF], [mid + DOOR_HALF, e]]
	else:
		segs = [[s, e]]
	var trim := Mats.toon(Color(0.45, 0.33, 0.22), 0.15)
	for seg in segs:
		var seg_len: float = seg[1] - seg[0]
		var m: float = (seg[0] + seg[1]) * 0.5
		var p := Vector3(m, 0, a.z) if horiz else Vector3(a.x, 0, m)
		var full := Vector3(seg_len + WALL_T, 2.2, WALL_T) if horiz else Vector3(WALL_T, 2.2, seg_len + WALL_T)
		# collision pleine sur toute la hauteur
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(full.x, WALL_H, full.z)
		cs.shape = sh
		cs.position = p + Vector3(0, WALL_H * 0.5, 0)
		_static.add_child(cs)
		# deux demi-épaisseurs peintes différemment
		var half := Vector3(full.x, 2.2, WALL_T * 0.5) if horiz else Vector3(WALL_T * 0.5, 2.2, full.z)
		var off := Vector3(0, 0, WALL_T * 0.25) if horiz else Vector3(WALL_T * 0.25, 0, 0)
		_box(half, p + Vector3(0, 1.1, 0) - off, _wall_mat(neg))
		_box(half, p + Vector3(0, 1.1, 0) + off, _wall_mat(pos))
		var size_up := Vector3(seg_len + WALL_T, WALL_H - 2.2, WALL_T + 0.3) if horiz else Vector3(WALL_T + 0.3, WALL_H - 2.2, seg_len + WALL_T)
		_box(size_up, p + Vector3(0, 2.2 + (WALL_H - 2.2) * 0.5, 0), upper)
		var tsize := Vector3(seg_len, 0.12, WALL_T + 0.08) if horiz else Vector3(WALL_T + 0.08, 0.12, seg_len)
		_box(tsize, p + Vector3(0, 2.22, 0), trim)
		var bsize := Vector3(seg_len, 0.14, WALL_T + 0.06) if horiz else Vector3(WALL_T + 0.06, 0.14, seg_len)
		_box(bsize, p + Vector3(0, 0.07, 0), M["wood_dark"])
	if gap:
		var frame := Mats.toon(Color(0.5, 0.36, 0.2), 0.15, OL)
		for side in [-1.0, 1.0]:
			var off2: float = mid + side * (DOOR_HALF + 0.12)
			var fp := Vector3(off2, 1.5, a.z) if horiz else Vector3(a.x, 1.5, off2)
			var fs := Vector3(0.24, 3.0, WALL_T + 0.25) if horiz else Vector3(WALL_T + 0.25, 3.0, 0.24)
			_box(fs, fp, frame)
		var lp := Vector3(mid, 3.05, a.z) if horiz else Vector3(a.x, 3.05, mid)
		var ls := Vector3(DOOR_HALF * 2 + 0.5, 0.3, WALL_T + 0.25) if horiz else Vector3(WALL_T + 0.25, 0.3, DOOR_HALF * 2 + 0.5)
		_box(ls, lp, M["hazard"])
		# panneau au-dessus de la porte, lisible des deux côtés
		for sgn in [-1.0, 1.0]:
			var room: String = neg if sgn < 0 else pos
			var other: String = pos if sgn < 0 else neg
			var lbl := Label3D.new()
			lbl.text = GameData.ROOMS[other]["name"].to_upper() if other != "" else ""
			lbl.font_size = 64
			lbl.pixel_size = 0.004
			lbl.outline_size = 10
			lbl.modulate = Color(0.95, 0.85, 0.65)
			lbl.outline_modulate = Color(0.05, 0.04, 0.03)
			var f = load("res://assets/fonts/AlegreyaSC-Bold.woff2")
			if f:
				lbl.font = f
			var n := Vector3(0, 0, sgn) if horiz else Vector3(sgn, 0, 0)
			lbl.position = lp + n * (WALL_T * 0.5 + 0.14) + Vector3(0, 0.0, 0)
			lbl.rotation.y = atan2(n.x, n.z)
			add_child(lbl)
			if room == "":
				lbl.visible = false


func _build_walls() -> void:
	_wall(Vector3(-7, 0, -6), Vector3(7, 0, -6), true, "dortoir", "refectoire")
	_wall(Vector3(-7, 0, 6), Vector3(7, 0, 6), false, "refectoire", "")
	_wall(Vector3(-7, 0, -6), Vector3(-7, 0, 6), true, "infirmerie", "refectoire")
	_wall(Vector3(7, 0, -6), Vector3(7, 0, 6), true, "refectoire", "atelier")
	_wall(Vector3(-7, 0, -18), Vector3(7, 0, -18), false, "", "dortoir")
	_wall(Vector3(-7, 0, -18), Vector3(-7, 0, -6), false, "", "dortoir")
	_wall(Vector3(7, 0, -18), Vector3(7, 0, -6), false, "dortoir", "")
	_wall(Vector3(7, 0, -6), Vector3(19, 0, -6), false, "", "atelier")
	_wall(Vector3(7, 0, 6), Vector3(19, 0, 6), false, "atelier", "")
	_wall(Vector3(19, 0, -6), Vector3(19, 0, 6), false, "atelier", "")
	_wall(Vector3(-19, 0, -6), Vector3(-7, 0, -6), false, "", "infirmerie")
	_wall(Vector3(-19, 0, 6), Vector3(-7, 0, 6), false, "infirmerie", "")
	_wall(Vector3(-19, 0, -6), Vector3(-19, 0, 6), false, "", "infirmerie")
	# la roche de la grotte perce dans les angles
	for p in [Vector3(-6.4, 0.4, 5.4), Vector3(6.4, 0.3, 5.3), Vector3(-6.3, 0.5, -17.4), Vector3(6.2, 0.4, -17.4),
			Vector3(18.4, 0.4, 5.5), Vector3(-18.4, 0.5, 5.4), Vector3(18.4, 0.3, -5.5), Vector3(-18.4, 0.4, -5.5)]:
		_rock(p, Vector3(1.0, 0.9, 0.9))
		_rock(p + Vector3(0, 2.6, 0), Vector3(0.9, 1.3, 0.8))


func _rock(pos: Vector3, scale_v: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radial_segments = 7
	sm.rings = 4
	mi.mesh = sm
	mi.material_override = M["rock"]
	mi.position = pos
	mi.scale = scale_v
	mi.rotation = Vector3(_rng.randf() * 0.6, _rng.randf() * TAU, _rng.randf() * 0.6)
	add_child(mi)


# ---------------------------------------------------------------- réfectoire

func _build_refectoire() -> void:
	var counter_top := Mats.toon(Color(0.55, 0.5, 0.44), 0.2, OL)
	# deux plans de travail contre le mur nord, la porte du dortoir reste libre au milieu
	for run in [[-6.6, -1.6], [1.6, 6.6]]:
		var cx: float = (run[0] + run[1]) * 0.5
		var w: float = run[1] - run[0]
		_box(Vector3(w, 0.9, 0.8), Vector3(cx, 0.45, -5.35), M["wood"], true)
		_box(Vector3(w + 0.06, 0.06, 0.86), Vector3(cx, 0.93, -5.33), counter_top)
		for i in int(w / 0.8):
			_box(Vector3(0.7, 0.7, 0.02), Vector3(run[0] + 0.4 + i * 0.8, 0.45, -4.94), M["wood_dark"])
			_box(Vector3(0.12, 0.03, 0.03), Vector3(run[0] + 0.4 + i * 0.8, 0.72, -4.92), M["brass"])
		# étagères murales chargées
		for h in [1.65, 2.05]:
			_box(Vector3(w, 0.04, 0.3), Vector3(cx, h, -5.62), M["wood_dark"])
		_cans(Vector3(run[0] + 0.25, 1.67, -5.62), int(w / 0.14), Vector3(1, 0, 0), [Color(0.7, 0.3, 0.2), Color(0.8, 0.7, 0.4), Color(0.4, 0.5, 0.3), Color(0.6, 0.6, 0.62)])
		for i in int(w / 0.5):
			_cyl(0.09, 0.08, 0.2, Vector3(run[0] + 0.3 + i * 0.5, 2.17, -5.62), Mats.toon(Color(0.55, 0.65, 0.6), 0.05))

	# fourneau (cook_stove) : poêle en fonte, grosse marmite, hotte
	_box(Vector3(1.1, 0.12, 0.7), Vector3(-4.5, 1.02, -5.3), M["metal_dark"])
	_box(Vector3(0.5, 0.06, 0.02), Vector3(-4.5, 0.75, -4.94), Mats.glow(Color(1.0, 0.45, 0.12), 3.0))
	_cyl(0.3, 0.27, 0.34, Vector3(-4.5, 1.25, -5.3), M["copper"])
	_cyl(0.31, 0.31, 0.03, Vector3(-4.5, 1.42, -5.3), M["metal"])
	_cyl(0.18, 0.18, 0.08, Vector3(-3.95, 1.12, -5.4), M["metal"])
	_box(Vector3(1.4, 0.5, 0.8), Vector3(-4.5, 2.6, -5.35), M["metal"])
	_cyl(0.12, 0.12, 1.3, Vector3(-4.5, 3.5, -5.45), M["metal_dark"])
	for i in 4:
		_cyl(0.008, 0.008, 0.3, Vector3(-5.4 + i * 0.18, 2.2, -5.68), M["metal"])
		_ball(0.05, Vector3(-5.4 + i * 0.18, 2.03, -5.66), M["metal"], Vector3(1, 0.5, 1))
	# planche à découper (chop)
	_box(Vector3(0.6, 0.04, 0.4), Vector3(-2.0, 0.98, -5.25), M["wood_light"])
	for i in 4:
		_cyl(0.025, 0.025, 0.18, Vector3(-2.15 + i * 0.07, 1.02, -5.2), Mats.toon(Color(0.9, 0.48, 0.15), 0.2), false, null, Vector3(0, 0, PI / 2))
	_ball(0.11, Vector3(-1.75, 1.08, -5.4), Mats.toon(Color(0.45, 0.62, 0.3), 0.4))
	_box(Vector3(0.4, 0.3, 0.3), Vector3(-2.6, 1.1, -5.45), M["wood"])
	for i in 3:
		_ball(0.06, Vector3(-2.7 + i * 0.1, 1.28, -5.45), Mats.toon(Color(0.7, 0.55, 0.3), 0.3))
	# évier (wash_dishes)
	_box(Vector3(0.8, 0.12, 0.5), Vector3(2.4, 0.92, -5.3), M["ceramic"])
	_box(Vector3(0.66, 0.1, 0.38), Vector3(2.4, 0.95, -5.3), Mats.toon(Color(0.25, 0.35, 0.4), 0.0))
	_cyl(0.02, 0.02, 0.4, Vector3(2.4, 1.15, -5.6), M["brass"])
	_cyl(0.02, 0.02, 0.2, Vector3(2.4, 1.33, -5.5), M["brass"], false, null, Vector3(PI / 2, 0, 0))
	for i in 6:
		_cyl(0.13, 0.11, 0.025, Vector3(3.15, 0.97 + i * 0.028, -5.3), M["ceramic"])
	_box(Vector3(0.35, 0.02, 0.25), Vector3(1.85, 0.97, -5.25), Mats.toon(Color(0.55, 0.62, 0.7), 0.3))
	# rations (count_rations) : caisses, conserves, registre
	_box(Vector3(0.5, 0.35, 0.4), Vector3(5.6, 1.13, -5.4), M["wood"])
	_box(Vector3(0.45, 0.3, 0.38), Vector3(6.15, 1.1, -5.35), M["wood_dark"])
	_cans(Vector3(4.6, 0.96, -5.45), 5, Vector3(1, 0, 0), [Color(0.6, 0.6, 0.62), Color(0.75, 0.3, 0.22)])
	_box(Vector3(0.32, 0.03, 0.24), Vector3(5.0, 0.97, -5.15), M["paper"], false, null, Vector3(0, 0.2, 0))
	# garde-manger contre le mur est
	var hs := _shelf_unit(Vector3(6.45, 0, -3.6), Vector3(0.5, 2.0, 1.6), 4, M["wood_dark"])
	for h in hs:
		_cans(Vector3(6.45, h, -4.25), 9, Vector3(0, 0, 1), [Color(0.6, 0.6, 0.62), Color(0.72, 0.5, 0.25), Color(0.4, 0.55, 0.35)])
	for i in 3:
		_ball(0.2, Vector3(5.85, 0.2, -3.0 - i * 0.42), Mats.toon(Color(0.7, 0.6, 0.42), 0.5), Vector3(1, 1.2, 1))

	# salle à manger : deux longues tables, chaises, couverts
	var seats_info := []
	for id in GameData.STATIONS:
		var st: Dictionary = GameData.STATIONS[id]
		if st["room"] == "refectoire" and st.get("sit", false) and id.begins_with("seat"):
			seats_info.append(st)
	for x in [-4.2, 4.2]:
		_box(Vector3(3.2, 0.1, 1.3), Vector3(x, 0.78, 3.0), M["wood"], true)
		for lx in [-1.4, 1.4]:
			for lz in [-0.5, 0.5]:
				_box(Vector3(0.1, 0.73, 0.1), Vector3(x + lx, 0.37, 3.0 + lz), M["wood_dark"])
		_box(Vector3(2.6, 0.02, 0.4), Vector3(x, 0.84, 3.0), M["cloth"])
		# couverts sur la table
		for k in [-1.0, -0.2, 0.6]:
			_cyl(0.1, 0.07, 0.06, Vector3(x + k, 0.86, 2.55), M["ceramic"])
			_cyl(0.04, 0.035, 0.1, Vector3(x + k + 0.2, 0.88, 2.6), M["metal"])
		_box(Vector3(0.3, 0.12, 0.16), Vector3(x + 0.3, 0.89, 3.2), Mats.toon(Color(0.72, 0.5, 0.25), 0.4))
		_cyl(0.04, 0.05, 0.14, Vector3(x - 0.4, 0.9, 3.05), M["white"])
		_glow(0.025, Vector3(x - 0.4, 1.0, 3.05), Color(1.0, 0.7, 0.3), 5.0)
		# chaises côté sud, décoratives
		for k in [-0.8, 0.8]:
			_chair(Vector3(x + k, 0, 4.05), Vector3(x + k, 0, 3.0), M["wood_dark"])
	for st in seats_info:
		var p := Vector3(st["pos"][0], 0, st["pos"][1])
		_chair(p, Vector3(st["face"][0], 0, st["face"][1]), M["wood_dark"])
	# cartes étalées pour les parties du soir
	for i in 5:
		_box(Vector3(0.07, 0.005, 0.1), Vector3(3.0 + i * 0.09, 0.85, 2.7 + (i % 2) * 0.05), M["paper"], false, null, Vector3(0, i * 0.3, 0))
	_rug(Vector3(0, 0, 0.4), Vector2(2.4, 8.0), Color(0.45, 0.18, 0.14), Color(0.62, 0.45, 0.2))

	# radio du secteur contre le mur sud
	_box(Vector3(1.4, 0.8, 0.6), Vector3(0, 0.4, 5.4), M["wood_dark"], true)
	_box(Vector3(0.9, 0.55, 0.4), Vector3(0, 1.08, 5.45), M["wood"])
	_box(Vector3(0.5, 0.35, 0.02), Vector3(-0.12, 1.1, 5.24), Mats.toon(Color(0.25, 0.2, 0.15), 0.6))
	_box(Vector3(0.18, 0.08, 0.02), Vector3(0.28, 1.2, 5.24), Mats.glow(Color(1.0, 0.7, 0.3), 2.5))
	for i in 2:
		_cyl(0.035, 0.035, 0.04, Vector3(0.2 + i * 0.12, 0.98, 5.24), M["brass"], false, null, Vector3(PI / 2, 0, 0))
	_cyl(0.008, 0.008, 0.8, Vector3(0.35, 1.7, 5.5), M["metal"], false, null, Vector3(0, 0, -0.3))
	_light(Vector3(0.2, 1.3, 5.0), Color(1.0, 0.7, 0.35), 0.6, 2.5)
	# tableau d'affichage et dessins d'enfants
	_box(Vector3(1.8, 1.1, 0.04), Vector3(-3.5, 1.6, 5.73), Mats.toon(Color(0.55, 0.4, 0.25), 0.6))
	for i in 6:
		_box(Vector3(0.3, 0.38, 0.01), Vector3(-4.1 + (i % 3) * 0.6, 1.85 - (i / 3) * 0.5, 5.7), M["paper"], false, null, Vector3(0, 0, _rng.randf_range(-0.12, 0.12)))
	_frame(Vector3(3.5, 1.7, 5.72), Vector3(0, 0, -1), Vector2(1.2, 0.8), Color(0.3, 0.45, 0.55))
	_plant(Vector3(-6.3, 0, 4.3), true)
	_plant(Vector3(6.3, 0, 4.4))


# ---------------------------------------------------------------- dortoir

func _build_dortoir() -> void:
	var blankets := [Color(0.55, 0.2, 0.16), Color(0.2, 0.38, 0.45), Color(0.6, 0.48, 0.2), Color(0.35, 0.42, 0.28), Color(0.45, 0.28, 0.42), Color(0.5, 0.36, 0.25)]
	for i in 6:
		var x: float = [-5.5, -3.5, -1.5, 1.5, 3.5, 5.5][i]
		_box(Vector3(1.1, 0.42, 2.1), Vector3(x, 0.21, -16.5), M["wood_dark"], true)
		for px in [-0.52, 0.52]:
			_box(Vector3(0.08, 0.95, 0.08), Vector3(x + px, 0.47, -17.52), M["wood_dark"])
		_box(Vector3(1.1, 0.5, 0.06), Vector3(x, 0.7, -17.52), M["wood"])
		_box(Vector3(1.0, 0.14, 2.0), Vector3(x, 0.49, -16.5), M["cloth"])
		_box(Vector3(1.06, 0.12, 1.35), Vector3(x, 0.6, -16.1), Mats.toon(blankets[i], 0.45))
		_box(Vector3(1.06, 0.02, 0.18), Vector3(x, 0.67, -16.7), Mats.toon(blankets[i].lightened(0.3), 0.4))
		_box(Vector3(0.7, 0.16, 0.38), Vector3(x, 0.64, -17.15), M["paper"], false, null, Vector3(0.15, 0, 0))
		beds.append(Vector3(x, 0.0, -14.6))
	# tables de chevet entre les lits
	for x in [-4.5, -2.5, 2.5, 4.5]:
		_box(Vector3(0.5, 0.55, 0.45), Vector3(x, 0.275, -17.35), M["wood"])
		_cyl(0.04, 0.05, 0.12, Vector3(x, 0.61, -17.35), M["white"])
		_glow(0.025, Vector3(x, 0.71, -17.35), Color(1.0, 0.7, 0.3), 5.0)
		_books(Vector3(x - 0.15, 0.55, -17.25), 2, Vector3(1, 0, 0))
	_shelf_unit(Vector3(0, 0, -17.5), Vector3(1.6, 1.8, 0.4), 3, M["wood"])
	_books(Vector3(-0.7, 0.17, -17.5), 18, Vector3(1, 0, 0))
	_books(Vector3(-0.6, 0.72, -17.5), 10, Vector3(1, 0, 0))
	_box(Vector3(0.3, 0.3, 0.3), Vector3(0.4, 1.45, -17.5), M["copper"])
	# casiers à l'ouest
	for i in 6:
		var z: float = -14.0 + i * 1.0
		_box(Vector3(0.6, 1.9, 0.9), Vector3(-6.45, 0.95, z), M["metal"], true)
		_box(Vector3(0.02, 1.7, 0.02), Vector3(-6.14, 0.95, z), M["metal_dark"])
		for k in 4:
			_box(Vector3(0.02, 0.03, 0.4), Vector3(-6.14, 1.55 + k * 0.06, z + 0.2), M["metal_dark"])
		_box(Vector3(0.05, 0.25, 0.08), Vector3(-6.13, 1.0, z + 0.3), M["copper"])
		_box(Vector3(0.01, 0.1, 0.16), Vector3(-6.13, 1.75, z - 0.2), M["paper"])
		lockers.append(Vector3(-6.45, 0.0, z))
	# bureau pour écrire (write_letter)
	_box(Vector3(1.4, 0.06, 0.65), Vector3(-4.0, 0.76, -6.62), M["wood"], true)
	for lx in [-0.62, 0.62]:
		_box(Vector3(0.06, 0.73, 0.55), Vector3(-4.0 + lx, 0.37, -6.62), M["wood_dark"])
	_box(Vector3(0.3, 0.005, 0.22), Vector3(-4.0, 0.795, -6.75), M["paper"], false, null, Vector3(0, 0.1, 0))
	_box(Vector3(0.22, 0.04, 0.3), Vector3(-4.5, 0.81, -6.7), M["paper"])
	_cyl(0.03, 0.035, 0.06, Vector3(-3.55, 0.82, -6.7), M["black"])
	_cyl(0.04, 0.05, 0.14, Vector3(-3.4, 0.86, -6.5), M["white"])
	_glow(0.025, Vector3(-3.4, 0.96, -6.5), Color(1.0, 0.7, 0.3), 5.0)
	_chair(Vector3(-4.0, 0, -7.55), Vector3(-4.0, 0, -6.2), M["wood_dark"])
	_frame(Vector3(-4.0, 1.7, -6.27), Vector3(0, 0, -1), Vector2(0.5, 0.65), Color(0.7, 0.5, 0.35))
	_frame(Vector3(-3.2, 1.55, -6.27), Vector3(0, 0, -1), Vector2(0.35, 0.45), Color(0.4, 0.5, 0.6))
	# coin lecture (read_chair) : fauteuil, guéridon, lampe, bibliothèque
	var g := _group(Vector3(5.75, 0, -9.5), Vector3(4.0, 0, -9.5))
	var velvet := Mats.toon(Color(0.45, 0.16, 0.18), 0.4, OL)
	_box(Vector3(0.8, 0.4, 0.75), Vector3(0, 0.2, 0), velvet, false, g)
	_box(Vector3(0.7, 0.1, 0.65), Vector3(0, 0.45, 0.02), Mats.toon(Color(0.55, 0.22, 0.22), 0.4), false, g)
	_box(Vector3(0.8, 0.75, 0.18), Vector3(0, 0.75, -0.32), velvet, false, g)
	for sx in [-0.4, 0.4]:
		_box(Vector3(0.14, 0.32, 0.7), Vector3(sx, 0.56, 0), velvet, false, g)
	_cyl(0.25, 0.25, 0.04, Vector3(6.25, 0.6, -8.45), M["wood"])
	_cyl(0.04, 0.06, 0.58, Vector3(6.25, 0.3, -8.45), M["wood_dark"])
	_cyl(0.03, 0.03, 0.5, Vector3(6.3, 0.85, -8.4), M["brass"])
	_cyl(0.08, 0.16, 0.16, Vector3(6.3, 1.12, -8.4), Mats.toon(Color(0.85, 0.7, 0.45), 0.2))
	_glow(0.05, Vector3(6.3, 1.06, -8.4), Color(1.0, 0.75, 0.4), 5.0)
	_cyl(0.05, 0.05, 0.1, Vector3(6.15, 0.67, -8.55), M["ceramic"])
	var hb := _shelf_unit(Vector3(6.5, 0, -7.0), Vector3(0.4, 1.9, 1.2), 4, M["wood"])
	for h in hb:
		_books(Vector3(6.5, h, -7.45), 12, Vector3(0, 0, 1))
	# linge (fold_laundry) : table contre le mur est, piles, panier, corde à linge
	_box(Vector3(0.8, 0.06, 1.6), Vector3(5.95, 0.85, -12.2), M["wood_light"], true)
	for lz in [-0.72, 0.72]:
		_box(Vector3(0.7, 0.82, 0.06), Vector3(5.95, 0.41, -12.2 + lz), M["wood_dark"])
	for i in 3:
		for k in 3:
			_box(Vector3(0.36, 0.05, 0.3), Vector3(5.95, 0.9 + k * 0.055, -12.7 + i * 0.45), Mats.toon(blankets[(i + k) % 6].lightened(0.2), 0.3))
	_cyl(0.3, 0.24, 0.4, Vector3(5.8, 0.2, -13.4), M["wood_light"])
	_ball(0.25, Vector3(5.8, 0.38, -13.4), M["cloth"], Vector3(1, 0.5, 1))
	_cyl(0.01, 0.01, 12.0, Vector3(0, 2.7, -11.0), M["black"], false, null, Vector3(0, 0, PI / 2))
	for i in 7:
		var x: float = -5.0 + i * 1.6
		_box(Vector3(0.5, 0.6, 0.02), Vector3(x, 2.4, -11.0), Mats.toon(blankets[i % 6].lightened(0.15), 0.4), false, null, Vector3(0, 0, _rng.randf_range(-0.05, 0.05)))
	_rug(Vector3(0, 0, -11.5), Vector2(6.0, 4.0), Color(0.3, 0.2, 0.3), Color(0.55, 0.45, 0.25))
	_frame(Vector3(-6.73, 1.6, -8.0), Vector3(1, 0, 0), Vector2(0.9, 0.6), Color(0.35, 0.5, 0.42))
	_plant(Vector3(-6.2, 0, -7.0))
	_plant(Vector3(-6.2, 0, -17.2), true)


# ---------------------------------------------------------------- atelier

func _build_atelier() -> void:
	# pompe à air (pump_fix) contre le mur nord
	_box(Vector3(2.2, 1.6, 0.8), Vector3(12.0, 0.8, -5.35), M["metal"], true)
	_box(Vector3(2.0, 0.2, 0.84), Vector3(12.0, 1.4, -5.35), M["rust"])
	_cyl(0.55, 0.55, 0.12, Vector3(10.7, 1.0, -5.3), M["metal_dark"], false, null, Vector3(0, 0, PI / 2))
	_cyl(0.08, 0.08, 0.2, Vector3(10.62, 1.0, -5.3), M["brass"], false, null, Vector3(0, 0, PI / 2))
	for i in 3:
		_cyl(0.12, 0.12, 0.04, Vector3(11.4 + i * 0.5, 1.15, -4.93), M["brass"], false, null, Vector3(PI / 2, 0, 0))
		_cyl(0.09, 0.09, 0.045, Vector3(11.4 + i * 0.5, 1.15, -4.92), Mats.glow(Color(0.6, 1.0, 0.7), 0.8), false, null, Vector3(PI / 2, 0, 0))
	_box(Vector3(0.12, 0.12, 0.04), Vector3(13.0, 0.75, -4.93), Mats.glow(Color(1.0, 0.25, 0.15), 3.0))
	for x in [11.4, 12.6]:
		_cyl(0.14, 0.14, 2.6, Vector3(x, 2.9, -5.5), M["copper"])
	_cyl(0.18, 0.18, 12.0, Vector3(13.0, 3.3, -5.55), M["copper"], false, null, Vector3(0, 0, PI / 2))
	_cyl(0.12, 0.12, 12.0, Vector3(13.0, 3.0, -5.6), M["metal"], false, null, Vector3(0, 0, PI / 2))
	for x in [9.0, 15.0, 17.5]:
		_cyl(0.2, 0.2, 0.12, Vector3(x, 3.3, -5.55), M["metal_dark"], false, null, Vector3(0, 0, PI / 2))

	# chaudière (boiler_watch)
	_cyl(0.9, 0.95, 2.8, Vector3(16.6, 1.4, 4.4), M["copper"], true)
	for h in [0.4, 1.4, 2.4]:
		_cyl(0.97, 0.97, 0.08, Vector3(16.6, h, 4.4), M["metal_dark"])
	_cyl(0.3, 0.3, 1.6, Vector3(16.6, 3.4, 4.4), M["metal_dark"])
	_box(Vector3(0.5, 0.4, 0.1), Vector3(16.0, 0.65, 3.65), M["metal_dark"], false, null, Vector3(0, -0.6, 0))
	_box(Vector3(0.38, 0.28, 0.1), Vector3(15.97, 0.65, 3.62), Mats.glow(Color(1.0, 0.45, 0.1), 5.0), false, null, Vector3(0, -0.6, 0))
	_cyl(0.16, 0.16, 0.05, Vector3(15.95, 1.8, 3.75), M["brass"], false, null, Vector3(PI / 2, -0.6, 0))
	_cyl(0.13, 0.13, 0.055, Vector3(15.94, 1.8, 3.74), M["paper"], false, null, Vector3(PI / 2, -0.6, 0))
	_box(Vector3(0.02, 0.1, 0.01), Vector3(15.92, 1.83, 3.71), M["black"], false, null, Vector3(0, -0.6, 0.6))
	for i in 7:
		_ball(0.22, Vector3(17.9 + _rng.randf_range(-0.4, 0.4), 0.12, 5.3 + _rng.randf_range(-0.3, 0.2)), Mats.toon(Color(0.1, 0.1, 0.1), 0.6), Vector3(1, 0.6, 1))
	_box(Vector3(0.3, 0.02, 2.0), Vector3(15.0, 0.01, 4.4), M["hazard"])
	_box(Vector3(2.0, 0.02, 0.3), Vector3(16.6, 0.01, 2.9), M["hazard"])

	# établi (weld, bench_repair) contre le mur est
	_box(Vector3(1.2, 0.1, 5.0), Vector3(18.0, 0.95, 0.0), M["wood"], true)
	for lz in [-2.3, 0.0, 2.3]:
		_box(Vector3(1.0, 0.9, 0.1), Vector3(18.0, 0.45, lz), M["wood_dark"])
	_box(Vector3(1.0, 0.04, 4.6), Vector3(18.0, 0.3, 0.0), M["wood_dark"])
	for i in 4:
		_box(Vector3(0.4, 0.25, 0.3), Vector3(18.1, 0.45, -1.8 + i * 1.2), M["metal"])
	# poste de soudure : plaque, masque, bouteilles de gaz
	_box(Vector3(0.6, 0.02, 0.5), Vector3(17.75, 1.01, 1.6), M["metal_dark"])
	_box(Vector3(0.12, 0.04, 0.3), Vector3(17.75, 1.04, 1.6), Mats.glow(Color(1.0, 0.6, 0.2), 1.5))
	_box(Vector3(0.25, 0.3, 0.12), Vector3(18.3, 1.15, 2.1), M["metal_dark"])
	for z in [2.75, 3.05]:
		_cyl(0.13, 0.13, 1.1, Vector3(18.5, 0.55, z), Mats.toon(Color(0.25, 0.4, 0.3), 0.2, OL), true)
		_cyl(0.04, 0.04, 0.12, Vector3(18.5, 1.15, z), M["brass"])
	# radio en réparation
	_box(Vector3(0.45, 0.32, 0.55), Vector3(17.85, 1.16, -1.3), M["wood_dark"])
	_box(Vector3(0.02, 0.22, 0.4), Vector3(17.62, 1.16, -1.3), Mats.toon(Color(0.2, 0.35, 0.25), 0.4))
	for i in 5:
		_cyl(0.025, 0.025, 0.06, Vector3(17.6, 1.06 + (i % 2) * 0.1, -1.45 + i * 0.07), Mats.toon(Color(0.7, 0.55, 0.3), 0.2), false, null, Vector3(0, 0, PI / 2))
	_box(Vector3(0.18, 0.15, 0.25), Vector3(17.7, 1.08, -0.6), M["metal"])
	_box(Vector3(0.14, 0.06, 0.18), Vector3(17.7, 1.19, -0.6), M["metal_dark"])
	for i in 8:
		_cyl(0.015, 0.015, 0.03, Vector3(17.6 + _rng.randf() * 0.5, 1.02, -2.2 + _rng.randf() * 1.0), M["brass"])
	# lampe articulée
	_cyl(0.015, 0.015, 0.9, Vector3(18.4, 1.45, 0.3), M["metal_dark"], false, null, Vector3(0.3, 0, 0))
	_cyl(0.06, 0.15, 0.15, Vector3(18.2, 1.9, 0.5), M["metal"], false, null, Vector3(0, 0, -0.8))
	_glow(0.05, Vector3(18.15, 1.85, 0.5), Color(1.0, 0.92, 0.75), 5.0)
	_light(Vector3(17.8, 1.6, 0.3), Color(1.0, 0.9, 0.75), 1.4, 4.5)
	# panneau à outils au-dessus de l'établi
	_box(Vector3(0.04, 1.2, 3.4), Vector3(18.73, 1.9, 0.0), Mats.toon(Color(0.45, 0.35, 0.25), 0.6))
	for i in 9:
		var z: float = -1.5 + i * 0.38
		var tool_m: Material = M["metal"] if i % 3 != 1 else M["wood_light"]
		_box(Vector3(0.03, 0.35 + (i % 3) * 0.1, 0.05), Vector3(18.69, 1.9, z), tool_m, false, null, Vector3(0.0, 0, 0.0) + Vector3((i % 2) * 0.3, 0, 0))
		if i % 3 == 0:
			_cyl(0.05, 0.05, 0.03, Vector3(18.69, 2.1, z), M["metal"], false, null, Vector3(0, 0, PI / 2))

	# rangement des outils (tools_store) contre le mur sud
	var hs := _shelf_unit(Vector3(10.5, 0, 5.45), Vector3(2.0, 2.0, 0.5), 3, M["metal_dark"])
	for h in hs:
		for i in 4:
			var c := Color(0.62, 0.22, 0.15) if i % 2 == 0 else Color(0.55, 0.55, 0.58)
			_box(Vector3(0.38, 0.2, 0.3), Vector3(9.8 + i * 0.47, h + 0.1, 5.45), Mats.toon(c, 0.2))
	_box(Vector3(0.6, 0.3, 0.3), Vector3(11.8, 0.15, 5.0), Mats.toon(Color(0.7, 0.24, 0.16), 0.2, OL))
	_box(Vector3(0.62, 0.04, 0.05), Vector3(11.8, 0.33, 5.0), M["metal"])

	# fûts d'huile et tuyaux en vrac
	for p in [Vector3(8.0, 0, -5.1), Vector3(8.75, 0, -5.25), Vector3(8.3, 0, 5.1)]:
		_cyl(0.32, 0.32, 0.95, p + Vector3(0, 0.475, 0), Mats.toon(Color(0.32, 0.4, 0.45), 0.3, OL), true)
		_cyl(0.33, 0.33, 0.04, p + Vector3(0, 0.3, 0), M["metal_dark"])
		_cyl(0.33, 0.33, 0.04, p + Vector3(0, 0.7, 0), M["metal_dark"])
	for i in 3:
		_cyl(0.07, 0.07, 1.8, Vector3(14.0, 0.07 + i * 0.13, 5.5 - i * 0.05), M["rust"], false, null, Vector3(0, 0, PI / 2))
	# palan suspendu au plafond
	_box(Vector3(0.2, 0.15, 4.0), Vector3(13.5, 3.85, 0.0), M["metal_dark"])
	_cyl(0.015, 0.015, 1.6, Vector3(13.5, 3.0, 1.0), M["metal"])
	_box(Vector3(0.12, 0.18, 0.08), Vector3(13.5, 2.15, 1.0), M["hazard"])
	_frame(Vector3(9.5, 1.7, -5.73), Vector3(0, 0, 1), Vector2(1.0, 0.7), Color(0.75, 0.62, 0.3), M["metal_dark"])
	_plant(Vector3(7.8, 0, 3.6))


# ---------------------------------------------------------------- infirmerie

func _build_infirmerie() -> void:
	var white: Material = M["white"]
	var sheet := Mats.toon(Color(0.88, 0.9, 0.86), 0.2)
	# trois lits de soin à l'ouest, paravents entre eux
	for z in [-2.8, 0.2, 3.2]:
		_box(Vector3(1.0, 0.1, 2.0), Vector3(-17.9, 0.55, z), M["metal"], true)
		for lx in [-0.45, 0.45]:
			for lz in [-0.92, 0.92]:
				_cyl(0.025, 0.025, 0.55, Vector3(-17.9 + lx, 0.27, z + lz), M["metal"])
		_box(Vector3(0.95, 0.12, 1.95), Vector3(-17.9, 0.66, z), sheet)
		_box(Vector3(0.6, 0.12, 0.35), Vector3(-17.9, 0.78, z - 0.75), M["paper"])
		_box(Vector3(1.0, 0.5, 0.05), Vector3(-17.9, 0.85, z - 1.0), M["metal"])
		# perfusion
		_cyl(0.015, 0.015, 1.8, Vector3(-18.6, 0.9, z - 0.6), M["metal"])
		_box(Vector3(0.12, 0.18, 0.05), Vector3(-18.6, 1.7, z - 0.6), Mats.glow(Color(0.6, 1.0, 0.75), 0.8))
		_cyl(0.18, 0.2, 0.03, Vector3(-18.6, 0.02, z - 0.6), M["metal"])
	for z in [-1.3, 1.7]:
		_box(Vector3(1.6, 1.5, 0.03), Vector3(-17.9, 1.05, z), Mats.toon(Color(0.72, 0.82, 0.75), 0.3))
		for lx in [-0.8, 0.8]:
			_cyl(0.015, 0.015, 1.8, Vector3(-17.9 + lx, 0.9, z), M["metal"])
	# malades alités (tend_patient, tend_patient2 / visit_mother : la mère d'Elio)
	_patient(Vector3(-17.9, 0, -2.8), Color(0.85, 0.66, 0.55), Color(0.25, 0.18, 0.12), Color(0.55, 0.62, 0.7))
	_patient(Vector3(-17.9, 0, 3.2), Color(0.9, 0.74, 0.62), Color(0.72, 0.7, 0.66), Color(0.62, 0.45, 0.5))
	_stool(Vector3(-16.75, 0, 3.2), M["metal"])

	# armoire à pharmacie (sort_meds)
	_box(Vector3(3.0, 2.0, 0.55), Vector3(-12.5, 1.0, -5.45), Mats.toon(Color(0.3, 0.45, 0.42), 0.2, OL), true)
	_box(Vector3(2.8, 1.2, 0.02), Vector3(-12.5, 1.35, -5.16), M["glass"])
	for row in 3:
		_box(Vector3(2.8, 0.03, 0.4), Vector3(-12.5, 0.85 + row * 0.38, -5.3), white)
		for i in 12:
			var cols := [Color(0.4, 0.9, 0.5), Color(0.9, 0.55, 0.25), Color(0.5, 0.65, 0.95), Color(0.9, 0.85, 0.6)]
			var h := 0.1 + _rng.randf() * 0.12
			_cyl(0.04, 0.045, h, Vector3(-13.75 + i * 0.22, 0.87 + row * 0.38 + h * 0.5, -5.25), Mats.glow(cols[(i + row) % 4], 0.35))
	for i in 3:
		_box(Vector3(0.9, 0.5, 0.02), Vector3(-13.45 + i * 0.95, 0.38, -5.16), white)
		_box(Vector3(0.12, 0.03, 0.03), Vector3(-13.45 + i * 0.95, 0.5, -5.14), M["brass"])
	_box(Vector3(0.5, 0.5, 0.02), Vector3(-12.5, 2.45, -5.73), Mats.glow(Color(0.85, 0.15, 0.12), 1.5))
	_box(Vector3(0.18, 0.4, 0.03), Vector3(-12.5, 2.45, -5.71), white)
	_box(Vector3(0.4, 0.14, 0.03), Vector3(-12.5, 2.45, -5.71), white)

	# paillasse à remèdes (brew_remedy)
	_box(Vector3(2.2, 0.1, 0.8), Vector3(-14.5, 0.9, 5.3), white, true)
	_box(Vector3(2.1, 0.85, 0.7), Vector3(-14.5, 0.43, 5.32), Mats.toon(Color(0.4, 0.5, 0.48), 0.2))
	_cyl(0.07, 0.09, 0.08, Vector3(-14.5, 0.99, 5.25), M["metal_dark"])
	_glow(0.04, Vector3(-14.5, 1.05, 5.25), Color(0.4, 0.7, 1.0), 4.0)
	_ball(0.11, Vector3(-14.5, 1.18, 5.25), Mats.glow(Color(0.4, 1.0, 0.55), 1.0))
	_cyl(0.025, 0.025, 0.2, Vector3(-14.5, 1.35, 5.25), M["glass"])
	for i in 6:
		var cl: Color = [Color(0.9, 0.4, 0.3), Color(0.4, 0.8, 0.9), Color(0.85, 0.8, 0.4)][i % 3]
		_cyl(0.035, 0.05, 0.14, Vector3(-15.4 + i * 0.13, 1.02, 5.45), Mats.glow(cl, 0.5))
	_box(Vector3(0.5, 0.05, 0.3), Vector3(-13.7, 0.97, 5.35), M["wood_light"])
	for i in 4:
		_ball(0.05, Vector3(-13.85 + i * 0.1, 1.02, 5.35), M["leaf"])
	for i in 5:
		_box(Vector3(0.05, 0.3, 0.02), Vector3(-15.3 + i * 0.4, 1.9, 5.72), M["leaf"], false, null, Vector3(0, 0, 0.1))
	_box(Vector3(2.0, 0.02, 0.02), Vector3(-14.5, 2.08, 5.72), M["black"])

	# bureau des dossiers (write_records)
	_box(Vector3(1.4, 0.06, 0.7), Vector3(-10.0, 0.76, 5.15), M["wood"], true)
	for lx in [-0.62, 0.62]:
		_box(Vector3(0.06, 0.73, 0.6), Vector3(-10.0 + lx, 0.37, 5.15), M["wood_dark"])
	for i in 4:
		_box(Vector3(0.26, 0.04, 0.34), Vector3(-10.45 + i * 0.05, 0.81 + i * 0.04, 5.3), Mats.toon(Color(0.75, 0.62, 0.42) if i % 2 == 0 else Color(0.85, 0.82, 0.72), 0.2))
	_box(Vector3(0.3, 0.005, 0.22), Vector3(-9.95, 0.795, 5.0), M["paper"])
	_cyl(0.03, 0.03, 0.3, Vector3(-9.5, 0.94, 5.3), M["brass"])
	_box(Vector3(0.3, 0.1, 0.12), Vector3(-9.5, 1.1, 5.25), Mats.toon(Color(0.15, 0.4, 0.25), 0.1))
	_glow(0.03, Vector3(-9.5, 1.04, 5.22), Color(1.0, 0.9, 0.6), 4.0)
	_light(Vector3(-9.6, 1.1, 5.0), Color(1.0, 0.88, 0.6), 0.8, 3.0)
	_chair(Vector3(-10.0, 0, 4.1), Vector3(-10.0, 0, 5.4), M["wood_dark"])
	_box(Vector3(0.6, 1.3, 0.55), Vector3(-8.1, 0.65, 5.4), M["metal"], true)
	for k in 3:
		_box(Vector3(0.5, 0.36, 0.02), Vector3(-8.1, 0.25 + k * 0.42, 5.12), M["metal_dark"])
		_box(Vector3(0.12, 0.03, 0.03), Vector3(-8.1, 0.36 + k * 0.42, 5.1), M["brass"])

	# lavabo (wash_hands), miroir, serviette
	_box(Vector3(0.6, 0.15, 0.45), Vector3(-9.0, 0.88, -5.5), M["ceramic"])
	_box(Vector3(0.48, 0.08, 0.32), Vector3(-9.0, 0.93, -5.48), Mats.toon(Color(0.25, 0.35, 0.4), 0.0))
	_cyl(0.07, 0.1, 0.8, Vector3(-9.0, 0.4, -5.55), M["ceramic"])
	_cyl(0.02, 0.02, 0.25, Vector3(-9.0, 1.08, -5.68), M["brass"])
	_box(Vector3(0.5, 0.6, 0.02), Vector3(-9.0, 1.6, -5.73), M["glass"])
	_box(Vector3(0.56, 0.66, 0.015), Vector3(-9.0, 1.6, -5.74), M["metal"])
	_box(Vector3(0.3, 0.45, 0.03), Vector3(-8.4, 1.15, -5.72), Mats.toon(Color(0.55, 0.75, 0.7), 0.4))
	_box(Vector3(0.2, 0.06, 0.12), Vector3(-9.35, 0.97, -5.45), Mats.toon(Color(0.9, 0.85, 0.6), 0.3))
	_frame(Vector3(-17.6, 1.6, -5.73), Vector3(0, 0, 1), Vector2(1.0, 0.7), Color(0.5, 0.6, 0.55))
	_plant(Vector3(-7.8, 0, -4.8))
	_plant(Vector3(-10.9, 0, 5.4), true)


func _patient(pos: Vector3, skin: Color, hair: Color, blanket: Color) -> void:
	_ball(0.15, pos + Vector3(0, 0.88, -0.72), Mats.toon(skin, 0.06, 0.016), Vector3(1, 1, 1.05))
	_ball(0.16, pos + Vector3(0, 0.92, -0.78), Mats.toon(hair, 0.35, 0.016), Vector3(1.05, 0.9, 0.9))
	_box(Vector3(0.9, 0.2, 1.45), pos + Vector3(0, 0.8, 0.2), Mats.toon(blanket, 0.4, OL))
	_ball(0.2, pos + Vector3(0, 0.88, -0.2), Mats.toon(blanket, 0.4), Vector3(1.8, 0.6, 1.2))


# ---------------------------------------------------------------- caisses, lumières, sons

func _build_crates() -> void:
	crates["bleu"] = Vector3(-6.2, 0.0, -3.6)
	crates["rouge"] = Vector3(17.8, 0.0, -4.7)
	crates["jaune"] = Vector3(-15.8, 0.0, -5.0)
	var crate_mat := Mats.toon(Color(0.45, 0.32, 0.18), 0.35, OL)
	for team in crates:
		var c: Vector3 = crates[team]
		_box(Vector3(1.0, 1.0, 1.0), c + Vector3(0, 0.5, 0), crate_mat, true)
		_box(Vector3(1.04, 0.1, 1.04), c + Vector3(0, 0.75, 0), M["wood_dark"])
		_box(Vector3(1.04, 0.1, 1.04), c + Vector3(0, 0.25, 0), M["wood_dark"])
		_box(Vector3(0.3, 0.3, 1.02), c + Vector3(0, 0.5, 0), Mats.toon(GameData.TEAMS[team]["color"], 0.3))


func _build_lights() -> void:
	var c_ref: Color = GameData.ROOMS["refectoire"]["light"]
	_lamp_hanging(Vector3(0, 3.3, -1.0), c_ref, 2.0, 10.0)
	_lamp_hanging(Vector3(-4.2, 2.6, 3.0), c_ref, 1.2, 5.0)
	_lamp_hanging(Vector3(4.2, 2.6, 3.0), c_ref, 1.2, 5.0)
	_light(Vector3(-4.5, 2.1, -4.8), Color(1.0, 0.6, 0.3), 1.3, 5.0)
	_light(Vector3(3.5, 2.1, -4.6), Color(1.0, 0.75, 0.45), 0.9, 4.5)

	var c_dor: Color = GameData.ROOMS["dortoir"]["light"]
	_lamp_hanging(Vector3(0, 3.2, -11.5), c_dor, 1.5, 10.0)
	_light(Vector3(-3.6, 1.2, -6.8), Color(1.0, 0.7, 0.35), 0.8, 3.5)
	_light(Vector3(6.1, 1.3, -8.6), Color(1.0, 0.75, 0.4), 1.0, 4.0)
	_light(Vector3(0, 1.0, -16.0), Color(1.0, 0.65, 0.35), 0.7, 5.0)

	var c_at: Color = GameData.ROOMS["atelier"]["light"]
	_lamp_hanging(Vector3(12.0, 3.3, -1.5), c_at, 2.0, 10.0)
	_light(Vector3(16.0, 0.8, 3.4), Color(1.0, 0.4, 0.12), 2.0, 5.0)
	_light(Vector3(12.0, 1.4, -4.6), Color(0.6, 1.0, 0.7), 0.5, 2.5)

	var c_inf: Color = GameData.ROOMS["infirmerie"]["light"]
	_lamp_hanging(Vector3(-13.0, 3.3, 0.0), c_inf.lerp(Color.WHITE, 0.35), 2.0, 10.0)
	for z in [-2.8, 0.2, 3.2]:
		_light(Vector3(-16.9, 1.0, z), Color(0.3, 1.0, 0.6), 0.9, 3.0)
	_light(Vector3(-12.5, 1.4, -4.6), Color(0.6, 1.0, 0.8), 0.6, 3.0)
	_light(Vector3(-14.5, 1.3, 4.8), Color(0.4, 1.0, 0.6), 0.8, 3.0)


func _build_ambience() -> void:
	for id in GameData.ROOMS:
		var p := AudioStreamPlayer.new()
		p.stream = Sfx.stream(GameData.ROOMS[id]["ambience"])
		p.bus = "Ambience"
		p.volume_db = -40.0
		add_child(p)
		if p.stream:
			p.play()
		ambience[id] = p
