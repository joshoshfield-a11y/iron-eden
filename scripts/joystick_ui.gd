extends Control

## Touch stick indicators (move = cyan, aim = amber). Set via set_sticks()
## with an Array of Dictionaries: {active, origin, vec, color}

var sticks: Array = []

func set_sticks(p_sticks: Array) -> void:
	sticks = p_sticks
	queue_redraw()

# legacy single-stick call, kept harmless
func set_state(p_active: bool, p_origin: Vector2, p_vec: Vector2) -> void:
	set_sticks([{"active": p_active, "origin": p_origin, "vec": p_vec, "color": Color(0.5, 0.9, 1.0)}])

func _draw() -> void:
	for s in sticks:
		if not s.get("active", false):
			continue
		var origin: Vector2 = s["origin"]
		var vec: Vector2 = s["vec"]
		var col: Color = s.get("color", Color(1, 1, 1))
		draw_circle(origin, 58.0, Color(col, 0.08))
		draw_arc(origin, 58.0, 0.0, TAU, 40, Color(col, 0.4), 2.0)
		draw_circle(origin + vec * 46.0, 24.0, Color(col, 0.5))
