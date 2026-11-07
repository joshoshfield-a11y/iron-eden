extends Node3D

## Hostile mech. Walks at the core, diverts to the player when close.
## Types: runner (fast/fragile), grunt (balanced), brute (slow/tanky).

signal died(enemy, xp_value, salvage_value, source)

var last_hit_source: String = "player"

var kind: String = "grunt"
var max_hp: float = 42.0
var hp: float = 42.0
var speed: float = 4.8
var damage: float = 10.0
var xp_value: int = 1
var salvage_value: int = 9
var attack_range: float = 3.0

var core_position: Vector3 = Vector3.ZERO
var on_core_damage: Callable = Callable() # main.take_core_damage(amount)

var _attack_cd: float = 0.0
var _root: Node3D
var _mat: StandardMaterial3D
var _flash_t: float = 0.0
var _dead: bool = false

func setup(p_kind: String, hp_mult: float, spawn_pos: Vector3) -> void:
	kind = p_kind
	position = spawn_pos # setup runs before add_child; global_position would error outside the tree
	match kind:
		"runner":
			max_hp = 18.0; speed = 7.6; damage = 6.0; xp_value = 1; salvage_value = 7
		"brute":
			max_hp = 135.0; speed = 3.0; damage = 22.0; xp_value = 3; salvage_value = 18
		_:
			max_hp = 42.0; speed = 4.8; damage = 10.0; xp_value = 2; salvage_value = 9
	max_hp *= hp_mult
	hp = max_hp

func _ready() -> void:
	add_to_group("enemies")
	_build()

func _build() -> void:
	_root = Node3D.new()
	add_child(_root)
	var base_color := Color(0.55, 0.16, 0.14)
	var scale_f := 1.0
	match kind:
		"runner":
			base_color = Color(0.75, 0.35, 0.12); scale_f = 0.75
		"brute":
			base_color = Color(0.4, 0.1, 0.22); scale_f = 1.45
	_mat = Factory.mat(base_color, Color(0, 0, 0), 0.0, 0.5, 0.5)
	var dark := Factory.mat(Color(0.09, 0.09, 0.11), Color(0, 0, 0), 0.0, 0.7, 0.45)
	var eye := Factory.mat(Color(1.0, 0.25, 0.15), Color(1.0, 0.25, 0.15), 2.2, 0.0, 0.3)
	_root.scale = Vector3.ONE * scale_f
	Factory.box(_root, Vector3(0.5, 0.9, 0.95), Vector3(-0.6, 0.45, 0.1), dark)
	Factory.box(_root, Vector3(0.5, 0.9, 0.95), Vector3(0.6, 0.45, 0.1), dark)
	Factory.box(_root, Vector3(1.8, 0.95, 2.0), Vector3(0, 1.25, 0), _mat)
	Factory.box(_root, Vector3(1.2, 0.35, 1.1), Vector3(0, 1.85, -0.15), _mat)
	Factory.box(_root, Vector3(0.95, 0.16, 0.1), Vector3(0, 1.6, -1.03), eye)
	var gun := Factory.cyl(_root, 0.1, 1.4, Vector3(0.85, 1.45, -0.6), dark, 8)
	gun.rotation.x = PI / 2.0

func _physics_process(delta: float) -> void:
	if _dead:
		return
	var player = get_tree().get_first_node_in_group("player")
	var target_pos := core_position
	var target_is_player := false
	if player and is_instance_valid(player) and player.hp > 0.0:
		if (player.global_position - global_position).length() < 9.0:
			target_pos = player.global_position
			target_is_player = true
	var to_t: Vector3 = target_pos - global_position
	to_t.y = 0.0
	var dist := to_t.length()
	_attack_cd -= delta
	if dist > attack_range:
		var dir := to_t / maxf(dist, 0.001)
		# light separation so they do not stack into one blob
		for other in get_tree().get_nodes_in_group("enemies"):
			if other == self or not is_instance_valid(other):
				continue
			var away: Vector3 = global_position - other.global_position
			away.y = 0.0
			var ad := away.length()
			if ad > 0.01 and ad < 1.9:
				dir += away / ad * 0.7
		global_position += dir.normalized() * speed * delta
		_root.rotation.y = lerp_angle(_root.rotation.y, atan2(dir.x, dir.z) + PI, 8.0 * delta)
	elif _attack_cd <= 0.0:
		_attack_cd = 0.85
		if target_is_player:
			player.take_damage(damage)
		elif on_core_damage.is_valid():
			on_core_damage.call(damage)
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			_mat.emission_enabled = false

func take_damage(amount: float, source: String = "player") -> void:
	if _dead:
		return
	last_hit_source = source
	hp -= amount
	_flash_t = 0.06
	_mat.emission_enabled = true
	_mat.emission = Color(1.0, 0.6, 0.4)
	_mat.emission_energy_multiplier = 1.2
	if hp <= 0.0:
		_dead = true
		emit_signal("died", self, xp_value, salvage_value, last_hit_source)
		queue_free()
