extends Node3D
## Personnage stylisé paramétrable : proportions exagérées, visage (yeux, sourcils, nez, bouche),
## coiffure, accessoires, démarche et gestes de travail propres à chacun.
## Le modèle regarde vers +Z. Placeholder procédural : un vrai modèle 3D pourra le remplacer.

signal step

const Mats := preload("res://scripts/materials.gd")
const INK := 0.016

var look: Dictionary
var gait := {"speed": 1.0, "stride": 0.6, "bounce": 0.05, "sway": 0.03, "hunch": 0.0}
var idle := "breathe"

var walking := false
var speed_factor := 1.0
var task_anim := ""      # geste de travail en cours, "" si aucun
var sitting := false

var _phase := 0.0
var _t := 0.0
var _yaw := 0.0
var _body: Node3D
var _hips: Node3D
var _chest: Node3D
var _head: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _hand_r: Node3D
var _props := {}
var _prop := ""
var _leg_len := 0.8
var _last_sin := 0.0


# ================================================================ construction

func _mesh(m: Mesh, mat: Material, pos: Vector3, parent: Node3D, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


func _sphere(r: float, hemi: bool = false) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * (1.0 if hemi else 2.0)
	s.is_hemisphere = hemi
	s.radial_segments = 16
	s.rings = 8
	return s


func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = maxf(h, r * 2.0 + 0.01)
	return c


func _cyl(top: float, bottom: float, h: float, seg: int = 14) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = seg
	return c


func _boxm(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _torus(inner: float, outer: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	return t


func build_look(l: Dictionary) -> void:
	look = l
	gait = l.get("gait", gait)
	idle = l.get("idle", "breathe")
	var h: float = l.get("height", 1.0)
	var bulk: float = l.get("bulk", 1.0)
	var head_s: float = l.get("head", 1.0)
	var legs_s: float = l.get("legs", 1.0)
	var shoulders_s: float = l.get("shoulders", 1.0)
	var skin: Color = l["skin"]
	var coat: Color = l["coat"]
	var pants: Color = l["pants"]
	var accent: Color = l["accent"]
	var hair_c: Color = l["hair_color"]

	var m_skin := Mats.toon(skin, 0.06, INK)
	var m_coat := Mats.toon(coat, 0.2, INK)
	var m_pants := Mats.toon(pants, 0.2, INK)
	var m_shoe := Mats.toon(pants.darkened(0.6), 0.1, INK)
	var m_accent := Mats.toon(accent, 0.15, INK)
	var m_hair := Mats.toon(hair_c, 0.35, INK)

	_leg_len = 0.8 * h * legs_s
	var torso := 0.6 * h
	var head_r := 0.165 * head_s
	var hip_w := 0.1 * bulk
	var torso_r := 0.19 * bulk
	var sh_w := 0.21 * shoulders_s * maxf(bulk, 0.85)
	var arm_len := 0.6 * h * (0.85 + 0.15 * legs_s)
	var arm_r := 0.06 * maxf(bulk, 0.8) * (1.15 if shoulders_s > 1.2 else 1.0)

	_body = Node3D.new()
	add_child(_body)
	_hips = Node3D.new()
	_hips.position = Vector3(0, _leg_len, 0)
	_body.add_child(_hips)

	# jambes et chaussures
	for side in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(side * hip_w, _leg_len, 0)
		_body.add_child(pivot)
		var leg_r := 0.075 * maxf(bulk * 0.9, 0.7)
		_mesh(_capsule(leg_r, _leg_len), m_pants, Vector3(0, -_leg_len * 0.5, 0), pivot)
		_mesh(_boxm(Vector3(leg_r * 2.2, 0.09, 0.26 * maxf(h, 0.9))), m_shoe, Vector3(0, -_leg_len + 0.03, 0.05), pivot)
		if side < 0:
			_leg_l = pivot
		else:
			_leg_r = pivot

	# torse : bassin + poitrine, la corpulence élargit tout
	_chest = Node3D.new()
	_chest.position = Vector3(0, 0, 0)
	_hips.add_child(_chest)
	_mesh(_cyl(torso_r * 0.95, torso_r * 1.05, torso * 0.45), m_pants, Vector3(0, torso * 0.12, 0), _chest, Vector3.ZERO, Vector3(1, 1, 0.8))
	_mesh(_capsule(torso_r * 1.1, torso * 0.8), m_coat, Vector3(0, torso * 0.55, 0), _chest, Vector3.ZERO, Vector3(maxf(sh_w / torso_r, 1.0) * 0.95, 1, 0.78))
	# épaules arrondies
	for side in [-1.0, 1.0]:
		_mesh(_sphere(arm_r * 1.5), m_coat, Vector3(side * sh_w, torso * 0.9, 0), _chest)

	# bras et main droite (qui tient les objets)
	for side in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(side * (sh_w + arm_r * 0.6), torso * 0.92, 0)
		_chest.add_child(pivot)
		_mesh(_capsule(arm_r, arm_len), m_coat, Vector3(0, -arm_len * 0.5, 0), pivot)
		_mesh(_sphere(arm_r * 1.25), m_skin, Vector3(0, -arm_len, 0), pivot)
		if side < 0:
			_arm_l = pivot
		else:
			_arm_r = pivot
			_hand_r = Node3D.new()
			_hand_r.position = Vector3(0, -arm_len, 0.02)
			pivot.add_child(_hand_r)

	# cou et tête
	_mesh(_cyl(head_r * 0.42, head_r * 0.5, 0.12), m_skin, Vector3(0, torso + 0.04, 0), _chest)
	_head = Node3D.new()
	_head.position = Vector3(0, torso + 0.08 + head_r * 0.95, 0)
	_chest.add_child(_head)
	_mesh(_sphere(head_r), m_skin, Vector3.ZERO, _head, Vector3.ZERO, Vector3(1.0, 1.08, 1.0))
	_build_face(head_r, l, m_skin, m_hair)
	_build_hair(head_r, l.get("hair", "buzz"), m_hair, m_accent)
	for acc in l.get("accessories", []):
		_build_accessory(acc, head_r, torso, torso_r, sh_w, m_coat, m_accent, m_pants)


func _build_face(r: float, l: Dictionary, m_skin: Material, m_hair: Material) -> void:
	var eye_s: float = l.get("eye_size", 1.0)
	var white := Mats.toon(Color(0.97, 0.95, 0.92), 0.0)
	var iris := Mats.toon(l.get("eyes", Color(0.3, 0.2, 0.1)), 0.0)
	var pupil := Mats.toon(Color(0.03, 0.03, 0.04), 0.0)
	var dark_skin := Mats.toon((l["skin"] as Color).darkened(0.18), 0.05)
	# yeux
	for side in [-1.0, 1.0]:
		var e := Vector3(side * r * 0.36, r * 0.1, r * 0.84)
		_mesh(_sphere(r * 0.2 * eye_s), white, e, _head, Vector3.ZERO, Vector3(1.0, 1.15, 0.55))
		_mesh(_sphere(r * 0.12 * eye_s), iris, e + Vector3(0, -r * 0.01, r * 0.08), _head, Vector3.ZERO, Vector3(1, 1, 0.5))
		_mesh(_sphere(r * 0.06 * eye_s), pupil, e + Vector3(0, -r * 0.01, r * 0.12), _head, Vector3.ZERO, Vector3(1, 1, 0.5))
	# sourcils : plus épais = plus froncés
	var brows: float = l.get("brows", 1.0)
	for side in [-1.0, 1.0]:
		_mesh(_boxm(Vector3(r * 0.42, r * 0.07 * brows, r * 0.1)), m_hair, Vector3(side * r * 0.36, r * 0.4, r * 0.88), _head,
			Vector3(0, 0, side * (0.08 + 0.1 * (brows - 1.0))))
	# nez
	var nose: float = l.get("nose", 1.0)
	_mesh(_sphere(r * 0.13), dark_skin, Vector3(0, -r * 0.08, r * 1.0), _head, Vector3(0.3, 0, 0), Vector3(0.85 * nose, 1.2 * nose, 1.1 * nose))
	# bouche
	var lips := Mats.toon((l["skin"] as Color).darkened(0.45).lerp(Color(0.55, 0.2, 0.18), 0.4), 0.0)
	_mesh(_boxm(Vector3(r * 0.36, r * 0.05, r * 0.06)), lips, Vector3(0, -r * 0.46, r * 0.86), _head)
	# oreilles
	for side in [-1.0, 1.0]:
		_mesh(_sphere(r * 0.2), m_skin, Vector3(side * r * 0.97, 0, -r * 0.05), _head, Vector3.ZERO, Vector3(0.45, 1.0, 0.8))
	match l.get("beard", ""):
		"full":
			_mesh(_sphere(r * 0.82), m_hair, Vector3(0, -r * 0.5, r * 0.32), _head, Vector3.ZERO, Vector3(1.05, 0.95, 0.85))
			_mesh(_boxm(Vector3(r * 0.32, r * 0.05, r * 0.06)), lips, Vector3(0, -r * 0.4, r * 1.06), _head)
		"stubble":
			_mesh(_sphere(r * 1.0, true), Mats.toon((l["skin"] as Color).darkened(0.3), 0.6), Vector3(0, -r * 0.12, r * 0.04), _head, Vector3(PI, 0, 0), Vector3(1.02, 0.9, 1.02))
		"mustache":
			_mesh(_boxm(Vector3(r * 0.55, r * 0.11, r * 0.12)), m_hair, Vector3(0, -r * 0.3, r * 0.95), _head)
	match l.get("glasses", ""):
		"round":
			var frame := Mats.toon(Color(0.15, 0.12, 0.1), 0.0)
			for side in [-1.0, 1.0]:
				_mesh(_torus(r * 0.2, r * 0.26), frame, Vector3(side * r * 0.36, r * 0.1, r * 0.98), _head, Vector3(PI / 2, 0, 0))
			_mesh(_boxm(Vector3(r * 0.22, r * 0.04, r * 0.04)), frame, Vector3(0, r * 0.14, r * 1.0), _head)


func _build_hair(r: float, style: String, m_hair: Material, m_accent: Material) -> void:
	match style:
		"bald":
			pass
		"bald_sides":
			for side in [-1.0, 1.0]:
				_mesh(_sphere(r * 0.45), m_hair, Vector3(side * r * 0.82, r * 0.05, -r * 0.25), _head, Vector3.ZERO, Vector3(0.5, 0.9, 1.1))
			_mesh(_sphere(r * 0.6), m_hair, Vector3(0, -r * 0.05, -r * 0.65), _head, Vector3.ZERO, Vector3(1.3, 0.8, 0.6))
		"buzz":
			_mesh(_sphere(r * 1.04, true), m_hair, Vector3(0, r * 0.08, -r * 0.03), _head)
		"spiky":
			_mesh(_sphere(r * 1.05, true), m_hair, Vector3(0, r * 0.1, -r * 0.04), _head)
			for i in 7:
				var a := -0.9 + i * 0.3
				var spike := PrismMesh.new()
				spike.size = Vector3(r * 0.45, r * 0.9, r * 0.45)
				_mesh(spike, m_hair, Vector3(sin(a) * r * 0.6, r * 0.95, -r * 0.1 + cos(a * 2.0) * r * 0.15), _head, Vector3(-0.5, 0, a * 0.6))
		"bun":
			_mesh(_sphere(r * 1.06, true), m_hair, Vector3(0, r * 0.08, -r * 0.04), _head)
			_mesh(_sphere(r * 0.48), m_hair, Vector3(0, r * 1.05, -r * 0.35), _head)
		"cap":
			_mesh(_sphere(r * 1.08, true), m_accent, Vector3(0, r * 0.2, 0), _head, Vector3.ZERO, Vector3(1, 0.8, 1))
			_mesh(_boxm(Vector3(r * 1.5, r * 0.08, r * 0.9)), m_accent, Vector3(0, r * 0.28, r * 0.95), _head, Vector3(0.15, 0, 0))
			_mesh(_sphere(r * 0.5), m_hair, Vector3(0, -r * 0.1, -r * 0.7), _head, Vector3.ZERO, Vector3(1.6, 0.8, 0.5))
		"braid":
			_mesh(_sphere(r * 1.07, true), m_hair, Vector3(0, r * 0.06, -r * 0.05), _head, Vector3(-0.2, 0, 0))
			for i in 5:
				_mesh(_sphere(r * (0.3 - i * 0.03)), m_hair, Vector3(0, -r * 0.2 - i * r * 0.42, -r * 1.0 - i * r * 0.08), _head)
		"bob":
			_mesh(_sphere(r * 1.13, true), m_hair, Vector3(0, r * 0.05, -r * 0.04), _head, Vector3(-0.15, 0, 0))
			for side in [-1.0, 1.0]:
				_mesh(_boxm(Vector3(r * 0.32, r * 1.15, r * 1.2)), m_hair, Vector3(side * r * 0.92, -r * 0.25, -r * 0.08), _head)
			_mesh(_boxm(Vector3(r * 1.6, r * 0.32, r * 0.3)), m_hair, Vector3(r * 0.15, r * 0.62, r * 0.82), _head, Vector3(0.3, 0, -0.25))
			# mèche colorée, signature de Lina
			_mesh(_boxm(Vector3(r * 0.22, r * 1.0, r * 0.2)), m_accent, Vector3(-r * 0.7, -r * 0.05, r * 0.72), _head, Vector3(0, 0, 0.1))
		_:
			_mesh(_sphere(r * 1.05, true), m_hair, Vector3(0, r * 0.08, -r * 0.03), _head)


func _build_accessory(acc: String, r: float, torso: float, torso_r: float, sh_w: float, m_coat: Material, m_accent: Material, m_pants: Material) -> void:
	var leather := Mats.toon(Color(0.35, 0.22, 0.13), 0.25, INK)
	var metal := Mats.toon(Color(0.7, 0.72, 0.75), 0.05, INK)
	match acc:
		"goggles_head":
			_mesh(_torus(r * 1.0, r * 1.1), leather, Vector3(0, r * 0.45, 0), _head, Vector3(0.25, 0, 0))
			for side in [-1.0, 1.0]:
				_mesh(_cyl(r * 0.25, r * 0.25, r * 0.22), metal, Vector3(side * r * 0.35, r * 0.72, r * 0.82), _head, Vector3(PI / 2 - 0.4, 0, 0))
				_mesh(_cyl(r * 0.2, r * 0.2, r * 0.05), Mats.glow(Color(0.3, 0.8, 0.75), 0.6), Vector3(side * r * 0.35, r * 0.78, r * 0.92), _head, Vector3(PI / 2 - 0.4, 0, 0))
		"goggles_eyes":
			_mesh(_torus(r * 1.0, r * 1.08), leather, Vector3(0, r * 0.12, 0), _head)
			for side in [-1.0, 1.0]:
				_mesh(_cyl(r * 0.3, r * 0.3, r * 0.25), metal, Vector3(side * r * 0.37, r * 0.12, r * 0.92), _head, Vector3(PI / 2, 0, 0))
				_mesh(_cyl(r * 0.24, r * 0.24, r * 0.05), Mats.glow(Color(0.35, 0.9, 0.8), 0.5), Vector3(side * r * 0.37, r * 0.12, r * 1.05), _head, Vector3(PI / 2, 0, 0))
		"apron", "apron_white":
			var m := leather if acc == "apron" else Mats.toon(Color(0.93, 0.9, 0.82), 0.2, INK)
			_mesh(_boxm(Vector3(torso_r * 1.9, torso * 1.25, 0.04)), m, Vector3(0, torso * 0.3, torso_r * 0.9), _chest, Vector3(-0.08, 0, 0))
		"toolbelt":
			_mesh(_torus(torso_r * 0.95, torso_r * 1.12), leather, Vector3(0, torso * 0.1, 0), _chest)
			for side in [-1.0, 1.0]:
				_mesh(_boxm(Vector3(0.08, 0.14, 0.1)), leather, Vector3(side * torso_r * 1.05, torso * 0.02, 0.05), _chest)
			_mesh(_boxm(Vector3(0.03, 0.22, 0.03)), metal, Vector3(torso_r * 1.12, torso * 0.08, 0.1), _chest)
		"scarf":
			_mesh(_torus(r * 0.45, r * 0.75), m_accent, Vector3(0, torso + 0.02, 0), _chest)
			_mesh(_boxm(Vector3(0.1, 0.32, 0.04)), m_accent, Vector3(0.08, torso - 0.15, torso_r * 0.85), _chest, Vector3(-0.2, 0, 0.15))
		"long_coat", "lab_coat":
			var coat_len := torso * 0.6 + _leg_len * (0.75 if acc == "long_coat" else 0.6)
			_mesh(_cyl(torso_r * 1.12, torso_r * 1.55, coat_len, 12), m_coat, Vector3(0, torso * 0.35 - coat_len * 0.5, 0), _chest, Vector3.ZERO, Vector3(1, 1, 0.85))
			_mesh(_boxm(Vector3(sh_w * 0.9, 0.06, 0.06)), m_accent, Vector3(0, torso * 0.75, torso_r * 0.92), _chest)
		"cards_pocket":
			_mesh(_boxm(Vector3(0.07, 0.1, 0.03)), Mats.toon(Color(0.9, 0.85, 0.75), 0.0), Vector3(torso_r * 0.5, torso * 0.68, torso_r * 0.98), _chest)
		"stethoscope":
			_mesh(_torus(r * 0.55, r * 0.68), Mats.toon(Color(0.1, 0.1, 0.12), 0.0), Vector3(0, torso - 0.02, 0.02), _chest, Vector3(0.2, 0, 0))
			_mesh(_cyl(0.035, 0.035, 0.02), metal, Vector3(0.05, torso * 0.62, torso_r * 1.0), _chest, Vector3(PI / 2, 0, 0))
		"headband":
			_mesh(_torus(r * 1.0, r * 1.1), m_accent, Vector3(0, r * 0.5, 0), _head, Vector3(0.2, 0, 0))
		"nurse_cap":
			_mesh(_boxm(Vector3(r * 0.9, r * 0.35, r * 0.6)), Mats.toon(Color(0.95, 0.93, 0.88), 0.0, INK), Vector3(0, r * 1.05, r * 0.1), _head, Vector3(-0.25, 0, 0))
			_mesh(_boxm(Vector3(r * 0.25, r * 0.08, r * 0.05)), Mats.toon(Color(0.75, 0.15, 0.12), 0.0), Vector3(0, r * 1.1, r * 0.42), _head, Vector3(-0.25, 0, 0))
		"satchel":
			_mesh(_boxm(Vector3(0.08, 0.2, 0.26)), leather, Vector3(-torso_r * 1.25, torso * 0.05, 0.02), _chest)
			_mesh(_boxm(Vector3(0.04, torso * 1.1, 0.03)), leather, Vector3(0, torso * 0.5, torso_r * 0.82), _chest, Vector3(0, 0, 0.75))
		"hood":
			_mesh(_sphere(r * 1.25, true), m_coat, Vector3(0, -r * 0.15, -r * 0.55), _head, Vector3(-1.9, 0, 0), Vector3(1, 1, 0.8))
			_mesh(_torus(r * 0.55, r * 0.9), m_coat, Vector3(0, torso + 0.02, -0.02), _chest)
		"lantern":
			var lamp := _mesh(_sphere(0.06), Mats.glow(Color(1.0, 0.72, 0.35), 4.0), Vector3(torso_r * 1.2, torso * 0.0, 0.08), _chest)
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.72, 0.4)
			l.light_energy = 0.7
			l.omni_range = 3.5
			lamp.add_child(l)


# ================================================================ objets en main

func set_prop(p: String) -> void:
	if p == _prop:
		return
	if _props.has(_prop):
		_props[_prop].visible = false
	_prop = p
	if p == "":
		return
	if not _props.has(p):
		_props[p] = _make_prop(p)
	_props[p].visible = true


func _make_prop(p: String) -> Node3D:
	var root := Node3D.new()
	_hand_r.add_child(root)
	var wood := Mats.toon(Color(0.5, 0.33, 0.18), 0.2, INK)
	var metal := Mats.toon(Color(0.72, 0.74, 0.78), 0.05, INK)
	match p:
		"ladle":
			_mesh(_cyl(0.012, 0.012, 0.45), wood, Vector3(0, -0.15, 0.08), root, Vector3(0.6, 0, 0))
			_mesh(_sphere(0.05, true), metal, Vector3(0, -0.33, 0.2), root, Vector3(PI, 0, 0))
		"knife":
			_mesh(_boxm(Vector3(0.02, 0.05, 0.22)), metal, Vector3(0, -0.02, 0.12), root)
		"rag", "cloth":
			_mesh(_boxm(Vector3(0.16, 0.03, 0.14)), Mats.toon(Color(0.85, 0.82, 0.7) if p == "cloth" else Color(0.55, 0.62, 0.7), 0.3, INK), Vector3(0, -0.02, 0.05), root)
		"clipboard":
			_mesh(_boxm(Vector3(0.2, 0.28, 0.015)), wood, Vector3(0, 0.05, 0.08), root, Vector3(-0.6, 0, 0))
			_mesh(_boxm(Vector3(0.17, 0.22, 0.005)), Mats.toon(Color(0.95, 0.92, 0.85), 0.0), Vector3(0, 0.05, 0.09), root, Vector3(-0.6, 0, 0))
		"broom":
			_mesh(_cyl(0.015, 0.015, 1.2), wood, Vector3(0, -0.25, 0.1), root, Vector3(0.35, 0, 0))
			_mesh(_boxm(Vector3(0.3, 0.12, 0.08)), Mats.toon(Color(0.75, 0.6, 0.3), 0.4, INK), Vector3(0, -0.82, 0.3), root, Vector3(0.35, 0, 0))
		"pen":
			_mesh(_cyl(0.008, 0.008, 0.13), Mats.toon(Color(0.1, 0.1, 0.15), 0.0), Vector3(0, -0.02, 0.05), root, Vector3(1.0, 0, 0))
		"wrench":
			_mesh(_boxm(Vector3(0.03, 0.3, 0.02)), metal, Vector3(0, -0.1, 0.04), root, Vector3(0.4, 0, 0))
			_mesh(_torus(0.02, 0.045), metal, Vector3(0, -0.25, 0.1), root)
		"torch":
			_mesh(_cyl(0.025, 0.02, 0.22), metal, Vector3(0, -0.06, 0.08), root, Vector3(1.2, 0, 0))
			_mesh(_sphere(0.025), Mats.glow(Color(0.6, 0.85, 1.0), 6.0), Vector3(0, -0.1, 0.2), root)
		"hammer":
			_mesh(_cyl(0.015, 0.015, 0.32), wood, Vector3(0, -0.08, 0.06), root, Vector3(0.5, 0, 0))
			_mesh(_boxm(Vector3(0.05, 0.05, 0.14)), metal, Vector3(0, -0.2, 0.14), root, Vector3(0.5, 0, 0))
		"vial":
			_mesh(_cyl(0.025, 0.025, 0.12), Mats.glow(Color(0.4, 1.0, 0.5), 1.2), Vector3(0, 0.02, 0.05), root)
		"book":
			_mesh(_boxm(Vector3(0.18, 0.24, 0.05)), Mats.toon(Color(0.45, 0.15, 0.12), 0.2, INK), Vector3(0, 0.03, 0.08), root, Vector3(-0.9, 0, 0))
		"cards":
			_mesh(_boxm(Vector3(0.08, 0.11, 0.02)), Mats.toon(Color(0.95, 0.92, 0.85), 0.0, INK), Vector3(0, 0.0, 0.06), root, Vector3(-0.7, 0, 0))
		"bowl":
			_mesh(_sphere(0.08, true), Mats.toon(Color(0.75, 0.68, 0.55), 0.1, INK), Vector3(0, 0.0, 0.08), root, Vector3(PI, 0, 0))
	return root


# ================================================================ animation

func face(dir: Vector3, delta: float) -> void:
	if dir.length_squared() < 0.0001:
		return
	_yaw = lerp_angle(_yaw, atan2(dir.x, dir.z), 1.0 - exp(-12.0 * delta))
	rotation.y = _yaw


func set_yaw(y: float) -> void:
	_yaw = y
	rotation.y = y


func _approach(n: Node3D, target: Vector3, k: float) -> void:
	n.rotation = n.rotation.lerp(target, k)


func _process(delta: float) -> void:
	if _body == null:
		return
	_t += delta
	var k := 1.0 - exp(-12.0 * delta)
	var hunch: float = gait["hunch"]
	var leg_l := Vector3.ZERO
	var leg_r := Vector3.ZERO
	var arm_l := Vector3(0, 0, -0.08)
	var arm_r := Vector3(0, 0, 0.08)
	var chest := Vector3(hunch, 0, 0)
	var head := Vector3(-hunch * 0.6, 0, 0)
	var body_y := 0.0

	if walking:
		_phase += delta * 8.5 * gait["speed"] * speed_factor / maxf(_leg_len / 0.8, 0.6)
		var s := sin(_phase)
		var stride: float = gait["stride"]
		leg_l.x = s * stride
		leg_r.x = -s * stride
		arm_l.x = -s * stride * 0.8
		arm_r.x = s * stride * 0.8
		chest = Vector3(hunch + 0.06, 0, cos(_phase) * gait["sway"])
		body_y = absf(cos(_phase)) * gait["bounce"]
		if signf(s) != signf(_last_sin):
			step.emit()
		_last_sin = s
	elif task_anim != "":
		var res := _task_pose(task_anim)
		arm_l = res[0]
		arm_r = res[1]
		chest = res[2] + Vector3(hunch, 0, 0)
		head = res[3]
	else:
		var b := sin(_t * 1.6) * 0.02
		match idle:
			"arms_crossed":
				arm_l = Vector3(-0.9, 0.4, 0.75)
				arm_r = Vector3(-0.9, -0.4, -0.75)
			"fidget":
				leg_l.x = sin(_t * 3.0) * 0.08
				head = Vector3(0, sin(_t * 0.9) * 0.6, 0)
				arm_r = Vector3(-0.2 + sin(_t * 5.0) * 0.1, 0, 0.1)
			"shuffle":
				arm_r = Vector3(-1.0 + sin(_t * 7.0) * 0.12, 0, -0.35)
				arm_l = Vector3(-0.9, 0, 0.35)
				head = Vector3(0.25, 0, 0)
			"hum":
				chest = Vector3(hunch, 0, sin(_t * 1.4) * 0.07)
				head = Vector3(0, 0, sin(_t * 1.4 + 0.5) * 0.12)
			"hands_back":
				arm_l = Vector3(0.45, 0, 0.25)
				arm_r = Vector3(0.45, 0, -0.25)
				head = Vector3(-0.08, sin(_t * 0.4) * 0.25, 0)
			"look_around":
				head = Vector3(0, sin(_t * 0.7) * 0.9, 0)
			_:
				head = Vector3(0, sin(_t * 0.5) * 0.2, 0)
		chest.x += b

	if sitting:
		leg_l = Vector3(-1.45, 0, 0.05)
		leg_r = Vector3(-1.45, 0, -0.05)
		body_y = 0.48 - _leg_len

	_approach(_leg_l, leg_l, k)
	_approach(_leg_r, leg_r, k)
	_approach(_arm_l, arm_l, k)
	_approach(_arm_r, arm_r, k)
	_approach(_chest, chest, k)
	_approach(_head, head, k)
	_body.position.y = lerpf(_body.position.y, body_y, k)


## Gestes de travail : renvoie [bras gauche, bras droit, buste, tête].
func _task_pose(a: String) -> Array:
	var t := _t
	match a:
		"stir":
			return [Vector3(-0.7, 0, 0.1), Vector3(-1.1 + sin(t * 4.0) * 0.12, cos(t * 4.0) * 0.25, -0.1), Vector3(0.15, 0, 0), Vector3(0.35, 0, 0)]
		"chop":
			return [Vector3(-0.8, 0, 0.25), Vector3(-0.95 + absf(sin(t * 7.0)) * -0.45, 0, -0.1), Vector3(0.2, 0, 0), Vector3(0.45, 0, 0)]
		"wash":
			return [Vector3(-1.0 + sin(t * 5.0) * 0.15, cos(t * 5.0) * 0.2, 0.15), Vector3(-1.0 - sin(t * 5.0) * 0.15, -cos(t * 5.0) * 0.2, -0.15), Vector3(0.25, 0, 0), Vector3(0.4, 0, 0)]
		"write":
			return [Vector3(-0.7, 0, 0.3), Vector3(-0.85 + sin(t * 11.0) * 0.04, sin(t * 6.0) * 0.08, -0.2), Vector3(0.2, 0, 0), Vector3(0.5, 0, 0)]
		"hammer":
			var c := fmod(t, 1.0)
			var swing := -2.3 + smoothstep(0.0, 0.25, c) * 1.6 if c < 0.3 else -0.7 - smoothstep(0.3, 1.0, c) * 1.6
			return [Vector3(-0.8, 0, 0.2), Vector3(swing, 0, -0.1), Vector3(0.15, 0, 0), Vector3(0.4, 0, 0)]
		"weld":
			return [Vector3(-1.2, 0, 0.2), Vector3(-1.25 + sin(t * 25.0) * 0.02, 0, -0.2), Vector3(0.25, 0, 0), Vector3(0.5, 0, 0)]
		"reach":
			return [Vector3(-0.5, 0, 0.1), Vector3(-2.0 + sin(t * 2.5) * 0.2, sin(t * 1.3) * 0.3, -0.1), Vector3(-0.05, 0, 0), Vector3(-0.2, 0, 0)]
		"inspect":
			return [Vector3(-0.4, 0, 0.5), Vector3(-1.7, -0.5, -0.8), Vector3(0.1, 0, sin(t * 0.8) * 0.05), Vector3(0.15, 0, 0.15)]
		"sweep":
			return [Vector3(-0.7, sin(t * 3.0) * 0.4, 0.2), Vector3(-0.55, sin(t * 3.0) * 0.4, -0.2), Vector3(0.2, sin(t * 3.0) * 0.25, 0), Vector3(0.3, 0, 0)]
		"tend":
			return [Vector3(-0.9 + sin(t * 2.0) * 0.1, 0, 0.15), Vector3(-0.9 - sin(t * 2.0) * 0.1, 0, -0.15), Vector3(0.4, 0, 0), Vector3(0.3, 0, 0)]
		"read":
			return [Vector3(-1.1, 0.3, 0.3), Vector3(-1.1, -0.3, -0.3), Vector3(0.05, 0, 0), Vector3(0.35, sin(t * 0.3) * 0.1, 0)]
		"eat":
			var e := (sin(t * 2.2) + 1.0) * 0.5
			return [Vector3(-0.8, 0, 0.25), Vector3(-1.0 - e * 1.1, 0, -0.35 * e), Vector3(0.1, 0, 0), Vector3(0.15 - e * 0.1, 0, 0)]
		"cards":
			return [Vector3(-1.0, 0.2, 0.25), Vector3(-1.0 + maxf(sin(t * 1.7), 0.0) * -0.5, 0, -0.25), Vector3(0.1, 0, 0), Vector3(0.25, sin(t * 0.6) * 0.3, 0)]
		"fold":
			var f := sin(t * 2.0)
			return [Vector3(-0.9 + f * 0.25, 0.3 * f, 0.2), Vector3(-0.9 + f * 0.25, -0.3 * f, -0.2), Vector3(0.2, 0, 0), Vector3(0.45, 0, 0)]
	return [Vector3(0, 0, -0.08), Vector3(0, 0, 0.08), Vector3.ZERO, Vector3.ZERO]
