extends Node3D
## Caméra à la troisième personne, par-dessus l'épaule droite, pilotée à la souris.
## Un bras-ressort l'empêche de traverser les murs. La passe « peinture » est attachée à la caméra.

const PAINT := preload("res://shaders/painterly.gdshader")

var target: Node3D
var yaw := PI          # regarde vers le sud du dortoir au départ
var pitch := -0.22
var sensitivity := 0.0025
var shoulder := 0.7

var spring: SpringArm3D
var cam: Camera3D
var _pivot: Node3D
var paint: MeshInstance3D


func _ready() -> void:
	_pivot = Node3D.new()
	_pivot.position = Vector3(0, 1.75, 0)
	add_child(_pivot)
	spring = SpringArm3D.new()
	spring.spring_length = 3.2
	spring.collision_mask = 1
	spring.margin = 0.25
	var sh := SphereShape3D.new()
	sh.radius = 0.25
	spring.shape = sh
	spring.position = Vector3(shoulder, 0, 0)
	_pivot.add_child(spring)
	cam = Camera3D.new()
	cam.fov = 72.0
	cam.near = 0.05
	cam.far = 120.0
	cam.current = true
	spring.add_child(cam)

	var quad := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(2, 2)
	quad.mesh = qm
	var mat := ShaderMaterial.new()
	mat.shader = PAINT
	quad.material_override = mat
	quad.extra_cull_margin = 16384.0
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	quad.position = Vector3(0, 0, -1)
	cam.add_child(quad)
	paint = quad


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_P:
		paint.visible = not paint.visible
		Game.say("Filtre peinture " + ("activé" if paint.visible else "coupé") + " (touche P).")
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * sensitivity
		pitch = clampf(pitch - event.relative.y * sensitivity, -1.05, 0.55)


func _process(delta: float) -> void:
	if target == null:
		return
	global_position = global_position.lerp(target.global_position, 1.0 - exp(-16.0 * delta))
	rotation = Vector3(0, yaw, 0)
	_pivot.rotation = Vector3(pitch, 0, 0)


## Base horizontale de la caméra : sert à convertir Z/Q/S/D en direction de marche.
func flat_basis() -> Basis:
	return Basis(Vector3.UP, yaw)


func forward() -> Vector3:
	return flat_basis() * Vector3(0, 0, -1)


func snap_to(t: Node3D) -> void:
	target = t
	global_position = t.global_position
