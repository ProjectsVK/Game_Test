extends Node3D
## Silhouette stylisée d'un personnage : manteau évasé, tête, cheveux, bras et jambes animés.
## Placeholder procédural en attendant de vrais modèles 3D (Blender) : remplacer ce nœud suffit.

const Mats := preload("res://scripts/materials.gd")
const INK := 0.022

var walking := false
var speed_factor := 1.0
var _t := 0.0
var _leg_l: Node3D
var _leg_r: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _body: Node3D
var _yaw := 0.0


func build(coat: Color, hair: Color, skin: Color, accessory: String = "") -> void:
	_body = Node3D.new()
	add_child(_body)
	var dark := Mats.toon(coat.darkened(0.55), 0.15, INK)
	var coat_mat := Mats.toon(coat, 0.2, INK)
	var skin_mat := Mats.toon(skin, 0.08, INK)
	var hair_mat := Mats.toon(hair, 0.3, INK)

	_leg_l = _limb(Vector3(-0.13, 0.85, 0), 0.085, 0.8, dark, _body)
	_leg_r = _limb(Vector3(0.13, 0.85, 0), 0.085, 0.8, dark, _body)

	# manteau : cône tronqué, plus large en bas
	var coat_mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.24
	cm.bottom_radius = 0.42
	cm.height = 0.95
	cm.radial_segments = 10
	coat_mi.mesh = cm
	coat_mi.material_override = coat_mat
	coat_mi.position = Vector3(0, 1.02, 0)
	_body.add_child(coat_mi)
	var chest := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.25
	cap.height = 0.7
	chest.mesh = cap
	chest.material_override = coat_mat
	chest.position = Vector3(0, 1.38, 0)
	chest.scale = Vector3(1.0, 1.0, 0.75)
	_body.add_child(chest)
	# col / écharpe
	var scarf := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.1
	tm.outer_radius = 0.2
	scarf.mesh = tm
	scarf.material_override = Mats.toon(coat.lightened(0.25), 0.2, INK)
	scarf.position = Vector3(0, 1.68, 0)
	_body.add_child(scarf)

	_arm_l = _limb(Vector3(-0.32, 1.6, 0), 0.07, 0.65, coat_mat, _body)
	_arm_r = _limb(Vector3(0.32, 1.6, 0), 0.07, 0.65, coat_mat, _body)

	var head := MeshInstance3D.new()
	var hs := SphereMesh.new()
	hs.radius = 0.2
	hs.height = 0.44
	head.mesh = hs
	head.material_override = skin_mat
	head.position = Vector3(0, 1.92, 0)
	_body.add_child(head)
	var hair_mi := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.22
	hm.height = 0.44
	hm.is_hemisphere = true
	hair_mi.mesh = hm
	hair_mi.material_override = hair_mat
	hair_mi.position = Vector3(0, 1.96, 0.02)
	hair_mi.rotation = Vector3(-0.35, 0, 0)
	_body.add_child(hair_mi)
	# mèche qui retombe sur le côté, signature graphique
	var lock := MeshInstance3D.new()
	var lm := PrismMesh.new()
	lm.size = Vector3(0.12, 0.32, 0.12)
	lock.mesh = lm
	lock.material_override = hair_mat
	lock.position = Vector3(0.14, 1.86, -0.14)
	lock.rotation = Vector3(PI, 0, 0.25)
	_body.add_child(lock)

	match accessory:
		"lina":
			var book := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.05, 0.3, 0.22)
			book.mesh = bm
			book.material_override = Mats.toon(Color(0.5, 0.18, 0.12), 0.2, INK)
			book.position = Vector3(-0.42, 1.15, 0.0)
			_body.add_child(book)
		"mael":
			var lamp := MeshInstance3D.new()
			var lsm := SphereMesh.new()
			lsm.radius = 0.08
			lsm.height = 0.16
			lamp.mesh = lsm
			lamp.material_override = Mats.glow(Color(1.0, 0.75, 0.35), 5.0)
			lamp.position = Vector3(0.4, 1.1, -0.1)
			_body.add_child(lamp)
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.75, 0.4)
			l.light_energy = 0.9
			l.omni_range = 4.0
			lamp.add_child(l)
		"sacha":
			var wrench := MeshInstance3D.new()
			var wm := BoxMesh.new()
			wm.size = Vector3(0.06, 0.5, 0.06)
			wrench.mesh = wm
			wrench.material_override = Mats.toon(Color(0.7, 0.72, 0.75), 0.1, INK)
			wrench.position = Vector3(0.0, 1.35, -0.3)
			wrench.rotation = Vector3(0, 0, 0.7)
			_body.add_child(wrench)


func _limb(pivot_pos: Vector3, radius: float, length: float, mat: Material, parent: Node3D) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pivot_pos
	parent.add_child(pivot)
	var mi := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = radius
	cap.height = length
	mi.mesh = cap
	mi.material_override = mat
	mi.position = Vector3(0, -length * 0.5, 0)
	pivot.add_child(mi)
	return pivot


## Tourne doucement le personnage vers une direction (plan horizontal).
func face(dir: Vector3, delta: float) -> void:
	if dir.length_squared() < 0.0001:
		return
	var target := atan2(dir.x, dir.z)
	_yaw = lerp_angle(_yaw, target, 1.0 - exp(-12.0 * delta))
	rotation.y = _yaw


func set_yaw(y: float) -> void:
	_yaw = y
	rotation.y = y


func _process(delta: float) -> void:
	if _body == null:
		return
	if walking:
		_t += delta * 9.0 * speed_factor
	else:
		_t = lerpf(_t, round(_t / PI) * PI, 1.0 - exp(-10.0 * delta))
	var s := sin(_t)
	_leg_l.rotation.x = s * 0.6
	_leg_r.rotation.x = -s * 0.6
	_arm_l.rotation.x = -s * 0.45
	_arm_r.rotation.x = s * 0.45
	_body.position.y = absf(cos(_t)) * 0.05 if walking else 0.0
	_body.rotation.x = 0.06 if walking else 0.0
