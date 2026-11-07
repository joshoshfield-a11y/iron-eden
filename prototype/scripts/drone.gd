extends Node3D

## Pass 2 (Wave 4): allied engineering drone.
## Follows the run doctrine (chosen in the hangar, persisted in the loadout):
## - iron_wall: fastest structure repair (22 hp/s), repairs even with enemies near.
## - hunting_pack: fetches active salvage caches (collects on contact, same
##   +20 salvage / +1 XP payout as the player), then repairs, then follows the player.
## - ghost_protocol: never repairs while an enemy is within 18 m (it flees instead);
##   otherwise repairs at the base 15 hp/s and keeps its distance when idle.
## Enemies never target the drone (it is not in their target groups); the ghost
## flee is about not exposing the repair position, not survival.
## HOLD command (main.drone_hold, key V): the drone stays put and only repairs
## structures already within repair range.

const SPEED := 14.0
const REPAIR_RANGE := 4.0
const CACHE_PICKUP := 3.2
const GHOST_RADIUS := 18.0
const FOLLOW_DIST := 6.0
const GHOST_IDLE_DIST := 12.0

var doctrine: String = "iron_wall"
var hold: bool = false
var _bob_t: float = 0.0
# Pass 7 (Overhaul A): color code — allies green.
var trim_color: Color = Color(0.3, 0.9, 0.5)

func set_doctrine(d: String) -> bool:
	if d not in ["iron_wall", "hunting_pack", "ghost_protocol"]:
		return false
	doctrine = d
	return true

func repair_rate() -> float:
	return 22.0 if doctrine == "iron_wall" else 15.0

func _ready() -> void:
	add_to_group("drone")
	_build_visual()

func _build_visual() -> void:
	# Pass 7: generated billboard engineering-drone slice (green trim),
	# plus a green ground ring so the ally reads from above. The drone
	# node hovers at y ~1.2, so the ring sits at local y -1.14 (ground).
	var spr := SpriteUtil.billboard_sprite("res://sprites/p7/p7_eng_drone.png", 2.2)
	if spr != null:
		add_child(spr)
	# Pass 12: ring scales with the billboard.
	var ring := SpriteUtil.ground_ring(self, 1.6 * SpriteUtil.UNIT_SCALE, trim_color)
	ring.name = "ally_ring"
	ring.position.y = -1.14

func nearest_enemy_dist() -> float:
	var best := 99999.0
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and not e.get("is_dead"):
			best = minf(best, global_position.distance_to(e.global_position))
	return best

func repair_blocked() -> bool:
	# Ghost protocol only: an enemy close by vetoes all repair work.
	return doctrine == "ghost_protocol" and nearest_enemy_dist() <= GHOST_RADIUS

func nearest_damaged_structure() -> Node:
	var best: Node = null
	var best_d := 99999.0
	for s in get_tree().get_nodes_in_group("structures"):
		if not is_instance_valid(s) or s.get("is_dead_struct"):
			continue
		if float(s.get("hp")) >= float(s.get("max_hp")):
			continue
		var d := global_position.distance_to(s.global_position)
		if d < best_d:
			best_d = d
			best = s
	return best

func nearest_active_cache() -> Node:
	var best: Node = null
	var best_d := 99999.0
	for c in get_tree().get_nodes_in_group("caches"):
		if not is_instance_valid(c):
			continue
		if not bool(c.get_meta("cache_active", false)):
			continue
		var d := global_position.distance_to(c.global_position)
		if d < best_d:
			best_d = d
			best = c
	return best

func _move_toward(target: Vector3, delta: float) -> void:
	var flat := Vector3(target.x, 0, target.z)
	var mine := Vector3(global_position.x, 0, global_position.z)
	var d := flat.distance_to(mine)
	if d < 0.1:
		return
	var step := minf(SPEED * delta, d)
	global_position += (flat - mine).normalized() * step

func _process(delta: float) -> void:
	_bob_t += delta
	# hover bob (y only; movement logic below works on the flat plane)
	global_position.y = 1.2 + sin(_bob_t * 3.0) * 0.15
	if hold:
		# HOLD: no movement at all; repair only what is already in range.
		var s := nearest_damaged_structure()
		if s != null and global_position.distance_to(s.global_position) <= REPAIR_RANGE and not repair_blocked():
			s.heal(repair_rate() * delta)
		return
	# Ghost protocol: flee from any nearby enemy instead of working.
	if doctrine == "ghost_protocol" and nearest_enemy_dist() <= GHOST_RADIUS:
		var foe: Node3D = null
		var bd := 99999.0
		for e in get_tree().get_nodes_in_group("enemies"):
			if is_instance_valid(e) and not e.get("is_dead"):
				var d := global_position.distance_to(e.global_position)
				if d < bd:
					bd = d
					foe = e
		if foe:
			var away: Vector3 = global_position - foe.global_position
			away.y = 0.0
			if away.length() > 0.1:
				_move_toward(global_position + away.normalized() * 10.0, delta)
		return
	# Hunting Pack fetches caches first.
	if doctrine == "hunting_pack":
		var cache := nearest_active_cache()
		if cache != null:
			if global_position.distance_to(cache.global_position) <= CACHE_PICKUP:
				var main = get_tree().get_first_node_in_group("main")
				if main and main.has_method("collect_cache_by_node"):
					main.collect_cache_by_node(cache)
			else:
				_move_toward(cache.global_position, delta)
			return
	# Repair the most damaged structure in reach, else head for it.
	var damaged := nearest_damaged_structure()
	if damaged != null:
		if global_position.distance_to(damaged.global_position) <= REPAIR_RANGE:
			if not repair_blocked():
				damaged.heal(repair_rate() * delta)
		else:
			_move_toward(damaged.global_position, delta)
		return
	# Idle: follow the player (ghost keeps its distance).
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var p: Node = players[0]
	var pd := global_position.distance_to(p.global_position)
	if doctrine == "ghost_protocol":
		if pd < GHOST_IDLE_DIST - 2.0:
			var away: Vector3 = global_position - p.global_position
			away.y = 0.0
			if away.length() > 0.1:
				_move_toward(global_position + away.normalized() * 10.0, delta)
	elif pd > FOLLOW_DIST:
		_move_toward(p.global_position, delta)
