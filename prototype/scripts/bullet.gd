extends Node3D

## Manual-integration projectile: no physics bodies, distance checks vs groups.

var dir: Vector3 = Vector3.FORWARD
# Pass 45 (Region 2 dust storm): lateral wind push, snapshotted from
# main.storm_wind_drift() at setup() so a shot keeps the wind it was
# fired under even if the storm state changes mid-flight. ZERO when
# no storm is active (or no main node exists, e.g. unit tests that
# build bullets outside the tree).
var wind_drift: Vector3 = Vector3.ZERO
var speed: float = 55.0
var damage: float = 10.0
var weapon_name: String = "Autocannon"
var from_player_side: bool = true # player/turret vs enemy
# Pass 42: true only for bullets the player MECH fired (turret and
# mortar bullets also have from_player_side true, but must not count
# toward the mech's end-panel stats). Set by player.gd's _fire.
var from_player_mech: bool = false
var _p42_hit_counted: bool = false
var pierce: bool = false
var life: float = 2.2
var shooter_pos: Vector3 = Vector3.ZERO
var _hit_ids: Dictionary = {}
# Pass 19 (PERF): bullet pool — detached nodes are kept in a static free
# list instead of freed, so a shot costs a re-add, not a Node3D + mesh
# allocation. _active gates _process so a pooled bullet sitting between
# add_child and setup (e.g. the Flak test's awaited frame) never moves or
# detonates on stale state; setup() is what re-arms it.
var _active: bool = false
static var _free_pool: Array = []
static var _pool_created: int = 0
static var _pool_reused: int = 0
static var _pool_released: int = 0

static func take_from_pool() -> Node:
	if _free_pool.is_empty():
		return null
	_pool_reused += 1
	return _free_pool.pop_back()

static func pool_stats() -> Dictionary:
	# No "active" key on purpose: created counts every bullet ever
	# _ready'd, including ones an external queue_free later destroyed,
	# so created-minus-free would overstate live bullets. The three
	# counters + free size are the honest, directly counted numbers.
	return {"created": _pool_created, "reused": _pool_reused, "released": _pool_released, "free": _free_pool.size()}

func release_to_pool() -> void:
	if not _active:
		return
	_active = false
	_pool_released += 1
	var p := get_parent()
	if p != null:
		p.remove_child(self)
	if not _free_pool.has(self):
		_free_pool.append(self)
# Pass 1 (Wave 3): mortar shells fly an arc and detonate an AoE blast.
var aoe: float = 0.0
# Pass 10: proximity fuse radius for the Flak Cannon (0 = direct-hit only).
var prox_radius: float = 0.0
# Pass 21: Tesla Arc chain — jumps remaining + max jump range (0 = no chain).
var chain_jumps: int = 0
var chain_range: float = 0.0
var arc_height: float = 0.0
var _arc_dur: float = 0.9
var _arc_t: float = 0.0
var _arc_start: Vector3 = Vector3.ZERO
var _arc_end: Vector3 = Vector3.ZERO
var _arc_init: bool = false

func setup(p_dir: Vector3, p_damage: float, p_weapon: String, p_player_side: bool, p_pierce: bool = false, p_speed: float = 55.0, p_aoe: float = 0.0, p_arc_height: float = 0.0, p_arc_dur: float = 0.9, p_prox_radius: float = 0.0, p_chain_jumps: int = 0, p_chain_range: float = 0.0, p_from_player_mech: bool = false) -> void:
	dir = p_dir.normalized()
	damage = p_damage
	weapon_name = p_weapon
	from_player_side = p_player_side
	from_player_mech = p_from_player_mech
	_p42_hit_counted = false
	pierce = p_pierce
	speed = p_speed
	shooter_pos = global_position
	aoe = p_aoe
	prox_radius = p_prox_radius
	chain_jumps = p_chain_jumps
	chain_range = p_chain_range
	arc_height = p_arc_height
	_arc_dur = p_arc_dur
	# Pass 19: full state reset — a reused bullet must not carry a previous
	# shot's pierce hits, arc progress, or lifetime.
	life = 2.2
	_hit_ids.clear()
	_arc_t = 0.0
	_arc_init = false
	# Pass 45: snapshot the storm wind now — pooled reuse must not
	# carry a previous shot's drift into calm air, or vice versa.
	wind_drift = Vector3.ZERO
	if is_inside_tree():
		var _m = get_tree().get_first_node_in_group("main")
		if _m and _m.has_method("storm_wind_drift"):
			wind_drift = _m.storm_wind_drift()
	_active = true
	visible = true
	set_process(true)
	if is_inside_tree() and dir.length() > 0.01:
		look_at(global_position + dir, Vector3.UP)

func _ready() -> void:
	_pool_created += 1
	_active = true
	var col := Color(1.0, 0.75, 0.3) if from_player_side else Color(1.0, 0.3, 0.3)
	if weapon_name == "Scattergun":
		col = Color(1.0, 0.55, 0.25)
	if weapon_name == "Railgun":
		col = Color(0.4, 0.85, 1.0)
	if weapon_name == "Flak Cannon":
		col = Color(1.0, 0.65, 0.2)
	if weapon_name == "Tesla Arc":
		col = Color(0.45, 0.9, 1.0)
		Factory.sphere(self, 0.3, Vector3.ZERO, Factory.mat(col, col, 2.2, 0.0, 0.3))
	elif weapon_name == "Grenade Launcher":
		col = Color(0.55, 1.0, 0.3)
		Factory.sphere(self, 0.32, Vector3.ZERO, Factory.mat(col, col, 2.2, 0.0, 0.3))
	elif weapon_name == "Mortar":
		col = Color(1.0, 0.5, 0.2)
		Factory.sphere(self, 0.35, Vector3.ZERO, Factory.mat(col, col, 2.4, 0.0, 0.3))
	elif weapon_name == "Railgun":
		Factory.box(self, Vector3(0.22, 0.22, 1.6), Vector3.ZERO, Factory.mat(col, col, 2.5, 0.0, 0.3))
	else:
		Factory.sphere(self, 0.22, Vector3.ZERO, Factory.mat(col, col, 2.2, 0.0, 0.3))
	if dir.length() > 0.01:
		look_at(global_position + dir, Vector3.UP)

# Pass 42: one bullet counts at most ONE hit toward accuracy, however
# many enemies it damages (AoE victims, chain jumps, pierce-throughs
# all add damage but no extra hit) — so accuracy is shots that struck
# at least one enemy / shots fired, never over 100%. Destructible-only
# hits never count: accuracy is measured against enemies. Damage is
# the nominal amount handed to take_damage, before armor/shield
# mitigation, so the panel's "damage dealt" matches what the player
# fired, not the bleed-through that survived a shield.
func _p42_note_enemy_hit(delivered: float) -> void:
	if not from_player_mech:
		return
	var first := not _p42_hit_counted
	_p42_hit_counted = true
	var main_e = get_tree().get_first_node_in_group("main")
	if main_e and main_e.has_method("record_player_bullet_damage"):
		main_e.record_player_bullet_damage(delivered, first)

# Pass 21: Tesla Arc chain — from the struck enemy, jump to the nearest
# not-yet-hit enemy within chain_range, up to chain_jumps times, at
# 75% then 50% damage. A target already hit (primary or chain) is never
# struck twice, and the chain stops when nothing is in range. Positions
# are captured before take_damage because a killing blow frees the node.
func _arc_chain(from_pos: Vector3) -> void:
	var cur := from_pos
	var factors := [0.75, 0.5]
	for j in range(chain_jumps):
		var best: Node = null
		var best_d := chain_range + 0.001
		for cand in get_tree().get_nodes_in_group("enemies"):
			if not is_instance_valid(cand) or cand.get("is_dead"):
				continue
			if _hit_ids.has(cand.get_instance_id()):
				continue
			var dd: Vector3 = cand.global_position - cur
			dd.y = 0.0
			if dd.length() <= chain_range and dd.length() < best_d:
				best_d = dd.length()
				best = cand
		if best == null:
			break
		var bpos: Vector3 = best.global_position
		var bdir: Vector3 = bpos - cur
		bdir.y = 0.0
		bdir = bdir.normalized() if bdir.length() > 0.01 else Vector3(0, 0, -1)
		_hit_ids[best.get_instance_id()] = true
		var f: float = factors[j] if j < factors.size() else 0.5
		_p42_note_enemy_hit(damage * f)
		best.take_damage(damage * f, bdir, weapon_name)
		cur = bpos

func _explode() -> void:
	# brief flash ring at the impact point
	var fx := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	fx.mesh = sm
	fx.position = global_position
	fx.set_surface_override_material(0, Factory.mat_transparent(Color(1.0, 0.6, 0.25), 0.6, 1.6))
	get_parent().add_child(fx)
	var tw := fx.create_tween()
	tw.set_parallel(true)
	tw.tween_property(fx, "scale", Vector3.ONE * maxf(aoe, 1.0), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(fx, "transparency", 1.0, 0.35)
	tw.chain().tween_callback(fx.queue_free)
	if from_player_side:
		for e in get_tree().get_nodes_in_group("enemies"):
			if not is_instance_valid(e) or e.get("is_dead"):
				continue
			var d: Vector3 = e.global_position - global_position
			d.y = 0.0
			var dist := d.length()
			if dist <= aoe:
				var falloff := 1.0 - 0.5 * (dist / aoe)
				var hit_dir := d.normalized() if dist > 0.01 else Vector3(0, 0, -1)
				_p42_note_enemy_hit(damage * falloff)
				e.take_damage(damage * falloff, hit_dir, weapon_name)
		# Pass 30: AoE blasts break destructibles in radius too.
		var main_e = get_tree().get_first_node_in_group("main")
		if main_e and main_e.has_method("damage_destructible"):
			for d in get_tree().get_nodes_in_group("destructibles"):
				if not is_instance_valid(d) or bool(d.get_meta("destructible_broken", false)):
					continue
				var dd2: Vector3 = d.global_position - global_position
				dd2.y = 0.0
				if dd2.length() <= aoe:
					main_e.damage_destructible(d, damage)
	release_to_pool()

func _process(delta: float) -> void:
	# Pass 10: never re-detonate after _explode() queued this shell — a
	# manually stepped shell in the test (or a double engine tick) must not
	# apply the AoE blast twice.
	if is_queued_for_deletion():
		return
	# Pass 19: pooled (inactive) bullets never move, collide, or detonate.
	if not _active:
		return
	if arc_height > 0.0:
		# arcing shell: parabolic flight to the target point, no mid-flight collisions
		if not _arc_init:
			_arc_init = true
			_arc_start = global_position
			var flat := dir
			flat.y = 0.0
			flat = flat.normalized() if flat.length() > 0.01 else Vector3(0, 0, -1)
			_arc_end = _arc_start + Vector3(flat.x, 0, flat.z) * speed * _arc_dur
			# Pass 45: wind pushes the mortar's landing point, same
			# drift-over-flight-time as straight shots accumulate.
			_arc_end += wind_drift * _arc_dur
		_arc_t += delta
		var k := minf(1.0, _arc_t / _arc_dur)
		global_position = _arc_start.lerp(_arc_end, k) + Vector3(0, sin(k * PI) * arc_height, 0)
		if k >= 1.0:
			_explode()
			return
		life -= delta
		if life <= 0.0:
			release_to_pool()
		return
	# Pass 45: straight flight carries the wind drift alongside the
	# aimed velocity — the drift is lateral, never a speed boost.
	global_position += (dir * speed + wind_drift) * delta
	life -= delta
	if life <= 0.0:
		release_to_pool()
		return
	if from_player_side:
		for e in get_tree().get_nodes_in_group("enemies"):
			if not is_instance_valid(e) or e.get("is_dead"):
				continue
			var d: Vector3 = e.global_position - global_position
			d.y = 0.0
			var r: float = 2.6 if e.get("kind") == "siege" else 1.7
			# Pass 10: Flak Cannon proximity fuse — detonate the AoE blast
			# when any enemy comes within the fuse radius (or on direct hit
			# for AoE shells), instead of dealing single-target damage.
			if aoe > 0.0 and d.length() <= maxf(prox_radius, r):
				_explode()
				return
			if d.length() < r:
				var eid: int = e.get_instance_id()
				if _hit_ids.has(eid):
					continue
				_hit_ids[eid] = true
				var hit_dir: Vector3 = shooter_pos - e.global_position
				hit_dir.y = 0.0
				hit_dir = hit_dir.normalized() if hit_dir.length() > 0.01 else -dir
				# Pass 21: capture the struck position before the blow,
				# so the chain origin survives a killing hit.
				var struck_pos: Vector3 = e.global_position
				_p42_note_enemy_hit(damage)
				e.take_damage(damage, hit_dir, weapon_name)
				if weapon_name == "Tesla Arc" and chain_jumps > 0:
					_arc_chain(struck_pos)
				if not pierce:
					release_to_pool()
					return
		# Pass 30: player-side bullets break destructibles on contact
		# (enemies are checked first, so a shot never passes through
		# an enemy to break a crate behind it).
		for d in get_tree().get_nodes_in_group("destructibles"):
			if not is_instance_valid(d) or bool(d.get_meta("destructible_broken", false)):
				continue
			var dd: Vector3 = d.global_position - global_position
			dd.y = 0.0
			var rr: float = float(d.get_meta("destructible_radius", 1.9))
			if aoe > 0.0 and dd.length() <= maxf(prox_radius, rr):
				_explode()
				return
			if dd.length() < rr:
				var main2 = get_tree().get_first_node_in_group("main")
				if main2 and main2.has_method("damage_destructible"):
					main2.damage_destructible(d, damage)
				if not pierce:
					release_to_pool()
					return
	else:
		var main = get_tree().get_first_node_in_group("main")
		# hit player
		var p = get_tree().get_first_node_in_group("player")
		if p and is_instance_valid(p):
			var dp: Vector3 = p.global_position - global_position
			dp.y = 0.0
			if dp.length() < 1.8:
				p.take_damage(damage)
				release_to_pool()
				return
		# hit core (handled as main damage when very close to center)
		var dc: Vector3 = global_position
		dc.y = 0.0
		if dc.length() < 3.4:
			if main and main.has_method("take_core_damage"):
				main.take_core_damage(damage)
			release_to_pool()
			return
		# hit structures
		for s in get_tree().get_nodes_in_group("structures"):
			if not is_instance_valid(s):
				continue
			var ds: Vector3 = s.global_position - global_position
			ds.y = 0.0
			if ds.length() < 2.0 and s.has_method("take_damage"):
				s.take_damage(damage)
				release_to_pool()
				return
