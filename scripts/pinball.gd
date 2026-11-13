extends RefCounted
## Pinball arena elements. Each one calls back into the match ("game"), which
## owns the balls, sounds and effects. Use e.g. Pinball.Bumper.new().


const Mk = preload("res://scripts/mk.gd")


# ------------------------------------------------------------------ Bumper
class Bumper extends StaticBody3D:
	var game
	var _glow: StandardMaterial3D
	var _flash := 0.0
	var _cd := 0.0
	var _ring: MeshInstance3D

	func setup(g, pos: Vector3, col: Color) -> void:
		game = g
		position = pos
		var pm := PhysicsMaterial.new()
		pm.bounce = 0.9
		pm.friction = 0.1
		physics_material_override = pm
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = 0.55
		sh.height = 2.0
		cs.shape = sh
		cs.position.y = 1.0
		add_child(cs)
		Mk.cyl(self, 0.62, 0.7, 0.18, Vector3(0, 0.09, 0), Mk.mat(Color(0.8, 0.82, 0.88), 0.0, 1.0, 0.15))
		_glow = Mk.mat(col, 1.2, 0.2, 0.3)
		Mk.cyl(self, 0.5, 0.56, 0.75, Vector3(0, 0.55, 0), _glow)
		Mk.cyl(self, 0.64, 0.64, 0.12, Vector3(0, 0.98, 0), Mk.mat(Color(1, 1, 1), 2.0, 0.0, 0.2))
		_ring = Mk.cyl(self, 0.75, 0.75, 0.04, Vector3(0, 0.35, 0), Mk.mat(col, 3.0))
		var light := OmniLight3D.new()
		light.light_color = col
		light.light_energy = 1.2
		light.omni_range = 3.0
		light.position = Vector3(0, 1.3, 0)
		add_child(light)
		var ash := CylinderShape3D.new()
		ash.radius = 0.85
		ash.height = 1.6
		var a := Mk.area(self, ash, Vector3(0, 0.8, 0))
		a.body_entered.connect(_on_body)

	func _process(delta: float) -> void:
		_cd = maxf(0.0, _cd - delta)
		_flash = maxf(0.0, _flash - delta)
		_glow.emission_energy_multiplier = 8.0 if _flash > 0.0 else 1.2
		_ring.scale = Vector3.ONE * (1.0 + _flash * 3.0)

	func _on_body(body: Node) -> void:
		if _cd > 0.0 or not (body is RigidBody3D):
			return
		var rb := body as RigidBody3D
		var dir := rb.global_position - global_position
		dir.y = 0.0
		dir = dir.normalized() if dir.length() > 0.01 else Vector3.RIGHT
		if game.is_ball(rb):
			rb.linear_velocity = dir * maxf(11.0, rb.linear_velocity.length() * 0.9) + Vector3.UP * 1.0
			game.on_pinball("bumper", global_position, rb)
		elif rb.has_method("is_chair"):
			rb.apply_central_impulse(dir * rb.mass * 4.0)
		_flash = 0.15
		_cd = 0.12


# ----------------------------------------------------------------- Flipper
## Sits in a corner near a goal and fires the ball back out toward the middle.
class Flipper extends Node3D:
	var game
	var _paddle: Node3D
	var _rest := 0.0
	var _cd := 0.0
	var _side := 1.0
	var _mat_glow: StandardMaterial3D

	func setup(g, pos: Vector3, facing_yaw: float, side: float, col: Color) -> void:
		game = g
		position = pos
		rotation.y = facing_yaw
		_side = side
		Mk.cyl(self, 0.22, 0.25, 0.5, Vector3(0, 0.25, 0), Mk.mat(Color(0.85, 0.85, 0.9), 0.0, 1.0, 0.2))
		_paddle = StaticBody3D.new()
		add_child(_paddle)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(1.8, 0.5, 0.3)
		cs.shape = bs
		cs.position = Vector3(0.9 * side, 0.25, 0)
		_paddle.add_child(cs)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.8, 0.4, 0.26)
		_mat_glow = Mk.mat(col, 1.5, 0.3, 0.25)
		bm.material = _mat_glow
		mi.mesh = bm
		mi.position = Vector3(0.9 * side, 0.25, 0)
		_paddle.add_child(mi)
		_rest = -0.35 * side
		_paddle.rotation.y = _rest
		var bsh := BoxShape3D.new()
		bsh.size = Vector3(2.2, 1.2, 1.6)
		var a := Mk.area(self, bsh, Vector3(0.9 * side, 0.6, 0.6))
		a.body_entered.connect(_on_body)

	func _process(delta: float) -> void:
		_cd = maxf(0.0, _cd - delta)
		_mat_glow.emission_energy_multiplier = 1.5 if _cd <= 0.0 else 5.0

	func _on_body(body: Node) -> void:
		if _cd > 0.0 or not game.is_ball(body):
			return
		_cd = 0.6
		var tw := create_tween()
		tw.tween_property(_paddle, "rotation:y", _rest + 0.9 * _side, 0.06)
		tw.tween_property(_paddle, "rotation:y", _rest, 0.25)
		var rb := body as RigidBody3D
		var out := -rb.global_position
		out.y = 0.0
		out = out.normalized().rotated(Vector3.UP, randf_range(-0.35, 0.35))
		rb.linear_velocity = out * randf_range(12.0, 15.0) + Vector3.UP * 1.5
		game.on_pinball("flipper", global_position, rb)


# ----------------------------------------------------------------- Spinner
## Spinner gate on a wall: hitting it spins the vane and gives the team boost.
class SpinnerGate extends Node3D:
	var game
	var _vane: MeshInstance3D
	var _spin := 0.0
	var _cd := 0.0

	func setup(g, pos: Vector3, col: Color) -> void:
		game = g
		position = pos
		var frame := Mk.mat(Color(0.8, 0.82, 0.88), 0.0, 1.0, 0.15)
		for sx in [-1.0, 1.0]:
			var post := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.12, 1.5, 0.12)
			bm.material = frame
			post.mesh = bm
			post.position = Vector3(sx * 0.9, 0.75, 0)
			add_child(post)
		_vane = MeshInstance3D.new()
		var vm := BoxMesh.new()
		vm.size = Vector3(1.6, 0.9, 0.04)
		vm.material = Mk.mat(col, 2.0, 0.5, 0.2)
		_vane.mesh = vm
		_vane.position = Vector3(0, 0.85, 0)
		add_child(_vane)
		var bsh := BoxShape3D.new()
		bsh.size = Vector3(1.8, 1.4, 0.9)
		var a := Mk.area(self, bsh, Vector3(0, 0.7, 0.3))
		a.body_entered.connect(_on_body)

	func _process(delta: float) -> void:
		_cd = maxf(0.0, _cd - delta)
		_vane.rotation.x += _spin * delta
		_spin = move_toward(_spin, 0.0, delta * 8.0)

	func _on_body(body: Node) -> void:
		if _cd > 0.0 or not game.is_ball(body):
			return
		_cd = 0.5
		_spin = 10.0 + (body as RigidBody3D).linear_velocity.length() * 3.0
		game.on_pinball("spinner", global_position, body)


# -------------------------------------------------------------------- Ramp
## A wedge by the back wall: a fast ball that rolls onto it gets lobbed toward the middle.
class Ramp extends Node3D:
	var game
	var _cd := 0.0
	var _arrow: StandardMaterial3D

	func setup(g, pos: Vector3, yaw: float, col: Color) -> void:
		game = g
		position = pos
		rotation.y = yaw
		var mi := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(2.2, 0.5, 1.4)
		pm.left_to_right = 0.0
		pm.material = Mk.mat(Color(0.25, 0.27, 0.32), 0.0, 0.6, 0.3)
		mi.mesh = pm
		mi.rotation.y = PI / 2
		mi.position = Vector3(0, 0.25, 0)
		add_child(mi)
		var strip := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(1.6, 0.02, 0.15)
		_arrow = Mk.mat(col, 3.0)
		sm.material = _arrow
		strip.mesh = sm
		strip.position = Vector3(0, 0.27, 0)
		strip.rotation.x = 0.33
		add_child(strip)
		var bsh := BoxShape3D.new()
		bsh.size = Vector3(1.6, 1.0, 2.0)
		var a := Mk.area(self, bsh, Vector3(0, 0.5, 0))
		a.body_entered.connect(_on_body)

	func _process(delta: float) -> void:
		_cd = maxf(0.0, _cd - delta)
		_arrow.emission_energy_multiplier = 1.0 + 2.0 * (0.5 + 0.5 * sin(Time.get_ticks_msec() / 150.0))

	func _on_body(body: Node) -> void:
		if _cd > 0.0 or not game.is_ball(body):
			return
		var rb := body as RigidBody3D
		if rb.linear_velocity.length() < 3.5:
			return
		_cd = 1.0
		var to_mid := -rb.global_position
		to_mid.y = 0.0
		body.lob(to_mid.normalized() * 8.0 + Vector3.UP * 6.0)
		game.on_pinball("ramp", global_position, rb)


# ---------------------------------------------------------------- Kickback
## Guards a goal post: saves one angled shot, then recharges for 30 s.
class Kickback extends Node3D:
	var game
	var charged := true
	var _timer := 0.0
	var _lamp: StandardMaterial3D
	var _goal_dir := 1.0

	func setup(g, pos: Vector3, goal_dir: float) -> void:
		game = g
		position = pos
		_goal_dir = goal_dir
		_lamp = Mk.mat(Color(0.2, 1.0, 0.4), 3.0)
		Mk.cyl(self, 0.12, 0.15, 1.2, Vector3(0, 0.6, 0), Mk.mat(Color(0.8, 0.8, 0.85), 0.0, 1.0, 0.2))
		Mk.cyl(self, 0.18, 0.18, 0.2, Vector3(0, 1.3, 0), _lamp)
		var bsh := BoxShape3D.new()
		bsh.size = Vector3(1.0, 1.2, 0.9)
		var a := Mk.area(self, bsh, Vector3(-goal_dir * 0.4, 0.6, 0))
		a.body_entered.connect(_on_body)

	func _process(delta: float) -> void:
		if not charged:
			_timer -= delta
			if _timer <= 0.0:
				charged = true
		var c := Color(0.2, 1.0, 0.4) if charged else Color(1.0, 0.2, 0.2)
		_lamp.albedo_color = c
		_lamp.emission = c

	func _on_body(body: Node) -> void:
		if not charged or not game.is_ball(body):
			return
		var rb := body as RigidBody3D
		if rb.linear_velocity.x * _goal_dir < 2.0:
			return  # only saves balls heading into the goal
		charged = false
		_timer = 30.0
		var v := rb.linear_velocity
		rb.linear_velocity = Vector3(-v.x * 0.9 - _goal_dir * 4.0, 1.0, v.z * 0.5 + randf_range(-3, 3))
		game.on_pinball("kickback", global_position, rb)
