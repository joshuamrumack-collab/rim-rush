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
	tm.rings = 32
	tm.ring_segments = 12
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
