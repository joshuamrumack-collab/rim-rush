extends RefCounted
## Small static helpers for building meshes and materials in code.


static func mat(c: Color, emit := 0.0, metal := 0.0, rough := 0.35) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	return m


static func glass(c: Color, alpha := 0.18) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.metallic = 0.2
	m.roughness = 0.05
	m.rim_enabled = true
	m.rim = 0.6
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func cyl(parent: Node3D, r_top: float, r_bot: float, h: float, pos: Vector3, m: Material, segs := 24) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = segs
	cm.material = m
	mi.mesh = cm
	mi.position = pos
	parent.add_child(mi)
	return mi


static func box(parent: Node3D, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = m
	mi.mesh = bm
	mi.position = pos
	parent.add_child(mi)
	return mi


static func sphere(parent: Node3D, r: float, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 16 if r < 0.2 else 32
	sm.rings = 8 if r < 0.2 else 16
	sm.material = m
	mi.mesh = sm
	mi.position = pos
	parent.add_child(mi)
	return mi


static func capsule(parent: Node3D, r: float, h: float, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = r
	cm.height = h
	cm.radial_segments = 12
	cm.rings = 4
	cm.material = m
	mi.mesh = cm
	mi.position = pos
	parent.add_child(mi)
	return mi


static func torus(parent: Node3D, inner: float, outer: float, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = inner
	tm.outer_radius = outer
	tm.rings = 24
	tm.ring_segments = 8
	tm.material = m
	mi.mesh = tm
	mi.position = pos
	parent.add_child(mi)
	return mi


## A cylinder from a to b (a tube), in the parent's local space.
static func tube(parent: Node3D, a: Vector3, b: Vector3, r: float, m: Material) -> MeshInstance3D:
	var mi := cyl(parent, r, r, a.distance_to(b), (a + b) * 0.5, m, 10)
	var up := (b - a).normalized()
	var side := up.cross(Vector3.FORWARD)
	if side.length() < 0.01:
		side = up.cross(Vector3.RIGHT)
	side = side.normalized()
	var fwd := side.cross(up).normalized()
	mi.basis = Basis(side, up, fwd)
	return mi


static func area(parent: Node3D, shape: Shape3D, pos: Vector3) -> Area3D:
	var a := Area3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = shape
	a.add_child(cs)
	a.position = pos
	parent.add_child(a)
	return a


static func static_box(parent: Node3D, size: Vector3, pos: Vector3, pm: PhysicsMaterial, rot_y := 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.physics_material_override = pm
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	body.position = pos
	body.rotation.y = rot_y
	parent.add_child(body)
	return body


static func label(parent: Node3D, text: String, size: int, pos: Vector3, col := Color(1, 1, 1), pixel := 0.01) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.outline_size = int(size / 6.0)
	l.modulate = col
	l.pixel_size = pixel
	l.position = pos
	parent.add_child(l)
	return l


## Merges all static, opaque meshes under `root` into one mesh with one
## surface per material. Fewer draw calls = much smoother, above all in the
## browser. Nodes in `skip` (and anything with a script) are left alone, so
## animated parts and pinball elements keep working. Materials are shared,
## so changing a material's colour later still works.
static func merge_static(root: Node3D, skip: Array) -> void:
	var groups := {}
	var to_free: Array = []
	_collect(root, Transform3D(), skip, groups, to_free)
	if to_free.size() < 2:
		return
	var am := ArrayMesh.new()
	for mat in groups:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for e in groups[mat]:
			st.append_from(e[0], 0, e[1])
		st.commit(am)
		am.surface_set_material(am.get_surface_count() - 1, mat)
	var mi := MeshInstance3D.new()
	mi.name = "Merged"
	mi.mesh = am
	root.add_child(mi)
	for n in to_free:
		n.get_parent().remove_child(n)
		n.queue_free()


static func _collect(node: Node, xf: Transform3D, skip: Array, groups: Dictionary, to_free: Array) -> void:
	for c in node.get_children():
		if c in skip or c.get_script() != null:
			continue
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			if mi.mesh == null or mi.mesh.get_surface_count() != 1 or mi.get_child_count() > 0:
				continue
			var mat: Material = mi.material_override if mi.material_override else mi.mesh.surface_get_material(0)
			if mat == null:
				continue
			if mat is BaseMaterial3D and (mat as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				continue
			if not groups.has(mat):
				groups[mat] = []
			groups[mat].append([mi.mesh, xf * mi.transform])
			to_free.append(mi)
		elif c.get_class() == "Node3D":
			_collect(c, xf * (c as Node3D).transform, skip, groups, to_free)
