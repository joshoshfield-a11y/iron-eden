extends Node3D

signal died

const BulletScript := preload("res://scripts/bullet.gd")

var max_hp: float = 150.0
var hp: float = 150.0
var move_input: Vector2 = Vector2.ZERO
var aim_point: Vector3 = Vector3(0, 0, -10)
var firing: bool = false
var velocity: Vector3 = Vector3.ZERO
var max_speed: float = 13.0
var accel: float = 55.0
var drag: float = 4.0

var heat: float = 0.0
var overheated: bool = false
var venting: bool = false
var current_weapon: int = 1 # 1 autocannon, 2 railgun, 3 scattergun, 4 flak cannon, 5 tesla arc, 6 grenade launcher
var damage_mult: float = 1.0 # Wave 1: level-up upgrades
var fire_rate_mult: float = 1.0
# Wave 2: hangar loadout
var chassis: String = "assault"
var utility: String = "repair_pulse" # or "grapple"
var _utility_cd: float = 0.0
var _fire_cd: float = 0.0
var _dash_cd: float = 0.0
# Pass 42 (End-panel stats): player-mech run counters, owned here
# because _fire / take_damage are the only places that know a shot
# was fired or the mech was hurt. Main reads them for the end panel
# and the world save; reset_for_new_run clears them with the run.
var shots_fired: int = 0
var damage_taken: float = 0.0
# Pass 5 audit fix (H1): grapple sets a 46 m/s impulse, but _process clamps
# velocity to max_speed whenever _dash_cd < 2.2 — and grapple never touched
# _dash_cd, so the impulse was clamped away on the very next frame and the
# utility barely moved the mech. _boost_t exempts the clamp while it runs.
var _boost_t: float = 0.0
var _is_dead: bool = false
var _body: Node3D
var _turret_head: Node3D
var use_sprite: bool = false
# Pass 7 (Overhaul A): color code — player = cyan/white.
var trim_color: Color = Color(0.25, 0.85, 1.0)
var _health_ring: MeshInstance3D = null
var _health_ring_mat: StandardMaterial3D = null
var _ring_band: int = -1
# Pass 34 (template top-down units): the unit sprite is now a flat
# ground-plane holder (SpriteUtil.topdown_sprite), not a billboard —
# see sprite_util.gd for why flat is correct for top-down template art.
# Pass 35 (real frame walk cycles): the sprite is a 4-frame walk holder
# (SpriteUtil.topdown_walk_sprite, sprites/p35/). Exposed for the test:
# anim_phase advances only while moving, anim_moving reports the current
# state, anim_frame is the cycled texture index (0 at rest). The holder
# never bobs or scales — Pass 28's bob/lean is gone for units.
var _sprite: Node3D = null
var _sprite_base_y: float = 0.0
var anim_phase: float = 0.0
var anim_idle_t: float = 0.0
var anim_moving: bool = false
var anim_frame: int = 0

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

func weapon_name() -> String:
	match current_weapon:
		1: return "Autocannon"
		2: return "Railgun"
		3: return "Scattergun"
		4: return "Flak Cannon"
		5: return "Tesla Arc"
		6: return "Grenade Launcher"
	return "Autocannon"

# Pass 44 (BUG-HUNT: weapon spam-switch): the fire cooldown is shared,
# so switching straight after a fast shot used to let a slow weapon
# fire on the fast weapon's short cooldown — an autocannon shot (0.13 s)
# followed 0.13 s later by a railgun shot (0.70 s interval) is a free
# heavy shot every switch cycle. Selecting a different weapon now
# raises the cooldown to at least that weapon's own interval (scaled
# by fire_rate_mult, like _fire sets it); re-selecting the current
# weapon costs nothing, and a longer cooldown already running is kept.
func select_weapon(w: int) -> void:
	if w < 1 or w > 6 or w == current_weapon:
		return
	current_weapon = w
	var interval := 0.13
	match w:
		2, 4: interval = 0.70
		3, 5: interval = 0.55
		6: interval = 0.90
	if fire_rate_mult > 0.0:
		interval /= fire_rate_mult
	if _fire_cd < interval:
		_fire_cd = interval

func apply_loadout(p_chassis: String, p_utility: String) -> void:
	chassis = p_chassis
	utility = p_utility
	_utility_cd = 0.0
	match chassis:
		"scout":
			max_hp = 110.0; max_speed = 16.5; accel = 65.0
		"support":
			max_hp = 135.0; max_speed = 11.5; accel = 48.0
		_:
			chassis = "assault"
			max_hp = 150.0; max_speed = 13.0; accel = 55.0
	hp = max_hp
	if _body:
		_build_visual()

func utility_cooldown() -> float:
	return _utility_cd

func try_utility() -> bool:
	if _utility_cd > 0.0 or _is_dead:
		return false
	if utility == "grapple":
		var dir: Vector3 = aim_point - global_position
		dir.y = 0.0
		if dir.length() < 3.0:
			return false
		velocity = dir.normalized() * 46.0
		heat = minf(100.0, heat + 3.0)
		_utility_cd = 7.0
		_boost_t = 0.4
		return true
	# repair pulse: self + nearby structures (stronger on support chassis)
	var self_heal := 45.0 if chassis == "support" else 30.0
	var struct_heal := 40.0 if chassis == "support" else 25.0
	hp = minf(max_hp, hp + self_heal)
	for s in get_tree().get_nodes_in_group("structures"):
		if is_instance_valid(s) and global_position.distance_to(s.global_position) <= 13.0 and s.has_method("heal"):
			s.heal(struct_heal)
	_utility_cd = 13.5 if chassis == "support" else 18.0
	return true

func _ready() -> void:
	add_to_group("player")
	_body = Node3D.new()
	add_child(_body)
	_build_visual()

func _build_visual() -> void:
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	_health_ring = null
	_health_ring_mat = null
	_ring_band = -1
	use_sprite = false
	# Pass 34 (template top-down units): chassis art is sliced from the
	# user's Game Assets Template chassis column (p34) and laid flat on
	# the ground — the template frames are top-down, so the Pass 7
	# billboard presentation (correct for front-view art) is superseded
	# for units. There is deliberately NO primitive-box fallback: a
	# missing slice must fail the test, not ship.
	# forward_m is the PRE-scale length (topdown_sprite applies the
	# Pass 12 UNIT_SCALE itself): 3.8/4.8/4.4 render as 5.3/6.7/6.2 m,
	# exactly the old billboard heights, so footprints do not change.
	var path := "res://sprites/p34/p34_assault.png"
	var forward_m := 4.8
	var ring_r := 2.4
	match chassis:
		"scout":
			path = "res://sprites/p34/p34_scout.png"; forward_m = 3.8; ring_r = 1.9
		"support":
			path = "res://sprites/p34/p34_support.png"; forward_m = 4.4; ring_r = 2.2
	var spr := SpriteUtil.topdown_walk_sprite(path, forward_m)
	if spr != null:
		use_sprite = true
		_sprite = spr
		_sprite_base_y = spr.position.y
		anim_frame = 0
		_body.add_child(spr)
	_turret_head = Node3D.new() # dummy so aim code stays safe; sprite carries the turret art
	_body.add_child(_turret_head)
	# Pass 12: ring + chevron scale with the billboard, so the ground
	# footprint still matches the bigger sprite.
	SpriteUtil.facing_chevron(_body, ring_r * SpriteUtil.UNIT_SCALE, 1.1, trim_color)
	_health_ring = SpriteUtil.ground_ring(_body, ring_r * SpriteUtil.UNIT_SCALE, Color(0.3, 0.9, 0.5))
	_health_ring_mat = _health_ring.get_surface_override_material(0) as StandardMaterial3D
	_update_health_ring()

func try_dash() -> void:
	if _dash_cd > 0.0 or _is_dead:
		return
	_dash_cd = 2.5
	var d := Vector3(move_input.x, 0, move_input.y)
	if d.length() < 0.1:
		d = -global_transform.basis.z
		d.y = 0.0
		d = d.normalized()
	velocity += d.normalized() * 26.0
	heat = minf(100.0, heat + 4.0)

func take_damage(amount: float) -> void:
	if _is_dead:
		return
	# Pass 42: every source funnels through here (enemy bullets,
	# melee, lancer charge, sapper blast), so this is the one
	# reliable damage-taken counter — including the lethal blow,
	# which main's per-frame HP poll can never see (the death
	# signal ends the run before the next poll).
	damage_taken += amount
	hp -= amount
	if hp <= 0.0:
		hp = 0.0
		_is_dead = true
		died.emit()

func heal_full() -> void:
	hp = max_hp

# Pass 17 (Pause menu): full run-reset state for the mech. apply_loadout
# (called by main after this) restores chassis HP/speed and rebuilds the
# visual; this clears everything apply_loadout does not touch, including
# _is_dead, so a reset run can never start with a dead mech.
func reset_for_new_run() -> void:
	_is_dead = false
	velocity = Vector3.ZERO
	move_input = Vector2.ZERO
	firing = false
	venting = false
	heat = 0.0
	overheated = false
	_fire_cd = 0.0
	_dash_cd = 0.0
	_boost_t = 0.0
	_utility_cd = 0.0
	shots_fired = 0
	damage_taken = 0.0
	current_weapon = 1
	damage_mult = 1.0
	fire_rate_mult = 1.0
	anim_phase = 0.0
	anim_idle_t = 0.0
	anim_moving = false
	anim_frame = 0

func _process(delta: float) -> void:
	if _is_dead:
		return
	_dash_cd = maxf(0.0, _dash_cd - delta)
	_boost_t = maxf(0.0, _boost_t - delta)
	_fire_cd = maxf(0.0, _fire_cd - delta)
	_utility_cd = maxf(0.0, _utility_cd - delta)
	# movement with mass/momentum
	var wish := Vector3(move_input.x, 0, move_input.y)
	if wish.length() > 1.0:
		wish = wish.normalized()
	velocity += wish * accel * delta
	velocity *= exp(-drag * delta)
	if velocity.length() > max_speed and _dash_cd < 2.2 and _boost_t <= 0.0:
		velocity = velocity.normalized() * max_speed
	global_position += velocity * delta
	global_position.x = clampf(global_position.x, -57.0, 57.0)
	global_position.z = clampf(global_position.z, -57.0, 57.0)
	global_position.y = 0.0
	# Pass 35: real frame walk cycles — phase advances with speed while
	# moving and the holder's quad texture cycles 0..3; at rest the unit
	# holds frame 0. The holder never bobs, sways, or scales: Pass 28's
	# procedural bob/lean is replaced, not layered under the frames.
	if _sprite != null:
		anim_moving = velocity.length() > 1.0
		anim_idle_t += delta
		if anim_moving:
			anim_phase += delta * (4.0 + velocity.length() * 0.55)
			anim_frame = SpriteUtil.walk_frame_index(anim_phase)
		else:
			anim_frame = 0
		SpriteUtil.set_walk_frame(_sprite, anim_frame)
		_sprite.position.y = _sprite_base_y
		_sprite.scale = Vector3.ONE
	# Pass 7: the body (and its ground chevron) turns toward the AIM point —
	# twin-stick readable. The billboard sprite itself always faces the
	# camera, so the chevron is what shows facing.
	var aim_dir: Vector3 = aim_point - global_position
	aim_dir.y = 0.0
	if aim_dir.length() > 0.5:
		var aim_yaw := atan2(aim_dir.x, aim_dir.z) + PI
		_body.rotation.y = lerp_angle(_body.rotation.y, aim_yaw, 16.0 * delta)
	_update_health_ring()
	# heat
	var cool_rate: float = 16.0
	if venting:
		cool_rate = 55.0
	if overheated:
		cool_rate = 42.0
	heat = maxf(0.0, heat - cool_rate * delta)
	if overheated and heat <= 30.0:
		overheated = false
	# firing
	if firing and not overheated and _fire_cd <= 0.0:
		_fire()

func _fire() -> void:
	var dir: Vector3 = aim_point - global_position
	dir.y = 0.0
	if dir.length() < 0.5:
		return
	dir = dir.normalized()
	# Pass 19: reuse a pooled bullet when one is free, else allocate.
	var b: Node3D = BulletScript.take_from_pool() as Node3D
	if b == null:
		b = Node3D.new()
		b.set_script(BulletScript)
	var start := global_position + dir * 2.2 + Vector3(0, 1.5, 0)
	b.position = start
	get_parent().add_child(b)
	if current_weapon == 1:
		shots_fired += 1
		b.setup(dir, 9.0 * damage_mult, "Autocannon", true, false, 60.0, 0.0, 0.0, 0.9, 0.0, 0, 0.0, true)
		_fire_cd = 0.13 / fire_rate_mult
		heat += 3.2
	elif current_weapon == 2:
		# Pass 15 (BALANCE): 54 dmg / 0.70 s = 77.1 DPS — the heavy
		# weapon finally out-DPSes the starter autocannon (69.2), which
		# it lost to on every armor case before (46 / 0.85 = 54.1).
		# Heat 17/shot = 24.3/s vs autocannon 24.6/s, so the heat
		# economy is unchanged in character; one-shot scout/burrower
		# breakpoints (30/45 HP) are preserved.
		shots_fired += 1
		b.setup(dir, 54.0 * damage_mult, "Railgun", true, true, 85.0, 0.0, 0.0, 0.9, 0.0, 0, 0.0, true)
		_fire_cd = 0.70 / fire_rate_mult
		heat += 17.0
	elif current_weapon == 4:
		# Pass 10: Flak Cannon — single shell, proximity fuse (4 m), 5.5 m
		# AoE burst. 22 dmg / 0.70 s is below autocannon single-target DPS,
		# so it wins only against groups, not against everything.
		shots_fired += 1
		b.setup(dir, 22.0 * damage_mult, "Flak Cannon", true, false, 48.0, 5.5, 0.0, 0.9, 4.0, 0, 0.0, true)
		_fire_cd = 0.70 / fire_rate_mult
		heat += 12.0
	elif current_weapon == 5:
		# Pass 21: Tesla Arc — one fast bolt, 20 dmg, chains to 2 extra
		# targets within 12 m at 75% / 50% (bullet.gd _arc_chain). 20 /
		# 0.55 s = 36.4 single-target DPS, below the autocannon, so it
		# wins only against groups (45 total per shot across 3 targets).
		shots_fired += 1
		b.setup(dir, 20.0 * damage_mult, "Tesla Arc", true, false, 62.0, 0.0, 0.0, 0.9, 0.0, 2, 12.0, true)
		_fire_cd = 0.55 / fire_rate_mult
		heat += 10.0
	elif current_weapon == 6:
		# Pass 48: Grenade Launcher — one slow arcing shell, 30 dmg
		# with a 6.0 m AoE burst at the landing point. The arc
		# duration is the aim distance / 30 m/s (mortar pattern),
		# so the shell lands where aimed instead of at a fixed
		# range; 30 / 0.90 s is below autocannon single-target DPS,
		# so it wins only against groups. No mid-flight collisions:
		# bullet.gd's arc branch detonates at _arc_end.
		shots_fired += 1
		var aim_dist := (aim_point - global_position).length()
		var arc_dur := clampf(aim_dist / 30.0, 0.4, 1.5)
		b.setup(dir, 30.0 * damage_mult, "Grenade Launcher", true, false, 30.0, 6.0, 7.0, arc_dur, 0.0, 0, 0.0, true)
		_fire_cd = 0.90 / fire_rate_mult
		heat += 14.0
	else:
		# Scattergun: first pellet uses the bullet already spawned above;
		# four more fan out around it. 5 pellets x 5 dmg, wide spread.
		shots_fired += 1
		b.setup(dir.rotated(Vector3.UP, -0.16), 5.0 * damage_mult, "Scattergun", true, false, 52.0, 0.0, 0.0, 0.9, 0.0, 0, 0.0, true)
		for off in [-0.08, 0.0, 0.08, 0.16]:
			var pb: Node3D = BulletScript.take_from_pool() as Node3D
			if pb == null:
				pb = Node3D.new()
				pb.set_script(BulletScript)
			pb.position = start
			get_parent().add_child(pb)
			shots_fired += 1
			pb.setup(dir.rotated(Vector3.UP, off), 5.0 * damage_mult, "Scattergun", true, false, 52.0, 0.0, 0.0, 0.9, 0.0, 0, 0.0, true)
		_fire_cd = 0.55 / fire_rate_mult
		heat += 9.0
	if heat >= 100.0:
		heat = 100.0
		overheated = true
		firing = false
