extends Node3D

## Player mech. Movement: WASD/arrows or left-half touch drag.
## Fire: automatic at nearest enemy in range (mobile-first), mouse aims
## the hull when no enemy is in range.

signal died

var max_hp: float = 120.0
var hp: float = 120.0
var speed: float = 11.0
var fire_interval: float = 0.22
var bullet_damage: float = 12.0
var bullet_speed: float = 58.0
var aim_range: float = 27.0

var move_input: Vector2 = Vector2.ZERO # set by main (keys / joystick)
var aim_point: Vector3 = Vector3(0, 0, -10)
var manual_aim: Vector3 = Vector3.ZERO # twin-stick aim direction (flat), set by main
var manual_fire: bool = false # aim stick held / mouse held: fire along manual_aim

var dash_cooldown: float = 0.0
var _dash_time: float = 0.0
var _dash_dir: Vector3 = Vector3.ZERO

func start_dash() -> void:
	if dash_cooldown > 0.0 or hp <= 0.0:
		return
	var dir := Vector3(move_input.x, 0, move_input.y)
	if dir.length() < 0.1:
		dir = -_hull.global_transform.basis.z
		dir.y = 0.0
	_dash_dir = dir.normalized()
	_dash_time = 0.18
	dash_cooldown = 1.6

var _fire_cd: float = 0.0
var _hull: Node3D
var _turret: Node3D
var _muzzle: Vector3 = Vector3(0, 1.5, -1.6)
var _flash_t: float = 0.0
var _body_mat: StandardMaterial3D

const BulletScene := preload("res://scripts/bullet.gd")

func _ready() -> void:
	add_to_group("player")
	_build()

func _build() -> void:
	_body_mat = Factory.mat(Color(0.22, 0.48, 0.62), Color(0, 0, 0), 0.0, 0.6, 0.35)
	var dark := Factory.mat(Color(0.1, 0.12, 0.15), Color(0, 0, 0), 0.0, 0.7, 0.4)
	var accent := Factory.mat(Color(0.35, 0.9, 1.0), Color(0.35, 0.9, 1.0), 1.8, 0.1, 0.3)
	_hull = Node3D.new()
	add_child(_hull)
	# legs
	Factory.box(_hull, Vector3(0.55, 1.0, 1.1), Vector3(-0.75, 0.5, 0.2), dark)
	Factory.box(_hull, Vector3(0.55, 1.0, 1.1), Vector3(0.75, 0.5, 0.2), dark)
	Factory.box(_hull, Vector3(0.7, 0.35, 1.3), Vector3(-0.75, 0.18, 0.25), dark)
	Factory.box(_hull, Vector3(0.7, 0.35, 1.3), Vector3(0.75, 0.18, 0.25), dark)
	# torso
	Factory.box(_hull, Vector3(2.1, 1.0, 2.3), Vector3(0, 1.35, 0), _body_mat)
	Factory.box(_hull, Vector3(1.5, 0.4, 1.4), Vector3(0, 1.95, -0.2), _body_mat)
	# cockpit glow strip
	Factory.box(_hull, Vector3(1.1, 0.18, 0.1), Vector3(0, 1.75, -1.18), accent)
	# shoulder pads
	Factory.box(_hull, Vector3(0.7, 0.55, 1.5), Vector3(-1.35, 1.6, 0.1), dark)
	Factory.box(_hull, Vector3(0.7, 0.55, 1.5), Vector3(1.35, 1.6, 0.1), dark)
	_turret = Node3D.new()
	_turret.position = Vector3(0, 1.9, 0)
	add_child(_turret)
	# twin barrels
	var barrel_mat := Factory.mat(Color(0.16, 0.18, 0.2), Color(0, 0, 0), 0.0, 0.85, 0.3)
	var b1 := Factory.cyl(_turret, 0.11, 1.7, Vector3(-0.3, 0.1, -0.8), barrel_mat, 10)
	b1.rotation.x = PI / 2.0
	var b2 := Factory.cyl(_turret, 0.11, 1.7, Vector3(0.3, 0.1, -0.8), barrel_mat, 10)
	b2.rotation.x = PI / 2.0
	Factory.box(_turret, Vector3(0.9, 0.4, 0.7), Vector3(0, 0.1, 0.1), dark)

func _physics_process(delta: float) -> void:
	if hp <= 0.0:
		return
	var dir := Vector3(move_input.x, 0, move_input.y)
	if dir.length() > 1.0:
		dir = dir.normalized()
	global_position += dir * speed * delta
	dash_cooldown = maxf(0.0, dash_cooldown - delta)
	if _dash_time > 0.0:
		_dash_time -= delta
		global_position += _dash_dir * speed * 2.7 * delta
	global_position.x = clampf(global_position.x, -56.0, 56.0)
	global_position.z = clampf(global_position.z, -56.0, 56.0)
	global_position.y = 0.0
	if dir.length() > 0.05:
		var target_yaw := atan2(dir.x, dir.z) + PI
		_hull.rotation.y = lerp_angle(_hull.rotation.y, target_yaw, 12.0 * delta)
	_fire_cd -= delta
	if manual_fire and manual_aim.length() > 0.1:
		# twin-stick: aim and fire exactly where the player points
		var look2: Vector3 = global_position + manual_aim * 12.0
		var to2: Vector3 = look2 - global_position
		to2.y = 0.0
		_turret.rotation.y = lerp_angle(_turret.rotation.y, atan2(to2.x, to2.z) + PI - _hull.rotation.y, 22.0 * delta)
		if _fire_cd <= 0.0:
			_fire_cd = fire_interval
			_shoot(look2)
		return
	# smart targeting assistance (GDD 3.1): nearest enemy, else mouse point
	var target = _nearest_enemy()
	var look := aim_point
	if target:
		look = target.global_position
	var to_look: Vector3 = look - global_position
	to_look.y = 0.0
	if to_look.length() > 0.3:
		_turret.rotation.y = lerp_angle(_turret.rotation.y, atan2(to_look.x, to_look.z) + PI - _hull.rotation.y, 18.0 * delta)
	if target and _fire_cd <= 0.0:
		_fire_cd = fire_interval
		_shoot(target.global_position)
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			_body_mat.emission_enabled = false

func _nearest_enemy() -> Node3D:
	var best: Node3D = null
	var best_d := aim_range
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		var d: float = (e.global_position - global_position).length()
		if d < best_d:
			best_d = d
			best = e
	return best

func _shoot(at: Vector3) -> void:
	var from: Vector3 = global_position + Vector3(0, 1.9, 0)
	var dir: Vector3 = at + Vector3(0, 0.9, 0) - from
	dir.y = 0.0
	if dir.length() < 0.1:
		return
	var b = Node3D.new()
	b.set_script(BulletScene)
	get_parent().add_child(b)
	b.setup(from, dir, bullet_damage, bullet_speed, true, Color(0.45, 0.95, 1.0))
	_flash_t = 0.05
	_body_mat.emission_enabled = true
	_body_mat.emission = Color(0.3, 0.7, 0.9)
	_body_mat.emission_energy_multiplier = 0.7

func take_damage(amount: float) -> void:
	if hp <= 0.0:
		return
	hp -= amount
	if hp <= 0.0:
		hp = 0.0
		emit_signal("died")

func heal_full() -> void:
	hp = max_hp
