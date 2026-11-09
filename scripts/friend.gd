extends CharacterBody3D
## Un des trois amis. Celui qui est actif suit les touches et la caméra, les autres suivent sa trace.

const Visual := preload("res://scripts/character_visual.gd")

var data: Dictionary
var main
var index := 0
var cd := [0.0, 0.0, 0.0, 0.0]
var is_active := false
var visual


func setup(d: Dictionary, m, i: int) -> void:
	data = d
	main = m
	index = i
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	collision_layer = 2
	collision_mask = 1 | 4
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	cs.position = Vector3(0, 0.95, 0)
	add_child(cs)
	visual = Visual.new()
	add_child(visual)
	visual.build(d["color"], d["hair"], d["skin"], d["id"])


func _physics_process(delta: float) -> void:
	if main == null:
		return
	for i in 4:
		cd[i] = maxf(0.0, cd[i] - delta)
	if Game.paused or Game.over:
		velocity = Vector3.ZERO
		visual.walking = false
		return
	if is_active:
		_control(delta)
	else:
		_follow(delta)
	global_position.y = 0.0


func _control(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir: Vector3 = main.rig.flat_basis() * Vector3(input.x, 0, input.y)
	var boosted: bool = Input.is_action_pressed("sprint") or main.timers["sprint"] > 0.0
	var spd := 4.2 * (1.75 if boosted else 1.0)
	velocity = dir * spd
	move_and_slide()
	visual.walking = dir.length() > 0.05
	visual.speed_factor = 1.5 if boosted else 1.0
	# comme dans un jeu de tir à la 3e personne : le personnage regarde là où vise la caméra
	if visual.walking:
		visual.face(main.rig.forward() if input.y <= 0.1 else dir, delta)
	var last: Vector3 = main.trail[-1] if main.trail.size() > 0 else Vector3(INF, 0, INF)
	if global_position.distance_to(last) > 0.5:
		main.trail.append(global_position)
		if main.trail.size() > 40:
			main.trail.pop_front()


func _follow(delta: float) -> void:
	var rank: int = (index - main.active + 3) % 3
	var idx: int = main.trail.size() - 1 - rank * 3
	if idx < 0:
		visual.walking = false
		return
	var tgt: Vector3 = main.trail[idx]
	var to := tgt - global_position
	to.y = 0.0
	var d := to.length()
	if d > 0.9:
		var spd := 7.5 if d > 4.0 else 4.2
		velocity = to / d * spd
		move_and_slide()
		visual.face(to, delta)
		visual.walking = true
	else:
		velocity = Vector3.ZERO
		visual.walking = false
