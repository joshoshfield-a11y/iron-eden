class_name Factory
extends RefCounted

## Procedural low-poly mesh helpers (shared pattern from prior protos).

static func mat(albedo: Color, emission: Color = Color(0,0,0), emission_energy: float = 0.0, metallic: float = 0.2, roughness: float = 0.7) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.metallic = metallic
	m.roughness = roughness
	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = emission_energy
	return m

static func mat_transparent(albedo: Color, alpha: float, emission_energy: float = 0.6) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var c := albedo
	c.a = alpha
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = albedo
		m.emission_energy_multiplier = emission_energy
	return m

static func box(parent: Node, size: Vector3, pos: Vector3, material: Material, rot_y: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.rotation.y = rot_y
	if material:
		mi.set_surface_override_material(0, material)
	parent.add_child(mi)
	return mi

static func cyl(parent: Node, radius: float, height: float, pos: Vector3, material: Material, sides: int = 16) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = sides
	mi.mesh = cm
	mi.position = pos
	if material:
		mi.set_surface_override_material(0, material)
	parent.add_child(mi)
	return mi

static func sphere(parent: Node, radius: float, pos: Vector3, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 16
	sm.rings = 8
	mi.mesh = sm
	mi.position = pos
	if material:
		mi.set_surface_override_material(0, material)
	parent.add_child(mi)
	return mi

static func plane(parent: Node, size: Vector2, pos: Vector3, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size
	mi.mesh = pm
	mi.position = pos
	if material:
		mi.set_surface_override_material(0, material)
	parent.add_child(mi)
	return mi
