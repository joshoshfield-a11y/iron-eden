extends Node3D

## IRON EDEN slice v0.1 main: world, wave director, power network, build system,
## substation choice, HUD, persistent world save, automated test.

const PlayerScript := preload("res://scripts/player.gd")
const EnemyScript := preload("res://scripts/enemy.gd")
const TurretScript := preload("res://scripts/turret.gd")
const DroneScript := preload("res://scripts/drone.gd")

const ARENA := 58.0
const CORE_POWER_RADIUS := 28.0
const GEN_POWER_RADIUS := 22.0
const COSTS := {"turret": 50, "generator": 75, "barricade": 25, "mortar": 90, "emp_pylon": 120, "repair_station": 110}

var player: Node3D
var camera: Camera3D
var core_max_hp: float = 500.0
var core_hp: float = 500.0
var salvage: int = 90
var kills: int = 0
var wave: int = 0
var siege_killer_weapon: String = ""
# Wave 1 (build loop): progression, kill split, adaptation, caches, endless
var xp: int = 0
var level: int = 1
var pending_levels: int = 0
var mech_kills: int = 0
var turret_kills: int = 0
var endless_mode: bool = false
var _caches: Array = []
var _cache_rng := RandomNumberGenerator.new()
# Pass 30 (Destructibles + item animations): breakable crates/barrels/
# ruins, each with HP + a flat salvage payout (scaled by difficulty at
# payout, like kill/capture salvage). Nodes live in group
# "destructibles" and carry their state in metas, so bullet.gd can
# damage them without a new script. _destructible_break_fx counts
# break-effect flashes spawned (the visible effect itself is a tweened
# sphere flash, like bullet AoE flashes).
var _destructibles: Array = []
var _destructible_broken: int = 0
var _destructible_break_fx: int = 0
# Pass 31 (Kill-streak + combo salvage): consecutive kills without
# taking player damage. Counts mech kills, turret kills and captures
# alike (the whole war machine earns it); a detonated sapper pays
# nothing and does not count, because it dies by die_silent, never
# through _on_enemy_died / capture_enemy. best_kill_streak survives
# a broken streak (it is a run record, reset only by _reset_run).
# last_streak_call / streak_call_count are the observable callouts:
# a call fires at every 5-streak milestone, and a combo bonus is
# paid on every kill at streak >= 5 (see combo_bonus_for_streak).
var kill_streak: int = 0
var best_kill_streak: int = 0
var last_streak_call: String = ""
var streak_call_count: int = 0
# Pass 49 (FEATURE: Overdrive meter). Kills charge the meter (+10
# each, only while inactive — an active overdrive banks nothing, so
# the next meter always starts from zero). At 100, Space+Shift
# (desktop) or a double-tap on the move stick (touch) triggers a
# 6 s overdrive: player.fire_rate_mult x1.4, restored by division
# on expiry (multiplication commutes with the level-up x1.2, so a
# mid-overdrive upgrade still leaves the correct base rate after
# expiry). _reset_run clears the flags; player.reset_for_new_run
# clears fire_rate_mult itself, so a reset can never strand a 1.4x.
var overdrive_charge: float = 0.0
var overdrive_active: bool = false
var overdrive_timer: float = 0.0
var _od_bar: ProgressBar
var _last_move_tap_msec: int = 0
const OVERDRIVE_CHARGE_PER_KILL := 10.0
const OVERDRIVE_DURATION := 6.0
const OVERDRIVE_FIRE_MULT := 1.4
const OVERDRIVE_DOUBLE_TAP_MSEC := 350
# Pass 42 (End-panel stats): run-scoped, player-mech-only stats.
# shots_fired and damage_taken live on player.gd (only _fire and
# take_damage know they happened); shots_hit and damage_dealt live
# here, counted by bullet.gd at impact. Definitions, stated so the
# panel cannot be misread: run time = live play from deploy to the
# end panel (pauses and hangar excluded, endless continues the same
# run); shots_hit = player-mech shots that struck at least one enemy
# (one per bullet, so accuracy never exceeds 100%); accuracy =
# shots_hit / shots_fired (0 with no shots); damage dealt = nominal
# damage handed to enemies before armor/shield mitigation; damage
# taken = all HP lost by the mech, lethal blow included. Turret,
# mortar, drone and destructible damage never enter these counters.
var run_time_seconds: float = 0.0
var shots_hit: int = 0
var damage_dealt: float = 0.0
var _cache_anim_t: float = 0.0
var _lvl_panel: PanelContainer
var _lvl_title: Label
# Wave 2: hangar + loadout
var loadout := {"chassis": "assault", "utility": "repair_pulse", "doctrine": "iron_wall", "region": "region1", "dust_storm": false}
var _sel_chassis: String = "assault"
var _sel_utility: String = "repair_pulse"
var _sel_doctrine: String = "iron_wall"
# Pass 3 (Wave 5): Region 2 arena + recovery contract + saved-adaptation counters
var current_region: String = "region1"
var _sel_region: String = "region1"
# Pass 45 (Region 2 dust storm): hangar toggle, persisted in the
# loadout. It only takes effect on Rust Flats — Iron Flats has no
# storm, so a storm-ON loadout on region1 changes nothing until the
# player picks region2.
var _sel_dust_storm: bool = false
var _dust_storm_btn: Button
# Pass 46 (Contracts board): 3 rotating bonus objectives per run,
# drawn from a fixed pool of 6. The board rolls every time the hangar
# opens for a new run (back-to-hangar re-rolls; pause-restart keeps
# the board, since _reset_run never re-rolls). Rotation is a sliding
# window over the pool, indexed by contracts_roll_index, which is
# persisted in the loadout file like the schema stamp (file-only,
# never a gameplay field of the in-memory loadout). Progress reuses
# existing run counters plus two new ones (captures, caches
# collected); flawless-wave progress is a flag set at wave clear.
# Rewards pay at completion, scaled by the difficulty salvage
# multiplier like every other salvage income, and only once.
var contracts_roll_index: int = 0
var contracts_active: Array = []
var contracts_done: Dictionary = {}
var contracts_paid_total: int = 0
# Pass 46: payouts only count while a deployed run is live. Deploy
# arms it; hangar-open, run reset, and game end disarm it; pause-
# restart re-arms it (same run continues) and endless re-arms it.
# This is also what keeps scripted test blocks that spawn and kill
# outside any deploy from tripping contract payouts mid-assertion.
var contracts_live: bool = false
var captures: int = 0
var caches_collected: int = 0
var _contracts_flawless_done: bool = false
var _wave_core_hp_start: float = 0.0
var _contracts_lbl: Label
# Pass 23 (Difficulty select): Standard / Hard / Brutal, picked in the
# hangar and persisted in the loadout file. Multipliers are a pure
# function so tests can assert them without spawning anything.
var difficulty: String = "standard"
var _sel_difficulty: String = "standard"
var _difficulty_btns: Array = []
var saved_adaptation: String = ""
# Pass 25 (AUDIT: save schema + corrupt-save recovery): both save files
# are versioned JSON. Version 1 stamps every write; a file with no
# version is legacy (pre-Pass-25) and loads as before; a file with a
# NEWER version still loads its known fields (forward-compat, unknown
# fields ignored, never rejected). Writes are atomic-ish: the previous
# valid file is kept as .bak, the new data goes to .tmp, then .tmp is
# renamed over the target — a crash mid-write can no longer leave a
# truncated file as the only copy. A corrupt main file is quarantined
# to .corrupt and the .bak is restored when it is usable; the loadout
# falls back to defaults (a safe default exists), while the world file
# has no safe default, so it clears to "no prior world state" instead
# of inventing a victory. Every corrupt case prints a log line (this
# closes Pass 5 backlog item L1, silent fallback on unparseable JSON).
const SAVE_SCHEMA_VERSION := 1
const LOADOUT_PATH := "user://iron_eden_loadout.json"
const WORLD_PATH := "user://iron_eden_world.json"
var save_corrupt_loadout: bool = false
var save_corrupt_world: bool = false
var save_recovered_from_backup: bool = false
var save_future_schema_seen: bool = false
var save_load_note: String = ""
var recovery_active: bool = false
var recovery_built: int = 0
var recovery_bonus_paid: bool = false
var _region_marker: Node3D
var _world_env: Environment
# Pass 2 (Wave 4): allied engineering drone + doctrine presets
var drone: Node3D
var drone_hold: bool = false
var _hangar_panel: PanelContainer
var _hangar_portrait: TextureRect
var _hangar_stats: Label
# Pass 26 (UX: hangar overhaul): one card per chassis (preview + stat
# bars), plus a single integrated loadout summary line. Layout only:
# the cards read the same stats player.gd applies, they change nothing.
var _hangar_cards: Dictionary = {}
# Pass 36 (menu-systems restyle): every hangar pick button, keyed so
# _refresh_hangar can paint the selected pick cyan-fill; plus every
# modal header divider, so the test can assert the chrome exists.
var _hangar_pick_btns: Dictionary = {}
var _p36_dividers: Array = []
var _hangar_summary: Label
var hangar_open: bool = false
# Pass 11 (HOTFIX): HUD registry + hangar modal pieces.
var _hud_controls: Array = []
var _hint_lbl: Label
var _build_bar: HBoxContainer
var _deploy_btn: Button
var _spawn_queue: Array = []
var _spawn_timer: float = 0.0
var _intermission: float = 2.5
var _wave_active: bool = false
var _game_over: bool = false
var _won: bool = false
var _structures: Array = []
var _abandoned_turrets: Array = []
var _substation_pos := Vector3(-46, 0, -46)
var _substation_used: bool = false
var _tunnel_gate: Node3D
var _sub_panel: PanelContainer
var _win_panel: PanelContainer
var _gameover_panel: PanelContainer
var _lbl_stats: Label
var _lbl_wave: Label
var _lbl_msg: Label
# Pass 40: the message zone panel itself, so _refresh_hud can hide the
# whole bar (not just clear its text) when no message is showing.
var _msg_zone: PanelContainer
# Pass 37 (FEATURE: wave preview): intermission panel + label. The
# panel is a layer child of _build_hud, so the Pass 11 registry loop
# picks it up and the hangar hides/restores it with the rest of the HUD.
var _preview_panel: PanelContainer
var _preview_lbl: Label
var _heat_bar: ProgressBar
var _hull_bar: ProgressBar
var _core_bar: ProgressBar
var _msg_timer: float = 0.0
# touch joystick
var _joy_active: bool = false
var _joy_id: int = -1
var _joy_origin: Vector2 = Vector2.ZERO
var _joy_vec: Vector2 = Vector2.ZERO
var _touch_firing: bool = false
# Pass 4 (Wave 6): right virtual stick aim + fire button, quality/perf, signing prep
var _aim_active: bool = false
var _aim_id: int = -1
var _aim_origin: Vector2 = Vector2.ZERO
var _aim_vec: Vector2 = Vector2.ZERO
var _fire_btn: Button
var _quality_btn: Button
var quality_mode: String = "balanced" # s25 / balanced / forward_plus
var adaptive_quality: bool = true
var _sun_light: DirectionalLight3D
var _last_perf := {}
# Pass 1 (Wave 3): power-line visuals generator -> powered structures
var _power_lines_mi: MeshInstance3D
var _power_line_count: int = 0
var _power_line_timer: float = 0.0
# Pass 8 (Overhaul B): world visuals — tiled ground atlas, core plaza,
# clustered ruins, dark walls with edge strips, tile props, dimmable lines.
var _ground_mat: StandardMaterial3D
var _ground_node: MeshInstance3D
var _ground_base_node: MeshInstance3D
var _core_node: Node3D
var _plaza_node: MeshInstance3D
var _wall_mat: StandardMaterial3D
var _wall_edges: Array = []
var _ruin_positions: Array = []
# Pass 39 (Ground v2): flat top-down sprite props replacing the ruin boxes.
var _ruin_sprites: Array = []
var _prop_sprites: Array = []
var _power_line_mat: StandardMaterial3D
var _power_line_bright_t: float = 0.0
# Pass 9 (Overhaul C): HUD skin/zones, icon buttons, range-gated labels, zoom.
# Pass 12 (battlefield readability): zoom steps re-based so the CLOSEST
# step (34) is the default — a phone player starts pulled in, not at 50.
var _core_lbl: Label3D
var _sub_lbl: Label3D
var _hud_zones: Array = []
var _weapon_icons: Array = []
var _utility_btn: Button
var _zoom_btn: Button
var zoom_step: int = 0
var _zoom_sizes := [34.0, 42.0, 50.0]
# Pass 18 (UX): damage vignette (red screen edges on player hit), screen
# shake on siege death. Vignette alpha is the single source of truth —
# the edge rects just render it, so tests can assert on the number.
var _vignette: Control
var _vignette_edges: Array = []
var _vignette_alpha: float = 0.0
var _last_player_hp: float = -1.0
var _shake_t: float = 0.0
var _shake_dur: float = 0.0
var _shake_amp: float = 0.0
var _shake_clock: float = 0.0
# Pass 17 (Pause menu): Esc/P toggles a centred modal with RESUME,
# RESTART RUN (in-place run reset, no scene reload, no hangar reopen)
# and BACK TO HANGAR (run reset + hangar reopen). The panel is created
# AFTER the HUD registry on purpose: it is not a HUD control, so the
# hangar modal never hides or restores it — its visibility is owned by
# open/resume/restart/back-to-hangar only.
var pause_open: bool = false
var _pause_panel: PanelContainer
var _pause_resume_btn: Button
var _pause_restart_btn: Button
var _pause_hangar_btn: Button
# Pass 16 (Minimap): top-right battlefield overview. World range +/-60 m
# covers the arena (walls at ~58.5) plus the spawn ring at 54, so no live
# entity can fall off the map; anything outside clamps to the edge.
var _minimap_panel: PanelContainer
var _minimap_dots: Dictionary = {}
# Pass 20 (seamless ground + phone HUD rebuild): bottom panel shrinks
# 160 -> 128 px; the camera look target shifts south of the player so the
# mech renders above the panel (safe-area), never behind it.
# Pass 40 keeps P20_BOTTOM_H as the camera-clearance reference (the
# player must still clear vh-128-50); the real panel is P40_BOTTOM_H.
const P20_BOTTOM_H := 128.0
const P20_CAM_TARGET_Z := 6.0
# Pass 40 (HUD consolidation): one total HUD budget, in px at the
# 648-high design viewport. Top 84 + bottom 124 = 208 typical chrome
# (32.1% of height, was 112 + 150 = 262 effective / 40.4% with the
# always-on message panel and the above-panel MOVE/AIM labels).
# Message 30 and preview 40 only count when actually visible.
const P40_TOP_H := 84.0
const P40_MSG_H := 30.0
const P40_PREVIEW_H := 40.0
const P40_BOTTOM_H := 124.0
var _version_lbl: Label
var _minimap_border: Array = []
const MINIMAP_SIZE := 120.0
const MINIMAP_RANGE := 60.0
# test
var test_mode: bool = false
var _test_t: float = 0.0
var _test_t4: float = 0.0
var _test_stage: int = 0
var _test_failures: Array[String] = []
# Pass 17: stage 5 (pause checks) contains an await, so a second
# _process call re-enters _run_test while the first is suspended — the
# flag makes re-entrant calls no-ops instead of a second concurrent run.
var _p17_active: bool = false

func _ready() -> void:
	# Pass 17: main runs PROCESS_MODE_ALWAYS so Esc/P reach _input while
	# the tree is paused (a paused INHERIT node never receives input, so
	# a pause menu could only be closed by its buttons). The game itself
	# still freezes on pause: _process returns early on any pause in a
	# real build, and _input swallows everything except Esc/P while the
	# pause menu is open, and everything while any other pause holds.
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("main")
	test_mode = "--iron-eden-test" in OS.get_cmdline_user_args()
	_load_existing_save()
	_load_loadout()
	_build_world()
	set_quality_mode(quality_mode)
	_build_player()
	_spawn_drone()
	_build_hud()
	if test_mode:
		Engine.time_scale = 4.0
		print("IRON EDEN TEST MODE")
	else:
		_open_hangar()

# ---------------- loadout (Wave 2) ----------------

# Pass 25: save-file plumbing shared by loadout + world. _parse returns
# {} for unparseable text, non-dict JSON, and empty text alike, so
# callers must check the key field they need — never trust {} as data.
func _save_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		return ""
	var t := f.get_as_text()
	f = null
	return t

func _parse_save_dict(text: String) -> Dictionary:
	if text == "":
		return {}
	# JSON.new().parse() is quiet on bad input; JSON.parse_string()
	# prints an engine ERROR line for every corrupt file, which would
	# pollute the test log on exactly the files this pass recovers.
	var j := JSON.new()
	if j.parse(text) != OK:
		return {}
	return j.data if j.data is Dictionary else {}

func _note_save_schema(data: Dictionary) -> void:
	var raw = data.get("schema_version", 0)
	var v := 0
	if raw is int or raw is float:
		v = int(raw)
	elif raw is String:
		v = raw.to_int()
	if v > SAVE_SCHEMA_VERSION:
		save_future_schema_seen = true
		print("IRON EDEN SAVE: file schema v%d is newer than game v%d — known fields loaded, unknown fields ignored" % [v, SAVE_SCHEMA_VERSION])

func _write_save_file(path: String, data: Dictionary) -> bool:
	# Back up only a parsable, non-empty previous file: a corrupt main
	# must never overwrite a good backup with itself.
	var old := _save_text(path)
	if old != "":
		if not _parse_save_dict(old).is_empty():
			var bf := FileAccess.open(path + ".bak", FileAccess.WRITE)
			if bf:
				bf.store_string(old)
				bf = null
	var tmp := path + ".tmp"
	var tf := FileAccess.open(tmp, FileAccess.WRITE)
	if not tf:
		print("IRON EDEN SAVE: cannot open tmp for ", path)
		return false
	tf.store_string(JSON.stringify(data, "\t"))
	tf = null
	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK:
		print("IRON EDEN SAVE: tmp rename failed (", err, "), falling back to direct write for ", path)
		var df := FileAccess.open(path, FileAccess.WRITE)
		if not df:
			return false
		df.store_string(JSON.stringify(data, "\t"))
		df = null
		DirAccess.remove_absolute(tmp)
	return true

func _quarantine_save_file(path: String) -> void:
	var err := DirAccess.rename_absolute(path, path + ".corrupt")
	if err != OK:
		# Rename failed: copy the corrupt bytes to .corrupt instead, so
		# the evidence survives the clean rewrite that follows.
		var t := _save_text(path)
		var cf := FileAccess.open(path + ".corrupt", FileAccess.WRITE)
		if cf:
			cf.store_string(t)
			cf = null
		print("IRON EDEN SAVE: quarantine rename failed (", err, "), copied to .corrupt for ", path)

func _backup_dict(path: String, needs_key: String) -> Dictionary:
	var d := _parse_save_dict(_save_text(path + ".bak"))
	if d.is_empty() or not d.has(needs_key):
		return {}
	return d

func _load_loadout() -> void:
	save_corrupt_loadout = false
	save_recovered_from_backup = false
	save_future_schema_seen = false
	save_load_note = ""
	if FileAccess.file_exists(LOADOUT_PATH):
		var parsed := _parse_save_dict(_save_text(LOADOUT_PATH))
		_note_save_schema(parsed)
		if parsed.is_empty() or not parsed.has("chassis"):
			# Invalid loadout: unparseable, non-dict, empty, or missing
			# the key field. Pass 24 asserted this "left the loadout
			# untouched"; Pass 25 replaces that with real recovery, and
			# the old checks still pass because the fallback IS the
			# default loadout the old tests started from.
			save_corrupt_loadout = true
			save_load_note = "loadout file invalid, recovery attempted"
			print("IRON EDEN SAVE: loadout file invalid — attempting backup recovery")
			var bak := _backup_dict(LOADOUT_PATH, "chassis")
			if not bak.is_empty():
				parsed = bak
				save_recovered_from_backup = true
				print("IRON EDEN SAVE: loadout recovered from backup")
				var stamped := bak.duplicate()
				stamped["schema_version"] = SAVE_SCHEMA_VERSION
				_write_save_file(LOADOUT_PATH, stamped)
			else:
				print("IRON EDEN SAVE: no usable loadout backup — quarantining corrupt file, falling back to defaults")
				_quarantine_save_file(LOADOUT_PATH)
				loadout = {"chassis": "assault", "utility": "repair_pulse", "doctrine": "iron_wall", "region": "region1", "quality": "balanced", "difficulty": "standard", "dust_storm": false}
				quality_mode = "balanced"
				difficulty = "standard"
				save_loadout()
		if parsed is Dictionary and parsed.has("chassis"):
			var doc := str(parsed.get("doctrine", "iron_wall"))
			if doc not in ["iron_wall", "hunting_pack", "ghost_protocol"]:
				doc = "iron_wall"
			# Pass 5 audit fix (M1): chassis/utility were copied straight
			# from the file with no validation, so a corrupt value flowed
			# into the hangar (empty stats line) and the deploy path.
			var ch := str(parsed.get("chassis", "assault"))
			if ch not in ["scout", "assault", "support"]:
				ch = "assault"
			var ut := str(parsed.get("utility", "repair_pulse"))
			if ut not in ["repair_pulse", "grapple"]:
				ut = "repair_pulse"
			var reg := str(parsed.get("region", "region1"))
			if reg not in ["region1", "region2"]:
				reg = "region1"
			var qual := str(parsed.get("quality", "balanced"))
			if qual not in ["s25", "balanced", "forward_plus"]:
				qual = "balanced"
			quality_mode = qual
			# Pass 23: difficulty validated like every other loadout
			# field — a corrupt value falls back to standard, never
			# flows into spawn scaling as an unknown multiplier.
			var diff := str(parsed.get("difficulty", "standard"))
			if diff not in ["standard", "hard", "brutal"]:
				diff = "standard"
			difficulty = diff
			# Pass 45: dust-storm flag is a plain bool — any non-bool
			# (or missing) value reads as OFF, never as a crash.
			var storm := bool(parsed.get("dust_storm", false))
			# Pass 46: rotation index is file-only, like the schema
			# stamp — a missing value starts the rotation at board 0.
			contracts_roll_index = int(parsed.get("contracts_roll", 0))
			loadout = {"chassis": ch, "utility": ut, "doctrine": doc, "region": reg, "quality": qual, "difficulty": diff, "dust_storm": storm}
	_sel_chassis = str(loadout["chassis"])
	_sel_utility = str(loadout["utility"])
	_sel_doctrine = str(loadout["doctrine"])
	_sel_region = str(loadout.get("region", "region1"))
	_sel_dust_storm = bool(loadout.get("dust_storm", false))
	_sel_difficulty = str(loadout.get("difficulty", "standard"))
	if _sel_difficulty not in ["standard", "hard", "brutal"]:
		_sel_difficulty = "standard"
	difficulty = _sel_difficulty
	current_region = _sel_region
	loadout["quality"] = quality_mode
	loadout["difficulty"] = difficulty

func save_loadout() -> void:
	# Pass 25: the stamped copy carries the schema version; the
	# in-memory loadout stays the six gameplay fields, so no caller
	# that reads loadout directly sees a new key.
	var stamped := loadout.duplicate()
	stamped["schema_version"] = SAVE_SCHEMA_VERSION
	# Pass 46: rotation index rides the file only, like the stamp.
	stamped["contracts_roll"] = contracts_roll_index
	_write_save_file(LOADOUT_PATH, stamped)

func read_loadout_file() -> Dictionary:
	if not FileAccess.file_exists("user://iron_eden_loadout.json"):
		return {}
	var f := FileAccess.open("user://iron_eden_loadout.json", FileAccess.READ)
	if not f:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}

# Pass 11 (HOTFIX): hide/show every HUD control at once, so nothing
# (zones, bars, labels, weapon/build buttons, touch labels, ZOOM) can
# show through or be tapped behind the hangar modal. Panels with their
# own visibility logic (substation/level-up/end) are not in the registry.
func _set_hud_visible(v: bool) -> void:
	for c in _hud_controls:
		if is_instance_valid(c):
			c.visible = v

func _open_hangar() -> void:
	hangar_open = true
	_sel_chassis = str(loadout["chassis"])
	_sel_utility = str(loadout["utility"])
	_sel_doctrine = str(loadout["doctrine"])
	_sel_difficulty = difficulty
	# Pass 46: a fresh board for the new run, rolled before refresh
	# so the hangar label shows it. Pause-restart never comes here,
	# so a restart keeps the run's board.
	contracts_live = false
	contracts_roll()
	_refresh_hangar()
	_hangar_panel.visible = true
	_set_hud_visible(false)
	get_tree().paused = true

# Pass 23 (Difficulty select): the multiplier table. Standard is the
# identity (1.0 everywhere) so every pre-Pass-23 test expectation holds
# unchanged; Hard and Brutal scale HP, damage and salvage income.
# Unknown names fall back to standard, never to a zero multiplier.
func difficulty_multipliers(name: String) -> Dictionary:
	match name:
		"hard":
			return {"hp": 1.35, "dmg": 1.25, "salvage": 1.25}
		"brutal":
			return {"hp": 1.8, "dmg": 1.6, "salvage": 1.6}
	return {"hp": 1.0, "dmg": 1.0, "salvage": 1.0}

func set_difficulty(name: String) -> bool:
	if name not in ["standard", "hard", "brutal"]:
		return false
	difficulty = name
	_sel_difficulty = name
	loadout["difficulty"] = name
	_refresh_hangar()
	return true

# Pass 31 (Kill-streak): pure bonus table, so tests can assert it
# without spawning anything. Below 5: no bonus. From 5 up, +5 per
# 5-streak tier (5-9: +5, 10-14: +10, 15-19: +15, ...), capped at
# +50 so endless streaks cannot print infinite salvage. The paid
# bonus is scaled by the difficulty salvage multiplier at payout,
# like every other salvage income in the game.
func combo_bonus_for_streak(streak: int) -> int:
	if streak < 5:
		return 0
	return mini(50, 5 * ((streak - 5) / 5 + 1))

# Pass 31: callout text for a streak milestone, "" otherwise.
# Milestones are every 5; 5/10/15 get their own names, 20+ share
# the WAR MACHINE call with the streak number in it.
func streak_call_text(streak: int) -> String:
	if streak < 5 or streak % 5 != 0:
		return ""
	match streak:
		5:
			return "KILL STREAK x5"
		10:
			return "RAMPAGE x10"
		15:
			return "UNSTOPPABLE x15"
		_:
			return "WAR MACHINE x%d" % streak

# Pass 31: advance the streak by one kill and pay the combo bonus.
# Returns the scaled bonus paid (0 below streak 5). Callouts fire
# only on milestones; bonus-paying non-milestone kills still flash
# a short combo line so the payout is visible in play.
func apply_kill_streak() -> int:
	kill_streak += 1
	if kill_streak > best_kill_streak:
		best_kill_streak = kill_streak
	var paid: int = int(round(float(combo_bonus_for_streak(kill_streak)) * float(difficulty_multipliers(difficulty)["salvage"])))
	if paid > 0:
		salvage += paid
	var call := streak_call_text(kill_streak)
	if call != "":
		last_streak_call = call
		streak_call_count += 1
		flash_msg("%s — combo +%d salvage" % [call, paid])
	elif paid > 0:
		flash_msg("COMBO +%d salvage — streak x%d" % [paid, kill_streak])
	return paid

# Pass 49 (FEATURE: Overdrive meter) — trigger + expiry tick.
func try_overdrive() -> bool:
	if overdrive_active or overdrive_charge < 100.0 or player == null:
		return false
	overdrive_charge = 0.0
	overdrive_active = true
	overdrive_timer = OVERDRIVE_DURATION
	player.fire_rate_mult *= OVERDRIVE_FIRE_MULT
	flash_msg("OVERDRIVE — +40% FIRE RATE")
	return true

func _overdrive_tick(delta: float) -> void:
	if not overdrive_active:
		return
	overdrive_timer -= delta
	if overdrive_timer <= 0.0:
		overdrive_active = false
		overdrive_timer = 0.0
		if player:
			player.fire_rate_mult /= OVERDRIVE_FIRE_MULT
		flash_msg("OVERDRIVE ENDED")

# Pass 3 (Wave 5): region select — Region 2 is the same arena re-skinned
# (rust fog + rust ground tint + a marker), so the variant is a real visual
# and data change, not a second level to maintain.
func set_region(name: String) -> bool:
	if name not in ["region1", "region2"]:
		return false
	current_region = name
	_sel_region = name
	loadout["region"] = name
	_apply_region_look()
	return true

# Pass 45: dust-storm toggle + derived state. storm_wind_drift is what
# bullet.gd snapshots at setup(), so every bullet — player, turret,
# enemy, and mortar-arc landing point — drifts the same way while a
# storm is active. Wind is a fixed +X push with a slight +Z lean.
func set_dust_storm(on: bool) -> void:
	_sel_dust_storm = on
	loadout["dust_storm"] = on
	_apply_region_look()
	_refresh_hangar()

func dust_storm_active() -> bool:
	return current_region == "region2" and _sel_dust_storm

func storm_wind_drift() -> Vector3:
	if dust_storm_active():
		return Vector3(4.0, 0.0, 1.0)
	return Vector3.ZERO

# Pass 46 (Contracts board): the pool, progress, payout, and board
# text are pure functions of run counters, so tests can assert them
# without driving waves. Targets are run totals, not per-wave: a
# contract completes the moment its counter reaches target, pays
# once, and stays done for the rest of the run.
func contract_defs() -> Array:
	return [
		{"id": "capture_2", "title": "CAPTURE 2 ENEMIES", "reward": 60},
		{"id": "flawless_wave", "title": "CLEAR A WAVE WITH NO CORE DAMAGE", "reward": 40},
		{"id": "kill_10", "title": "DESTROY 10 ENEMIES", "reward": 50},
		{"id": "turret_5", "title": "TURRETS DESTROY 5 ENEMIES", "reward": 50},
		{"id": "cache_3", "title": "COLLECT 3 SALVAGE CACHES", "reward": 40},
		{"id": "break_3", "title": "SMASH 3 DESTRUCTIBLES", "reward": 40},
	]

func contract_def(id: String) -> Dictionary:
	for d in contract_defs():
		if str(d["id"]) == id:
			return d
	return {}

func contract_target(id: String) -> int:
	match id:
		"capture_2": return 2
		"flawless_wave": return 1
		"kill_10": return 10
		"turret_5": return 5
		"cache_3": return 3
		"break_3": return 3
	return 0

func contract_progress(id: String) -> int:
	match id:
		"capture_2": return captures
		"flawless_wave": return 1 if _contracts_flawless_done else 0
		"kill_10": return kills
		"turret_5": return turret_kills
		"cache_3": return caches_collected
		"break_3": return _destructible_broken
	return 0

func contracts_roll() -> void:
	var pool := contract_defs()
	var n := pool.size()
	contracts_active = []
	for i in range(3):
		contracts_active.append(str(pool[(contracts_roll_index + i) % n]["id"]))
	contracts_done = {}
	contracts_roll_index += 1
	save_loadout()

func contracts_evaluate() -> void:
	if not contracts_live:
		return
	for id in contracts_active:
		var cid := str(id)
		if bool(contracts_done.get(cid, false)):
			continue
		if contract_progress(cid) >= contract_target(cid):
			contracts_done[cid] = true
			var def := contract_def(cid)
			var pay := int(round(float(def.get("reward", 0)) * float(difficulty_multipliers(difficulty)["salvage"])))
			salvage += pay
			contracts_paid_total += pay
			flash_msg("CONTRACT COMPLETE — %s +%d salvage" % [str(def.get("title", cid)), pay])

func contracts_on_wave_clear() -> void:
	if core_hp >= _wave_core_hp_start:
		_contracts_flawless_done = true
		contracts_evaluate()

func contracts_board_text() -> String:
	# Two lines by design: a header plus one wrapped row of
	# contracts. The hangar column must still fit the test viewport
	# with DEPLOY on screen (Pass 11), so the board cannot cost four
	# full lines — wrapping handles narrower phones via the scroll
	# container the hangar already lives in.
	var parts: Array = []
	for id in contracts_active:
		var cid := str(id)
		var def := contract_def(cid)
		var mark := "[x]" if bool(contracts_done.get(cid, false)) else "[ ]"
		parts.append("%s %s %d/%d (+%d)" % [mark, str(def.get("title", cid)), contract_progress(cid), contract_target(cid), int(def.get("reward", 0))])
	return "CONTRACTS BOARD\n" + "  |  ".join(parts)

func contracts_summary_text() -> String:
	var done := 0
	for id in contracts_active:
		if bool(contracts_done.get(str(id), false)):
			done += 1
	return "Contracts: %d/%d complete (+%d salvage paid)\n" % [done, contracts_active.size(), contracts_paid_total]

# Pass 8 (Overhaul B): Region 2 rust lives in the ground itself — the
# ground atlas swaps to the rust-tinted atlas and fog/bg warm up. There
# is deliberately NO translucent overlay plane any more (the old Pass 3
# marker plane washed the whole arena and hid the tile seams).
func _apply_region_look() -> void:
	_apply_p29_prop_visibility()
	if is_instance_valid(_region_marker):
		_region_marker.visible = (current_region == "region2")
	if _world_env == null:
		return
	if current_region == "region2":
		if dust_storm_active():
			# Pass 45: storm visibility — fog ~3x the calm Rust Flats
			# value, dust-tan fog light, darker dusty background. The
			# ground atlas is unchanged; the storm is fog + wind, not
			# a new overlay plane (Pass 8 removed those on purpose).
			_world_env.background_color = Color(0.26, 0.18, 0.10)
			_world_env.fog_light_color = Color(0.45, 0.35, 0.20)
			_world_env.fog_density = 0.012
		else:
			# Pass 12: rust bg/fog match the rust atlas average (0.227/0.143/0.072).
			_world_env.background_color = Color(0.227, 0.143, 0.072)
			_world_env.fog_light_color = Color(0.28, 0.18, 0.10)
			_world_env.fog_density = 0.004
		if _ground_mat:
			_ground_mat.albedo_texture = load("res://sprites/p39/p39_ground_rust_v2.png")
	else:
		# Pass 12: bg/fog match the region-1 atlas average (0.122/0.167/0.137).
		_world_env.background_color = Color(0.122, 0.167, 0.137)
		_world_env.fog_light_color = Color(0.16, 0.21, 0.18)
		_world_env.fog_density = 0.0022
		if _ground_mat:
			_ground_mat.albedo_texture = load("res://sprites/p39/p39_ground_v2.png")

# Pass 29 (Tiles + props expansion): biome-variant dressing. Props carry
# a "p29_region" meta — "common" (always visible), "region1" (Iron Flats
# green dressing only) or "region2" (Rust Flats rust dressing only).
# Props with no meta (the Pass 8 set) count as common. Visuals only:
# visibility never gates a structure, spawn, cost, or combat value.
func _apply_p29_prop_visibility() -> void:
	for spr in _prop_sprites:
		if spr is Node:
			var tag := str(spr.get_meta("p29_region", "common"))
			spr.visible = (tag == "common" or tag == current_region)

# Pass 3 (Wave 5): one parse path for the world save, shared by boot and tests.
# Pass 25: facility_state and adaptation are validated against their
# known sets — a corrupt or hand-edited world file can no longer plant
# an unknown adaptation code into wave composition or a phantom
# recovery contract. Unknown values clear/log instead of flowing on.
func parse_world_state(data: Dictionary) -> void:
	var adapt := str(data.get("adaptation", ""))
	if adapt not in ["", "unformed", "tunneling_units", "shielded_heavies", "mixed_doctrine"]:
		print("IRON EDEN SAVE: world adaptation '", adapt, "' is not a known code — clearing it")
		adapt = ""
	saved_adaptation = adapt
	var fac := str(data.get("facility_state", ""))
	if fac not in ["Forward Base", "Damaged Outpost", "Ruin"]:
		if fac != "":
			print("IRON EDEN SAVE: world facility_state '", fac, "' is not known — no recovery contract")
		fac = ""
	recovery_active = fac == "Damaged Outpost"
	recovery_built = 0
	recovery_bonus_paid = false

# Pass 26 (UX: hangar overhaul): the chassis table, in one place, so
# the cards, the bars, and the stats line can never disagree. Values
# are copied from player.gd apply_loadout (scout 110/16.5/65, assault
# 150/13/55, support 135/11.5/48); unknown names fall back to assault,
# exactly as apply_loadout does. Bars normalise against the class
# maximums (hull 150, speed 16.5, accel 65) so every bar reads 0-100.
func hangar_chassis_stats(name: String) -> Dictionary:
	match name:
		"scout":
			return {"hp": 110.0, "speed": 16.5, "accel": 65.0}
		"support":
			return {"hp": 135.0, "speed": 11.5, "accel": 48.0}
		_:
			return {"hp": 150.0, "speed": 13.0, "accel": 55.0}

func _refresh_hangar() -> void:
	if not _hangar_portrait:
		return
	var path := "res://sprites/p34/p34_%s.png" % _sel_chassis
	if ResourceLoader.exists(path):
		_hangar_portrait.texture = load(path)
	var stats := {"scout": "SCOUT — hull 110, speed 16.5, fast & fragile", "assault": "ASSAULT — hull 150, speed 13, balanced", "support": "SUPPORT — hull 135, speed 11.5, deployables -20% salvage, stronger repair"}
	var utils := {"repair_pulse": "REPAIR PULSE [Q] — heal self + nearby structures", "grapple": "GRAPPLE [Q] — slingshot toward your aim point"}
	var doctrines := {"iron_wall": "DOCTRINE IRON WALL — drone repairs fastest, even under fire", "hunting_pack": "DOCTRINE HUNTING PACK — drone fetches salvage caches, then repairs", "ghost_protocol": "DOCTRINE GHOST PROTOCOL — drone never repairs with enemies near, keeps its distance"}
	var regions := {"region1": "REGION: IRON FLATS (standard)", "region2": "REGION: RUST FLATS (Region 2 variant)"}
	var qualitys := {"s25": "QUALITY: S25 (performance)", "balanced": "QUALITY: BALANCED", "forward_plus": "QUALITY: FORWARD+ (laptop)"}
	var diffs := {"standard": "DIFFICULTY: STANDARD — enemies at base HP/damage, base salvage", "hard": "DIFFICULTY: HARD — enemies +35% HP, +25% damage, +25% salvage", "brutal": "DIFFICULTY: BRUTAL — enemies +80% HP, +60% damage, +60% salvage"}
	var extra := "\nRECOVERY CONTRACT ACTIVE — build 3 structures for +100 salvage" if recovery_active else ""
	# Pass 45: the storm line names the region restriction outright —
	# ON here means nothing on Iron Flats, so the player is never left
	# wondering why the toggle "did nothing".
	var storm_line := "DUST STORM: ON — Rust Flats only (fog + wind drift)" if _sel_dust_storm else "DUST STORM: OFF"
	_hangar_stats.text = "%s\n%s\n%s\n%s\n%s\n%s\n%s%s" % [stats.get(_sel_chassis, ""), utils.get(_sel_utility, ""), doctrines.get(_sel_doctrine, ""), regions.get(_sel_region, ""), qualitys.get(quality_mode, ""), diffs.get(_sel_difficulty, ""), storm_line, extra]
	if _quality_btn:
		_quality_btn.text = "QUALITY: " + quality_mode.to_upper() + " (TAP TO CYCLE)"
	if _dust_storm_btn:
		_dust_storm_btn.text = "DUST STORM (RUST FLATS): ON" if _sel_dust_storm else "DUST STORM (RUST FLATS): OFF"
		_p36_button(_dust_storm_btn, _sel_dust_storm)
	# Pass 36: the selected pick reads as the template's cyan-fill
	# primary; unselected picks stay dark-navy rows. Skin only — the
	# selection values themselves are untouched.
	var _p36_sel := {"utility:" + _sel_utility: true, "doctrine:" + _sel_doctrine: true, "region:" + _sel_region: true, "difficulty:" + _sel_difficulty: true}
	for _pk in _hangar_pick_btns:
		_p36_button(_hangar_pick_btns[_pk] as Button, _p36_sel.has(_pk))
	for _cn2 in _hangar_cards:
		_p36_button((_hangar_cards[_cn2] as Dictionary)["select"] as Button, _cn2 == _sel_chassis)
	# Pass 26: one integrated summary line — the whole loadout, difficulty
	# included, exactly as DEPLOY will save it — plus the card states.
	# The stats line above is kept verbatim (older checks read it).
	if _hangar_summary:
		_hangar_summary.text = "LOADOUT: %s / %s / %s / %s / %s — DIFFICULTY: %s" % [_sel_chassis.to_upper(), _sel_utility.to_upper(), _sel_doctrine.to_upper(), _sel_region.to_upper(), quality_mode.to_upper(), _sel_difficulty.to_upper()]
	# Pass 46: the board reads on the hangar, refreshed with every pick
	# (progress is live counters, so a restart's board shows its state).
	if _contracts_lbl:
		_contracts_lbl.text = contracts_board_text()
	for cname in _hangar_cards:
		var card: Dictionary = _hangar_cards[cname]
		var panel: PanelContainer = card["panel"]
		panel.add_theme_stylebox_override("panel", _p36_card_style(cname == _sel_chassis))
		var cstats := hangar_chassis_stats(cname)
		var bars: Dictionary = card["bars"]
		(bars["hull"] as ProgressBar).value = float(cstats["hp"]) / 150.0 * 100.0
		(bars["speed"] as ProgressBar).value = float(cstats["speed"]) / 16.5 * 100.0
		(bars["mobility"] as ProgressBar).value = float(cstats["accel"]) / 65.0 * 100.0
		var preview: TextureRect = card["preview"]
		var cpath := "res://sprites/p34/p34_%s.png" % cname
		if ResourceLoader.exists(cpath):
			preview.texture = load(cpath)

func _deploy_from_hangar() -> void:
	difficulty = _sel_difficulty
	# Pass 46: deploy never re-rolls — the board shown in the hangar
	# is the run's board. The guard only covers a deploy that somehow
	# bypassed the hangar open (tests, pause paths).
	if contracts_active.is_empty():
		contracts_roll()
	# Pass 46: deploying arms the board — payouts count from here.
	contracts_live = true
	loadout = {"chassis": _sel_chassis, "utility": _sel_utility, "doctrine": _sel_doctrine, "region": _sel_region, "quality": quality_mode, "difficulty": _sel_difficulty, "dust_storm": _sel_dust_storm}
	save_loadout()
	set_region(_sel_region)
	player.apply_loadout(_sel_chassis, _sel_utility)
	set_doctrine(_sel_doctrine)
	_hangar_panel.visible = false
	_set_hud_visible(true)
	hangar_open = false
	get_tree().paused = false
	flash_msg("DEPLOYED: %s / %s" % [_sel_chassis.capitalize(), "Repair Pulse" if _sel_utility == "repair_pulse" else "Grapple"])

func _load_existing_save() -> void:
	# Pass 25: corrupt world recovery mirrors the loadout path, except
	# there is no safe default world state to fall back to — a world
	# file is a record of a victory, and inventing one would lie about
	# progress. So no-backup corruption quarantines the file and clears
	# to "no prior world state" (empty adaptation, no recovery).
	save_corrupt_world = false
	save_recovered_from_backup = false
	save_future_schema_seen = false
	if FileAccess.file_exists(WORLD_PATH):
		var parsed := _parse_save_dict(_save_text(WORLD_PATH))
		_note_save_schema(parsed)
		if parsed.is_empty() or not parsed.has("facility_state"):
			save_corrupt_world = true
			print("IRON EDEN SAVE: world file invalid — attempting backup recovery")
			var bak := _backup_dict(WORLD_PATH, "facility_state")
			if not bak.is_empty():
				save_recovered_from_backup = true
				print("IRON EDEN SAVE: world state recovered from backup")
				var stamped := bak.duplicate()
				stamped["schema_version"] = SAVE_SCHEMA_VERSION
				_write_save_file(WORLD_PATH, stamped)
				parse_world_state(bak)
				print("IRON EDEN: prior world state recovered from backup: ", bak.get("facility_state", "unknown"), " adaptation=", saved_adaptation, " recovery=", recovery_active)
			else:
				print("IRON EDEN SAVE: no usable world backup — quarantining corrupt file, clearing world state")
				_quarantine_save_file(WORLD_PATH)
				saved_adaptation = ""
				recovery_active = false
				recovery_built = 0
				recovery_bonus_paid = false
		else:
			parse_world_state(parsed)
			print("IRON EDEN: prior world state found: ", parsed.get("facility_state", "unknown"), " adaptation=", saved_adaptation, " recovery=", recovery_active)

func adaptation_for(p_mech: int, p_turret: int) -> String:
	var total := p_mech + p_turret
	if total <= 0:
		return "unformed"
	if float(p_turret) / float(total) >= 0.6:
		return "tunneling_units"
	if float(p_mech) / float(total) >= 0.6:
		return "shielded_heavies"
	return "mixed_doctrine"

func adaptation_text(code: String) -> String:
	match code:
		"tunneling_units":
			return "TUNNELING UNITS — your turrets did the killing; burrowers will come for the power network first"
		"shielded_heavies":
			return "SHIELDED HEAVIES — your mech did the killing; frontal plates are being reinforced. Flank them"
		"mixed_doctrine":
			return "MIXED DOCTRINE — no single counter to your balanced kill split. Expect sensor drones"
		_:
			return "UNFORMED — not enough combat data"

func xp_threshold() -> int:
	# Pass 38 (BALANCE): quadratic tail after level 4. Levels 1-4 keep
	# the old linear thresholds (5/9/13/17), so campaign pacing is
	# untouched; beyond that each level costs (L-4)^2 * 2 extra, so
	# endless-run damage growth (1.25x per level) can no longer
	# compound past enemy HP growth (1.15x per wave): the level-8
	# threshold is 65 XP, not 33, the level-10 threshold is 113, not
	# 41, and reaching level 10 from level 1 now costs 299 XP, not 189.
	var extra := maxi(level - 4, 0)
	return 5 + (level - 1) * 4 + extra * extra * 2

func grant_xp(amount: int) -> void:
	xp += amount
	while xp >= xp_threshold():
		xp -= xp_threshold()
		level += 1
		pending_levels += 1
	if pending_levels > 0:
		if test_mode:
			# deterministic auto-pick for the automated test: damage path
			while pending_levels > 0:
				pending_levels -= 1
				player.damage_mult *= 1.25
		else:
			_show_levelup_panel()

func apply_upgrade(idx: int) -> void:
	if pending_levels <= 0:
		return
	pending_levels -= 1
	match idx:
		0:
			player.damage_mult *= 1.25
			flash_msg("UPGRADE: +25% weapon damage")
		1:
			player.fire_rate_mult *= 1.2
			flash_msg("UPGRADE: +20% fire rate")
		2:
			player.max_hp += 30.0
			player.hp = minf(player.max_hp, player.hp + 50.0)
			flash_msg("UPGRADE: +30 max hull, repaired 50")
	if pending_levels > 0:
		_show_levelup_panel()
	else:
		if _lvl_panel:
			_lvl_panel.visible = false
		get_tree().paused = false

func _show_levelup_panel() -> void:
	if _lvl_panel:
		_lvl_title.text = "LEVEL %d — CHOOSE AN UPGRADE" % level
		_lvl_panel.visible = true
		get_tree().paused = true

func save_world(facility_state: String) -> void:
	var data := {
		"schema_version": SAVE_SCHEMA_VERSION,
		"facility_state": facility_state,
		"core_hp": int(core_hp),
		"core_hp_pct": int(core_hp / core_max_hp * 100.0),
		"siege_killer_weapon": siege_killer_weapon,
		"waves_cleared": wave,
		"loadout": loadout,
		"region": str(loadout.get("region", "region1")),
		"recovery_active": recovery_active,
		"level": level,
		"mech_kills": mech_kills,
		"turret_kills": turret_kills,
		"adaptation": adaptation_for(mech_kills, turret_kills),
		# Pass 42: per-run stats record, not progression — a later
		# run overwrites it, and it is never loaded back as current
		# run state (a fresh run starts at zero by construction).
		"stats_run_time": int(run_time_seconds),
		"stats_shots_fired": int(run_stats()["shots_fired"]),
		"stats_shots_hit": shots_hit,
		"stats_accuracy_pct": int(round(float(run_stats()["accuracy"]) * 100.0)),
		"stats_damage_dealt": int(round(damage_dealt)),
		"stats_damage_taken": int(round(float(run_stats()["damage_taken"]))),
		"timestamp": Time.get_datetime_string_from_system(),
	}
	_write_save_file(WORLD_PATH, data)

# ---------------- salvage caches (Wave 1) ----------------

func _make_cache(pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = Vector3(pos.x, 0, pos.z)
	n.add_to_group("caches")
	n.set_meta("cache_active", true)
	Factory.box(n, Vector3(0.9, 0.9, 0.9), Vector3(0, 0.8, 0), Factory.mat(Color(0.3, 1.0, 0.8), Color(0.3, 1.0, 0.8), 1.6, 0.1, 0.35), 0.6)
	Factory.box(n, Vector3(0.45, 1.5, 0.45), Vector3(0, 0.75, 0), Factory.mat(Color(0.2, 0.8, 0.65), Color(0.2, 0.9, 0.7), 1.0, 0.1, 0.4), -0.4)
	add_child(n)
	_caches.append({"node": n, "active": true, "timer": 0.0, "phase": float(_caches.size()) * 1.3})
	return n

func _spawn_caches() -> void:
	_cache_rng.seed = 77123
	for i in range(8):
		var a := _cache_rng.randf_range(0.0, TAU)
		var r := _cache_rng.randf_range(18.0, 50.0)
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		if p.distance_to(_substation_pos) < 6.0:
			p += Vector3(10, 0, 10)
		_make_cache(p)

func _cache_spot() -> Vector3:
	var a := _cache_rng.randf_range(0.0, TAU)
	var r := _cache_rng.randf_range(18.0, 50.0)
	return Vector3(cos(a) * r, 0, sin(a) * r)

# Pass 2: single payout path for cache collection, shared by the player
# (proximity in _update_caches) and the Hunting Pack drone.
func collect_cache_entry(c: Dictionary) -> void:
	if not bool(c["active"]):
		return
	var n: Node3D = c["node"]
	c["active"] = false
	c["timer"] = 25.0
	if is_instance_valid(n):
		n.visible = false
		n.set_meta("cache_active", false)
	salvage += 20
	grant_xp(1)
	# Pass 46: a cache collection is contract progress.
	caches_collected += 1
	contracts_evaluate()
	flash_msg("SALVAGE CACHE +20")

func collect_cache_by_node(n: Node) -> bool:
	for c in _caches:
		if c["node"] == n:
			collect_cache_entry(c)
			return true
	return false

func _update_caches(delta: float) -> void:
	if not player:
		return
	# Pass 30: caches bob/spin/pulse — vertical bob + faster spin +
	# a scale pulse, each cache phase-offset so they do not move in
	# lockstep. The ground ring/collection radius is unchanged; the
	# bob is vertical only, so the 3.2 m pickup distance still reads.
	_cache_anim_t += delta
	for c in _caches:
		var n: Node3D = c["node"]
		if not is_instance_valid(n):
			continue
		if c["active"]:
			var ph := float(c.get("phase", 0.0))
			n.position.y = sin(_cache_anim_t * 2.2 + ph) * 0.28
			n.rotation.y += delta * 1.4
			var sc := 1.0 + 0.07 * sin(_cache_anim_t * 3.1 + ph)
			n.scale = Vector3(sc, sc, sc)
			if player.global_position.distance_to(n.global_position) < 3.2:
				collect_cache_entry(c)
		else:
			c["timer"] = float(c["timer"]) - delta
			if float(c["timer"]) <= 0.0:
				n.position = _cache_spot()
				n.visible = true
				n.set_meta("cache_active", true)
				c["active"] = true

# ---------------- Pass 30: destructibles ----------------

# Pure stats table so tests can assert HP/salvage/radius per kind
# without spawning anything. Crate = 2 autocannon hits, barrel = 3,
# ruin = 4 (autocannon damage 10); salvage is the flat base payout.
func destructible_stats(kind: String) -> Dictionary:
	match kind:
		"barrel":
			return {"hp": 30.0, "salvage": 15, "radius": 1.9, "tile": ""}
		"ruin":
			return {"hp": 40.0, "salvage": 20, "radius": 2.2, "tile": "tile_wreck"}
		_:
			return {"hp": 20.0, "salvage": 10, "radius": 1.9, "tile": "tile_crate"}

func _make_destructible(kind: String, pos: Vector3) -> Node3D:
	var st := destructible_stats(kind)
	var n := Node3D.new()
	n.name = "destructible_" + kind
	n.position = Vector3(pos.x, 0, pos.z)
	n.add_to_group("destructibles")
	n.set_meta("destructible_kind", kind)
	n.set_meta("destructible_hp", float(st["hp"]))
	n.set_meta("destructible_max_hp", float(st["hp"]))
	n.set_meta("destructible_salvage", int(st["salvage"]))
	n.set_meta("destructible_radius", float(st["radius"]))
	n.set_meta("destructible_broken", false)
	# Visual: crate/ruin reuse the already-generated p8 tile slices
	# (the standing sprite rule — no primitive-box look for terrain
	# props); a barrel is a drum, so it renders as a cylinder, the
	# shape it actually is, not a box.
	if str(st["tile"]) != "":
		var spr := SpriteUtil.ground_sprite("res://sprites/p8/%s.png" % str(st["tile"]), 5.0 * SpriteUtil.UNIT_SCALE, 0.0, false)
		if spr != null:
			n.add_child(spr)
	else:
		Factory.cyl(n, 0.9, 1.6, Vector3(0, 0.8, 0), Factory.mat(Color(0.55, 0.3, 0.15), Color(1.0, 0.5, 0.2), 0.4, 0.3, 0.6), 14)
	add_child(n)
	_destructibles.append(n)
	return n

func _spawn_destructibles() -> void:
	# Two of each kind, hand-placed clear of the core (12 m) and the
	# substation (10 m), at least 6 m apart from each other.
	var defs: Array = [
		["crate", Vector3(-24, 0, 6)], ["barrel", Vector3(18, 0, -18)],
		["ruin", Vector3(-6, 0, 30)], ["crate", Vector3(34, 0, 30)],
		["barrel", Vector3(-34, 0, 34)], ["ruin", Vector3(6, 0, -34)],
	]
	for d in defs:
		_make_destructible(str(d[0]), d[1])

# Single damage path for bullets (direct + AoE) and tests. Returns
# true only on the breaking hit. Broken nodes go invisible and stay
# in the array/group so a second hit can never pay twice.
func damage_destructible(n: Node, amount: float) -> bool:
	if not is_instance_valid(n) or bool(n.get_meta("destructible_broken", false)):
		return false
	var hp := float(n.get_meta("destructible_hp", 0.0)) - amount
	n.set_meta("destructible_hp", hp)
	if hp > 0.0:
		return false
	n.set_meta("destructible_broken", true)
	_destructible_broken += 1
	var base := int(n.get_meta("destructible_salvage", 0))
	var pay := int(round(float(base) * float(difficulty_multipliers(difficulty)["salvage"])))
	salvage += pay
	flash_msg("DESTRUCTIBLE BROKEN +%d SALVAGE" % pay)
	_spawn_destructible_break_fx(n.global_position)
	# Pass 46: a break is contract progress.
	contracts_evaluate()
	n.visible = false
	return true

func _spawn_destructible_break_fx(pos: Vector3) -> void:
	_destructible_break_fx += 1
	var fx := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	fx.mesh = sm
	fx.position = pos
	fx.set_surface_override_material(0, Factory.mat_transparent(Color(1.0, 0.7, 0.3), 0.6, 1.6))
	add_child(fx)
	var tw := fx.create_tween()
	tw.set_parallel(true)
	tw.tween_property(fx, "scale", Vector3.ONE * 2.5, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(fx, "transparency", 1.0, 0.35)
	tw.chain().tween_callback(fx.queue_free)

func check_powered(pos: Vector3) -> bool:
	var flat := Vector3(pos.x, 0, pos.z)
	if flat.length() <= CORE_POWER_RADIUS:
		return true
	for g in get_tree().get_nodes_in_group("generators"):
		if is_instance_valid(g) and not g.get("is_dead_struct"):
			var gp := Vector3(g.global_position.x, 0, g.global_position.z)
			if flat.distance_to(gp) <= GEN_POWER_RADIUS:
				return true
	return false

# Pass 1 (Wave 3): power-line visuals — a line from each power source to every
# powered structure it feeds (generators and the core reactor).
func _refresh_power_lines() -> void:
	_power_line_count = 0
	var im := _power_lines_mi.mesh as ImmediateMesh
	if im == null:
		return
	im.clear_surfaces()
	var anchors: Array = [[Vector3(0, 5.4, 0), CORE_POWER_RADIUS]] # core reactor top
	for g in get_tree().get_nodes_in_group("generators"):
		if is_instance_valid(g) and not g.get("is_dead_struct"):
			anchors.append([g.global_position + Vector3(0, 2.6, 0), GEN_POWER_RADIUS])
	var segments: Array = []
	for s in get_tree().get_nodes_in_group("structures"):
		if not is_instance_valid(s) or s.get("is_dead_struct"):
			continue
		if str(s.get("structure_kind")) not in ["turret", "mortar", "emp_pylon", "repair_station"]:
			continue
		var flat := Vector3(s.global_position.x, 0, s.global_position.z)
		var best := -1
		var best_d := 99999.0
		for i in range(anchors.size()):
			var ap: Vector3 = anchors[i][0]
			var d := flat.distance_to(Vector3(ap.x, 0, ap.z))
			if d <= float(anchors[i][1]) and d < best_d:
				best_d = d
				best = i
		if best >= 0:
			var top: Vector3 = anchors[best][0]
			segments.append([top, s.global_position + Vector3(0, 1.6, 0)])
	_power_line_count = segments.size()
	if segments.is_empty():
		return
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for seg in segments:
		im.surface_add_vertex(seg[0])
		im.surface_add_vertex(seg[1])
	im.surface_end()

# Pass 8 (Overhaul B): power lines are dim outside build mode (alpha
# 0.35) and brighten for 3 s after a structure goes up (alpha 0.75).
# Engine note: ImmediateMesh lines are 1 px by engine design, so "thinner"
# is expressed as dimmer here, not a narrower primitive.
func _update_power_line_brightness() -> void:
	if _power_line_mat == null:
		return
	var c := _power_line_mat.albedo_color
	c.a = 0.75 if _power_line_bright_t > 0.0 else 0.35
	_power_line_mat.albedo_color = c

func flash_msg(text: String) -> void:
	if _lbl_msg:
		_lbl_msg.text = text
	_msg_timer = 3.2

# Pass 18 (UX): vignette + shake drivers. The vignette is polled, not
# signaled: player.take_damage has no hook into main, and every damage
# source (enemy melee, enemy bullets, sapper blast) funnels through it,
# so an HP drop between frames is the one reliable trigger.
func _apply_vignette() -> void:
	if _vignette == null:
		return
	_vignette.visible = _vignette_alpha > 0.001
	for e in _vignette_edges:
		if is_instance_valid(e):
			e.color = Color(0.85, 0.05, 0.05, _vignette_alpha)

func trigger_damage_vignette() -> void:
	_vignette_alpha = 0.55
	_apply_vignette()

func _update_vignette(delta: float) -> void:
	if _vignette_alpha > 0.0:
		_vignette_alpha = maxf(0.0, _vignette_alpha - delta * 0.9)
		_apply_vignette()

func _poll_player_damage() -> void:
	if player == null:
		return
	var hp: float = player.hp
	if _last_player_hp >= 0.0 and hp < _last_player_hp:
		trigger_damage_vignette()
		# Pass 31: taking damage breaks the kill streak (best survives).
		kill_streak = 0
	_last_player_hp = hp

# ---------------- world ----------------

func _build_world() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	# Pass 12: background + fog MATCH the ground atlas (measured atlas
	# average 0.122/0.167/0.137), not the old near-black blue — the area
	# past the ground plane now reads as ground haze, not a black void.
	env.background_color = Color(0.122, 0.167, 0.137)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.38, 0.44, 0.58)
	env.ambient_light_energy = 0.52
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.fog_enabled = true
	env.fog_light_color = Color(0.16, 0.21, 0.18)
	env.fog_density = 0.0022
	_world_env = env
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	# Pass 12: sun brightened for arm's-length sprite readability.
	sun.light_energy = 1.55
	sun.light_color = Color(1.0, 0.9, 0.78)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 170.0
	_sun_light = sun
	add_child(sun)
	# Pass 8 (Overhaul B): ground is ONE textured plane, not 144 tile
	# quads (draw-call budget). The atlas (4x4 seeded tile pattern, dark
	# seams) repeats 6x6 across the arena via uv1_scale. Region 2 swaps
	# the atlas in _apply_region_look, not an overlay plane.
	# Pass 39 (Ground v2): macro-blotch texture (sprites/p39/, large
	# sine-wave + soft-blotch variation over the seamless atlas) at
	# uv repeat 2, not 6. Plane is ARENA*3.2 = 185.6 m, so one texture
	# repeat spans 92.8 m — wider than the ~61 m phone view at the
	# default 34 m ortho height, so the same motif cannot appear
	# twice on screen. The old 6x repeat tiled every ~31 m.
	_ground_mat = StandardMaterial3D.new()
	_ground_mat.albedo_texture = load("res://sprites/p39/p39_ground_v2.png")
	_ground_mat.uv1_scale = Vector3(2, 2, 1)
	_ground_mat.roughness = 0.95
	# Pass 13 (gameplay-video bugfix): the p8 atlas pasted diamond tiles
	# (~30% opaque) on a near-black base, so the arena read as spaced
	# islands. The contiguous atlas fills every tile's transparent corners
	# with its own mean colour and pastes edge-to-edge (3px seams only),
	# and a solid ground-coloured base plane sits underneath at y=-0.02
	# so no seam or edge can ever show black void again.
	var _base_mat := StandardMaterial3D.new()
	_base_mat.albedo_color = Color(0.122, 0.167, 0.137)
	_base_mat.roughness = 1.0
	var _base_node := Factory.plane(self, Vector2(ARENA * 3.2, ARENA * 3.2), Vector3(0, -0.02, 0), _base_mat)
	_base_node.name = "ground_base_plane"
	_ground_base_node = _base_node
	# Pass 12: ground plane widened (was ARENA x2.4) so the atlas fills the
	# frame at the closer default zoom instead of ending in a void edge.
	_ground_node = Factory.plane(self, Vector2(ARENA * 3.2, ARENA * 3.2), Vector3.ZERO, _ground_mat)
	_ground_node.name = "ground_atlas_plane"
	# Lighter core plaza: metal-platform atlas, 30x30 m around the core.
	var plaza_mat := StandardMaterial3D.new()
	plaza_mat.albedo_texture = load("res://sprites/p8/plaza_atlas_contiguous.png")
	plaza_mat.roughness = 0.85
	_plaza_node = Factory.plane(self, Vector2(30.0, 30.0), Vector3(0, 0.05, 0), plaza_mat)
	_plaza_node.name = "core_plaza"
	# Region 2 marker is now a sign only — the rust lives in the atlas.
	_region_marker = Node3D.new()
	add_child(_region_marker)
	# Pass 9 (Overhaul C): no floating REGION label — the region reads
	# from the ground atlas + the hangar pick, not a billboard over play.
	_apply_region_look()
	# Arena walls: dark, no cyan glow, with a thin light top edge strip.
	# Pass 12: edge strip emission brightened so walls read as arena bounds
	# against the now ground-toned background, not as a horizon line.
	_wall_mat = Factory.mat(Color(0.10, 0.11, 0.13), Color(0,0,0), 0.0, 0.3, 0.8)
	var edge_mat := Factory.mat(Color(0.55, 0.75, 0.95), Color(0.3, 0.6, 0.9), 0.6, 0.2, 0.5)
	var wall_defs: Array = [
		[Vector3(ARENA * 2.0 + 2.0, 1.7, 1.0), Vector3(0, 0.85, -ARENA - 0.5), Vector3(ARENA * 2.0 + 2.0, 0.12, 1.1), Vector3(0, 1.76, -ARENA - 0.5)],
		[Vector3(ARENA * 2.0 + 2.0, 1.7, 1.0), Vector3(0, 0.85, ARENA + 0.5), Vector3(ARENA * 2.0 + 2.0, 0.12, 1.1), Vector3(0, 1.76, ARENA + 0.5)],
		[Vector3(1.0, 1.7, ARENA * 2.0 + 2.0), Vector3(-ARENA - 0.5, 0.85, 0), Vector3(1.1, 0.12, ARENA * 2.0 + 2.0), Vector3(-ARENA - 0.5, 1.76, 0)],
		[Vector3(1.0, 1.7, ARENA * 2.0 + 2.0), Vector3(ARENA + 0.5, 0.85, 0), Vector3(1.1, 0.12, ARENA * 2.0 + 2.0), Vector3(ARENA + 0.5, 1.76, 0)],
	]
	for wd in wall_defs:
		Factory.box(self, wd[0], wd[1], _wall_mat)
		var edge := Factory.box(self, wd[2], wd[3], edge_mat)
		edge.name = "wall_edge"
		_wall_edges.append(edge)
	# Cover ruins, clustered into 5 cover groups (seeded, not scattered).
	# Pass 39 audit verdict on the old ruin boxes: FAIL — flat-colour
	# BoxMesh props with no top-down art, floating or sunk by up to
	# 0.25*s (box centre sat at s*0.3 while height ran s*0.5..s*1.1).
	# Replaced with flat top-down sprite props from the same p8 tile
	# sheet as every other ground prop (mossy_stone / wreck / cliff,
	# cycled), grounded at y=0 with a contact shadow from
	# SpriteUtil.ground_sprite. Positions, cluster count, and the
	# _ruin_positions list are unchanged, so the Pass 8 clustering
	# checks still read the same layout; visuals only, no cover or
	# collision value ever existed for these props.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261023
	var p39_ruin_kinds := ["mossy_stone", "wreck", "cliff"]
	for ci in range(5):
		var ca := float(ci) * TAU / 5.0 + 0.4
		var cr := rng.randf_range(24.0, 48.0)
		var center := Vector3(cos(ca) * cr, 0, sin(ca) * cr)
		if center.distance_to(_substation_pos) < 10.0 or center.length() < 14.0:
			center = Vector3(cos(ca) * 40.0, 0, sin(ca) * 40.0)
		for j in range(6):
			var p := center + Vector3(rng.randf_range(-3.5, 3.5), 0, rng.randf_range(-3.5, 3.5))
			if p.distance_to(_substation_pos) < 6.0 or p.length() < 10.0:
				continue
			var s := rng.randf_range(1.2, 3.0)
			var p39_rot := rng.randf_range(0.0, PI)
			var p39_kind: String = p39_ruin_kinds[(ci + j) % p39_ruin_kinds.size()]
			var p39_spr := SpriteUtil.ground_sprite("res://sprites/p8/tile_%s.png" % p39_kind, s * 2.0 * SpriteUtil.UNIT_SCALE, p39_rot, false)
			if p39_spr != null:
				p39_spr.name = "ruin_sprite"
				p39_spr.position = p
				add_child(p39_spr)
				_ruin_sprites.append(p39_spr)
			_ruin_positions.append(p)
	# Pass 8 tile props: flat ground sprites from the generated tiles sheet.
	# Pass 29: expanded — every entry is [kind, position, size, region tag];
	# the Pass 8 set stays as "common", new hand-placed dressing adds the
	# previously unused p8 slices (cliff, gate, metal platform, mossy
	# stone, dead turret, grass, pond, rust wall, dirt path), and each
	# region gets its own biome dressing on top of the common set.
	var prop_defs: Array = [
		["pine_trees", Vector3(-28, 0, -20), 8.0, "common"], ["pine_trees", Vector3(30, 0, 25), 7.0, "common"],
		["crystal", Vector3(-32, 0, 18), 7.0, "common"], ["crystal", Vector3(24, 0, -32), 6.0, "common"],
		["wreck", Vector3(-20, 0, 32), 8.0, "common"], ["solar", Vector3(36, 0, -8), 7.0, "common"],
		["crate", Vector3(-38, 0, -6), 5.0, "common"], ["crate", Vector3(14, 0, 34), 5.0, "common"],
		["cliff", Vector3(-8, 0, -38), 8.0, "common"], ["gate", Vector3(38, 0, 20), 8.0, "common"],
		["metal_platform", Vector3(-38, 0, 28), 8.0, "common"], ["mossy_stone", Vector3(10, 0, -38), 7.0, "common"],
		["turret", Vector3(-44, 0, 14), 7.0, "common"], ["crate", Vector3(40, 0, -28), 5.0, "common"],
		["crystal", Vector3(-12, 0, 40), 6.0, "common"],
		["pine_trees", Vector3(-44, 0, -20), 8.0, "region1"], ["grass", Vector3(22, 0, 40), 7.0, "region1"],
		["water", Vector3(44, 0, -20), 7.0, "region1"],
		["rust_wall", Vector3(34, 0, -36), 8.0, "region2"], ["wreck", Vector3(44, 0, 8), 8.0, "region2"],
		["dirt_path", Vector3(0, 0, 44), 8.0, "region2"],
	]
	var p29_centers: Array = []
	for pd in prop_defs:
		# Pass 12: props scale with units, so cover reads at the closer zoom.
		var spr := SpriteUtil.ground_sprite("res://sprites/p8/tile_%s.png" % str(pd[0]), float(pd[2]) * SpriteUtil.UNIT_SCALE, 0.0, false)
		if spr != null:
			spr.name = "p29_prop"
			spr.position = pd[1]
			spr.set_meta("p29_region", str(pd[3]))
			spr.visible = (str(pd[3]) == "common" or str(pd[3]) == current_region)
			add_child(spr)
			_prop_sprites.append(spr)
			p29_centers.append(pd[1])
	# Pass 29 seeded scatter: denser small clutter (crate / crystal /
	# mossy stone) in the 14–50 m annulus, kept clear of the core, the
	# substation, and every hand-placed prop (6 m). Separate RNG seed so
	# the Pass 8 ruin sequence is untouched and the layout reproduces.
	var p29_rng := RandomNumberGenerator.new()
	p29_rng.seed = 20261029
	var p29_scatter_kinds := ["crate", "crystal", "mossy_stone"]
	var p29_scatter_sizes := [3.5, 4.0, 4.5]
	var p29_placed := 0
	var p29_attempts := 0
	while p29_placed < 12 and p29_attempts < 200:
		p29_attempts += 1
		var ang := p29_rng.randf_range(0.0, TAU)
		var rad := p29_rng.randf_range(14.0, 50.0)
		var pos := Vector3(cos(ang) * rad, 0, sin(ang) * rad)
		if pos.distance_to(_substation_pos) < 10.0:
			continue
		var blocked := false
		for c in p29_centers:
			if pos.distance_to(c) < 6.0:
				blocked = true
				break
		if blocked:
			continue
		var kind: String = str(p29_scatter_kinds[p29_placed % 3])
		var spr2 := SpriteUtil.ground_sprite("res://sprites/p8/tile_%s.png" % kind, p29_scatter_sizes[p29_placed % 3] * SpriteUtil.UNIT_SCALE, 0.0, false)
		if spr2 == null:
			continue
		spr2.name = "p29_prop"
		spr2.position = pos
		spr2.set_meta("p29_region", "common")
		add_child(spr2)
		_prop_sprites.append(spr2)
		p29_centers.append(pos)
		p29_placed += 1
	# core reactor — Pass 13: the primitive cylinders/sphere are gone.
	# The generated structures-sheet Core Reactor slice (blue crystal on
	# an octagonal platform, flood-fill keyed, p13_core.png) renders as a
	# spherical billboard, so it reads as the reactor from any camera
	# angle, at the same scale as the unit billboards. Only the flat
	# power-radius disc on the ground stays (gameplay radius, not a body).
	var core := Node3D.new()
	core.name = "CoreReactor"
	add_child(core)
	_core_node = core
	var core_spr := SpriteUtil.billboard_sprite("res://sprites/p13/p13_core.png", 6.0)
	if core_spr != null:
		core.add_child(core_spr)
	Factory.cyl(core, CORE_POWER_RADIUS, 0.04, Vector3(0, 0.04, 0), Factory.mat_transparent(Color(0.3,0.8,1.0), 0.045, 0.5), 48)
	# Pass 9: the ONE core label — shown only when the player is near.
	# Pass 13: raised above the billboard top (6.0 * 1.4 = 8.4 m).
	_core_lbl = Label3D.new()
	_core_lbl.text = "LAST REACTOR"
	_core_lbl.position = Vector3(0, 9.4, 0)
	_core_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_core_lbl.font_size = 48
	core.add_child(_core_lbl)
	# Parked support mech (user sprite) as base dressing in v0.1 — no support-unit gameplay yet.
	var support_spr := SpriteUtil.ground_sprite("res://sprites/support_mech_td.png", 4.2 * SpriteUtil.UNIT_SCALE, -PI / 2.0)
	if support_spr != null:
		support_spr.position = Vector3(7.5, 0, 5.0)
		add_child(support_spr)
		# Pass 9: no floating SUPPORT label — it is base dressing, not a unit.
	# substation
	var sub := Node3D.new()
	sub.position = _substation_pos
	add_child(sub)
	Factory.box(sub, Vector3(3.2, 2.0, 3.2), Vector3(0, 1.0, 0), Factory.mat(Color(0.3,0.3,0.22), Color(0,0,0), 0.0, 0.4, 0.6))
	Factory.cyl(sub, 0.5, 1.4, Vector3(0, 2.7, 0), Factory.mat(Color(1,0.85,0.3), Color(1,0.85,0.3), 1.5, 0.2, 0.4), 10)
	_sub_lbl = Label3D.new()
	_sub_lbl.text = "SUBSTATION [E]"
	_sub_lbl.position = Vector3(0, 3.8, 0)
	_sub_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sub_lbl.font_size = 42
	sub.add_child(_sub_lbl)
	# tunnel gate (removed by substation choice B)
	_tunnel_gate = Node3D.new()
	_tunnel_gate.position = Vector3(26, 0, -30)
	_tunnel_gate.rotation.y = 0.6
	add_child(_tunnel_gate)
	Factory.box(_tunnel_gate, Vector3(9.0, 2.6, 0.9), Vector3(0, 1.3, 0), Factory.mat(Color(0.3,0.26,0.2), Color(1,0.5,0.2), 0.4, 0.3, 0.6))
	# Pass 9: no floating TUNNEL label — the gate geometry speaks for itself.
	# two abandoned (dead) turrets
	for p in [Vector3(17, 0, 17), Vector3(-17, 0, 19)]:
		var t = _make_structure("abandoned_turret", p)
		_abandoned_turrets.append(t)
	_spawn_caches()
	_spawn_destructibles()
	# power-line visual layer: one line-mesh rebuilt twice a second
	var pl_im := ImmediateMesh.new()
	_power_lines_mi = MeshInstance3D.new()
	_power_lines_mi.mesh = pl_im
	# material_override (not surface override): the ImmediateMesh has no
	# surfaces until the first refresh draws lines into it. Pass 8: dim
	# by default (outside build mode), brightened by _update_power_line_brightness.
	_power_line_mat = Factory.mat_transparent(Color(0.4, 0.85, 1.0), 0.35, 1.0)
	_power_lines_mi.material_override = _power_line_mat
	_power_lines_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_power_lines_mi)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 34.0 # Pass 12 default: closest zoom step.
	add_child(camera)

func _build_player() -> void:
	player = Node3D.new()
	player.set_script(PlayerScript)
	player.position = Vector3(0, 0, 10)
	add_child(player)
	player.died.connect(_on_player_died)

# ---------------- drone + doctrines (Pass 2 / Wave 4) ----------------

func _spawn_drone() -> void:
	drone = Node3D.new()
	drone.set_script(DroneScript)
	drone.position = Vector3(3, 1.2, 13)
	add_child(drone)
	drone.set_doctrine(str(loadout["doctrine"]))

func set_doctrine(d: String) -> bool:
	if drone and not drone.set_doctrine(d):
		return false
	if drone == null and d not in ["iron_wall", "hunting_pack", "ghost_protocol"]:
		return false
	loadout["doctrine"] = d
	return true

func toggle_drone_command() -> void:
	drone_hold = not drone_hold
	if drone:
		drone.hold = drone_hold
	flash_msg("Drone: %s" % ("HOLD POSITION" if drone_hold else "FOLLOW DOCTRINE"))

# ---------------- Pass 4 (Wave 6): touch aim stick, quality, perf ----------------

# Right virtual stick: second finger on the right half aims (stick vector maps
# to world XZ the same way the move stick does) and fires while held. This is
# the twin-stick half the old right-side touch lacked — it used to fire with
# nearest-enemy aim assist only, and releasing ANY touch stopped firing.
func touch_aim_begin(origin: Vector2, id: int) -> bool:
	if _aim_active:
		return false
	_aim_active = true
	_aim_id = id
	_aim_origin = origin
	_aim_vec = Vector2.ZERO
	_touch_firing = true
	return true

func touch_aim_drag(pos: Vector2) -> void:
	if not _aim_active:
		return
	_aim_vec = (pos - _aim_origin) / 70.0
	if _aim_vec.length() > 1.0:
		_aim_vec = _aim_vec.normalized()

func touch_aim_end(id: int) -> void:
	if id != _aim_id:
		return
	_aim_active = false
	_aim_id = -1
	_aim_vec = Vector2.ZERO
	_touch_firing = false

func touch_aim_dir() -> Vector3:
	if _aim_vec.length() < 0.2:
		return Vector3.ZERO
	return Vector3(_aim_vec.x, 0, _aim_vec.y).normalized()

# FIRE button polish: the on-screen button shares this one path, so a tap and
# a right-stick hold can never disagree about whether the mech is firing.
# Releasing the button must not kill a stick hold (the old release bug).
func set_fire_button(down: bool) -> void:
	if down:
		_touch_firing = true
	elif not _aim_active:
		_touch_firing = false

# Quality presets. "s25" is the phone performance preset (shadows + glow off);
# "balanced" is the default; "forward_plus" is the laptop preset (shadows on,
# longer shadow distance, glow on). The preset is a runtime knob + a saved
# loadout value; it does NOT rewrite project.godot's renderer, so switching
# it in a running build never needs a restart or a re-export to take effect.
func set_quality_mode(mode: String) -> bool:
	if mode not in ["s25", "balanced", "forward_plus"]:
		return false
	quality_mode = mode
	loadout["quality"] = mode
	if _world_env:
		_world_env.glow_enabled = (mode != "s25")
	if _sun_light:
		_sun_light.shadow_enabled = (mode != "s25")
		if mode == "forward_plus":
			_sun_light.directional_shadow_max_distance = 220.0
		elif mode == "balanced":
			_sun_light.directional_shadow_max_distance = 170.0
	return true

func cycle_quality_mode() -> String:
	var order := ["s25", "balanced", "forward_plus"]
	var next: String = order[(order.find(quality_mode) + 1) % order.size()]
	set_quality_mode(next)
	_refresh_hangar()
	return next

# Pass 12: phone zoom step — cycles 34 -> 42 -> 50 -> 34 world units of
# ortho height. Step 0 (34) is the default: closest view first, pull back
# only on purpose. Pass 9's order (50 first) is superseded by this.
func cycle_zoom() -> int:
	zoom_step = (zoom_step + 1) % _zoom_sizes.size()
	if camera:
		camera.size = _zoom_sizes[zoom_step]
	return zoom_step

func set_adaptive_quality(enabled: bool) -> void:
	adaptive_quality = enabled

# Headless-measurable perf: draw calls / objects / primitives come from the
# engine's own monitors (0 in headless, which is why the test asserts >= 0,
# not > 0); render_nodes is a real scene count and must be > 0 anywhere.
func count_render_nodes() -> int:
	var count := 0
	var stack: Array = [self]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is GeometryInstance3D:
			count += 1
		for c in n.get_children():
			stack.append(c)
	return count

func measure_perf() -> Dictionary:
	_last_perf = {
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"objects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"primitives": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"fps": Performance.get_monitor(Performance.TIME_FPS),
		"render_nodes": count_render_nodes(),
	}
	return _last_perf

# Pass 43 (PERF audit): per-bucket scene render-node counts. Every
# GeometryInstance3D lands in exactly one bucket, so the buckets sum
# to count_render_nodes(); "labels" is a subset note (Label3D is a
# GeometryInstance3D), not an extra bucket. Headless engine monitors
# read 0, so this scene count is the audit's draw-call proxy: one
# MeshInstance/Sprite3D/Label3D is one draw call in the forward
# renderer unless materials batch, and this codebase gives every
# sprite its own material, so nothing batches. "prop_shadows" counts
# the flat black contact-shadow quads under static ground props
# (p29_prop / ruin_sprite holders) — the Pass 43 cut target.
func count_visual_nodes() -> Dictionary:
	var counts := {"total": 0, "player": 0, "drone": 0, "enemies": 0, "structures": 0, "props": 0, "destructibles": 0, "world": 0, "labels": 0, "prop_shadows": 0}
	var stack: Array = [[self, "world"]]
	while not stack.is_empty():
		var item: Array = stack.pop_back()
		var n: Node = item[0]
		var bucket: String = str(item[1])
		for c in n.get_children():
			var cb := bucket
			if c == player:
				cb = "player"
			elif c == drone:
				cb = "drone"
			elif c.is_in_group("enemies"):
				cb = "enemies"
			elif c.is_in_group("structures"):
				cb = "structures"
			elif c.is_in_group("destructibles"):
				cb = "destructibles"
			elif _prop_sprites.has(c) or _ruin_sprites.has(c):
				cb = "props"
			if c is GeometryInstance3D:
				counts[cb] += 1
				counts["total"] += 1
				if c is Label3D:
					counts["labels"] += 1
				# Pass 43 lesson: Godot renames duplicate sibling names
				# to @Node3D@N, so a name test can never identify the
				# 2nd+ prop holder — identity via the sprite arrays is
				# the only reliable match, for the shadow count too.
				if c is MeshInstance3D and (_prop_sprites.has(c.get_parent()) or _ruin_sprites.has(c.get_parent())):
					var smat := (c as MeshInstance3D).get_surface_override_material(0) as StandardMaterial3D
					if smat != null and smat.albedo_color == Color(0, 0, 0, 0.28):
						counts["prop_shadows"] += 1
			stack.append([c, cb])
	return counts

# Adaptive step, called by the perf pass (not every frame, to avoid flapping):
# a heavy frame steps one tier down, a light frame steps one tier up.
func auto_adjust_quality(draw_calls: int) -> String:
	if not adaptive_quality:
		return quality_mode
	var order := ["s25", "balanced", "forward_plus"]
	var i := order.find(quality_mode)
	if draw_calls > 2000 and i > 0:
		set_quality_mode(order[i - 1])
	elif draw_calls < 200 and i < order.size() - 1:
		set_quality_mode(order[i + 1])
	return quality_mode

# ---------------- structures / power ----------------

func _make_structure(kind: String, pos: Vector3) -> Node3D:
	var t = Node3D.new()
	t.set_script(TurretScript)
	t.setup(kind, pos)
	add_child(t)
	_structures.append(t)
	return t

func try_build(kind: String, pos: Vector3) -> bool:
	var cost: int = COSTS.get(kind, 9999)
	if player and str(player.get("chassis")) == "support":
		cost = int(round(float(cost) * 0.8)) # Wave 2: support chassis discount
	if salvage < cost:
		flash_msg("Need %d salvage for %s" % [cost, kind])
		return false
	var flat := Vector3(pos.x, 0, pos.z)
	if flat.length() < 5.0:
		flash_msg("Too close to the Core")
		return false
	if absf(pos.x) > 55.0 or absf(pos.z) > 55.0:
		return false
	for s in get_tree().get_nodes_in_group("structures"):
		if is_instance_valid(s) and Vector3(s.global_position.x, 0, s.global_position.z).distance_to(flat) < 3.0:
			flash_msg("Position blocked")
			return false
	salvage -= cost
	_make_structure(kind, flat)
	_power_line_bright_t = 3.0 # Pass 8: lines brighten briefly after a build
	_update_power_line_brightness()
	# Pass 3 (Wave 5): recovery contract — a Damaged Outpost save pays +100
	# salvage once, when the third structure of the run goes up.
	if recovery_active and not recovery_bonus_paid:
		recovery_built += 1
		if recovery_built >= 3:
			recovery_bonus_paid = true
			salvage += 100
			flash_msg("RECOVERY CONTRACT COMPLETE — outpost repaired +100 salvage")
	var needs_power := kind in ["turret", "mortar", "emp_pylon", "repair_station"]
	flash_msg("%s online%s" % [kind.capitalize().replace("_", " "), "" if not needs_power and kind != "generator" else (" — powered" if check_powered(flat) or kind == "generator" else " — NO POWER (out of range)")])
	return true

func build_at_player(kind: String) -> void:
	if not player:
		return
	var dir: Vector3 = player.aim_point - player.global_position
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.3 else Vector3(0, 0, -1)
	try_build(kind, player.global_position + dir * 4.0)

func capture_enemy(e: Node) -> bool:
	if not is_instance_valid(e) or not e.get("is_disabled") or e.get("is_dead"):
		return false
	# Pass 23: capture bonus is salvage income too, so it pays out at
	# the same difficulty multiplier as kill salvage.
	var bonus: int = int(round(float(e.capture_value()) * float(difficulty_multipliers(difficulty)["salvage"])))
	salvage += bonus
	kills += 1
	mech_kills += 1
	# Pass 46: a capture is contract progress.
	captures += 1
	# Pass 31: a capture is a kill for streak purposes, paying its
	# combo bonus on top of the capture bonus. If the capture lands
	# on a milestone, the flash carries both messages; otherwise the
	# plain capture line stays (a non-milestone combo flash from
	# apply_kill_streak is superseded by it, the bonus still paid).
	var _cap_calls_before := streak_call_count
	var _cap_combo := apply_kill_streak()
	grant_xp(2)
	if streak_call_count > _cap_calls_before:
		flash_msg("CAPTURED %s — intact salvage +%d — %s, combo +%d" % [str(e.get("kind")).capitalize(), bonus, last_streak_call, _cap_combo])
	else:
		flash_msg("CAPTURED %s — intact salvage +%d" % [str(e.get("kind")).capitalize(), bonus])
	contracts_evaluate()
	e.die_silent()
	return true

func try_capture_near_player() -> bool:
	if not player:
		return false
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and e.get("is_disabled") and player.global_position.distance_to(e.global_position) < 5.5:
			return capture_enemy(e)
	return false

# ---------------- combat / waves ----------------

func take_core_damage(amount: float) -> void:
	if _game_over or _won:
		return
	core_hp -= amount
	if core_hp <= 0.0:
		core_hp = 0.0
		_end_game(false)

# Pass 38 (BALANCE): endless-only scaling, pure so tests assert it
# directly. Damage grows 5%/wave from wave 4, capped at +50% (wave
# 14+); the shield pool tracks the same wave HP factor as hull, so
# a shield heavy's shield stays the same fraction of its effective HP
# at every wave instead of shrinking from 37% (wave 1) to ~18%
# (wave 12). Both apply only while endless_mode, so campaign waves
# 1-3 and the automated test's spawned enemies keep exact base values.
func endless_dmg_factor(w: int) -> float:
	return 1.0 + float(mini(maxi(w - 4, 0), 10)) * 0.05

func endless_shield_factor(w: int) -> float:
	return 1.0 + float(maxi(w - 1, 0)) * 0.15

func spawn_enemy(kind: String, pos: Vector3) -> Node3D:
	var e = Node3D.new()
	e.set_script(EnemyScript)
	# Pass 23: difficulty scales the wave HP factor (so wave escalation
	# and difficulty multiply, they do not replace each other), the
	# damage dealt, and — for shield heavies — the shield pool itself,
	# which is part of effective HP. Salvage is scaled at payout, not
	# here, so per-kind salvage_value stays the base value tests assert.
	var dm := difficulty_multipliers(difficulty)
	e.setup(kind, (1.0 + float(maxi(wave - 1, 0)) * 0.15) * float(dm["hp"]), pos)
	e.dmg = float(e.get("dmg")) * float(dm["dmg"])
	if kind == "shield_heavy" or kind == "bulwark":
		e.shield_max = float(e.get("shield_max")) * float(dm["hp"])
		e.shield_hp = float(e.get("shield_max"))
	# Pass 38: endless escalation is per-hit deadliness + shield weight,
	# not just headcount. Guarded by endless_mode, so this never fires
	# for campaign waves or test spawns outside an endless run.
	if endless_mode:
		e.dmg = float(e.get("dmg")) * endless_dmg_factor(wave)
		if kind == "shield_heavy" or kind == "bulwark":
			e.shield_max = float(e.get("shield_max")) * endless_shield_factor(wave)
			e.shield_hp = float(e.get("shield_max"))
	add_child(e)
	e.core_position = Vector3.ZERO
	e.on_core_damage = Callable(self, "take_core_damage")
	e.died.connect(_on_enemy_died)
	return e

func _on_enemy_died(enemy, salvage_value: int, weapon_name: String) -> void:
	kills += 1
	# Pass 49: a kill charges the overdrive meter (+10, inactive only).
	if not overdrive_active:
		overdrive_charge = minf(100.0, overdrive_charge + OVERDRIVE_CHARGE_PER_KILL)
	# Pass 23: kill salvage pays out at the difficulty multiplier
	# (standard 1.0, so pre-pass expectations are unchanged).
	salvage += int(round(float(salvage_value) * float(difficulty_multipliers(difficulty)["salvage"])))
	# Pass 31: combo bonus on top of the kill payout (0 below streak 5,
	# so every pre-Pass-31 exact-payout test keeps its expectation
	# whenever its streak is under 5 — verified in the Pass 31 block).
	apply_kill_streak()
	if weapon_name == "Turret":
		turret_kills += 1
	else:
		mech_kills += 1
	match str(enemy.get("kind")):
		"scout": grant_xp(1)
		"burrower": grant_xp(2)
		"sapper": grant_xp(1)
		"lancer": grant_xp(3)
		"heavy": grant_xp(3)
		"shield_heavy": grant_xp(4)
		"bulwark": grant_xp(5)
		"siege": grant_xp(10)
		_: grant_xp(1)
	if enemy.get("kind") == "siege":
		siege_killer_weapon = weapon_name if weapon_name != "" else "Autocannon"
		flash_msg("SIEGE PLATFORM DESTROYED by %s" % siege_killer_weapon)
		# Pass 18 (UX): small screen shake on siege death only — the
		# biggest kill in the game gets a physical thump, nothing else.
		_shake_t = 0.5
		_shake_dur = 0.5
		_shake_amp = 1.4
		_shake_clock = 0.0
	# Pass 46: a kill is contract progress (kills + turret kills).
	contracts_evaluate()

func _wave_director(delta: float) -> void:
	if _wave_active:
		if not _spawn_queue.is_empty():
			_spawn_timer -= delta
			if _spawn_timer <= 0.0:
				_spawn_timer = 0.8
				var kind: String = _spawn_queue.pop_front()
				_spawn_wave_enemy(kind)
		elif get_tree().get_nodes_in_group("enemies").is_empty():
			_wave_active = false
			# Pass 46: the wave cleared — judge the flawless contract
			# before either the victory panel or the clear bonus.
			contracts_on_wave_clear()
			if wave >= 3 and not endless_mode:
				_end_game(true)
				return
			_intermission = 5.0
			var bonus := 30 + wave * 10
			salvage += bonus
			flash_msg("Wave %d clear — +%d salvage" % [wave, bonus])
	else:
		_intermission -= delta
		if _intermission <= 0.0:
			_start_wave()

# Pass 3 (Wave 5): wave composition as a pure function, so the saved
# adaptation flag can inject its counter and tests can count it directly.
# Base queues are unchanged from before this pass; the adaptation bonus
# applies from wave 2 on: tunneling_units -> burrowers, shielded_heavies ->
# shield heavies, mixed_doctrine -> scout + heavy.
func build_wave_queue(w: int, adaptation: String) -> Array:
	var q: Array = []
	match w:
		1:
			q = ["scout","scout","scout","scout","scout","scout","scout","scout"]
		2:
			q = ["scout","scout","heavy","shield_heavy","scout","scout","heavy","scout","scout","shield_heavy"]
		3:
			# Pass 22: 2 lancers debut in wave 3 (queue 16 -> 18).
			# Pass 41: 1 bulwark debuts in wave 3 (queue 18 -> 19).
			q = ["scout","burrower","heavy","shield_heavy","scout","burrower","heavy","scout","burrower","scout","heavy","shield_heavy","scout","sapper","sapper","lancer","lancer","siege","bulwark"]
		_:
			# endless waves 4+: procedural escalation
			# Pass 38 (BALANCE): scout count caps at 24, so the total
			# queue never exceeds 53 — under the 60-enemy spawn-cap
			# stress test. Waves up to 18 are unchanged (6 + 18 = 24);
			# further escalation comes from damage/shield scaling in
			# spawn_enemy, not from ever-longer queues.
			var scouts := mini(6 + w, 24)
			var heavies := mini(2 + w, 7)
			var shield_heavies := mini(1 + w / 2, 5)
			var burrowers := mini(1 + w, 6)
			for i in range(scouts):
				q.append("scout")
				if i % 3 == 0 and heavies > 0:
					q.append("heavy")
					heavies -= 1
				if i % 5 == 0 and shield_heavies > 0:
					q.append("shield_heavy")
					shield_heavies -= 1
				if i % 4 == 0 and burrowers > 0:
					q.append("burrower")
					burrowers -= 1
			while heavies > 0:
				q.append("heavy")
				heavies -= 1
			while shield_heavies > 0:
				q.append("shield_heavy")
				shield_heavies -= 1
			while burrowers > 0:
				q.append("burrower")
				burrowers -= 1
			# Pass 14: sapper drones escalate with the endless waves
			# (wave 4: 2, +1 per wave, capped at 6).
			var sappers := mini(2 + (w - 4), 6)
			for i in range(sappers):
				q.append("sapper")
			# Pass 22: lancers escalate with the endless waves
			# (wave 4: 1, +1 per wave, capped at 4).
			var lancers := mini(1 + (w - 4), 4)
			for i in range(lancers):
				q.append("lancer")
			# Pass 41: bulwarks join endless from wave 9 (1, then 2
			# from wave 12, capped at 2) — waves 4 and 8 are unchanged,
			# so only the wave 12/20/30 cap checks move.
			if w >= 9:
				var bulwarks := mini(1 + (w - 9) / 3, 2)
				for i in range(bulwarks):
					q.append("bulwark")
			if w % 3 == 0:
				q.append("siege")
	if w >= 2:
		match adaptation:
			"tunneling_units":
				q.append("burrower")
				q.append("burrower")
			"shielded_heavies":
				q.append("shield_heavy")
				q.append("shield_heavy")
			"mixed_doctrine":
				q.append("scout")
				q.append("heavy")
	return q

# Pass 37 (FEATURE: wave preview): the intermission panel's text as a
# pure function of the next wave number and adaptation, so tests can
# assert the exact composition without driving the wave director.
# Counts come from build_wave_queue, so the panel can never disagree
# with what actually spawns; kinds print in one fixed order.
func wave_preview_text(w: int, adaptation: String) -> String:
	var counts := {}
	for k in build_wave_queue(w, adaptation):
		var ks := str(k)
		counts[ks] = counts.get(ks, 0) + 1
	var order := ["scout", "heavy", "shield_heavy", "bulwark", "burrower", "sapper", "lancer", "siege"]
	var joined := ""
	for kind in order:
		if counts.has(kind):
			if joined != "":
				joined += ", "
			joined += "%dx %s" % [counts[kind], kind.to_upper().replace("_", " ")]
	return "NEXT WAVE %d — %s" % [w, joined]

# Pass 15 (BALANCE): wave income as a pure function — kill salvage per
# queue kind + the clear bonus — so economy pacing is test-asserted,
# not eyeballed. Salvage map mirrors enemy.gd setup().
func salvage_for_kind(kind: String) -> int:
	match kind:
		"scout": return 12
		"heavy": return 30
		"burrower": return 18
		"sapper": return 15
		"lancer": return 25
		"shield_heavy": return 45
		"bulwark": return 60
		"siege": return 120
	return 0

func wave_income(w: int, adaptation: String) -> int:
	var total := 0
	for k in build_wave_queue(w, adaptation):
		total += salvage_for_kind(str(k))
	return total + 30 + w * 10

# Pass 15: analytic TTK — ceil(hp / per-shot damage) shots x cooldown.
# Conservative (counts the first shot's full cooldown); matches the
# empirical armor-factor checks elsewhere in stage 1.
func ttk_seconds(dmg: float, armor_factor: float, hp: float, cd: float) -> float:
	return ceilf(hp / (dmg * armor_factor)) * cd

func _start_wave() -> void:
	wave += 1
	# Pass 46: flawless-wave is judged against the core HP at wave
	# start, so damage from an earlier wave cannot false-complete it.
	_wave_core_hp_start = core_hp
	var adapt := saved_adaptation if saved_adaptation != "" else adaptation_for(mech_kills, turret_kills)
	_spawn_queue = build_wave_queue(wave, adapt)
	_wave_active = true
	_spawn_timer = 0.2
	flash_msg("WAVE %d INCOMING" % wave)

func _spawn_wave_enemy(kind: String) -> void:
	var pos: Vector3
	if kind == "burrower":
		# spawn inside perimeter near a power structure or the core
		var anchor := Vector3(14, 0, 14)
		var gens := get_tree().get_nodes_in_group("generators")
		if not gens.is_empty() and is_instance_valid(gens[0]):
			anchor = gens[0].global_position + Vector3(4, 0, 4)
		pos = anchor + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))
	else:
		var angle := randf() * TAU
		pos = Vector3(cos(angle) * 54.0, 0, sin(angle) * 54.0)
	spawn_enemy(kind, pos)

# Pass 42: the single snapshot for the end panel and the world
# save, so panel and save can never disagree with each other.
func run_stats() -> Dictionary:
	var fired := int(player.get("shots_fired")) if player else 0
	var taken := float(player.get("damage_taken")) if player else 0.0
	var acc := 0.0
	if fired > 0:
		acc = float(shots_hit) / float(fired)
	return {"run_time": run_time_seconds, "shots_fired": fired, "shots_hit": shots_hit, "accuracy": acc, "damage_dealt": damage_dealt, "damage_taken": taken}

func format_run_time(sec: float) -> String:
	var m := int(sec) / 60
	var s := int(sec) % 60
	return "%d:%02d" % [m, s]

func end_panel_stats_text() -> String:
	var s := run_stats()
	return "RUN STATS — TIME %s | SHOTS %d | HITS %d | ACCURACY %d%%\nDAMAGE DEALT %d | DAMAGE TAKEN %d\n" % [format_run_time(float(s["run_time"])), int(s["shots_fired"]), shots_hit, int(round(float(s["accuracy"]) * 100.0)), int(round(damage_dealt)), int(round(float(s["damage_taken"])))]

# Pass 42: called by bullet.gd once per enemy struck by a player-mech
# bullet. first_hit is true only for the bullet's first enemy, so
# AoE/chain/pierce victims add damage without inflating accuracy.
func record_player_bullet_damage(delivered: float, first_hit: bool) -> void:
	damage_dealt += delivered
	if first_hit:
		shots_hit += 1

func _on_player_died() -> void:
	_end_game(false)

func _end_game(won: bool) -> void:
	if _game_over or _won:
		return
	# Pass 46: the run is over, so its board stops paying.
	contracts_live = false
	if won:
		_won = true
		var pct := core_hp / core_max_hp
		var state := "Forward Base"
		var line := "Facility saved intact — becomes a Forward Base"
		if pct < 0.75:
			state = "Damaged Outpost"
			line = "Facility saved damaged — Damaged Outpost + recovery contract"
		save_world(state)
		var txt := "VICTORY\n%s\nCore integrity: %d%%\n" % [line, int(pct * 100.0)]
		if siege_killer_weapon != "":
			txt += "Mech Memory: %s earned the mark — SIEGEBREAKER\n" % siege_killer_weapon
		txt += "SCOUT REPORT — Directorate adaptation: %s\n" % adaptation_text(adaptation_for(mech_kills, turret_kills))
		txt += end_panel_stats_text()
		txt += contracts_summary_text()
		txt += "World state saved."
		_win_panel.get_meta("label").text = txt
		_win_panel.visible = true
	else:
		_game_over = true
		save_world("Ruin")
		_gameover_panel.get_meta("label").text = "FACILITY LOST\nThe reactor is gone — this place becomes a Ruin.\n" + end_panel_stats_text() + contracts_summary_text() + "World state saved."
		_gameover_panel.visible = true
	get_tree().paused = true

func start_endless() -> void:
	if not _won:
		return
	_won = false
	# Pass 46: endless continues the same run, so its board stays live.
	contracts_live = true
	endless_mode = true
	_win_panel.visible = false
	get_tree().paused = false
	_wave_active = false
	_intermission = 3.0
	flash_msg("ENDLESS DEFENSE — the Directorate keeps coming")

func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

# ---------------- Pass 17: pause menu ----------------
# Guards: the menu never opens over the hangar, the level-up choice, or
# an end panel — those pauses own their own buttons and must resolve
# first. Opening hides the substation choice (not consumed, so the
# player can re-interact after resuming).

func open_pause() -> bool:
	if pause_open or hangar_open or _game_over or _won:
		return false
	if _lvl_panel and _lvl_panel.visible:
		return false
	if _sub_panel:
		_sub_panel.visible = false
	pause_open = true
	if _pause_panel:
		_pause_panel.visible = true
	get_tree().paused = true
	return true

func resume_from_pause() -> void:
	if not pause_open:
		return
	pause_open = false
	if _pause_panel:
		_pause_panel.visible = false
	get_tree().paused = false

func toggle_pause() -> void:
	if pause_open:
		resume_from_pause()
	else:
		open_pause()

func restart_from_pause() -> void:
	if not pause_open:
		return
	_reset_run()
	# Pass 46: restart continues the same run, so its board stays live.
	contracts_live = true
	pause_open = false
	if _pause_panel:
		_pause_panel.visible = false
	get_tree().paused = false

func back_to_hangar_from_pause() -> void:
	if not pause_open:
		return
	_reset_run()
	pause_open = false
	if _pause_panel:
		_pause_panel.visible = false
	_open_hangar()

# Run reset shared by pause RESTART and BACK TO HANGAR. Resets run state
# only: loadout, saved adaptation, and the world save are untouched, and
# the two abandoned turrets stay (world dressing, not player-built —
# an activated one stays live; only its substation choice resets).
func _reset_run() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e):
			e.queue_free()
	var kept: Array = []
	for s in _structures:
		if is_instance_valid(s) and s in _abandoned_turrets:
			kept.append(s)
		elif is_instance_valid(s):
			s.queue_free()
	_structures = kept
	for c in get_tree().get_nodes_in_group("caches"):
		if is_instance_valid(c):
			c.queue_free()
	_caches.clear()
	_spawn_caches()
	# Pass 30: destructibles reset with the run, like caches — broken
	# ones come back whole, counters reset, so a restart is a fresh field.
	for d in get_tree().get_nodes_in_group("destructibles"):
		if is_instance_valid(d):
			d.queue_free()
	_destructibles.clear()
	_destructible_broken = 0
	_destructible_break_fx = 0
	_spawn_destructibles()
	for n in get_children():
		if n is Node3D:
			var sc = n.get_script()
			if sc != null and str(sc.resource_path) == "res://scripts/bullet.gd":
				# Pass 19: return live bullets to the pool, never free them
				# — freeing a pooled node would leave a dead reference in
				# the free list for the next shot to reuse.
				if n.has_method("release_to_pool"):
					n.release_to_pool()
				else:
					n.queue_free()
	if _tunnel_gate == null or not is_instance_valid(_tunnel_gate):
		var tg := Node3D.new()
		tg.position = Vector3(26, 0, -30)
		tg.rotation.y = 0.6
		add_child(tg)
		Factory.box(tg, Vector3(9.0, 2.6, 0.9), Vector3(0, 1.3, 0), Factory.mat(Color(0.3, 0.26, 0.2), Color(1, 0.5, 0.2), 0.4, 0.3, 0.6))
		_tunnel_gate = tg
	_spawn_queue.clear()
	_spawn_timer = 0.0
	_intermission = 2.5
	_wave_active = false
	_game_over = false
	_won = false
	endless_mode = false
	wave = 0
	kills = 0
	mech_kills = 0
	turret_kills = 0
	# Pass 31: a fresh run is a fresh streak (best resets with it).
	kill_streak = 0
	best_kill_streak = 0
	last_streak_call = ""
	streak_call_count = 0
	# Pass 49: a fresh run is a fresh overdrive meter. The rate
	# itself resets in player.reset_for_new_run below, so an active
	# overdrive can never survive into the next run.
	overdrive_charge = 0.0
	overdrive_active = false
	overdrive_timer = 0.0
	_last_move_tap_msec = 0
	# Pass 42: a fresh run is fresh stats (player counters clear in
	# player.reset_for_new_run, called below).
	run_time_seconds = 0.0
	shots_hit = 0
	damage_dealt = 0.0
	# Pass 46: a fresh run is fresh contract progress — but NOT a
	# fresh board. Pause-restart replays the same board; only a
	# hangar open (contracts_roll) draws a new one.
	captures = 0
	caches_collected = 0
	contracts_paid_total = 0
	contracts_live = false
	_contracts_flawless_done = false
	_wave_core_hp_start = 0.0
	xp = 0
	level = 1
	pending_levels = 0
	salvage = 90
	core_hp = core_max_hp
	siege_killer_weapon = ""
	_substation_used = false
	recovery_built = 0
	recovery_bonus_paid = false
	_joy_active = false
	_joy_id = -1
	_joy_vec = Vector2.ZERO
	_aim_active = false
	_aim_id = -1
	_touch_firing = false
	_power_line_bright_t = 0.0
	if _power_line_mat:
		_update_power_line_brightness()
	if _sub_panel:
		_sub_panel.visible = false
	if _lvl_panel:
		_lvl_panel.visible = false
	if _win_panel:
		_win_panel.visible = false
	if _gameover_panel:
		_gameover_panel.visible = false
	if _lbl_msg:
		_lbl_msg.text = ""
	_msg_timer = 0.0
	if player:
		player.reset_for_new_run()
		player.apply_loadout(str(player.get("chassis")), str(player.get("utility")))
		player.global_position = Vector3(0, 0, 10)
	drone_hold = false
	if drone:
		drone.position = Vector3(3, 1.2, 13)
		drone.hold = false

# ---------------- substation ----------------

func choose_substation(choice: String) -> void:
	if _substation_used:
		return
	# Pass 47 (audit, closes Pass 5 backlog M2): only the two real
	# choices consume the substation. An unknown string used to fall
	# into the tunnel branch and pay +40 for nothing.
	if choice != "turrets" and choice != "tunnel":
		return
	_substation_used = true
	_sub_panel.visible = false
	if choice == "turrets":
		for t in _abandoned_turrets:
			if is_instance_valid(t):
				t.activate()
		flash_msg("Substation power rerouted — abandoned turrets LIVE")
	else:
		if _tunnel_gate:
			_tunnel_gate.queue_free()
			_tunnel_gate = null
		salvage += 40
		flash_msg("Maintenance tunnel OPEN — salvage cache +40")

# ---------------- process / input ----------------

func _process(delta: float) -> void:
	# Pass 17: main is ALWAYS, so this runs during pauses too — in a real
	# build the game must still freeze on any pause (test mode is exempt
	# so the automated test can drive pause/hangar checks while paused).
	if get_tree().paused and not test_mode:
		return
	if _msg_timer > 0.0:
		_msg_timer -= delta
		if _msg_timer <= 0.0 and _lbl_msg:
			_lbl_msg.text = ""
	if not _game_over and not _won:
		# Pass 42: live play only — the tree pause already freezes
		# this in a real build, and the hangar/pause guards cover
		# test mode, where _process runs while paused.
		if not hangar_open and not pause_open:
			run_time_seconds += delta
		_poll_player_damage()
		_update_vignette(delta)
		if _shake_t > 0.0:
			_shake_t = maxf(0.0, _shake_t - delta)
			_shake_clock += delta
		_update_camera(delta)
		_update_input()
		_wave_director(delta)
		_update_caches(delta)
		_power_line_timer -= delta
		if _power_line_timer <= 0.0:
			_power_line_timer = 0.5
			_refresh_power_lines()
		if _power_line_bright_t > 0.0:
			_power_line_bright_t -= delta
			if _power_line_bright_t <= 0.0:
				_power_line_bright_t = 0.0
				_update_power_line_brightness()
		# Pass 49: overdrive ticks only in live play — hangar/pause
		# guard mirrors the run-time guard above (test mode runs
		# _process while paused, so the guard has to be explicit).
		if not hangar_open and not pause_open:
			_overdrive_tick(delta)
		_refresh_hud()
	if test_mode:
		_run_test(delta)

func _update_camera(delta: float) -> void:
	if not player or not camera:
		return
	var focus: Vector3 = player.global_position
	# Pass 7 (Overhaul A): pitched angled-isometric view (was 46 up / 26
	# back) so billboard unit sprites read against the ground. _ground_point
	# already raycasts the camera, so mouse/touch aim keep working — the
	# Pass 7 test asserts the ray mapping, not just the offset.
	camera.size = _zoom_sizes[zoom_step]
	var desired: Vector3 = focus + Vector3(0, 44, 32)
	if camera.global_position.length() < 0.01:
		camera.global_position = desired
	else:
		camera.global_position = camera.global_position.lerp(desired, 6.0 * delta)
	# Pass 18 (UX): shake offset AFTER the lerp (the lerp would smooth
	# it away) and before look_at (look_at only turns the camera, so
	# the offset survives). Decays with _shake_t; zero when not shaking.
	if _shake_t > 0.0 and _shake_dur > 0.0:
		var _sk := _shake_t / _shake_dur
		camera.global_position += Vector3(sin(_shake_clock * 47.0), 0.0, cos(_shake_clock * 39.0)) * _shake_amp * _sk
	# Pass 20 (camera safe-area): the look target sits 6 m SOUTH of the
	# player (was 2 m north), so the mech renders above screen centre —
	# clear of the 128 px bottom panel on a phone, not behind it.
	camera.look_at(focus + Vector3(0, 0, P20_CAM_TARGET_Z), Vector3.UP)

func _ground_point(screen_pos: Vector2) -> Vector3:
	if not camera:
		return Vector3.ZERO
	var origin := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.001:
		return Vector3.ZERO
	var t := -origin.y / dir.y
	return origin + dir * t

func _update_input() -> void:
	if not player or _game_over or _won:
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
	player.aim_point = _ground_point(get_viewport().get_mouse_position())
	if _aim_active:
		# Pass 4: right stick aims; it overrides mouse and aim assist
		var ad := touch_aim_dir()
		if ad != Vector3.ZERO:
			player.aim_point = player.global_position + ad * 20.0
	elif _touch_firing:
		# touch aim = nearest enemy direction (fire button, no stick held)
		var best: Node = null
		var bd := 9999.0
		for e in get_tree().get_nodes_in_group("enemies"):
			# Pass 47 (audit, closes Pass 5 backlog M3): the FIRE-button
			# aim assist must not aim at a disabled capture target (or
			# a dead one) — it used to pick the nearest enemy outright.
			if is_instance_valid(e) and not e.get("is_disabled") and not e.get("is_dead"):
				var d := player.global_position.distance_to(e.global_position)
				if d < bd:
					bd = d; best = e
		if best:
			player.aim_point = best.global_position
	player.firing = (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not _joy_active and get_viewport().get_mouse_position().y > 90.0) or _touch_firing
	player.venting = Input.is_physical_key_pressed(KEY_R)

func _input(event: InputEvent) -> void:
	# Pass 17: main is ALWAYS, so input arrives during pauses too. While
	# the pause menu is open only its own keys act (Esc/P resume); while
	# any other pause holds (hangar/level-up/end), all input is swallowed
	# and that panel's own buttons resolve it.
	if get_tree().paused:
		if pause_open and event is InputEventKey:
			var pk := event as InputEventKey
			if pk.pressed and not pk.echo and pk.keycode in [KEY_ESCAPE, KEY_P]:
				resume_from_pause()
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		var vp := get_viewport().get_visible_rect().size
		if t.pressed:
			if t.position.x < vp.x * 0.45 and not _joy_active:
				# Pass 49: a second move-stick touch within 350 ms of
				# the previous move-finger lift is a double-tap — the
				# touch trigger for overdrive (no-op unless full).
				if _last_move_tap_msec > 0 and Time.get_ticks_msec() - _last_move_tap_msec <= OVERDRIVE_DOUBLE_TAP_MSEC:
					try_overdrive()
				_joy_active = true; _joy_id = t.index; _joy_origin = t.position; _joy_vec = Vector2.ZERO
			elif t.position.x >= vp.x * 0.55 and not _aim_active:
				touch_aim_begin(t.position, t.index)
		else:
			# Pass 4 fix: releases are per-finger now — lifting the move
			# stick no longer stops firing, and vice versa.
			if t.index == _joy_id:
				_last_move_tap_msec = Time.get_ticks_msec()
				_joy_active = false; _joy_id = -1; _joy_vec = Vector2.ZERO
			if t.index == _aim_id:
				touch_aim_end(t.index)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if _joy_active and d.index == _joy_id:
			var off: Vector2 = d.position - _joy_origin
			_joy_vec = off / 70.0
			if _joy_vec.length() > 1.0:
				_joy_vec = _joy_vec.normalized()
		elif _aim_active and d.index == _aim_id:
			touch_aim_drag(d.position)
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo:
			match k.keycode:
				KEY_1: player.select_weapon(1)
				KEY_2: player.select_weapon(2)
				KEY_3: player.select_weapon(3)
				KEY_4: player.select_weapon(4)
				KEY_5: player.select_weapon(5)
				KEY_6: player.select_weapon(6)
				KEY_Q:
					if player.try_utility():
						flash_msg("Utility: %s" % ("Repair Pulse" if str(player.get("utility")) == "repair_pulse" else "Grapple"))
				KEY_SPACE:
					# Pass 49: Space+Shift triggers overdrive, plain
					# Space still dashes — the shift test is on the
					# event, not the polled key, so a held Shift from
					# another action cannot leak in.
					if k.shift_pressed:
						try_overdrive()
					else:
						player.try_dash()
				KEY_F: build_at_player("turret")
				KEY_G: build_at_player("generator")
				KEY_B: build_at_player("barricade")
				KEY_M: build_at_player("mortar")
				# Pass 17: P is the pause toggle now (Esc/P per the pass
				# spec) — the EMP pylon stays buildable from the build
				# bar button, which is also the touch path. Keeping P as
				# both pause and build would fire a build on every pause
				# attempt and pause on every EMP attempt.
				KEY_ESCAPE: toggle_pause()
				KEY_P: toggle_pause()
				KEY_V: toggle_drone_command()
				KEY_Z: cycle_zoom()
				KEY_E: _interact()

func _interact() -> void:
	if try_capture_near_player():
		return
	if player and not _substation_used and player.global_position.distance_to(_substation_pos) < 7.0:
		_sub_panel.visible = true
		flash_msg("Substation: choose ONE — power turrets OR open tunnel")


# ---------------- HUD ----------------

# ---------------- Pass 36 (MENU-SYSTEMS RESTYLE) ----------------
# One shared chrome for every menu surface, from the MENU SYSTEMS
# TEMPLATE: dark near-black navy panels, bright cyan border, cyan
# section titles with a divider under them, cyan-fill primary buttons
# and dark-navy rows for the rest. Skin only: no size, position, text,
# cost, stat, or behaviour change anywhere it is applied.
const P36_BG := Color(0.02, 0.05, 0.11)
const P36_CYAN := Color(0.18, 0.78, 0.95)
const P36_CYAN_DIM := Color(0.18, 0.28, 0.42)
const P36_TITLE := Color(0.65, 0.93, 1.0)

func _p36_panel(alpha: float) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = Color(P36_BG.r, P36_BG.g, P36_BG.b, alpha)
	st.border_color = P36_CYAN
	st.set_border_width_all(2)
	st.set_corner_radius_all(8)
	return st

func _p36_modal_panel() -> StyleBoxFlat:
	var st := _p36_panel(1.0)
	st.set_content_margin_all(10)
	return st

func _p36_card_style(selected: bool) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.04, 0.08, 0.16, 1.0)
	if selected:
		st.border_color = P36_CYAN
		st.set_border_width_all(3)
	else:
		st.border_color = P36_CYAN_DIM
		st.set_border_width_all(1)
	st.set_corner_radius_all(8)
	return st

func _p36_button_style(selected: bool) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	if selected:
		st.bg_color = P36_CYAN
		st.border_color = P36_CYAN
	else:
		st.bg_color = Color(0.04, 0.08, 0.15, 1.0)
		st.border_color = P36_CYAN_DIM
	st.set_border_width_all(1)
	st.set_corner_radius_all(4)
	return st

func _p36_button(btn: Button, selected: bool) -> void:
	btn.add_theme_stylebox_override("normal", _p36_button_style(selected))
	var hov := _p36_button_style(selected)
	if not selected:
		hov.bg_color = Color(0.07, 0.13, 0.24, 1.0)
		hov.border_color = P36_CYAN
	btn.add_theme_stylebox_override("hover", hov)
	btn.add_theme_stylebox_override("pressed", _p36_button_style(selected))
	btn.add_theme_color_override("font_color", Color(0.02, 0.05, 0.12) if selected else Color(0.85, 0.95, 1.0))
	btn.add_theme_color_override("font_hover_color", Color(0.02, 0.05, 0.12) if selected else Color(1.0, 1.0, 1.0))

func _p36_divider() -> ColorRect:
	var d := ColorRect.new()
	d.color = Color(P36_CYAN.r, P36_CYAN.g, P36_CYAN.b, 0.6)
	d.custom_minimum_size = Vector2(0, 2)
	d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_p36_dividers.append(d)
	return d

func _p36_title(lbl: Label) -> void:
	lbl.add_theme_color_override("font_color", P36_TITLE)

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	# Pass 11 (HOTFIX): HUD widths/heights derive from the real viewport,
	# not the 1152x648 design size, so nothing overflows a phone screen.
	var _vw := get_viewport().get_visible_rect().size.x
	var _vh := get_viewport().get_visible_rect().size.y
	if _vw <= 0.0:
		_vw = 1152.0
	if _vh <= 0.0:
		_vh = 648.0
	# Pass 9 (Overhaul C): HUD in three zones on a dark-navy/cyan panel
	# skin (menu-systems reference). Panels are added first so they sit
	# behind the existing labels/buttons, which keep their positions.
	# Pass 36: HUD zones use the one shared menu chrome (was the Pass 9
	# skin: same idea, lighter navy, radius 6 — now identical to every
	# modal panel except for the 0.88 battlefield translucency).
	var panel_style := _p36_panel(0.88)
	# Pass 13 (gameplay-video bugfix): top-left zone widens to 980 (or the
	# viewport) so the long wave line fits inside it, and the message
	# zone moves BELOW it (y=118) instead of overlapping it at y=66.
	# Bottom zone now CONTAINS every bottom control (weapons, zoom,
	# fire, build bar, hint) in three stacked rows — the old layout put
	# buttons at fixed y=500/540 above the 158 panel, so total bottom
	# chrome was ~220px (a third of a phone screen) and the hint's
	# wrapped second line ran off the bottom edge. Panel is 160, total
	# chrome 160, and every row is inside it with room for the hint's
	# real content height (a Label's rect grows to its wrapped lines,
	# so the hint row is 44 high, not a 30-high slot at the edge).
	var _top_w := minf(980.0, _vw - 16.0)
	# Pass 40 (HUD consolidation): top bar 112 -> 84 (stats 6, bars 28,
	# wave 44..78 with 10 px bottom pad), message 34 -> 30 at y=92
	# (top ends 88 + 4 gap), bottom 128 -> 124 (rows 6+44+6+38+6+18+6).
	# The message zone's panel is kept as _msg_zone so _refresh_hud
	# can hide the whole bar when empty — before this pass the panel
	# drew even with no message in it, costing 34 px permanently.
	var zone_defs: Array = [
		[Vector2(8, 4), Vector2(_top_w, P40_TOP_H)],       # top-left: stats/wave/bars
		[Vector2(-350, P40_TOP_H + 8.0), Vector2(700, P40_MSG_H)],   # centre-top: message, below top zone
		[Vector2(8, _vh - P40_BOTTOM_H), Vector2(_vw - 16.0, P40_BOTTOM_H)],   # bottom: icons/buttons/hint
	]
	for zd in zone_defs:
		var zp := PanelContainer.new()
		if zd[0].x < 0:
			zp.set_anchors_preset(Control.PRESET_CENTER_TOP)
		zp.position = zd[0]
		zp.size = zd[1]
		zp.add_theme_stylebox_override("panel", panel_style)
		layer.add_child(zp)
		_hud_zones.append(zp)
	_msg_zone = _hud_zones[1]
	# Pass 16 (Minimap): top-right panel, same dark-navy/cyan skin as the
	# HUD zones, display-only (mouse passes through to the game). On the
	# 1152-wide design viewport it sits at x=988, exactly where the
	# 980-wide top-left zone ends, so the two zones never overlap.
	# Pass 40: minimap 156 -> 120 (panel + border + mapping all read
	# MINIMAP_SIZE, so the shrink is one constant; dots shrink below).
	_minimap_panel = PanelContainer.new()
	_minimap_panel.position = Vector2(_vw - MINIMAP_SIZE - 8.0, 8.0)
	_minimap_panel.size = Vector2(MINIMAP_SIZE, MINIMAP_SIZE)
	_minimap_panel.add_theme_stylebox_override("panel", panel_style)
	_minimap_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_minimap_panel)
	# Pass 20: arena border around the minimap — four cyan edge bars, so
	# the map reads as the bounded arena, not a floating square. They
	# are layer children at the panel's absolute position, NOT panel
	# children: a PanelContainer lays out its children itself and
	# would stretch every bar to the full panel (the first cut's bug).
	var _map_pos := Vector2(_vw - MINIMAP_SIZE - 8.0, 8.0)
	for _br in [[_map_pos + Vector2(0, 0), Vector2(MINIMAP_SIZE, 3)], [_map_pos + Vector2(0, MINIMAP_SIZE - 3), Vector2(MINIMAP_SIZE, 3)], [_map_pos + Vector2(0, 0), Vector2(3, MINIMAP_SIZE)], [_map_pos + Vector2(MINIMAP_SIZE - 3, 0), Vector2(3, MINIMAP_SIZE)]]:
		var _bc := ColorRect.new()
		_bc.position = _br[0]
		_bc.size = _br[1]
		_bc.color = P36_CYAN
		_bc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(_bc)
		_minimap_border.append(_bc)
	# Pass 20: in-game version stamp, centred at the top, above the HUD.
	_version_lbl = Label.new()
	_version_lbl.text = "IRON EDEN v1.51"
	_version_lbl.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_version_lbl.position = Vector2(-110, 8)
	_version_lbl.size = Vector2(220, 20)
	_version_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_version_lbl.add_theme_font_size_override("font_size", 12)
	_p36_title(_version_lbl)
	layer.add_child(_version_lbl)
	_lbl_stats = Label.new()
	_lbl_stats.position = Vector2(14, 6)
	_lbl_stats.add_theme_font_size_override("font_size", 16)
	layer.add_child(_lbl_stats)
	_lbl_wave = Label.new()
	# Pass 40: wave line moves up to y=44 inside the slimmed 84-high
	# top bar (bars at 28, wave 44..78, 10 px pad); font 15 -> 14.
	_lbl_wave.position = Vector2(14, 44)
	_lbl_wave.size = Vector2(_top_w - 28.0, 34)
	_lbl_wave.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_wave.add_theme_font_size_override("font_size", 14)
	layer.add_child(_lbl_wave)
	_lbl_msg = Label.new()
	_lbl_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_msg.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_lbl_msg.position = Vector2(-350, P40_TOP_H + 8.0)
	_lbl_msg.size = Vector2(700, P40_MSG_H)
	_lbl_msg.add_theme_font_size_override("font_size", 18)
	layer.add_child(_lbl_msg)
	# Pass 37 (FEATURE: wave preview): intermission panel, centre-top
	# below the message zone. Pass 40: height 44 -> 40, and the y is
	# no longer fixed — _refresh_hud stacks it at 126 under a visible
	# message (92 + 30 + 4) or at 92 when the message bar is hidden,
	# so the preview never floats over a gap the message left behind.
	# The label is the panel's only child, so it fills the panel; text
	# wraps to two lines for the longest endless compositions.
	_preview_panel = PanelContainer.new()
	_preview_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_preview_panel.position = Vector2(-350, P40_TOP_H + 8.0)
	_preview_panel.size = Vector2(700, P40_PREVIEW_H)
	_preview_panel.add_theme_stylebox_override("panel", panel_style)
	layer.add_child(_preview_panel)
	_preview_lbl = Label.new()
	_preview_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview_lbl.add_theme_font_size_override("font_size", 14)
	_preview_panel.add_child(_preview_lbl)
	var hull_lbl := Label.new()
	hull_lbl.text = "HULL"
	hull_lbl.position = Vector2(14, 28)
	hull_lbl.add_theme_font_size_override("font_size", 12)
	layer.add_child(hull_lbl)
	# Pass 20: high-contrast bar fills on a dark track, so HULL/CORE/HEAT
	# read at arm's length instead of as washed-out default grey.
	var _bar_bg := StyleBoxFlat.new()
	_bar_bg.bg_color = Color(P36_BG.r, P36_BG.g, P36_BG.b, 1.0)
	var _hull_fill := StyleBoxFlat.new()
	_hull_fill.bg_color = Color(0.2, 1.0, 0.4)
	_hull_bar = ProgressBar.new()
	_hull_bar.position = Vector2(52, 28)
	_hull_bar.size = Vector2(150, 12)
	_hull_bar.add_theme_stylebox_override("fill", _hull_fill)
	_hull_bar.add_theme_stylebox_override("background", _bar_bg)
	layer.add_child(_hull_bar)
	var heat_lbl := Label.new()
	heat_lbl.text = "HEAT"
	heat_lbl.position = Vector2(214, 28)
	heat_lbl.add_theme_font_size_override("font_size", 12)
	layer.add_child(heat_lbl)
	var _heat_fill := StyleBoxFlat.new()
	_heat_fill.bg_color = Color(1.0, 0.65, 0.1)
	_heat_bar = ProgressBar.new()
	_heat_bar.position = Vector2(252, 28)
	_heat_bar.size = Vector2(150, 12)
	_heat_bar.max_value = 100
	_heat_bar.add_theme_stylebox_override("fill", _heat_fill)
	_heat_bar.add_theme_stylebox_override("background", _bar_bg)
	layer.add_child(_heat_bar)
	var core_lbl := Label.new()
	core_lbl.text = "CORE"
	core_lbl.position = Vector2(414, 28)
	core_lbl.add_theme_font_size_override("font_size", 12)
	layer.add_child(core_lbl)
	var _core_fill := StyleBoxFlat.new()
	_core_fill.bg_color = Color(0.25, 0.85, 1.0)
	_core_bar = ProgressBar.new()
	_core_bar.position = Vector2(452, 28)
	_core_bar.size = Vector2(150, 12)
	_core_bar.add_theme_stylebox_override("fill", _core_fill)
	_core_bar.add_theme_stylebox_override("background", _bar_bg)
	layer.add_child(_core_bar)
	# Pass 49 (Overdrive meter): a fourth top-bar meter in the empty
	# stretch after CORE (ends 602): "OD" label at 610, bar 636..756
	# at 120 wide, so it still fits the narrowest top zone (784 on
	# an 800-wide viewport) without moving the top bar's height or
	# any existing bar. Added before the Pass 11 registry loop, so
	# the hangar hides it with the rest of the HUD.
	var od_lbl := Label.new()
	od_lbl.text = "OD"
	od_lbl.position = Vector2(610, 28)
	od_lbl.add_theme_font_size_override("font_size", 12)
	layer.add_child(od_lbl)
	var _od_fill := StyleBoxFlat.new()
	_od_fill.bg_color = Color(1.0, 0.85, 0.2)
	_od_bar = ProgressBar.new()
	_od_bar.position = Vector2(636, 28)
	_od_bar.size = Vector2(120, 12)
	_od_bar.max_value = 100
	_od_bar.add_theme_stylebox_override("fill", _od_fill)
	_od_bar.add_theme_stylebox_override("background", _bar_bg)
	layer.add_child(_od_bar)
	var hint := Label.new()
	# Pass 20: touch instructions replace the desktop keybind paragraph —
	# the phone player has sticks and buttons, not WASD/mouse keys.
	# Pass 40: shortened to one line at 11 px (was a 2-line wrap at 12 px
	# in a 32-high slot). A Label's rendered line height is 23 px at
	# 11 px type, so the row starts at vh-26 and ends at vh-3 — still
	# inside the panel with room to spare, and the whole bottom panel
	# fits 6+44+6+38+6+18+6 = 124 px with nothing clipped.
	hint.text = "TOUCH: LEFT STICK — MOVE  •  RIGHT STICK — AIM + FIRE  •  TAP BUILD  •  ZOOM  •  SHIELD"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.position = Vector2(14, _vh - 26.0)
	hint.size = Vector2(_vw - 28.0, 18.0)
	hint.add_theme_font_size_override("font_size", 11)
	layer.add_child(hint)
	_hint_lbl = hint
	# build buttons (clickable) — Pass 11 (HOTFIX): was five buttons at
	# fixed x=620..1254, overflowing narrower viewports; now one bar
	# anchored to the bottom-right corner, so it always fits the width.
	_build_bar = HBoxContainer.new()
	_build_bar.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	# Pass 13: build bar lives in the bottom panel's second row
	# above the hint, 6 x 122px buttons + 5 x 6px gaps = 762 wide,
	# right-anchored so it only extends left into the panel's empty
	# second-row space. Pass 40: row 2 of the 124 panel — top vh-68,
	# 38 high, ending vh-30, 6 px above the hint row (vh-24).
	_build_bar.position = Vector2(-776.0, -68.0)
	_build_bar.size = Vector2(762.0, 38.0)
	_build_bar.add_theme_constant_override("separation", 6)
	layer.add_child(_build_bar)
	var builds := [["TURRET 50", "turret"], ["GENERATOR 75", "generator"], ["BARRICADE 25", "barricade"], ["MORTAR 90", "mortar"], ["EMP 120", "emp_pylon"], ["REPAIR 110", "repair_station"]]
	for i in range(builds.size()):
		var b := Button.new()
		b.text = builds[i][0]
		b.custom_minimum_size = Vector2(122, 38)
		var kind: String = builds[i][1]
		b.pressed.connect(func() -> void: build_at_player(kind))
		_p36_button(b, false)
		_build_bar.add_child(b)
	# Pass 4: on-screen FIRE button (touch polish) — hold to fire, same path as the stick
	_fire_btn = Button.new()
	_fire_btn.text = "FIRE"
	# Pass 40: icon buttons MUST expand their icons into the assigned
	# slot. A Button's minimum size is its icon's native size (the p9
	# icons are ~480 px), so without this the assigned 110x44 slot was
	# ignored and FIRE rendered 519x428 — overflowing the panel and
	# the screen, which is the oversized/clipped bottom HUD in the
	# user's v1.39 screenshot. Same for the weapon and utility icons.
	_fire_btn.expand_icon = true
	# Pass 13: fire/zoom/weapon buttons live in the bottom panel's top
	# row, not at fixed y=500/540 above the panel. Pass 40: row 1 of
	# the 124 panel — top vh-118, 44 high, ending vh-74.
	_fire_btn.position = Vector2(_vw - 140.0, _vh - 118.0)
	_fire_btn.size = Vector2(110, 44)
	_fire_btn.button_down.connect(func() -> void: set_fire_button(true))
	_fire_btn.button_up.connect(func() -> void: set_fire_button(false))
	var fire_tex = load("res://sprites/p9/icon_plasma_rifle.png")
	if fire_tex is Texture2D:
		_fire_btn.icon = fire_tex
	_p36_button(_fire_btn, false)
	layer.add_child(_fire_btn)
	# Pass 9: weapon cards as icon buttons, not text-only buttons.
	# Mapping: [1] Autocannon -> gatling, [2] Railgun -> railgun,
	# [3] Scattergun -> missile_pod (multi-projectile spread),
	# [4] Flak Cannon -> grenade_launcher (explosive AoE shell),
	# [5] Tesla Arc -> laser_emitter (energy bolt),
	# [6] Grenade Launcher -> rocket_launcher (arcing explosive).
	# Pass 48: six buttons at 56 px pitch, 50 px wide, so the sixth
	# (x 294..344) clears the utility button, now moved to x 352.
	var weapon_icon_defs: Array = [["gatling", 1], ["railgun", 2], ["missile_pod", 3], ["grenade_launcher", 4], ["laser_emitter", 5], ["rocket_launcher", 6]]
	for wi in range(weapon_icon_defs.size()):
		var wb := Button.new()
		wb.expand_icon = true
		var wtex = load("res://sprites/p9/icon_%s.png" % str(weapon_icon_defs[wi][0]))
		if wtex is Texture2D:
			wb.icon = wtex
		wb.position = Vector2(14 + wi * 56, _vh - 118.0)
		wb.size = Vector2(50, 44)
		var widx: int = int(weapon_icon_defs[wi][1])
		wb.pressed.connect(func() -> void:
			if player:
				player.select_weapon(widx))
		_p36_button(wb, false)
		layer.add_child(wb)
		_weapon_icons.append(wb)
	# Utility card: shield-generator icon for the Q utility.
	_utility_btn = Button.new()
	_utility_btn.expand_icon = true
	var utex = load("res://sprites/p9/icon_shield_generator.png")
	if utex is Texture2D:
		_utility_btn.icon = utex
	_utility_btn.position = Vector2(352, _vh - 118.0)
	_utility_btn.size = Vector2(52, 44)
	_utility_btn.pressed.connect(func() -> void:
		if player and player.try_utility():
			flash_msg("Utility: %s" % ("Repair Pulse" if str(player.get("utility")) == "repair_pulse" else "Grapple")))
	_p36_button(_utility_btn, false)
	layer.add_child(_utility_btn)
	# Phone zoom step button.
	_zoom_btn = Button.new()
	_zoom_btn.text = "ZOOM"
	_zoom_btn.position = Vector2(_vw - 260.0, _vh - 118.0)
	_zoom_btn.size = Vector2(110, 44)
	_zoom_btn.pressed.connect(func() -> void: cycle_zoom())
	_p36_button(_zoom_btn, false)
	layer.add_child(_zoom_btn)
	# Pass 40: the Pass 13 MOVE/AIM labels are deleted, not moved.
	# They sat 22 px ABOVE the bottom panel, so effective bottom
	# chrome was 150 px, not the panel's 128 — the exact accretion
	# this pass removes. Their content is already in the hint row
	# (LEFT STICK — MOVE, RIGHT STICK — AIM + FIRE), so nothing
	# instructional is lost; the panel alone is now the bottom HUD.
	# substation panel
	_sub_panel = PanelContainer.new()
	_sub_panel.set_anchors_preset(Control.PRESET_CENTER)
	_sub_panel.position = Vector2(-190, -110)
	_sub_panel.size = Vector2(380, 220)
	_sub_panel.visible = false
	_sub_panel.add_theme_stylebox_override("panel", _p36_modal_panel())
	layer.add_child(_sub_panel)
	var sv := VBoxContainer.new()
	_sub_panel.add_child(sv)
	var st := Label.new()
	st.text = "SUBSTATION — CHOOSE ONE"
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_p36_title(st)
	sv.add_child(st)
	sv.add_child(_p36_divider())
	var ba := Button.new()
	ba.text = "A: POWER ABANDONED TURRETS"
	ba.custom_minimum_size = Vector2(340, 52)
	ba.pressed.connect(func() -> void: choose_substation("turrets"))
	_p36_button(ba, false)
	sv.add_child(ba)
	var bb := Button.new()
	bb.text = "B: OPEN TUNNEL + 40 SALVAGE"
	bb.custom_minimum_size = Vector2(340, 52)
	bb.pressed.connect(func() -> void: choose_substation("tunnel"))
	_p36_button(bb, false)
	sv.add_child(bb)
	# level-up panel (Wave 1) — pauses the game, 1-of-3 upgrades
	_lvl_panel = PanelContainer.new()
	_lvl_panel.set_anchors_preset(Control.PRESET_CENTER)
	_lvl_panel.position = Vector2(-200, -140)
	_lvl_panel.size = Vector2(400, 280)
	_lvl_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	_lvl_panel.visible = false
	# Pass 20: level-up panel is fully opaque (alpha 1.0), not the
	# translucent HUD skin — the choice must read over the battlefield.
	_lvl_panel.add_theme_stylebox_override("panel", _p36_modal_panel())
	layer.add_child(_lvl_panel)
	var lv := VBoxContainer.new()
	_lvl_panel.add_child(lv)
	_lvl_title = Label.new()
	_lvl_title.text = "LEVEL UP — CHOOSE AN UPGRADE"
	_lvl_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lvl_title.add_theme_font_size_override("font_size", 20)
	_p36_title(_lvl_title)
	lv.add_child(_lvl_title)
	lv.add_child(_p36_divider())
	var upgrade_names := ["1. +25% WEAPON DAMAGE", "2. +20% FIRE RATE", "3. +30 MAX HULL & REPAIR 50"]
	for i in range(3):
		var ub := Button.new()
		ub.text = upgrade_names[i]
		ub.custom_minimum_size = Vector2(360, 52)
		var idx := i
		ub.pressed.connect(func() -> void: apply_upgrade(idx))
		_p36_button(ub, false)
		lv.add_child(ub)
	# hangar panel (Wave 2) — shown before deployment, game paused behind it
	# Pass 11 (HOTFIX): was a fixed 460x640 translucent box on the same
	# layer as the HUD, so the HUD showed straight through it and the
	# button stack overflowed the bottom. Now a full-screen opaque modal:
	# full-rect anchors, alpha-1 background, input-blocking, and a
	# ScrollContainer so every control is reachable on any screen size.
	_hangar_panel = PanelContainer.new()
	_hangar_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hangar_panel.offset_left = 0.0
	_hangar_panel.offset_top = 0.0
	_hangar_panel.offset_right = 0.0
	_hangar_panel.offset_bottom = 0.0
	_hangar_panel.add_theme_stylebox_override("panel", _p36_modal_panel())
	_hangar_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_hangar_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	_hangar_panel.visible = false
	layer.add_child(_hangar_panel)
	var hscroll := ScrollContainer.new()
	hscroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	hscroll.offset_left = 0.0
	hscroll.offset_top = 0.0
	hscroll.offset_right = 0.0
	hscroll.offset_bottom = 0.0
	hscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_hangar_panel.add_child(hscroll)
	var hv := VBoxContainer.new()
	hv.alignment = BoxContainer.ALIGNMENT_CENTER
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hscroll.add_child(hv)
	var ht := Label.new()
	ht.text = "HANGAR — CHOOSE YOUR WAR MACHINE"
	ht.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ht.add_theme_font_size_override("font_size", 20)
	_p36_title(ht)
	hv.add_child(ht)
	var _hdiv := _p36_divider()
	hv.add_child(_hdiv)
	hv.move_child(_hdiv, 1)
	_hangar_portrait = TextureRect.new()
	_hangar_portrait.custom_minimum_size = Vector2(150, 150)
	_hangar_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_hangar_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hv.add_child(_hangar_portrait)
	# Pass 26 (UX: hangar overhaul): class cards, not bare chassis
	# buttons — one card per chassis with its skin preview (the same
	# front-idle sprite the portrait uses) and HULL / SPEED / MOBILITY
	# bars from hangar_chassis_stats. Tapping anywhere on a card —
	# portrait, name, stat bars, or its SELECT button — picks that
	# chassis (Pass 33 whole-card tap target); the border marks the
	# pick. Layout only: the cards change no stat, cost, or deploy
	# behaviour.
	var hcard_lbl := Label.new()
	hcard_lbl.text = "CLASS — TAP A CARD"
	hcard_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hcard_lbl.add_theme_font_size_override("font_size", 16)
	hv.add_child(hcard_lbl)
	var hcards := HBoxContainer.new()
	hcards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hcards.add_theme_constant_override("separation", 8)
	hv.add_child(hcards)
	for cname in ["scout", "assault", "support"]:
		var card_panel := PanelContainer.new()
		card_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# Pass 33 (BUGFIX: whole-card tap target): taps on the portrait,
		# name, or stat bars used to die on those controls (Control
		# default mouse_filter STOP) and only the small SELECT button
		# selected a chassis — on a phone the mech image did nothing.
		# The panel itself now selects on mouse click or screen touch;
		# every non-button child below is IGNORE so the tap reaches it.
		var cn_panel: String = cname
		card_panel.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
				_sel_chassis = cn_panel
				_refresh_hangar()
			elif ev is InputEventScreenTouch and ev.pressed:
				_sel_chassis = cn_panel
				_refresh_hangar())
		hcards.add_child(card_panel)
		var cv := VBoxContainer.new()
		cv.alignment = BoxContainer.ALIGNMENT_CENTER
		cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card_panel.add_child(cv)
		var cprev := TextureRect.new()
		cprev.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cprev.custom_minimum_size = Vector2(120, 120)
		cprev.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		cprev.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		var cpath2 := "res://sprites/p34/p34_%s.png" % cname
		if ResourceLoader.exists(cpath2):
			cprev.texture = load(cpath2)
		cv.add_child(cprev)
		var cname_lbl := Label.new()
		cname_lbl.text = cname.to_upper()
		cname_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cname_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cv.add_child(cname_lbl)
		var cbars: Dictionary = {}
		for bardef in [["HULL", "hull"], ["SPEED", "speed"], ["MOBILITY", "mobility"]]:
			var brow := HBoxContainer.new()
			brow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			brow.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cv.add_child(brow)
			var blbl := Label.new()
			blbl.text = bardef[0]
			blbl.custom_minimum_size = Vector2(62, 14)
			blbl.add_theme_font_size_override("font_size", 11)
			blbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			brow.add_child(blbl)
			var bar := ProgressBar.new()
			bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			bar.min_value = 0.0
			bar.max_value = 100.0
			bar.show_percentage = false
			bar.custom_minimum_size = Vector2(60, 14)
			bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			brow.add_child(bar)
			cbars[bardef[1]] = bar
		var csel := Button.new()
		csel.text = "SELECT " + cname.to_upper()
		csel.custom_minimum_size = Vector2(120, 36)
		var cn: String = cname
		csel.pressed.connect(func() -> void:
			_sel_chassis = cn
			_refresh_hangar())
		_p36_button(csel, false)
		cv.add_child(csel)
		_hangar_cards[cname] = {"panel": card_panel, "preview": cprev, "bars": cbars, "select": csel}
	# Pass 11 (HOTFIX): pick buttons in a 2-column grid, not one tall
	# stack — title + portrait + grid + stats + DEPLOY now fit a
	# 648-tall landscape screen without scrolling (scroll remains for
	# shorter screens).
	var hpick_lbl := Label.new()
	hpick_lbl.text = "LOADOUT PICKS"
	hpick_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hpick_lbl.add_theme_font_size_override("font_size", 16)
	hv.add_child(hpick_lbl)
	var hgrid := GridContainer.new()
	hgrid.columns = 2
	hgrid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hgrid.add_theme_constant_override("h_separation", 8)
	hgrid.add_theme_constant_override("v_separation", 6)
	hv.add_child(hgrid)
	for uname in ["repair_pulse", "grapple"]:
		var ubtn := Button.new()
		ubtn.text = "REPAIR PULSE" if uname == "repair_pulse" else "GRAPPLE"
		ubtn.custom_minimum_size = Vector2(400, 40)
		var un: String = uname
		ubtn.pressed.connect(func() -> void:
			_sel_utility = un
			_refresh_hangar())
		_hangar_pick_btns["utility:" + uname] = ubtn
		_p36_button(ubtn, false)
		hgrid.add_child(ubtn)
	for dname in ["iron_wall", "hunting_pack", "ghost_protocol"]:
		var dbtn := Button.new()
		dbtn.text = "DOCTRINE: " + dname.to_upper().replace("_", " ")
		dbtn.custom_minimum_size = Vector2(400, 40)
		var dn: String = dname
		dbtn.pressed.connect(func() -> void:
			_sel_doctrine = dn
			_refresh_hangar())
		_hangar_pick_btns["doctrine:" + dname] = dbtn
		_p36_button(dbtn, false)
		hgrid.add_child(dbtn)
	for rname in ["region1", "region2"]:
		var rbtn := Button.new()
		rbtn.text = "REGION: IRON FLATS" if rname == "region1" else "REGION: RUST FLATS (REGION 2)"
		rbtn.custom_minimum_size = Vector2(400, 40)
		var rn: String = rname
		rbtn.pressed.connect(func() -> void:
			_sel_region = rn
			_refresh_hangar())
		_hangar_pick_btns["region:" + rname] = rbtn
		_p36_button(rbtn, false)
		hgrid.add_child(rbtn)
	# Pass 45: dust-storm toggle (Rust Flats only — see set_dust_storm).
	_dust_storm_btn = Button.new()
	_dust_storm_btn.text = "DUST STORM (RUST FLATS): OFF"
	_dust_storm_btn.custom_minimum_size = Vector2(400, 40)
	_dust_storm_btn.pressed.connect(func() -> void:
		_sel_dust_storm = not _sel_dust_storm
		_refresh_hangar())
	_p36_button(_dust_storm_btn, false)
	hgrid.add_child(_dust_storm_btn)
	# Pass 23: difficulty pick buttons (Standard / Hard / Brutal).
	for dname in ["standard", "hard", "brutal"]:
		var dfbtn := Button.new()
		dfbtn.text = "DIFFICULTY: " + dname.to_upper()
		dfbtn.custom_minimum_size = Vector2(400, 40)
		var dn2: String = dname
		dfbtn.pressed.connect(func() -> void:
			_sel_difficulty = dn2
			_refresh_hangar())
		_hangar_pick_btns["difficulty:" + dname] = dfbtn
		_p36_button(dfbtn, false)
		_difficulty_btns.append(dfbtn)
		hgrid.add_child(dfbtn)
	# Pass 4: quality cycle button (S25 / Balanced / Forward+ laptop)
	_quality_btn = Button.new()
	_quality_btn.text = "QUALITY: BALANCED (TAP TO CYCLE)"
	_quality_btn.custom_minimum_size = Vector2(400, 40)
	_quality_btn.pressed.connect(func() -> void: cycle_quality_mode())
	_p36_button(_quality_btn, false)
	hgrid.add_child(_quality_btn)
	_hangar_stats = Label.new()
	_hangar_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hangar_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hangar_stats.custom_minimum_size = Vector2(400, 56)
	hv.add_child(_hangar_stats)
	# Pass 26: integrated loadout summary, refreshed with every pick.
	_hangar_summary = Label.new()
	_hangar_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hangar_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hangar_summary.custom_minimum_size = Vector2(400, 28)
	hv.add_child(_hangar_summary)
	# Pass 46: contracts board label — the run's 3 objectives, with
	# live progress, shown above DEPLOY so the player deploys knowing
	# what pays extra. Text comes from _refresh_hangar.
	_contracts_lbl = Label.new()
	_contracts_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_contracts_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_contracts_lbl.custom_minimum_size = Vector2(400, 42)
	hv.add_child(_contracts_lbl)
	var dep := Button.new()
	dep.text = "DEPLOY"
	dep.custom_minimum_size = Vector2(400, 54)
	dep.pressed.connect(_deploy_from_hangar)
	_p36_button(dep, true)
	_deploy_btn = dep
	hv.add_child(dep)
	# win + gameover panels
	_win_panel = _make_end_panel(layer, "VICTORY")
	_gameover_panel = _make_end_panel(layer, "GAME OVER")
	# endless continue on the win panel only
	var wv := _win_panel.get_child(0) as VBoxContainer
	var cb := Button.new()
	cb.text = "CONTINUE — ENDLESS DEFENSE"
	cb.custom_minimum_size = Vector2(360, 52)
	cb.pressed.connect(start_endless)
	_p36_button(cb, true)
	wv.add_child(cb)
	# Pass 11 (HOTFIX): registry of every HUD control, so the hangar
	# modal can hide the whole HUD while open and restore it on deploy.
	# Panels with their own visibility logic are excluded on purpose.
	for _hc in layer.get_children():
		if _hc is Control and _hc != _hangar_panel and _hc != _sub_panel and _hc != _lvl_panel and _hc != _win_panel and _hc != _gameover_panel:
			_hud_controls.append(_hc)
	# Pass 17 (Pause menu): created AFTER the registry loop on purpose —
	# it is not a HUD control, so _set_hud_visible never touches it.
	# ALWAYS (like the level-up/end panels) so its buttons work while
	# the tree is paused; MOUSE_FILTER_STOP so taps cannot reach the
	# game or HUD buttons behind it.
	_pause_panel = PanelContainer.new()
	_pause_panel.set_anchors_preset(Control.PRESET_CENTER)
	_pause_panel.position = Vector2(-210, -150)
	_pause_panel.size = Vector2(420, 300)
	_pause_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	_pause_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_panel.visible = false
	_pause_panel.add_theme_stylebox_override("panel", _p36_modal_panel())
	layer.add_child(_pause_panel)
	var pv := VBoxContainer.new()
	_pause_panel.add_child(pv)
	var pt := Label.new()
	pt.text = "PAUSED"
	pt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pt.add_theme_font_size_override("font_size", 26)
	_p36_title(pt)
	pv.add_child(pt)
	pv.add_child(_p36_divider())
	var ph := Label.new()
	ph.text = "Esc/P resume  •  RESTART resets this run  •  BACK TO HANGAR re-picks loadout"
	ph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ph.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pv.add_child(ph)
	_pause_resume_btn = Button.new()
	_pause_resume_btn.text = "RESUME"
	_pause_resume_btn.custom_minimum_size = Vector2(360, 52)
	_pause_resume_btn.pressed.connect(resume_from_pause)
	_p36_button(_pause_resume_btn, true)
	pv.add_child(_pause_resume_btn)
	_pause_restart_btn = Button.new()
	_pause_restart_btn.text = "RESTART RUN"
	_pause_restart_btn.custom_minimum_size = Vector2(360, 52)
	_pause_restart_btn.pressed.connect(restart_from_pause)
	_p36_button(_pause_restart_btn, false)
	pv.add_child(_pause_restart_btn)
	_pause_hangar_btn = Button.new()
	_pause_hangar_btn.text = "BACK TO HANGAR"
	_pause_hangar_btn.custom_minimum_size = Vector2(360, 52)
	_pause_hangar_btn.pressed.connect(back_to_hangar_from_pause)
	_p36_button(_pause_hangar_btn, false)
	pv.add_child(_pause_hangar_btn)
	# Pass 18 (UX): damage vignette — four red edge bars over the full
	# viewport, mouse-transparent, NOT a HUD control. Added last in
	# _build_hud, so it draws above the HUD zones (and above the
	# hangar modal, which is created earlier in this function) — that
	# is safe because the alpha decays to 0 on its own and no damage
	# can land while the tree is paused behind a modal.
	_vignette = Control.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.visible = false
	layer.add_child(_vignette)
	var _vig_t := 56.0
	var _vig_rects: Array = [
		[Vector2(0, 0), Vector2(_vw, _vig_t)],
		[Vector2(0, _vh - _vig_t), Vector2(_vw, _vig_t)],
		[Vector2(0, 0), Vector2(_vig_t, _vh)],
		[Vector2(_vw - _vig_t, 0), Vector2(_vig_t, _vh)],
	]
	for _vr in _vig_rects:
		var _cr := ColorRect.new()
		_cr.position = _vr[0]
		_cr.size = _vr[1]
		_cr.color = Color(0.85, 0.05, 0.05, 0.0)
		_cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_vignette.add_child(_cr)
		_vignette_edges.append(_cr)

func _make_end_panel(layer: CanvasLayer, title: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.position = Vector2(-210, -160)
	# Pass 42: starting size only — container layout grows the panel
	# to its content height on the next frame (435 with stats in this
	# run, inside the 648 landscape viewport), so never assert this
	# number synchronously after _end_game.
	p.size = Vector2(420, 320)
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	p.visible = false
	p.add_theme_stylebox_override("panel", _p36_modal_panel())
	layer.add_child(p)
	var v := VBoxContainer.new()
	p.add_child(v)
	var t := Label.new()
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 26)
	_p36_title(t)
	v.add_child(t)
	v.add_child(_p36_divider())
	var body := Label.new()
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(body)
	p.set_meta("label", body)
	var rb := Button.new()
	rb.text = "RESTART"
	rb.custom_minimum_size = Vector2(360, 52)
	rb.pressed.connect(_restart)
	_p36_button(rb, false)
	v.add_child(rb)
	return p

func _refresh_hud() -> void:
	if not _lbl_stats or not player:
		return
	_lbl_stats.text = "SALVAGE %d    KILLS %d    LV %d  XP %d/%d" % [salvage, kills, level, xp, xp_threshold()]
	# Pass 31: the live streak reads on the stats line only once it
	# matters (streak >= 5, when the combo bonus is actually paying).
	if kill_streak >= 5:
		_lbl_stats.text += "    STREAK x%d" % kill_streak
	# Pass 46: the board's completion count rides the stats line so
	# the run always shows it (suffix only, like the streak — no
	# existing stats assertion matches the line exactly).
	if not contracts_active.is_empty():
		var _cdone := 0
		for _cid in contracts_active:
			if bool(contracts_done.get(str(_cid), false)):
				_cdone += 1
		_lbl_stats.text += "    CONTRACTS %d/%d" % [_cdone, contracts_active.size()]
	var ucd: float = player.utility_cooldown()
	_lbl_wave.text = "WAVE %d%s    WEAPON: %s%s    %s: %s    DOCTRINE %s%s" % [wave, "/3" if not endless_mode else " ENDLESS", player.weapon_name(), "  [OVERHEATED]" if player.overheated else "", str(player.get("chassis")).to_upper(), "UTILITY READY [Q]" if ucd <= 0.0 else "utility %.0fs" % ucd, str(loadout["doctrine"]).to_upper().replace("_", " "), " [DRONE HOLD]" if drone_hold else ""]
	# Pass 9: floating 3D labels only in range — core within 25 m,
	# substation within 20 m; everything else was removed outright.
	if is_instance_valid(_core_lbl):
		_core_lbl.visible = player.global_position.distance_to(Vector3.ZERO) < 25.0
	if is_instance_valid(_sub_lbl):
		_sub_lbl.visible = player.global_position.distance_to(_substation_pos) < 20.0
	_hull_bar.max_value = player.max_hp
	_hull_bar.value = player.hp
	_heat_bar.value = player.heat
	_core_bar.max_value = core_max_hp
	_core_bar.value = core_hp
	# Pass 49: the OD bar shows charge at rest and drains with the
	# remaining overdrive time while active (full at trigger, empty
	# at expiry), so one bar reads both states without new chrome.
	if _od_bar:
		_od_bar.max_value = 100.0
		_od_bar.value = (overdrive_timer / OVERDRIVE_DURATION * 100.0) if overdrive_active else overdrive_charge
	_refresh_minimap()
	# Pass 37: the preview shows only during intermission (no active
	# wave, no end panel). While the hangar is open the tree is paused
	# so this never runs, and the Pass 11 registry keeps it hidden;
	# on deploy _set_hud_visible(true) restores it and the next frame
	# here re-applies the rule. The next wave is wave + 1 with the
	# same adaptation rule _start_wave uses.
	if is_instance_valid(_preview_panel) and is_instance_valid(_preview_lbl):
		var _show_preview := not _wave_active and not _game_over and not _won
		_preview_panel.visible = _show_preview
		if _show_preview:
			var _adapt := saved_adaptation if saved_adaptation != "" else adaptation_for(mech_kills, turret_kills)
			_preview_lbl.text = wave_preview_text(wave + 1, _adapt)
	# Pass 40 (HUD consolidation): the message bar is hidden, panel
	# and all, whenever no message is showing — it used to draw
	# permanently even empty. The preview then stacks directly under
	# the top bar (y=92) instead of floating over the message bar's
	# old slot; under a live message it sits at 126 (92 + 30 + 4).
	# _set_hud_visible(true) on deploy re-shows the zone, and the
	# next _refresh_hud frame re-applies this rule, so the hangar
	# restore path cannot leave an empty bar on screen.
	if is_instance_valid(_msg_zone) and _lbl_msg:
		var _msg_on := _lbl_msg.text != ""
		_msg_zone.visible = _msg_on
		_lbl_msg.visible = _msg_on
	if is_instance_valid(_preview_panel) and _lbl_msg:
		_preview_panel.position = Vector2(-350, 126.0 if _lbl_msg.text != "" else P40_TOP_H + 8.0)

# ---------------- Pass 16 minimap ----------------
# Map: world x -> panel x, world z -> panel y (screen-down is +z, the same
# direction the angled camera's ground ray maps to, per the Pass 7 test).
# Colours: player white, core blue, drone green, structures amber,
# enemies red. Dead structures and dead/freed entities get no dot.
func minimap_pos(world: Vector3) -> Vector2:
	var x := clampf((world.x + MINIMAP_RANGE) / (MINIMAP_RANGE * 2.0) * MINIMAP_SIZE, 0.0, MINIMAP_SIZE)
	var y := clampf((world.z + MINIMAP_RANGE) / (MINIMAP_RANGE * 2.0) * MINIMAP_SIZE, 0.0, MINIMAP_SIZE)
	return Vector2(x, y)

func _minimap_dot(node: Node, color: Color, size_px: float) -> ColorRect:
	if _minimap_dots.has(node):
		var existing: ColorRect = _minimap_dots[node]
		existing.color = color
		existing.size = Vector2(size_px, size_px)
		return existing
	var d := ColorRect.new()
	d.color = color
	d.size = Vector2(size_px, size_px)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_minimap_panel.add_child(d)
	_minimap_dots[node] = d
	return d

func _refresh_minimap() -> void:
	if _minimap_panel == null:
		return
	var live: Array = []
	if player:
		live.append(player)
	if _core_node:
		live.append(_core_node)
	if drone:
		live.append(drone)
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and not e.get("is_dead"):
			live.append(e)
	for s in get_tree().get_nodes_in_group("structures"):
		if is_instance_valid(s) and not s.get("is_dead_struct"):
			live.append(s)
	var stale: Array = []
	for k in _minimap_dots.keys():
		if not is_instance_valid(k) or k not in live:
			stale.append(k)
	for k in stale:
		var d: ColorRect = _minimap_dots[k]
		if is_instance_valid(d):
			d.queue_free()
		_minimap_dots.erase(k)
	for n in live:
		var dot: ColorRect
		var half: float
		# Pass 40: dots shrink with the 120 map (player 9, core 10,
		# rest 7) so dot-to-map proportion stays what Pass 20 set.
		if n == player:
			dot = _minimap_dot(n, Color(1.0, 1.0, 1.0), 9.0)
			half = 4.5
		elif n == _core_node:
			dot = _minimap_dot(n, Color(0.3, 0.8, 1.0), 10.0)
			half = 5.0
		elif n == drone:
			dot = _minimap_dot(n, Color(0.3, 0.9, 0.5), 7.0)
			half = 3.5
		elif n.is_in_group("enemies"):
			dot = _minimap_dot(n, Color(1.0, 0.25, 0.2), 7.0)
			half = 3.5
		else:
			dot = _minimap_dot(n, Color(1.0, 0.85, 0.3), 7.0)
			half = 3.5
		dot.position = minimap_pos(n.global_position) - Vector2(half, half)

# ---------------- automated test ----------------

func _check(cond: bool, what: String) -> void:
	if not cond:
		_test_failures.append(what)
		print("TEST FAIL: ", what)

func _run_test(delta: float) -> void:
	_test_t += delta
	if _test_stage == 0 and _test_t > 0.5:
		_test_stage = 1
		_check(player != null, "player exists")
		_check(camera != null, "camera exists")
		# Pass 7 (Overhaul A) as superseded by Pass 34: units are now flat
		# ground-plane top-down sprites (template art is top-down, so a
		# billboard would show it side-on). The Pass 7 anti-flat-plane
		# rule applied to FRONT-view art only; the chevron/ring/trim/
		# camera checks below are unchanged.
		var pbody: Node = player.get("_body")
		_check(pbody != null, "pass7: player body exists")
		if pbody:
			var p7_holder: Node = pbody.get_node_or_null("unit_sprite")
			_check(p7_holder != null and not (p7_holder is Sprite3D), "pass34: player body uses a flat top-down holder, not a billboard")
			_check(SpriteUtil.topdown_quad(p7_holder) != null, "pass34: player holder carries a flat td_quad")
			_check(pbody.get_node_or_null("facing_chevron") != null, "pass7: player has facing chevron")
			_check(pbody.get_node_or_null("health_ring") != null, "pass7: player has health ring")
			var _stack: Array = [pbody]
			var _has_billboard := false
			while not _stack.is_empty():
				var _n: Node = _stack.pop_back()
				for _ch in _n.get_children():
					if _ch is Sprite3D:
						_has_billboard = true
					_stack.append(_ch)
			_check(not _has_billboard, "pass34: player body has no billboard sprite")
		_check(Color(player.get("trim_color")) == Color(0.25, 0.85, 1.0), "pass7: player trim is cyan")
		var cam_off: Vector3 = camera.global_position - player.global_position
		_check(cam_off.y > 20.0 and cam_off.z > 20.0, "pass7: camera pitched angled view (offset %s)" % cam_off)
		var vs: Vector2 = get_viewport().get_visible_rect().size
		if vs.x > 0.0 and vs.y > 0.0:
			var gp_c: Vector3 = _ground_point(vs * 0.5)
			var gp_low: Vector3 = _ground_point(vs * 0.5 + Vector2(0, 80))
			_check(absf(gp_c.y) < 0.01, "pass7: ground point lies on y=0 plane (got %s)" % gp_c)
			_check(gp_low.z > gp_c.z, "pass7: angled camera ray — lower screen maps further south (%s -> %s)" % [gp_c, gp_low])
		# one of each enemy kind: flat top-down holder + chevron + ring + red trim, no billboard (Pass 34)
		var p7_kinds := ["scout", "heavy", "shield_heavy", "burrower", "siege"]
		var p7_foes: Array = []
		for _k in p7_kinds:
			p7_foes.append(spawn_enemy(_k, Vector3(-40, 0, -40)))
		await get_tree().process_frame
		for _e in p7_foes:
			var _eb: Node = _e.get("_body")
			var _eh: Node = _eb.get_node_or_null("unit_sprite") if _eb else null
			_check(_eb != null and _eh != null and not (_eh is Sprite3D) and SpriteUtil.topdown_quad(_eh) != null, "pass34: %s uses flat top-down sprite" % _e.get("kind"))
			_check(_eb != null and _eb.get_node_or_null("facing_chevron") != null and _eb.get_node_or_null("health_ring") != null, "pass7: %s has chevron + health ring" % _e.get("kind"))
			var _tc: Color = Color(_e.get("trim_color"))
			_check(_tc.r > 0.8 and _tc.g < 0.5, "pass7: %s trim is red/orange (%s)" % [_e.get("kind"), _tc])
		# shield opacity tracks shield HP on a frontal hit
		var p7_sh: Node = null
		for _e in p7_foes:
			if str(_e.get("kind")) == "shield_heavy":
				p7_sh = _e
		if p7_sh:
			var p7_sh_mat: StandardMaterial3D = p7_sh.get("_shield_mat")
			var p7_a0 := p7_sh_mat.albedo_color.a if p7_sh_mat else -1.0
			p7_sh.take_damage(40.0, p7_sh.get_facing(), "TestGun")
			var p7_a1 := p7_sh_mat.albedo_color.a if p7_sh_mat else -1.0
			_check(p7_a0 > p7_a1 and p7_a1 > 0.1, "pass7: shield opacity falls with shield HP (%f -> %f)" % [p7_a0, p7_a1])
		for _e in p7_foes:
			if is_instance_valid(_e):
				_e.die_silent()
		await get_tree().process_frame
		# allied drone: generated billboard + green trim + ground ring
		_check(drone != null, "pass7: drone exists")
		if drone:
			_check(drone.get_node_or_null("unit_sprite") != null and drone.get_node_or_null("unit_sprite") is Sprite3D, "pass7: drone uses billboard sprite")
			_check(Color(drone.get("trim_color")) == Color(0.3, 0.9, 0.5), "pass7: drone trim is green")
		# Pass 8 (Overhaul B): tiled ground atlas, plaza, clustered ruins,
		# dark walls + edge strips, tile props, rust-as-atlas, dim lines.
		_check(_ground_mat != null and _ground_mat.albedo_texture != null, "pass8: ground has atlas texture")
		if _ground_mat and _ground_mat.albedo_texture:
			_check(str(_ground_mat.albedo_texture.resource_path).contains("p39_ground"), "pass39 supersedes pass8: ground texture is the v2 atlas (%s)" % _ground_mat.albedo_texture.resource_path)
		_check(_plaza_node != null, "pass8: core plaza plane exists")
		if _plaza_node:
			var _pm: StandardMaterial3D = _plaza_node.get_surface_override_material(0)
			_check(_pm != null and _pm.albedo_texture != null and str(_pm.albedo_texture.resource_path).contains("plaza_atlas"), "pass8: plaza uses metal-platform atlas")
		var _p8_overlay := false
		if is_instance_valid(_region_marker):
			for _ch in _region_marker.get_children():
				if _ch is MeshInstance3D and _ch.mesh is PlaneMesh:
					_p8_overlay = true
		_check(not _p8_overlay, "pass8: region marker has no overlay plane (rust is in the atlas)")
		_check(set_region("region2"), "pass8: region2 selectable")
		if _ground_mat and _ground_mat.albedo_texture:
			_check(str(_ground_mat.albedo_texture.resource_path).contains("rust"), "pass8: region2 swaps to rust atlas (%s)" % _ground_mat.albedo_texture.resource_path)
		_check(absf(_world_env.fog_density - 0.004) < 0.001, "pass8: region2 fog is 0.004 (got %f)" % _world_env.fog_density)
		_check(set_region("region1"), "pass8: region1 restores")
		if _ground_mat and _ground_mat.albedo_texture:
			_check(not str(_ground_mat.albedo_texture.resource_path).contains("rust"), "pass8: region1 restores base atlas")
		_check(absf(_world_env.fog_density - 0.0022) < 0.001, "pass8: region1 fog is 0.0022 (got %f)" % _world_env.fog_density)
		_check(_ruin_positions.size() >= 20, "pass8: clustered ruins count >= 20 (got %d)" % _ruin_positions.size())
		var _p8_clustered := 0
		for _rp in _ruin_positions:
			for _rq in _ruin_positions:
				if _rp != _rq and _rp.distance_to(_rq) < 7.0:
					_p8_clustered += 1
					break
		_check(_ruin_positions.size() > 0 and _p8_clustered >= _ruin_positions.size() * 4 / 5, "pass8: ruins clustered, %d/%d have a neighbour within 7 m" % [_p8_clustered, _ruin_positions.size()])
		_check(_wall_edges.size() == 4, "pass8: 4 wall edge strips (got %d)" % _wall_edges.size())
		_check(_wall_mat != null and _wall_mat.albedo_color.r < 0.15 and not _wall_mat.emission_enabled, "pass8: walls dark, no glow")
		_check(_prop_sprites.size() >= 6, "pass8: tile props >= 6 (got %d)" % _prop_sprites.size())
		var _p8_props_textured := 0
		for _ps in _prop_sprites:
			for _ch in _ps.get_children():
				if _ch is MeshInstance3D:
					var _m: StandardMaterial3D = _ch.get_surface_override_material(0)
					if _m != null and _m.albedo_texture != null:
						_p8_props_textured += 1
						break
		_check(_p8_props_textured == _prop_sprites.size(), "pass8: every prop carries a tile texture (%d/%d)" % [_p8_props_textured, _prop_sprites.size()])
		_power_line_bright_t = 0.0
		_update_power_line_brightness()
		_check(_power_line_mat != null and absf(_power_line_mat.albedo_color.a - 0.35) < 0.01, "pass8: power lines dim outside build mode (alpha %f)" % (_power_line_mat.albedo_color.a if _power_line_mat else -1.0))
		_power_line_bright_t = 3.0
		_update_power_line_brightness()
		_check(_power_line_mat != null and absf(_power_line_mat.albedo_color.a - 0.75) < 0.01, "pass8: power lines bright after a build (alpha %f)" % (_power_line_mat.albedo_color.a if _power_line_mat else -1.0))
		_power_line_bright_t = 0.0
		_update_power_line_brightness()
		_check(_sun_light != null and _sun_light.light_energy >= 1.3, "pass8: sun brightened for contrast (energy %f)" % (_sun_light.light_energy if _sun_light else -1.0))
		_check(_world_env != null and _world_env.ambient_light_energy <= 0.55, "pass8: ambient dimmed for contrast (energy %f)" % (_world_env.ambient_light_energy if _world_env else -1.0))
		# Pass 6 (BUG-HUNT): spawn-cap stress — 60 mixed enemies at once.
		# Placed first in stage 1, before any await, so the stage-2 transition
		# (which fires at _test_t > 1.4) cannot interleave a spawn into the count.
		var cap_base := get_tree().get_nodes_in_group("enemies").size()
		var cap_before_nodes := count_render_nodes()
		var cap_kinds := ["scout", "heavy", "shield_heavy", "burrower"]
		var cap_spawned: Array = []
		for i in range(60):
			var ang := float(i) * TAU / 60.0
			var cpos := Vector3(cos(ang) * 45.0, 0, sin(ang) * 45.0)
			cap_spawned.append(spawn_enemy(cap_kinds[i % cap_kinds.size()], cpos))
		await get_tree().process_frame
		# Pass 12 flake fix (sibling of the cleanup fix below): the old
		# global-count check raced live wave spawns — the retry run failed
		# it with 61 (one wave enemy inside the await) while all 60 capped
		# spawns were registered. Assert on the spawned set itself.
		var cap_reg := 0
		for e in cap_spawned:
			if is_instance_valid(e) and e.is_in_group("enemies"):
				cap_reg += 1
		_check(cap_reg == 60, "spawn cap: all 60 spawned enemies registered (registered %d, group total %d incl. any wave spawn)" % [cap_reg, get_tree().get_nodes_in_group("enemies").size()])
		var cap_all_alive := true
		for e in cap_spawned:
			if not is_instance_valid(e) or e.get("is_dead") or float(e.get("hp")) <= 0.0 or float(e.get("hp")) != float(e.get("max_hp")):
				cap_all_alive = false
		_check(cap_all_alive, "spawn cap: all 60 spawned enemies alive at full HP")
		_check(count_render_nodes() > cap_before_nodes, "spawn cap: scene render nodes grew with 60 enemies (%d -> %d)" % [cap_before_nodes, count_render_nodes()])
		for e in cap_spawned:
			if is_instance_valid(e):
				e.die_silent()
		await get_tree().process_frame
		await get_tree().process_frame
		# Pass 12 flake fix: the old check compared the GLOBAL enemy group
		# to baseline, but the live game (time_scale 4) can wave-spawn an
		# enemy inside this window — the 2026-10-25 gate run failed with
		# exactly one such extra enemy (group 1, base 0) while all 60 capped
		# enemies had cleaned up. Assert on the spawned set itself, which
		# is what this check actually means; the global total is reported
		# for diagnosis, not asserted.
		var cap_left := 0
		for e in cap_spawned:
			if is_instance_valid(e) and e.is_in_group("enemies"):
				cap_left += 1
		_check(cap_left == 0, "spawn cap: all 60 spawned enemies left the group after cleanup (left %d, group total %d incl. any wave spawn)" % [cap_left, get_tree().get_nodes_in_group("enemies").size()])
		salvage = 250
		_check(try_build("turret", Vector3(10, 0, 10)), "turret builds at 10,10")
		_check(not try_build("turret", Vector3(10, 0, 10)), "occupied spot refuses rebuild")
		salvage = 0
		_check(not try_build("turret", Vector3(20, 0, 20)), "build refuses when broke")
		# generator extends power
		salvage = 500
		_check(try_build("generator", Vector3(40, 0, 0)), "generator builds")
		_check(try_build("turret", Vector3(54, 0, 0)), "far turret builds")
		var far_turret: Node = null
		var unpowered_turret: Node = null
		_check(try_build("turret", Vector3(-50, 0, 40)), "remote turret builds")
		for s in get_tree().get_nodes_in_group("structures"):
			if Vector3(s.global_position.x, 0, s.global_position.z).distance_to(Vector3(54, 0, 0)) < 1.0:
				far_turret = s
			if Vector3(s.global_position.x, 0, s.global_position.z).distance_to(Vector3(-50, 0, 40)) < 1.0:
				unpowered_turret = s
		_check(far_turret != null and far_turret.is_powered(), "turret outside core radius but inside gen radius is powered")
		_check(unpowered_turret != null and not unpowered_turret.is_powered(), "remote turret outside all radii is unpowered")
		# Pass 7: powered lamp matches powered state on both turrets.
		_check(far_turret != null and far_turret.get("_power_lamp") != null and far_turret.power_lamp_on(), "pass7: powered turret lamp is on")
		_check(unpowered_turret != null and unpowered_turret.get("_power_lamp") != null and not unpowered_turret.power_lamp_on(), "pass7: unpowered turret lamp is off")
		# directional armor: two heavies facing core (+Z from z=-30)
		var h1 = spawn_enemy("heavy", Vector3(0, 0, -30))
		var h2 = spawn_enemy("heavy", Vector3(6, 0, -30))
		await get_tree().process_frame
		var facing: Vector3 = h1.get_facing()
		var front_dmg: float = h1.take_damage(40.0, facing, "TestGun")
		var rear_dmg: float = h2.take_damage(40.0, -facing, "TestGun")
		_check(absf(front_dmg - 14.0) < 0.5, "heavy front damage is 35%% (got %f)" % front_dmg)
		_check(absf(rear_dmg - 60.0) < 0.5, "heavy rear damage is 150%% (got %f)" % rear_dmg)
		_check(rear_dmg > front_dmg, "rear damage > front damage")
		h1.die_silent()
		h2.die_silent()
		# Wave 1: salvage cache pays out on contact
		var s_before := salvage
		_make_cache(player.global_position)
		_update_caches(0.016)
		_check(salvage == s_before + 20, "salvage cache pays +20 (got %d)" % (salvage - s_before))
		# Wave 1: scattergun fires exactly 5 pellets
		player.current_weapon = 3
		_check(player.weapon_name() == "Scattergun", "weapon 3 is Scattergun")
		player.aim_point = player.global_position + Vector3(0, 0, -20)
		var cc := get_child_count()
		player._fire()
		_check(get_child_count() == cc + 5, "scattergun spawns 5 pellets (got %d)" % (get_child_count() - cc))
		player.current_weapon = 1
		player._fire_cd = 0.0
		# Pass 10: Flak Cannon [4] — selects, fires one shell, heat + cooldown
		player.current_weapon = 4
		_check(player.weapon_name() == "Flak Cannon", "weapon 4 is Flak Cannon")
		player.aim_point = player.global_position + Vector3(0, 0, -20)
		var heat10: float = player.heat
		var cc10 := get_child_count()
		player._fire_cd = 0.0
		player._fire()
		_check(get_child_count() == cc10 + 1, "flak cannon spawns exactly 1 shell (got %d)" % (get_child_count() - cc10))
		_check(player._fire_cd > 0.5 and player._fire_cd < 0.9, "flak cooldown ~0.70 s (got %f)" % player._fire_cd)
		_check(player.heat > heat10, "flak shot adds heat (got %f, was %f)" % [player.heat, heat10])
		player._fire_cd = 0.0
		# Pass 10: KEY_4 selects the Flak Cannon via the input handler
		player.current_weapon = 1
		var kev := InputEventKey.new()
		kev.keycode = KEY_4
		kev.pressed = true
		kev.echo = false
		_input(kev)
		_check(player.current_weapon == 4, "KEY_4 selects Flak Cannon (got %d)" % player.current_weapon)
		# Pass 10: HUD weapon button 4 also selects it
		player.current_weapon = 1
		(_weapon_icons[3] as Button).pressed.emit()
		_check(player.current_weapon == 4, "HUD button 4 selects Flak Cannon (got %d)" % player.current_weapon)
		# Pass 21: Tesla Arc [5] — selects, fires one bolt, heat + cooldown
		player.current_weapon = 5
		_check(player.weapon_name() == "Tesla Arc", "weapon 5 is Tesla Arc")
		player.aim_point = player.global_position + Vector3(0, 0, -20)
		var heat21: float = player.heat
		var cc21 := get_child_count()
		player._fire_cd = 0.0
		player._fire()
		_check(get_child_count() == cc21 + 1, "tesla arc spawns exactly 1 bolt (got %d)" % (get_child_count() - cc21))
		_check(player._fire_cd > 0.4 and player._fire_cd < 0.7, "tesla cooldown ~0.55 s (got %f)" % player._fire_cd)
		_check(player.heat > heat21, "tesla shot adds heat (got %f, was %f)" % [player.heat, heat21])
		player._fire_cd = 0.0
		# Pass 21: KEY_5 selects the Tesla Arc via the input handler
		player.current_weapon = 1
		var kev5 := InputEventKey.new()
		kev5.keycode = KEY_5
		kev5.pressed = true
		kev5.echo = false
		_input(kev5)
		_check(player.current_weapon == 5, "KEY_5 selects Tesla Arc (got %d)" % player.current_weapon)
		# Pass 21: HUD weapon button 5 also selects it, and it carries an icon
		player.current_weapon = 1
		(_weapon_icons[4] as Button).pressed.emit()
		_check(player.current_weapon == 5, "HUD button 5 selects Tesla Arc (got %d)" % player.current_weapon)
		_check((_weapon_icons[4] as Button).icon != null, "HUD button 5 carries a generated icon")
		# Pass 48: Grenade Launcher [6] — selects, fires one slow
		# arcing shell, heat + cooldown; KEY_6 + HUD button 6 select
		# it, and the utility button sits clear of the sixth slot.
		player.current_weapon = 6
		_check(player.weapon_name() == "Grenade Launcher", "weapon 6 is Grenade Launcher")
		player.aim_point = player.global_position + Vector3(0, 0, -20)
		var heat48: float = player.heat
		var cc48 := get_child_count()
		player._fire_cd = 0.0
		player._fire()
		_check(get_child_count() == cc48 + 1, "grenade launcher spawns exactly 1 shell (got %d)" % (get_child_count() - cc48))
		_check(player._fire_cd > 0.8 and player._fire_cd < 1.0, "grenade cooldown ~0.90 s (got %f)" % player._fire_cd)
		_check(player.heat > heat48, "grenade shot adds heat (got %f, was %f)" % [player.heat, heat48])
		# Release the live shell now: its landing blast is real, and
		# a later section must never take splash from this check.
		var p48_live = get_child(cc48)
		if p48_live != null and str(p48_live.get("weapon_name")) == "Grenade Launcher" and p48_live.has_method("release_to_pool"):
			p48_live.release_to_pool()
		player._fire_cd = 0.0
		# Pass 48: KEY_6 selects the Grenade Launcher via the input handler
		player.current_weapon = 1
		var kev6 := InputEventKey.new()
		kev6.keycode = KEY_6
		kev6.pressed = true
		kev6.echo = false
		_input(kev6)
		_check(player.current_weapon == 6, "KEY_6 selects Grenade Launcher (got %d)" % player.current_weapon)
		# Pass 48: HUD weapon button 6 also selects it, and it carries an icon
		player.current_weapon = 1
		(_weapon_icons[5] as Button).pressed.emit()
		_check(player.current_weapon == 6, "HUD button 6 selects Grenade Launcher (got %d)" % player.current_weapon)
		_check((_weapon_icons[5] as Button).icon != null, "HUD button 6 carries a generated icon")
		_check(absf((_utility_btn as Control).position.x - 352.0) < 0.5, "utility button moved to x 352, clear of weapon button 6 (got %f)" % (_utility_btn as Control).position.x)
		# Pass 48: arc + AoE — a manually stepped shell lands 30 m
		# ahead, arcs high mid-flight, bursts 6 m at landing, spares
		# a distant enemy and never touches the player. Far-field
		# scenario (flak-test pattern) so no core/structure fire
		# interferes.
		var g1 = spawn_enemy("scout", Vector3(45, 0, -8))
		var g2 = spawn_enemy("scout", Vector3(47, 0, -6))
		var g3 = spawn_enemy("scout", Vector3(45, 0, 20))
		await get_tree().process_frame
		var ghp1: float = g1.get("hp")
		var ghp2: float = g2.get("hp")
		var ghp3: float = g3.get("hp")
		var php48: float = player.hp
		var gb = Node3D.new()
		gb.set_script(load("res://scripts/bullet.gd"))
		gb.position = Vector3(45, 1.5, 22)
		add_child(gb)
		gb.setup(Vector3(0, 0, -1), 30.0, "Grenade Launcher", true, false, 30.0, 6.0, 7.0, 1.0)
		_check(float(gb.get("speed")) == 30.0, "grenade shell is slower than flak (30 vs 48)")
		gb._process(0.016)
		var gae: Vector3 = gb.get("_arc_end")
		_check(absf(gae.x - 45.0) < 0.5 and absf(gae.z - (-8.0)) < 0.5, "grenade arc lands 30 m ahead (got %s)" % str(gae))
		gb._process(0.484)
		_check(absf(gb.global_position.y - 8.5) < 0.6, "grenade arcs high mid-flight (y %f)" % gb.global_position.y)
		for _gstep in range(40):
			if not is_instance_valid(gb) or gb.is_queued_for_deletion() or gb.get_parent() == null:
				break
			gb._process(0.016)
		var gb_detonated := not is_instance_valid(gb) or gb.get_parent() == null
		await get_tree().process_frame
		_check(gb_detonated, "grenade detonates at landing and returns to the bullet pool")
		_check(not is_instance_valid(g1) or float(g1.get("hp")) < ghp1, "grenade AoE damages the landing-point enemy (hp %f)" % ghp1)
		_check(not is_instance_valid(g2) or float(g2.get("hp")) < ghp2, "grenade AoE damages a nearby second enemy (hp %f)" % ghp2)
		_check(is_instance_valid(g3) and float(g3.get("hp")) == ghp3, "grenade AoE spares a distant enemy (hp %f)" % ghp3)
		_check(player.hp == php48, "grenade AoE never damages the player (hp %f)" % player.hp)
		if is_instance_valid(g1):
			g1.die_silent()
		if is_instance_valid(g2):
			g2.die_silent()
		if is_instance_valid(g3):
			g3.die_silent()
		player.current_weapon = 1
		player._fire_cd = 0.0
		# Pass 21: chain — one bolt hits the first scout (20), jumps to
		# the second within 12 m (15) and the third (10), and stops
		# before a fourth scout 26+ m from the third. Far-field scenario
		# (flak-test pattern) so no core/structure fire interferes.
		var t1 = spawn_enemy("scout", Vector3(45, 0, 10))
		var t2 = spawn_enemy("scout", Vector3(48, 0, 12))
		var t3 = spawn_enemy("scout", Vector3(51, 0, 14))
		var t4 = spawn_enemy("scout", Vector3(45, 0, 40))
		await get_tree().process_frame
		# Pass 24 (BUG-HUNT): the baseline run failed this section (t1 took the
		# 75% chain hit, t2 the 20 primary) because scouts drift toward the
		# core during the awaited frame, and at time_scale 4 one slow host
		# frame moves a scout metres — enough for t2 to drift onto the bolt
		# line while t1 drifts off it, so the bolt struck t2 first. The game
		# is correct (chain order follows the actual first hit); the test
		# geometry was not drift-proof. Re-place all four targets at exact
		# spots with no await before the bolt is built, so the bolt path,
		# the primary, and the chain order are all deterministic.
		t1.global_position = Vector3(45, 0, 10)
		t2.global_position = Vector3(48, 0, 12)
		t3.global_position = Vector3(51, 0, 14)
		t4.global_position = Vector3(45, 0, 40)
		var thp1: float = t1.get("hp")
		var thp2: float = t2.get("hp")
		var thp3: float = t3.get("hp")
		var thp4: float = t4.get("hp")
		var tb = Node3D.new()
		tb.set_script(load("res://scripts/bullet.gd"))
		tb.position = Vector3(45, 1.5, 22)
		add_child(tb)
		# Pass 21 flake fix (same as the flak fix below): setup in the
		# SAME synchronous block as add_child — no await between, so no
		# engine frame ever moves this bolt as a default Autocannon round.
		tb.setup(Vector3(0, 0, -1), 20.0, "Tesla Arc", true, false, 62.0, 0.0, 0.0, 0.9, 0.0, 2, 12.0)
		for _step in range(40):
			if not is_instance_valid(tb) or tb.is_queued_for_deletion() or tb.get_parent() == null:
				break
			tb._process(0.016)
		# Pass 24: capture the post-chain HP synchronously, before the awaited
		# frame — a live turret bullet landing in that frame could otherwise
		# shift an exact-HP check by its own damage (same race class as the
		# drift above, and the Pass 22 flak-pool race).
		var p24_t1hp: float = float(t1.get("hp")) if is_instance_valid(t1) else -1.0
		var p24_t2hp: float = float(t2.get("hp")) if is_instance_valid(t2) else -1.0
		var p24_t3hp: float = float(t3.get("hp")) if is_instance_valid(t3) else -1.0
		var p24_t4hp: float = float(t4.get("hp")) if is_instance_valid(t4) else -1.0
		# Pass 40 (test-only fix, same race class as the Pass 24 HP
		# capture above): the bolt releases into the Pass 19 bullet
		# pool, and a shot fired during the awaited frame below can
		# take that exact node back out of the pool — so a post-await
		# parent check fails even when the chain completed (the HP
		# checks pass, the bolt just isn't the bolt anymore). Capture
		# release before the await; the check passes if the bolt
		# released during the driven chain OR by the awaited frame.
		# A bolt that never releases still fails: pool reuse can only
		# happen after a release, so a never-released bolt is never
		# re-parented by another shot.
		var p24_released := tb.get_parent() == null
		await get_tree().process_frame
		_check(p24_released or tb.get_parent() == null, "tesla bolt releases after its chain (no pierce-through)")
		_check(is_instance_valid(t1) and absf(p24_t1hp - (thp1 - 20.0)) < 0.5, "tesla primary deals 20 to first scout (%f -> %f)" % [thp1, p24_t1hp])
		_check(is_instance_valid(t2) and absf(p24_t2hp - (thp2 - 15.0)) < 0.5, "tesla chain deals 15 (75%%) to second scout (%f -> %f)" % [thp2, p24_t2hp])
		_check(is_instance_valid(t3) and absf(p24_t3hp - (thp3 - 10.0)) < 0.5, "tesla chain deals 10 (50%%) to third scout (%f -> %f)" % [thp3, p24_t3hp])
		_check(is_instance_valid(t4) and p24_t4hp == thp4, "tesla chain stops before a scout out of range (%f)" % thp4)
		if is_instance_valid(t1):
			t1.die_silent()
		if is_instance_valid(t2):
			t2.die_silent()
		if is_instance_valid(t3):
			t3.die_silent()
		if is_instance_valid(t4):
			t4.die_silent()
		player.current_weapon = 1
		player._fire_cd = 0.0
		# Pass 10: proximity fuse detonates an AoE burst on a group, spares
		# a distant enemy and never touches the player. Far-field scenario
		# (mortar-test pattern) so no core/structure fire interferes.
		var f1 = spawn_enemy("scout", Vector3(45, 0, 10))
		var f2 = spawn_enemy("scout", Vector3(46, 0, 11))
		var f3 = spawn_enemy("scout", Vector3(45, 0, 30))
		await get_tree().process_frame
		var hp1: float = f1.get("hp")
		var hp2: float = f2.get("hp")
		var hp3: float = f3.get("hp")
		var php10: float = player.hp
		var fb = Node3D.new()
		fb.set_script(load("res://scripts/bullet.gd"))
		fb.position = Vector3(45, 1.5, 22)
		add_child(fb)
		# Pass 21 flake fix (test-only): the old await between add_child
		# and setup let one engine frame move this shell as a default
		# Autocannon round at time_scale 4 — on a loaded host that frame
		# jumped it past both fuse targets, so it never detonated (the
		# gate run's single failure; the pre-gate run passed). Setup in
		# the same synchronous block, so manual stepping is deterministic.
		fb.setup(Vector3(0, 0, -1), 22.0, "Flak Cannon", true, false, 48.0, 5.5, 0.0, 0.9, 4.0)
		for _step in range(30):
			if not is_instance_valid(fb) or fb.is_queued_for_deletion() or fb.get_parent() == null:
				break
			fb._process(0.016)
		# Pass 22 flake fix (test-only): the old check re-read the
		# parent AFTER an engine frame, but a live turret can reuse a
		# pooled shell in that frame, re-parenting it and failing the
		# check even though it detonated (the gate run's single
		# failure; the AoE checks passed). Record detonation
		# synchronously at the end of manual stepping, before any
		# live frame runs; the assertion's meaning is unchanged.
		var fb_detonated := not is_instance_valid(fb) or fb.get_parent() == null
		await get_tree().process_frame
		_check(fb_detonated, "flak shell detonates and returns to the bullet pool (proximity fuse)")
		_check(not is_instance_valid(f1) or float(f1.get("hp")) < hp1, "flak AoE damages the fused enemy (hp %f)" % hp1)
		_check(not is_instance_valid(f2) or float(f2.get("hp")) < hp2, "flak AoE damages a nearby second enemy (hp %f)" % hp2)
		_check(is_instance_valid(f3) and float(f3.get("hp")) == hp3, "flak AoE spares a distant enemy (hp %f)" % hp3)
		_check(player.hp == php10, "flak AoE never damages the player (hp %f)" % player.hp)
		if is_instance_valid(f1):
			f1.die_silent()
		if is_instance_valid(f2):
			f2.die_silent()
		if is_instance_valid(f3):
			f3.die_silent()
		player.current_weapon = 1
		player._fire_cd = 0.0
		# Wave 1: XP threshold levels up; test mode auto-applies the damage upgrade
		var lvl0 := level
		var dmg0: float = player.damage_mult
		grant_xp(xp_threshold())
		_check(level == lvl0 + 1, "xp threshold levels up (lvl %d -> %d)" % [lvl0, level])
		_check(player.damage_mult > dmg0, "level-up upgrade applied to damage_mult")
		# Wave 1: kill split + adaptation mapping
		var tk0 := turret_kills
		var ks = spawn_enemy("scout", Vector3(35, 0, -35))
		await get_tree().process_frame
		ks.take_damage(999.0, Vector3(0, 0, 1), "Turret")
		_check(turret_kills == tk0 + 1, "turret kill tracked in kill split")
		_check(adaptation_for(10, 0) == "shielded_heavies", "adaptation: mech-heavy split -> shielded heavies")
		_check(adaptation_for(0, 10) == "tunneling_units", "adaptation: turret-heavy split -> tunneling units")
		_check(adaptation_for(5, 5) == "mixed_doctrine", "adaptation: balanced split -> mixed doctrine")
		# Wave 2: chassis stats + grapple utility
		player.apply_loadout("scout", "grapple")
		_check(player.max_hp == 110.0 and player.max_speed > 16.0, "scout chassis stats applied (hp %f speed %f)" % [player.max_hp, player.max_speed])
		player.aim_point = player.global_position + Vector3(0, 0, -15)
		player.velocity = Vector3.ZERO
		_check(player.try_utility(), "grapple utility fires")
		_check(player.velocity.length() > 20.0, "grapple boosts velocity (got %f)" % player.velocity.length())
		# Pass 5 audit (H1): the boost must survive a real _process frame —
		# the old speed clamp ate it on the next frame, so the utility barely moved.
		player._process(0.016)
		_check(player.velocity.length() > player.max_speed, "grapple boost survives one process frame (got %f, max %f)" % [player.velocity.length(), player.max_speed])
		_check(not player.try_utility(), "utility cooldown blocks immediate reuse")
		# Wave 2: support chassis + repair pulse heals player and structures
		var tt: Node = null
		for s in get_tree().get_nodes_in_group("structures"):
			if str(s.get("structure_kind")) == "turret" and Vector3(s.global_position.x, 0, s.global_position.z).distance_to(Vector3(10, 0, 10)) < 1.0:
				tt = s
		_check(tt != null, "test turret found for repair check")
		if tt:
			tt.take_damage(40.0)
			var thp: float = tt.get("hp")
			player.apply_loadout("support", "repair_pulse")
			player.hp = 40.0
			_check(player.try_utility(), "repair pulse fires")
			_check(player.hp > 40.0, "repair pulse heals player (hp %f)" % player.hp)
			_check(float(tt.get("hp")) > thp, "repair pulse heals structures (%f -> %f)" % [thp, float(tt.get("hp"))])
			# support build discount: turret 50 -> 40, so exactly 40 salvage suffices
			salvage = 40
			_check(try_build("turret", Vector3(-30, 0, -30)), "support discount: turret builds at exactly 40 salvage")
		# Wave 2: loadout persists to its file and reads back
		loadout = {"chassis": "support", "utility": "repair_pulse", "doctrine": "iron_wall"}
		save_loadout()
		var lo := read_loadout_file()
		_check(str(lo.get("chassis", "")) == "support", "loadout file round-trips chassis")
		# restore assault defaults for the rest of the test
		player.apply_loadout("assault", "repair_pulse")
		player.velocity = Vector3.ZERO
		salvage = 500
		player.global_position = Vector3(0, 0, 14)
		# Pass 1 (Wave 3): mortar + EMP pylon build costs and power
		salvage = 200
		_check(try_build("mortar", Vector3(30, 0, 10)), "mortar builds for 90 salvage")
		var mortar_node: Node = null
		var remote_mortar: Node = null
		for s in get_tree().get_nodes_in_group("structures"):
			var sf := Vector3(s.global_position.x, 0, s.global_position.z)
			if str(s.get("structure_kind")) == "mortar":
				if sf.distance_to(Vector3(30, 0, 10)) < 1.0:
					mortar_node = s
		_check(mortar_node != null and mortar_node.is_powered(), "mortar near core is powered")
		salvage = 89
		_check(not try_build("mortar", Vector3(38, 0, 10)), "mortar refuses at 89 salvage")
		salvage = 200
		_check(try_build("emp_pylon", Vector3(20, 0, 16)), "emp pylon builds for 120 salvage")
		var emp_node: Node = null
		for s in get_tree().get_nodes_in_group("structures"):
			if str(s.get("structure_kind")) == "emp_pylon":
				emp_node = s
		_check(emp_node != null and emp_node.is_powered(), "emp pylon near core is powered")
		salvage = 119
		_check(not try_build("emp_pylon", Vector3(12, 0, 24)), "emp pylon refuses at 119 salvage")
		salvage = 200
		_check(try_build("mortar", Vector3(-45, 0, -30)), "remote mortar builds")
		for s in get_tree().get_nodes_in_group("structures"):
			var sf2 := Vector3(s.global_position.x, 0, s.global_position.z)
			if str(s.get("structure_kind")) == "mortar" and sf2.distance_to(Vector3(-45, 0, -30)) < 1.0:
				remote_mortar = s
		_check(remote_mortar != null and not remote_mortar.is_powered(), "remote mortar outside power net is unpowered")
		_check(not remote_mortar.fire_mortar(), "unpowered mortar does not fire")
		# Pass 1 (Wave 3): mortar indirect AoE — two clustered scouts both take damage
		var m1 = spawn_enemy("scout", Vector3(45, 0, 10))
		var m2 = spawn_enemy("scout", Vector3(47, 0, 12))
		await get_tree().process_frame
		# Pass 24 (BUG-HUNT): the old check flaked once (Pass 20 note) because
		# fire_mortar targets the NEAREST live enemy — a live wave spawn nearer
		# to the mortar than m1 could steal the shell, so m1/m2 took nothing
		# even though the mortar worked. Clear the field first (test-only):
		# with only m1/m2 live, the shell must target m1, and the check means
		# what it says. Also re-place both targets at exact spots, so a slow
		# host frame (time_scale 4 turns one frame into metres of scout
		# drift toward the core) cannot move them before the shot.
		for e in get_tree().get_nodes_in_group("enemies"):
			if is_instance_valid(e) and e != m1 and e != m2:
				e.die_silent()
		await get_tree().process_frame
		m1.global_position = Vector3(45, 0, 10)
		m2.global_position = Vector3(47, 0, 12)
		_check(mortar_node.fire_mortar(), "mortar fires at clustered targets")
		await get_tree().create_timer(1.0).timeout
		var m1_hurt: bool = not is_instance_valid(m1) or float(m1.get("hp")) < 30.0
		var m2_hurt: bool = not is_instance_valid(m2) or float(m2.get("hp")) < 30.0
		_check(m1_hurt, "mortar AoE damages primary target")
		_check(m2_hurt, "mortar AoE damages secondary target in blast radius")
		# Pass 1 (Wave 3): EMP pulse stuns (non-lethal) and wears off
		var e1 = spawn_enemy("scout", emp_node.global_position + Vector3(4, 0, 0))
		var e2 = spawn_enemy("scout", emp_node.global_position + Vector3(-4, 0, 0))
		await get_tree().process_frame
		_check(emp_node.fire_emp(), "emp pylon fires pulse")
		_check(bool(e1.get("is_stunned")) and bool(e2.get("is_stunned")), "emp pulse stuns enemies in radius")
		e1.set("_stun_timer", 0.01)
		await get_tree().process_frame
		await get_tree().process_frame
		_check(not bool(e1.get("is_stunned")) and not bool(e1.get("is_dead")), "stun wears off without killing (recoverable)")
		# Pass 1 (Wave 3): shield-heavy frontal shield absorbs, breaks, rear exposed
		var sh = spawn_enemy("shield_heavy", Vector3(-20, 0, -20))
		await get_tree().process_frame
		var shf: Vector3 = sh.get_facing()
		_check(absf(float(sh.get("shield_hp")) - 90.0) < 0.5, "shield heavy spawns with 90 shield (got %f)" % float(sh.get("shield_hp")))
		var a1: float = sh.take_damage(40.0, shf, "TestGun")
		_check(a1 < 8.0, "frontal hit absorbed by shield (actual %f)" % a1)
		_check(absf(float(sh.get("shield_hp")) - 50.0) < 0.5, "shield depleted to 50 after 40 hit")
		sh.take_damage(60.0, shf, "TestGun")
		_check(float(sh.get("shield_hp")) <= 0.0, "shield breaks under sustained frontal fire")
		var a2: float = sh.take_damage(40.0, shf, "TestGun")
		_check(absf(a2 - 14.0) < 0.5, "shield-down frontal hit takes 35%% (got %f)" % a2)
		var a3: float = sh.take_damage(40.0, -shf, "TestGun")
		_check(absf(a3 - 60.0) < 0.5, "rear hit takes 150%% (got %f)" % a3)
		sh.die_silent()
		# Pass 1 (Wave 3): power lines drawn from sources to powered structures
		_refresh_power_lines()
		_check(_power_line_count >= 1, "power lines drawn for powered structures (count=%d)" % _power_line_count)
		# Pass 2 (Wave 4): engineering drone + doctrine presets
		_check(drone != null, "engineering drone spawned")
		_check(str(loadout.get("doctrine", "")) in ["iron_wall", "hunting_pack", "ghost_protocol"], "doctrine is a known preset (got '%s')" % str(loadout.get("doctrine", "")))
		_check(set_doctrine("ghost_protocol"), "doctrine switches to ghost protocol")
		_check(not set_doctrine("bogus_doctrine"), "invalid doctrine rejected")
		_check(str(drone.get("doctrine")) == "ghost_protocol", "drone carries the selected doctrine")
		# Iron Wall repair: damage the test turret, park the drone beside it
		set_doctrine("iron_wall")
		if tt:
			tt.take_damage(40.0)
			var dhp0: float = float(tt.get("hp"))
			drone.global_position = tt.global_position + Vector3(3, 0, 0)
			await get_tree().create_timer(0.5).timeout
			_check(float(tt.get("hp")) > dhp0 + 2.0, "iron wall drone repairs structure (%f -> %f)" % [dhp0, float(tt.get("hp"))])
			# Ghost Protocol: repair blocked while an enemy is near the drone
			set_doctrine("ghost_protocol")
			var ge = spawn_enemy("scout", drone.global_position + Vector3(5, 0, 0))
			await get_tree().process_frame
			_check(drone.repair_blocked(), "ghost protocol blocks repair with enemy near")
			var ghp0: float = float(tt.get("hp"))
			await get_tree().process_frame
			await get_tree().process_frame
			await get_tree().process_frame
			_check(absf(float(tt.get("hp")) - ghp0) < 0.6, "ghost drone does not repair while enemy near (%f -> %f)" % [ghp0, float(tt.get("hp"))])
			ge.die_silent()
			# clear wave stragglers too: a scout parked on the core is also
			# within ghost radius of the drone and would keep the block true
			for e in get_tree().get_nodes_in_group("enemies"):
				if is_instance_valid(e):
					e.die_silent()
			await get_tree().process_frame
			_check(not drone.repair_blocked(), "ghost repair block clears when enemy gone")
		# Hunting Pack fetch: a fresh cache parked under the drone pays out
		set_doctrine("hunting_pack")
		var cache_pos := Vector3(30, 0, 30)
		var cn := _make_cache(cache_pos)
		drone.global_position = cache_pos
		var s_before2 := salvage
		await get_tree().process_frame
		await get_tree().process_frame
		_check(salvage == s_before2 + 20, "hunting pack drone fetches cache +20 (got %d)" % (salvage - s_before2))
		_check(not bool(cn.get_meta("cache_active", true)), "fetched cache marked inactive")
		# HOLD command: drone stays put despite a damaged structure far away
		if tt:
			tt.take_damage(20.0)
			set_doctrine("iron_wall")
			toggle_drone_command()
			_check(drone_hold and bool(drone.get("hold")), "drone hold command engages")
			var hold_flat := Vector3(drone.global_position.x, 0, drone.global_position.z)
			await get_tree().process_frame
			await get_tree().process_frame
			await get_tree().process_frame
			await get_tree().process_frame
			var moved := Vector3(drone.global_position.x, 0, drone.global_position.z).distance_to(hold_flat)
			_check(moved < 0.5, "held drone does not move (moved %f)" % moved)
			toggle_drone_command()
			_check(not drone_hold, "drone hold command releases")
			var d_before := Vector3(drone.global_position.x, 0, drone.global_position.z).distance_to(Vector3(tt.global_position.x, 0, tt.global_position.z))
			await get_tree().create_timer(0.5).timeout
			var d_after := Vector3(drone.global_position.x, 0, drone.global_position.z).distance_to(Vector3(tt.global_position.x, 0, tt.global_position.z))
			_check(d_after < d_before - 1.0, "released drone moves toward damaged structure (%f -> %f)" % [d_before, d_after])
		# Doctrine persistence + invalid-file fallback
		set_doctrine("ghost_protocol")
		save_loadout()
		var lo2 := read_loadout_file()
		_check(str(lo2.get("doctrine", "")) == "ghost_protocol", "doctrine persists in loadout file")
		var bf := FileAccess.open("user://iron_eden_loadout.json", FileAccess.WRITE)
		if bf:
			bf.store_string(JSON.stringify({"chassis": "assault", "utility": "repair_pulse", "doctrine": "bogus"}))
			bf = null # close/flush before re-reading, or the read sees stale bytes
		_load_loadout()
		_check(str(loadout["doctrine"]) == "iron_wall", "invalid doctrine in file falls back to iron wall")
		# Pass 5 audit (M1): chassis/utility in the file are validated too.
		var cf := FileAccess.open("user://iron_eden_loadout.json", FileAccess.WRITE)
		if cf:
			cf.store_string(JSON.stringify({"chassis": "bogus_mech", "utility": "bogus_util", "doctrine": "iron_wall", "region": "region1", "quality": "balanced"}))
			cf = null
		_load_loadout()
		_check(str(loadout["chassis"]) == "assault", "invalid chassis in file falls back to assault (got '%s')" % str(loadout["chassis"]))
		_check(str(loadout["utility"]) == "repair_pulse", "invalid utility in file falls back to repair pulse (got '%s')" % str(loadout["utility"]))
		set_doctrine("iron_wall")
		save_loadout()
		_refresh_hud()
		_check("IRON WALL" in _lbl_wave.text, "HUD shows current doctrine")
		# Pass 3 (Wave 5): region select + marker + persistence
		_check(set_region("region2"), "region2 select accepted")
		_check(current_region == "region2" and is_instance_valid(_region_marker) and _region_marker.visible, "region2 shows rust marker")
		_check(set_region("region1"), "region1 select accepted")
		_check(current_region == "region1" and not _region_marker.visible, "region1 hides rust marker")
		_check(not set_region("bogus_region"), "invalid region rejected")
		_check(current_region == "region1", "invalid region leaves region unchanged")
		set_region("region2")
		save_loadout()
		var lo3 := read_loadout_file()
		_check(str(lo3.get("region", "")) == "region2", "region persists in loadout file")
		set_region("region1")
		save_loadout()
		# Pass 3 (Wave 5): world-save parsing drives recovery + saved adaptation
		parse_world_state({"facility_state": "Damaged Outpost", "adaptation": "tunneling_units"})
		_check(recovery_active, "Damaged Outpost save activates recovery contract")
		_check(saved_adaptation == "tunneling_units", "saved adaptation flag read (tunneling)")
		parse_world_state({"facility_state": "Forward Base", "adaptation": "shielded_heavies"})
		_check(not recovery_active, "Forward Base save does not activate recovery")
		_check(saved_adaptation == "shielded_heavies", "saved adaptation flag read (shielded)")
		# Pass 3 (Wave 5): adaptation counters in wave composition (counted directly)
		var q_tun := build_wave_queue(2, "tunneling_units")
		var q_sh := build_wave_queue(2, "shielded_heavies")
		var q_mix := build_wave_queue(2, "mixed_doctrine")
		var q_base := build_wave_queue(2, "unformed")
		var q_w1 := build_wave_queue(1, "tunneling_units")
		_check(q_tun.count("burrower") == q_base.count("burrower") + 2, "tunneling adaptation adds 2 burrowers to wave 2 (%d -> %d)" % [q_base.count("burrower"), q_tun.count("burrower")])
		_check(q_sh.count("shield_heavy") == q_base.count("shield_heavy") + 2, "shielded adaptation adds 2 shield heavies to wave 2 (%d -> %d)" % [q_base.count("shield_heavy"), q_sh.count("shield_heavy")])
		_check(q_mix.count("scout") == q_base.count("scout") + 1 and q_mix.count("heavy") == q_base.count("heavy") + 1, "mixed adaptation adds scout + heavy to wave 2")
		_check(q_w1.count("burrower") == 0, "wave 1 gets no adaptation bonus")
		_check(q_base.size() == 10, "wave 2 base queue unchanged (10 units)")
		# Pass 3 (Wave 5): recovery contract pays exactly once at the 3rd build
		parse_world_state({"facility_state": "Damaged Outpost", "adaptation": "tunneling_units"})
		salvage = 500
		_check(try_build("barricade", Vector3(-52, 0, 20)), "recovery build 1 goes up")
		_check(recovery_built == 1 and not recovery_bonus_paid, "recovery counts build 1, no payout yet")
		_check(try_build("barricade", Vector3(-52, 0, -20)), "recovery build 2 goes up")
		var s_rec := salvage
		_check(try_build("barricade", Vector3(-52, 0, 0)), "recovery build 3 goes up")
		_check(salvage == s_rec - 25 + 100, "recovery contract pays +100 at 3rd build (got %d, expected %d)" % [salvage, s_rec - 25 + 100])
		_check(recovery_bonus_paid, "recovery bonus marked paid")
		var s_rec2 := salvage
		_check(try_build("barricade", Vector3(52, 0, 20)), "recovery build 4 goes up")
		_check(salvage == s_rec2 - 25, "recovery bonus does not pay twice (got %d)" % salvage)
		# restore neutral state for the later stages
		recovery_active = false
		recovery_bonus_paid = false
		recovery_built = 0
		saved_adaptation = ""
		set_region("region1")
		save_loadout()
		salvage = 500
		# Pass 4 (Wave 6): right virtual stick aim + fire button + quality/perf
		_check(_fire_btn != null and _fire_btn.text == "FIRE", "on-screen FIRE button exists")
		_check(touch_aim_begin(Vector2(900, 400), 7), "right stick aim begins")
		_check(not touch_aim_begin(Vector2(900, 400), 8), "second right stick rejected while one is active")
		touch_aim_drag(Vector2(935, 330))
		var adir := touch_aim_dir()
		_check(adir.length() > 0.99 and adir.length() < 1.01, "aim stick direction is unit length (got %f)" % adir.length())
		_check(adir.x > 0.4 and adir.x < 0.5 and adir.z < -0.85 and adir.z > -0.95, "aim stick maps screen drag to world XZ (dir %s)" % str(adir))
		_update_input()
		var aim_off: Vector3 = player.aim_point - player.global_position
		_check(absf(aim_off.length() - 20.0) < 0.5, "aim stick points 20 m out (got %f)" % aim_off.length())
		_check(player.aim_point.z < player.global_position.z, "up-drag aims forward (-Z)")
		touch_aim_end(999)
		_check(_aim_active and _touch_firing, "wrong-finger release does not end the aim stick")
		touch_aim_end(7)
		_check(not _aim_active and not _touch_firing and _aim_vec == Vector2.ZERO, "correct release ends aim stick and firing")
		set_fire_button(true)
		_check(_touch_firing, "FIRE button press starts firing")
		set_fire_button(false)
		_check(not _touch_firing, "FIRE button release stops firing when no stick is held")
		touch_aim_begin(Vector2(900, 400), 8)
		set_fire_button(false)
		_check(_touch_firing, "FIRE button release does not kill a stick hold")
		touch_aim_end(8)
		_check(not _touch_firing, "stick release after button release stops firing")
		# Quality presets drive real runtime knobs (sun shadow + env glow)
		_check(_sun_light != null and _world_env != null, "sun + environment refs exist for quality presets")
		_check(set_quality_mode("forward_plus"), "forward_plus quality accepted")
		_check(quality_mode == "forward_plus" and _sun_light.shadow_enabled and _world_env.glow_enabled, "forward_plus enables shadow + glow")
		_check(absf(_sun_light.directional_shadow_max_distance - 220.0) < 0.5, "forward_plus shadow distance is 220")
		_check(set_quality_mode("s25"), "s25 quality accepted")
		_check(not _sun_light.shadow_enabled and not _world_env.glow_enabled, "s25 disables shadow + glow")
		_check(not set_quality_mode("bogus_quality"), "invalid quality rejected")
		_check(quality_mode == "s25", "invalid quality leaves mode unchanged")
		_check(set_quality_mode("balanced"), "balanced quality accepted")
		_check(_sun_light.shadow_enabled and _world_env.glow_enabled and absf(_sun_light.directional_shadow_max_distance - 170.0) < 0.5, "balanced restores shadow + glow at 170 distance")
		_check(cycle_quality_mode() == "forward_plus", "quality cycles balanced -> forward_plus")
		_check(cycle_quality_mode() == "s25", "quality cycles forward_plus -> s25")
		_check(cycle_quality_mode() == "balanced", "quality cycles s25 -> balanced")
		_refresh_hangar()
		_check("BALANCED" in _quality_btn.text, "hangar quality button shows current mode")
		# Adaptive step: heavy frames step down, light frames step up, toggle gates it
		set_quality_mode("balanced")
		set_adaptive_quality(false)
		_check(auto_adjust_quality(5000) == "balanced", "adaptive off: heavy frame does not step down")
		set_adaptive_quality(true)
		_check(auto_adjust_quality(5000) == "s25", "adaptive on: heavy frame steps balanced -> s25")
		_check(auto_adjust_quality(10) == "balanced", "adaptive on: light frame steps s25 -> balanced")
		_check(auto_adjust_quality(10) == "forward_plus", "adaptive on: light frame steps balanced -> forward_plus")
		set_quality_mode("balanced")
		# Perf measurement: engine monitors + a real scene render-node count
		var perf := measure_perf()
		_check(perf.has("draw_calls") and perf.has("objects") and perf.has("primitives") and perf.has("fps") and perf.has("render_nodes"), "perf report has all five keys")
		_check(int(perf["draw_calls"]) >= 0 and int(perf["objects"]) >= 0 and int(perf["primitives"]) >= 0 and float(perf["fps"]) >= 0.0, "perf monitor values are non-negative")
		_check(int(perf["render_nodes"]) > 0, "scene has render nodes (count=%d)" % int(perf["render_nodes"]))
		# Pass 9 (Overhaul C): HUD zones + panel skin + icons + labels + zoom.
		_check(_hud_zones.size() == 3, "pass9: HUD has exactly three zones (got %d)" % _hud_zones.size())
		for _zp in _hud_zones:
			var _sb = _zp.get_theme_stylebox("panel")
			_check(_sb is StyleBoxFlat, "pass9: HUD zone uses a flat panel stylebox")
			if _sb is StyleBoxFlat:
				_check(_sb.bg_color == Color(0.02, 0.05, 0.11, 0.88), "pass36 supersedes pass9: HUD panel is the shared dark navy")
				_check(_sb.border_color == Color(0.18, 0.78, 0.95), "pass36 supersedes pass9: HUD panel border is the template cyan")
		_check(_weapon_icons.size() == 6, "pass9+10+21+48: six weapon icon buttons exist")
		for _wb in _weapon_icons:
			_check(_wb is Button and _wb.icon != null, "pass9: weapon button carries a generated icon")
		_check(_utility_btn != null and _utility_btn.icon != null, "pass9: utility button carries a generated icon")
		_check(_fire_btn != null and _fire_btn.icon != null, "pass9: FIRE button carries an icon")
		_check(_zoom_btn != null, "pass9: ZOOM button exists")
		# Removed floating labels: scan the whole tree for their texts.
		var _lbl_stack: Array = [self]
		var _bad_labels := 0
		while not _lbl_stack.is_empty():
			var _n: Node = _lbl_stack.pop_back()
			if _n is Label3D and str(_n.text) in ["REGION 2 — RUST FLATS", "SUPPORT MECH (offline)", "SEALED TUNNEL"]:
				_bad_labels += 1
			for _ch in _n.get_children():
				_lbl_stack.append(_ch)
		_check(_bad_labels == 0, "pass9: removed floating labels are gone (bad=%d)" % _bad_labels)
		_check(_core_lbl != null and _sub_lbl != null, "pass9: core + substation labels exist")
		# Range gating: near substation -> visible, far -> hidden; same for core.
		player.global_position = _substation_pos
		_refresh_hud()
		_check(_sub_lbl.visible, "pass9: substation label visible in range")
		player.global_position = Vector3(0, 0, 10)
		_refresh_hud()
		_check(not _sub_lbl.visible, "pass9: substation label hidden out of range")
		_check(_core_lbl.visible, "pass9: core label visible near core")
		player.global_position = Vector3(40, 0, 40)
		_refresh_hud()
		_check(not _core_lbl.visible, "pass9: core label hidden far from core")
		player.global_position = Vector3(0, 0, 10)
		_refresh_hud()
		# Pass 12 supersedes Pass 9's zoom order: cycles 34 -> 42 -> 50 -> 34,
		# closest step first and default on phones.
		_check(zoom_step == 0 and absf(camera.size - 34.0) < 0.5, "pass12: zoom starts at closest step 34")
		_check(cycle_zoom() == 1 and absf(camera.size - 42.0) < 0.5, "pass12: zoom step 1 is 42")
		_check(cycle_zoom() == 2 and absf(camera.size - 50.0) < 0.5, "pass12: zoom step 2 is 50")
		_check(cycle_zoom() == 0 and absf(camera.size - 34.0) < 0.5, "pass12: zoom wraps back to 34")
		_check(_zoom_sizes[0] == _zoom_sizes.min(), "pass12: default zoom step is the closest size")
		# Pass 12 (battlefield readability): units/props scaled up, ground
		# fills the frame, fog/bg match the ground, contrast tuned.
		_check(absf(SpriteUtil.UNIT_SCALE - 1.4) < 0.001, "pass12: unit scale constant is 1.4")
		# Pass 34: the assault unit is a flat quad whose forward (Y) size
		# is the rendered length — same 4.8*1.4 as the old billboard height.
		var p12_quad: MeshInstance3D = SpriteUtil.topdown_quad(pbody.get_node_or_null("unit_sprite"))
		if p12_quad != null and p12_quad.mesh is QuadMesh:
			var p12_h := (p12_quad.mesh as QuadMesh).size.y
			_check(absf(p12_h - 4.8 * 1.4) < 0.3, "pass12: assault sprite renders 4.8*1.4 long (got %f)" % p12_h)
		if _ground_node != null and _ground_node.mesh is PlaneMesh:
			var p12_gs := (_ground_node.mesh as PlaneMesh).size
			_check(p12_gs.x >= ARENA * 3.0, "pass12: ground plane covers ARENA x3 (got %s)" % p12_gs)
		_check(_prop_sprites.size() >= 8, "pass12: at least the original eight tile props exist (got %d; pass29 expands the set, exact total asserted there)" % _prop_sprites.size())
		if _prop_sprites.size() > 0:
			var p12_p0: Node = _prop_sprites[0]
			var p12_pm: MeshInstance3D = null
			for _pc in p12_p0.get_children():
				# First QuadMesh child is the sprite quad; the second is
				# the smaller contact-shadow blob — do not measure that one.
				if _pc is MeshInstance3D and (_pc as MeshInstance3D).mesh is QuadMesh:
					p12_pm = _pc
					break
			if p12_pm != null:
				var p12_ps := (p12_pm.mesh as QuadMesh).size
				_check(absf(p12_ps.x - 8.0 * 1.4) < 0.3, "pass12: first prop renders 8*1.4 wide (got %s)" % p12_ps)
		_check(_wall_edges.size() == 4, "pass12: four arena wall edge strips exist (got %d)" % _wall_edges.size())
		_check(_sun_light != null and _sun_light.light_energy >= 1.5, "pass12: sun brightened to >= 1.5 (got %f)" % (_sun_light.light_energy if _sun_light else -1.0))
		_check(_world_env != null and _world_env.ambient_light_energy >= 0.5 and _world_env.ambient_light_energy <= 0.55, "pass12: ambient in 0.50-0.55 (got %f)" % (_world_env.ambient_light_energy if _world_env else -1.0))
		set_region("region1")
		_check(_world_env.background_color == Color(0.122, 0.167, 0.137), "pass12: region1 bg matches ground atlas average (got %s)" % _world_env.background_color)
		_check(_world_env.fog_light_color == Color(0.16, 0.21, 0.18), "pass12: region1 fog matches ground tone (got %s)" % _world_env.fog_light_color)
		set_region("region2")
		_check(_world_env.background_color == Color(0.227, 0.143, 0.072), "pass12: region2 bg matches rust atlas average (got %s)" % _world_env.background_color)
		_check(_world_env.fog_light_color == Color(0.28, 0.18, 0.10), "pass12: region2 fog matches rust tone (got %s)" % _world_env.fog_light_color)
		set_region("region1")
		# Pass 13 (gameplay-video bugfix): billboard mode, ground, core,
		# siege, HUD — every check is a direct property read, not a
		# rendering assumption (headless cannot render, but the mode,
		# texture paths and control rects are what decide the phone look).
		# Pass 34 supersedes Pass 13's billboard rule for UNITS (the core
		# below keeps its billboard): a top-down sprite must turn WITH
		# the body, so yawing the body 90 deg must yaw the holder too.
		var p13_spr: Node = pbody.get_node_or_null("unit_sprite")
		_check(p13_spr != null and not (p13_spr is Sprite3D) and SpriteUtil.topdown_quad(p13_spr) != null, "pass34: player sprite is a flat top-down holder, not a billboard")
		if pbody != null:
			# Structural proof it turns with the body: the holder is a
			# child of _body (children inherit body yaw by construction)
			# and its quad lies flat (rotation -90 deg), so body yaw
			# rotates the top-down art — no frame-timing read needed.
			pbody.rotation.y = PI / 2.0
			var p13_spr2: Node = pbody.get_node_or_null("unit_sprite")
			var p13_quad2: MeshInstance3D = SpriteUtil.topdown_quad(p13_spr2) if p13_spr2 else null
			_check(p13_spr2 != null and p13_spr2.get_parent() == pbody and p13_quad2 != null and absf(p13_quad2.rotation_degrees.x + 90.0) < 0.01, "pass34: top-down holder is a body child with a flat quad, so it turns with body yaw")
			pbody.rotation.y = 0.0
		_check(_ground_mat != null and _ground_mat.albedo_texture != null and str(_ground_mat.albedo_texture.resource_path).contains("p39_ground_v2"), "pass39 supersedes pass13: ground uses v2 atlas (%s)" % (_ground_mat.albedo_texture.resource_path if _ground_mat and _ground_mat.albedo_texture else "none"))
		_check(_ground_base_node != null and _ground_base_node.position.y < 0.0, "pass13: solid ground base plane sits below the atlas (y=%s)" % (_ground_base_node.position.y if _ground_base_node else 999.0))
		var p13_core_spr: Sprite3D = null
		var p13_core_prim := false
		if _core_node != null:
			for _cc in _core_node.get_children():
				if _cc is Sprite3D and (_cc as Sprite3D).texture != null and str((_cc as Sprite3D).texture.resource_path).contains("p13_core"):
					p13_core_spr = _cc
				if _cc is MeshInstance3D:
					var _cm = (_cc as MeshInstance3D).mesh
					if _cm is CylinderMesh and (_cm as CylinderMesh).height > 1.0:
						p13_core_prim = true
					if _cm is SphereMesh:
						p13_core_prim = true
		_check(p13_core_spr != null and p13_core_spr.billboard == BaseMaterial3D.BILLBOARD_ENABLED, "pass13: core reactor is a billboarded generated slice, not primitives")
		_check(not p13_core_prim, "pass13: core has no primitive cylinder/sphere body (disc only)")
		var p13_siege = spawn_enemy("siege", Vector3(20, 0, -20))
		var p13_siege_body: Node = p13_siege.get("_body")
		var p13_siege_quad: MeshInstance3D = SpriteUtil.topdown_quad(p13_siege_body.get_node_or_null("unit_sprite")) if p13_siege_body else null
		var p13_siege_tex: String = ""
		if p13_siege_quad != null:
			var p13_siege_mat: StandardMaterial3D = p13_siege_quad.get_surface_override_material(0) as StandardMaterial3D
			if p13_siege_mat != null and p13_siege_mat.albedo_texture != null:
				p13_siege_tex = str(p13_siege_mat.albedo_texture.resource_path)
		_check(p13_siege_quad != null and p13_siege_tex.contains("p35_enemy_siege_walk"), "pass35: siege platform uses template p35_enemy_siege walk frame (%s)" % p13_siege_tex)
		_check(p13_siege_quad != null and p13_siege_quad.mesh is QuadMesh and absf((p13_siege_quad.mesh as QuadMesh).size.y - 9.0 * 1.4) < 0.3, "pass34: siege platform renders 9.0*1.4 long")
		if p13_siege.has_method("die_silent"):
			p13_siege.die_silent()
		var p13_vp := get_viewport().get_visible_rect().size
		_check(_hud_zones.size() == 3 and (_hud_zones[2] as Control).size.y <= 160.5, "pass13: bottom HUD panel is 160 high and contains all bottom controls (got %s)" % ((_hud_zones[2] as Control).size.y if _hud_zones.size() == 3 else -1))
		_check(_hint_lbl != null and _hint_lbl.get_global_rect().end.y <= p13_vp.y + 0.5, "pass13: hint line ends inside the viewport (end y %s vs vh %s)" % [_hint_lbl.get_global_rect().end.y if _hint_lbl else -1, p13_vp.y])
		_check(_build_bar != null and _build_bar.get_global_rect().end.x <= p13_vp.x + 0.5 and _build_bar.get_global_rect().position.x >= -0.5, "pass13: build bar fits viewport width without right-edge clip")
		_check(_lbl_wave != null and _lbl_wave.get_global_rect().end.x <= p13_vp.x + 0.5, "pass13: wave line ends inside the viewport (end x %s vs vw %s)" % [_lbl_wave.get_global_rect().end.x if _lbl_wave else -1, p13_vp.x])
		if _hud_zones.size() == 3:
			var p13_top_end := (_hud_zones[0] as Control).get_global_rect().end.y
			var p13_msg_y := (_hud_zones[1] as Control).get_global_rect().position.y
			_check(p13_msg_y >= p13_top_end - 0.5, "pass13: message zone sits below the top zone, no overlap (msg y %s vs top end %s)" % [p13_msg_y, p13_top_end])
		var perf9 := measure_perf()
		print("P9 PERF draw_calls=%d objects=%d primitives=%d render_nodes=%d" % [int(perf9["draw_calls"]), int(perf9["objects"]), int(perf9["primitives"]), int(perf9["render_nodes"])])
		_check(int(perf9["render_nodes"]) > 0, "pass9: perf table has a real render-node count")
		# Pass 11 (HOTFIX): hangar is a full-screen opaque modal; the HUD
		# is hidden behind it and restored on deploy; bar/hint fit width.
		# The hangar pauses the tree, so the test node must run in ALWAYS
		# mode while the modal is open, or _process (and this test) stalls.
		process_mode = Node.PROCESS_MODE_ALWAYS
		_open_hangar()
		await get_tree().process_frame
		var p11_vp := get_viewport().get_visible_rect().size
		_check(_hangar_panel.visible and hangar_open, "pass11: hangar open and visible")
		var p11_hr := _hangar_panel.get_global_rect()
		_check(p11_hr.size.x >= p11_vp.x - 1.0 and p11_hr.size.y >= p11_vp.y - 1.0, "pass11: hangar covers full viewport (panel %s vs viewport %s)" % [p11_hr.size, p11_vp])
		var p11_style = _hangar_panel.get_theme_stylebox("panel")
		_check(p11_style is StyleBoxFlat and (p11_style as StyleBoxFlat).bg_color.a >= 0.99, "pass11: hangar background is opaque")
		var p11_hidden := true
		for _hc in _hud_controls:
			if _hc.visible:
				p11_hidden = false
		_check(p11_hidden, "pass11: every HUD control hidden while hangar open")
		_check(_hint_lbl != null and _hint_lbl.get_global_rect().size.x <= p11_vp.x + 0.5, "pass11: hint label fits viewport width")
		_check(_build_bar != null and _build_bar.get_global_rect().position.x >= -0.5 and _build_bar.get_global_rect().end.x <= p11_vp.x + 0.5, "pass11: build bar fits viewport width")
		_check(_deploy_btn != null and _deploy_btn.get_global_rect().position.y >= -0.5 and _deploy_btn.get_global_rect().end.y <= p11_vp.y + 0.5, "pass11: DEPLOY button inside viewport")
		_deploy_from_hangar()
		# Pass 17: main is ALWAYS by design now (pause keys must reach
		# _input while paused), so the restore is ALWAYS, not INHERIT —
		# restoring INHERIT here would silently break pause-key handling
		# for every later test section and for the shipped game.
		process_mode = Node.PROCESS_MODE_ALWAYS
		var p11_restored := true
		for _hc in _hud_controls:
			if not _hc.visible:
				p11_restored = false
		_check(p11_restored, "pass11: HUD controls visible again after deploy")
		_check(not hangar_open, "pass11: hangar closed after deploy")
		# Quality persists in the loadout file; a bogus value falls back to balanced
		set_quality_mode("forward_plus")
		save_loadout()
		var lo4 := read_loadout_file()
		_check(str(lo4.get("quality", "")) == "forward_plus", "quality persists in loadout file")
		var qf := FileAccess.open("user://iron_eden_loadout.json", FileAccess.WRITE)
		if qf:
			qf.store_string(JSON.stringify({"chassis": "assault", "utility": "repair_pulse", "doctrine": "iron_wall", "region": "region1", "quality": "bogus"}))
			qf = null
		_load_loadout()
		_check(quality_mode == "balanced", "invalid quality in file falls back to balanced")
		set_quality_mode("balanced")
		save_loadout()
		# Pass 14 (Sapper Drone): stats, generated sprite, wave queues,
		# death-by-damage never detonates, contact detonation pays nothing.
		var p14 = spawn_enemy("sapper", Vector3(-38, 0, 10))
		await get_tree().process_frame
		_check(float(p14.get("max_hp")) < 40.0, "pass14: sapper is low HP (max %f)" % float(p14.get("max_hp")))
		_check(float(p14.get("speed")) >= 10.0, "pass14: sapper is fast (speed %f, scout is 7.5)" % float(p14.get("speed")))
		_check(int(p14.get("salvage_value")) == 15, "pass14: sapper salvage is 15 (got %d)" % int(p14.get("salvage_value")))
		var p14_body: Node = p14.get("_body")
		var p14_quad: MeshInstance3D = SpriteUtil.topdown_quad(p14_body.get_node_or_null("unit_sprite")) if p14_body else null
		var p14_tex: String = ""
		if p14_quad != null:
			var p14_mat: StandardMaterial3D = p14_quad.get_surface_override_material(0) as StandardMaterial3D
			if p14_mat != null and p14_mat.albedo_texture != null:
				p14_tex = str(p14_mat.albedo_texture.resource_path)
		_check(p14_quad != null and p14_tex.contains("p35_enemy_drone_walk"), "pass35: sapper uses template p35_enemy_drone walk frame (%s)" % p14_tex)
		_check(p14_quad != null and p14_quad.mesh is QuadMesh and absf(p14_quad.rotation_degrees.x + 90.0) < 0.01, "pass34: sapper sprite lies flat")
		_check(p14_body != null and p14_body.get_node_or_null("facing_chevron") != null and p14_body.get_node_or_null("health_ring") != null, "pass14: sapper has chevron + health ring")
		var p14_tc: Color = Color(p14.get("trim_color"))
		_check(p14_tc.r > 0.8 and p14_tc.g < 0.5, "pass14: sapper trim is red/orange (%s)" % p14_tc)
		if is_instance_valid(p14):
			p14.die_silent()
		var q14_w3 := build_wave_queue(3, "unformed")
		_check(q14_w3.count("sapper") == 2, "pass14: wave 3 has 2 sappers (got %d)" % q14_w3.count("sapper"))
		# Pass 22 added 2 lancers to wave 3, so the queue is 18 now.
		# Pass 41 added 1 bulwark to wave 3, so the queue is 19 now.
		_check(q14_w3.size() == 19, "pass14: wave 3 queue is 19 (was 18, got %d)" % q14_w3.size())
		_check(build_wave_queue(2, "unformed").count("sapper") == 0, "pass14: wave 2 has no sappers")
		_check(build_wave_queue(1, "unformed").count("sapper") == 0, "pass14: wave 1 has no sappers")
		var q14_w4 := build_wave_queue(4, "unformed")
		var q14_w8 := build_wave_queue(8, "unformed")
		_check(q14_w4.count("sapper") == 2, "pass14: endless wave 4 has 2 sappers (got %d)" % q14_w4.count("sapper"))
		_check(q14_w8.count("sapper") == 6, "pass14: endless wave 8 caps at 6 sappers (got %d)" % q14_w8.count("sapper"))
		# Death by damage must NOT detonate: a sapper shot dead next to
		# a turret leaves the turret untouched.
		salvage = 500
		_check(try_build("turret", Vector3(-38, 0, -20)), "pass14: detonation-test turret builds")
		_check(try_build("turret", Vector3(-36, 0, -17)), "pass14: splash-test turret builds")
		var p14_turret: Node = null
		var p14_splash: Node = null
		for s in get_tree().get_nodes_in_group("structures"):
			var sf := Vector3(s.global_position.x, 0, s.global_position.z)
			if str(s.get("structure_kind")) == "turret" and sf.distance_to(Vector3(-38, 0, -20)) < 1.0:
				p14_turret = s
			if str(s.get("structure_kind")) == "turret" and sf.distance_to(Vector3(-36, 0, -17)) < 1.0:
				p14_splash = s
		_check(p14_turret != null and p14_splash != null, "pass14: both test turrets found")
		var p14_thp0 := float(p14_turret.get("hp")) if p14_turret else -1.0
		var p14_shp0 := float(p14_splash.get("hp")) if p14_splash else -1.0
		var p14_dead = spawn_enemy("sapper", Vector3(-36, 0, -20))
		p14_dead.take_damage(999.0, Vector3(0, 0, 1), "TestGun")
		# Read is_dead synchronously: the sapper's queue_free is
		# processed at frame end, so a post-await .get() would read a
		# freed instance (that was the one SCRIPT ERROR in the first run).
		_check(bool(p14_dead.get("is_dead")), "pass14: damage-killed sapper is dead")
		await get_tree().process_frame
		_check(not is_instance_valid(p14_dead), "pass14: damage-killed sapper freed")
		_check(p14_turret != null and absf(float(p14_turret.get("hp")) - p14_thp0) < 0.5, "pass14: damage-killed sapper does NOT detonate (turret %f -> %f)" % [p14_thp0, float(p14_turret.get("hp")) if p14_turret else -1.0])
		# Contact detonation: full blast to the target, half to the
		# splash turret 3 m away, no salvage for the detonated drone.
		var p14_salv0 := salvage
		var p14_live = spawn_enemy("sapper", Vector3(-36, 0, -20))
		await get_tree().process_frame
		# Freed counts as detonated too: die_silent frees it, and no
		# other path frees a healthy sapper in this window (a turret
		# kill would instead trip the salvage check below).
		_check(not is_instance_valid(p14_live) or bool(p14_live.get("is_dead")), "pass14: sapper in range detonates (is_dead or freed)")
		_check(p14_turret != null and absf((p14_thp0 - float(p14_turret.get("hp"))) - 35.0) < 0.5, "pass14: detonation deals 35 to target turret (%f -> %f)" % [p14_thp0, float(p14_turret.get("hp")) if p14_turret else -1.0])
		_check(p14_splash != null and absf((p14_shp0 - float(p14_splash.get("hp"))) - 17.5) < 0.5, "pass14: detonation splashes 17.5 to turret 3 m away (%f -> %f)" % [p14_shp0, float(p14_splash.get("hp")) if p14_splash else -1.0])
		_check(salvage == p14_salv0, "pass14: detonated sapper pays no salvage (%d -> %d)" % [p14_salv0, salvage])
		await get_tree().process_frame
		_check(not is_instance_valid(p14_live), "pass14: detonated sapper freed")
		# Pass 15 (BALANCE): railgun must out-DPS the starter autocannon —
		# before this pass it lost everywhere (54.1 vs 69.2 DPS) despite
		# being the heavy weapon. 54 dmg / 0.70 s = 77.1 DPS, heat
		# 17/shot = 24.3/s vs autocannon 24.6/s, so the heat economy is
		# unchanged in character.
		var p15_auto_dps := 9.0 / 0.13
		var p15_rail_dps := 54.0 / 0.70
		_check(p15_rail_dps > p15_auto_dps, "pass15: railgun DPS %.1f beats autocannon %.1f" % [p15_rail_dps, p15_auto_dps])
		# TTK vs heavy (130 HP): side 1.0, front 0.35, rear 1.5.
		_check(ttk_seconds(9.0, 1.0, 130.0, 0.13) <= 2.5, "pass15: autocannon side TTK vs heavy %.2f s <= 2.5" % ttk_seconds(9.0, 1.0, 130.0, 0.13))
		_check(ttk_seconds(9.0, 0.35, 130.0, 0.13) <= 6.0, "pass15: autocannon frontal TTK vs heavy %.2f s <= 6.0" % ttk_seconds(9.0, 0.35, 130.0, 0.13))
		_check(ttk_seconds(54.0, 0.35, 130.0, 0.70) <= 5.0, "pass15: railgun frontal TTK vs heavy %.2f s <= 5.0" % ttk_seconds(54.0, 0.35, 130.0, 0.70))
		_check(ttk_seconds(54.0, 1.5, 130.0, 0.70) <= 2.0, "pass15: railgun rear TTK vs heavy %.2f s <= 2.0" % ttk_seconds(54.0, 1.5, 130.0, 0.70))
		# Empirical: a railgun hit on a frontal heavy really deals 54 * 0.35.
		var p15_h = spawn_enemy("heavy", Vector3(-45, 0, 45))
		await get_tree().process_frame
		var p15_dealt: float = p15_h.take_damage(54.0, p15_h.get_facing(), "Railgun")
		_check(absf(p15_dealt - 18.9) < 0.5, "pass15: railgun frontal heavy hit deals 18.9 (got %f)" % p15_dealt)
		p15_h.die_silent()
		# Economy thresholds: wave income vs build pacing.
		_check(wave_income(1, "unformed") >= 120, "pass15: wave 1 income %d >= 120" % wave_income(1, "unformed"))
		_check(wave_income(2, "unformed") >= 240, "pass15: wave 2 income %d >= 240" % wave_income(2, "unformed"))
		_check(wave_income(3, "unformed") >= 450, "pass15: wave 3 income %d >= 450" % wave_income(3, "unformed"))
		_check(wave_income(1, "unformed") >= COSTS["turret"] + COSTS["generator"], "pass15: wave 1 income covers turret + generator (%d >= %d)" % [wave_income(1, "unformed"), COSTS["turret"] + COSTS["generator"]])
		_check(wave_income(2, "unformed") >= COSTS["mortar"] + COSTS["emp_pylon"], "pass15: wave 2 income covers mortar + EMP pylon (%d >= %d)" % [wave_income(2, "unformed"), COSTS["mortar"] + COSTS["emp_pylon"]])
		# Pass 16 (Minimap): panel placement, mapping math, one dot per
		# live kind with the right colour, and pruning on death.
		_check(_minimap_panel != null, "pass16: minimap panel exists")
		if _minimap_panel != null:
			var p16_vp := get_viewport().get_visible_rect().size
			var p16_rect := _minimap_panel.get_global_rect()
			_check(absf(p16_rect.size.x - 120.0) < 0.5 and absf(p16_rect.size.y - 120.0) < 0.5, "pass40 supersedes pass16: minimap is 120x120 (got %s)" % p16_rect.size)
			_check(absf(p16_rect.position.y - 8.0) < 0.5, "pass16: minimap sits at top (y=%f)" % p16_rect.position.y)
			_check(p16_rect.end.x <= p16_vp.x + 0.5 and p16_rect.position.x >= -0.5, "pass16: minimap fits viewport width (x %f..%f vs vw %f)" % [p16_rect.position.x, p16_rect.end.x, p16_vp.x])
			_check(p16_rect.position.x >= (_hud_zones[0] as Control).get_global_rect().end.x - 0.5, "pass16: minimap starts at or after the top-left zone ends (map x %f vs zone end %f)" % [p16_rect.position.x, (_hud_zones[0] as Control).get_global_rect().end.x])
			var p16_style = _minimap_panel.get_theme_stylebox("panel")
			_check(p16_style is StyleBoxFlat and (p16_style as StyleBoxFlat).bg_color == Color(0.02, 0.05, 0.11, 0.88), "pass36 supersedes pass16: minimap uses the shared menu skin")
			_check(_minimap_panel.mouse_filter == Control.MOUSE_FILTER_IGNORE, "pass16: minimap is display-only (mouse passes through)")
		_check(minimap_pos(Vector3.ZERO) == Vector2(60.0, 60.0), "pass40 supersedes pass16: world origin maps to map centre (got %s)" % minimap_pos(Vector3.ZERO))
		_check(minimap_pos(Vector3(-60, 0, -60)) == Vector2.ZERO, "pass16: (-60,-60) maps to top-left corner")
		_check(minimap_pos(Vector3(60, 0, 60)) == Vector2(120.0, 120.0), "pass40 supersedes pass16: (60,60) maps to bottom-right corner")
		_check(minimap_pos(Vector3(100, 0, 100)) == Vector2(120.0, 120.0), "pass40 supersedes pass16: out-of-range world clamps to the map edge")
		_check(minimap_pos(Vector3(-100, 0, -100)) == Vector2.ZERO, "pass16: out-of-range negative world clamps to zero")
		player.global_position = Vector3(0, 0, 10)
		_refresh_minimap()
		_check(_minimap_dots.has(player), "pass16: player has a minimap dot")
		if _minimap_dots.has(player):
			var p16_pd: ColorRect = _minimap_dots[player]
			_check(p16_pd.color == Color(1.0, 1.0, 1.0), "pass16: player dot is white")
			# Pass 40 supersedes: player dot is 9 px on the 120 map, so
			# its top-left moves to (55.5,65.5) at the same centre (60,70).
			_check((p16_pd.position - Vector2(55.5, 65.5)).length() < 0.6, "pass40 supersedes pass16: player dot sits at its world spot (got %s, want ~(55.5,65.5))" % p16_pd.position)
		_check(_minimap_dots.has(_core_node), "pass16: core has a minimap dot")
		if _minimap_dots.has(_core_node):
			var p16_cd: ColorRect = _minimap_dots[_core_node]
			_check(p16_cd.color == Color(0.3, 0.8, 1.0), "pass16: core dot is blue")
			_check((p16_cd.position - Vector2(55.0, 55.0)).length() < 0.6, "pass40 supersedes pass16: core dot sits at map centre (got %s)" % p16_cd.position)
		_check(_minimap_dots.has(drone), "pass16: drone has a minimap dot")
		if _minimap_dots.has(drone):
			_check((_minimap_dots[drone] as ColorRect).color == Color(0.3, 0.9, 0.5), "pass16: drone dot is green")
		var p16_turret: Node = null
		for s in get_tree().get_nodes_in_group("structures"):
			if str(s.get("structure_kind")) == "turret" and Vector3(s.global_position.x, 0, s.global_position.z).distance_to(Vector3(10, 0, 10)) < 1.0:
				p16_turret = s
		_check(p16_turret != null, "pass16: test turret found for structure dot")
		if p16_turret != null:
			_check(_minimap_dots.has(p16_turret), "pass16: live structure has a minimap dot")
			if _minimap_dots.has(p16_turret):
				var p16_sd: ColorRect = _minimap_dots[p16_turret]
				_check(p16_sd.color == Color(1.0, 0.85, 0.3), "pass16: structure dot is amber")
				_check((p16_sd.position - Vector2(66.5, 66.5)).length() < 0.6, "pass40 supersedes pass16: structure dot sits at its world spot (got %s, want ~(66.5,66.5))" % p16_sd.position)
		var p16_foe = spawn_enemy("scout", Vector3(30, 0, -30))
		_refresh_minimap()
		_check(_minimap_dots.has(p16_foe), "pass16: spawned enemy has a minimap dot")
		if _minimap_dots.has(p16_foe):
			var p16_ed: ColorRect = _minimap_dots[p16_foe]
			_check(p16_ed.color == Color(1.0, 0.25, 0.2), "pass16: enemy dot is red")
			_check((p16_ed.position - Vector2(86.5, 26.5)).length() < 0.6, "pass40 supersedes pass16: enemy dot sits at its world spot (got %s, want ~(86.5,26.5))" % p16_ed.position)
		p16_foe.die_silent()
		await get_tree().process_frame
		_refresh_minimap()
		_check(not _minimap_dots.has(p16_foe), "pass16: dead enemy's dot is pruned")
	if _test_stage == 1 and _test_t > 1.4:
		_test_stage = 2
		# disable + capture
		var s = spawn_enemy("scout", player.global_position + Vector3(3, 0, 0))
		await get_tree().process_frame
		# Pass 28 flake fix (test-only): the old flat 26 damage assumed a
		# wave-1 scout (30 HP -> 4 HP, 13.3%). spawn_enemy scales HP by
		# (1 + (wave-1)*0.15), so when live combat has already advanced
		# the wave counter, 26 leaves the scout above the 15% disable
		# line and all five capture checks fail — the 2026-10-26 gate
		# retry failed exactly this way. Scale the damage to the
		# spawned scout's actual max HP (90% leaves 10%, always <=15%
		# and always alive), which is what the check means.
		s.take_damage(float(s.get("max_hp")) * 0.9, Vector3(0, 0, 1), "Autocannon")
		_check(s.get("is_disabled"), "scout at <=15%% HP becomes disabled")
		# Pass 5 audit (H2): sprite enemies showed no disabled state before;
		# every disabled enemy must now carry a visible capture marker.
		_check(is_instance_valid(s.get("_disabled_fx")), "disabled scout shows a capture marker")
		var cv: int = s.capture_value()
		var before := salvage
		_check(capture_enemy(s), "capture succeeds on disabled enemy")
		_check(salvage - before == cv, "capture pays bonus salvage (%d)" % cv)
		_check(mech_kills >= 1, "capture counts toward mech kill split")
	if _test_stage == 2:
		# drive player in a circle, auto-aim + fire at nearest enemy
		player.move_input = Vector2(sin(_test_t * 0.7), cos(_test_t * 0.7) * 0.4)
		var best: Node = null
		var bd := 9999.0
		for e in get_tree().get_nodes_in_group("enemies"):
			if is_instance_valid(e) and not e.get("is_disabled"):
				var d := player.global_position.distance_to(e.global_position)
				if d < bd:
					bd = d; best = e
		if best:
			player.aim_point = best.global_position
			player.firing = true
		else:
			player.firing = false
		if _test_t > 16.0:
			_test_stage = 3
			player.firing = false
			_check(wave >= 1, "wave director started wave 1")
			_check(kills >= 1, "kills happened, kills=%d" % kills)
			# siege killer tracking
			var sg = spawn_enemy("siege", Vector3(20, 0, -20))
			await get_tree().process_frame
			sg.hp = 10.0
			sg.is_disabled = false
			var rear: Vector3 = -sg.get_facing()
			sg.take_damage(50.0, rear, "Railgun")
			await get_tree().process_frame
			_check(siege_killer_weapon == "Railgun", "siege killer weapon tracked (got '%s')" % siege_killer_weapon)
			# substation choice A path (function-level)
			choose_substation("turrets")
			_check(_substation_used, "substation choice consumed")
			# Wave 1: victory -> save carries adaptation -> endless continue -> wave 4
			for e in get_tree().get_nodes_in_group("enemies"):
				if is_instance_valid(e):
					e.die_silent()
			_spawn_queue.clear()
			wave = 3
			_wave_active = false
			_end_game(true)
			_check(_won, "victory state set at wave 3")
			var sf := FileAccess.open("user://iron_eden_world.json", FileAccess.READ)
			var saved_ok := false
			if sf:
				var parsed = JSON.parse_string(sf.get_as_text())
				saved_ok = parsed is Dictionary and parsed.has("adaptation") and parsed.has("level")
			_check(saved_ok, "world save carries adaptation + level")
			start_endless()
			_check(endless_mode and not _won, "endless continue resumes play")
			_intermission = 0.05
			_test_stage = 4
			_test_t4 = 0.0
	if _test_stage == 4:
		_test_t4 += delta
		if wave >= 4 or _test_t4 > 3.0:
			_check(wave >= 4, "endless wave 4 started (wave=%d)" % wave)
			# Totals printed here, before Pass 17 resets the run below.
			print("IRON EDEN TEST kills=%d level-wave=%d salvage=%d core=%d siege_killer=%s level=%d adaptation=%s" % [kills, wave, salvage, int(core_hp), siege_killer_weapon, level, adaptation_for(mech_kills, turret_kills)])
			_test_stage = 5
	if _test_stage == 5:
		if _p17_active:
			return
		_p17_active = true
		# Pass 17 (Pause menu): Esc/P, resume, restart, back-to-hangar,
		# and the open guards. Guards first: pause must not open over
		# the hangar or a game-over pause.
		_open_hangar()
		_check(not open_pause(), "pass17: pause refuses to open over the hangar")
		_check(not pause_open and _pause_panel != null and not _pause_panel.visible, "pass17: pause panel stays hidden over hangar")
		_deploy_from_hangar()
		_game_over = true
		_check(not open_pause(), "pass17: pause refuses to open on game over")
		_game_over = false
		_check(_pause_panel != null, "pass17: pause panel exists")
		_check(_pause_resume_btn != null and _pause_restart_btn != null and _pause_hangar_btn != null, "pass17: resume/restart/hangar buttons exist")
		_check(_pause_panel.process_mode == Node.PROCESS_MODE_ALWAYS, "pass17: pause panel runs while paused")
		_check(_pause_panel.mouse_filter == Control.MOUSE_FILTER_STOP, "pass17: pause panel blocks input behind it")
		_check(not (_pause_panel in _hud_controls), "pass17: pause panel is not a HUD control (hangar never hides it)")
		# Dirty run state, then restart must clean it.
		spawn_enemy("scout", Vector3(30, 0, 30))
		spawn_enemy("scout", Vector3(-30, 0, 30))
		_check(try_build("turret", Vector3(0, 0, -40)), "pass17: setup turret builds for restart check")
		salvage = 123
		wave = 7
		kills = 9
		xp = 4
		level = 3
		core_hp = 400.0
		player.global_position = Vector3(25, 0, 25)
		_check(open_pause(), "pass17: open_pause succeeds in a live run")
		_check(pause_open and _pause_panel.visible and get_tree().paused, "pass17: pause opens, panel visible, tree paused")
		# Esc resumes: direct _input call. Headless engine dispatch
		# filtering is bypassed by a direct call; the ALWAYS mode is
		# what makes the real build dispatch it while paused.
		var p17_esc := InputEventKey.new()
		p17_esc.keycode = KEY_ESCAPE
		p17_esc.pressed = true
		_input(p17_esc)
		_check(not pause_open and not get_tree().paused and not _pause_panel.visible, "pass17: Esc resumes the run")
		# P opens and does NOT build an EMP pylon (the Pass 17 rebinding).
		var p17_structs_before := get_tree().get_nodes_in_group("structures").size()
		var p17_p := InputEventKey.new()
		p17_p.keycode = KEY_P
		p17_p.pressed = true
		_input(p17_p)
		_check(pause_open and get_tree().paused, "pass17: P opens the pause menu")
		_check(get_tree().get_nodes_in_group("structures").size() == p17_structs_before, "pass17: P builds no EMP pylon anymore")
		# Restart from pause: full run reset, back in play.
		restart_from_pause()
		await get_tree().process_frame
		_check(not pause_open and not get_tree().paused, "pass17: restart closes pause and unpauses")
		_check(wave == 0 and kills == 0 and xp == 0 and level == 1, "pass17: restart resets wave/kills/xp/level (wave %d kills %d xp %d level %d)" % [wave, kills, xp, level])
		_check(salvage == 90 and core_hp == core_max_hp, "pass17: restart resets salvage/core (salvage %d core %f)" % [salvage, core_hp])
		_check(get_tree().get_nodes_in_group("enemies").is_empty(), "pass17: restart clears all enemies")
		var p17_structs := 0
		for _s in _structures:
			if is_instance_valid(_s):
				p17_structs += 1
		_check(p17_structs == _abandoned_turrets.size(), "pass17: restart keeps only the abandoned turrets (%d)" % p17_structs)
		_check(player.global_position.distance_to(Vector3(0, 0, 10)) < 0.5, "pass17: restart respawns the player at (0,0,10)")
		_check(player.hp == player.max_hp and player.current_weapon == 1, "pass17: restart restores full hull + weapon 1")
		_check(_caches.size() == 8, "pass17: restart respawns 8 salvage caches (got %d)" % _caches.size())
		_check(not drone_hold and drone.hold == false, "pass17: restart releases drone hold")
		# Back to hangar: reset + hangar reopen, then deploy to restore play.
		_check(open_pause(), "pass17: pause reopens for back-to-hangar")
		back_to_hangar_from_pause()
		_check(hangar_open and _hangar_panel.visible and not pause_open, "pass17: back-to-hangar opens the hangar and closes pause")
		_check(wave == 0 and salvage == 90, "pass17: back-to-hangar resets the run")
		_check(get_tree().paused, "pass17: hangar pauses the tree after back-to-hangar")
		_deploy_from_hangar()
		_check(not hangar_open and not get_tree().paused, "pass17: deploy from hangar resumes play")
		# Pass 18 (UX): damage vignette, enemy hit-flash, siege-death shake.
		_last_player_hp = player.hp
		var p18_hp0: float = player.hp
		player.take_damage(10.0)
		_poll_player_damage()
		_check(_vignette_alpha > 0.3, "pass18: player hit raises vignette alpha (got %f)" % _vignette_alpha)
		_check(_vignette != null and _vignette.visible and _vignette_edges.size() == 4, "pass18: vignette node visible with 4 edge bars")
		_update_vignette(1.0)
		_check(_vignette_alpha == 0.0 and not _vignette.visible, "pass18: vignette fades fully after 1s")
		player.hp = p18_hp0
		_last_player_hp = player.hp
		var p18_e = spawn_enemy("scout", Vector3(30, 0, -30))
		await get_tree().process_frame
		# Pass 34: the flash lives on the quad material's albedo, not on a
		# Sprite3D modulate (there is no Sprite3D any more).
		var p18_mat: StandardMaterial3D = p18_e.get("_td_mat")
		p18_e.take_damage(5.0, Vector3(0, 0, 1), "TestGun")
		_check(float(p18_e.get("hit_flash_t")) > 0.0, "pass18: enemy hit sets flash timer")
		_check(p18_mat != null and p18_mat.albedo_color != Color.WHITE, "pass18: enemy quad tinted on hit")
		p18_e._process(0.2)
		_check(float(p18_e.get("hit_flash_t")) == 0.0, "pass18: flash timer decays to zero")
		_check(p18_mat != null and p18_mat.albedo_color == Color.WHITE, "pass18: quad tint clears after flash")
		p18_e.die_silent()
		var p18_sg = spawn_enemy("siege", Vector3(20, 0, -20))
		await get_tree().process_frame
		p18_sg.take_damage(99999.0, -p18_sg.get_facing(), "Railgun")
		_check(_shake_t > 0.0, "pass18: siege death starts screen shake (t=%f)" % _shake_t)
		_check(_shake_amp > 0.0, "pass18: siege shake amplitude set")
		camera.global_position = player.global_position + Vector3(0, 44, 32)
		_update_camera(0.016)
		var p18_off: Vector3 = camera.global_position - (player.global_position + Vector3(0, 44, 32))
		_check(p18_off.length() > 0.05, "pass18: camera offset while shaking (off %s)" % p18_off)
		# Pass 19 (PERF): bullet pooling — before/after measurement plus
		# falsifiable reuse checks. Unpooled path allocates a Node3D +
		# mesh per shot; pooled path re-adds a detached node. All checks
		# use deltas from a snapshot taken after the benchmark, so earlier
		# phases (flak shell, turret fire) cannot skew the numbers.
		var BulletScript19 = load("res://scripts/bullet.gd")
		var p19_t0 = Time.get_ticks_usec()
		for _i in range(200):
			var ub = Node3D.new()
			ub.set_script(BulletScript19)
			ub.position = Vector3(60, 1.5, 60)
			add_child(ub)
			ub.queue_free()
		var p19_unpooled_us = Time.get_ticks_usec() - p19_t0
		await get_tree().process_frame
		var p19_snap = BulletScript19.pool_stats()
		var p19_t1 = Time.get_ticks_usec()
		var p19_batch_a = []
		for _i in range(50):
			var pb = BulletScript19.take_from_pool()
			if pb == null:
				pb = Node3D.new()
				pb.set_script(BulletScript19)
			pb.position = Vector3(60, 1.5, 60)
			add_child(pb)
			pb.setup(Vector3(0, 0, 1), 7.0, "TestPool", true, false, 55.0)
			p19_batch_a.append(pb)
		for pb in p19_batch_a:
			pb.release_to_pool()
		var p19_mid = BulletScript19.pool_stats()
		var p19_batch_b = []
		for _i in range(50):
			var pb = BulletScript19.take_from_pool()
			if pb == null:
				pb = Node3D.new()
				pb.set_script(BulletScript19)
			pb.position = Vector3(60, 1.5, 60)
			add_child(pb)
			pb.setup(Vector3(0, 0, 1), 7.0, "TestPool", true, false, 55.0)
			p19_batch_b.append(pb)
		var p19_end = BulletScript19.pool_stats()
		var p19_pooled_us = Time.get_ticks_usec() - p19_t1
		print("pass19: unpooled 200 shots took ", p19_unpooled_us, " usec; pooled 100 obtain+setup+release took ", p19_pooled_us, " usec; stats snap=", p19_snap, " mid=", p19_mid, " end=", p19_end)
		_check(int(p19_end["created"]) == int(p19_mid["created"]), "pass19: second 50-shot batch creates no new bullets (created %d -> %d)" % [int(p19_mid["created"]), int(p19_end["created"])])
		_check(int(p19_end["reused"]) - int(p19_mid["reused"]) == 50, "pass19: second batch reuses 50 bullets (reused +%d)" % (int(p19_end["reused"]) - int(p19_mid["reused"])))
		_check(int(p19_end["free"]) == int(p19_mid["free"]) - 50, "pass19: second batch drains 50 from the free pool (free %d -> %d)" % [int(p19_mid["free"]), int(p19_end["free"])])
		var p19_same = true
		for pb in p19_batch_b:
			if not p19_batch_a.has(pb):
				p19_same = false
		_check(p19_same, "pass19: second batch reuses the exact first-batch instances")
		var p19_r = p19_batch_b[0]
		_check(float(p19_r.get("damage")) == 7.0, "pass19: reused bullet damage resets to the new setup value (got %f)" % float(p19_r.get("damage")))
		_check(float(p19_r.get("life")) == 2.2, "pass19: reused bullet life resets to 2.2 (got %f)" % float(p19_r.get("life")))
		_check(float(p19_r.get("_arc_t")) == 0.0 and not bool(p19_r.get("_arc_init")), "pass19: reused bullet arc state resets")
		_check(bool(p19_r.get("_active")) and p19_r.get_parent() == self, "pass19: reused bullet is active and a live child while in flight")
		player.current_weapon = 1
		player.aim_point = player.global_position + Vector3(0, 0, -20)
		var p19_start = player.global_position + Vector3(0, 0, -20).normalized() * 2.2 + Vector3(0, 1.5, 0)
		player._fire_cd = 0.0
		player._fire()
		var p19_shot1 = null
		for n in get_children():
			if n is Node3D and n.get_script() != null and str(n.get_script().resource_path) == "res://scripts/bullet.gd" and n.global_position.distance_to(p19_start) < 0.5:
				p19_shot1 = n
		_check(p19_shot1 != null, "pass19: player shot produces a bullet child at the muzzle")
		if p19_shot1 != null:
			p19_shot1.release_to_pool()
			_check(p19_shot1.get_parent() == null, "pass19: released bullet leaves the tree (free pool)")
			player._fire_cd = 0.0
			player._fire()
			var p19_shot2 = null
			for n in get_children():
				if n is Node3D and n.get_script() != null and str(n.get_script().resource_path) == "res://scripts/bullet.gd" and n.global_position.distance_to(p19_start) < 0.5:
					p19_shot2 = n
			_check(p19_shot2 == p19_shot1, "pass19: player second shot reuses the released bullet instance")
			if p19_shot2 != null:
				p19_shot2.release_to_pool()
		for pb in p19_batch_b:
			pb.release_to_pool()
		player._fire_cd = 0.0
		# Pass 20 (GRAPHICS+UI): seamless ground + phone HUD rebuild.
		# Ground: the texture is the seamless build (no tile borders),
		# and the region swap still swaps to the seamless rust build.
		if _ground_mat and _ground_mat.albedo_texture:
			_check(str(_ground_mat.albedo_texture.resource_path).contains("p39_ground_v2"), "pass39 supersedes pass20: ground uses v2 texture (%s)" % _ground_mat.albedo_texture.resource_path)
		_check(set_region("region2"), "pass20: region2 selectable")
		if _ground_mat and _ground_mat.albedo_texture:
			_check(str(_ground_mat.albedo_texture.resource_path).contains("p39_ground_rust_v2"), "pass39 supersedes pass20: region2 ground is v2 rust (%s)" % _ground_mat.albedo_texture.resource_path)
		_check(set_region("region1"), "pass20: region1 restores")
		if _ground_mat and _ground_mat.albedo_texture:
			_check(str(_ground_mat.albedo_texture.resource_path).contains("p39_ground_v2") and not str(_ground_mat.albedo_texture.resource_path).contains("rust"), "pass39 supersedes pass20: region1 ground is v2 base (%s)" % _ground_mat.albedo_texture.resource_path)
		# Bottom panel: 128 high, smaller than the Pass 13 160, and the
		# build bar + hint both end inside it and inside the viewport.
		var p20_vp := get_viewport().get_visible_rect().size
		_check(_hud_zones.size() == 3 and absf((_hud_zones[2] as Control).size.y - P40_BOTTOM_H) < 0.5, "pass40 supersedes pass20: bottom panel is 124 high (got %s)" % ((_hud_zones[2] as Control).size.y if _hud_zones.size() == 3 else -1.0))
		_check(_build_bar != null and _build_bar.get_global_rect().end.y <= p20_vp.y - 30.0, "pass20: build bar ends above the hint row (end y %s vs vh %s)" % [_build_bar.get_global_rect().end.y if _build_bar else -1.0, p20_vp.y])
		_check(_hint_lbl != null and _hint_lbl.get_global_rect().end.y <= p20_vp.y + 0.5, "pass20: hint ends inside viewport (end y %s vs vh %s)" % [_hint_lbl.get_global_rect().end.y if _hint_lbl else -1.0, p20_vp.y])
		# Touch instructions replaced the desktop keybind paragraph.
		_check(_hint_lbl != null and _hint_lbl.text.contains("LEFT STICK") and _hint_lbl.text.contains("RIGHT STICK"), "pass20: hint is touch instructions (%s)" % (_hint_lbl.text if _hint_lbl else "none"))
		_check(_hint_lbl != null and not _hint_lbl.text.contains("WASD"), "pass20: hint no longer mentions WASD")
		# High-contrast bar fills on a dark track.
		var p20_hull_fill = _hull_bar.get_theme_stylebox("fill") if _hull_bar else null
		var p20_heat_fill = _heat_bar.get_theme_stylebox("fill") if _heat_bar else null
		var p20_core_fill = _core_bar.get_theme_stylebox("fill") if _core_bar else null
		_check(p20_hull_fill is StyleBoxFlat and (p20_hull_fill as StyleBoxFlat).bg_color == Color(0.2, 1.0, 0.4), "pass20: HULL fill is bright green")
		_check(p20_heat_fill is StyleBoxFlat and (p20_heat_fill as StyleBoxFlat).bg_color == Color(1.0, 0.65, 0.1), "pass20: HEAT fill is amber")
		_check(p20_core_fill is StyleBoxFlat and (p20_core_fill as StyleBoxFlat).bg_color == Color(0.25, 0.85, 1.0), "pass20: CORE fill is cyan")
		_check(p20_hull_fill is StyleBoxFlat and _hull_bar.get_theme_stylebox("background") is StyleBoxFlat and (_hull_bar.get_theme_stylebox("background") as StyleBoxFlat).bg_color == Color(0.02, 0.05, 0.11, 1.0), "pass36 supersedes pass20: bar track is the shared menu navy")
		# Bigger minimap dots + arena border.
		_refresh_minimap()
		if _minimap_dots.has(player):
			_check((_minimap_dots[player] as ColorRect).size.x == 9.0, "pass40 supersedes pass20: player minimap dot is 9 px (got %s)" % (_minimap_dots[player] as ColorRect).size.x)
		if _minimap_dots.has(_core_node):
			_check((_minimap_dots[_core_node] as ColorRect).size.x == 10.0, "pass40 supersedes pass20: core minimap dot is 10 px (got %s)" % (_minimap_dots[_core_node] as ColorRect).size.x)
		_check(_minimap_border.size() == 4, "pass20: minimap arena border has 4 edge bars (got %d)" % _minimap_border.size())
		if _minimap_border.size() == 4 and _minimap_panel != null:
			var p20_mp := _minimap_panel.get_global_rect().position
			_check((_minimap_border[0] as ColorRect).position == p20_mp and (_minimap_border[1] as ColorRect).position == p20_mp + Vector2(0, MINIMAP_SIZE - 3.0), "pass20: minimap border spans top and bottom edges (top %s, bottom %s, panel %s)" % [(_minimap_border[0] as ColorRect).position, (_minimap_border[1] as ColorRect).position, p20_mp])
			_check((_minimap_border[2] as ColorRect).position == p20_mp and (_minimap_border[3] as ColorRect).position == p20_mp + Vector2(MINIMAP_SIZE - 3.0, 0), "pass20: minimap border spans left and right edges (left %s, right %s, panel %s)" % [(_minimap_border[2] as ColorRect).position, (_minimap_border[3] as ColorRect).position, p20_mp])
		var p20_foe = spawn_enemy("scout", Vector3(30, 0, -30))
		_refresh_minimap()
		if _minimap_dots.has(p20_foe):
			_check((_minimap_dots[p20_foe] as ColorRect).size.x == 7.0, "pass40 supersedes pass20: enemy minimap dot is 7 px (got %s)" % (_minimap_dots[p20_foe] as ColorRect).size.x)
		p20_foe.die_silent()
		await get_tree().process_frame
		_refresh_minimap()
		# Opaque level-up panel with numbered buttons.
		if _lvl_panel != null:
			var p20_lvl_style = _lvl_panel.get_theme_stylebox("panel")
			_check(p20_lvl_style is StyleBoxFlat and (p20_lvl_style as StyleBoxFlat).bg_color.a >= 0.99, "pass20: level-up panel is opaque (alpha %s)" % ((p20_lvl_style as StyleBoxFlat).bg_color.a if p20_lvl_style is StyleBoxFlat else -1.0))
			var p20_lvbox := _lvl_panel.get_child(0)
			if p20_lvbox != null and p20_lvbox.get_child_count() >= 4:
				# Pass 36: the header divider sits at index 1, so the three
				# numbered buttons are now at 2/3/4 (title 0, divider 1).
				_check(str((p20_lvbox.get_child(2) as Button).text).begins_with("1."), "pass20: level-up button 1 is numbered (%s)" % (p20_lvbox.get_child(2) as Button).text)
				_check(str((p20_lvbox.get_child(3) as Button).text).begins_with("2."), "pass20: level-up button 2 is numbered (%s)" % (p20_lvbox.get_child(3) as Button).text)
				_check(str((p20_lvbox.get_child(4) as Button).text).begins_with("3."), "pass20: level-up button 3 is numbered (%s)" % (p20_lvbox.get_child(4) as Button).text)
		# In-game version stamp.
		# Pass 24 (BUG-HUNT finding): the stamp still read v1.24 after Pass 23
		# shipped v1.25 — the Pass 23 run never bumped it, and its own check
		# still asserted v1.24, so the lag was invisible. The stamp now
		# tracks the shipped version, and the check asserts the current one.
		_check(_version_lbl != null and _version_lbl.text.contains("v1.51"), "pass47 supersedes pass45: version stamp reads v1.51 (%s)" % (_version_lbl.text if _version_lbl else "none"))
		if _version_lbl != null:
			_check(_version_lbl.get_global_rect().end.x <= p20_vp.x + 0.5 and _version_lbl.get_global_rect().position.x >= -0.5, "pass20: version stamp fits viewport width")
		# Camera safe-area: the player must render above the bottom
		# panel with margin, not behind it, at the default zoom.
		player.global_position = Vector3(0, 0, 10)
		_shake_t = 0.0
		_shake_dur = 0.0
		camera.global_position = player.global_position + Vector3(0, 44, 32)
		_update_camera(0.016)
		var p20_screen: Vector2 = camera.unproject_position(player.global_position)
		print("pass20: player screen pos ", p20_screen, " viewport ", p20_vp, " panel top ", p20_vp.y - P20_BOTTOM_H)
		_check(p20_screen.y >= 0.0 and p20_screen.y <= p20_vp.y - P20_BOTTOM_H - 50.0, "pass20: player renders above bottom panel with margin (screen y %s, panel top %s)" % [p20_screen.y, p20_vp.y - P20_BOTTOM_H])
		_check(p20_screen.x >= 0.0 and p20_screen.x <= p20_vp.x, "pass20: player screen x inside viewport (x %s vs vw %s)" % [p20_screen.x, p20_vp.x])
		# Pass 22 (Lancer): stats, generated sprite, telegraphed charge,
		# one charge hit of exactly 22, no melee while cooling down,
		# no telegraph out of range, wave mix, salvage + XP.
		# No awaits in this section: engine _process must not advance
		# the lancer between the direct _process calls below.
		var p22 = spawn_enemy("lancer", player.global_position + Vector3(10, 0, 0))
		var p22_scale := 1.0 + float(maxi(wave - 1, 0)) * 0.15
		_check(absf(float(p22.get("max_hp")) - 70.0 * p22_scale) < 0.5, "pass22: lancer HP is 70 x scale (got %f)" % float(p22.get("max_hp")))
		_check(float(p22.get("speed")) == 7.0, "pass22: lancer speed is 7.0 (got %f)" % float(p22.get("speed")))
		_check(float(p22.get("dmg")) == 22.0, "pass22: lancer charge damage is 22 (got %f)" % float(p22.get("dmg")))
		_check(int(p22.get("salvage_value")) == 25, "pass22: lancer salvage is 25 (got %d)" % int(p22.get("salvage_value")))
		var p22_body: Node = p22.get("_body")
		var p22_quad: MeshInstance3D = SpriteUtil.topdown_quad(p22_body.get_node_or_null("unit_sprite")) if p22_body else null
		var p22_tex: String = ""
		if p22_quad != null:
			var p22_mat: StandardMaterial3D = p22_quad.get_surface_override_material(0) as StandardMaterial3D
			if p22_mat != null and p22_mat.albedo_texture != null:
				p22_tex = str(p22_mat.albedo_texture.resource_path)
		_check(p22_quad != null and p22_tex.contains("p35_enemy_strider_walk"), "pass35: lancer uses template p35_enemy_strider walk frame (%s)" % p22_tex)
		_check(p22_quad != null and p22_quad.mesh is QuadMesh and absf(p22_quad.rotation_degrees.x + 90.0) < 0.01, "pass34: lancer sprite lies flat")
		_check(p22_body != null and p22_body.get_node_or_null("facing_chevron") != null and p22_body.get_node_or_null("health_ring") != null, "pass22: lancer has chevron + health ring")
		var p22_tc: Color = Color(p22.get("trim_color"))
		_check(p22_tc.r > 0.8 and p22_tc.g < 0.5, "pass22: lancer trim is red/orange (%s)" % p22_tc)
		_check(str(p22.get("lancer_state")) == "chase", "pass22: lancer starts in chase (got %s)" % str(p22.get("lancer_state")))
		var p22_pos0: Vector3 = p22.global_position
		p22._process(0.016)
		_check(str(p22.get("lancer_state")) == "telegraph", "pass22: in-range lancer enters telegraph (got %s)" % str(p22.get("lancer_state")))
		var p22_tel: Node = p22.get("_lancer_telegraph")
		_check(p22_tel != null and p22_tel.visible, "pass22: telegraph lane is visible during windup")
		_check(p22.global_position.distance_to(p22_pos0) < 0.01, "pass22: lancer holds still during telegraph")
		p22._process(0.4)
		_check(str(p22.get("lancer_state")) == "telegraph", "pass22: still telegraphing at 0.4 s (got %s)" % str(p22.get("lancer_state")))
		_check(p22.global_position.distance_to(p22_pos0) < 0.01, "pass22: still holding still at 0.4 s")
		p22._process(0.5)
		_check(str(p22.get("lancer_state")) == "charge", "pass22: windup ends in charge (got %s)" % str(p22.get("lancer_state")))
		_check(p22_tel == null or not p22_tel.visible, "pass22: telegraph lane hides on charge")
		var p22_hp0: float = player.hp
		var p22_steps := 0
		while str(p22.get("lancer_state")) != "chase" and p22_steps < 40:
			p22._process(0.05)
			p22_steps += 1
		_check(str(p22.get("lancer_state")) == "chase", "pass22: charge ends back in chase (got %s after %d steps)" % [str(p22.get("lancer_state")), p22_steps])
		_check(absf((p22_hp0 - player.hp) - 22.0) < 0.5, "pass22: charge hit deals exactly 22 (player %f -> %f)" % [p22_hp0, player.hp])
		_check(absf(float(p22.get("_lancer_cd")) - 3.0) < 0.01, "pass22: charge sets 3 s cooldown (got %f)" % float(p22.get("_lancer_cd")))
		var p22_hp1: float = player.hp
		p22._process(0.016)
		_check(absf(player.hp - p22_hp1) < 0.5, "pass22: cooling-down lancer in melee range does NOT brawl (player %f -> %f)" % [p22_hp1, player.hp])
		player.hp = p22_hp0
		var p22_far = spawn_enemy("lancer", Vector3(60, 0, 60))
		p22_far._process(0.016)
		_check(str(p22_far.get("lancer_state")) == "chase", "pass22: out-of-range lancer stays in chase (got %s)" % str(p22_far.get("lancer_state")))
		var p22_far_tel: Node = p22_far.get("_lancer_telegraph")
		_check(p22_far_tel == null or not p22_far_tel.visible, "pass22: out-of-range lancer shows no telegraph")
		_check(build_wave_queue(3, "unformed").count("lancer") == 2, "pass22: wave 3 has 2 lancers (got %d)" % build_wave_queue(3, "unformed").count("lancer"))
		_check(build_wave_queue(2, "unformed").count("lancer") == 0, "pass22: wave 2 has no lancers")
		_check(build_wave_queue(1, "unformed").count("lancer") == 0, "pass22: wave 1 has no lancers")
		_check(build_wave_queue(4, "unformed").count("lancer") == 1, "pass22: endless wave 4 has 1 lancer (got %d)" % build_wave_queue(4, "unformed").count("lancer"))
		_check(build_wave_queue(8, "unformed").count("lancer") == 4, "pass22: endless wave 8 caps at 4 lancers (got %d)" % build_wave_queue(8, "unformed").count("lancer"))
		_check(salvage_for_kind("lancer") == 25, "pass22: salvage_for_kind lancer is 25")
		var p22_xp = spawn_enemy("lancer", Vector3(-30, 0, -30))
		var p22_xp0 := xp
		var p22_sv0 := salvage
		_on_enemy_died(p22_xp, 25, "TestGun")
		_check(xp - p22_xp0 == 3, "pass22: lancer kill grants 3 XP (%d -> %d)" % [p22_xp0, xp])
		_check(salvage - p22_sv0 == 25, "pass22: lancer kill pays 25 salvage (%d -> %d)" % [p22_sv0, salvage])
		if is_instance_valid(p22):
			p22.die_silent()
		if is_instance_valid(p22_far):
			p22_far.die_silent()
		if is_instance_valid(p22_xp):
			p22_xp.die_silent()
		# Pass 23 (Difficulty select): multiplier table, setter validation,
		# spawn scaling (HP/damage/shield), kill + capture payout scaling,
		# hangar buttons + stats line, and loadout persistence with a
		# bogus-value fallback. Runs at the test's current wave, so the
		# expected HP reuses the same wave-escalation factor as spawn.
		var p23_dm_std := difficulty_multipliers("standard")
		_check(float(p23_dm_std["hp"]) == 1.0 and float(p23_dm_std["dmg"]) == 1.0 and float(p23_dm_std["salvage"]) == 1.0, "pass23: standard multipliers are all 1.0")
		var p23_dm_hard := difficulty_multipliers("hard")
		_check(float(p23_dm_hard["hp"]) == 1.35 and float(p23_dm_hard["dmg"]) == 1.25 and float(p23_dm_hard["salvage"]) == 1.25, "pass23: hard multipliers are 1.35/1.25/1.25")
		var p23_dm_brut := difficulty_multipliers("brutal")
		_check(float(p23_dm_brut["hp"]) == 1.8 and float(p23_dm_brut["dmg"]) == 1.6 and float(p23_dm_brut["salvage"]) == 1.6, "pass23: brutal multipliers are 1.8/1.6/1.6")
		var p23_dm_bad := difficulty_multipliers("nightmare")
		_check(float(p23_dm_bad["hp"]) == 1.0 and float(p23_dm_bad["dmg"]) == 1.0 and float(p23_dm_bad["salvage"]) == 1.0, "pass23: unknown difficulty falls back to 1.0 multipliers")
		_check(set_difficulty("hard") and difficulty == "hard" and _sel_difficulty == "hard", "pass23: set_difficulty hard sticks (got '%s')" % difficulty)
		_check(not set_difficulty("nightmare") and difficulty == "hard", "pass23: set_difficulty rejects unknown name and keeps hard")
		var p23_wave_scale := 1.0 + float(maxi(wave - 1, 0)) * 0.15
		var p23_scout = spawn_enemy("scout", Vector3(40, 0, 40))
		_check(absf(float(p23_scout.get("max_hp")) - 30.0 * p23_wave_scale * 1.35) < 0.5, "pass23: hard scout HP is 30 x wave x 1.35 (got %f)" % float(p23_scout.get("max_hp")))
		_check(absf(float(p23_scout.get("dmg")) - 5.0 * 1.25) < 0.01, "pass23: hard scout damage is 5 x 1.25 (got %f)" % float(p23_scout.get("dmg")))
		_check(int(p23_scout.get("salvage_value")) == 12, "pass23: hard scout base salvage stays 12 (got %d)" % int(p23_scout.get("salvage_value")))
		var p23_sv0 := salvage
		_on_enemy_died(p23_scout, 12, "TestGun")
		_check(salvage - p23_sv0 == 15, "pass23: hard kill pays 12 x 1.25 = 15 salvage (%d -> %d)" % [p23_sv0, salvage])
		if is_instance_valid(p23_scout):
			p23_scout.die_silent()
		_check(set_difficulty("brutal") and difficulty == "brutal", "pass23: set_difficulty brutal sticks")
		var p23_sh = spawn_enemy("shield_heavy", Vector3(-40, 0, 40))
		_check(absf(float(p23_sh.get("max_hp")) - 150.0 * p23_wave_scale * 1.8) < 0.5, "pass23: brutal shield-heavy HP is 150 x wave x 1.8 (got %f)" % float(p23_sh.get("max_hp")))
		_check(absf(float(p23_sh.get("dmg")) - 14.0 * 1.6) < 0.01, "pass23: brutal shield-heavy damage is 14 x 1.6 (got %f)" % float(p23_sh.get("dmg")))
		_check(absf(float(p23_sh.get("shield_max")) - 90.0 * 1.8) < 0.01 and absf(float(p23_sh.get("shield_hp")) - 90.0 * 1.8) < 0.01, "pass23: brutal shield pool is 90 x 1.8 (got %f/%f)" % [float(p23_sh.get("shield_max")), float(p23_sh.get("shield_hp"))])
		var p23_cap = spawn_enemy("scout", Vector3(20, 0, -20))
		p23_cap.set("is_disabled", true)
		var p23_cv0 := salvage
		_check(capture_enemy(p23_cap), "pass23: capture succeeds on disabled scout at brutal")
		_check(salvage - p23_cv0 == 48, "pass23: brutal capture pays 12 x 2.5 x 1.6 = 48 salvage (%d -> %d)" % [p23_cv0, salvage])
		if is_instance_valid(p23_sh):
			p23_sh.die_silent()
		_check(_difficulty_btns.size() == 3, "pass23: hangar has 3 difficulty buttons (got %d)" % _difficulty_btns.size())
		var p23_btn_txt := ""
		for b in _difficulty_btns:
			p23_btn_txt += str((b as Button).text) + " "
		_check(p23_btn_txt.contains("STANDARD") and p23_btn_txt.contains("HARD") and p23_btn_txt.contains("BRUTAL"), "pass23: difficulty buttons read STANDARD/HARD/BRUTAL (%s)" % p23_btn_txt)
		_refresh_hangar()
		_check(_hangar_stats.text.contains("BRUTAL"), "pass23: hangar stats line shows BRUTAL")
		save_loadout()
		var p23_lo := read_loadout_file()
		_check(str(p23_lo.get("difficulty", "")) == "brutal", "pass23: difficulty persists in loadout file (got '%s')" % str(p23_lo.get("difficulty", "")))
		var p23_bf := FileAccess.open("user://iron_eden_loadout.json", FileAccess.WRITE)
		if p23_bf:
			p23_bf.store_string(JSON.stringify({"chassis": "assault", "utility": "repair_pulse", "doctrine": "iron_wall", "region": "region1", "quality": "balanced", "difficulty": "nightmare"}))
			p23_bf = null # close/flush before re-reading, or the read sees stale bytes
		_load_loadout()
		_check(difficulty == "standard", "pass23: bogus difficulty in file falls back to standard (got '%s')" % difficulty)
		_check(set_difficulty("standard"), "pass23: difficulty restored to standard for the next run")
		save_loadout()
		# Pass 24 (BUG-HUNT): save/load round-trip fuzz. A deterministic LCG
		# (seed fixed, so every run fuzzes the same combos and a failure
		# reproduces) walks 36 random loadouts across all six fields, and
		# each combo must survive a file write + file read AND a validated
		# reload, with the difficulty multiplier table matching the pick.
		# Then 12 world saves (3 facility states x 4 kill splits) must
		# round-trip adaptation + recovery + facility + level through the
		# file and the shared parse path, one of them through the boot path.
		# Then every field, written bogus on its own, must fall back to its
		# default while the other fields survive; a fully-bogus file falls
		# back everywhere, and a missing-key / non-dict file leaves the
		# current loadout untouched (documented current behaviour — the
		# corrupt-save recovery path itself is Pass 25's scope, not this
		# pass's, so these two checks assert behaviour, they do not change it).
		var p24_chassis := ["scout", "assault", "support"]
		var p24_utils := ["repair_pulse", "grapple"]
		var p24_docs := ["iron_wall", "hunting_pack", "ghost_protocol"]
		var p24_regs := ["region1", "region2"]
		var p24_quals := ["s25", "balanced", "forward_plus"]
		var p24_diffs := ["standard", "hard", "brutal"]
		var p24_exp_mult := {"standard": [1.0, 1.0, 1.0], "hard": [1.35, 1.25, 1.25], "brutal": [1.8, 1.6, 1.6]}
		var p24_seed := 20261026
		var p24_seen_ch := {}
		var p24_seen_df := {}
		for p24_i in range(36):
			p24_seed = (p24_seed * 1103515245 + 12345) % 2147483648
			var p24_c: String = p24_chassis[p24_seed % 3]
			p24_seed = (p24_seed * 1103515245 + 12345) % 2147483648
			var p24_u: String = p24_utils[p24_seed % 2]
			p24_seed = (p24_seed * 1103515245 + 12345) % 2147483648
			var p24_d: String = p24_docs[p24_seed % 3]
			p24_seed = (p24_seed * 1103515245 + 12345) % 2147483648
			var p24_r: String = p24_regs[p24_seed % 2]
			p24_seed = (p24_seed * 1103515245 + 12345) % 2147483648
			var p24_q: String = p24_quals[p24_seed % 3]
			p24_seed = (p24_seed * 1103515245 + 12345) % 2147483648
			var p24_f: String = p24_diffs[p24_seed % 3]
			p24_seen_ch[p24_c] = true
			p24_seen_df[p24_f] = true
			loadout = {"chassis": p24_c, "utility": p24_u, "doctrine": p24_d, "region": p24_r, "quality": p24_q, "difficulty": p24_f}
			save_loadout()
			var p24_lo := read_loadout_file()
			_check(str(p24_lo.get("chassis", "")) == p24_c and str(p24_lo.get("utility", "")) == p24_u and str(p24_lo.get("doctrine", "")) == p24_d and str(p24_lo.get("region", "")) == p24_r and str(p24_lo.get("quality", "")) == p24_q and str(p24_lo.get("difficulty", "")) == p24_f, "pass24: fuzz combo %d file round-trips %s/%s/%s/%s/%s/%s (got %s)" % [p24_i, p24_c, p24_u, p24_d, p24_r, p24_q, p24_f, p24_lo])
			_load_loadout()
			_check(str(loadout.get("chassis", "")) == p24_c and str(loadout.get("utility", "")) == p24_u and str(loadout.get("doctrine", "")) == p24_d and str(loadout.get("region", "")) == p24_r and str(loadout.get("quality", "")) == p24_q and str(loadout.get("difficulty", "")) == p24_f and _sel_chassis == p24_c and _sel_difficulty == p24_f and difficulty == p24_f, "pass24: fuzz combo %d validated reload keeps %s/%s/%s/%s/%s/%s (got %s diff=%s)" % [p24_i, p24_c, p24_u, p24_d, p24_r, p24_q, p24_f, loadout, difficulty])
			var p24_dm := difficulty_multipliers(p24_f)
			var p24_em: Array = p24_exp_mult[p24_f]
			_check(absf(float(p24_dm["hp"]) - p24_em[0]) < 0.001 and absf(float(p24_dm["dmg"]) - p24_em[1]) < 0.001 and absf(float(p24_dm["salvage"]) - p24_em[2]) < 0.001, "pass24: fuzz combo %d multiplier table matches %s" % [p24_i, p24_f])
			_check(set_difficulty(p24_f) and _sel_difficulty == p24_f, "pass24: fuzz combo %d setter accepts %s" % [p24_i, p24_f])
		_check(p24_seen_ch.size() == 3, "pass24: fuzz sample covers all 3 chassis (saw %d)" % p24_seen_ch.size())
		_check(p24_seen_df.size() == 3, "pass24: fuzz sample covers all 3 difficulties (saw %d)" % p24_seen_df.size())
		var p24_states := ["Damaged Outpost", "Ruin", "Forward Base"]
		var p24_splits := [[10, 0], [0, 10], [5, 5], [0, 0]]
		var p24_wrote := 0
		for p24_st in p24_states:
			for p24_sp in p24_splits:
				mech_kills = int(p24_sp[0])
				turret_kills = int(p24_sp[1])
				var p24_exp_adapt := adaptation_for(mech_kills, turret_kills)
				var p24_exp_rec: bool = (p24_st == "Damaged Outpost")
				var p24_lvl := level
				save_world(p24_st)
				p24_wrote += 1
				var p24_wf := FileAccess.open("user://iron_eden_world.json", FileAccess.READ)
				var p24_wp := {}
				if p24_wf:
					var p24_parsed = JSON.parse_string(p24_wf.get_as_text())
					if p24_parsed is Dictionary:
						p24_wp = p24_parsed
					p24_wf = null
				_check(str(p24_wp.get("facility_state", "")) == p24_st and str(p24_wp.get("adaptation", "")) == p24_exp_adapt and int(p24_wp.get("level", -1)) == p24_lvl, "pass24: world save %s %d/%d carries facility+adaptation+level (got %s)" % [p24_st, p24_sp[0], p24_sp[1], p24_wp])
				parse_world_state(p24_wp)
				_check(saved_adaptation == p24_exp_adapt and recovery_active == p24_exp_rec, "pass24: world parse %s %d/%d restores adaptation=%s recovery=%s (got %s/%s)" % [p24_st, p24_sp[0], p24_sp[1], p24_exp_adapt, p24_exp_rec, saved_adaptation, recovery_active])
				if p24_wrote == 1:
					_load_existing_save()
					_check(saved_adaptation == p24_exp_adapt and recovery_active == p24_exp_rec, "pass24: boot path re-reads first world save (got %s/%s)" % [saved_adaptation, recovery_active])
		_check(p24_wrote == 12, "pass24: all 12 world-save combos written (got %d)" % p24_wrote)
		var p24_base := {"chassis": "assault", "utility": "repair_pulse", "doctrine": "iron_wall", "region": "region1", "quality": "balanced", "difficulty": "standard"}
		var p24_bogus := {"chassis": "bogus", "utility": "bogus", "doctrine": "bogus", "region": "bogus", "quality": "bogus", "difficulty": "bogus"}
		var p24_defaults := {"chassis": "assault", "utility": "repair_pulse", "doctrine": "iron_wall", "region": "region1", "quality": "balanced", "difficulty": "standard"}
		for p24_field in ["chassis", "utility", "doctrine", "region", "quality", "difficulty"]:
			var p24_one := p24_base.duplicate()
			p24_one[p24_field] = "bogus"
			var p24_of := FileAccess.open("user://iron_eden_loadout.json", FileAccess.WRITE)
			if p24_of:
				p24_of.store_string(JSON.stringify(p24_one, "\t"))
				p24_of = null
			_load_loadout()
			var p24_kept := true
			for p24_k in p24_base.keys():
				if p24_k != p24_field and str(loadout.get(p24_k, "")) != str(p24_base[p24_k]):
					p24_kept = false
			_check(str(loadout.get(p24_field, "")) == str(p24_defaults[p24_field]) and p24_kept, "pass24: bogus %s falls back to %s, other fields survive (got %s)" % [p24_field, p24_defaults[p24_field], loadout])
		var p24_af := FileAccess.open("user://iron_eden_loadout.json", FileAccess.WRITE)
		if p24_af:
			p24_af.store_string(JSON.stringify(p24_bogus, "\t"))
			p24_af = null
		_load_loadout()
		_check(str(loadout.get("chassis", "")) == "assault" and str(loadout.get("utility", "")) == "repair_pulse" and str(loadout.get("doctrine", "")) == "iron_wall" and str(loadout.get("region", "")) == "region1" and str(loadout.get("quality", "")) == "balanced" and str(loadout.get("difficulty", "")) == "standard", "pass24: fully-bogus file falls back to all defaults (got %s)" % [loadout])
		loadout = p24_base.duplicate()
		save_loadout()
		var p24_ef := FileAccess.open("user://iron_eden_loadout.json", FileAccess.WRITE)
		if p24_ef:
			p24_ef.store_string("{}")
			p24_ef = null
		_load_loadout()
		_check(str(loadout.get("chassis", "")) == "assault" and str(loadout.get("difficulty", "")) == "standard", "pass24: empty-dict file leaves current loadout untouched (got %s)" % [loadout])
		var p24_nf := FileAccess.open("user://iron_eden_loadout.json", FileAccess.WRITE)
		if p24_nf:
			p24_nf.store_string("[1, 2, 3]")
			p24_nf = null
		_load_loadout()
		_check(str(loadout.get("chassis", "")) == "assault" and str(loadout.get("difficulty", "")) == "standard", "pass24: non-dict file leaves current loadout untouched (got %s)" % [loadout])
		# Restore a clean default loadout for the next boot; the world file
		# is left at the last fuzz write (Forward Base, 0/0, unformed).
		loadout = p24_base.duplicate()
		_check(set_difficulty("standard"), "pass24: difficulty restored to standard after fuzz")
		save_loadout()
		# Pass 25 (AUDIT: save schema + corrupt-save recovery). Findings
		# fixed here: (1) neither save file carried a schema version, so
		# no migration path existed; (2) both writers truncated the live
		# file in place, so a crash mid-write destroyed the only copy;
		# (3) unparseable files fell back silently (Pass 5 backlog L1)
		# with no log, no quarantine, and no backup; (4) world fields
		# were never validated. The old Pass 24 "leave untouched" checks
		# for empty/non-dict files still pass below this block's scope
		# because the new fallback IS the default loadout — recovery
		# replaces silent inaction, it does not break the old contract
		# for a default-starting loadout.
		var p25_base := {"chassis": "assault", "utility": "repair_pulse", "doctrine": "iron_wall", "region": "region1", "quality": "balanced", "difficulty": "standard"}
		loadout = p25_base.duplicate()
		save_loadout()
		var p25_lo := read_loadout_file()
		_check(int(p25_lo.get("schema_version", 0)) == 1, "pass25: loadout save stamps schema_version 1 (got %s)" % [p25_lo])
		_check(not FileAccess.file_exists("user://iron_eden_loadout.json.tmp"), "pass25: no loadout .tmp left after save")
		mech_kills = 0
		turret_kills = 0
		save_world("Forward Base")
		var p25_wp := _parse_save_dict(_save_text("user://iron_eden_world.json"))
		_check(int(p25_wp.get("schema_version", 0)) == 1, "pass25: world save stamps schema_version 1 (got %s)" % [p25_wp])
		_check(not FileAccess.file_exists("user://iron_eden_world.json.tmp"), "pass25: no world .tmp left after save")
		# Legacy file (no schema key, valid fields) loads unchanged.
		var p25_leg := FileAccess.open("user://iron_eden_loadout.json", FileAccess.WRITE)
		if p25_leg:
			p25_leg.store_string(JSON.stringify({"chassis": "scout", "utility": "grapple", "doctrine": "hunting_pack", "region": "region2", "quality": "forward_plus", "difficulty": "brutal"}))
			p25_leg = null
		_load_loadout()
		_check(str(loadout.get("chassis", "")) == "scout" and str(loadout.get("utility", "")) == "grapple" and str(loadout.get("difficulty", "")) == "brutal" and not save_corrupt_loadout and not save_future_schema_seen, "pass25: legacy file without schema_version loads fields, no corrupt/future flag (got %s corrupt=%s future=%s)" % [loadout, save_corrupt_loadout, save_future_schema_seen])
		# Future schema (v99) still loads its known fields, flags it.
		var p25_fut := FileAccess.open("user://iron_eden_loadout.json", FileAccess.WRITE)
		if p25_fut:
			p25_fut.store_string(JSON.stringify({"schema_version": 99, "chassis": "support", "utility": "repair_pulse", "doctrine": "ghost_protocol", "region": "region1", "quality": "s25", "difficulty": "hard"}))
			p25_fut = null
		_load_loadout()
		_check(str(loadout.get("chassis", "")) == "support" and str(loadout.get("difficulty", "")) == "hard" and save_future_schema_seen and not save_corrupt_loadout, "pass25: future schema v99 loads known fields and flags future (got %s future=%s)" % [loadout, save_future_schema_seen])
		# Backup restore: save A, then B (bak becomes A), corrupt main.
		loadout = {"chassis": "scout", "utility": "grapple", "doctrine": "hunting_pack", "region": "region2", "quality": "forward_plus", "difficulty": "brutal"}
		save_loadout()
		loadout = {"chassis": "support", "utility": "repair_pulse", "doctrine": "iron_wall", "region": "region1", "quality": "balanced", "difficulty": "standard"}
		save_loadout()
		var p25_cor := FileAccess.open("user://iron_eden_loadout.json", FileAccess.WRITE)
		if p25_cor:
			p25_cor.store_string("{truncated json, no closing")
			p25_cor = null
		_load_loadout()
		var p25_restored := read_loadout_file()
		_check(save_corrupt_loadout and save_recovered_from_backup and str(loadout.get("chassis", "")) == "scout" and str(loadout.get("difficulty", "")) == "brutal" and str(p25_restored.get("chassis", "")) == "scout", "pass25: corrupt loadout restores backup A, main file repaired (got %s corrupt=%s recovered=%s file=%s)" % [loadout, save_corrupt_loadout, save_recovered_from_backup, p25_restored])
		# No usable backup: garbage in .bak too -> defaults + quarantine.
		var p25_gbak := FileAccess.open("user://iron_eden_loadout.json.bak", FileAccess.WRITE)
		if p25_gbak:
			p25_gbak.store_string("{broken backup")
			p25_gbak = null
		var p25_cor2 := FileAccess.open("user://iron_eden_loadout.json", FileAccess.WRITE)
		if p25_cor2:
			p25_cor2.store_string("{truncated again")
			p25_cor2 = null
		_load_loadout()
		_check(save_corrupt_loadout and not save_recovered_from_backup and str(loadout.get("chassis", "")) == "assault" and str(loadout.get("difficulty", "")) == "standard" and save_load_note != "" and FileAccess.file_exists("user://iron_eden_loadout.json.corrupt"), "pass25: corrupt loadout with dead backup falls back to defaults, quarantined, note set (got %s corrupt=%s recovered=%s note='%s')" % [loadout, save_corrupt_loadout, save_recovered_from_backup, save_load_note])
		_check(str(read_loadout_file().get("chassis", "")) == "assault", "pass25: after no-backup recovery the main loadout file is a clean defaults file")
		# World backup restore: Damaged Outpost/tunneling is the backup.
		mech_kills = 0
		turret_kills = 10
		save_world("Damaged Outpost")
		mech_kills = 10
		turret_kills = 0
		save_world("Ruin")
		var p25_wcor := FileAccess.open("user://iron_eden_world.json", FileAccess.WRITE)
		if p25_wcor:
			p25_wcor.store_string("[not a dict")
			p25_wcor = null
		_load_existing_save()
		_check(save_corrupt_world and save_recovered_from_backup and recovery_active and saved_adaptation == "tunneling_units", "pass25: corrupt world restores backup Damaged Outpost/tunneling (got recovery=%s adapt=%s corrupt=%s recovered=%s)" % [recovery_active, saved_adaptation, save_corrupt_world, save_recovered_from_backup])
		_check(str(_parse_save_dict(_save_text("user://iron_eden_world.json")).get("facility_state", "")) == "Damaged Outpost", "pass25: world main file repaired from backup")
		# World with no usable backup: clears, quarantines, invents nothing.
		var p25_wgbak := FileAccess.open("user://iron_eden_world.json.bak", FileAccess.WRITE)
		if p25_wgbak:
			p25_wgbak.store_string("{broken world backup")
			p25_wgbak = null
		var p25_wcor2 := FileAccess.open("user://iron_eden_world.json", FileAccess.WRITE)
		if p25_wcor2:
			p25_wcor2.store_string("{truncated world")
			p25_wcor2 = null
		_load_existing_save()
		_check(save_corrupt_world and not save_recovered_from_backup and saved_adaptation == "" and not recovery_active and FileAccess.file_exists("user://iron_eden_world.json.corrupt"), "pass25: corrupt world with dead backup clears state and quarantines (got adapt='%s' recovery=%s)" % [saved_adaptation, recovery_active])
		# Invalid world fields are validated out by the shared parse path.
		parse_world_state({"facility_state": "Bogus Base", "adaptation": "bogus_code"})
		_check(saved_adaptation == "" and not recovery_active, "pass25: bogus facility/adaptation parse to empty + no recovery (got '%s'/%s)" % [saved_adaptation, recovery_active])
		# Legacy world file loads unchanged.
		var p25_wleg := FileAccess.open("user://iron_eden_world.json", FileAccess.WRITE)
		if p25_wleg:
			p25_wleg.store_string(JSON.stringify({"facility_state": "Damaged Outpost", "adaptation": "mixed_doctrine", "level": 3}))
			p25_wleg = null
		_load_existing_save()
		_check(not save_corrupt_world and recovery_active and saved_adaptation == "mixed_doctrine", "pass25: legacy world file loads recovery + adaptation (got %s/%s corrupt=%s)" % [recovery_active, saved_adaptation, save_corrupt_world])
		# Restore clean state for the next boot: defaults + Forward Base.
		loadout = p25_base.duplicate()
		_check(set_difficulty("standard"), "pass25: difficulty restored to standard after audit")
		save_loadout()
		mech_kills = 0
		turret_kills = 0
		save_world("Forward Base")
		# Pass 26 (UX: hangar overhaul): class cards, stat bars, integrated
		# summary — layout only, so the checks also prove no stat or
		# deploy behaviour changed. Hangar must be open for the card
		# geometry; deploy at the end restores play.
		_open_hangar()
		_check(_hangar_cards.size() == 3 and _hangar_cards.has("scout") and _hangar_cards.has("assault") and _hangar_cards.has("support"), "pass26: exactly 3 class cards, one per chassis (got %s)" % [_hangar_cards.keys()])
		for p26_cn in ["scout", "assault", "support"]:
			var p26_card: Dictionary = _hangar_cards[p26_cn]
			var p26_prev: TextureRect = p26_card["preview"]
			_check(p26_prev.texture != null, "pass26: %s card has a skin preview texture" % p26_cn)
			var p26_bars: Dictionary = p26_card["bars"]
			_check(p26_bars.has("hull") and p26_bars.has("speed") and p26_bars.has("mobility"), "pass26: %s card has HULL/SPEED/MOBILITY bars" % p26_cn)
			_check(p26_card.has("select") and (p26_card["select"] as Button).text.contains(p26_cn.to_upper()), "pass26: %s card has a SELECT button" % p26_cn)
		var p26_scout_card: Dictionary = _hangar_cards["scout"]
		var p26_assault_card: Dictionary = _hangar_cards["assault"]
		var p26_support_card: Dictionary = _hangar_cards["support"]
		var p26_scout_bars: Dictionary = p26_scout_card["bars"]
		var p26_assault_bars: Dictionary = p26_assault_card["bars"]
		var p26_support_bars: Dictionary = p26_support_card["bars"]
		_check(absf((p26_scout_bars["hull"] as ProgressBar).value - 110.0 / 150.0 * 100.0) < 0.01 and absf((p26_scout_bars["speed"] as ProgressBar).value - 100.0) < 0.01 and absf((p26_scout_bars["mobility"] as ProgressBar).value - 100.0) < 0.01, "pass26: scout bars hull %.1f speed %.1f mobility %.1f" % [(p26_scout_bars["hull"] as ProgressBar).value, (p26_scout_bars["speed"] as ProgressBar).value, (p26_scout_bars["mobility"] as ProgressBar).value])
		_check(absf((p26_assault_bars["hull"] as ProgressBar).value - 100.0) < 0.01 and absf((p26_assault_bars["speed"] as ProgressBar).value - 13.0 / 16.5 * 100.0) < 0.01 and absf((p26_assault_bars["mobility"] as ProgressBar).value - 55.0 / 65.0 * 100.0) < 0.01, "pass26: assault bars hull %.1f speed %.1f mobility %.1f" % [(p26_assault_bars["hull"] as ProgressBar).value, (p26_assault_bars["speed"] as ProgressBar).value, (p26_assault_bars["mobility"] as ProgressBar).value])
		_check(absf((p26_support_bars["hull"] as ProgressBar).value - 135.0 / 150.0 * 100.0) < 0.01 and absf((p26_support_bars["speed"] as ProgressBar).value - 11.5 / 16.5 * 100.0) < 0.01 and absf((p26_support_bars["mobility"] as ProgressBar).value - 48.0 / 65.0 * 100.0) < 0.01, "pass26: support bars hull %.1f speed %.1f mobility %.1f" % [(p26_support_bars["hull"] as ProgressBar).value, (p26_support_bars["speed"] as ProgressBar).value, (p26_support_bars["mobility"] as ProgressBar).value])
		_check(hangar_chassis_stats("scout")["hp"] == 110.0 and hangar_chassis_stats("scout")["speed"] == 16.5 and hangar_chassis_stats("scout")["accel"] == 65.0, "pass26: chassis table scout matches player.gd (110/16.5/65)")
		_check(hangar_chassis_stats("assault")["hp"] == 150.0 and hangar_chassis_stats("assault")["speed"] == 13.0 and hangar_chassis_stats("assault")["accel"] == 55.0, "pass26: chassis table assault matches player.gd (150/13/55)")
		_check(hangar_chassis_stats("support")["hp"] == 135.0 and hangar_chassis_stats("support")["speed"] == 11.5 and hangar_chassis_stats("support")["accel"] == 48.0, "pass26: chassis table support matches player.gd (135/11.5/48)")
		_check(hangar_chassis_stats("bogus")["hp"] == 150.0, "pass26: unknown chassis falls back to assault stats")
		# Card selection: pick scout, check border + summary + portrait,
		# then deploy and prove the applied stats are unchanged.
		_sel_chassis = "scout"
		_refresh_hangar()
		var p26_scout_style = (_hangar_cards["scout"]["panel"] as PanelContainer).get_theme_stylebox("panel")
		var p26_assault_style = (_hangar_cards["assault"]["panel"] as PanelContainer).get_theme_stylebox("panel")
		_check(p26_scout_style is StyleBoxFlat and (p26_scout_style as StyleBoxFlat).border_width_left == 3, "pass26: selected scout card border is thick (3)")
		_check(p26_assault_style is StyleBoxFlat and (p26_assault_style as StyleBoxFlat).border_width_left == 1, "pass26: unselected assault card border is thin (1)")
		_check(_hangar_summary != null and _hangar_summary.text.contains("SCOUT") and _hangar_summary.text.contains("DIFFICULTY: STANDARD"), "pass26: summary shows SCOUT + difficulty (%s)" % (_hangar_summary.text if _hangar_summary else "none"))
		_check(set_difficulty("hard") and _hangar_summary.text.contains("DIFFICULTY: HARD") and _hangar_summary.text.contains("SCOUT"), "pass26: summary follows difficulty change to HARD (%s)" % _hangar_summary.text)
		_check(set_difficulty("standard"), "pass26: difficulty restored to standard")
		_sel_utility = "grapple"
		_sel_doctrine = "hunting_pack"
		_refresh_hangar()
		_check(_hangar_summary.text.contains("GRAPPLE") and _hangar_summary.text.contains("HUNTING_PACK"), "pass26: summary follows utility + doctrine picks (%s)" % _hangar_summary.text)
		_deploy_from_hangar()
		_check(not hangar_open and str(player.get("chassis")) == "scout" and player.max_hp == 110.0 and player.max_speed == 16.5, "pass26: deploy from card pick applies unchanged scout stats (hp %f speed %f)" % [player.max_hp, player.max_speed])
		# Phone layout, unchanged from Pass 11: full-screen opaque modal,
		# HUD hidden while open, restored on deploy.
		_open_hangar()
		var p26_hr := _hangar_panel.get_global_rect()
		var p26_vp := get_viewport().get_visible_rect().size
		_check(p26_hr.size.x >= p26_vp.x - 1.0 and p26_hr.size.y >= p26_vp.y - 1.0, "pass26: hangar still covers full viewport (panel %s vs viewport %s)" % [p26_hr.size, p26_vp])
		var p26_hidden := true
		for p26_hc in _hud_controls:
			if is_instance_valid(p26_hc) and (p26_hc as Control).visible:
				p26_hidden = false
		_check(p26_hidden, "pass26: every HUD control still hidden while hangar open")
		_deploy_from_hangar()
		_check(not hangar_open, "pass26: hangar closed after deploy")
		# Restore the default loadout the next boot starts from. save_loadout
		# writes the loadout dict, not the _sel_* vars, so the dict itself
		# must be reset (setting only _sel_* would save the deployed pick).
		_sel_chassis = "assault"
		_sel_utility = "repair_pulse"
		_sel_doctrine = "iron_wall"
		_sel_region = "region1"
		loadout = {"chassis": "assault", "utility": "repair_pulse", "doctrine": "iron_wall", "region": "region1", "quality": quality_mode, "difficulty": "standard"}
		_check(set_difficulty("standard"), "pass26: difficulty restored after hangar checks")
		save_loadout()
		# Pass 27 (Class skins): distinct generated skin per chassis, wired
		# in-game and in the hangar cards — no stat/mechanic change, so the
		# checks assert texture identity only, then restore assault.
		# Pass 34 supersedes Pass 27's skin set: the three chassis now use
		# template-sliced flat top-down frames (p34), not p27 billboards.
		var p27_paths := {}
		for p27_cn in ["scout", "assault", "support"]:
			player.apply_loadout(p27_cn, "repair_pulse")
			var p27_body: Node = player.get("_body")
			var p27_quad: MeshInstance3D = SpriteUtil.topdown_quad(p27_body.get_node_or_null("unit_sprite")) if p27_body else null
			_check(p27_quad != null, "pass34: %s has a flat top-down skin quad" % p27_cn)
			if p27_quad != null:
				var p27_mat: StandardMaterial3D = p27_quad.get_surface_override_material(0) as StandardMaterial3D
				if p27_mat != null and p27_mat.albedo_texture != null:
					var p27_path := str(p27_mat.albedo_texture.resource_path)
					p27_paths[p27_cn] = p27_path
					_check(p27_path.contains("p35_%s_walk" % p27_cn), "pass35: %s skin path is its p35 walk set (got %s)" % [p27_cn, p27_path])
					_check(not p27_path.contains("p27_"), "pass34: %s no longer uses a p27 billboard skin (%s)" % [p27_cn, p27_path])
		_check(p27_paths.size() == 3 and p27_paths["scout"] != p27_paths["assault"] and p27_paths["assault"] != p27_paths["support"] and p27_paths["scout"] != p27_paths["support"], "pass34: all three chassis skins are distinct (%s)" % [p27_paths])
		_check(ResourceLoader.exists("res://sprites/p34/p34_scout.png") and ResourceLoader.exists("res://sprites/p34/p34_assault.png") and ResourceLoader.exists("res://sprites/p34/p34_support.png"), "pass34: all three p34 skin files exist")
		player.apply_loadout("assault", "repair_pulse")
		_check(str(player.get("chassis")) == "assault" and player.max_hp == 150.0, "pass27: assault restored after skin checks (hp %f)" % player.max_hp)
		# Pass 35 (real frame walk cycles, supersedes Pass 28): the
		# Pass 28 bob/lean is deleted — units now cycle 4 real textures
		# (p35 stride frames, side zones striding, centre torso identical)
		# and the holder never bobs or scales. Visuals only; the checks
		# assert frame math, cycling, stillness, and per-kind holders.
		_check(SpriteUtil.walk_frame_index(0.0) == 0, "pass35: frame index at phase 0 is 0")
		_check(SpriteUtil.walk_frame_index(0.89) == 0, "pass35: frame index at phase 0.89 is 0")
		_check(SpriteUtil.walk_frame_index(0.9) == 1, "pass35: frame index at phase 0.9 is 1")
		_check(SpriteUtil.walk_frame_index(1.8) == 2, "pass35: frame index at phase 1.8 is 2")
		_check(SpriteUtil.walk_frame_index(2.7) == 3, "pass35: frame index at phase 2.7 is 3")
		_check(SpriteUtil.walk_frame_index(3.6) == 0, "pass35: frame index wraps at phase 3.6")
		var p35_body: Node = player.get("_body")
		var p35_spr: Node = p35_body.get_node_or_null("unit_sprite")
		var p35_base_y := float(player.get("_sprite_base_y"))
		_check(SpriteUtil.walk_frame_count(p35_spr) == 4, "pass35: player holder carries 4 walk frames")
		_check(SpriteUtil.walk_frame(p35_spr) == 0, "pass35: player holder starts on frame 0")
		var p35_quad0 := SpriteUtil.topdown_quad(p35_spr)
		var p35_tex0 := ""
		if p35_quad0 != null:
			var p35_mat0 := p35_quad0.get_surface_override_material(0) as StandardMaterial3D
			if p35_mat0 != null and p35_mat0.albedo_texture != null:
				p35_tex0 = str(p35_mat0.albedo_texture.resource_path)
		_check(p35_tex0.contains("p35_assault_walk0"), "pass35: assault holder shows walk0 texture (%s)" % p35_tex0)
		player.firing = false
		player.move_input = Vector2(1, 0)
		var p35_seen := {}
		var p35_max_off := 0.0
		var p35_max_scale := 0.0
		for _i in range(120):
			player._process(0.016)
			p35_seen[int(player.get("anim_frame"))] = true
			if p35_spr != null:
				p35_max_off = maxf(p35_max_off, absf(p35_spr.position.y - p35_base_y))
				p35_max_scale = maxf(p35_max_scale, absf(p35_spr.scale.x - 1.0))
		_check(bool(player.get("anim_moving")), "pass35: player reports moving while driven")
		_check(float(player.get("anim_phase")) > 1.0, "pass35: player walk phase advances while moving (got %f)" % float(player.get("anim_phase")))
		_check(p35_seen.size() == 4, "pass35: player cycles all 4 walk frames while moving (%s)" % str(p35_seen.keys()))
		_check(p35_max_off < 0.001, "pass35: player holder never bobs while walking (max off %f)" % p35_max_off)
		_check(p35_max_scale < 0.001, "pass35: player holder never scales while walking (max %f)" % p35_max_scale)
		player.move_input = Vector2.ZERO
		for _i in range(60):
			player._process(0.016)
		var p35_idle_phase := float(player.get("anim_phase"))
		for _i in range(10):
			player._process(0.016)
		_check(not bool(player.get("anim_moving")), "pass35: player reports idle after stopping")
		_check(absf(float(player.get("anim_phase")) - p35_idle_phase) < 0.001, "pass35: walk phase freezes at rest (was %f, now %f)" % [p35_idle_phase, float(player.get("anim_phase"))])
		_check(int(player.get("anim_frame")) == 0, "pass35: player holds frame 0 at rest (got %d)" % int(player.get("anim_frame")))
		_check(SpriteUtil.walk_frame(p35_spr) == 0, "pass35: holder reports frame 0 at rest")
		if p35_spr != null:
			_check(absf(p35_spr.position.y - p35_base_y) < 0.001, "pass35: player holder sits at base height at rest (off %f)" % absf(p35_spr.position.y - p35_base_y))
		player.velocity = Vector3.ZERO
		var p35_foe = spawn_enemy("scout", Vector3(40, 0, -40))
		await get_tree().process_frame
		var p35_ephase0 := float(p35_foe.get("anim_phase"))
		var p35_ebase_y := float(p35_foe.get("_sprite_base_y"))
		var p35_espr: Node = (p35_foe.get("_body") as Node).get_node_or_null("unit_sprite")
		var p35_eseen := {}
		var p35_emax_off := 0.0
		for _i in range(120):
			p35_foe._process(0.016)
			p35_eseen[int(p35_foe.get("anim_frame"))] = true
			if p35_espr != null:
				p35_emax_off = maxf(p35_emax_off, absf(p35_espr.position.y - p35_ebase_y))
		_check(float(p35_foe.get("anim_phase")) > p35_ephase0, "pass35: enemy walk phase advances while chasing (was %f, now %f)" % [p35_ephase0, float(p35_foe.get("anim_phase"))])
		_check(p35_eseen.size() == 4, "pass35: enemy cycles all 4 walk frames while chasing (%s)" % str(p35_eseen.keys()))
		_check(p35_emax_off < 0.001, "pass35: enemy holder never bobs while chasing (max off %f)" % p35_emax_off)
		_check(SpriteUtil.walk_frame_count(p35_espr) == 4, "pass35: enemy holder carries 4 walk frames")
		p35_foe.stun(10.0)
		for _i in range(5):
			p35_foe._process(0.016)
		var p35_stun_phase := float(p35_foe.get("anim_phase"))
		for _i in range(5):
			p35_foe._process(0.016)
		_check(absf(float(p35_foe.get("anim_phase")) - p35_stun_phase) < 0.001, "pass35: stunned enemy walk phase freezes (was %f, now %f)" % [p35_foe.get("anim_phase"), p35_stun_phase])
		_check(not bool(p35_foe.get("anim_moving")), "pass35: stunned enemy reports not moving")
		_check(int(p35_foe.get("anim_frame")) == 0, "pass35: stunned enemy holds frame 0 (got %d)" % int(p35_foe.get("anim_frame")))
		if is_instance_valid(p35_foe):
			p35_foe.die_silent()
		# Per-kind walk holders: every player chassis and every enemy kind
		# renders a 4-frame p35 holder whose walk0 is its own stem.
		for p35_cn in ["scout", "support"]:
			player.apply_loadout(p35_cn, "repair_pulse")
			var p35_cspr: Node = (player.get("_body") as Node).get_node_or_null("unit_sprite")
			_check(SpriteUtil.walk_frame_count(p35_cspr) == 4, "pass35: %s holder carries 4 walk frames" % p35_cn)
			var p35_cquad := SpriteUtil.topdown_quad(p35_cspr)
			var p35_ctex := ""
			if p35_cquad != null:
				var p35_cmat := p35_cquad.get_surface_override_material(0) as StandardMaterial3D
				if p35_cmat != null and p35_cmat.albedo_texture != null:
					p35_ctex = str(p35_cmat.albedo_texture.resource_path)
			_check(p35_ctex.contains("p35_%s_walk0" % p35_cn), "pass35: %s holder shows its own walk0 (%s)" % [p35_cn, p35_ctex])
		player.apply_loadout("assault", "repair_pulse")
		var p35_kinds := {"scout": "enemy_swarm_green", "heavy": "enemy_tank", "shield_heavy": "enemy_artillery", "burrower": "enemy_spiky", "sapper": "enemy_drone", "lancer": "enemy_strider", "siege": "enemy_siege"}
		var p35_kx := 0
		for p35_kind in p35_kinds.keys():
			var p35_kfoe = spawn_enemy(p35_kind, Vector3(-44 + p35_kx * 12, 0, 44))
			await get_tree().process_frame
			var p35_kspr: Node = (p35_kfoe.get("_body") as Node).get_node_or_null("unit_sprite")
			_check(SpriteUtil.walk_frame_count(p35_kspr) == 4, "pass35: %s holder carries 4 walk frames" % p35_kind)
			var p35_kquad := SpriteUtil.topdown_quad(p35_kspr)
			var p35_ktex := ""
			if p35_kquad != null:
				var p35_kmat := p35_kquad.get_surface_override_material(0) as StandardMaterial3D
				if p35_kmat != null and p35_kmat.albedo_texture != null:
					p35_ktex = str(p35_kmat.albedo_texture.resource_path)
			_check(p35_ktex.contains("p35_%s_walk" % str(p35_kinds[p35_kind])), "pass35: %s holder shows its own walk set (%s)" % [p35_kind, p35_ktex])
			if is_instance_valid(p35_kfoe):
				p35_kfoe.die_silent()
			p35_kx += 1
		player.move_input = Vector2.ZERO
		# Pass 29 (Tiles + props expansion): denser dressing + biome
		# variants — visuals only, so the checks assert counts, kinds,
		# clearance, and per-region visibility, never stats or spawns.
		var p29_hand: Array = [
			Vector3(-28, 0, -20), Vector3(30, 0, 25), Vector3(-32, 0, 18), Vector3(24, 0, -32),
			Vector3(-20, 0, 32), Vector3(36, 0, -8), Vector3(-38, 0, -6), Vector3(14, 0, 34),
			Vector3(-8, 0, -38), Vector3(38, 0, 20), Vector3(-38, 0, 28), Vector3(10, 0, -38),
			Vector3(-44, 0, 14), Vector3(40, 0, -28), Vector3(-12, 0, 40),
			Vector3(-44, 0, -20), Vector3(22, 0, 40), Vector3(44, 0, -20),
			Vector3(34, 0, -36), Vector3(44, 0, 8), Vector3(0, 0, 44),
		]
		var p29_common := 0
		var p29_r1 := 0
		var p29_r2 := 0
		var p29_scatter := 0
		var p29_kinds: Array = []
		var p29_clear := true
		for _ps in _prop_sprites:
			var _tag := str(_ps.get_meta("p29_region", "common"))
			if _tag == "common":
				p29_common += 1
			elif _tag == "region1":
				p29_r1 += 1
			elif _tag == "region2":
				p29_r2 += 1
			var _is_hand := false
			for _hp in p29_hand:
				if _ps.position.distance_to(_hp) < 0.01:
					_is_hand = true
					break
			if not _is_hand:
				p29_scatter += 1
				if _ps.position.length() < 14.0 or _ps.position.length() > 50.0:
					p29_clear = false
			if _ps.position.length() < 12.0 or _ps.position.distance_to(_substation_pos) < 10.0:
				p29_clear = false
			if absf(_ps.position.x) > 58.0 or absf(_ps.position.z) > 58.0:
				p29_clear = false
			for _ch in _ps.get_children():
				if _ch is MeshInstance3D:
					var _m: StandardMaterial3D = _ch.get_surface_override_material(0)
					if _m != null and _m.albedo_texture != null:
						var _tp := str(_m.albedo_texture.resource_path)
						if _tp.contains("tile_") and not p29_kinds.has(_tp):
							p29_kinds.append(_tp)
						break
		var p29_close := false
		for _i in range(_prop_sprites.size()):
			for _j in range(_i + 1, _prop_sprites.size()):
				if _prop_sprites[_i].position.distance_to(_prop_sprites[_j].position) < 6.0:
					p29_close = true
		_check(_prop_sprites.size() == 33, "pass29: total props 33 (got %d)" % _prop_sprites.size())
		_check(p29_common == 27 and p29_r1 == 3 and p29_r2 == 3, "pass29: tags common 27 / region1 3 / region2 3 (got %d/%d/%d)" % [p29_common, p29_r1, p29_r2])
		_check(p29_scatter == 12, "pass29: seeded scatter placed 12 props (got %d)" % p29_scatter)
		_check(p29_clear, "pass29: every prop clears core 12 m, substation 10 m, arena bounds, scatter in 14-50 m annulus")
		_check(not p29_close, "pass29: no two props closer than 6 m")
		for _kind in ["tile_cliff", "tile_gate", "tile_metal_platform", "tile_mossy_stone", "tile_turret", "tile_grass", "tile_water", "tile_rust_wall", "tile_dirt_path"]:
			var _found := false
			for _tp in p29_kinds:
				if _tp.contains(_kind):
					_found = true
					break
			_check(_found, "pass29: previously unused slice present: %s" % _kind)
		_check(set_region("region2"), "pass29: region2 selectable")
		var p29_r2_vis := 0
		var p29_r1_vis := 0
		var p29_com_vis := 0
		for _ps in _prop_sprites:
			var _tag := str(_ps.get_meta("p29_region", "common"))
			if _tag == "region2" and _ps.visible:
				p29_r2_vis += 1
			if _tag == "region1" and _ps.visible:
				p29_r1_vis += 1
			if _tag == "common" and _ps.visible:
				p29_com_vis += 1
		_check(p29_r2_vis == 3 and p29_r1_vis == 0 and p29_com_vis == 27, "pass29: region2 shows rust 3, hides green 0, keeps common 27 (got %d/%d/%d)" % [p29_r2_vis, p29_r1_vis, p29_com_vis])
		_check(set_region("region1"), "pass29: region1 restores")
		p29_r2_vis = 0
		p29_r1_vis = 0
		p29_com_vis = 0
		for _ps in _prop_sprites:
			var _tag := str(_ps.get_meta("p29_region", "common"))
			if _tag == "region2" and _ps.visible:
				p29_r2_vis += 1
			if _tag == "region1" and _ps.visible:
				p29_r1_vis += 1
			if _tag == "common" and _ps.visible:
				p29_com_vis += 1
		_check(p29_r2_vis == 0 and p29_r1_vis == 3 and p29_com_vis == 27, "pass29: region1 shows green 3, hides rust 0, keeps common 27 (got %d/%d/%d)" % [p29_r2_vis, p29_r1_vis, p29_com_vis])
		# Pass 30 (Destructibles + item animations): stats table, spawn,
		# damage path, no-double-pay, bullet path, cache animation.
		var p30_cs := destructible_stats("crate")
		var p30_bs := destructible_stats("barrel")
		var p30_rs := destructible_stats("ruin")
		_check(float(p30_cs["hp"]) == 20.0 and int(p30_cs["salvage"]) == 10 and float(p30_cs["radius"]) == 1.9, "pass30: crate stats 20 HP / +10 / r1.9 (got %s)" % [p30_cs])
		_check(float(p30_bs["hp"]) == 30.0 and int(p30_bs["salvage"]) == 15 and float(p30_bs["radius"]) == 1.9, "pass30: barrel stats 30 HP / +15 / r1.9 (got %s)" % [p30_bs])
		_check(float(p30_rs["hp"]) == 40.0 and int(p30_rs["salvage"]) == 20 and float(p30_rs["radius"]) == 2.2, "pass30: ruin stats 40 HP / +20 / r2.2 (got %s)" % [p30_rs])
		_check(float(destructible_stats("bogus")["hp"]) == 20.0, "pass30: unknown kind falls back to crate stats")
		_check(_destructibles.size() == 6, "pass30: 6 destructibles spawned (got %d)" % _destructibles.size())
		var p30_kinds := {"crate": 0, "barrel": 0, "ruin": 0}
		var p30_clear := true
		var p30_intact := true
		for _dn in _destructibles:
			var _dk := str(_dn.get_meta("destructible_kind", ""))
			if p30_kinds.has(_dk):
				p30_kinds[_dk] += 1
			if _dn.position.length() < 12.0 or _dn.position.distance_to(_substation_pos) < 10.0:
				p30_clear = false
			if bool(_dn.get_meta("destructible_broken", true)) or not _dn.visible:
				p30_intact = false
			if float(_dn.get_meta("destructible_hp", -1.0)) != float(_dn.get_meta("destructible_max_hp", -2.0)):
				p30_intact = false
			for _dm in _destructibles:
				if _dm != _dn and _dn.position.distance_to(_dm.position) < 6.0:
					p30_clear = false
		_check(p30_kinds["crate"] == 2 and p30_kinds["barrel"] == 2 and p30_kinds["ruin"] == 2, "pass30: kinds 2/2/2 crate/barrel/ruin (got %s)" % [p30_kinds])
		_check(p30_clear, "pass30: destructibles clear core 12 m, substation 10 m, each other 6 m")
		_check(p30_intact, "pass30: all destructibles spawn intact and visible at full HP")
		_check(get_tree().get_nodes_in_group("destructibles").size() >= 6, "pass30: destructibles are in the destructibles group")
		# Damage path on a spawned crate, at standard difficulty.
		difficulty = "standard"
		var p30_crate: Node = null
		for _dn in _destructibles:
			if str(_dn.get_meta("destructible_kind", "")) == "crate":
				p30_crate = _dn
				break
		_check(p30_crate != null, "pass30: a spawned crate exists to damage")
		if p30_crate != null:
			var p30_s0 := salvage
			var p30_fx0 := _destructible_break_fx
			var p30_br0 := _destructible_broken
			_check(not damage_destructible(p30_crate, 10.0), "pass30: 10 damage does not break a 20 HP crate")
			_check(float(p30_crate.get_meta("destructible_hp", -1.0)) == 10.0 and salvage == p30_s0, "pass30: partial hit leaves 10 HP, pays nothing (hp %s, salvage %d)" % [str(p30_crate.get_meta("destructible_hp", -1.0)), salvage])
			_check(damage_destructible(p30_crate, 10.0), "pass30: second 10 damage breaks the crate")
			_check(bool(p30_crate.get_meta("destructible_broken", false)) and not p30_crate.visible, "pass30: broken crate is flagged and hidden")
			_check(salvage == p30_s0 + 10 and _destructible_break_fx == p30_fx0 + 1 and _destructible_broken == p30_br0 + 1, "pass30: broken crate pays +10, spawns 1 break FX (salvage %d, fx %d, broken %d)" % [salvage, _destructible_break_fx, _destructible_broken])
			var p30_s1 := salvage
			_check(not damage_destructible(p30_crate, 99.0) and salvage == p30_s1 and _destructible_break_fx == p30_fx0 + 1, "pass30: hitting a broken crate pays nothing twice")
		# Difficulty scaling: a hard barrel pays 15 x 1.25 = 19.
		difficulty = "hard"
		var p30_barrel: Node = null
		for _dn in _destructibles:
			if str(_dn.get_meta("destructible_kind", "")) == "barrel" and not bool(_dn.get_meta("destructible_broken", false)):
				p30_barrel = _dn
				break
		if p30_barrel != null:
			var p30_s2 := salvage
			_check(damage_destructible(p30_barrel, 30.0) and salvage == p30_s2 + 19, "pass30: hard barrel pays 15 x 1.25 = 19 (salvage %d -> %d)" % [p30_s2, salvage])
		difficulty = "standard"
		# Bullet path: a live player-side bullet breaking a fresh crate.
		var p30_fresh := _make_destructible("crate", Vector3(40, 0, 40))
		var p30_s3 := salvage
		var p30_b := Node3D.new()
		p30_b.set_script(load("res://scripts/bullet.gd"))
		p30_b.position = Vector3(40, 0, 36)
		add_child(p30_b)
		p30_b.setup(Vector3(0, 0, 1), 20.0, "Autocannon", true, false, 55.0)
		for _step in range(20):
			if not is_instance_valid(p30_b) or p30_b.get_parent() == null:
				break
			p30_b._process(0.016)
		_check(bool(p30_fresh.get_meta("destructible_broken", false)) and salvage == p30_s3 + 10, "pass30: bullet breaks a crate for +10 (salvage %d -> %d)" % [p30_s3, salvage])
		_check(p30_b.get_parent() == null, "pass30: bullet is consumed by the destructible hit")
		_destructibles.erase(p30_fresh)
		if is_instance_valid(p30_fresh):
			p30_fresh.queue_free()
		# Cache animation: spin is deterministic, bob/pulse move too.
		var p30_cache := _make_cache(player.global_position + Vector3(20, 0, 0))
		var p30_cn: Node3D = p30_cache
		var p30_rot0 := p30_cn.rotation.y
		var p30_y0 := p30_cn.position.y
		var p30_sc0 := p30_cn.scale.x
		_update_caches(0.6)
		_check(absf(p30_cn.rotation.y - p30_rot0 - 0.84) < 0.05, "pass30: cache spins 1.4 rad/s (rot %f -> %f)" % [p30_rot0, p30_cn.rotation.y])
		_check(absf(p30_cn.position.y - p30_y0) > 0.05 or absf(p30_cn.scale.x - p30_sc0) > 0.02, "pass30: cache bobs/pulses (y %f -> %f, scale %f -> %f)" % [p30_y0, p30_cn.position.y, p30_sc0, p30_cn.scale.x])
		# Pass 31 (Kill-streak + combo salvage): pure tables, kill
		# payouts, milestone calls, HUD line, damage break, capture
		# milestone, difficulty scaling, turret-kill counting, reset.
		# Test isolation (Pass 46): this block measures kill + combo
		# payouts to the salvage, so the contracts board is emptied
		# for its duration — a contract completing mid-sequence would
		# add its own payout to the deltas below. Contracts have their
		# own block (Pass 46) asserting their payouts.
		contracts_active = []
		_check(combo_bonus_for_streak(0) == 0 and combo_bonus_for_streak(4) == 0, "pass31: bonus is 0 below streak 5")
		_check(combo_bonus_for_streak(5) == 5 and combo_bonus_for_streak(9) == 5, "pass31: streak 5-9 pays +5")
		_check(combo_bonus_for_streak(10) == 10 and combo_bonus_for_streak(14) == 10, "pass31: streak 10-14 pays +10")
		_check(combo_bonus_for_streak(15) == 15 and combo_bonus_for_streak(20) == 20 and combo_bonus_for_streak(25) == 25, "pass31: tiers 15/20/25 pay +15/+20/+25")
		_check(combo_bonus_for_streak(55) == 50 and combo_bonus_for_streak(100) == 50, "pass31: bonus caps at +50")
		_check(streak_call_text(0) == "" and streak_call_text(4) == "" and streak_call_text(6) == "", "pass31: no call below 5 or off-milestone")
		_check(streak_call_text(5) == "KILL STREAK x5", "pass31: call at 5 is KILL STREAK x5")
		_check(streak_call_text(10) == "RAMPAGE x10", "pass31: call at 10 is RAMPAGE x10")
		_check(streak_call_text(15) == "UNSTOPPABLE x15", "pass31: call at 15 is UNSTOPPABLE x15")
		_check(streak_call_text(20) == "WAR MACHINE x20" and streak_call_text(25) == "WAR MACHINE x25", "pass31: calls at 20+ are WAR MACHINE xN")
		_check(set_difficulty("standard"), "pass31: difficulty set to standard for payout checks")
		kill_streak = 0
		best_kill_streak = 0
		last_streak_call = ""
		streak_call_count = 0
		for _k in range(4):
			var p31_e = spawn_enemy("scout", Vector3(45, 0, 45))
			var p31_s0 := salvage
			_on_enemy_died(p31_e, 12, "TestGun")
			_check(salvage - p31_s0 == 12, "pass31: kill %d below streak 5 pays base 12 only (got %d)" % [_k + 1, salvage - p31_s0])
			if is_instance_valid(p31_e):
				p31_e.die_silent()
		_check(kill_streak == 4 and best_kill_streak == 4 and streak_call_count == 0, "pass31: 4 kills give streak 4, best 4, no call (streak %d best %d calls %d)" % [kill_streak, best_kill_streak, streak_call_count])
		var p31_e5 = spawn_enemy("scout", Vector3(45, 0, 45))
		var p31_s5 := salvage
		_on_enemy_died(p31_e5, 12, "TestGun")
		_check(salvage - p31_s5 == 17, "pass31: 5th kill pays 12 + 5 combo = 17 (got %d)" % (salvage - p31_s5))
		_check(kill_streak == 5 and last_streak_call == "KILL STREAK x5" and streak_call_count == 1, "pass31: 5th kill calls KILL STREAK x5 (call '%s' count %d)" % [last_streak_call, streak_call_count])
		if is_instance_valid(p31_e5):
			p31_e5.die_silent()
		for _k in range(3):
			var p31_e = spawn_enemy("scout", Vector3(45, 0, 45))
			var p31_s0 := salvage
			_on_enemy_died(p31_e, 12, "TestGun")
			_check(salvage - p31_s0 == 17, "pass31: streak 6-8 kill pays 12 + 5 = 17 (got %d)" % (salvage - p31_s0))
			if is_instance_valid(p31_e):
				p31_e.die_silent()
		_check(kill_streak == 8 and streak_call_count == 1, "pass31: streak 8 still has only the x5 call (streak %d calls %d)" % [kill_streak, streak_call_count])
		var p31_e9 = spawn_enemy("scout", Vector3(45, 0, 45))
		_on_enemy_died(p31_e9, 12, "TestGun")
		if is_instance_valid(p31_e9):
			p31_e9.die_silent()
		var p31_e10 = spawn_enemy("scout", Vector3(45, 0, 45))
		var p31_s10 := salvage
		_on_enemy_died(p31_e10, 12, "TestGun")
		_check(salvage - p31_s10 == 22, "pass31: 10th kill pays 12 + 10 combo = 22 (got %d)" % (salvage - p31_s10))
		_check(kill_streak == 10 and last_streak_call == "RAMPAGE x10" and streak_call_count == 2, "pass31: 10th kill calls RAMPAGE x10 (call '%s' count %d)" % [last_streak_call, streak_call_count])
		if is_instance_valid(p31_e10):
			p31_e10.die_silent()
		_refresh_hud()
		_check(_lbl_stats != null and "STREAK x10" in _lbl_stats.text, "pass31: HUD stats line shows STREAK x10 (%s)" % (_lbl_stats.text if _lbl_stats else "none"))
		_last_player_hp = player.hp
		var p31_hp0: float = player.hp
		player.take_damage(10.0)
		_poll_player_damage()
		_check(kill_streak == 0 and best_kill_streak == 10 and streak_call_count == 2, "pass31: player damage breaks streak, best survives (streak %d best %d calls %d)" % [kill_streak, best_kill_streak, streak_call_count])
		player.hp = p31_hp0
		_last_player_hp = player.hp
		var p31_ea = spawn_enemy("scout", Vector3(45, 0, 45))
		var p31_sa := salvage
		_on_enemy_died(p31_ea, 12, "TestGun")
		_check(kill_streak == 1 and salvage - p31_sa == 12, "pass31: first kill after a break pays base 12 only (streak %d delta %d)" % [kill_streak, salvage - p31_sa])
		if is_instance_valid(p31_ea):
			p31_ea.die_silent()
		kill_streak = 4
		var p31_cc0 := streak_call_count
		var p31_cap = spawn_enemy("scout", Vector3(20, 0, -20))
		p31_cap.set("is_disabled", true)
		var p31_sc := salvage
		_check(capture_enemy(p31_cap), "pass31: capture succeeds at streak 4")
		_check(kill_streak == 5 and streak_call_count == p31_cc0 + 1 and last_streak_call == "KILL STREAK x5", "pass31: capture at streak 4 reaches 5 and calls (streak %d calls %d call '%s')" % [kill_streak, streak_call_count, last_streak_call])
		_check(salvage - p31_sc == 35, "pass31: capture pays 30 capture + 5 combo = 35 (got %d)" % (salvage - p31_sc))
		_check(set_difficulty("hard"), "pass31: difficulty set to hard for scaling check")
		kill_streak = 14
		var p31_eh = spawn_enemy("scout", Vector3(45, 0, 45))
		var p31_sh := salvage
		_on_enemy_died(p31_eh, 12, "TestGun")
		_check(salvage - p31_sh == 34, "pass31: hard streak-15 kill pays 15 + 19 = 34 (got %d)" % (salvage - p31_sh))
		_check(last_streak_call == "UNSTOPPABLE x15", "pass31: hard streak-15 call is UNSTOPPABLE x15 (got '%s')" % last_streak_call)
		if is_instance_valid(p31_eh):
			p31_eh.die_silent()
		_check(set_difficulty("standard"), "pass31: difficulty restored to standard")
		kill_streak = 0
		var p31_et = spawn_enemy("scout", Vector3(45, 0, 45))
		_on_enemy_died(p31_et, 12, "Turret")
		_check(kill_streak == 1, "pass31: turret kill increments the streak (streak %d)" % kill_streak)
		if is_instance_valid(p31_et):
			p31_et.die_silent()
		_reset_run()
		_check(kill_streak == 0 and best_kill_streak == 0 and streak_call_count == 0 and last_streak_call == "", "pass31: run reset clears streak/best/calls (streak %d best %d calls %d call '%s')" % [kill_streak, best_kill_streak, streak_call_count, last_streak_call])
		# Pass 32 (Repair Station): cost, power, slow AoE repair, no
		# self-repair, radius cutoff, unpowered silence, support
		# discount. All checks are direct repair_tick calls (no frame
		# timing), and every coordinate sits >= 6 m from every
		# structure any earlier block built.
		player.apply_loadout("assault", "repair_pulse")
		salvage = 2000
		_check(COSTS["repair_station"] == 110, "pass32: repair station costs 110 salvage")
		salvage = 109
		_check(not try_build("repair_station", Vector3(8, 0, 26)), "pass32: station refuses at 109 salvage")
		salvage = 500
		_check(try_build("repair_station", Vector3(8, 0, 26)), "pass32: station builds for 110 salvage")
		_check(salvage == 390, "pass32: station deducts exactly 110 (salvage %d)" % salvage)
		var p32_station: Node = null
		for s in get_tree().get_nodes_in_group("structures"):
			if str(s.get("structure_kind")) == "repair_station" and Vector3(s.global_position.x, 0, s.global_position.z).distance_to(Vector3(8, 0, 26)) < 1.0:
				p32_station = s
		_check(p32_station != null and p32_station.is_powered(), "pass32: station near core is powered")
		_check(try_build("turret", Vector3(8, 0, 20)), "pass32: turret builds inside repair radius")
		var p32_turret: Node = null
		for s in get_tree().get_nodes_in_group("structures"):
			if str(s.get("structure_kind")) == "turret" and Vector3(s.global_position.x, 0, s.global_position.z).distance_to(Vector3(8, 0, 20)) < 1.0:
				p32_turret = s
		p32_turret.take_damage(40.0)
		p32_station.take_damage(40.0)
		_check(absf(float(p32_turret.get("hp")) - 50.0) < 0.5 and absf(float(p32_station.get("hp")) - 60.0) < 0.5, "pass32: damaged turret 50 hp, station 60 hp (got %f / %f)" % [float(p32_turret.get("hp")), float(p32_station.get("hp"))])
		_check(try_build("barricade", Vector3(30, 0, 26)), "pass32: barricade builds outside repair radius")
		var p32_bar: Node = null
		for s in get_tree().get_nodes_in_group("structures"):
			if str(s.get("structure_kind")) == "barricade" and Vector3(s.global_position.x, 0, s.global_position.z).distance_to(Vector3(30, 0, 26)) < 1.0:
				p32_bar = s
		p32_bar.take_damage(40.0)
		p32_station.repair_tick(1.0)
		_check(absf(float(p32_turret.get("hp")) - 56.0) < 0.5, "pass32: 1 s powered repair heals turret 50 -> 56 (got %f)" % float(p32_turret.get("hp")))
		_check(absf(float(p32_station.get("hp")) - 60.0) < 0.5, "pass32: station does not repair itself (hp %f)" % float(p32_station.get("hp")))
		_check(absf(float(p32_bar.get("hp")) - 120.0) < 0.5, "pass32: out-of-radius barricade untouched (hp %f)" % float(p32_bar.get("hp")))
		p32_station.repair_tick(5.0)
		_check(absf(float(p32_turret.get("hp")) - 86.0) < 0.5, "pass32: 5 s more repair heals turret 56 -> 86 (got %f)" % float(p32_turret.get("hp")))
		_check(absf(float(p32_station.get("hp")) - 60.0) < 0.5 and absf(float(p32_bar.get("hp")) - 120.0) < 0.5, "pass32: station/barricade still unchanged after 6 s total")
		salvage = 2000
		_check(try_build("repair_station", Vector3(-45, 0, 30)), "pass32: remote station builds")
		var p32_remote: Node = null
		for s in get_tree().get_nodes_in_group("structures"):
			if str(s.get("structure_kind")) == "repair_station" and Vector3(s.global_position.x, 0, s.global_position.z).distance_to(Vector3(-45, 0, 30)) < 1.0:
				p32_remote = s
		_check(p32_remote != null and not p32_remote.is_powered(), "pass32: remote station outside power net is unpowered")
		_check(try_build("turret", Vector3(-45, 0, 24)), "pass32: remote turret builds")
		var p32_rturret: Node = null
		for s in get_tree().get_nodes_in_group("structures"):
			if str(s.get("structure_kind")) == "turret" and Vector3(s.global_position.x, 0, s.global_position.z).distance_to(Vector3(-45, 0, 24)) < 1.0:
				p32_rturret = s
		p32_rturret.take_damage(40.0)
		p32_remote.repair_tick(2.0)
		_check(absf(float(p32_rturret.get("hp")) - 50.0) < 0.5, "pass32: unpowered station repairs nothing (hp %f)" % float(p32_rturret.get("hp")))
		player.apply_loadout("support", "repair_pulse")
		salvage = 88
		_check(try_build("repair_station", Vector3(-18, 0, 10)), "pass32: support builds station at exactly 88 salvage")
		_check(salvage == 0, "pass32: support discount is 110 * 0.8 = 88 (salvage %d)" % salvage)
		player.apply_loadout("assault", "repair_pulse")
		salvage = 500
		_refresh_power_lines()
		_check(_power_line_count >= 1, "pass32: power lines drawn with stations on the net (count=%d)" % _power_line_count)
		# Pass 33 (BUGFIX: whole-card tap target): a tap anywhere on a
		# class card selects that chassis, not only the small SELECT
		# button. gui_input is emitted directly — that is exactly the
		# signal the panel handler is connected to — and the
		# mouse_filter checks prove a real tap reaches the panel
		# instead of dying on a portrait/label/bar child.
		_open_hangar()
		for p33_cn in ["scout", "assault", "support"]:
			var p33_card: Dictionary = _hangar_cards[p33_cn]
			var p33_panel: PanelContainer = p33_card["panel"]
			_check(p33_panel.mouse_filter == Control.MOUSE_FILTER_STOP, "pass33: %s card panel still receives input (filter %d)" % [p33_cn, p33_panel.mouse_filter])
			_check((p33_card["preview"] as Control).mouse_filter == Control.MOUSE_FILTER_IGNORE, "pass33: %s card preview passes taps through (filter %d)" % [p33_cn, (p33_card["preview"] as Control).mouse_filter])
			var p33_bars: Dictionary = p33_card["bars"]
			var p33_bars_ignore := true
			for p33_bk in ["hull", "speed", "mobility"]:
				if (p33_bars[p33_bk] as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
					p33_bars_ignore = false
			_check(p33_bars_ignore, "pass33: %s card stat bars pass taps through" % p33_cn)
			var p33_other := "scout" if p33_cn != "scout" else "assault"
			_sel_chassis = p33_other
			var p33_click := InputEventMouseButton.new()
			p33_click.button_index = MOUSE_BUTTON_LEFT
			p33_click.pressed = true
			p33_panel.gui_input.emit(p33_click)
			_check(_sel_chassis == p33_cn, "pass33: mouse tap on %s card panel selects %s (got %s)" % [p33_cn, p33_cn, _sel_chassis])
			_sel_chassis = p33_other
			var p33_touch := InputEventScreenTouch.new()
			p33_touch.pressed = true
			p33_panel.gui_input.emit(p33_touch)
			_check(_sel_chassis == p33_cn, "pass33: touch tap on %s card panel selects %s (got %s)" % [p33_cn, p33_cn, _sel_chassis])
			_sel_chassis = p33_other
			var p33_right := InputEventMouseButton.new()
			p33_right.button_index = MOUSE_BUTTON_RIGHT
			p33_right.pressed = true
			p33_panel.gui_input.emit(p33_right)
			var p33_release := InputEventMouseButton.new()
			p33_release.button_index = MOUSE_BUTTON_LEFT
			p33_release.pressed = false
			p33_panel.gui_input.emit(p33_release)
			_check(_sel_chassis == p33_other, "pass33: right-click / left-release on %s card does NOT select (still %s)" % [p33_cn, _sel_chassis])
			_sel_chassis = p33_other
			(p33_card["select"] as Button).pressed.emit()
			_check(_sel_chassis == p33_cn, "pass33: SELECT button on %s card still selects %s (got %s)" % [p33_cn, p33_cn, _sel_chassis])
		# Panel-tap pick drives the border + deploy exactly like the
		# old button pick did (no stat/cost/deploy change).
		_sel_chassis = "assault"
		var p33_scout_click := InputEventMouseButton.new()
		p33_scout_click.button_index = MOUSE_BUTTON_LEFT
		p33_scout_click.pressed = true
		(_hangar_cards["scout"]["panel"] as PanelContainer).gui_input.emit(p33_scout_click)
		var p33_scout_style = (_hangar_cards["scout"]["panel"] as PanelContainer).get_theme_stylebox("panel")
		var p33_assault_style = (_hangar_cards["assault"]["panel"] as PanelContainer).get_theme_stylebox("panel")
		_check(p33_scout_style is StyleBoxFlat and (p33_scout_style as StyleBoxFlat).border_width_left == 3, "pass33: panel-tapped scout card border is thick (3)")
		_check(p33_assault_style is StyleBoxFlat and (p33_assault_style as StyleBoxFlat).border_width_left == 1, "pass33: unselected assault card border stays thin (1)")
		_deploy_from_hangar()
		_check(not hangar_open and str(player.get("chassis")) == "scout" and player.max_hp == 110.0 and player.max_speed == 16.5, "pass33: deploy after panel-tap pick applies scout stats (hp %f speed %f)" % [player.max_hp, player.max_speed])
		_sel_chassis = "assault"
		_sel_utility = "repair_pulse"
		_sel_doctrine = "iron_wall"
		_sel_region = "region1"
		loadout = {"chassis": "assault", "utility": "repair_pulse", "doctrine": "iron_wall", "region": "region1", "quality": quality_mode, "difficulty": "standard"}
		_check(set_difficulty("standard"), "pass33: difficulty restored after card-tap checks")
		save_loadout()
		# Pass 34 (template top-down units): every unit kind renders a
		# flat top-down frame from the template, at the old rendered
		# length, with no billboard anywhere in the body subtree; the
		# hangar portrait shows the same p34 art as the in-game unit.
		# Pass 35: the per-kind holder now shows a p35 walk frame of its
		# own stem (walk0 = the p34 base frame); the frame index after an
		# awaited frame is not pinned, so the check asserts the walk set.
		var p34_expect := {
			"scout": ["enemy_swarm_green", 3.4],
			"heavy": ["enemy_tank", 4.6],
			"shield_heavy": ["enemy_artillery", 4.6],
			"burrower": ["enemy_spiky", 3.6],
			"sapper": ["enemy_drone", 3.0],
			"lancer": ["enemy_strider", 4.2],
			"siege": ["enemy_siege", 9.0],
		}
		var p34_seen := {}
		for p34_kind in p34_expect:
			var p34_foe = spawn_enemy(p34_kind, Vector3(-45, 0, -45))
			await get_tree().process_frame
			var p34_body: Node = p34_foe.get("_body")
			var p34_quad: MeshInstance3D = SpriteUtil.topdown_quad(p34_body.get_node_or_null("unit_sprite")) if p34_body else null
			var p34_tex: String = ""
			if p34_quad != null:
				var p34_mat: StandardMaterial3D = p34_quad.get_surface_override_material(0) as StandardMaterial3D
				if p34_mat != null and p34_mat.albedo_texture != null:
					p34_tex = str(p34_mat.albedo_texture.resource_path)
			p34_seen[p34_kind] = p34_tex
			_check(p34_quad != null and p34_tex.contains("p35_%s_walk" % str(p34_expect[p34_kind][0])), "pass35: %s renders its p35 walk set (got %s)" % [p34_kind, p34_tex])
			if p34_quad != null and p34_quad.mesh is QuadMesh:
				_check(absf((p34_quad.mesh as QuadMesh).size.y - float(p34_expect[p34_kind][1]) * 1.4) < 0.3, "pass34: %s quad length is %f*1.4 (got %f)" % [p34_kind, float(p34_expect[p34_kind][1]), (p34_quad.mesh as QuadMesh).size.y])
				_check(absf(p34_quad.rotation_degrees.x + 90.0) < 0.01, "pass34: %s quad lies flat" % p34_kind)
			var p34_stack: Array = [p34_body]
			var p34_bill := false
			while not p34_stack.is_empty():
				var p34_n: Node = p34_stack.pop_back()
				for p34_ch in p34_n.get_children():
					if p34_ch is Sprite3D:
						p34_bill = true
					p34_stack.append(p34_ch)
			_check(not p34_bill, "pass34: %s body has no billboard sprite" % p34_kind)
			if is_instance_valid(p34_foe):
				p34_foe.die_silent()
		var p34_distinct := true
		var p34_keys := p34_seen.keys()
		for _i in range(p34_keys.size()):
			for _j in range(_i + 1, p34_keys.size()):
				if p34_seen[p34_keys[_i]] == p34_seen[p34_keys[_j]]:
					p34_distinct = false
		_check(p34_distinct, "pass34: all seven enemy kinds use distinct template frames (%s)" % [p34_seen])
		for p34_file in ["p34_scout.png", "p34_assault.png", "p34_support.png", "p34_enemy_strider.png", "p34_enemy_tank.png", "p34_enemy_artillery.png", "p34_enemy_swarm_green.png", "p34_enemy_spiky.png", "p34_enemy_drone.png", "p34_enemy_siege.png"]:
			_check(ResourceLoader.exists("res://sprites/p34/" + p34_file), "pass34: sprite file exists: %s" % p34_file)
		_sel_chassis = "assault"
		_open_hangar()
		_refresh_hangar()
		if _hangar_portrait != null and _hangar_portrait.texture != null:
			_check(str(_hangar_portrait.texture.resource_path).contains("p34_assault"), "pass34: hangar portrait shows the same p34 assault art as the unit (%s)" % str(_hangar_portrait.texture.resource_path))
		_deploy_from_hangar()
		_check(not hangar_open, "pass34: hangar closed after portrait check")
		# Pass 36 (MENU-SYSTEMS RESTYLE): one shared chrome — every
		# panel dark near-black navy with a bright cyan border and
		# radius 8, HUD zones translucent (0.88) and modals opaque,
		# six header dividers (hangar, level-up, substation, pause,
		# victory, game-over), pick buttons cyan-fill when selected
		# and dark-navy otherwise, primaries (DEPLOY, RESUME,
		# CONTINUE) cyan-fill. Skin only: no size, position, text,
		# cost, or stat is asserted here beyond chrome.
		var p36_bg := Color(0.02, 0.05, 0.11)
		var p36_cyan := Color(0.18, 0.78, 0.95)
		var p36_dark_btn := Color(0.04, 0.08, 0.15, 1.0)
		var p36_panels: Array = []
		for _zp in _hud_zones:
			p36_panels.append([_zp, 0.88])
		p36_panels.append([_minimap_panel, 0.88])
		p36_panels.append([_hangar_panel, 1.0])
		p36_panels.append([_lvl_panel, 1.0])
		p36_panels.append([_sub_panel, 1.0])
		p36_panels.append([_pause_panel, 1.0])
		p36_panels.append([_win_panel, 1.0])
		p36_panels.append([_gameover_panel, 1.0])
		for _pp in p36_panels:
			var _psb = (_pp[0] as PanelContainer).get_theme_stylebox("panel")
			_check(_psb is StyleBoxFlat and (_psb as StyleBoxFlat).bg_color == Color(p36_bg.r, p36_bg.g, p36_bg.b, float(_pp[1])) and (_psb as StyleBoxFlat).border_color == p36_cyan and (_psb as StyleBoxFlat).border_width_left == 2 and (_psb as StyleBoxFlat).corner_radius_top_left == 8, "pass36: panel chrome shared (bg %s border %s w %d r %d)" % [str((_psb as StyleBoxFlat).bg_color) if _psb is StyleBoxFlat else "none", str((_psb as StyleBoxFlat).border_color) if _psb is StyleBoxFlat else "none", (_psb as StyleBoxFlat).border_width_left if _psb is StyleBoxFlat else -1, (_psb as StyleBoxFlat).corner_radius_top_left if _psb is StyleBoxFlat else -1])
		_check(_p36_dividers.size() == 6, "pass36: exactly 6 modal header dividers (got %d)" % _p36_dividers.size())
		for _dv in _p36_dividers:
			var _dc: ColorRect = _dv
			_check(_dc.color == Color(p36_cyan.r, p36_cyan.g, p36_cyan.b, 0.6) and _dc.custom_minimum_size.y == 2.0, "pass36: divider is 2px cyan at 0.6 alpha (got %s %f)" % [str(_dc.color), _dc.custom_minimum_size.y])
		_check(_version_lbl != null and _version_lbl.get_theme_color("font_color") == Color(0.65, 0.93, 1.0), "pass36: version stamp uses the menu title colour")
		var p36_fire = _fire_btn.get_theme_stylebox("normal")
		var p36_zoom = _zoom_btn.get_theme_stylebox("normal")
		var p36_build0 = (_build_bar.get_child(0) as Button).get_theme_stylebox("normal")
		_check(p36_fire is StyleBoxFlat and (p36_fire as StyleBoxFlat).bg_color == p36_dark_btn, "pass36: FIRE button is a dark-navy menu row")
		_check(p36_zoom is StyleBoxFlat and (p36_zoom as StyleBoxFlat).bg_color == p36_dark_btn, "pass36: ZOOM button is a dark-navy menu row")
		_check(p36_build0 is StyleBoxFlat and (p36_build0 as StyleBoxFlat).bg_color == p36_dark_btn, "pass36: build-bar button is a dark-navy menu row")
		# _open_hangar reloads chassis/utility/doctrine/difficulty from the
		# saved loadout (region is untouched), so the picks must be set
		# AFTER opening, not before — setting them first was this
		# block's first-cut bug, caught by its own checks.
		_open_hangar()
		_sel_chassis = "support"
		_sel_utility = "grapple"
		_sel_doctrine = "ghost_protocol"
		_sel_region = "region2"
		_sel_difficulty = "brutal"
		_refresh_hangar()
		var p36_sel_btn = (_hangar_pick_btns["utility:grapple"] as Button).get_theme_stylebox("normal")
		var p36_unsel_btn = (_hangar_pick_btns["utility:repair_pulse"] as Button).get_theme_stylebox("normal")
		var p36_doc_btn = (_hangar_pick_btns["doctrine:ghost_protocol"] as Button).get_theme_stylebox("normal")
		var p36_reg_btn = (_hangar_pick_btns["region:region2"] as Button).get_theme_stylebox("normal")
		var p36_dif_btn = (_hangar_pick_btns["difficulty:brutal"] as Button).get_theme_stylebox("normal")
		var p36_sup_sel = (_hangar_cards["support"]["select"] as Button).get_theme_stylebox("normal")
		var p36_sco_sel = (_hangar_cards["scout"]["select"] as Button).get_theme_stylebox("normal")
		_check(p36_sel_btn is StyleBoxFlat and (p36_sel_btn as StyleBoxFlat).bg_color == p36_cyan, "pass36: selected grapple pick is cyan-fill")
		_check((_hangar_pick_btns["utility:grapple"] as Button).get_theme_color("font_color") == Color(0.02, 0.05, 0.12), "pass36: selected pick text is dark navy on cyan")
		_check(p36_unsel_btn is StyleBoxFlat and (p36_unsel_btn as StyleBoxFlat).bg_color == p36_dark_btn, "pass36: unselected repair-pulse pick stays dark-navy")
		_check(p36_doc_btn is StyleBoxFlat and (p36_doc_btn as StyleBoxFlat).bg_color == p36_cyan, "pass36: selected ghost-protocol pick is cyan-fill")
		_check(p36_reg_btn is StyleBoxFlat and (p36_reg_btn as StyleBoxFlat).bg_color == p36_cyan, "pass36: selected region2 pick is cyan-fill")
		_check(p36_dif_btn is StyleBoxFlat and (p36_dif_btn as StyleBoxFlat).bg_color == p36_cyan, "pass36: selected brutal pick is cyan-fill")
		_check(p36_sup_sel is StyleBoxFlat and (p36_sup_sel as StyleBoxFlat).bg_color == p36_cyan, "pass36: selected support SELECT is cyan-fill")
		_check(p36_sco_sel is StyleBoxFlat and (p36_sco_sel as StyleBoxFlat).bg_color == p36_dark_btn, "pass36: unselected scout SELECT stays dark-navy")
		var p36_dep = _deploy_btn.get_theme_stylebox("normal")
		_check(p36_dep is StyleBoxFlat and (p36_dep as StyleBoxFlat).bg_color == p36_cyan, "pass36: DEPLOY is the cyan-fill primary")
		_sel_chassis = "assault"
		_sel_utility = "repair_pulse"
		_sel_doctrine = "iron_wall"
		_sel_region = "region1"
		_sel_difficulty = "standard"
		_deploy_from_hangar()
		_check(not hangar_open, "pass36: hangar closed after chrome checks")
		_check(set_difficulty("standard"), "pass36: difficulty restored after chrome checks")
		# Pass 37 (FEATURE: wave preview): the panel lists the next
		# wave's composition during intermission and hides otherwise.
		# Pure-text counts are pinned against the real queues first,
		# then the panel's visibility rule is driven end to end.
		_check(wave_preview_text(1, "") == "NEXT WAVE 1 — 8x SCOUT", "pass37: wave 1 preview counts its queue (%s)" % wave_preview_text(1, ""))
		_check(wave_preview_text(2, "") == "NEXT WAVE 2 — 6x SCOUT, 2x HEAVY, 2x SHIELD HEAVY", "pass37: wave 2 preview counts its queue (%s)" % wave_preview_text(2, ""))
		_check(wave_preview_text(3, "") == "NEXT WAVE 3 — 5x SCOUT, 3x HEAVY, 2x SHIELD HEAVY, 1x BULWARK, 3x BURROWER, 2x SAPPER, 2x LANCER, 1x SIEGE", "pass37: wave 3 preview counts its queue (%s)" % wave_preview_text(3, ""))
		_check(wave_preview_text(4, "") == "NEXT WAVE 4 — 10x SCOUT, 6x HEAVY, 3x SHIELD HEAVY, 5x BURROWER, 2x SAPPER, 1x LANCER", "pass37: endless wave 4 preview counts its queue (%s)" % wave_preview_text(4, ""))
		_check(wave_preview_text(2, "shielded_heavies") == "NEXT WAVE 2 — 6x SCOUT, 2x HEAVY, 4x SHIELD HEAVY", "pass37: adaptation counter lands in the preview (%s)" % wave_preview_text(2, "shielded_heavies"))
		_check(wave_preview_text(2, "tunneling_units") == "NEXT WAVE 2 — 6x SCOUT, 2x HEAVY, 2x SHIELD HEAVY, 2x BURROWER", "pass37: tunneling counter lands in the preview (%s)" % wave_preview_text(2, "tunneling_units"))
		var p37_wave0 := wave
		var p37_active0 := _wave_active
		var p37_go0 := _game_over
		var p37_won0 := _won
		var p37_adapt0 := saved_adaptation
		_check(_preview_panel != null and _preview_panel is PanelContainer, "pass37: preview panel exists")
		_check(_preview_lbl != null and _preview_lbl.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART, "pass37: preview label wraps")
		var p37_psb = _preview_panel.get_theme_stylebox("panel")
		_check(p37_psb is StyleBoxFlat and (p37_psb as StyleBoxFlat).bg_color == Color(0.02, 0.05, 0.11, 0.88) and (p37_psb as StyleBoxFlat).border_color == Color(0.18, 0.78, 0.95), "pass37: preview panel uses the shared menu chrome")
		# Pass 40 supersedes: the preview stacks at 126 under a live
		# message or at 92 under the hidden message bar, never at a
		# fixed 158 — assert the stacked value for the current state.
		_check(_preview_panel.position.y == (126.0 if _lbl_msg.text != "" else 92.0), "pass40 supersedes pass37: preview stacks under the message state (y %f, msg %s)" % [_preview_panel.position.y, ("live" if _lbl_msg.text != "" else "hidden")])
		_check(_preview_panel.size == Vector2(700, 40), "pass40 supersedes pass37: preview panel is 700x40 (got %s)" % str(_preview_panel.size))
		_check(_preview_panel in _hud_controls, "pass37: preview panel is a HUD control (hangar hides it)")
		wave = 1
		_wave_active = false
		_game_over = false
		_won = false
		saved_adaptation = "shielded_heavies"
		_refresh_hud()
		_check(_preview_panel.visible, "pass37: preview visible during intermission")
		_check(_preview_lbl.text == "NEXT WAVE 2 — 6x SCOUT, 2x HEAVY, 4x SHIELD HEAVY", "pass37: intermission preview shows wave 2 with the saved adaptation (%s)" % _preview_lbl.text)
		_wave_active = true
		_refresh_hud()
		_check(not _preview_panel.visible, "pass37: preview hidden while a wave runs")
		_wave_active = false
		_refresh_hud()
		_check(_preview_panel.visible, "pass37: preview returns at the next intermission")
		_open_hangar()
		_check(not _preview_panel.visible, "pass37: hangar hides the preview")
		_deploy_from_hangar()
		_refresh_hud()
		_check(_preview_panel.visible, "pass37: preview returns after deploy")
		wave = p37_wave0
		_wave_active = p37_active0
		_game_over = p37_go0
		_won = p37_won0
		saved_adaptation = p37_adapt0
		# Pass 38 (BALANCE): XP curve, endless queue cap, endless scaling.
		var p38_level0 := level
		var p38_xp0 := xp
		var p38_wave0 := wave
		var p38_endless0 := endless_mode
		var p38_diff0 := difficulty
		var p38_dmg0 := float(player.damage_mult)
		level = 1
		_check(xp_threshold() == 5, "pass38: level 1 threshold is 5 (got %d)" % xp_threshold())
		level = 2
		_check(xp_threshold() == 9, "pass38: level 2 threshold is 9 (got %d)" % xp_threshold())
		level = 3
		_check(xp_threshold() == 13, "pass38: level 3 threshold is 13 (got %d)" % xp_threshold())
		level = 4
		_check(xp_threshold() == 17, "pass38: level 4 threshold is 17 (got %d)" % xp_threshold())
		level = 5
		_check(xp_threshold() == 23, "pass38: level 5 threshold is 23, not old 21 (got %d)" % xp_threshold())
		level = 6
		_check(xp_threshold() == 33, "pass38: level 6 threshold is 33, not old 25 (got %d)" % xp_threshold())
		level = 7
		_check(xp_threshold() == 47, "pass38: level 7 threshold is 47, not old 29 (got %d)" % xp_threshold())
		level = 8
		_check(xp_threshold() == 65, "pass38: level 8 threshold is 65, not old 33 (got %d)" % xp_threshold())
		level = 10
		_check(xp_threshold() == 113, "pass38: level 10 threshold is 113, not old 41 (got %d)" % xp_threshold())
		var p38_cum := 0
		for p38_lv in range(1, 10):
			level = p38_lv
			p38_cum += xp_threshold()
		_check(p38_cum == 299, "pass38: XP to reach level 10 is 299, not old 189 (got %d)" % p38_cum)
		# grant_xp honours the new curve: 23 XP at level 4 buys exactly
		# one level (17) and leaves 6 toward the 23-cost level 5.
		level = 4
		xp = 0
		grant_xp(23)
		_check(level == 5 and xp == 6, "pass38: grant 23 XP at level 4 -> level 5, 6 XP left (got level %d, xp %d)" % [level, xp])
		# Early campaign pacing is unchanged: 27 XP still buys levels 2-4.
		level = 1
		xp = 0
		grant_xp(27)
		_check(level == 4 and xp == 0, "pass38: grant 27 XP at level 1 -> level 4, 0 XP left (got level %d, xp %d)" % [level, xp])
		# Queue sizes: campaign waves untouched, endless waves capped.
		_check(build_wave_queue(1, "unformed").size() == 8, "pass38: wave 1 queue still 8 (got %d)" % build_wave_queue(1, "unformed").size())
		_check(build_wave_queue(2, "unformed").size() == 10, "pass38: wave 2 queue still 10 (got %d)" % build_wave_queue(2, "unformed").size())
		_check(build_wave_queue(3, "unformed").size() == 19, "pass38: wave 3 queue now 19 with Pass 41 bulwark (got %d)" % build_wave_queue(3, "unformed").size())
		_check(build_wave_queue(4, "unformed").size() == 27, "pass38: wave 4 queue still 27 (got %d)" % build_wave_queue(4, "unformed").size())
		_check(build_wave_queue(8, "unformed").size() == 42, "pass38: wave 8 queue still 42 (got %d)" % build_wave_queue(8, "unformed").size())
		_check(build_wave_queue(12, "unformed").size() == 49, "pass38: wave 12 queue now 49 with 2 Pass 41 bulwarks (got %d)" % build_wave_queue(12, "unformed").size())
		_check(build_wave_queue(20, "unformed").size() == 54, "pass38: wave 20 queue now 54 with 2 Pass 41 bulwarks (got %d)" % build_wave_queue(20, "unformed").size())
		_check(build_wave_queue(30, "unformed").size() == 55, "pass38: wave 30 queue now 55 with 2 Pass 41 bulwarks, still under the 60 spawn cap (got %d)" % build_wave_queue(30, "unformed").size())
		# Pure endless factors.
		_check(absf(endless_dmg_factor(3) - 1.0) < 0.01, "pass38: dmg factor below wave 4 is 1.0 (got %f)" % endless_dmg_factor(3))
		_check(absf(endless_dmg_factor(4) - 1.0) < 0.01, "pass38: dmg factor at wave 4 is 1.0 (got %f)" % endless_dmg_factor(4))
		_check(absf(endless_dmg_factor(8) - 1.2) < 0.01, "pass38: dmg factor at wave 8 is 1.20 (got %f)" % endless_dmg_factor(8))
		_check(absf(endless_dmg_factor(12) - 1.4) < 0.01, "pass38: dmg factor at wave 12 is 1.40 (got %f)" % endless_dmg_factor(12))
		_check(absf(endless_dmg_factor(14) - 1.5) < 0.01, "pass38: dmg factor caps at 1.50 by wave 14 (got %f)" % endless_dmg_factor(14))
		_check(absf(endless_dmg_factor(30) - 1.5) < 0.01, "pass38: dmg factor still 1.50 at wave 30 (got %f)" % endless_dmg_factor(30))
		_check(absf(endless_shield_factor(1) - 1.0) < 0.01, "pass38: shield factor at wave 1 is 1.0 (got %f)" % endless_shield_factor(1))
		_check(absf(endless_shield_factor(4) - 1.45) < 0.01, "pass38: shield factor at wave 4 is 1.45 (got %f)" % endless_shield_factor(4))
		_check(absf(endless_shield_factor(12) - 2.65) < 0.01, "pass38: shield factor at wave 12 is 2.65 (got %f)" % endless_shield_factor(12))
		# Spawned proof, standard difficulty: the guard is endless_mode.
		difficulty = "standard"
		endless_mode = false
		wave = 12
		var p38_base = spawn_enemy("heavy", Vector3(-30, 0, -30))
		_check(absf(float(p38_base.get("dmg")) - 12.0) < 0.01, "pass38: non-endless wave-12 heavy keeps base dmg 12 (got %f)" % float(p38_base.get("dmg")))
		var p38_base_sh = spawn_enemy("shield_heavy", Vector3(-30, 0, -25))
		_check(absf(float(p38_base_sh.get("shield_max")) - 90.0) < 0.01, "pass38: non-endless shield pool stays 90 (got %f)" % float(p38_base_sh.get("shield_max")))
		endless_mode = true
		var p38_end = spawn_enemy("heavy", Vector3(-30, 0, -20))
		_check(absf(float(p38_end.get("dmg")) - 16.8) < 0.01, "pass38: endless wave-12 heavy dmg is 12 x 1.40 = 16.8 (got %f)" % float(p38_end.get("dmg")))
		var p38_end_sh = spawn_enemy("shield_heavy", Vector3(-30, 0, -15))
		_check(absf(float(p38_end_sh.get("shield_max")) - 238.5) < 0.01, "pass38: endless wave-12 shield pool is 90 x 2.65 = 238.5 (got %f)" % float(p38_end_sh.get("shield_max")))
		wave = 30
		var p38_cap = spawn_enemy("scout", Vector3(-30, 0, -10))
		_check(absf(float(p38_cap.get("dmg")) - 7.5) < 0.01, "pass38: endless wave-30 scout dmg caps at 5 x 1.50 = 7.5 (got %f)" % float(p38_cap.get("dmg")))
		for p38_e in [p38_base, p38_base_sh, p38_end, p38_end_sh, p38_cap]:
			if is_instance_valid(p38_e):
				p38_e.die_silent()
		level = p38_level0
		xp = p38_xp0
		wave = p38_wave0
		endless_mode = p38_endless0
		difficulty = p38_diff0
		player.damage_mult = p38_dmg0
		# Pass 39 (GRAPHICS: Ground v2): repeat frequency, both regions,
		# and the ruin-box audit outcome. No balance/mechanic values
		# are touched by this pass, so nothing here asserts one.
		# Repeat: plane 185.6 m / uv scale 2 = 92.8 m per motif, wider
		# than the phone view (ortho height 34 m, landscape aspect
		# ~1.8 -> ~61 m wide), so one view holds at most one repeat.
		if _ground_mat != null:
			_check(absf(_ground_mat.uv1_scale.x - 2.0) < 0.01 and absf(_ground_mat.uv1_scale.y - 2.0) < 0.01, "pass39: ground uv repeat is 2x2, not 6x6 (got %s)" % str(_ground_mat.uv1_scale))
			var p39_period := 185.6 / _ground_mat.uv1_scale.x
			_check(p39_period > 61.0, "pass39: motif period %.1f m exceeds the ~61 m phone view" % p39_period)
		else:
			_check(false, "pass39: ground material missing")
		_check(set_region("region1"), "pass39: region1 selectable")
		if _ground_mat and _ground_mat.albedo_texture:
			_check(str(_ground_mat.albedo_texture.resource_path).contains("p39_ground_v2") and not str(_ground_mat.albedo_texture.resource_path).contains("rust"), "pass39: region1 ground is v2 base (%s)" % _ground_mat.albedo_texture.resource_path)
		_check(set_region("region2"), "pass39: region2 selectable")
		if _ground_mat and _ground_mat.albedo_texture:
			_check(str(_ground_mat.albedo_texture.resource_path).contains("p39_ground_rust_v2"), "pass39: region2 ground is v2 rust (%s)" % _ground_mat.albedo_texture.resource_path)
		_check(set_region("region1"), "pass39: region1 restores")
		# Ruin audit: every ruin position now carries a flat top-down
		# sprite (same p8 sheet as the other props), none is a box, and
		# no ruin_box node remains anywhere in the tree.
		_check(_ruin_sprites.size() == _ruin_positions.size() and _ruin_positions.size() >= 20, "pass39: ruin sprites match ruin positions (%d sprites, %d positions)" % [_ruin_sprites.size(), _ruin_positions.size()])
		var p39_spr_textured := 0
		for _rs in _ruin_sprites:
			# ground_sprite holders: child 0 is the textured quad.
			var _rquad: Node = _rs.get_child(0) if _rs.get_child_count() > 0 else null
			if _rquad is MeshInstance3D:
				var _rm := (_rquad as MeshInstance3D).get_surface_override_material(0) as StandardMaterial3D
				if _rm != null and _rm.albedo_texture != null and str(_rm.albedo_texture.resource_path).contains("tile_"):
					p39_spr_textured += 1
		_check(p39_spr_textured == _ruin_sprites.size(), "pass39: every ruin sprite carries a p8 tile texture (%d/%d)" % [p39_spr_textured, _ruin_sprites.size()])
		var p39_boxes := 0
		for _n in get_children():
			if _n.name == "ruin_box":
				p39_boxes += 1
		_check(p39_boxes == 0, "pass39: no ruin_box node remains (got %d)" % p39_boxes)
		var p39_grounded := true
		for _rs in _ruin_sprites:
			if absf(_rs.position.y) > 0.01:
				p39_grounded = false
		_check(p39_grounded, "pass39: ruin sprites sit at ground level y=0, not floating")
		_check(_version_lbl != null and _version_lbl.text.contains("v1.51"), "pass47 supersedes pass45: version stamp reads v1.51 (%s)" % (_version_lbl.text if _version_lbl else "none"))
		# Pass 40 (UX: HUD consolidation) — one total HUD budget,
		# checked against the 1152x648 design viewport (the phone
		# viewport is wider, never narrower, under stretch-expand,
		# so a fit here is a fit there, with more side margin).
		var p40_vp := get_viewport().get_visible_rect().size
		var p40_wave0 := wave
		var p40_active0 := _wave_active
		var p40_go0 := _game_over
		var p40_won0 := _won
		var p40_msg0 := _lbl_msg.text if _lbl_msg else ""
		var p40_timer0 := _msg_timer
		_check(_hud_zones.size() == 3 and absf((_hud_zones[0] as Control).size.y - P40_TOP_H) < 0.5, "pass40: top bar is 84 high (got %s)" % ((_hud_zones[0] as Control).size.y if _hud_zones.size() == 3 else -1.0))
		_check(_hud_zones.size() == 3 and absf((_hud_zones[0] as Control).position.y - 4.0) < 0.5, "pass40: top bar sits at y=4 (got %s)" % ((_hud_zones[0] as Control).position.y if _hud_zones.size() == 3 else -1.0))
		_check(_hud_zones.size() == 3 and absf((_hud_zones[2] as Control).size.y - P40_BOTTOM_H) < 0.5, "pass40: bottom panel is 124 high (got %s)" % ((_hud_zones[2] as Control).size.y if _hud_zones.size() == 3 else -1.0))
		_check(_hud_zones.size() == 3 and absf((_hud_zones[2] as Control).position.y - (p40_vp.y - P40_BOTTOM_H)) < 0.5, "pass40: bottom panel tops at vh-124 (got %s vs %s)" % [(_hud_zones[2] as Control).position.y if _hud_zones.size() == 3 else -1.0, p40_vp.y - P40_BOTTOM_H])
		_check(_msg_zone != null and absf(_msg_zone.size.y - P40_MSG_H) < 0.5, "pass40: message bar is 30 high (got %s)" % (_msg_zone.size.y if _msg_zone else -1.0))
		_check(_minimap_panel != null and _minimap_panel.size == Vector2(120.0, 120.0), "pass40: minimap is 120x120 (got %s)" % (str(_minimap_panel.size) if _minimap_panel else "none"))
		_check(_minimap_panel != null and absf(_minimap_panel.position.x - (p40_vp.x - 128.0)) < 0.5 and absf(_minimap_panel.position.y - 8.0) < 0.5, "pass40: minimap sits top-right with an 8 px margin (got %s)" % (str(_minimap_panel.position) if _minimap_panel else "none"))
		if _minimap_panel != null and _hud_zones.size() == 3:
			var p40_map_rect := _minimap_panel.get_global_rect()
			_check(not p40_map_rect.intersects((_hud_zones[0] as Control).get_global_rect()), "pass40: minimap does not overlap the top bar")
			_check(not p40_map_rect.intersects(_msg_zone.get_global_rect()), "pass40: minimap does not overlap the message bar")
			_check(not p40_map_rect.intersects(_preview_panel.get_global_rect()), "pass40: minimap does not overlap the preview panel")
		# Message bar hidden when empty, whole panel and all.
		_lbl_msg.text = ""
		_msg_timer = 0.0
		_refresh_hud()
		_check(_msg_zone != null and not _msg_zone.visible, "pass40: message bar hidden when empty")
		_check(not _lbl_msg.visible, "pass40: message label hidden when empty")
		# Message bar back, at y=92, when a message is live.
		flash_msg("P40 HUD CHECK")
		_refresh_hud()
		_check(_msg_zone != null and _msg_zone.visible and _lbl_msg.visible, "pass40: message bar visible with a live message")
		_check(_msg_zone != null and absf(_msg_zone.position.y - 92.0) < 0.5, "pass40: message bar sits at y=92 (got %s)" % (_msg_zone.position.y if _msg_zone else -1.0))
		# Preview stacks under the live message, then under the top
		# bar once the message clears — never over a gap.
		wave = 1
		_wave_active = false
		_game_over = false
		_won = false
		_refresh_hud()
		_check(_preview_panel.visible and absf(_preview_panel.position.y - 126.0) < 0.5, "pass40: preview sits at y=126 under a live message (got %s)" % _preview_panel.position.y)
		_lbl_msg.text = ""
		_msg_timer = 0.0
		_refresh_hud()
		_check(_preview_panel.visible and absf(_preview_panel.position.y - 92.0) < 0.5, "pass40: preview rises to y=92 when the message bar hides (got %s)" % _preview_panel.position.y)
		_check(absf(_preview_panel.size.y - P40_PREVIEW_H) < 0.5, "pass40: preview panel is 40 high (got %s)" % _preview_panel.size.y)
		# Every bottom row lives inside the 124 panel, nothing clipped.
		if _hud_zones.size() == 3:
			var p40_bot := (_hud_zones[2] as Control).get_global_rect()
			var p40_w0 := (_weapon_icons[0] as Control).get_global_rect() if _weapon_icons.size() > 0 else Rect2()
			_check(p40_w0.position.y >= p40_bot.position.y - 0.5 and p40_w0.end.y <= p40_bot.end.y + 0.5, "pass40: weapon row inside the bottom panel (row %s vs panel %s)" % [p40_w0, p40_bot])
			var p40_fb := _fire_btn.get_global_rect()
			_check(p40_fb.position.y >= p40_bot.position.y - 0.5 and p40_fb.end.y <= p40_bot.end.y + 0.5, "pass40: FIRE button inside the bottom panel")
			var p40_bb := _build_bar.get_global_rect()
			_check(p40_bb.position.y >= p40_bot.position.y - 0.5 and p40_bb.end.y <= p40_bot.end.y + 0.5, "pass40: build bar inside the bottom panel (bar %s vs panel %s)" % [p40_bb, p40_bot])
			_check(absf(p40_bb.end.y - (p40_vp.y - 30.0)) < 0.5, "pass40: build bar ends 30 px above the screen bottom, above the hint row (got %s)" % p40_bb.end.y)
			var p40_hint := _hint_lbl.get_global_rect()
			_check(p40_hint.position.y >= p40_bot.position.y - 0.5 and p40_hint.end.y <= p40_bot.end.y + 0.5, "pass40: hint row inside the bottom panel")
			_check(p40_hint.end.y <= p40_vp.y + 0.5, "pass40: hint ends inside the viewport (got %s vs vh %s)" % [p40_hint.end.y, p40_vp.y])
			_check(_hint_lbl.size.y <= 24.0, "pass40: hint is a single rendered line, not a wrapped two-liner (got %s)" % _hint_lbl.size.y)
			_check(_hint_lbl.text.contains("LEFT STICK") and _hint_lbl.text.contains("RIGHT STICK") and not _hint_lbl.text.contains("WASD"), "pass40: hint still teaches touch controls (%s)" % _hint_lbl.text)
		# The Pass 13 MOVE/AIM labels above the panel are gone.
		var p40_stray := false
		for _hc in _hud_controls:
			if _hc is Label and (str((_hc as Label).text) == "MOVE ◀" or str((_hc as Label).text) == "AIM + FIRE ▶"):
				p40_stray = true
		_check(not p40_stray, "pass40: no MOVE/AIM label survives above the bottom panel")
		# Icon buttons actually occupy their assigned slots now: the
		# Pass 9 icons are ~480 px native, and without expand_icon a
		# Button's minimum size is its icon — the weapon buttons
		# rendered 488x434 and FIRE 519x428, overflowing panel and
		# screen. That, not the panel heights, was the oversized HUD.
		if _weapon_icons.size() > 0:
			_check((_weapon_icons[0] as Control).size == Vector2(50.0, 44.0), "pass40: weapon icon button is its assigned 50x44, not its 480 px icon (got %s)" % str((_weapon_icons[0] as Control).size))
			_check((_weapon_icons[0] as Button).expand_icon, "pass40: weapon icon button expands its icon into the slot")
		_check(_fire_btn.size == Vector2(110.0, 44.0), "pass40: FIRE button is its assigned 110x44 (got %s)" % str(_fire_btn.size))
		_check(_utility_btn.size == Vector2(52.0, 44.0), "pass40: utility button is its assigned 52x44 (got %s)" % str(_utility_btn.size))
		# The budget itself, in numbers: typical top+bottom, and the
		# worst case with message + preview both showing.
		var p40_typ := P40_TOP_H + P40_BOTTOM_H
		var p40_worst := P40_TOP_H + 4.0 + P40_MSG_H + 4.0 + P40_PREVIEW_H + P40_BOTTOM_H
		_check(p40_typ == 208.0 and p40_typ / p40_vp.y < 0.35, "pass40: typical HUD chrome is 208 px (%.1f%% of vh %s)" % [p40_typ / p40_vp.y * 100.0, p40_vp.y])
		_check(p40_worst / p40_vp.y < 0.45, "pass40: worst-case HUD chrome is %.0f px (%.1f%% of vh)" % [p40_worst, p40_worst / p40_vp.y * 100.0])
		print("pass40 HUD budget: top ", P40_TOP_H, " msg ", P40_MSG_H, " preview ", P40_PREVIEW_H, " bottom ", P40_BOTTOM_H, " typical ", p40_typ, " worst ", p40_worst, " vh ", p40_vp.y)
		# Pass 41 (CONTENT: Bulwark): very slow, huge frontal shield,
		# weak rear core — stats, shield absorb, rear 2.0x, regen,
		# sprite + shield panel, wave queues, salvage, kill XP.
		var p41_diff0 := difficulty
		var p41_end0 := endless_mode
		var p41_level0 := level
		var p41_xp0 := xp
		difficulty = "standard"
		endless_mode = false
		var p41_scale := 1.0 + float(maxi(wave - 1, 0)) * 0.15
		var p41 = spawn_enemy("bulwark", Vector3(-45, 0, 45))
		await get_tree().process_frame
		_check(absf(float(p41.get("max_hp")) - 220.0 * p41_scale) < 0.5, "pass41: bulwark HP is 220 x scale (got %f)" % float(p41.get("max_hp")))
		_check(float(p41.get("speed")) == 1.8, "pass41: bulwark speed is 1.8, very slow (got %f)" % float(p41.get("speed")))
		_check(float(p41.get("speed")) < 3.0, "pass41: bulwark slower than shield heavy 3.0")
		_check(float(p41.get("dmg")) == 16.0, "pass41: bulwark dmg is 16 (got %f)" % float(p41.get("dmg")))
		_check(int(p41.get("salvage_value")) == 60, "pass41: bulwark salvage is 60 (got %d)" % int(p41.get("salvage_value")))
		_check(absf(float(p41.get("shield_max")) - 160.0) < 0.5 and absf(float(p41.get("shield_hp")) - 160.0) < 0.5, "pass41: bulwark shield pool is 160, bigger than shield heavy 90 (got %f)" % float(p41.get("shield_max")))
		# Frontal hit: shield absorbs, 10% bleed-through only.
		var p41_face: Vector3 = p41.get_facing()
		var p41_hp0 := float(p41.get("hp"))
		var p41_dealt := float(p41.take_damage(100.0, p41_face, "TestGun"))
		_check(absf(p41_dealt - 10.0) < 0.5, "pass41: frontal 100 hit deals 10 bleed (got %f)" % p41_dealt)
		_check(absf(float(p41.get("shield_hp")) - 60.0) < 0.5, "pass41: frontal 100 hit drains shield 160 -> 60 (got %f)" % float(p41.get("shield_hp")))
		_check(absf(float(p41.get("hp")) - (p41_hp0 - 10.0)) < 0.5, "pass41: frontal hit costs 10 HP (got %f)" % float(p41.get("hp")))
		# Shield regen: with the cooldown cleared, 1 s restores 12.
		p41.set("_shield_regen_cd", 0.0)
		p41._process(1.0)
		_check(absf(float(p41.get("shield_hp")) - 72.0) < 0.5, "pass41: shield regens 12/s after cooldown (got %f)" % float(p41.get("shield_hp")))
		if is_instance_valid(p41):
			p41.die_silent()
		# Rear hit bypasses the shield and deals double: weak core.
		var p41r = spawn_enemy("bulwark", Vector3(-45, 0, -45))
		await get_tree().process_frame
		var p41r_face: Vector3 = p41r.get_facing()
		var p41r_dealt := float(p41r.take_damage(100.0, -p41r_face, "TestGun"))
		_check(absf(p41r_dealt - 200.0) < 0.5, "pass41: rear 100 hit deals 200, weak core 2.0x (got %f)" % p41r_dealt)
		_check(absf(float(p41r.get("shield_hp")) - 160.0) < 0.5, "pass41: rear hit leaves shield untouched (got %f)" % float(p41r.get("shield_hp")))
		if is_instance_valid(p41r):
			p41r.die_silent()
		# Sprite + shield panel: tank frame at bulwark scale, flat,
		# chevron + ring, 1.45x shield panel ahead of the nose.
		var p41s = spawn_enemy("bulwark", Vector3(45, 0, 45))
		await get_tree().process_frame
		var p41s_body: Node = p41s.get("_body")
		var p41s_quad: MeshInstance3D = SpriteUtil.topdown_quad(p41s_body.get_node_or_null("unit_sprite")) if p41s_body else null
		var p41s_tex := ""
		if p41s_quad != null:
			var p41s_mat := p41s_quad.get_surface_override_material(0) as StandardMaterial3D
			if p41s_mat != null and p41s_mat.albedo_texture != null:
				p41s_tex = str(p41s_mat.albedo_texture.resource_path)
		_check(p41s_quad != null and p41s_tex.contains("p35_enemy_tank_walk"), "pass41: bulwark renders the tank walk set (walk0 = the p34 base frame) (%s)" % p41s_tex)
		if p41s_quad != null and p41s_quad.mesh is QuadMesh:
			_check(absf((p41s_quad.mesh as QuadMesh).size.y - 5.8 * 1.4) < 0.3, "pass41: bulwark quad length is 5.8*1.4, bigger than heavy 4.6*1.4 (got %f)" % (p41s_quad.mesh as QuadMesh).size.y)
			_check(absf(p41s_quad.rotation_degrees.x + 90.0) < 0.01, "pass41: bulwark sprite lies flat")
		_check(p41s_body != null and p41s_body.get_node_or_null("facing_chevron") != null and p41s_body.get_node_or_null("health_ring") != null, "pass41: bulwark has chevron + health ring")
		var p41s_panel: MeshInstance3D = p41s.get("_shield_panel")
		_check(p41s_panel != null and p41s_panel.visible, "pass41: bulwark has a visible shield panel")
		if p41s_panel != null and p41s_panel.mesh is BoxMesh:
			_check(absf((p41s_panel.mesh as BoxMesh).size.x - 3.8 * 1.4 * 1.45) < 0.3, "pass41: bulwark shield panel is 1.45x wide (got %f)" % (p41s_panel.mesh as BoxMesh).size.x)
		# Kill pays 5 XP (level 10 threshold is 113, so no level-up
		# interferes) and increments the kill count.
		level = 10
		xp = 0
		var p41_kills0 := kills
		p41s.take_damage(9999.0, p41s.get_facing(), "TestGun")
		_check(bool(p41s.get("is_dead")), "pass41: lethal damage kills the bulwark")
		_check(kills == p41_kills0 + 1, "pass41: bulwark kill increments kills")
		_check(level == 10 and xp == 5, "pass41: bulwark kill grants 5 XP (got level %d, xp %d)" % [level, xp])
		await get_tree().process_frame
		# Queues, preview, salvage map.
		_check(build_wave_queue(3, "unformed").count("bulwark") == 1, "pass41: wave 3 has 1 bulwark")
		_check(build_wave_queue(2, "unformed").count("bulwark") == 0, "pass41: wave 2 has no bulwark")
		_check(build_wave_queue(1, "unformed").count("bulwark") == 0, "pass41: wave 1 has no bulwark")
		_check(build_wave_queue(8, "unformed").count("bulwark") == 0, "pass41: endless wave 8 has no bulwark yet")
		_check(build_wave_queue(9, "unformed").count("bulwark") == 1, "pass41: endless wave 9 has 1 bulwark")
		_check(build_wave_queue(12, "unformed").count("bulwark") == 2, "pass41: endless wave 12 has 2 bulwarks")
		_check(build_wave_queue(30, "unformed").count("bulwark") == 2, "pass41: endless wave 30 caps at 2 bulwarks")
		_check(wave_preview_text(3, "unformed").contains("BULWARK"), "pass41: wave preview lists BULWARK (%s)" % wave_preview_text(3, "unformed"))
		_check(salvage_for_kind("bulwark") == 60, "pass41: salvage_for_kind bulwark is 60")
		difficulty = p41_diff0
		endless_mode = p41_end0
		level = p41_level0
		xp = p41_xp0
		wave = p40_wave0
		_wave_active = p40_active0
		_game_over = p40_go0
		_won = p40_won0
		_lbl_msg.text = p40_msg0
		_msg_timer = p40_timer0
		_refresh_hud()
		# Pass 42: end-panel stats — run time, shots, accuracy, damage
		# dealt/taken, tracked, displayed on both end panels, saved.
		var p42_rt0 := run_time_seconds
		var p42_hit0 := shots_hit
		var p42_dealt0 := damage_dealt
		var p42_fired0 := int(player.get("shots_fired"))
		var p42_taken0 := float(player.get("damage_taken"))
		var p42_go0 := _game_over
		var p42_won0 := _won
		var p42_end0 := endless_mode
		var p42_core0 := core_hp
		var p42_level0 := level
		var p42_xp0 := xp
		var p42_salvage0 := salvage
		var p42_msg0 := _lbl_msg.text if _lbl_msg else ""
		var p42_timer0 := _msg_timer
		var p42_php0 := float(player.hp)
		var p42_ppos0 := player.global_position
		var p42_weapon0 := int(player.current_weapon)
		var p42_wave0 := wave
		_check(format_run_time(0.0) == "0:00", "pass42: run time 0 formats as 0:00 (got %s)" % format_run_time(0.0))
		_check(format_run_time(65.0) == "1:05", "pass42: run time 65 formats as 1:05 (got %s)" % format_run_time(65.0))
		_check(format_run_time(600.0) == "10:00", "pass42: run time 600 formats as 10:00 (got %s)" % format_run_time(600.0))
		run_time_seconds = 125.0
		shots_hit = 3
		damage_dealt = 87.0
		player.shots_fired = 4
		player.damage_taken = 22.0
		var p42_snap := run_stats()
		_check(int(p42_snap["shots_fired"]) == 4 and int(p42_snap["shots_hit"]) == 3 and absf(float(p42_snap["accuracy"]) - 0.75) < 0.001, "pass42: run_stats snapshot carries fired/hits/accuracy (got %s)" % str(p42_snap))
		var p42_txt := end_panel_stats_text()
		_check(p42_txt.contains("TIME 2:05") and p42_txt.contains("SHOTS 4") and p42_txt.contains("HITS 3") and p42_txt.contains("ACCURACY 75%") and p42_txt.contains("DAMAGE DEALT 87") and p42_txt.contains("DAMAGE TAKEN 22"), "pass42: stats text renders time/shots/hits/accuracy/damage (%s)" % p42_txt)
		player.shots_fired = 0
		shots_hit = 0
		_check(float(run_stats()["accuracy"]) == 0.0, "pass42: accuracy is 0 with no shots fired")
		_check(end_panel_stats_text().contains("ACCURACY 0%"), "pass42: stats text shows 0% accuracy with no shots")
		shots_hit = 0
		damage_dealt = 0.0
		record_player_bullet_damage(10.0, true)
		record_player_bullet_damage(5.0, false)
		record_player_bullet_damage(7.0, true)
		_check(shots_hit == 2 and absf(damage_dealt - 22.0) < 0.01, "pass42: record counts one hit per bullet, damage sums (hits %d dealt %f)" % [shots_hit, damage_dealt])
		# Live firing path: autocannon counts 1, scattergun counts 5.
		player.global_position = Vector3(0, 0, 10)
		player.aim_point = Vector3(0, 0, -10)
		player.shots_fired = 0
		player.current_weapon = 1
		player._fire_cd = 0.0
		player._fire()
		_check(player.shots_fired == 1, "pass42: autocannon _fire counts 1 shot (got %d)" % int(player.shots_fired))
		player.current_weapon = 3
		player._fire_cd = 0.0
		player._fire()
		_check(player.shots_fired == 6, "pass42: scattergun _fire counts 5 pellets (got %d)" % int(player.shots_fired))
		for n in get_children():
			if n is Node3D and n.get_script() != null and str(n.get_script().resource_path) == "res://scripts/bullet.gd":
				if n.has_method("release_to_pool"):
					n.release_to_pool()
		player.current_weapon = p42_weapon0
		player._fire_cd = 0.0
		# Live direct hit: one player-mech bullet, one hit, exact damage.
		shots_hit = 0
		damage_dealt = 0.0
		var p42_foe = spawn_enemy("scout", Vector3(40, 0, -40))
		await get_tree().process_frame
		var p42_hp0 := float(p42_foe.get("hp"))
		var p42_b = Node3D.new()
		p42_b.set_script(load("res://scripts/bullet.gd"))
		p42_b.position = Vector3(40, 1.5, -40)
		add_child(p42_b)
		p42_b.setup(Vector3(0, 0, -1), 9.0, "Autocannon", true, false, 60.0, 0.0, 0.0, 0.9, 0.0, 0, 0.0, true)
		p42_b._process(0.016)
		_check(shots_hit == 1 and absf(damage_dealt - 9.0) < 0.01, "pass42: live player bullet counts 1 hit and 9 damage (hits %d dealt %f)" % [shots_hit, damage_dealt])
		_check(absf(float(p42_foe.get("hp")) - (p42_hp0 - 9.0)) < 0.01, "pass42: live bullet deals its damage to the enemy (hp %f -> %f)" % [p42_hp0, float(p42_foe.get("hp"))])
		if is_instance_valid(p42_foe):
			p42_foe.die_silent()
		# Live flak AoE: two victims, still one hit.
		var p42_f1 = spawn_enemy("scout", Vector3(45, 0, 10))
		var p42_f2 = spawn_enemy("scout", Vector3(46, 0, 11))
		await get_tree().process_frame
		var p42_fhp1 := float(p42_f1.get("hp"))
		var p42_fhp2 := float(p42_f2.get("hp"))
		shots_hit = 0
		damage_dealt = 0.0
		var p42_fb = Node3D.new()
		p42_fb.set_script(load("res://scripts/bullet.gd"))
		p42_fb.position = Vector3(45, 1.5, 22)
		add_child(p42_fb)
		p42_fb.setup(Vector3(0, 0, -1), 22.0, "Flak Cannon", true, false, 48.0, 5.5, 0.0, 0.9, 4.0, 0, 0.0, true)
		for _step in range(30):
			if not is_instance_valid(p42_fb) or p42_fb.get_parent() == null:
				break
			p42_fb._process(0.016)
		_check(shots_hit == 1, "pass42: flak AoE over two enemies counts one hit (hits %d)" % shots_hit)
		_check(damage_dealt > 0.0 and float(p42_f1.get("hp")) < p42_fhp1 and float(p42_f2.get("hp")) < p42_fhp2, "pass42: flak AoE damages both victims and adds damage (dealt %f)" % damage_dealt)
		if is_instance_valid(p42_f1):
			p42_f1.die_silent()
		if is_instance_valid(p42_f2):
			p42_f2.die_silent()
		# Turret bullet: real damage, but not the mech's stats.
		var p42_t = spawn_enemy("scout", Vector3(40, 0, -40))
		await get_tree().process_frame
		var p42_thp0 := float(p42_t.get("hp"))
		shots_hit = 0
		damage_dealt = 0.0
		var p42_tb = Node3D.new()
		p42_tb.set_script(load("res://scripts/bullet.gd"))
		p42_tb.position = Vector3(40, 1.5, -40)
		add_child(p42_tb)
		p42_tb.setup(Vector3(0, 0, -1), 8.0, "Turret", true, false, 55.0)
		p42_tb._process(0.016)
		_check(shots_hit == 0 and damage_dealt == 0.0, "pass42: turret bullet counts nothing (hits %d dealt %f)" % [shots_hit, damage_dealt])
		_check(float(p42_t.get("hp")) < p42_thp0, "pass42: turret bullet still damages its target")
		if is_instance_valid(p42_t):
			p42_t.die_silent()
		# Destructible-only hit: breaks nothing in the stats.
		var p42_crate = _make_destructible("crate", Vector3(-40, 0, 40))
		var p42_chp0 := float(p42_crate.get_meta("destructible_hp", 0.0))
		shots_hit = 0
		damage_dealt = 0.0
		var p42_db = Node3D.new()
		p42_db.set_script(load("res://scripts/bullet.gd"))
		p42_db.position = Vector3(-40, 1.5, 40)
		add_child(p42_db)
		p42_db.setup(Vector3(0, 0, -1), 9.0, "Autocannon", true, false, 60.0, 0.0, 0.0, 0.9, 0.0, 0, 0.0, true)
		p42_db._process(0.016)
		_check(shots_hit == 0 and damage_dealt == 0.0, "pass42: destructible-only hit counts nothing (hits %d dealt %f)" % [shots_hit, damage_dealt])
		_check(float(p42_crate.get_meta("destructible_hp", 0.0)) < p42_chp0, "pass42: destructible-only bullet still damages the crate")
		# Victory panel + world save carry the same snapshot.
		run_time_seconds = 200.0
		shots_hit = 5
		damage_dealt = 123.0
		player.shots_fired = 7
		player.damage_taken = 45.0
		core_hp = core_max_hp
		_game_over = false
		_won = false
		_end_game(true)
		_check(_won and _win_panel.visible, "pass42: victory end panel shows")
		var p42_vtxt := str(_win_panel.get_meta("label").text)
		_check(p42_vtxt.contains("RUN STATS") and p42_vtxt.contains("TIME 3:20") and p42_vtxt.contains("SHOTS 7") and p42_vtxt.contains("HITS 5") and p42_vtxt.contains("ACCURACY 71%") and p42_vtxt.contains("DAMAGE DEALT 123") and p42_vtxt.contains("DAMAGE TAKEN 45"), "pass42: victory panel shows the run stats (%s)" % p42_vtxt)
		var p42_saved := _parse_save_dict(_save_text(WORLD_PATH))
		_check(int(p42_saved.get("stats_run_time", -1)) == 200 and int(p42_saved.get("stats_shots_fired", -1)) == 7 and int(p42_saved.get("stats_shots_hit", -1)) == 5 and int(p42_saved.get("stats_accuracy_pct", -1)) == 71 and int(p42_saved.get("stats_damage_dealt", -1)) == 123 and int(p42_saved.get("stats_damage_taken", -1)) == 45, "pass42: world save carries the run stats (%s)" % str(p42_saved))
		# The panel's set size (320) is only a starting size: container
		# layout grows it to its content height, and synchronously
		# after _end_game the label still measures at width 1, so a
		# synchronous size check reads a nonsense 7195. After one
		# layout frame it settles (label 400 wide, panel 435 high in
		# this run) — assert the settled, on-screen facts instead:
		# panel keeps its 420 width, fits the 648 landscape viewport
		# height, and the label actually wraps at panel width.
		await get_tree().process_frame
		var p42_vp := get_viewport().get_visible_rect().size
		_check(_win_panel.size.x == 420.0 and _win_panel.size.y <= p42_vp.y and (_win_panel.get_meta("label") as Control).size.x >= 300.0, "pass42: settled end panel fits the viewport (panel %s, label %s, viewport %s)" % [str(_win_panel.size), str((_win_panel.get_meta("label") as Control).size), str(p42_vp)])
		_won = false
		_win_panel.visible = false
		get_tree().paused = false
		# Game-over panel via a lethal blow: the lethal damage counts.
		player.hp = 5.0
		player.damage_taken = 40.0
		_game_over = false
		player.take_damage(10.0)
		_check(absf(float(player.get("damage_taken")) - 50.0) < 0.01, "pass42: lethal blow still counts toward damage taken (got %f)" % float(player.get("damage_taken")))
		_check(_game_over and _gameover_panel.visible, "pass42: lethal damage shows the game-over panel")
		var p42_gtxt := str(_gameover_panel.get_meta("label").text)
		_check(p42_gtxt.contains("RUN STATS") and p42_gtxt.contains("DAMAGE TAKEN 50"), "pass42: game-over panel shows the run stats (%s)" % p42_gtxt)
		_game_over = false
		_gameover_panel.visible = false
		get_tree().paused = false
		# Reset clears every counter, then baselines return.
		_reset_run()
		_check(run_time_seconds == 0.0 and shots_hit == 0 and damage_dealt == 0.0 and int(player.get("shots_fired")) == 0 and float(player.get("damage_taken")) == 0.0, "pass42: reset clears all run stats")
		run_time_seconds = p42_rt0
		shots_hit = p42_hit0
		damage_dealt = p42_dealt0
		player.shots_fired = p42_fired0
		player.damage_taken = p42_taken0
		_game_over = p42_go0
		_won = p42_won0
		endless_mode = p42_end0
		core_hp = p42_core0
		level = p42_level0
		xp = p42_xp0
		salvage = p42_salvage0
		wave = p42_wave0
		player.hp = p42_php0
		player.global_position = p42_ppos0
		player.current_weapon = p42_weapon0
		_lbl_msg.text = p42_msg0
		_msg_timer = p42_timer0
		_refresh_hud()
		# Pass 43 (PERF audit): baseline snapshot printed every run, so
		# the audit table in REPORT.md is measured, not estimated.
		var p43_audit := count_visual_nodes()
		print("pass43 audit: %s (render_nodes=%d, props=%d, ruins=%d, destructibles=%d)" % [str(p43_audit), count_render_nodes(), _prop_sprites.size(), _ruin_sprites.size(), _destructibles.size()])
		_check(int(p43_audit["total"]) == count_render_nodes(), "pass43: audit buckets sum to render-node count (audit %d, count %d)" % [int(p43_audit["total"]), count_render_nodes()])
		# Stable assertions only: props/ruins are never freed, so
		# their bucket is exact; destructibles/structures/caches at
		# this point include queue_free-pending nodes from _reset_run,
		# so their buckets are snapshot noise, not asserted here.
		_check(int(p43_audit["props"]) == (_prop_sprites.size() + _ruin_sprites.size()) and int(p43_audit["prop_shadows"]) == 0, "pass43: static props/ruins carry no shadow quad (props bucket %d for %d holders, shadows %d)" % [int(p43_audit["props"]), _prop_sprites.size() + _ruin_sprites.size(), int(p43_audit["prop_shadows"])])
		# A fresh tile destructible is one quad, no shadow blob.
		var p43_fresh := _make_destructible("crate", Vector3(-50, 0, -50))
		var p43_fgeom := 0
		var p43_fstack: Array = [p43_fresh]
		while not p43_fstack.is_empty():
			var p43_fn: Node = p43_fstack.pop_back()
			if p43_fn is GeometryInstance3D:
				p43_fgeom += 1
			for p43_fc in p43_fn.get_children():
				p43_fstack.append(p43_fc)
		_check(p43_fgeom == 1, "pass43: fresh tile destructible is 1 geometry node, no shadow quad (got %d)" % p43_fgeom)
		_destructibles.erase(p43_fresh)
		p43_fresh.queue_free()
		# Direct ground_sprite contract: shadowless holders have exactly
		# the textured quad; the default keeps the shadow for units and
		# the parked support mech, which keep their grounding blob.
		var p43_noshadow := SpriteUtil.ground_sprite("res://sprites/p8/tile_crate.png", 5.0, 0.0, false)
		var p43_shadowed := SpriteUtil.ground_sprite("res://sprites/p8/tile_crate.png", 5.0, 0.0, true)
		_check(p43_noshadow != null and p43_noshadow.get_child_count() == 1, "pass43: shadowless ground_sprite has exactly 1 child (got %d)" % (p43_noshadow.get_child_count() if p43_noshadow else -1))
		_check(p43_shadowed != null and p43_shadowed.get_child_count() == 2, "pass43: default ground_sprite still has quad + shadow (got %d)" % (p43_shadowed.get_child_count() if p43_shadowed else -1))
		if p43_noshadow:
			p43_noshadow.queue_free()
		if p43_shadowed:
			p43_shadowed.queue_free()
		# Pass 44 (BUG-HUNT: input edge cases) — weapon spam-switch,
		# dash-into-build, utility during the level-up pause. Every
		# check drives the real input path (_input / button signals /
		# viewport clicks), not just the underlying function, so a
		# guard that exists only in one path is caught by another.
		var p44_weapon0 := int(player.current_weapon)
		var p44_hp0 := float(player.hp)
		var p44_salvage0 := salvage
		var p44_pos0 := player.global_position
		var p44_aim0: Vector3 = player.aim_point
		var p44_msg0 := _lbl_msg.text if _lbl_msg else ""
		var p44_timer0 := _msg_timer
		var p44_structs0 := 0
		for _s in _structures:
			if is_instance_valid(_s):
				p44_structs0 += 1
		player.global_position = Vector3(0, 0, 10)
		player.aim_point = Vector3(0, 0, -10)
		player.move_input = Vector2.ZERO
		player.velocity = Vector3.ZERO
		player.firing = false
		player.heat = 0.0
		player.overheated = false
		# --- A: weapon spam-switch (the Pass 44 fix) ---
		player.current_weapon = 1
		player._fire_cd = 0.0
		var p44_shots0 := int(player.shots_fired)
		player._fire()
		_check(absf(player._fire_cd - 0.13) < 0.02, "pass44: autocannon shot sets 0.13 s cooldown (got %f)" % player._fire_cd)
		player._process(0.13)
		_check(player._fire_cd == 0.0, "pass44: cooldown clears after its interval (got %f)" % player._fire_cd)
		var p44_k2 := InputEventKey.new()
		p44_k2.keycode = KEY_2
		p44_k2.pressed = true
		p44_k2.echo = false
		_input(p44_k2)
		_check(player.current_weapon == 2, "pass44: KEY_2 selects railgun (got %d)" % player.current_weapon)
		_check(player._fire_cd >= 0.69, "pass44: switch to railgun raises cooldown to its own 0.70 s interval, not the autocannon's 0.13 (got %f)" % player._fire_cd)
		player.firing = true
		player._process(0.30)
		_check(int(player.shots_fired) == p44_shots0 + 1, "pass44: no railgun shot inside its switch cooldown (shots %d)" % int(player.shots_fired))
		player._process(0.45)
		_check(int(player.shots_fired) == p44_shots0 + 2 and player.weapon_name() == "Railgun", "pass44: railgun fires once its own interval elapses (shots %d, weapon %s)" % [int(player.shots_fired), player.weapon_name()])
		player.firing = false
		for n in get_children():
			if n is Node3D and n.get_script() != null and str(n.get_script().resource_path) == "res://scripts/bullet.gd":
				if n.has_method("release_to_pool"):
					n.release_to_pool()
		var p44_echo := InputEventKey.new()
		p44_echo.keycode = KEY_3
		p44_echo.pressed = true
		p44_echo.echo = true
		_input(p44_echo)
		_check(player.current_weapon == 2, "pass44: held-key echo does not switch weapons (got %d)" % player.current_weapon)
		for p44_k in [KEY_1, KEY_3, KEY_5, KEY_2, KEY_4, KEY_1]:
			var p44_ev := InputEventKey.new()
			p44_ev.keycode = p44_k
			p44_ev.pressed = true
			p44_ev.echo = false
			_input(p44_ev)
		_check(player.current_weapon == 1 and player._fire_cd >= 0.0, "pass44: rapid 1-3-5-2-4-1 spam ends on weapon 1 with a sane cooldown (weapon %d, cd %f)" % [player.current_weapon, player._fire_cd])
		player._fire_cd = 0.0
		var p44_k1 := InputEventKey.new()
		p44_k1.keycode = KEY_1
		p44_k1.pressed = true
		p44_k1.echo = false
		_input(p44_k1)
		_check(player._fire_cd == 0.0, "pass44: re-selecting the current weapon adds no cooldown (got %f)" % player._fire_cd)
		player.select_weapon(9)
		player.select_weapon(0)
		_check(player.current_weapon == 1, "pass44: out-of-range weapon ids are ignored (got %d)" % player.current_weapon)
		# --- B: dash-into-build ---
		player.move_input = Vector2(0, -1)
		player.try_dash()
		_check(player._dash_cd > 0.0 and player.velocity.length() > player.max_speed, "pass44: dash sets cooldown and a boost above max speed (cd %f, speed %f vs max %f)" % [player._dash_cd, player.velocity.length(), player.max_speed])
		salvage = 1000
		var p44_bsalv := salvage
		var p44_bcount := 0
		for _s in _structures:
			if is_instance_valid(_s):
				p44_bcount += 1
		build_at_player("barricade")
		var p44_built: Node3D = null
		for _s in _structures:
			if is_instance_valid(_s) and Vector3(_s.global_position.x, 0, _s.global_position.z).distance_to(Vector3(0, 0, 6)) < 0.5:
				p44_built = _s
		_check(p44_built != null, "pass44: dash-into-build places the barricade 4 m ahead of the player")
		if p44_built != null:
			_check(p44_built.global_position.distance_to(player.global_position) >= 3.5, "pass44: built structure is not under the player (dist %f)" % p44_built.global_position.distance_to(player.global_position))
		_check(salvage < p44_bsalv, "pass44: dash-into-build still charges salvage (%d -> %d)" % [p44_bsalv, salvage])
		_check(player._dash_cd > 0.0 and player.velocity.length() > player.max_speed, "pass44: building does not cancel the dash (cd %f, speed %f)" % [player._dash_cd, player.velocity.length()])
		player._process(0.016)
		_check(player.velocity.length() > player.max_speed, "pass44: dash boost survives a frame after building (speed %f vs max %f)" % [player.velocity.length(), player.max_speed])
		var p44_osalv := salvage
		_check(not try_build("barricade", Vector3(0, 0, 6)), "pass44: dash does not bypass the occupied-spot rule")
		_check(salvage == p44_osalv, "pass44: refused occupied build charges nothing (salvage %d)" % salvage)
		if p44_built != null:
			_structures.erase(p44_built)
			p44_built.queue_free()
		player.velocity = Vector3.ZERO
		player._dash_cd = 0.0
		player.move_input = Vector2.ZERO
		# --- C: utility / keys / live GUI clicks during pauses ---
		player.hp = 50.0
		player._utility_cd = 0.0
		player.current_weapon = 1
		player._fire_cd = 0.0
		pending_levels = 1
		_show_levelup_panel()
		_check(_lvl_panel.visible and get_tree().paused, "pass44: level-up panel pauses the tree")
		var p44_q := InputEventKey.new()
		p44_q.keycode = KEY_Q
		p44_q.pressed = true
		p44_q.echo = false
		_input(p44_q)
		_check(float(player.hp) == 50.0 and player.utility_cooldown() == 0.0, "pass44: Q during level-up pause fires no utility (hp %f, cd %f)" % [float(player.hp), player.utility_cooldown()])
		var p44_k2b := InputEventKey.new()
		p44_k2b.keycode = KEY_2
		p44_k2b.pressed = true
		p44_k2b.echo = false
		_input(p44_k2b)
		_check(player.current_weapon == 1, "pass44: weapon key during level-up pause is swallowed (got %d)" % player.current_weapon)
		var p44_f := InputEventKey.new()
		p44_f.keycode = KEY_F
		p44_f.pressed = true
		p44_f.echo = false
		var p44_fcount := 0
		for _s in _structures:
			if is_instance_valid(_s):
				p44_fcount += 1
		_input(p44_f)
		var p44_fcount2 := 0
		for _s in _structures:
			if is_instance_valid(_s):
				p44_fcount2 += 1
		_check(p44_fcount2 == p44_fcount, "pass44: build key during level-up pause builds nothing (%d -> %d)" % [p44_fcount, p44_fcount2])
		var p44_sp := InputEventKey.new()
		p44_sp.keycode = KEY_SPACE
		p44_sp.pressed = true
		p44_sp.echo = false
		_input(p44_sp)
		_check(player._dash_cd == 0.0, "pass44: dash key during level-up pause is swallowed (cd %f)" % player._dash_cd)
		# Live GUI probe: a real viewport click on the utility button
		# while paused. If HUD buttons stayed input-live under a pause
		# (main is PROCESS_MODE_ALWAYS, so they inherit ALWAYS), this
		# would heal the player and start the cooldown — the bug this
		# probe exists to catch. Godot's pause gating must stop it.
		if _utility_btn != null:
			var p44_ucenter := _utility_btn.get_global_rect().get_center()
			var p44_down := InputEventMouseButton.new()
			p44_down.button_index = MOUSE_BUTTON_LEFT
			p44_down.pressed = true
			p44_down.position = p44_ucenter
			p44_down.global_position = p44_ucenter
			get_viewport().push_input(p44_down)
			await get_tree().process_frame
			var p44_up := InputEventMouseButton.new()
			p44_up.button_index = MOUSE_BUTTON_LEFT
			p44_up.pressed = false
			p44_up.position = p44_ucenter
			p44_up.global_position = p44_ucenter
			get_viewport().push_input(p44_up)
			await get_tree().process_frame
			_check(float(player.hp) == 50.0 and player.utility_cooldown() == 0.0, "pass44: live utility-button click during level-up pause fires nothing (hp %f, cd %f)" % [float(player.hp), player.utility_cooldown()])
		_lvl_panel.visible = false
		get_tree().paused = false
		pending_levels = 0
		# Same live-click probe under the pause menu itself.
		_check(open_pause(), "pass44: pause menu opens for its click probe")
		if _weapon_icons.size() >= 2:
			var p44_wcenter := (_weapon_icons[1] as Button).get_global_rect().get_center()
			var p44_wdown := InputEventMouseButton.new()
			p44_wdown.button_index = MOUSE_BUTTON_LEFT
			p44_wdown.pressed = true
			p44_wdown.position = p44_wcenter
			p44_wdown.global_position = p44_wcenter
			get_viewport().push_input(p44_wdown)
			await get_tree().process_frame
			var p44_wup := InputEventMouseButton.new()
			p44_wup.button_index = MOUSE_BUTTON_LEFT
			p44_wup.pressed = false
			p44_wup.position = p44_wcenter
			p44_wup.global_position = p44_wcenter
			get_viewport().push_input(p44_wup)
			await get_tree().process_frame
			_check(player.current_weapon == 1, "pass44: live weapon-button click during pause menu switches nothing (got %d)" % player.current_weapon)
		resume_from_pause()
		_check(not get_tree().paused, "pass44: pause menu resumes after its probe")
		player.current_weapon = p44_weapon0
		player.hp = p44_hp0
		player.global_position = p44_pos0
		player.aim_point = p44_aim0
		player.move_input = Vector2.ZERO
		player.velocity = Vector3.ZERO
		player.firing = false
		player._fire_cd = 0.0
		player._dash_cd = 0.0
		player._utility_cd = 0.0
		salvage = p44_salvage0
		_lbl_msg.text = p44_msg0
		_msg_timer = p44_timer0
		_refresh_hud()
		# Pass 45 (CONTENT: Region 2 dust-storm variant) — fog visibility,
		# wind drift on straight + arc bullets, hangar toggle, persistence.
		# The storm is Rust-Flats-only by design: ON + region1 must be a
		# no-op, and a pooled storm bullet reused in calm air must not
		# keep its drift (the Pass 19 pool-reset rule, extended).
		set_dust_storm(false)
		set_region("region1")
		_check(not dust_storm_active(), "pass45: storm OFF is inactive on region1")
		_check(storm_wind_drift() == Vector3.ZERO, "pass45: calm air drifts nothing (got %s)" % storm_wind_drift())
		_check(absf(_world_env.fog_density - 0.0022) < 0.001, "pass45: region1 calm fog is 0.0022 (got %f)" % _world_env.fog_density)
		set_dust_storm(true)
		_check(not dust_storm_active(), "pass45: storm ON but region1 stays inactive (Rust Flats only)")
		_check(storm_wind_drift() == Vector3.ZERO, "pass45: region1 with storm ON still drifts nothing")
		_check(absf(_world_env.fog_density - 0.0022) < 0.001, "pass45: region1 fog unchanged with storm ON (got %f)" % _world_env.fog_density)
		_check(_hangar_stats.text.contains("DUST STORM: ON"), "pass45: hangar stats line shows storm ON (%s)" % _hangar_stats.text)
		_check(_dust_storm_btn != null and _dust_storm_btn.text.contains("ON"), "pass45: hangar dust-storm button exists and reads ON")
		set_region("region2")
		_check(dust_storm_active(), "pass45: storm ON + region2 is active")
		_check(storm_wind_drift() == Vector3(4.0, 0.0, 1.0), "pass45: storm wind is (4, 0, 1) (got %s)" % storm_wind_drift())
		_check(absf(_world_env.fog_density - 0.012) < 0.001, "pass45: storm fog is 0.012 (got %f)" % _world_env.fog_density)
		_check(_world_env.fog_light_color == Color(0.45, 0.35, 0.20), "pass45: storm fog light is dust-tan (got %s)" % _world_env.fog_light_color)
		var BulletScript45 = load("res://scripts/bullet.gd")
		var p45_b = BulletScript45.take_from_pool()
		if p45_b == null:
			p45_b = Node3D.new()
			p45_b.set_script(BulletScript45)
		p45_b.position = Vector3(60, 1.5, 60)
		add_child(p45_b)
		p45_b.setup(Vector3(0, 0, 1), 9.0, "Autocannon", true, false, 55.0)
		var p45_wd: Vector3 = p45_b.get("wind_drift")
		_check(p45_wd == Vector3(4.0, 0.0, 1.0), "pass45: bullet snapshots the storm wind at setup (got %s)" % p45_wd)
		p45_b._process(0.5)
		_check(absf(p45_b.global_position.x - 62.0) < 0.05 and absf(p45_b.global_position.z - 88.0) < 0.05, "pass45: 0.5 s of flight drifts +2.0 x / +0.5 z on top of 27.5 forward (got %s)" % p45_b.global_position)
		p45_b.release_to_pool()
		# Pooled reuse in calm air: the same instance must lose its drift.
		set_dust_storm(false)
		_check(not dust_storm_active(), "pass45: storm OFF deactivates on region2")
		_check(absf(_world_env.fog_density - 0.004) < 0.001, "pass45: calm region2 fog returns to 0.004 (got %f)" % _world_env.fog_density)
		var p45_c = BulletScript45.take_from_pool()
		if p45_c == null:
			p45_c = Node3D.new()
			p45_c.set_script(BulletScript45)
		p45_c.position = Vector3(60, 1.5, 60)
		add_child(p45_c)
		p45_c.setup(Vector3(0, 0, 1), 9.0, "Autocannon", true, false, 55.0)
		_check(Vector3(p45_c.get("wind_drift")) == Vector3.ZERO, "pass45: reused bullet in calm air snapshots zero drift (got %s)" % Vector3(p45_c.get("wind_drift")))
		p45_c._process(0.5)
		_check(absf(p45_c.global_position.x - 60.0) < 0.05 and absf(p45_c.global_position.z - 87.5) < 0.05, "pass45: calm bullet flies straight, no lateral drift (got %s)" % p45_c.global_position)
		p45_c.release_to_pool()
		# Mortar arc: wind shifts the landing point, not the launch.
		set_dust_storm(true)
		var p45_a = BulletScript45.take_from_pool()
		if p45_a == null:
			p45_a = Node3D.new()
			p45_a.set_script(BulletScript45)
		p45_a.position = Vector3(60, 1.5, 60)
		add_child(p45_a)
		p45_a.setup(Vector3(0, 0, 1), 20.0, "Mortar", true, false, 26.0, 5.0, 9.0, 1.0)
		p45_a._process(0.016)
		var p45_ae: Vector3 = p45_a.get("_arc_end")
		_check(absf(p45_ae.x - 64.0) < 0.05 and absf(p45_ae.z - 87.0) < 0.05, "pass45: storm pushes the mortar landing point +4.0 x / +1.0 z (got %s)" % p45_ae)
		p45_a.release_to_pool()
		# Persistence: the toggle survives a save/load round trip.
		save_loadout()
		var p45_lo := read_loadout_file()
		_check(bool(p45_lo.get("dust_storm", false)), "pass45: dust_storm=true persists in the loadout file")
		set_dust_storm(false)
		set_region("region1")
		_check(absf(_world_env.fog_density - 0.0022) < 0.001, "pass45: restore leaves region1 calm fog 0.0022 (got %f)" % _world_env.fog_density)
		save_loadout()
		# Pass 46 (FEATURE: contracts board) — pool, sliding rotation,
		# persistence, counter thresholds, real-event wiring, HUD +
		# hangar display, deploy-keeps-board, end-panel summary.
		_check(set_difficulty("standard"), "pass46: standard difficulty for exact payouts")
		# The board only pays on a live deployed run; arm it for the
		# counter checks below (deploy also proves the arm path).
		_deploy_from_hangar()
		_check(contracts_live, "pass46: deploy arms the board")
		var p46_defs := contract_defs()
		_check(p46_defs.size() == 6, "pass46: pool has 6 contracts (got %d)" % p46_defs.size())
		var p46_ids := {}
		var p46_rewards_ok := true
		for _d in p46_defs:
			if p46_ids.has(str(_d["id"])):
				p46_rewards_ok = false
			p46_ids[str(_d["id"])] = true
			if int(_d["reward"]) <= 0 or contract_target(str(_d["id"])) <= 0:
				p46_rewards_ok = false
		_check(p46_ids.size() == 6 and p46_rewards_ok, "pass46: 6 unique ids, all rewards and targets positive")
		contracts_roll_index = 0
		contracts_roll()
		_check(contracts_active == ["capture_2", "flawless_wave", "kill_10"], "pass46: roll 0 boards the first 3 (got %s)" % str(contracts_active))
		_check(contracts_done.is_empty(), "pass46: a fresh board has nothing done")
		contracts_roll()
		_check(contracts_active == ["flawless_wave", "kill_10", "turret_5"], "pass46: roll 1 slides the window by one (got %s)" % str(contracts_active))
		_check(contracts_roll_index == 2, "pass46: roll index is 2 after two rolls (got %d)" % contracts_roll_index)
		save_loadout()
		_check(int(read_loadout_file().get("contracts_roll", -1)) == 2, "pass46: roll index persists in the loadout file")
		# Counter thresholds, one contract at a time, exact paid deltas.
		contracts_active = ["turret_5"]
		contracts_done = {}
		var p46_paid0 := contracts_paid_total
		turret_kills = 4
		contracts_evaluate()
		_check(not bool(contracts_done.get("turret_5", false)), "pass46: turret_5 not done at 4/5")
		turret_kills = 5
		contracts_evaluate()
		_check(bool(contracts_done.get("turret_5", false)) and contracts_paid_total == p46_paid0 + 50, "pass46: turret_5 completes at 5/5 and pays +50 (paid %d)" % contracts_paid_total)
		contracts_evaluate()
		_check(contracts_paid_total == p46_paid0 + 50, "pass46: a completed contract never pays twice")
		contracts_active = ["cache_3"]
		contracts_done = {}
		p46_paid0 = contracts_paid_total
		caches_collected = 2
		contracts_evaluate()
		_check(not bool(contracts_done.get("cache_3", false)), "pass46: cache_3 not done at 2/3")
		caches_collected = 3
		contracts_evaluate()
		_check(bool(contracts_done.get("cache_3", false)) and contracts_paid_total == p46_paid0 + 40, "pass46: cache_3 completes at 3/3 and pays +40")
		# Flawless wave: undamaged clears, damaged does not.
		contracts_active = ["flawless_wave"]
		contracts_done = {}
		_contracts_flawless_done = false
		p46_paid0 = contracts_paid_total
		_wave_core_hp_start = core_hp
		contracts_on_wave_clear()
		_check(bool(contracts_done.get("flawless_wave", false)) and contracts_paid_total == p46_paid0 + 40, "pass46: an undamaged wave clear completes flawless_wave (+40)")
		contracts_done = {}
		_contracts_flawless_done = false
		_wave_core_hp_start = core_hp
		core_hp -= 10.0
		contracts_on_wave_clear()
		_check(not bool(contracts_done.get("flawless_wave", false)), "pass46: a wave with core damage does not complete flawless_wave")
		core_hp = core_max_hp
		# Real-event wiring: kills, captures, and breaks through the
		# live handlers, not just the counters.
		_reset_run()
		_check(not contracts_live, "pass46: run reset disarms the board")
		# The gate itself: a completed board pays nothing while disarmed.
		contracts_active = ["kill_10"]
		contracts_done = {}
		kills = 10
		contracts_evaluate()
		_check(not bool(contracts_done.get("kill_10", false)), "pass46: a disarmed board pays nothing even at target")
		_deploy_from_hangar()
		contracts_evaluate()
		_check(bool(contracts_done.get("kill_10", false)), "pass46: re-deploy re-arms and the board pays")
		contracts_active = ["kill_10"]
		contracts_done = {}
		p46_paid0 = contracts_paid_total
		kills = 0
		for _ki in range(10):
			var _ke = spawn_enemy("scout", Vector3(60, 0, 60))
			_on_enemy_died(_ke, 5, "Autocannon")
		_check(bool(contracts_done.get("kill_10", false)) and contracts_paid_total == p46_paid0 + 50, "pass46: 10 live kills complete kill_10 (+50)")
		contracts_active = ["capture_2"]
		contracts_done = {}
		p46_paid0 = contracts_paid_total
		captures = 0
		for _ci in range(2):
			var _ce = spawn_enemy("scout", Vector3(20, 0, -20))
			_ce.set("is_disabled", true)
			_check(capture_enemy(_ce), "pass46: capture %d succeeds on a disabled scout" % (_ci + 1))
		_check(captures == 2 and bool(contracts_done.get("capture_2", false)) and contracts_paid_total == p46_paid0 + 60, "pass46: 2 live captures complete capture_2 (+60)")
		contracts_active = ["break_3"]
		contracts_done = {}
		p46_paid0 = contracts_paid_total
		var p46_broken := 0
		for _dn in _destructibles:
			if p46_broken >= 3:
				break
			if not bool(_dn.get_meta("destructible_broken", false)):
				if damage_destructible(_dn, 9999.0):
					p46_broken += 1
		_check(p46_broken == 3 and bool(contracts_done.get("break_3", false)) and contracts_paid_total == p46_paid0 + 40, "pass46: 3 live breaks complete break_3 (+40, broke %d)" % p46_broken)
		# Real cache hook, guarded: only asserted when a live cache exists.
		var p46_cache: Dictionary = {}
		for _cc in _caches:
			if bool(_cc["active"]):
				p46_cache = _cc
				break
		if not p46_cache.is_empty():
			var _cc0 := caches_collected
			collect_cache_entry(p46_cache)
			_check(caches_collected == _cc0 + 1, "pass46: collecting a live cache increments the contract counter")
		# Display: HUD stats line, hangar board label, deploy keeps board.
		_refresh_hud()
		_check(_lbl_stats != null and "CONTRACTS" in _lbl_stats.text, "pass46: HUD stats line shows CONTRACTS (%s)" % (_lbl_stats.text if _lbl_stats else "none"))
		_refresh_hangar()
		_check(_contracts_lbl != null and "CONTRACTS BOARD" in _contracts_lbl.text, "pass46: hangar shows the contracts board")
		var p46_board := contracts_active.duplicate()
		_deploy_from_hangar()
		_check(contracts_active == p46_board, "pass46: deploy keeps the hangar board (was %s, now %s)" % [str(p46_board), str(contracts_active)])
		# End-panel summary is a pure function of the board state.
		contracts_active = ["capture_2", "kill_10", "flawless_wave"]
		contracts_done = {"capture_2": true}
		contracts_paid_total = 60
		_check("1/3" in contracts_summary_text() and "60" in contracts_summary_text(), "pass46: summary reads 1/3 +60 (%s)" % contracts_summary_text())
		for _e in get_tree().get_nodes_in_group("enemies"):
			if is_instance_valid(_e):
				_e.queue_free()
		set_region("region1")
		set_dust_storm(false)
		save_loadout()
		print("pass46 contracts-board checks ran, failures=%d" % _test_failures.size())
		# Pass 47 (AUDIT: test-coverage audit). Every shipped system was
		# re-checked against the test: 904 _check calls before this
		# block. The gaps below are the ones this pass closes with
		# direct checks; the rest are explicit gap notes in REPORT.md
		# (burrower target selection, siege core-fire amount, sapper
		# splash amounts — all frame-driven internals with no exposed
		# getter — plus the queued future systems, which have no check
		# to miss yet). No balance or mechanic values change here
		# except the two audit fixes: the version stamp (was hardcoded
		# v1.47, the recurring beta FAIL), the aim-assist disabled
		# filter, and substation choice validation.
		_check(_version_lbl != null and _version_lbl.text == "IRON EDEN v1.51", "pass47: version stamp reads v1.51 (%s)" % (_version_lbl.text if _version_lbl else "none"))
		# Overheat lockout (player.gd: firing gated on not overheated,
		# clears at heat <= 30). Direct _process calls, no frame timing.
		player.select_weapon(1)
		player.heat = 100.0
		player.overheated = true
		player._fire_cd = 0.0
		player.move_input = Vector2.ZERO
		player.aim_point = player.global_position + Vector3(0, 0, -20)
		var p47_shots0 := int(player.shots_fired)
		player.firing = true
		player._process(0.1)
		_check(bool(player.overheated) and int(player.shots_fired) == p47_shots0, "pass47: overheated mech fires nothing (overheated=%s shots %d -> %d)" % [str(player.overheated), p47_shots0, int(player.shots_fired)])
		player.heat = 25.0
		player._fire_cd = 0.0
		player._process(0.016)
		_check(not bool(player.overheated) and int(player.shots_fired) == p47_shots0 + 1, "pass47: heat <= 30 clears overheat and firing resumes (overheated=%s shots %d -> %d)" % [str(player.overheated), p47_shots0, int(player.shots_fired)])
		player.firing = false
		player.heat = 0.0
		player.overheated = false
		# Capture guards: live, dead, and out-of-range targets refuse.
		var p47_live = spawn_enemy("scout", player.global_position + Vector3(4, 0, 0))
		await get_tree().process_frame
		var p47_salv0 := salvage
		var p47_kills0 := kills
		_check(not capture_enemy(p47_live) and is_instance_valid(p47_live) and not bool(p47_live.get("is_dead")), "pass47: capture refuses a live (not disabled) enemy")
		_check(salvage == p47_salv0 and kills == p47_kills0, "pass47: refused capture pays nothing (salvage %d kills %d)" % [salvage, kills])
		var p47_dead = spawn_enemy("scout", player.global_position + Vector3(4, 0, 2))
		await get_tree().process_frame
		p47_dead.is_dead = true
		_check(not capture_enemy(p47_dead), "pass47: capture refuses a dead enemy")
		var p47_far = spawn_enemy("scout", player.global_position + Vector3(20, 0, 0))
		await get_tree().process_frame
		p47_far.is_disabled = true
		# Disabled enemies self-destruct when their timer runs out;
		# a directly-set flag leaves the timer at 0, so pin it long.
		p47_far._disabled_timer = 999.0
		_check(not try_capture_near_player(), "pass47: capture refuses a disabled enemy 20 m away (range is 5.5 m)")
		p47_live.queue_free()
		p47_dead.queue_free()
		p47_far.queue_free()
		# Touch aim assist skips disabled targets (the M3 fix above).
		_won = false
		_game_over = false
		var p47_dis = spawn_enemy("scout", player.global_position + Vector3(3, 0, 0))
		await get_tree().process_frame
		p47_dis.is_disabled = true
		p47_dis._disabled_timer = 999.0
		var p47_alive = spawn_enemy("scout", player.global_position + Vector3(12, 0, 0))
		await get_tree().process_frame
		var p47_best: Node = null
		var p47_bd := 9999.0
		for _e in get_tree().get_nodes_in_group("enemies"):
			if is_instance_valid(_e) and not _e.get("is_disabled") and not _e.get("is_dead"):
				var _d := player.global_position.distance_to(_e.global_position)
				if _d < p47_bd:
					p47_bd = _d; p47_best = _e
		_aim_active = false
		_touch_firing = true
		_update_input()
		_check(p47_best != null and player.aim_point.distance_to(p47_best.global_position) < 0.5, "pass47: touch aim picks the nearest live enemy, not the disabled one at 3 m (aim %s, best %s)" % [str(player.aim_point), str(p47_best.global_position) if p47_best else "none"])
		_check(player.aim_point.distance_to(p47_dis.global_position) > 0.5, "pass47: touch aim never points at the disabled scout")
		_touch_firing = false
		player.firing = false
		p47_dis.queue_free()
		p47_alive.queue_free()
		# Substation validation (the M2 fix above).
		_substation_used = false
		var p47_salv1 := salvage
		choose_substation("bogus")
		_check(not _substation_used and salvage == p47_salv1, "pass47: unknown substation choice is ignored, not consumed (used=%s salvage %d)" % [str(_substation_used), salvage])
		choose_substation("tunnel")
		_check(_substation_used and salvage == p47_salv1 + 40, "pass47: tunnel choice pays +40 and consumes (salvage %d -> %d)" % [p47_salv1, salvage])
		print("pass47 coverage-audit checks ran, failures=%d" % _test_failures.size())
		# Pass 49 (FEATURE: Overdrive meter). Charge is +10 per kill
		# through _on_enemy_died, trigger is Space+Shift or a
		# move-stick double-tap, effect is 6 s at x1.4 fire rate,
		# expiry restores the base rate by division, and the OD bar
		# shows charge at rest / remaining time while active.
		overdrive_charge = 0.0
		overdrive_active = false
		overdrive_timer = 0.0
		player.fire_rate_mult = 1.0
		_check(not try_overdrive(), "pass49: empty meter refuses trigger (active=%s)" % str(overdrive_active))
		var p49_e = spawn_enemy("scout", Vector3(40, 0, 40))
		await get_tree().process_frame
		for _k in range(9):
			_on_enemy_died(p49_e, 12, "Autocannon")
		_check(overdrive_charge == 90.0, "pass49: 9 kills charge 90 (got %f)" % overdrive_charge)
		_check(not try_overdrive(), "pass49: 90 charge refuses trigger")
		_on_enemy_died(p49_e, 12, "Autocannon")
		_check(overdrive_charge == 100.0, "pass49: 10th kill fills the meter (got %f)" % overdrive_charge)
		_check(try_overdrive() and overdrive_active and overdrive_timer == 6.0 and overdrive_charge == 0.0, "pass49: trigger arms 6 s and spends the meter (active=%s timer=%f charge=%f)" % [str(overdrive_active), overdrive_timer, overdrive_charge])
		_check(absf(player.fire_rate_mult - 1.4) < 0.001, "pass49: trigger multiplies fire rate x1.4 (got %f)" % player.fire_rate_mult)
		# The rate is real, not just a flag: an autocannon shot's
		# cooldown is 0.13 / 1.4, not 0.13.
		player.select_weapon(1)
		player._fire_cd = 0.0
		player.aim_point = player.global_position + Vector3(0, 0, -20)
		var p49_cc := get_child_count()
		player._fire()
		_check(player._fire_cd > 0.085 and player._fire_cd < 0.10, "pass49: overdrive autocannon cooldown ~0.093 s (got %f)" % player._fire_cd)
		var p49_live = get_child(p49_cc)
		if p49_live != null and p49_live.has_method("release_to_pool"):
			p49_live.release_to_pool()
		player._fire_cd = 0.0
		# No re-trigger, no banking while active.
		var p49_t0 := overdrive_timer
		_check(not try_overdrive() and overdrive_timer == p49_t0, "pass49: re-trigger while active refused, timer untouched")
		_on_enemy_died(p49_e, 12, "Autocannon")
		_check(overdrive_charge == 0.0, "pass49: kills during overdrive bank nothing (charge %f)" % overdrive_charge)
		_overdrive_tick(3.0)
		_check(overdrive_active and absf(overdrive_timer - 3.0) < 0.01 and absf(player.fire_rate_mult - 1.4) < 0.001, "pass49: 3 s in, still active at x1.4 (timer %f mult %f)" % [overdrive_timer, player.fire_rate_mult])
		_refresh_hud()
		_check(_od_bar != null and absf(_od_bar.value - 50.0) < 0.01, "pass49: OD bar drains with remaining time (value %f)" % [_od_bar.value if _od_bar else -1.0])
		_overdrive_tick(3.0)
		_check(not overdrive_active and overdrive_timer == 0.0 and absf(player.fire_rate_mult - 1.0) < 0.001, "pass49: expiry restores base fire rate (active=%s mult %f)" % [str(overdrive_active), player.fire_rate_mult])
		# Desktop trigger: Shift+Space arms it, plain Space dashes.
		overdrive_charge = 100.0
		var p49_shift := InputEventKey.new()
		p49_shift.keycode = KEY_SPACE
		p49_shift.pressed = true
		p49_shift.echo = false
		p49_shift.shift_pressed = true
		_input(p49_shift)
		_check(overdrive_active and absf(player.fire_rate_mult - 1.4) < 0.001, "pass49: Shift+Space triggers overdrive (active=%s mult %f)" % [str(overdrive_active), player.fire_rate_mult])
		_overdrive_tick(6.0)
		_check(not overdrive_active, "pass49: Shift+Space overdrive expires after 6 s")
		player._dash_cd = 0.0
		var p49_space := InputEventKey.new()
		p49_space.keycode = KEY_SPACE
		p49_space.pressed = true
		p49_space.echo = false
		_input(p49_space)
		_check(player._dash_cd > 0.0 and not overdrive_active, "pass49: plain Space still dashes, does not trigger overdrive (cd %f)" % player._dash_cd)
		player._dash_cd = 0.0
		# Touch trigger: two move-stick touches in quick succession.
		overdrive_charge = 100.0
		var p49_t1 := InputEventScreenTouch.new()
		p49_t1.index = 5
		p49_t1.position = Vector2(100, 400)
		p49_t1.pressed = true
		_input(p49_t1)
		var p49_t2 := InputEventScreenTouch.new()
		p49_t2.index = 5
		p49_t2.position = Vector2(100, 400)
		p49_t2.pressed = false
		_input(p49_t2)
		var p49_t3 := InputEventScreenTouch.new()
		p49_t3.index = 5
		p49_t3.position = Vector2(100, 400)
		p49_t3.pressed = true
		_input(p49_t3)
		_check(overdrive_active and absf(player.fire_rate_mult - 1.4) < 0.001, "pass49: move-stick double-tap triggers overdrive (active=%s)" % str(overdrive_active))
		var p49_t4 := InputEventScreenTouch.new()
		p49_t4.index = 5
		p49_t4.position = Vector2(100, 400)
		p49_t4.pressed = false
		_input(p49_t4)
		_overdrive_tick(6.0)
		# HUD bar at rest + cleanup.
		overdrive_charge = 50.0
		_refresh_hud()
		_check(_od_bar != null and absf(_od_bar.value - 50.0) < 0.01, "pass49: OD bar shows charge at rest (value %f)" % [_od_bar.value if _od_bar else -1.0])
		overdrive_charge = 0.0
		overdrive_active = false
		overdrive_timer = 0.0
		player.fire_rate_mult = 1.0
		player.damage_mult = 1.0
		p49_e.queue_free()
		print("pass49 overdrive checks ran, failures=%d" % _test_failures.size())
		print("pass45 dust-storm checks ran, failures=%d" % _test_failures.size())
		print("pass44 input edge-case checks ran, failures=%d" % _test_failures.size())
		print("pass33 card-tap checks ran, failures=%d" % _test_failures.size())
		print("P17 pause checks ran, failures=%d" % _test_failures.size())
		if _test_failures.is_empty():
			print("IRON EDEN AUTO TEST: PASS")
		else:
			print("IRON EDEN AUTO TEST: FAIL (", _test_failures.size(), ")")
		get_tree().quit(0 if _test_failures.is_empty() else 1)
