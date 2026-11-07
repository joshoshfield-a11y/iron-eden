extends Node3D

## Defensive turret placed on a build pad. Auto-fires at nearest enemy.

var fire_range: float = 19.0
var fire_interval: float = 0.5
var bullet_damage: float = 9.0
var bullet_speed: float = 52.0
var level: int = 1

var _cd: float = 0.0
var _head: Node3D

const BulletScene := preload("res://scripts/bullet.gd")

func _ready() -> void:
	_build()

func _build() -> void:
	var dark := Factory.mat(Color(0.12, 0.14, 0.16), Color(0, 0, 0), 0.0, 0.7, 0.4)
	var steel := Factory.mat(Color(0.35, 0.55, 0.45), Color(0, 0, 0), 0.0, 0.6, 0.4)
	var glow := Factory.mat(Color(0.4, 1.0, 0.6), Color(0.4, 1.0, 0.6), 1.6, 0.1, 0.3)
	Factory.cyl(self, 1.05, 0.5, Vector3(0, 0.25, 0), dark, 8)
	Factory.cyl(self, 0.7, 0.9, Vector3(0, 0.9, 0), steel, 8)
	_head = Node3D.new()
	_head.position = Vector3(0, 1.55, 0)
	add_child(_head)
	Factory.box(_head, Vector3(0.85, 0.45, 0.85), Vector3.ZERO, steel)
	Factory.box(_head, Vector3(0.5, 0.14, 0.08), Vector3(0, 0.05, -0.45), glow)
	var barrel := Factory.cyl(_head, 0.09, 1.3, Vector3(0, 0.05, -0.75), dark, 8)
	barrel.rotation.x = PI / 2.0

func _physics_process(delta: float) -> void:
	_cd -= delta
	var target: Node3D = null
	var best := fire_range
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		var d: float = (e.global_position - global_position).length()
		if d < best:
			best = d
			target = e
	if target:
		var to_t: Vector3 = target.global_position - global_position
		to_t.y = 0.0
		if to_t.length() > 0.2:
			_head.rotation.y = lerp_angle(_head.rotation.y, atan2(to_t.x, to_t.z) + PI, 10.0 * delta)
		if _cd <= 0.0:
			_cd = fire_interval
			var from: Vector3 = global_position + Vector3(0, 1.6, 0)
			var dir: Vector3 = target.global_position + Vector3(0, 0.9, 0) - from
			dir.y = 0.0
			var b = Node3D.new()
			b.set_script(BulletScene)
			get_parent().add_child(b)
			b.setup(from, dir, bullet_damage, bullet_speed, true, Color(0.55, 1.0, 0.65), "turret")
