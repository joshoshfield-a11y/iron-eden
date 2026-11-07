extends Node3D

## Distance-checked projectile (no physics bodies; reliable headless and on
## mobile, and cheap enough for a few hundred live rounds).

var velocity: Vector3 = Vector3.ZERO
var damage: float = 10.0
var life: float = 1.6
var from_player_side: bool = true
var source: String = "player" # "player" | "turret" - feeds the adaptation report

var _body: MeshInstance3D

func setup(start_pos: Vector3, dir: Vector3, dmg: float, speed: float, player_side: bool, color: Color, p_source: String = "player") -> void:
	global_position = start_pos
	damage = dmg
	from_player_side = player_side
	source = p_source
	velocity = dir.normalized() * speed
	velocity.y = 0.0
	_body = Factory.sphere(self, 0.16, Vector3.ZERO, Factory.mat(color, color, 2.6, 0.0, 0.3))
	Factory.box(self, Vector3(0.1, 0.1, 0.9), Vector3(0, 0, 0.45), Factory.mat(color, color, 1.4, 0.0, 0.4))
	if velocity.length() > 0.1:
		look_at(global_position + velocity, Vector3.UP)

func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	global_position += velocity * delta
	if from_player_side:
		for e in get_tree().get_nodes_in_group("enemies"):
			if not is_instance_valid(e):
				continue
			var d: Vector3 = e.global_position - global_position
			d.y = 0.0
			if d.length() < 1.15:
				e.take_damage(damage, source)
				queue_free()
				return
	else:
		var p = get_tree().get_first_node_in_group("player")
		if p and is_instance_valid(p):
			var d: Vector3 = p.global_position - global_position
			d.y = 0.0
			if d.length() < 1.15:
				p.take_damage(damage)
				queue_free()
