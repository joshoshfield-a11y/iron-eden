class_name SpriteUtil
extends RefCounted

## Builds a flat ground-plane quad showing a top-down sprite texture.
## Returns null when the file does not exist / cannot be loaded (caller falls back to procedural mesh).
## The holder's Y rotation offset lets a side-oriented slice be turned so its
## image-forward aligns with the node's -Z forward.

## Pass 12 (battlefield readability): every billboard unit and ground prop
## renders UNIT_SCALE times its Pass 7 base size, so units read at arm's
## length on a phone against the same-size arena. Gameplay values (speed,
## HP, damage, radii) are untouched — this is a visual scale only, applied
## at the one choke point all unit sprites share. Callers scale their
## ground rings/chevrons by the same constant so footprints stay matched.
const UNIT_SCALE := 1.4

## Pass 7 (Overhaul A): vertical billboard sprite from a generated sheet
## slice. The generated mechs/enemies sheets are FRONT-view art, not
## top-down — laying them flat on the ground would squash them. A billboard
## faces the angled camera, so the silhouette reads at a glance. Returns
## null when the file cannot be loaded (callers must NOT fall back to
## primitive boxes as the unit look — a null here fails the test loudly).
## Pass 13 (gameplay-video bugfix, proved 2026-10-25): Sprite3D.billboard
## DEFAULTS TO 0 (BILLBOARD_DISABLED) in Godot 4.8 — verified by a
## headless probe printing a fresh Sprite3D's billboard (= 0). The old
## code never set it, so unit sprites were fixed vertical planes facing
## -Z, children of yawing bodies. From the (0,44,32) camera the view
## direction is (0,-0.79,-0.61): a vertical plane's world-Y projects to
## only sqrt(1-0.79^2) = 0.61 of its height on screen (flat/squashed),
## and body yaw foreshortened its width by cos(yaw) — edge-on at 90 deg.
## BILLBOARD_ENABLED (spherical) aligns the plane with the camera, so
## the sprite renders upright at full height whatever the body yaw is.
## That is the only mode that satisfies the pass scope; FIXED_Y would
## keep the 0.61 vertical squash.
static func billboard_sprite(path: String, height: float) -> Sprite3D:
	if not ResourceLoader.exists(path):
		return null
	var tex = load(path)
	if tex == null or not (tex is Texture2D):
		return null
	var h := height * UNIT_SCALE
	var s := Sprite3D.new()
	s.name = "unit_sprite"
	s.texture = tex
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.pixel_size = h / float(tex.get_height())
	s.position.y = h * 0.5
	s.shaded = false
	return s

## Pass 34 (template top-down units): flat ground-plane unit sprite from
## a TRUE top-down slice (the user's Game Assets Template chassis/enemy
## frames, sprites/p34/). This is deliberately the opposite presentation
## from Pass 7's billboard: Pass 7's art was FRONT-view, and laying it
## flat squashed it, so a billboard was correct there. Template art is
## top-down by construction, so it belongs flat on the ground, turning
## with the body (a billboard would show a top-down mech side-on to the
## camera). The quad is aspect-preserving: forward_m is the nose-to-tail
## length in metres and the lateral width follows the texture aspect, so
## a long vehicle is never stretched square. Texture "up" maps to -Z
## (node forward), same convention as ground_sprite. Returns a holder
## Node3D named "unit_sprite" whose first child is the quad ("td_quad")
## and whose second child is the contact-shadow blob; null when the file
## cannot be loaded (callers must NOT fall back to primitive boxes).
static func topdown_sprite(path: String, forward_m: float) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var tex = load(path)
	if tex == null or not (tex is Texture2D):
		return null
	var holder := Node3D.new()
	holder.name = "unit_sprite"
	var fw := forward_m * UNIT_SCALE
	var lat := fw * float(tex.get_width()) / float(tex.get_height())
	var mi := MeshInstance3D.new()
	mi.name = "td_quad"
	var quad := QuadMesh.new()
	quad.size = Vector2(lat, fw)
	mi.mesh = quad
	mi.rotation_degrees.x = -90.0 # lie flat; texture "up" maps to -Z (node forward)
	mi.position.y = 0.07
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mi.set_surface_override_material(0, m)
	holder.add_child(mi)
	var sh := MeshInstance3D.new()
	var sq := QuadMesh.new()
	sq.size = Vector2(lat * 0.7, fw * 0.7)
	sh.mesh = sq
	sh.rotation_degrees.x = -90.0
	sh.position.y = 0.04
	var sm := StandardMaterial3D.new()
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_color = Color(0, 0, 0, 0.28)
	sh.set_surface_override_material(0, sm)
	holder.add_child(sh)
	return holder

## Pass 35 (real frame walk cycles): a topdown_sprite holder whose quad
## cycles through 4 walk frames from sprites/p35/ (walk0 = the p34 base
## frame exactly, walk1/2/3 = stride variants whose side zones — legs,
## treads, spikes — shift along the body axis while the centre torso is
## pixel-identical). The holder's meta "walk_frames" carries the 4
## textures and "walk_frame" the current index. Returns null when ANY
## walk frame is missing — a missing frame must fail loudly, never fall
## back to a single static frame or a primitive box. Walk path is derived
## from the base path: res://sprites/p34/p34_<stem>.png ->
## res://sprites/p35/p35_<stem>_walk{0..3}.png.
static func topdown_walk_sprite(path: String, forward_m: float) -> Node3D:
	var holder := topdown_sprite(path, forward_m)
	if holder == null:
		return null
	var stem := path.get_file().get_basename()
	if stem.begins_with("p34_"):
		stem = stem.substr(4)
	var frames: Array[Texture2D] = []
	for i in range(4):
		var wpath := "res://sprites/p35/p35_%s_walk%d.png" % [stem, i]
		if not ResourceLoader.exists(wpath):
			return null
		var tex := load(wpath)
		if tex == null or not (tex is Texture2D):
			return null
		frames.append(tex)
	holder.set_meta("walk_frames", frames)
	holder.set_meta("walk_frame", 0)
	set_walk_frame(holder, 0)
	return holder

## Current walk frame index of a topdown_walk_sprite holder, or -1.
static func walk_frame(holder: Node) -> int:
	if holder == null or not holder.has_meta("walk_frame"):
		return -1
	return int(holder.get_meta("walk_frame"))

## Number of walk frames on the holder (4 for a walk holder, 0 otherwise).
static func walk_frame_count(holder: Node) -> int:
	if holder == null or not holder.has_meta("walk_frames"):
		return 0
	return (holder.get_meta("walk_frames") as Array).size()

## Frame index for a walk phase: one frame per 0.9 rad of phase, cycling
## 0..3. Phase advances only while moving (callers own that rule), so a
## moving unit cycles and a stopped unit holds frame 0 by caller choice.
static func walk_frame_index(phase: float) -> int:
	return int(phase / 0.9) % 4

## Swap a walk holder's quad texture to the given frame (same material,
## so enemy hit-flash albedo tint survives the swap). No-op on
## non-walk holders and out-of-range indices.
static func set_walk_frame(holder: Node, idx: int) -> void:
	if holder == null or not holder.has_meta("walk_frames"):
		return
	var frames := holder.get_meta("walk_frames") as Array
	if frames.is_empty():
		return
	var i := idx % frames.size()
	var quad := topdown_quad(holder)
	if quad == null:
		return
	var mat := quad.get_surface_override_material(0) as StandardMaterial3D
	if mat == null:
		return
	mat.albedo_texture = frames[i] as Texture2D
	holder.set_meta("walk_frame", i)

## Returns the quad MeshInstance of a topdown_sprite holder, or null.
static func topdown_quad(holder: Node) -> MeshInstance3D:
	if holder == null:
		return null
	var q := holder.get_node_or_null("td_quad")
	return q as MeshInstance3D if q != null else null

## Flat ground ring in a trim color (health ring / ally ring). Returns the
## MeshInstance so the caller can re-tint it as HP changes.
static func ground_ring(parent: Node, radius: float, color: Color, mat_alpha: float = 0.95) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "health_ring"
	var tm := TorusMesh.new()
	tm.inner_radius = radius * 0.82
	tm.outer_radius = radius
	tm.rings = 24
	tm.ring_segments = 8
	mi.mesh = tm
	mi.rotation_degrees.x = 90.0
	mi.position.y = 0.07
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var c := color
	c.a = mat_alpha
	m.albedo_color = c
	mi.set_surface_override_material(0, m)
	parent.add_child(mi)
	return mi

## Small forward wedge on the ground, child of a rotating body, so facing
## reads even though the billboard itself always faces the camera.
## Forward in this codebase is -Z.
static func facing_chevron(parent: Node, forward_dist: float, length: float, color: Color) -> Node3D:
	var n := Node3D.new()
	n.name = "facing_chevron"
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.42, 0.1, length)
	mi.mesh = bm
	mi.position = Vector3(0, 0.1, -(forward_dist + length * 0.5))
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 1.2
	m.albedo_color = color
	mi.set_surface_override_material(0, m)
	n.add_child(mi)
	parent.add_child(n)
	return n

## Pass 35: the Pass 28 procedural bob/lean (anim_pose) is deleted
## with this pass — units cycle real p35 walk textures instead, and
## no caller bobs or scales a unit holder anymore. The engineering
## drone ally keeps its own billboard art (outside Pass 35 scope).

static func ground_sprite(path: String, size: float, y_rot_offset: float = 0.0, include_shadow: bool = true) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var tex = load(path)
	if tex == null or not (tex is Texture2D):
		return null
	var holder := Node3D.new()
	holder.rotation.y = y_rot_offset
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	mi.mesh = quad
	mi.rotation_degrees.x = -90.0 # lie flat; texture "up" maps to -Z (node forward)
	mi.position.y = 0.07
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mi.set_surface_override_material(0, m)
	holder.add_child(mi)
	# Pass 43 (PERF audit): the soft contact shadow blob is a second
	# draw call per sprite, and static terrain dressing does not need
	# it — the ground atlas already grounds it, and the blob is a flat
	# black quad that barely reads on textured ground. Static props,
	# ruins, and tile destructibles pass include_shadow=false and save
	# one draw call each (63 props/ruins + 4 tile destructibles = 67).
	# Moving units keep their blob (topdown_sprite, untouched), and
	# the parked support mech keeps the default true.
	if not include_shadow:
		return holder
	var sh := MeshInstance3D.new()
	var sq := QuadMesh.new()
	sq.size = Vector2(size * 0.7, size * 0.7)
	sh.mesh = sq
	sh.rotation_degrees.x = -90.0
	sh.position.y = 0.04
	var sm := StandardMaterial3D.new()
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_color = Color(0, 0, 0, 0.28)
	sh.set_surface_override_material(0, sm)
	holder.add_child(sh)
	return holder
