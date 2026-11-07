extends Node3D

## Deployable structure: turret / generator / barricade / abandoned_turret /
## mortar (Pass 1: indirect-fire AoE, powered) / emp_pylon (Pass 1: periodic
## disable pulse, powered) / repair_station (Pass 32: slow AoE structure
## repair, powered — dead without power).
## Power rule lives in main: mortar, emp_pylon and repair_station work
## only when powered.

const BulletScript := preload("res://scripts/bullet.gd")

const MORTAR_RANGE := 45.0
const MORTAR_MIN_RANGE := 6.0
const MORTAR_CD := 2.4
const MORTAR_DMG := 30.0
const MORTAR_AOE := 4.5
const EMP_RADIUS := 14.0
const EMP_CD := 6.0
const EMP_STUN := 2.5
const REPAIR_RADIUS := 12.0
const REPAIR_RATE := 6.0

var structure_kind: String = "turret"
var hp: float = 80.0
var max_hp: float = 80.0
var is_power_source: bool = false
var is_dead_struct: bool = false
var _fire_cd: float = 0.0
var _emp_cd: float = 0.0
var _head: Node3D
var _power_ring: MeshInstance3D
# Pass 7 (Overhaul A): powered lamp — lit green when powered, dark when not.
var _power_lamp: MeshInstance3D = null
var _power_lamp_mat: StandardMaterial3D = null

func power_lamp_on() -> bool:
	if structure_kind in ["barricade", "abandoned_turret"]:
		return false
	return is_powered()

func _update_power_lamp() -> void:
	if _power_lamp_mat == null:
		return
	var on := power_lamp_on()
	_power_lamp_mat.emission_enabled = on
	_power_lamp_mat.emission = Color(0.3, 0.9, 0.5) if on else Color(0, 0, 0)
	_power_lamp_mat.emission_energy_multiplier = 1.6 if on else 0.0
	_power_lamp_mat.albedo_color = Color(0.3, 0.9, 0.5) if on else Color(0.15, 0.15, 0.15)

func setup(p_kind: String, pos: Vector3) -> void:
	structure_kind = p_kind
	position = pos
	match p_kind:
		"turret":
			max_hp = 90.0
		"mortar":
			max_hp = 100.0
		"emp_pylon":
			max_hp = 120.0
		"repair_station":
			max_hp = 100.0
		"generator":
			max_hp = 110.0; is_power_source = true
		"barricade":
			max_hp = 160.0
		"abandoned_turret":
			max_hp = 90.0
	hp = max_hp

func heal(amount: float) -> void:
	if is_dead_struct:
		return
	hp = minf(max_hp, hp + amount)

func take_damage(amount: float) -> void:
	if is_dead_struct:
		return
	hp -= amount
	if hp <= 0.0:
		is_dead_struct = true
		remove_from_group("structures")
		if is_power_source:
			remove_from_group("generators")
		queue_free()

func is_powered() -> bool:
	if structure_kind == "generator" or structure_kind == "barricade":
		return true
	# mortar, emp_pylon and repair_station draw power from the network
	# like turrets do
	var main = get_tree().get_first_node_in_group("main")
	if main and main.has_method("check_powered"):
		return main.check_powered(global_position)
	return false

func repair_tick(delta: float) -> void:
	# Pass 32: slow AoE structure repair, powered only. Heals every
	# other structure in radius, never itself — a station cannot
	# sustain itself, so placement still needs a real defense.
	if is_dead_struct or structure_kind != "repair_station" or not is_powered():
		return
	for s in get_tree().get_nodes_in_group("structures"):
		if not is_instance_valid(s) or s == self or s.get("is_dead_struct"):
			continue
		if global_position.distance_to(s.global_position) <= REPAIR_RADIUS:
			s.heal(REPAIR_RATE * delta)

func _ready() -> void:
	add_to_group("structures")
	if structure_kind == "generator":
		add_to_group("generators")
	_build_visuals()

func _build_visuals() -> void:
	# Pass 7: powered lamp on every powered structure kind.
	var lamp_y := 1.6
	match structure_kind:
		"mortar": lamp_y = 1.9
		"emp_pylon": lamp_y = 4.9
		"repair_station": lamp_y = 2.6
		"generator": lamp_y = 2.9
		"barricade": lamp_y = 1.9
	_power_lamp_mat = Factory.mat(Color(0.15, 0.15, 0.15), Color(0, 0, 0), 0.0, 0.1, 0.4)
	_power_lamp = Factory.sphere(self, 0.28, Vector3(0, lamp_y, 0), _power_lamp_mat)
	_update_power_lamp()
	match structure_kind:
		"turret", "abandoned_turret":
			var dead := structure_kind == "abandoned_turret"
			var base_mat := Factory.mat(Color(0.25,0.3,0.28) if not dead else Color(0.22,0.22,0.22), Color(0,0,0), 0.0, 0.4, 0.6)
			Factory.cyl(self, 1.1, 0.7, Vector3(0, 0.35, 0), base_mat, 12)
			_head = Node3D.new()
			_head.position = Vector3(0, 1.0, 0)
			add_child(_head)
			Factory.box(_head, Vector3(0.9, 0.5, 0.9), Vector3.ZERO, base_mat)
			Factory.box(_head, Vector3(0.22, 0.22, 1.5), Vector3(0, 0, -0.9), Factory.mat(Color(0.15,0.15,0.16), Color(0,0,0), 0.0, 0.5, 0.4))
			if not dead:
				Factory.box(_head, Vector3(0.5, 0.16, 0.2), Vector3(0, 0.35, 0), Factory.mat(Color(0.3,0.9,0.5), Color(0.3,0.9,0.5), 1.4, 0.1, 0.4))
		"generator":
			Factory.box(self, Vector3(2.2, 1.4, 2.2), Vector3(0, 0.7, 0), Factory.mat(Color(0.3,0.32,0.2), Color(0,0,0), 0.0, 0.4, 0.55))
			Factory.cyl(self, 0.7, 1.2, Vector3(0, 2.0, 0), Factory.mat(Color(1,0.8,0.3), Color(1,0.8,0.3), 1.6, 0.2, 0.4), 12)
			_power_ring = Factory.cyl(self, 22.0, 0.04, Vector3(0, 0.05, 0), Factory.mat_transparent(Color(1,0.85,0.3), 0.05, 0.5), 40)
		"mortar":
			# squat emplacement + angled launch tube + shell crate
			Factory.cyl(self, 1.3, 0.6, Vector3(0, 0.3, 0), Factory.mat(Color(0.3,0.28,0.24), Color(0,0,0), 0.0, 0.5, 0.6), 12)
			var tube := Node3D.new()
			tube.position = Vector3(0, 0.9, 0)
			tube.rotation.x = -0.7
			add_child(tube)
			_head = tube
			Factory.cyl(tube, 0.42, 2.2, Vector3(0, 1.0, 0), Factory.mat(Color(0.42,0.3,0.16), Color(1,0.5,0.15), 0.5, 0.5, 0.45), 10)
			Factory.box(self, Vector3(1.1, 0.7, 0.8), Vector3(1.6, 0.35, 0.4), Factory.mat(Color(0.36,0.32,0.22), Color(0,0,0), 0.0, 0.4, 0.7))
			Factory.box(self, Vector3(0.5, 0.14, 0.2), Vector3(0, 1.35, 0.9), Factory.mat(Color(1,0.5,0.2), Color(1,0.5,0.2), 1.4, 0.1, 0.4))
		"emp_pylon":
			# tall mast with a slowly rotating dish head
			Factory.cyl(self, 1.0, 0.5, Vector3(0, 0.25, 0), Factory.mat(Color(0.25,0.3,0.38), Color(0,0,0), 0.0, 0.5, 0.5), 12)
			Factory.cyl(self, 0.35, 3.4, Vector3(0, 2.1, 0), Factory.mat(Color(0.3,0.36,0.44), Color(0,0,0), 0.0, 0.5, 0.45), 8)
			_head = Node3D.new()
			_head.position = Vector3(0, 4.0, 0)
			add_child(_head)
			Factory.sphere(_head, 0.85, Vector3.ZERO, Factory.mat(Color(0.3,0.6,0.9), Color(0.35,0.7,1.0), 1.8, 0.1, 0.35))
			Factory.box(_head, Vector3(0.2, 0.2, 1.6), Vector3(0, 0, -0.8), Factory.mat(Color(0.2,0.24,0.3), Color(0,0,0), 0.0, 0.5, 0.5))
			Factory.cyl(self, EMP_RADIUS, 0.04, Vector3(0, 0.05, 0), Factory.mat_transparent(Color(0.35,0.75,1.0), 0.05, 0.5), 40)
		"barricade":
			Factory.box(self, Vector3(3.6, 1.6, 0.7), Vector3(0, 0.8, 0), Factory.mat(Color(0.35,0.3,0.22), Color(0,0,0), 0.0, 0.3, 0.7))
			Factory.box(self, Vector3(3.6, 0.25, 0.8), Vector3(0, 1.7, 0), Factory.mat(Color(1,0.6,0.2), Color(1,0.6,0.2), 0.7, 0.1, 0.5))
		"repair_station":
			# squat depot + mast with a slowly rotating green repair
			# emitter + ground ring showing the repair radius
			Factory.box(self, Vector3(2.4, 1.0, 2.4), Vector3(0, 0.5, 0), Factory.mat(Color(0.22,0.3,0.24), Color(0,0,0), 0.0, 0.4, 0.6))
			Factory.cyl(self, 0.3, 1.6, Vector3(0, 1.8, 0), Factory.mat(Color(0.3,0.36,0.34), Color(0,0,0), 0.0, 0.5, 0.45), 8)
			_head = Node3D.new()
			_head.position = Vector3(0, 2.6, 0)
			add_child(_head)
			Factory.sphere(_head, 0.55, Vector3.ZERO, Factory.mat(Color(0.3,0.9,0.5), Color(0.3,0.9,0.5), 1.6, 0.1, 0.35))
			Factory.cyl(self, REPAIR_RADIUS, 0.04, Vector3(0, 0.05, 0), Factory.mat_transparent(Color(0.3,0.9,0.5), 0.05, 0.5), 40)

func activate() -> void: # abandoned -> live turret
	if structure_kind == "abandoned_turret":
		structure_kind = "turret"
		# rebuild visuals simply: tint head light on by adding emissive box
		if _head:
			Factory.box(_head, Vector3(0.5, 0.16, 0.2), Vector3(0, 0.35, 0), Factory.mat(Color(0.3,0.9,0.5), Color(0.3,0.9,0.5), 1.4, 0.1, 0.4))
		_update_power_lamp()

func fire_mortar() -> bool:
	# Indirect AoE fire: lobs a shell at the nearest enemy in range (no LOS needed).
	if is_dead_struct or structure_kind != "mortar" or not is_powered():
		return false
	var best: Node = null
	var best_d := MORTAR_RANGE
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or e.get("is_dead") or e.get("is_disabled"):
			continue
		var d := global_position.distance_to(e.global_position)
		if d < best_d and d > MORTAR_MIN_RANGE:
			best_d = d; best = e
	if best == null:
		return false
	_fire_cd = MORTAR_CD
	var target: Vector3 = best.global_position
	var dir: Vector3 = target - global_position
	dir.y = 0.0
	var b: Node3D = BulletScript.take_from_pool() as Node3D
	if b == null:
		b = Node3D.new()
		b.set_script(BulletScript)
	b.position = global_position + Vector3(0, 2.6, 0)
	get_parent().add_child(b)
	b.setup(dir.normalized(), MORTAR_DMG, "Mortar", true, false, 26.0, MORTAR_AOE, 9.0, best_d / 26.0)
	if _head:
		_head.rotation.y = lerp_angle(_head.rotation.y, atan2(dir.x, dir.z), 8.0)
	return true

func fire_emp() -> bool:
	# Periodic disable pulse: stuns (non-lethal) everything in radius.
	if is_dead_struct or structure_kind != "emp_pylon" or not is_powered():
		return false
	_emp_cd = EMP_CD
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and not e.get("is_dead") and global_position.distance_to(e.global_position) <= EMP_RADIUS:
			if e.has_method("stun"):
				e.stun(EMP_STUN)
	_spawn_pulse_fx(EMP_RADIUS)
	return true

func _spawn_pulse_fx(radius: float) -> void:
	var fx := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 0.5
	cm.radial_segments = 40
	fx.mesh = cm
	fx.position = global_position + Vector3(0, 0.3, 0)
	fx.set_surface_override_material(0, Factory.mat_transparent(Color(0.4, 0.8, 1.0), 0.5, 1.2))
	get_parent().add_child(fx)
	var tw := fx.create_tween()
	tw.set_parallel(true)
	tw.tween_property(fx, "scale", Vector3(radius, 1.0, radius), 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(fx, "transparency", 1.0, 0.6)
	tw.chain().tween_callback(fx.queue_free)

func _process(delta: float) -> void:
	if is_dead_struct or structure_kind == "generator" or structure_kind == "barricade" or structure_kind == "abandoned_turret":
		return
	_update_power_lamp()
	if structure_kind == "mortar":
		_fire_cd = maxf(0.0, _fire_cd - delta)
		if is_powered() and _fire_cd <= 0.0:
			fire_mortar()
		return
	if structure_kind == "emp_pylon":
		_emp_cd = maxf(0.0, _emp_cd - delta)
		if _head:
			_head.rotation.y += delta * 1.2
		if is_powered() and _emp_cd <= 0.0:
			fire_emp()
		return
	if structure_kind == "repair_station":
		if _head:
			_head.rotation.y += delta * 0.8
		if is_powered():
			repair_tick(delta)
		return
	_fire_cd = maxf(0.0, _fire_cd - delta)
	if not is_powered():
		return
	# find nearest enemy
	var best: Node = null
	var best_d := 32.0
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or e.get("is_dead") or e.get("is_disabled"):
			continue
		var d := global_position.distance_to(e.global_position)
		if d < best_d:
			best_d = d; best = e
	if best == null:
		return
	if _head:
		var dir: Vector3 = best.global_position - global_position
		dir.y = 0.0
		_head.rotation.y = lerp_angle(_head.rotation.y, atan2(dir.x, dir.z) + PI, 14.0 * delta)
	if _fire_cd <= 0.0:
		_fire_cd = 0.38
		var dir2: Vector3 = best.global_position - global_position
		dir2.y = 0.0
		var b: Node3D = BulletScript.take_from_pool() as Node3D
		if b == null:
			b = Node3D.new()
			b.set_script(BulletScript)
		b.position = global_position + dir2.normalized() * 1.4 + Vector3(0, 1.1, 0)
		get_parent().add_child(b)
		b.setup(dir2.normalized(), 8.0, "Turret", true, false, 55.0)
