class_name Factory
extends RefCounted

## Shared mesh/material builders so every entity can be assembled from
## primitives in code. No external assets, everything procedural.

static func mat(color: Color, emission_color: Color = Color(0, 0, 0), emission_energy: float = 0.0, metallic: float = 0.35, roughness: float = 0.55) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = emission_color
		m.emission_energy_multiplier = emission_energy
	return m

static func box(parent: Node3D, size: Vector3, pos: Vector3, material: Material, rot_y: float = 0.0) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation.y = rot_y
	if material:
		mi.set_surface_override_material(0, material)
	parent.add_child(mi)
	return mi

static func cyl(parent: Node3D, radius: float, height: float, pos: Vector3, material: Material, sides: int = 16) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = sides
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	if material:
		mi.set_surface_override_material(0, material)
	parent.add_child(mi)
	return mi

static func sphere(parent: Node3D, radius: float, pos: Vector3, material: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 20
	mesh.rings = 12
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	if material:
		mi.set_surface_override_material(0, material)
	parent.add_child(mi)
	return mi

static func plane(parent: Node3D, size: Vector2, pos: Vector3, material: Material) -> MeshInstance3D:
	var mesh := PlaneMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	if material:
		mi.set_surface_override_material(0, material)
	parent.add_child(mi)
	return mi
