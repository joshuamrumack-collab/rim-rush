extends RigidBody3D
## A power wheelchair athlete. Ball handling is fully physical: you drive into
## the ball, or spin the chair so the foot guard swings into it. The match fills
## the "intent" dictionary every physics frame, from player input or the AI.

const Mk = preload("res://scripts/mk.gd")

## "shot" = how hard the foot guard sends the ball on contact (guard spring).
const TYPES := {
	"All-rounder": {"max_speed": 6.0, "accel": 7.0, "turn": 3.4, "spin": 9.0, "shot": 1.0, "mass": 100.0, "grip": 6.5, "recharge": 13.0, "drain": 35.0, "brake": 10.0, "guard_w": 1.0,
		"desc": "Easy to learn, no big weakness. No big strength either."},
	"Sprinter": {"max_speed": 7.6, "accel": 10.0, "turn": 3.0, "spin": 7.5, "shot": 0.8, "mass": 70.0, "grip": 5.0, "recharge": 18.0, "drain": 35.0, "brake": 10.0, "guard_w": 1.0,
		"desc": "Fastest, quick boost recharge. Loses bumps, soft touches, slides wide."},
	"Spinner": {"max_speed": 5.4, "accel": 5.5, "turn": 4.6, "spin": 18.0, "shot": 1.3, "mass": 85.0, "grip": 7.0, "recharge": 12.0, "drain": 35.0, "brake": 10.0, "guard_w": 1.0,
		"desc": "Hardest spin hits, turns in place. Slow to accelerate, wobbles when bumped."},
	"Tank": {"max_speed": 4.6, "accel": 5.0, "turn": 2.4, "spin": 6.0, "shot": 1.05, "mass": 170.0, "grip": 9.0, "recharge": 11.0, "drain": 55.0, "brake": 12.0, "guard_w": 1.23,
		"desc": "Wins bumps, wide guard. Slowest chair, slow spin, boost drains fast."},
	"Glider": {"max_speed": 6.6, "accel": 7.5, "turn": 3.8, "spin": 8.5, "shot": 0.9, "mass": 90.0, "grip": 2.2, "recharge": 13.0, "drain": 35.0, "brake": 4.0, "guard_w": 1.0,
		"desc": "Best drifts and soft dribbling. Weak brakes, overshoots the ball."},
}
const TYPE_ORDER := ["All-rounder", "Sprinter", "Spinner", "Tank", "Glider"]
const SKINS := [Color(0.95, 0.78, 0.62), Color(0.78, 0.58, 0.42), Color(0.55, 0.38, 0.25), Color(0.36, 0.24, 0.16)]
const HAIR := [Color(0.1, 0.07, 0.05), Color(0.35, 0.2, 0.1), Color(0.8, 0.65, 0.35), Color(0.6, 0.2, 0.1), Color(0.15, 0.15, 0.15)]

var game
var team := 0
var team_color := Color(0.2, 0.5, 1.0)
var team_color2 := Color(1, 1, 1)
var paint := Color(0.18, 0.19, 0.22)
var chair_type := "All-rounder"
var build := {}
var stats: Dictionary = {}
var role := "attack"     # attack, defend, keeper
var number := 1
var look_seed := 0

var intent := {}
var battery := 100.0
var boosting := false
var spin_amount := 0.0
var frozen_flag := true
var lockout := 0.0       # foul penalty: no boost
var speed_scale := 1.0   # AI difficulty
var grip_mult := 1.0     # arena floor (ice)

var _pending_reset := false
var _reset_xform := Transform3D()

var _visual: Node3D
var _ring: Node3D
var _marker: Node3D
var _wheels: Array = []
var _casters: Array = []
var _trails: Array = []
var _torso: Node3D
var _head: Node3D
var _guard_shape: CollisionShape3D
var _was_boosting := false


func is_chair() -> bool:
	return true


func setup(g, t: int, tdef: Dictionary, type_name: String, r: String, num: int, chair_build := {}) -> void:
	game = g
	team = t
	team_color = tdef["color"]
	team_color2 = tdef["color2"]
	role = r
	number = num
	build = chair_build
	look_seed = randi()
	paint = Game.PAINTS[int(build.get("paint", 0))] if build.has("paint") else Color(0.18, 0.19, 0.22)
	intent = blank_intent()
	axis_lock_linear_y = true
	axis_lock_angular_x = true
	axis_lock_angular_z = true
	gravity_scale = 0.0
	can_sleep = false
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 4
	var pm := PhysicsMaterial.new()
	pm.friction = 0.3
	pm.bounce = 0.35
	physics_material_override = pm

	var body_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.9, 0.9, 1.1)
	body_shape.shape = box
	add_child(body_shape)

	_guard_shape = CollisionShape3D.new()
	var guard := BoxShape3D.new()
	guard.size = Vector3(0.86, 0.25, 0.2)
	_guard_shape.shape = guard
	_guard_shape.position = Vector3(0, -0.28, -0.95)  # longer front = more room for spin hits
	add_child(_guard_shape)
	# Side rails of the foot guard (so the ball can't slip between guard and chair)
	for sx in [-1.0, 1.0]:
		var side := CollisionShape3D.new()
		var sb := BoxShape3D.new()
		sb.size = Vector3(0.06, 0.25, 0.5)
		side.shape = sb
		side.position = Vector3(sx * 0.43, -0.28, -0.72)
		add_child(side)
	body_entered.connect(_on_body_entered)
	set_type(type_name)


## Two ways to drive:
##  relative = false: "move" is a world direction (used by the AI and one-hand mode)
##  relative = true: "throttle" (-1 reverse .. 1 forward) and "steer" (-1 left .. 1 right),
##                   relative to where the chair faces (W = forward)
## spin: -1 (counter-clockwise) .. 1 (clockwise), spins on the spot.
static func blank_intent() -> Dictionary:
	return {"move": Vector3.ZERO, "relative": false, "throttle": 0.0, "steer": 0.0,
		"boost": false, "brake": false, "spin": 0.0}


func set_type(type_name: String) -> void:
	chair_type = type_name
	stats = Game.build_stats(TYPES[type_name], build)
	mass = stats["mass"]
	var g := _guard_shape.shape as BoxShape3D
	g.size.x = 0.86 * float(stats["guard_w"])
	_build_visual()


func next_type() -> void:
	var i := TYPE_ORDER.find(chair_type)
	set_type(TYPE_ORDER[(i + 1) % TYPE_ORDER.size()])


func forward() -> Vector3:
	var f := -global_transform.basis.z
	f.y = 0.0
	return f.normalized()


func reset_to(pos: Vector3, facing: Vector3) -> void:
	var yaw := atan2(-facing.x, -facing.z)
	_reset_xform = Transform3D(Basis(Vector3.UP, yaw), Vector3(pos.x, 0.5, pos.z))
	_pending_reset = true
	battery = 100.0
	lockout = 0.0


func set_controlled(on: bool) -> void:
	if _ring:
		_ring.visible = on


func set_marker(on: bool) -> void:
	if _marker:
		_marker.visible = on


func _on_body_entered(b: Node) -> void:
	if b.has_method("is_chair") and game:
		game.on_chair_contact(self, b)


func _physics_process(delta: float) -> void:
	lockout = maxf(0.0, lockout - delta)
	if frozen_flag:
		boosting = false
		spin_amount = 0.0
		return
	var mv: Vector3 = intent["move"]
	spin_amount = clampf(float(intent["spin"]), -1.0, 1.0)
	var driving: bool = mv.length() > 0.2 or absf(float(intent["throttle"])) > 0.2
	boosting = intent["boost"] and battery > 1.0 and lockout <= 0.0 and (driving or absf(spin_amount) > 0.2)
	if boosting:
		battery = max(0.0, battery - stats["drain"] * delta)
	elif lockout <= 0.0:
		battery = min(100.0, battery + stats["recharge"] * delta)
	if boosting and not _was_boosting and game and game.is_player_chair(self):
		Sfx.play("boost", -8.0)
	_was_boosting = boosting


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _pending_reset:
		state.transform = _reset_xform
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		_pending_reset = false
		return
	if frozen_flag:
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		return

	var dt := state.step
	var fwd := -state.transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var v := state.linear_velocity
	v.y = 0.0
	var f_speed := v.dot(fwd)
	var lateral := v - fwd * f_speed

	var mv: Vector3 = intent["move"]
	var braking: bool = intent["brake"]
	var mag := clampf(mv.length(), 0.0, 1.0)
	var max_s: float = stats["max_speed"] * speed_scale
	var acc: float = stats["accel"]
	if boosting:
		max_s *= 1.55
		acc *= 2.0
	if braking:
		max_s *= 0.6

	var speed_ratio := clampf(absf(f_speed) / float(stats["max_speed"]), 0.0, 1.0)
	var turn_rate: float = stats["turn"] * lerpf(1.0, 0.65, speed_ratio)
	var target_speed := 0.0
	var ang := 0.0
	var relative: bool = intent["relative"]
	var throttle := clampf(float(intent["throttle"]), -1.0, 1.0)
	var steer := clampf(float(intent["steer"]), -1.0, 1.0)
	if absf(spin_amount) > 0.15:
		# Spin: rotate on the spot (clockwise for +1). Boost spins faster.
		ang = -float(stats["spin"]) * spin_amount * (1.3 if boosting else 1.0)
		if relative:
			target_speed = max_s * 0.3 * maxf(0.0, throttle)
		elif mag > 0.15:
			target_speed = max_s * mag * 0.3 * maxf(0.0, fwd.dot(mv.normalized()))
	elif relative:
		# W/S drive along the chair's own front, A/D turn it. Turning is a bit
		# quicker when nearly stopped, like a real power chair.
		var slow_bonus := 1.35 if absf(f_speed) < 1.0 else 1.0
		ang = -steer * turn_rate * slow_bonus
		target_speed = throttle * max_s if throttle >= 0.0 else throttle * max_s * 0.5
	elif mag > 0.15:
		var desired := mv.normalized()
		var diff := fwd.signed_angle_to(desired, Vector3.UP)
		ang = clampf(diff * 8.0, -turn_rate, turn_rate)
		var align := clampf(fwd.dot(desired), 0.0, 1.0)
		target_speed = max_s * mag * (0.25 + 0.75 * align)

	var rate: float = acc
	var speeding_up := absf(target_speed) > absf(f_speed) and (signf(target_speed) == signf(f_speed) or absf(f_speed) < 0.05)
	if not speeding_up:
		rate = stats["brake"] * (1.5 if braking else 0.6)
	f_speed = move_toward(f_speed, target_speed, rate * dt)

	var grip: float = stats["grip"] * grip_mult
	if braking and absf(ang) > 1.0:
		grip *= 0.25  # drift brake
	lateral *= maxf(0.0, 1.0 - grip * dt)

	state.linear_velocity = fwd * f_speed + lateral
	state.angular_velocity = Vector3(0, ang, 0)


func _process(delta: float) -> void:
	if not _visual:
		return
	# Lean into spins and turns, spin the wheels, swivel the casters.
	var v := linear_velocity
	var fwd := forward()
	var f_speed := v.dot(fwd)
	var turn := angular_velocity.y
	_visual.rotation.z = lerpf(_visual.rotation.z, -0.06 * spin_amount + turn * 0.012, 0.2)
	_visual.rotation.x = lerpf(_visual.rotation.x, clampf(f_speed * 0.01, -0.05, 0.05), 0.1)
	for w in _wheels:
		var side: float = w[1]
		var rad: float = w[2]
		(w[0] as Node3D).rotation.x -= (f_speed + turn * 0.37 * side) / rad * delta
	for c in _casters:
		var target := atan2(-v.dot(global_transform.basis.x), maxf(0.1, absf(f_speed))) if v.length() > 0.3 else 0.0
		(c as Node3D).rotation.y = lerpf((c as Node3D).rotation.y, target, 0.15)
	if _torso:
		_torso.rotation.y = lerpf(_torso.rotation.y, clampf(-turn * 0.04, -0.3, 0.3), 0.1)
	for t in _trails:
		(t as GPUParticles3D).emitting = boosting


# ---------------------------------------------------------------- visuals
# Modelled on real powerchair football chairs (the Strike Force is the
# standard): low and wide, drive wheels near the back with arched tube guards
# over them, front casters and rear anti-tip casters, a low soft-back seat
# with lap belt and joystick, and a square-cornered foot guard made of bars
# that sits close to the floor so the ball can't slip under it.
# Local space: forward is -Z, the floor is at y = -0.5.

const FLOOR_Y := -0.5


func _layout() -> Dictionary:
	# Drive layout per chair type. Most use the rear-wheel-drive sport chair;
	# the Spinner is a mid-wheel-drive chair (spins on the spot) and the Glider
	# a front-wheel-drive chair.
	var d := {"drive_z": 0.24, "r": 0.18, "front_casters": true, "rear_casters": "antitip", "tube": 0.022, "frame_w": 0.5, "track": 0.74, "back_h": 0.46, "rear_guard": false}
	match chair_type:
		"Spinner":
			d["drive_z"] = 0.0
			d["rear_casters"] = "full"
		"Glider":
			d["drive_z"] = -0.16
			d["front_casters"] = false
			d["rear_casters"] = "full"
		"Tank":
			d["r"] = 0.19
			d["tube"] = 0.03
			d["frame_w"] = 0.56
			d["track"] = 0.8
			d["rear_guard"] = true
		"Sprinter":
			d["tube"] = 0.018
			d["back_h"] = 0.38
	if role == "keeper":
		d["rear_guard"] = true
	return d


func _build_visual() -> void:
	var was_controlled := _ring != null and _ring.visible
	var was_marker := _marker != null and _marker.visible
	if _visual:
		_visual.queue_free()
	_wheels.clear()
	_casters.clear()
	_trails.clear()
	_visual = Node3D.new()
	add_child(_visual)
	var v := _visual
	var rng := RandomNumberGenerator.new()
	rng.seed = look_seed + number * 7
	var L := _layout()
	var tube_r: float = L["tube"]

	var frame_m := Mk.mat(paint, 0.0, 0.7, 0.32)
	var alu := Mk.mat(Color(0.78, 0.8, 0.84), 0.0, 1.0, 0.22)
	var chrome := Mk.mat(Color(0.88, 0.89, 0.92), 0.0, 1.0, 0.1)
	var dark := Mk.mat(Color(0.06, 0.06, 0.07), 0.0, 0.2, 0.6)
	var rubber := Mk.mat(Color(0.04, 0.04, 0.04), 0.0, 0.0, 0.9)
	var upholstery := Mk.mat(Color(0.09, 0.09, 0.1), 0.0, 0.0, 0.85)
	var guard_m := Mk.mat(team_color, 0.25, 0.55, 0.3)
	var glow := Mk.mat(team_color, 4.0)

	var fw: float = L["frame_w"]
	var track: float = L["track"]
	var dz: float = L["drive_z"]
	var wr: float = L["r"]
	var axle_y := FLOOR_Y + wr
	var frame_y := -0.33

	# --- Base frame: two rails, cross members, battery box, controller box
	for sx in [-1.0, 1.0]:
		Mk.tube(v, Vector3(sx * fw / 2.0, frame_y, -0.42), Vector3(sx * fw / 2.0, frame_y, 0.48), 0.028, frame_m)
	for z in [-0.42, 0.0, 0.48]:
		Mk.tube(v, Vector3(-fw / 2.0, frame_y, z), Vector3(fw / 2.0, frame_y, z), 0.024, frame_m)
	Mk.box(v, Vector3(fw - 0.08, 0.17, 0.5), Vector3(0, frame_y + 0.02, 0.06), dark)
	Mk.box(v, Vector3(fw - 0.06, 0.02, 0.86), Vector3(0, FLOOR_Y + 0.07, 0.03), glow)  # underglow strip
	var ctrl := Mk.box(v, Vector3(0.22, 0.12, 0.1), Vector3(0, -0.14, 0.46), dark)
	ctrl.name = "Controller"
	for k in 3:
		Mk.box(v, Vector3(0.16, 0.01, 0.005), Vector3(0, -0.17 + k * 0.03, 0.512), alu)  # cooling fan grill

	# --- Drive wheels with aluminium cut-out rims, and arched tube guards
	for side in [-1.0, 1.0]:
		var hub := Node3D.new()
		hub.position = Vector3(side * track / 2.0, axle_y, dz)
		v.add_child(hub)
		var spin_node := Node3D.new()
		hub.add_child(spin_node)
		var tire := Mk.torus(spin_node, wr - 0.055, wr, Vector3.ZERO, rubber)
		tire.rotation.z = PI / 2
		var rim := Mk.cyl(spin_node, wr - 0.045, wr - 0.045, 0.05, Vector3.ZERO, alu)
		rim.rotation.z = PI / 2
		for k in 5:
			var a := k * TAU / 5.0
			var hole := Mk.cyl(spin_node, 0.035, 0.035, 0.055, Vector3(0, sin(a) * (wr - 0.1), cos(a) * (wr - 0.1)), dark)
			hole.rotation.z = PI / 2
		var cap := Mk.cyl(spin_node, 0.035, 0.035, 0.07, Vector3(side * 0.01, 0, 0), Mk.mat(team_color, 1.5))
		cap.rotation.z = PI / 2
		_wheels.append([spin_node, side, wr])
		# Motor / gearbox between frame and wheel
		var motor := Mk.cyl(v, 0.06, 0.06, track / 2.0 - fw / 2.0, Vector3(side * (fw / 2.0 + (track / 2.0 - fw / 2.0) / 2.0), axle_y, dz), dark)
		motor.rotation.z = PI / 2
		# Arched wheel guard (keeps the wheel from riding up on other chairs)
		var gx: float = side * (track / 2.0 + 0.065)
		var gr := wr + 0.06
		var prev := Vector3(gx, axle_y - 0.02, dz - gr)
		for k in range(1, 9):
			var a := PI * float(k) / 8.0
			var p := Vector3(gx, axle_y + sin(a) * gr, dz - cos(a) * gr)
			Mk.tube(v, prev, p, tube_r * 0.9, guard_m)
			Mk.sphere(v, tube_r * 0.9, p, guard_m)
			prev = p
		Mk.tube(v, Vector3(side * fw / 2.0, frame_y, dz - gr), Vector3(gx, axle_y - 0.02, dz - gr), tube_r * 0.8, frame_m)
		Mk.tube(v, Vector3(side * fw / 2.0, frame_y, dz + gr), Vector3(gx, axle_y - 0.02, dz + gr), tube_r * 0.8, frame_m)
		var tr2: GPUParticles3D = game.fx.make_trail(hub, team_color, Vector3(side * 0.05, -0.1, 0.2), 0.09, 30, 0.35) if game and game.get("fx") and Game.quality() >= 1 else null
		if tr2:
			_trails.append(tr2)

	# --- Casters
	if L["front_casters"]:
		for sx in [-1.0, 1.0]:
			_caster(v, Vector3(sx * 0.22, frame_y, -0.38), 0.07, alu, rubber)
	match L["rear_casters"]:
		"antitip":
			# Small anti-tip casters on a support arm behind the drive wheels
			Mk.tube(v, Vector3(0, frame_y, 0.48), Vector3(0, frame_y - 0.02, 0.6), 0.022, frame_m)
			Mk.tube(v, Vector3(-0.17, frame_y - 0.02, 0.6), Vector3(0.17, frame_y - 0.02, 0.6), 0.022, frame_m)
			for sx in [-1.0, 1.0]:
				_caster(v, Vector3(sx * 0.17, frame_y - 0.02, 0.6), 0.045, alu, rubber)
		"full":
			for sx in [-1.0, 1.0]:
				_caster(v, Vector3(sx * 0.22, frame_y, 0.42), 0.07, alu, rubber)

	# --- Seat: low soft-back seat, lap belt, armrests, joystick
	var seat_y := -0.08
	Mk.box(v, Vector3(0.46, 0.04, 0.46), Vector3(0, seat_y - 0.07, 0.08), frame_m)
	Mk.tube(v, Vector3(-0.18, frame_y, 0.08), Vector3(-0.18, seat_y - 0.09, 0.08), 0.03, frame_m)
	Mk.tube(v, Vector3(0.18, frame_y, 0.08), Vector3(0.18, seat_y - 0.09, 0.08), 0.03, frame_m)
	Mk.box(v, Vector3(0.44, 0.08, 0.44), Vector3(0, seat_y - 0.02, 0.08), upholstery)
	var back_h: float = L["back_h"]
	var back := Node3D.new()
	back.position = Vector3(0, seat_y, 0.31)
	back.rotation.x = 0.14
	v.add_child(back)
	Mk.box(back, Vector3(0.44, back_h, 0.07), Vector3(0, back_h / 2.0, 0), upholstery)
	Mk.box(back, Vector3(0.36, back_h * 0.55, 0.02), Vector3(0, back_h * 0.55, 0.04), Mk.mat(team_color, 0.2, 0.0, 0.7))
	Mk.label(back, str(number), 64, Vector3(0, back_h * 0.55, 0.052), team_color2, 0.005)
	for sx in [-1.0, 1.0]:
		Mk.tube(back, Vector3(sx * 0.23, -0.05, 0.02), Vector3(sx * 0.23, back_h + 0.04, 0.02), 0.016, frame_m)
	Mk.sphere(back, 0.018, Vector3(-0.23, back_h + 0.04, 0.02), frame_m)
	Mk.sphere(back, 0.018, Vector3(0.23, back_h + 0.04, 0.02), frame_m)
	if role == "keeper":
		Mk.tube(back, Vector3(0, back_h, 0.0), Vector3(0, back_h + 0.12, 0.0), 0.015, frame_m)
		Mk.box(back, Vector3(0.26, 0.14, 0.07), Vector3(0, back_h + 0.18, -0.02), upholstery)  # headrest
	for sx in [-1.0, 1.0]:
		Mk.box(v, Vector3(0.07, 0.04, 0.3), Vector3(sx * 0.255, seat_y + 0.2, 0.06), upholstery)
		Mk.tube(v, Vector3(sx * 0.255, seat_y - 0.05, 0.16), Vector3(sx * 0.255, seat_y + 0.18, 0.16), 0.014, frame_m)
	# Joystick module on the right armrest
	Mk.box(v, Vector3(0.08, 0.05, 0.13), Vector3(0.265, seat_y + 0.23, -0.12), dark)
	Mk.box(v, Vector3(0.06, 0.005, 0.04), Vector3(0.265, seat_y + 0.256, -0.09), Mk.mat(Color(0.3, 0.8, 1.0), 2.5))  # display
	Mk.tube(v, Vector3(0.265, seat_y + 0.25, -0.15), Vector3(0.265, seat_y + 0.31, -0.15), 0.008, chrome)
	Mk.sphere(v, 0.022, Vector3(0.265, seat_y + 0.32, -0.15), Mk.mat(Color(0.08, 0.08, 0.08), 0.0, 0.2, 0.4))

	# --- Footrest: round bar with a single plate
	for sx in [-1.0, 1.0]:
		Mk.tube(v, Vector3(sx * 0.17, seat_y - 0.06, -0.12), Vector3(sx * 0.17, FLOOR_Y + 0.12, -0.42), 0.018, frame_m)
	Mk.tube(v, Vector3(-0.2, FLOOR_Y + 0.12, -0.42), Vector3(0.2, FLOOR_Y + 0.12, -0.42), 0.02, frame_m)
	Mk.box(v, Vector3(0.36, 0.015, 0.16), Vector3(0, FLOOR_Y + 0.13, -0.47), dark)

	# --- Foot guard: square-cornered bar frame close to the floor
	var gw := 0.86 * float(stats["guard_w"])
	var front_z := -1.0
	var back_z := -0.36
	var rails := [FLOOR_Y + 0.06, FLOOR_Y + 0.17, FLOOR_Y + 0.28]
	var corner := 0.06
	for y in rails:
		var pts := [
			Vector3(-gw / 2.0, y, back_z), Vector3(-gw / 2.0, y, front_z + corner), Vector3(-gw / 2.0 + corner, y, front_z),
			Vector3(gw / 2.0 - corner, y, front_z), Vector3(gw / 2.0, y, front_z + corner), Vector3(gw / 2.0, y, back_z),
		]
		for k in range(pts.size() - 1):
			Mk.tube(v, pts[k], pts[k + 1], tube_r, guard_m)
			if k > 0:
				Mk.sphere(v, tube_r, pts[k], guard_m)
	# Uprights tying the rails together, front and sides
	var ups := [Vector3(-gw / 2.0 + corner * 0.3, 0, front_z + corner * 0.3), Vector3(gw / 2.0 - corner * 0.3, 0, front_z + corner * 0.3),
		Vector3(-gw / 6.0, 0, front_z), Vector3(gw / 6.0, 0, front_z), Vector3(-gw / 2.0, 0, -0.68), Vector3(gw / 2.0, 0, -0.68)]
	for u in ups:
		Mk.tube(v, Vector3(u.x, rails[0], u.z), Vector3(u.x, rails[2], u.z), tube_r * 0.85, guard_m)
	# Polycarbonate face behind the front bars
	var face := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(gw - 0.1, 0.24)
	face.mesh = qm
	var pc := Mk.glass(team_color.lightened(0.2), 0.35)
	face.material_override = pc
	face.position = Vector3(0, FLOOR_Y + 0.17, front_z + 0.03)
	v.add_child(face)
	# Mounting arms back to the frame
	for sx in [-1.0, 1.0]:
		Mk.tube(v, Vector3(sx * fw / 2.0, frame_y, -0.42), Vector3(sx * gw / 2.0, rails[1], back_z), tube_r, frame_m)
	if L["rear_guard"]:
		var rz := 0.68
		for y in [FLOOR_Y + 0.08, FLOOR_Y + 0.2]:
			Mk.tube(v, Vector3(-0.3, y, 0.52), Vector3(-0.3, y, rz), tube_r, guard_m)
			Mk.tube(v, Vector3(-0.3, y, rz), Vector3(0.3, y, rz), tube_r, guard_m)
			Mk.tube(v, Vector3(0.3, y, rz), Vector3(0.3, y, 0.52), tube_r, guard_m)

	# --- Athlete
	var skin: Color = SKINS[rng.randi() % SKINS.size()]
	var skin_m := Mk.mat(skin, 0.0, 0.0, 0.6)
	var jersey := Mk.mat(team_color, 0.0, 0.0, 0.7)
	var shorts := Mk.mat(team_color2.darkened(0.3) if team_color2.get_luminance() > 0.5 else team_color2, 0.0, 0.0, 0.8)
	_torso = Node3D.new()
	_torso.position = Vector3(0, seat_y + 0.02, 0.14)
	v.add_child(_torso)
	var t := _torso
	Mk.capsule(t, 0.17, 0.58, Vector3(0, 0.29, 0.02), jersey)
	Mk.box(t, Vector3(0.34, 0.08, 0.19), Vector3(0, 0.52, 0.03), jersey)
	var chest := Mk.label(t, str(number), 36, Vector3(0, 0.36, -0.16), team_color2, 0.004)
	chest.rotation.y = PI
	Mk.capsule(t, 0.05, 0.12, Vector3(0, 0.62, 0.02), skin_m)
	_head = Node3D.new()
	_head.position = Vector3(0, 0.77, 0.0)
	t.add_child(_head)
	Mk.sphere(_head, 0.12, Vector3.ZERO, skin_m)
	var hair_c: Color = HAIR[rng.randi() % HAIR.size()]
	var hair := Mk.sphere(_head, 0.125, Vector3(0, 0.03, 0.025), Mk.mat(hair_c, 0.0, 0.0, 0.9))
	hair.scale = Vector3(1.0, 0.85, 1.0)
	for ex in [-0.042, 0.042]:
		Mk.sphere(_head, 0.016, Vector3(ex, 0.01, -0.11), Mk.mat(Color(0.05, 0.05, 0.05)))
	# Right hand on the joystick, left hand on the armrest
	var joy := Vector3(0.265, seat_y + 0.31, -0.15) - _torso.position
	Mk.tube(t, Vector3(0.18, 0.5, 0.04), Vector3(0.27, 0.3, -0.02), 0.045, jersey)
	Mk.tube(t, Vector3(0.27, 0.3, -0.02), joy + Vector3(0, 0.03, 0.03), 0.036, skin_m)
	Mk.tube(t, Vector3(-0.18, 0.5, 0.04), Vector3(-0.27, 0.3, 0.0), 0.045, jersey)
	Mk.tube(t, Vector3(-0.27, 0.3, 0.0), Vector3(-0.26, 0.22, -0.2), 0.036, skin_m)
	# Lap belt
	Mk.box(v, Vector3(0.42, 0.04, 0.05), Vector3(0, seat_y + 0.1, -0.02), Mk.mat(Color(0.05, 0.05, 0.06), 0.0, 0.1, 0.6))
	Mk.box(v, Vector3(0.07, 0.05, 0.055), Vector3(0, seat_y + 0.1, -0.025), alu)  # buckle
	# Legs down to the footplate
	for sx in [-0.1, 0.1]:
		Mk.tube(v, Vector3(sx, seat_y + 0.06, 0.06), Vector3(sx, seat_y + 0.04, -0.3), 0.065, shorts)
		Mk.tube(v, Vector3(sx, seat_y + 0.04, -0.3), Vector3(sx, FLOOR_Y + 0.18, -0.42), 0.05, skin_m)
		Mk.box(v, Vector3(0.09, 0.07, 0.19), Vector3(sx, FLOOR_Y + 0.17, -0.49), Mk.mat(Color(0.95, 0.95, 0.95), 0.0, 0.0, 0.5))
	if role == "keeper":
		Mk.box(t, Vector3(0.36, 0.28, 0.02), Vector3(0, 0.3, -0.17), Mk.mat(Color(0.2, 1.0, 0.4), 0.4))  # keeper bib

	if Game.quality() >= 2:
		var light := OmniLight3D.new()
		light.light_color = team_color
		light.light_energy = 0.8
		light.omni_range = 1.6
		light.position = Vector3(0, FLOOR_Y + 0.12, 0)
		v.add_child(light)

	# Controlled-player ring with a chevron that shows which way is forward
	_ring = Node3D.new()
	v.add_child(_ring)
	var ring_m := Mk.mat(Color(1.0, 0.9, 0.2), 3.0)
	Mk.torus(_ring, 0.95, 1.03, Vector3(0, FLOOR_Y + 0.03, -0.1), ring_m)
	var chev := Mk.box(_ring, Vector3(0.26, 0.02, 0.26), Vector3(0, FLOOR_Y + 0.03, -1.4), ring_m)
	chev.rotation.y = PI / 4
	_ring.visible = was_controlled

	# Colour-blind team shape: circle for team 0, triangle for team 1
	_marker = Node3D.new()
	_marker.position = Vector3(0, 1.5, 0)
	v.add_child(_marker)
	if team == 0:
		var mt := Mk.torus(_marker, 0.12, 0.2, Vector3.ZERO, Mk.mat(Color(1, 1, 1), 2.0))
		mt.rotation.x = PI / 2
	else:
		var pr := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(0.38, 0.33, 0.06)
		pm.material = Mk.mat(Color(1, 1, 1), 2.0)
		pr.mesh = pm
		_marker.add_child(pr)
	_marker.visible = was_marker or Game.settings["shapes"]

	# Merge all the static parts into one mesh (animated parts stay separate).
	var skip: Array = [_torso, _ring, _marker]
	for w in _wheels:
		skip.append((w[0] as Node3D).get_parent())
	skip.append_array(_casters)
	Mk.merge_static(v, skip)
	# Each moving part is merged on its own, so it can still move.
	for w in _wheels:
		Mk.merge_static(w[0], [])
	for c in _casters:
		Mk.merge_static(c, [])
	Mk.merge_static(_torso, [_head])
	Mk.merge_static(_head, [])
	Mk.merge_static(_ring, [])


## Swivel caster: vertical stem, fork, small wheel with an aluminium hub.
func _caster(v: Node3D, top: Vector3, r: float, alu: Material, rubber: Material) -> void:
	var pivot := Node3D.new()
	pivot.position = top
	v.add_child(pivot)
	var floor_rel := FLOOR_Y - top.y
	Mk.cyl(pivot, 0.025, 0.025, 0.04, Vector3.ZERO, alu)
	var hub_y := floor_rel + r
	for sx in [-0.03, 0.03]:
		Mk.tube(pivot, Vector3(sx, -0.01, 0), Vector3(sx, hub_y, 0.05), 0.01, alu)
	var w := Mk.torus(pivot, r - 0.025, r, Vector3(0, hub_y, 0.05), rubber)
	w.rotation.z = PI / 2
	var hubm := Mk.cyl(pivot, r - 0.025, r - 0.025, 0.03, Vector3(0, hub_y, 0.05), alu)
	hubm.rotation.z = PI / 2
	_casters.append(pivot)
