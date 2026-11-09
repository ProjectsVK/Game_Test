extends CharacterBody3D
## Lina, la seule personne jouable. Marche dans la direction de la caméra.
## Anti-blocage : ne heurte que les murs et les meubles (jamais les habitants),
## mémorise sa dernière position sûre et y revient si elle ne bouge plus malgré les touches
## pendant 3 secondes, ou si elle sort de la carte.

const Visual := preload("res://scripts/character_visual.gd")

const SPEED := 4.2
const SPRINT := 1.6
const RADIUS := 0.3
const STUCK_TIME := 3.0

var main
var data: Dictionary = GameData.PLAYER
var cd := [0.0, 0.0, 0.0, 0.0]
var visual
var safe_pos := Vector3(0, 0, -9.0)
var moving := false

var _stuck_t := 0.0
var _safe_t := 0.0
var _probe: PhysicsShapeQueryParameters3D


func setup(m) -> void:
	main = m
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	collision_layer = 2
	collision_mask = 1          # murs et meubles seulement : les habitants ne bloquent jamais
	safe_margin = 0.02
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = RADIUS
	cap.height = 1.7
	cs.shape = cap
	cs.position = Vector3(0, 0.85, 0)
	add_child(cs)
	visual = Visual.new()
	add_child(visual)
	visual.build_look(data["look"])
	visual.step.connect(_on_step)
	# sonde un peu plus large que Lina pour vérifier qu'un endroit est vraiment dégagé
	var probe_shape := CapsuleShape3D.new()
	probe_shape.radius = RADIUS + 0.08
	probe_shape.height = 1.6
	_probe = PhysicsShapeQueryParameters3D.new()
	_probe.shape = probe_shape
	_probe.collision_mask = 1


func _physics_process(delta: float) -> void:
	if main == null:
		return
	for i in 4:
		cd[i] = maxf(0.0, cd[i] - delta)
	if Game.paused or Game.over:
		velocity = Vector3.ZERO
		visual.walking = false
		moving = false
		return
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir: Vector3 = main.rig.flat_basis() * Vector3(input.x, 0, input.y)
	var sprinting := Input.is_action_pressed("sprint")
	var spd := SPEED * (SPRINT if sprinting else 1.0)
	var before := global_position
	velocity = dir * spd
	move_and_slide()
	global_position.y = 0.0
	moving = dir.length() > 0.05
	visual.walking = moving
	visual.speed_factor = 1.45 if sprinting else 1.0
	if moving:
		visual.face(main.rig.forward() if input.y <= 0.1 else dir, delta)
	_watch_stuck(delta, input.length() > 0.2, before, spd)


func _watch_stuck(delta: float, pushing: bool, before: Vector3, spd: float) -> void:
	# sortie de la carte (ou chute) : retour immédiat
	if global_position.y < -2.0 or main.bunker.room_at(global_position) == "":
		unstuck(false)
		return
	var moved := global_position.distance_to(before)
	if pushing and moved < spd * delta * 0.1:
		_stuck_t += delta
		if _stuck_t >= STUCK_TIME:
			unstuck(false)
			return
	else:
		_stuck_t = maxf(0.0, _stuck_t - delta * 2.0)
	_safe_t -= delta
	if _safe_t <= 0.0 and _stuck_t < 0.3:
		_safe_t = 0.25
		if is_free(global_position):
			safe_pos = global_position


## Vrai si Lina tient à cet endroit sans toucher un mur ni un meuble.
func is_free(p: Vector3, margin: float = 0.08) -> bool:
	if not is_inside_tree():
		return true
	(_probe.shape as CapsuleShape3D).radius = RADIUS + margin
	_probe.transform = Transform3D(Basis(), p + Vector3(0, 0.9, 0))
	var hits := get_world_3d().direct_space_state.intersect_shape(_probe, 1)
	return hits.is_empty()


## Replace Lina. force = bouton « Débloquer » : on va au centre dégagé de la salle la plus proche.
func unstuck(force: bool) -> void:
	_stuck_t = 0.0
	var target := safe_pos
	if force or not is_free(target):
		target = _nearest_room_center()
	global_position = target
	velocity = Vector3.ZERO
	safe_pos = target
	Sfx.ui("ui_unstuck", -4.0)
	Game.say("Lina se dégage et reprend sa route.")


func _nearest_room_center() -> Vector3:
	var best := Vector3.ZERO
	var bd := INF
	for id in GameData.ROOMS:
		var c: Vector3 = main.bunker.center(id)
		var d := c.distance_to(global_position)
		if d < bd:
			bd = d
			best = c
	return best


func _on_step() -> void:
	var g: String = main.bunker.ground_at(global_position)
	Sfx.ui("step_%s_%d" % [g, Game.rng.randi_range(1, 4)], -9.0, Game.rng.randf_range(0.92, 1.08))
