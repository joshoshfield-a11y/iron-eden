extends Node3D

signal died(enemy, salvage_value: int, weapon_name: String)

const BulletScript := preload("res://scripts/bullet.gd")

var kind: String = "scout"
var max_hp: float = 30.0
var hp: float = 30.0
var speed: float = 6.5
var dmg: float = 6.0
var salvage_value: int = 12
var core_position: Vector3 = Vector3.ZERO
var on_core_damage: Callable
var is_dead: bool = false
var is_disabled: bool = false
var _disabled_timer: float = 0.0
# Pass 1 (Wave 3): EMP stun is NON-lethal — pauses the unit, then it recovers.
var is_stunned: bool = false
var _stun_timer: float = 0.0
var _stun_fx: Node3D = null
# Pass 1 (Wave 3): shield-heavy frontal energy shield pool + regen.
var shield_max: float = 0.0
var shield_hp: float = 0.0
var _shield_regen_cd: float = 0.0
var _shield_panel: MeshInstance3D = null
var _attack_cd: float = 0.0
var _shoot_cd: float = 2.0
# Pass 22 (Lancer): telegraphed charge state machine. chase -> telegraph
# (0.8 s, stationary, ground line shows the charge lane) -> charge
# (22 m/s along the locked direction, one hit) -> chase with a 3 s
# cooldown. The charge hit is the ONLY damage a lancer deals: in melee
# range during cooldown it holds position instead of brawling, so every
# lancer hit is one the player saw coming.
var lancer_state: String = "chase"
var _lancer_timer: float = 0.0
var _lancer_cd: float = 0.0
var _lancer_dir: Vector3 = Vector3.ZERO
var _lancer_target: Node = null
var _lancer_target_pos: Vector3 = Vector3.ZERO
var _lancer_telegraph: Node3D = null
var _last_weapon: String = ""
var _comp_damaged_announced: bool = false
# Pass 5 audit fix (H2): the old _flash_disabled only retextured direct
# MeshInstance3D children of _body. Sprite enemies (scout/heavy/shield_heavy)
# carry their art one level deeper in a holder Node3D, so they showed NO
# disabled state at all — a capture target was indistinguishable from a live
# one. Every disabled enemy now also gets an orange containment marker, the
# same visual language as the EMP stun bubble, so the state reads on any art.
var _disabled_fx: Node3D = null
var suppress_loot: bool = false
# Pass 34 (template top-down units): the unit sprite is a flat
# ground-plane holder, not a billboard. Pass 18 (UX): hit-flash state —
# timer + the quad material it tints (albedo multiplies the texture, so
# a red albedo reads as a flash and white reads as normal).
var hit_flash_t: float = 0.0
var _sprite: Node3D = null
var _td_mat: StandardMaterial3D = null
var _body: Node3D
# Pass 7 (Overhaul A): color code — enemies red/orange.
var trim_color: Color = Color(1.0, 0.25, 0.2)
var _health_ring: MeshInstance3D = null
var _health_ring_mat: StandardMaterial3D = null
var _ring_band: int = -1
var _shield_mat: StandardMaterial3D = null
# Pass 35 (real frame walk cycles): same 4-frame walk holder as the
# player (p35 stride frames). anim_phase advances only while the unit
# actually displaced this frame; anim_frame is the cycled texture index
# (0 at rest). The holder never bobs or scales — Pass 28's bob is gone.
var anim_phase: float = 0.0
var anim_idle_t: float = 0.0
var anim_moving: bool = false
var anim_frame: int = 0
var _sprite_base_y: float = 0.0
var _anim_frame_pos: Vector3 = Vector3.ZERO

func _apply_anim(delta: float, moving: bool) -> void:
	if _sprite == null:
		return
	anim_moving = moving
	anim_idle_t += delta
	if moving:
		anim_phase += delta * (4.0 + speed * 0.55)
		anim_frame = SpriteUtil.walk_frame_index(anim_phase)
	else:
		anim_frame = 0
	SpriteUtil.set_walk_frame(_sprite, anim_frame)
	_sprite.position.y = _sprite_base_y
	_sprite.scale = Vector3.ONE

func _update_health_ring() -> void:
	if _health_ring_mat == null:
		return
	var frac := hp / max_hp if max_hp > 0.0 else 0.0
	var band := 0 if frac > 0.5 else (1 if frac > 0.25 else 2)
	if band == _ring_band:
		return
	_ring_band = band
	var c := Color(0.3, 0.9, 0.5) if band == 0 else (Color(1.0, 0.7, 0.2) if band == 1 else Color(1.0, 0.25, 0.2))
	var cc := c
	cc.a = 0.95
	_health_ring_mat.albedo_color = cc

func setup(p_kind: String, hp_scale: float, pos: Vector3) -> void:
	kind = p_kind
	position = pos
	match kind:
		"scout":
			max_hp = 30.0 * hp_scale; speed = 7.5; dmg = 5.0; salvage_value = 12
		"heavy":
			max_hp = 130.0 * hp_scale; speed = 3.4; dmg = 12.0; salvage_value = 30
		"burrower":
			max_hp = 45.0 * hp_scale; speed = 6.0; dmg = 8.0; salvage_value = 18
		# Pass 14: Sapper Drone — fast, fragile, and its dmg IS its blast:
		# it detonates on reaching a structure instead of melee-attacking.
		"sapper":
			max_hp = 20.0 * hp_scale; speed = 10.5; dmg = 35.0; salvage_value = 15
		# Pass 22: Lancer — mid-HP, scout-fast, and dmg IS its charge hit.
		"lancer":
			max_hp = 70.0 * hp_scale; speed = 7.0; dmg = 22.0; salvage_value = 25
		"shield_heavy":
			max_hp = 150.0 * hp_scale; speed = 3.0; dmg = 14.0; salvage_value = 45
			shield_max = 90.0; shield_hp = 90.0
		# Pass 41 (Bulwark): the wall — slower than a shield heavy,
		# a much bigger frontal shield pool, and a genuinely weak
		# rear core (2.0x damage, vs 1.5x for other armored kinds),
		# so flanking it is the answer, not head-on DPS.
		"bulwark":
			max_hp = 220.0 * hp_scale; speed = 1.8; dmg = 16.0; salvage_value = 60
			shield_max = 160.0; shield_hp = 160.0
		"siege":
			max_hp = 8.0 * 130.0 * hp_scale; speed = 1.6; dmg = 20.0; salvage_value = 120
	hp = max_hp

func get_facing() -> Vector3:
	var f := -global_transform.basis.z
	f.y = 0.0
	return f.normalized() if f.length() > 0.01 else Vector3(0, 0, 1)

func take_damage(amount: float, hit_dir: Vector3, weapon_name: String) -> float:
	if is_dead:
		return 0.0
	_last_weapon = weapon_name
	var has_dir := hit_dir.length() > 0.01
	var facing_d := get_facing().dot(hit_dir.normalized()) if has_dir else 0.0
	var actual: float
	# shield-heavy / bulwark frontal energy shield: absorbs almost
	# everything while up, then falls back to normal plate armor.
	# Rear always exposed.
	if (kind == "shield_heavy" or kind == "bulwark") and facing_d > 0.5 and shield_hp > 0.0:
		shield_hp = maxf(0.0, shield_hp - amount)
		_shield_regen_cd = 4.0
		actual = amount * 0.1 # 10% bleed-through
		_update_shield_visual()
	else:
		var factor: float = 1.0
		if kind == "bulwark":
			# Pass 41: weak rear core — rear hits deal double.
			if facing_d > 0.5:
				factor = 0.35 # front armor
			elif facing_d < -0.5:
				factor = 2.0 # rear core exposed
		elif kind == "heavy" or kind == "siege" or kind == "shield_heavy":
			if facing_d > 0.5:
				factor = 0.35 # front armor
			elif facing_d < -0.5:
				factor = 1.5 # rear exposed
		actual = amount * factor
	hp -= actual
	_update_health_ring()
	# Pass 18 (UX): hit-flash — red-tint the unit quad for 0.12 s so a
	# landed shot reads instantly, even on a small phone screen. The
	# tint clears in _process; a killing blow skips it (the unit is freed).
	if hp > 0.0:
		hit_flash_t = 0.12
		_apply_hit_flash()
	if hp <= 0.0:
		_die()
	elif hp <= max_hp * 0.15 and not is_disabled:
		is_disabled = true
		_disabled_timer = 4.0
		_flash_disabled()
	return actual

func stun(dur: float) -> void:
	# Non-lethal EMP stun: the unit stops, then recovers on its own.
	if is_dead or is_disabled:
		return
	is_stunned = true
	_stun_timer = maxf(_stun_timer, dur)
	if _stun_fx == null and _body:
		_stun_fx = Node3D.new()
		_body.add_child(_stun_fx)
		Factory.sphere(_stun_fx, 2.4, Vector3(0, 1.2, 0), Factory.mat_transparent(Color(0.4, 0.85, 1.0), 0.28, 1.0))

func _update_shield_visual() -> void:
	if _shield_panel:
		_shield_panel.visible = shield_hp > 0.0
	# Pass 7: shield panel opacity tracks shield HP (full = solid, breaking = faint).
	if _shield_mat != null and shield_max > 0.0:
		var c := _shield_mat.albedo_color
		c.a = 0.12 + 0.30 * (shield_hp / shield_max)
		_shield_mat.albedo_color = c

func _flash_disabled() -> void:
	if _body:
		for c in _body.get_children():
			if c is MeshInstance3D:
				c.set_surface_override_material(0, Factory.mat(Color(0.35,0.35,0.38), Color(1,0.6,0.2), 0.7, 0.2, 0.8))
	if _body and _disabled_fx == null:
		_disabled_fx = Node3D.new()
		_body.add_child(_disabled_fx)
		Factory.sphere(_disabled_fx, 2.4, Vector3(0, 1.2, 0), Factory.mat_transparent(Color(1.0, 0.6, 0.2), 0.30, 1.0))

func capture_value() -> int:
	return int(float(salvage_value) * 2.5) # +150% bonus over normal scrap

func _die() -> void:
	if is_dead:
		return
	is_dead = true
	if not suppress_loot:
		died.emit(self, salvage_value, _last_weapon)
	queue_free()

func die_silent() -> void:
	suppress_loot = true
	is_dead = true
	queue_free()

func _ready() -> void:
	add_to_group("enemies")
	_body = Node3D.new()
	add_child(_body)
	# Pass 34 (template top-down units): every kind is a true top-down
	# frame sliced from the user's Game Assets Template (p34) and laid
	# flat on the ground, distinct silhouette per class, with a ground
	# facing chevron and a health ring. This supersedes the Pass 7
	# billboard presentation for units (correct for front-view art, wrong
	# for top-down art). No primitive fallback — a missing slice fails
	# the test instead of shipping boxes. forward_m is the PRE-scale
	# length (topdown_sprite applies UNIT_SCALE itself), so rendered
	# lengths match the old billboard heights exactly.
	var path := "res://sprites/p34/p34_enemy_swarm_green.png"
	var forward_m := 3.4
	var ring_r := 1.7
	var shield_scale := 1.0
	match kind:
		"scout":
			path = "res://sprites/p34/p34_enemy_swarm_green.png"; forward_m = 3.4; ring_r = 1.7
			trim_color = Color(1.0, 0.45, 0.2)
		"heavy":
			path = "res://sprites/p34/p34_enemy_tank.png"; forward_m = 4.6; ring_r = 2.3
			trim_color = Color(1.0, 0.2, 0.2)
		"shield_heavy":
			path = "res://sprites/p34/p34_enemy_artillery.png"; forward_m = 4.6; ring_r = 2.3
			trim_color = Color(1.0, 0.25, 0.25)
		# Pass 41 (Bulwark): the tank frame at bulwark scale — the
		# biggest ground footprint short of the siege boss, with a
		# 1.45x shield panel to match. Deliberately NOT added to the
		# Pass 34 generic kind loops: those assert seven distinct
		# frames, and the bulwark shares the tank frame with the
		# heavy (its distinction is scale + shield panel + stats).
		"bulwark":
			path = "res://sprites/p34/p34_enemy_tank.png"; forward_m = 5.8; ring_r = 2.9
			trim_color = Color(1.0, 0.12, 0.12)
			shield_scale = 1.45
		"burrower":
			path = "res://sprites/p34/p34_enemy_spiky.png"; forward_m = 3.6; ring_r = 1.8
			trim_color = Color(0.9, 0.3, 0.3)
		"sapper":
			# Pass 34: the template's Coordinated-drone pair cell, kept
			# whole (a rectangular split would slice a drone in half) —
			# two coordinated drones flying as one sapper unit.
			path = "res://sprites/p34/p34_enemy_drone.png"; forward_m = 3.0; ring_r = 1.5
			trim_color = Color(1.0, 0.4, 0.15)
		"lancer":
			# Pass 34: the template's STRIDER chassis frame — legged,
			# fast-looking, the right read for a charging lancer.
			path = "res://sprites/p34/p34_enemy_strider.png"; forward_m = 4.2; ring_r = 2.1
			trim_color = Color(1.0, 0.35, 0.15)
		"siege":
			# Pass 34: the template's Directorate Siege Platform boss
			# cell replaces the Pass 13 generated slice, same 9.0 length.
			path = "res://sprites/p34/p34_enemy_siege.png"; forward_m = 9.0; ring_r = 4.5
			trim_color = Color(0.9, 0.2, 0.3)
	var spr := SpriteUtil.topdown_walk_sprite(path, forward_m)
	if spr != null:
		_sprite = spr
		_sprite_base_y = spr.position.y
		anim_frame = 0
		var _td_quad := SpriteUtil.topdown_quad(spr)
		if _td_quad != null:
			_td_mat = _td_quad.get_surface_override_material(0) as StandardMaterial3D
		_body.add_child(spr)
	# Pass 12: ring + chevron scale with the billboard, so the ground
	# footprint still matches the bigger sprite.
	SpriteUtil.facing_chevron(_body, ring_r * SpriteUtil.UNIT_SCALE, 1.1, trim_color)
	_health_ring = SpriteUtil.ground_ring(_body, ring_r * SpriteUtil.UNIT_SCALE, Color(0.3, 0.9, 0.5))
	_health_ring_mat = _health_ring.get_surface_override_material(0) as StandardMaterial3D
	_update_health_ring()
	if kind == "shield_heavy" or kind == "bulwark":
		_add_shield_panel(shield_scale)
	_finish_ready()

func _add_shield_panel(scale_f: float = 1.0) -> void:
	# translucent frontal energy shield on the -Z (forward) face
	# Pass 12: panel scales with the billboard so it still covers the sprite.
	# Pass 41: bulwark passes 1.45 for its bigger frame.
	_shield_mat = Factory.mat_transparent(Color(0.35, 0.8, 1.0), 0.35, 1.2)
	_shield_panel = Factory.box(_body, Vector3(3.8, 2.6, 0.3) * SpriteUtil.UNIT_SCALE * scale_f, Vector3(0, 1.5, -2.3) * SpriteUtil.UNIT_SCALE * scale_f, _shield_mat)
	_update_shield_visual()

func _finish_ready() -> void:
	if global_position.distance_to(core_position) > 1.0:
		look_at(core_position + Vector3(0, 0, 0.01), Vector3.UP)

func _apply_hit_flash() -> void:
	if _td_mat != null:
		# Pass 34: albedo multiplies the quad texture — red = flash, white = normal.
		_td_mat.albedo_color = Color(1.0, 0.35, 0.35) if hit_flash_t > 0.0 else Color.WHITE

func _set_lancer_telegraph(show: bool) -> void:
	# Ground lane marking the charge path: a thin red strip on the
	# -Z (forward) side of the body, so it rotates with the facing.
	# Created lazily on first trigger; freed with the enemy.
	if _lancer_telegraph == null and _body != null:
		_lancer_telegraph = Node3D.new()
		_lancer_telegraph.name = "lancer_telegraph"
		var mi := Factory.box(_lancer_telegraph, Vector3(1.0, 0.12, 20.0), Vector3(0, 0.12, -10.0), Factory.mat_transparent(Color(1.0, 0.2, 0.15), 0.35, 0.8))
		mi.name = "telegraph_lane"
		_body.add_child(_lancer_telegraph)
	if _lancer_telegraph != null:
		_lancer_telegraph.visible = show

func _process(delta: float) -> void:
	if is_dead:
		return
	_anim_frame_pos = global_position
	# Pass 18 (UX): flash decay runs before every early return below
	# (disabled/stunned), so a flashed unit always clears its tint.
	if hit_flash_t > 0.0:
		hit_flash_t = maxf(0.0, hit_flash_t - delta)
		_apply_hit_flash()
	if is_disabled:
		_disabled_timer -= delta
		if _disabled_timer <= 0.0:
			_die() # explodes for normal scrap
		_apply_anim(delta, false)
		return
	if is_stunned:
		# EMP stun: frozen in place, recovers on its own — non-lethal
		_stun_timer -= delta
		if _stun_timer <= 0.0:
			is_stunned = false
			if is_instance_valid(_stun_fx):
				_stun_fx.queue_free()
			_stun_fx = null
			_apply_anim(delta, false)
			return
		_apply_anim(delta, false)
		return
	# Pass 22 (Lancer): telegraphed charge state machine. Stun/disabled
	# already returned above, so a stunned lancer freezes mid-telegraph.
	if kind == "lancer":
		_lancer_cd = maxf(0.0, _lancer_cd - delta)
		if lancer_state == "telegraph":
			var tp := _lancer_target_pos
			if is_instance_valid(_lancer_target):
				tp = _lancer_target.global_position
			var td := tp - global_position
			td.y = 0.0
			if td.length() > 0.5:
				look_at(global_position + td, Vector3.UP)
			_lancer_timer -= delta
			if _lancer_timer <= 0.0:
				# Lock the charge direction at windup end, toward the
				# target's position at that moment.
				var ld := tp - global_position
				ld.y = 0.0
				_lancer_dir = ld.normalized() if ld.length() > 0.01 else get_facing()
				_lancer_timer = clampf(ld.length(), 6.0, 20.0) / 22.0
				lancer_state = "charge"
				_set_lancer_telegraph(false)
			_apply_anim(delta, false)
			return
		if lancer_state == "charge":
			_lancer_timer -= delta
			global_position += _lancer_dir * 22.0 * delta
			var hit := false
			if is_instance_valid(_lancer_target):
				if global_position.distance_to(_lancer_target.global_position) <= 2.8:
					if _lancer_target.has_method("take_damage"):
						_lancer_target.take_damage(dmg)
					hit = true
			elif global_position.distance_to(core_position) <= 2.8:
				if on_core_damage.is_valid():
					on_core_damage.call(dmg)
				hit = true
			if hit or _lancer_timer <= 0.0:
				lancer_state = "chase"
				_lancer_cd = 3.0
				_set_lancer_telegraph(false)
			_apply_anim(delta, true)
			return
		# chase: trigger a telegraph when a target is within charge
		# range (player first, else the core) and the cooldown is ready.
		if _lancer_cd <= 0.0:
			var pl = get_tree().get_first_node_in_group("player")
			var tgt: Node = null
			var tpos := core_position
			var in_range := false
			if pl and global_position.distance_to(pl.global_position) <= 18.0:
				tgt = pl; tpos = pl.global_position; in_range = true
			elif global_position.distance_to(core_position) <= 18.0:
				tpos = core_position; in_range = true
			if in_range:
				_lancer_target = tgt
				_lancer_target_pos = tpos
				lancer_state = "telegraph"
				_lancer_timer = 0.8
				var fd := tpos - global_position
				fd.y = 0.0
				if fd.length() > 0.5:
					look_at(global_position + fd, Vector3.UP)
				_set_lancer_telegraph(true)
				return
		# Otherwise fall through to the generic chase below; the generic
		# melee branch is lancer-guarded, so a cooling-down lancer holds
		# position instead of brawling.
	# shield-heavy / bulwark shield regen: 4s after the last frontal
	# hit, 12/s back to full
	if (kind == "shield_heavy" or kind == "bulwark") and shield_hp < shield_max:
		if _shield_regen_cd > 0.0:
			_shield_regen_cd -= delta
		else:
			shield_hp = minf(shield_max, shield_hp + 12.0 * delta)
			_update_shield_visual()
	_attack_cd = maxf(0.0, _attack_cd - delta)
	_shoot_cd = maxf(0.0, _shoot_cd - delta)
	# component damage lite for heavy/siege/shield_heavy/bulwark
	var eff_speed := speed
	if (kind == "heavy" or kind == "siege" or kind == "shield_heavy" or kind == "bulwark") and hp < max_hp * 0.5:
		eff_speed = speed * 0.65
		if not _comp_damaged_announced:
			_comp_damaged_announced = true
			var main = get_tree().get_first_node_in_group("main")
			if main and main.has_method("flash_msg"):
				main.flash_msg("%s: targeting/locomotion damaged — slowed" % kind.capitalize())
	# choose target
	var target_pos := core_position
	var target_node: Node = null
	var attack_range := 4.2
	if kind == "siege":
		attack_range = 38.0
	if kind == "burrower":
		var best: Node = null
		var best_d := 9999.0
		for s in get_tree().get_nodes_in_group("structures"):
			# Audit fix (Loop 2): explicit validity/alive guard + explicit parens.
			# Burrowers hunt LIVE power: generators, or turrets that are powered.
			if not is_instance_valid(s) or bool(s.get("is_dead_struct")):
				continue
			# Burrowers hunt LIVE power: generators, or powered turrets/mortars/emp pylons.
			var hunts: bool = bool(s.get("is_power_source")) or (str(s.get("structure_kind")) in ["turret", "mortar", "emp_pylon"] and s.has_method("is_powered") and s.is_powered())
			if hunts:
				var dd := global_position.distance_to(s.global_position)
				if dd < best_d:
					best_d = dd; best = s
		if best:
			target_node = best; target_pos = best.global_position; attack_range = 3.2
	if kind == "sapper":
		# Pass 14: sappers hunt the nearest LIVE structure (abandoned
		# turrets are dead dressing, not targets); with no structure
		# left, the fallback target below stays the core.
		var s_best: Node = null
		var s_best_d := 9999.0
		for s in get_tree().get_nodes_in_group("structures"):
			if not is_instance_valid(s) or bool(s.get("is_dead_struct")) or str(s.get("structure_kind")) == "abandoned_turret":
				continue
			var s_dd := global_position.distance_to(s.global_position)
			if s_dd < s_best_d:
				s_best_d = s_dd; s_best = s
		if s_best:
			target_node = s_best; target_pos = s_best.global_position; attack_range = 3.2
	# barricade blocking: if a barricade is close ahead, attack it
	for s in get_tree().get_nodes_in_group("structures"):
		if is_instance_valid(s) and s.get("structure_kind") == "barricade":
			if global_position.distance_to(s.global_position) < 3.0:
				target_node = s; target_pos = s.global_position; attack_range = 2.8
				break
	# player if very close (except siege keeps shelling core)
	var player = get_tree().get_first_node_in_group("player")
	if player and kind != "siege" and kind != "sapper" and global_position.distance_to(player.global_position) < 5.5:
		target_node = player; target_pos = player.global_position; attack_range = 2.6
	var to_target: Vector3 = target_pos - global_position
	to_target.y = 0.0
	var dist := to_target.length()
	if dist > 0.5:
		look_at(global_position + to_target, Vector3.UP)
	if kind == "siege":
		if dist > attack_range:
			global_position += to_target.normalized() * eff_speed * delta
		elif _shoot_cd <= 0.0:
			_shoot_cd = 2.6
			_fire_at_core()
		_apply_anim(delta, global_position.distance_to(_anim_frame_pos) > 0.001)
		return
	if kind == "sapper":
		# Pass 14: detonation, not melee. Full blast to the target
		# structure (or the core, when no structure is left), half blast
		# to other live structures within 4 m. die_silent suppresses the
		# died signal, so a detonated sapper pays NO salvage/XP — the
		# reward is for killing it before it arrives. Death by damage
		# (take_damage -> _die) never detonates, by design.
		if dist > attack_range:
			global_position += to_target.normalized() * eff_speed * delta
		else:
			if target_node == null:
				if on_core_damage.is_valid():
					on_core_damage.call(dmg)
			elif target_node.has_method("take_damage"):
				target_node.take_damage(dmg)
			for s in get_tree().get_nodes_in_group("structures"):
				if is_instance_valid(s) and s != target_node and not bool(s.get("is_dead_struct")) and str(s.get("structure_kind")) != "abandoned_turret" and global_position.distance_to(s.global_position) <= 4.0:
					if s.has_method("take_damage"):
						s.take_damage(dmg * 0.5)
			var main_node = get_tree().get_first_node_in_group("main")
			if main_node and main_node.has_method("flash_msg"):
				main_node.flash_msg("Sapper Drone detonated!")
			die_silent()
		return
	if dist > attack_range:
		global_position += to_target.normalized() * eff_speed * delta
		_apply_anim(delta, true)
	else:
		# Pass 22: a lancer never brawls — its charge is its only hit,
		# so in melee range during cooldown it holds position and
		# waits for the next telegraph instead of melee-attacking.
		if kind != "lancer" and _attack_cd <= 0.0:
			_attack_cd = 0.9
			if target_node == null:
				if on_core_damage.is_valid():
					on_core_damage.call(dmg)
			elif target_node == player:
				player.take_damage(dmg)
			elif target_node.has_method("take_damage"):
				target_node.take_damage(dmg)
	# Pass 28: generic chase — animate on actual displacement this frame
	# (a cooling-down lancer holds position, so it correctly idles here).
	_apply_anim(delta, global_position.distance_to(_anim_frame_pos) > 0.001)

func _fire_at_core() -> void:
	var b: Node3D = BulletScript.take_from_pool() as Node3D
	if b == null:
		b = Node3D.new()
		b.set_script(BulletScript)
	b.position = global_position + Vector3(0, 3.2, 0) + get_facing() * 3.5
	get_parent().add_child(b)
	var dir: Vector3 = (core_position - global_position)
	dir.y = 0.0
	b.setup(dir.normalized(), dmg, "SiegeShell", false, false, 32.0)
