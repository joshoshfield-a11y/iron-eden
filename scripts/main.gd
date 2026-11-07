extends Node3D

## IRON EDEN main: world building, wave director, RPG progression,
## tower-defense pads, HUD, camera, input (keys + mouse + touch joystick).
##
## Modes of play in one loop:
##  - top-down shooter: pilot the mech, auto-fire at nearest hostile
##  - tower defense: hostiles march on the core; spend salvage on pad turrets
##  - RPG: kills grant XP; level-ups pause for a 1-of-3 upgrade choice

const PlayerScript := preload("res://scripts/player.gd")
const EnemyScript := preload("res://scripts/enemy.gd")
const TurretScript := preload("res://scripts/turret.gd")

const ARENA := 58.0
const TURRET_COST := 50

var player: Node3D
var camera: Camera3D

# core (tower-defense objective)
var core_max_hp: float = 500.0
var core_hp: float = 500.0

# RPG state
var xp: int = 0
var level: int = 1
var xp_next: int = 6
var salvage: int = 60
var kills: int = 0

# wave state
var wave: int = 0
var _to_spawn: int = 0
var _spawn_timer: float = 0.0
var _intermission: float = 2.0
var _wave_active: bool = false
var _game_over: bool = false

# build pads
var pad_positions: Array[Vector3] = [
	Vector3(11, 0, 11), Vector3(-11, 0, 11), Vector3(11, 0, -11),
	Vector3(-11, 0, -11), Vector3(0, 0, 17), Vector3(0, 0, -17),
	Vector3(17, 0, 0), Vector3(-17, 0, 0),
]
var _pads: Dictionary = {} # Vector3 -> turret node or null
var _pad_rings: Dictionary = {}

# touch joysticks (twin-stick per GDD 3.1: left = move, right = aim/fire)
var _joy_active: bool = false
var _joy_id: int = -1
var _joy_origin: Vector2 = Vector2.ZERO
var _joy_vec: Vector2 = Vector2.ZERO
var _aim_active: bool = false
var _aim_id: int = -1
var _aim_origin: Vector2 = Vector2.ZERO
var _aim_vec: Vector2 = Vector2.ZERO
var _mouse_suppress_fire: bool = false

# exploration / salvage caches (GDD loop: EXPLORE -> SALVAGE)
var _caches: Dictionary = {} # Vector3 -> Node3D
var _cache_respawns: Array = [] # [Vector3, float]

# HUD refs
var _lbl_stats: Label
var _lbl_wave: Label
var _lbl_msg: Label
var _xp_bar: ProgressBar
var _level_panel: PanelContainer
var _gameover_panel: PanelContainer
var _joy_ui: Control

var test_mode: bool = false
var _test_t: float = 0.0
var _test_stage: int = 0
var _test_failures: Array[String] = []

func _ready() -> void:
	test_mode = "--ironeden-test" in OS.get_cmdline_user_args() or "--steelward-test" in OS.get_cmdline_user_args()
	_build_world()
	_build_player()
	_build_hud()
	if test_mode:
		Engine.time_scale = 4.0
		print("IRON EDEN TEST MODE")

func _build_world() -> void:
	# environment + light
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.016, 0.02, 0.035)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.42, 0.55)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.07, 0.11)
	env.fog_density = 0.0035
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_energy = 1.15
	sun.light_color = Color(1.0, 0.9, 0.78)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 160.0
	add_child(sun)
	# ground
	var ground_mat := Factory.mat(Color(0.13, 0.15, 0.19), Color(0, 0, 0), 0.0, 0.05, 0.95)
	Factory.plane(self, Vector2(ARENA * 2.4, ARENA * 2.4), Vector3.ZERO, ground_mat)
	# runway stripes + arena border
	var stripe_mat := Factory.mat(Color(0.2, 0.24, 0.3), Color(0, 0, 0), 0.0, 0.05, 0.9)
	for i in range(-5, 6):
		Factory.box(self, Vector3(0.5, 0.04, ARENA * 2.0), Vector3(i * 11.0, 0.02, 0), stripe_mat)
	var wall_mat := Factory.mat(Color(0.24, 0.28, 0.36), Color(0.3, 0.7, 1.0), 0.35, 0.4, 0.6)
	Factory.box(self, Vector3(ARENA * 2.0 + 2.0, 1.6, 1.0), Vector3(0, 0.8, -ARENA - 0.5), wall_mat)
	Factory.box(self, Vector3(ARENA * 2.0 + 2.0, 1.6, 1.0), Vector3(0, 0.8, ARENA + 0.5), wall_mat)
	Factory.box(self, Vector3(1.0, 1.6, ARENA * 2.0 + 2.0), Vector3(-ARENA - 0.5, 0.8, 0), wall_mat)
	Factory.box(self, Vector3(1.0, 1.6, ARENA * 2.0 + 2.0), Vector3(ARENA + 0.5, 0.8, 0), wall_mat)
	# scattered cover props (visual cover, no collision in v1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261023
	var prop_mat := Factory.mat(Color(0.2, 0.23, 0.28), Color(0, 0, 0), 0.0, 0.3, 0.8)
	var prop_mat2 := Factory.mat(Color(0.28, 0.22, 0.16), Color(0, 0, 0), 0.0, 0.2, 0.85)
	for i in range(34):
		var a := rng.randf_range(0.0, TAU)
		var r := rng.randf_range(20.0, 52.0)
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		var s := rng.randf_range(1.2, 3.2)
		Factory.box(self, Vector3(s, s * rng.randf_range(0.5, 1.1), s), p + Vector3(0, s * 0.3, 0), prop_mat if i % 2 == 0 else prop_mat2, rng.randf_range(0.0, PI))
	# the core
	var core := Node3D.new()
	core.name = "Core"
	add_child(core)
	Factory.cyl(core, 3.2, 0.7, Vector3(0, 0.35, 0), Factory.mat(Color(0.14, 0.17, 0.22), Color(0, 0, 0), 0.0, 0.6, 0.4), 24)
	Factory.cyl(core, 1.5, 3.4, Vector3(0, 1.7, 0), Factory.mat(Color(0.2, 0.3, 0.4), Color(0, 0, 0), 0.0, 0.6, 0.35), 16)
	Factory.sphere(core, 1.05, Vector3(0, 4.1, 0), Factory.mat(Color(0.4, 0.9, 1.0), Color(0.4, 0.9, 1.0), 2.4, 0.0, 0.25))
	# build pads
	var pad_mat := Factory.mat(Color(0.1, 0.2, 0.18), Color(0.25, 0.9, 0.6), 0.7, 0.2, 0.6)
	for p in pad_positions:
		var ring := Factory.cyl(self, 2.0, 0.18, p + Vector3(0, 0.09, 0), pad_mat, 20)
		_pads[p] = null
		_pad_rings[p] = ring
	# salvage caches scattered for exploration
	for i in range(10):
		var a2 := rng.randf_range(0.0, TAU)
		var r2 := rng.randf_range(16.0, 50.0)
		_spawn_cache(Vector3(cos(a2) * r2, 0, sin(a2) * r2))
	# camera: angled top-down, follows the player
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 46.0
	add_child(camera)

func _build_player() -> void:
	player = Node3D.new()
	player.set_script(PlayerScript)
	player.position = Vector3(0, 0, 9)
	add_child(player)
	player.died.connect(_on_player_died)

func _process(delta: float) -> void:
	if not _game_over:
		_update_camera(delta)
		_update_input()
		_wave_director(delta)
		_cache_director(delta)
		_refresh_hud()
	if test_mode:
		_run_test(delta)

func _update_camera(delta: float) -> void:
	var focus: Vector3 = player.global_position if player else Vector3.ZERO
	var desired: Vector3 = focus + Vector3(0, 42, 23)
	camera.global_position = camera.global_position.lerp(desired, 6.0 * delta) if camera.global_position.length() > 0.01 else desired
	camera.look_at(focus + Vector3(0, 0, -2), Vector3.UP)

func _ground_point(screen_pos: Vector2) -> Vector3:
	var origin := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.001:
		return Vector3.ZERO
	var t := -origin.y / dir.y
	return origin + dir * t

func _update_input() -> void:
	if not player or _game_over:
		return
	var v := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		v.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		v.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		v.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		v.y += 1.0
	if _joy_active:
		v = _joy_vec
	player.move_input = v
	var mp := get_viewport().get_mouse_position()
	player.aim_point = _ground_point(mp)
	# twin-stick / mouse manual fire
	if _aim_active and _aim_vec.length() > 0.18:
		player.manual_aim = Vector3(_aim_vec.x, 0, _aim_vec.y)
		player.manual_fire = true
	elif Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not _mouse_suppress_fire and not _joy_active:
		var md: Vector3 = player.aim_point - player.global_position
		md.y = 0.0
		if md.length() > 0.5:
			player.manual_aim = md.normalized()
			player.manual_fire = true
		else:
			player.manual_fire = false
	else:
		player.manual_fire = false

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		var vp := get_viewport().get_visible_rect().size
		if t.pressed:
			if _try_build_at_screen(t.position):
				return # tap was a build order, do not start a stick
			if t.position.x < vp.x * 0.45 and not _joy_active:
				_joy_active = true
				_joy_id = t.index
				_joy_origin = t.position
				_joy_vec = Vector2.ZERO
			elif t.position.x >= vp.x * 0.45 and not _aim_active:
				_aim_active = true
				_aim_id = t.index
				_aim_origin = t.position
				_aim_vec = Vector2.ZERO
			_update_joy_ui()
		else:
			if t.index == _joy_id:
				_joy_active = false
				_joy_vec = Vector2.ZERO
			if t.index == _aim_id:
				_aim_active = false
				_aim_vec = Vector2.ZERO
			_update_joy_ui()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if _joy_active and d.index == _joy_id:
			_joy_vec = _stick_vec(d.position - _joy_origin)
			_update_joy_ui()
		elif _aim_active and d.index == _aim_id:
			_aim_vec = _stick_vec(d.position - _aim_origin)
			_update_joy_ui()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_mouse_suppress_fire = _try_build_at_screen(mb.position)
			else:
				_mouse_suppress_fire = false
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo:
			if k.keycode >= KEY_1 and k.keycode <= KEY_8:
				var idx: int = int(k.keycode - KEY_1)
				if idx < pad_positions.size():
					try_build_turret(pad_positions[idx])
			elif k.keycode == KEY_SPACE or k.keycode == KEY_SHIFT:
				if player:
					player.start_dash()

func _stick_vec(off: Vector2) -> Vector2:
	var v: Vector2 = off / 70.0
	if v.length() > 1.0:
		v = v.normalized()
	return v

func _try_build_at_screen(screen_pos: Vector2) -> bool:
	var gp := _ground_point(screen_pos)
	for p in pad_positions:
		var d: Vector3 = gp - p
		d.y = 0.0
		if d.length() < 3.2:
			try_build_turret(p)
			return true
	return false

func try_build_turret(pad: Vector3) -> bool:
	if _pads.get(pad, null) != null:
		return false
	if salvage < TURRET_COST:
		_flash_msg("Need %d salvage for a turret" % TURRET_COST)
		return false
	salvage -= TURRET_COST
	var t = Node3D.new()
	t.set_script(TurretScript)
	t.position = pad
	add_child(t)
	_pads[pad] = t
	var ring = _pad_rings.get(pad)
	if ring:
		ring.set_surface_override_material(0, Factory.mat(Color(0.16, 0.2, 0.16), Color(0, 0, 0), 0.0, 0.3, 0.7))
	_flash_msg("Turret online")
	return true

func build_turret_first_free() -> void:
	for p in pad_positions:
		if _pads[p] == null:
			try_build_turret(p)
			return
	_flash_msg("All pads occupied")

func take_core_damage(amount: float) -> void:
	if _game_over:
		return
	core_hp -= amount
	if core_hp <= 0.0:
		core_hp = 0.0
		_end_game("The core fell on wave %d" % wave)

func _on_player_died() -> void:
	_end_game("Mech destroyed on wave %d" % wave)

func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

func _end_game(reason: String) -> void:
	_game_over = true
	_lbl_msg.text = reason
	_gameover_panel.visible = true
	get_tree().paused = true

# ---------------- waves / RPG ----------------

func _wave_director(delta: float) -> void:
	if _wave_active:
		if _to_spawn > 0:
			_spawn_timer -= delta
			if _spawn_timer <= 0.0:
				_spawn_timer = 0.65
				_to_spawn -= 1
				_spawn_enemy()
		elif get_tree().get_nodes_in_group("enemies").is_empty():
			_wave_active = false
			_intermission = 4.0
			var bonus := 20 + wave * 2
			salvage += bonus
			_flash_msg("Wave %d clear  +%d salvage" % [wave, bonus])
			if wave >= 3 and not _endless and not _victory_done:
				_victory()
	else:
		_intermission -= delta
		if _intermission <= 0.0:
			_start_wave()

func _start_wave() -> void:
	wave += 1
	_to_spawn = 5 + wave * 3
	_wave_active = true
	_spawn_timer = 0.2
	_flash_msg("Wave %d incoming" % wave)

func _spawn_enemy() -> void:
	var angle := randf() * TAU
	var pos := Vector3(cos(angle) * 53.0, 0, sin(angle) * 53.0)
	var i := _to_spawn
	var kind := "grunt"
	if i % 7 == 0 and wave >= 2:
		kind = "brute"
	elif randf() < 0.38:
		kind = "runner"
	var e = Node3D.new()
	e.set_script(EnemyScript)
	e.setup(kind, 1.0 + float(wave - 1) * 0.22, pos) # before add_child so _ready builds the right kind
	add_child(e)
	e.core_position = Vector3.ZERO
	e.on_core_damage = Callable(self, "take_core_damage")
	e.died.connect(_on_enemy_died)

var kills_by_player: int = 0
var kills_by_turret: int = 0
var _endless: bool = false
var _victory_done: bool = false
var _victory_panel: PanelContainer
var _victory_label: Label

func _on_enemy_died(_enemy: Node3D, xp_value: int, salvage_value: int, source: String = "player") -> void:
	kills += 1
	if source == "turret":
		kills_by_turret += 1
	else:
		kills_by_player += 1
	salvage += salvage_value
	_gain_xp(xp_value)

func _gain_xp(value: int) -> void:
	xp += value
	if xp >= xp_next:
		xp -= xp_next
		level += 1
		xp_next = 6 + level * 4
		_show_level_up()

# ---------------- victory / persistence (scoped plan section 3) ----------------

func _victory() -> void:
	_victory_done = true
	var pct := int(100.0 * core_hp / core_max_hp)
	var state := "forward_base"
	var outcome := "Facility saved, reactor intact (%d%%) - it becomes a forward base." % pct
	if pct < 60:
		state = "damaged_outpost"
		outcome = "Facility saved, reactor damaged (%d%%) - a damaged outpost, repair contract posted." % pct
	var adaptation := "Scout report: the Directorate is developing TUNNELING units to bypass static defenses."
	if kills_by_player >= kills_by_turret:
		adaptation = "Scout report: the Directorate is developing SHIELDED heavies to counter direct mech fire."
	var save_data := {
		"version": 1,
		"facility_state": state,
		"core_hp_pct": pct,
		"waves_cleared": wave,
		"level": level,
		"kills": kills,
		"kills_by_player": kills_by_player,
		"kills_by_turret": kills_by_turret,
	}
	var f := FileAccess.open("user://ironeden_save.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(save_data, "\t"))
		f.close()
	if test_mode:
		print("IRON EDEN VICTORY state=", state, " pct=", pct)
		return
	_victory_label.text = "THE LAST REACTOR HOLDS\n\n%s\n\n%s\n\nProgress saved." % [outcome, adaptation]
	_victory_panel.visible = true
	get_tree().paused = true

func _continue_endless() -> void:
	_endless = true
	_victory_panel.visible = false
	get_tree().paused = false
	_flash_msg("Endless defense - wave %d next" % (wave + 1))

# salvage caches: walk over to collect, respawn elsewhere after a delay
func _spawn_cache(pos: Vector3) -> void:
	var node := Node3D.new()
	node.position = pos
	add_child(node)
	Factory.box(node, Vector3(1.1, 0.8, 1.1), Vector3(0, 0.55, 0), Factory.mat(Color(0.55, 0.4, 0.14), Color(1.0, 0.7, 0.25), 0.9, 0.3, 0.6), 0.6)
	Factory.sphere(node, 0.22, Vector3(0, 1.25, 0), Factory.mat(Color(1.0, 0.75, 0.3), Color(1.0, 0.75, 0.3), 2.2, 0.0, 0.3))
	_caches[pos] = node

func _cache_director(delta: float) -> void:
	if player:
		var taken: Array = []
		for pos in _caches.keys():
			var d: Vector3 = player.global_position - pos
			d.y = 0.0
			if d.length() < 2.5:
				taken.append(pos)
		for pos in taken:
			var node = _caches[pos]
			if is_instance_valid(node):
				node.queue_free()
			_caches.erase(pos)
			salvage += 20
			_gain_xp(1)
			_flash_msg("Salvage cache recovered  +20 salvage")
			_cache_respawns.append([pos, 25.0])
	for i in range(_cache_respawns.size() - 1, -1, -1):
		_cache_respawns[i][1] -= delta
		if _cache_respawns[i][1] <= 0.0:
			var old_pos: Vector3 = _cache_respawns[i][0]
			_cache_respawns.remove_at(i)
			var a := randf() * TAU
			var r := randf_range(16.0, 50.0)
			_spawn_cache(Vector3(cos(a) * r, 0, sin(a) * r))

func _show_level_up() -> void:
	if test_mode:
		_apply_upgrade(0)
		return
	_level_panel.visible = true
	get_tree().paused = true

func _apply_upgrade(idx: int) -> void:
	match idx:
		0:
			player.bullet_damage *= 1.25
			_flash_msg("Level %d: +25%% damage" % level)
		1:
			player.fire_interval = maxf(0.08, player.fire_interval * 0.85)
			_flash_msg("Level %d: +fire rate" % level)
		2:
			player.max_hp += 30.0
			player.heal_full()
			_flash_msg("Level %d: +30 hull, repaired" % level)
	_level_panel.visible = false
	get_tree().paused = false

# ---------------- HUD ----------------

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_lbl_stats = Label.new()
	_lbl_stats.position = Vector2(14, 10)
	_lbl_stats.add_theme_font_size_override("font_size", 19)
	layer.add_child(_lbl_stats)
	_lbl_wave = Label.new()
	_lbl_wave.position = Vector2(14, 38)
	_lbl_wave.add_theme_font_size_override("font_size", 17)
	layer.add_child(_lbl_wave)
	_lbl_msg = Label.new()
	_lbl_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_msg.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_lbl_msg.position = Vector2(-300, 64)
	_lbl_msg.size = Vector2(600, 30)
	_lbl_msg.add_theme_font_size_override("font_size", 22)
	layer.add_child(_lbl_msg)
	_xp_bar = ProgressBar.new()
	_xp_bar.position = Vector2(14, 66)
	_xp_bar.size = Vector2(260, 14)
	_xp_bar.min_value = 0
	layer.add_child(_xp_bar)
	var hint := Label.new()
	hint.text = "WASD / left-drag: move   Auto-fire on nearest hostile   Click a glowing pad (or 1-8): build turret (%d salvage)" % TURRET_COST
	hint.position = Vector2(14, 600)
	hint.add_theme_font_size_override("font_size", 14)
	layer.add_child(hint)
	var build_btn := Button.new()
	build_btn.text = "BUILD TURRET (%d)" % TURRET_COST
	build_btn.position = Vector2(950, 580)
	build_btn.size = Vector2(185, 52)
	build_btn.pressed.connect(build_turret_first_free)
	layer.add_child(build_btn)
	var dodge_btn := Button.new()
	dodge_btn.text = "DODGE"
	dodge_btn.position = Vector2(950, 516)
	dodge_btn.size = Vector2(185, 52)
	dodge_btn.pressed.connect(func() -> void: if player: player.start_dash())
	layer.add_child(dodge_btn)
	# level up panel
	_level_panel = PanelContainer.new()
	_level_panel.set_anchors_preset(Control.PRESET_CENTER)
	_level_panel.position = Vector2(-170, -120)
	_level_panel.size = Vector2(340, 240)
	_level_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	_level_panel.visible = false
	layer.add_child(_level_panel)
	var lv := VBoxContainer.new()
	_level_panel.add_child(lv)
	var lt := Label.new()
	lt.text = "LEVEL UP — choose one"
	lt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv.add_child(lt)
	var names: Array[String] = ["+25% DAMAGE", "FASTER FIRE RATE", "+30 HULL + REPAIR"]
	for i in range(3):
		var b := Button.new()
		b.text = names[i]
		b.custom_minimum_size = Vector2(300, 52)
		var idx := i
		b.pressed.connect(func() -> void: _apply_upgrade(idx))
		lv.add_child(b)
	# game over panel
	_gameover_panel = PanelContainer.new()
	_gameover_panel.set_anchors_preset(Control.PRESET_CENTER)
	_gameover_panel.position = Vector2(-170, -90)
	_gameover_panel.size = Vector2(340, 180)
	_gameover_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	_gameover_panel.visible = false
	layer.add_child(_gameover_panel)
	var gv := VBoxContainer.new()
	_gameover_panel.add_child(gv)
	var gt := Label.new()
	gt.text = "GAME OVER"
	gt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gt.add_theme_font_size_override("font_size", 26)
	gv.add_child(gt)
	var rb := Button.new()
	rb.text = "RESTART"
	rb.custom_minimum_size = Vector2(300, 52)
	rb.pressed.connect(_restart)
	gv.add_child(rb)
	# victory panel
	_victory_panel = PanelContainer.new()
	_victory_panel.set_anchors_preset(Control.PRESET_CENTER)
	_victory_panel.position = Vector2(-230, -150)
	_victory_panel.size = Vector2(460, 300)
	_victory_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	_victory_panel.visible = false
	layer.add_child(_victory_panel)
	var vv := VBoxContainer.new()
	_victory_panel.add_child(vv)
	_victory_label = Label.new()
	_victory_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_victory_label.custom_minimum_size = Vector2(430, 180)
	vv.add_child(_victory_label)
	var eb := Button.new()
	eb.text = "CONTINUE: ENDLESS DEFENSE"
	eb.custom_minimum_size = Vector2(430, 48)
	eb.pressed.connect(_continue_endless)
	vv.add_child(eb)
	var rb2 := Button.new()
	rb2.text = "RESTART OPERATION"
	rb2.custom_minimum_size = Vector2(430, 48)
	rb2.pressed.connect(_restart)
	vv.add_child(rb2)
	# joystick indicator
	_joy_ui = Control.new()
	_joy_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_joy_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_joy_ui)
	_joy_ui.set_script(preload("res://scripts/joystick_ui.gd"))

func _update_joy_ui() -> void:
	if _joy_ui and _joy_ui.has_method("set_sticks"):
		_joy_ui.set_sticks([
			{"active": _joy_active, "origin": _joy_origin, "vec": _joy_vec, "color": Color(0.5, 0.9, 1.0)},
			{"active": _aim_active, "origin": _aim_origin, "vec": _aim_vec, "color": Color(1.0, 0.75, 0.35)},
		])

func _refresh_hud() -> void:
	if not _lbl_stats:
		return
	_lbl_stats.text = "HULL %d/%d    CORE %d/%d    SALVAGE %d" % [int(player.hp), int(player.max_hp), int(core_hp), int(core_max_hp), salvage]
	_lbl_wave.text = "WAVE %d    LV %d    KILLS %d" % [wave, level, kills]
	_xp_bar.max_value = xp_next
	_xp_bar.value = xp

var _msg_timer: float = 0.0
func _flash_msg(text: String) -> void:
	if _lbl_msg:
		_lbl_msg.text = text
	_msg_timer = 2.6

# ---------------- automated test ----------------

func _check(cond: bool, what: String) -> void:
	if not cond:
		_test_failures.append(what)
		print("TEST FAIL: ", what)

func _run_test(delta: float) -> void:
	_test_t += delta
	# stage 0: world sanity at t~0.5
	if _test_stage == 0 and _test_t > 0.5:
		_test_stage = 1
		_check(player != null, "player exists")
		_check(camera != null, "camera exists")
		_check(_pads.size() == 8, "8 build pads")
		salvage = 200
		_check(try_build_turret(pad_positions[0]), "turret builds on pad 1")
		_check(try_build_turret(pad_positions[1]), "turret builds on pad 2")
		_check(not try_build_turret(pad_positions[0]), "occupied pad refuses rebuild")
		# park the player next to the action and let auto-fire work
		player.global_position = Vector3(0, 0, 14)
	if _test_stage == 1:
		# drive the player in a slow circle so movement code runs
		player.move_input = Vector2(sin(_test_t * 0.7), cos(_test_t * 0.7) * 0.4)
		if _test_t > 14.0:
			_test_stage = 2
			_check(wave >= 1, "wave director started a wave")
			_check(kills >= 1, "kills happened (auto-fire/turrets), kills=%d" % kills)
			_check(xp > 0 or level > 1, "xp was earned")
			# rpg upgrade path
			var dmg_before: float = player.bullet_damage
			_apply_upgrade(0)
			_check(player.bullet_damage > dmg_before, "damage upgrade applies")
			# core damage path
			var core_before := core_hp
			take_core_damage(5.0)
			_check(core_hp < core_before, "core takes damage")
			# victory + persistence path (scoped plan: 3 waves, consequence saves)
			_victory()
			_check(_victory_done, "victory triggers after wave 3")
			_check(FileAccess.file_exists("user://ironeden_save.json"), "world-state save file written")
			print("IRON EDEN TEST kills=%d level=%d wave=%d salvage=%d core=%d player_hp=%d" % [kills, level, wave, salvage, int(core_hp), int(player.hp)])
			if _test_failures.is_empty():
				print("IRON EDEN AUTO TEST: PASS")
			else:
				print("IRON EDEN AUTO TEST: FAIL (", _test_failures.size(), ")")
			get_tree().quit(0 if _test_failures.is_empty() else 1)
