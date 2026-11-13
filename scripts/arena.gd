extends Node3D
## Builds a complete arena: lighting and post-processing, court, walls, goals,
## stands with a crowd, decoration per theme, and the pinball elements.

const Mk = preload("res://scripts/mk.gd")
const Pinball = preload("res://scripts/pinball.gd")

const HALF_X := 14.0
const HALF_Z := 8.0
const GOAL_HALF_W := 2.0
const GOAL_DEPTH := 1.6
const WALL_H := 1.4
const COLLIDE_H := 3.2

var def: Dictionary
var style := "indoor"
var game
var env: Environment
var floor_mat: ShaderMaterial
var crowd_mat: ShaderMaterial
var led_mats: Array = []
var goal_mats: Array = [null, null]   # index 0 = goal at -X, 1 = goal at +X
var net_mats: Array = [null, null]
var goal_areas: Array = [null, null]
var lane_mats: Array = []
var lane_positions: Array = []
var lane_areas: Array = []
var jackpot_mat: StandardMaterial3D
var jackpot_area: Area3D
var score_label: Label3D
var clock_label: Label3D
var floor_pm: PhysicsMaterial
var wall_pm: PhysicsMaterial
var moving_lights: Array = []
var spot_lights: Array = []
var bumper_positions: Array = []
var kickbacks: Array = []
var _light_base := {}
var _blackout := 0.0
var _ambient_base := 0.45
var _blackout_target := 0.0
var _t := 0.0


func build(arena_def: Dictionary, g, colors: Array) -> void:
	def = arena_def
	style = def["style"]
	game = g
	floor_pm = PhysicsMaterial.new()
	floor_pm.friction = 0.6 * float(def["grip"])
	floor_pm.bounce = 0.1
	wall_pm = PhysicsMaterial.new()
	wall_pm.bounce = 0.7
	wall_pm.friction = 0.2

	_build_environment()
	_build_floor(colors)
	_build_walls()
	_build_goals(colors)
	match style:
		"indoor": _build_hall(Color(0.09, 0.1, 0.13), true)
		"neon": _build_neon()
		"rooftop": _build_rooftop()
		"retro": _build_retro()
		"ice": _build_hall(Color(0.75, 0.82, 0.9), false)
	_build_stands(colors)
	_build_scoreboard()
	_build_pinball(colors)
	var probe := ReflectionProbe.new()
	probe.size = Vector3(40, 14, 28)
	probe.position = Vector3(0, 4, 0)
	probe.box_projection = true
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	add_child(probe)


# ------------------------------------------------------------ environment

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.95
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.ssil_enabled = true
	env.ssr_enabled = true
	env.ssr_max_steps = 64
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.12
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	match style:
		"indoor":
			env.background_color = Color(0.03, 0.035, 0.05)
			env.ambient_light_color = Color(0.55, 0.6, 0.72)
			env.ambient_light_energy = 0.45
			_fog(Color(0.75, 0.8, 0.95), 0.008)
		"neon":
			env.background_color = Color(0.01, 0.005, 0.03)
			env.ambient_light_color = Color(0.4, 0.3, 0.7)
			env.ambient_light_energy = 0.3
			env.glow_intensity = 1.1
			_fog(Color(0.6, 0.3, 1.0), 0.015)
		"rooftop":
			var sky := Sky.new()
			var psm := ProceduralSkyMaterial.new()
			psm.sky_top_color = Color(0.16, 0.22, 0.48)
			psm.sky_horizon_color = Color(1.0, 0.55, 0.35)
			psm.ground_horizon_color = Color(0.5, 0.3, 0.3)
			psm.ground_bottom_color = Color(0.08, 0.06, 0.08)
			psm.sun_angle_max = 20.0
			sky.sky_material = psm
			env.sky = sky
			env.background_mode = Environment.BG_SKY
			env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
			env.ambient_light_energy = 0.8
			env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
			env.fog_enabled = true
			env.fog_light_color = Color(0.9, 0.6, 0.5)
			env.fog_density = 0.004
			env.fog_sky_affect = 0.3
		"retro":
			env.background_color = Color(0.05, 0.035, 0.025)
			env.ambient_light_color = Color(0.8, 0.65, 0.5)
			env.ambient_light_energy = 0.45
			_fog(Color(1.0, 0.85, 0.6), 0.012)
		"ice":
			env.background_color = Color(0.06, 0.08, 0.11)
			env.ambient_light_color = Color(0.6, 0.75, 0.95)
			env.ambient_light_energy = 0.55
			_fog(Color(0.8, 0.9, 1.0), 0.014)
	we.environment = env
	_ambient_base = env.ambient_light_energy
	add_child(we)

	# Key light for crisp shadows (the sun on the rooftop).
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	if style == "rooftop":
		sun.rotation_degrees = Vector3(-18, -60, 0)
		sun.light_color = Color(1.0, 0.72, 0.5)
		sun.light_energy = 1.6
	else:
		sun.rotation_degrees = Vector3(-70, -30, 0)
		sun.light_energy = 0.35
		sun.light_color = Color(0.9, 0.92, 1.0)
	add_child(sun)
	_light_base[sun] = sun.light_energy


func _fog(col: Color, density: float) -> void:
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = density
	env.volumetric_fog_albedo = col
	env.volumetric_fog_anisotropy = 0.6
	env.volumetric_fog_length = 80.0


func _spot(pos: Vector3, target: Vector3, col: Color, energy: float, angle: float, shadow: bool) -> SpotLight3D:
	var s := SpotLight3D.new()
	s.light_color = col
	s.light_energy = energy
	s.spot_range = 40.0
	s.spot_angle = angle
	s.spot_attenuation = 0.6
	s.shadow_enabled = shadow and not OS.has_feature("web")
	s.light_volumetric_fog_energy = 1.4
	add_child(s)
	s.global_position = pos
	s.look_at(target, Vector3.UP if absf((target - pos).normalized().y) < 0.99 else Vector3.FORWARD)
	spot_lights.append(s)
	_light_base[s] = energy
	return s


# ------------------------------------------------------------------ court

func _build_floor(colors: Array) -> void:
	var fstyle := 0
	match style:
		"neon": fstyle = 1
		"rooftop": fstyle = 2
		"retro": fstyle = 3
		"ice": fstyle = 4
	floor_mat = ShaderMaterial.new()
	floor_mat.shader = load("res://shaders/floor.gdshader")
	floor_mat.set_shader_parameter("style", fstyle)
	floor_mat.set_shader_parameter("team_a", colors[0])
	floor_mat.set_shader_parameter("team_b", colors[1])
	floor_mat.set_shader_parameter("half_x", HALF_X)
	floor_mat.set_shader_parameter("half_z", HALF_Z)
	if style == "neon":
		floor_mat.set_shader_parameter("line_col", Color(0.3, 1.0, 1.0))
		floor_mat.set_shader_parameter("line_glow", 2.5)
	elif style == "ice":
		floor_mat.set_shader_parameter("line_col", Color(0.9, 0.15, 0.2))
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2.0 * (HALF_X + GOAL_DEPTH) + 4.0, 2.0 * HALF_Z + 4.0)
	pm.subdivide_width = 4
	pm.subdivide_depth = 4
	pm.material = floor_mat
	mi.mesh = pm
	add_child(mi)
	Mk.static_box(self, Vector3(60, 0.4, 40), Vector3(0, -0.2, 0), floor_pm)
	# Invisible ceiling so lobs can never leave the court.
	Mk.static_box(self, Vector3(60, 0.4, 40), Vector3(0, COLLIDE_H + 0.2, 0), wall_pm)


func _wall_look() -> Dictionary:
	match style:
		"neon": return {"board": Mk.mat(Color(0.05, 0.05, 0.08), 0.0, 0.6, 0.2), "trim": Mk.mat(Color(1.0, 0.2, 0.8), 4.0), "glass": Mk.glass(Color(0.6, 0.3, 1.0), 0.12)}
		"rooftop": return {"board": Mk.mat(Color(0.9, 0.9, 0.92), 0.0, 0.1, 0.3), "trim": Mk.mat(Color(1.0, 0.6, 0.2), 2.0), "glass": Mk.glass(Color(0.8, 0.9, 1.0), 0.12)}
		"retro": return {"board": Mk.mat(Color(0.55, 0.36, 0.2), 0.0, 0.0, 0.6), "trim": Mk.mat(Color(0.9, 0.75, 0.3), 0.6, 0.6, 0.3), "glass": Mk.glass(Color(1.0, 0.9, 0.8), 0.06)}
		"ice": return {"board": Mk.mat(Color(0.95, 0.96, 0.98), 0.0, 0.0, 0.25), "trim": Mk.mat(Color(0.2, 0.5, 1.0), 1.5), "glass": Mk.glass(Color(0.85, 0.95, 1.0), 0.16)}
	return {"board": Mk.mat(Color(0.92, 0.93, 0.96), 0.0, 0.0, 0.3), "trim": Mk.mat(Color(0.25, 0.55, 1.0), 1.5), "glass": Mk.glass(Color(0.8, 0.9, 1.0), 0.14)}


## One wall segment: padded board + LED band + glass, with tall collision.
func _wall(length: float, center: Vector3, yaw: float, near_side := false) -> void:
	var look := _wall_look()
	var root := Node3D.new()
	root.position = center
	root.rotation.y = yaw
	add_child(root)
	Mk.static_box(self, Vector3(length, COLLIDE_H, 0.4), Vector3(center.x, COLLIDE_H / 2.0, center.z), wall_pm, yaw)
	if near_side:
		# Camera side: low board only, everything else see-through.
		Mk.box(root, Vector3(length, 0.35, 0.3), Vector3(0, 0.175, 0), look["board"])
		Mk.box(root, Vector3(length, 0.05, 0.32), Vector3(0, 0.36, 0), look["trim"])
		Mk.box(root, Vector3(length, 1.6, 0.06), Vector3(0, 1.15, 0), look["glass"])
		return
	Mk.box(root, Vector3(length, 1.0, 0.4), Vector3(0, 0.5, 0), look["board"])
	var led := ShaderMaterial.new()
	led.shader = load("res://shaders/led.gdshader")
	led.set_shader_parameter("col_a", game.team_color(0) if game else Color(0.2, 0.5, 1.0))
	led.set_shader_parameter("col_b", game.team_color(1) if game else Color(1.0, 0.3, 0.2))
	led.set_shader_parameter("speed", randf_range(0.08, 0.2) * (1.0 if randf() < 0.5 else -1.0))
	led_mats.append(led)
	var band := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(length - 0.1, 0.5)
	qm.material = led
	band.mesh = qm
	band.position = Vector3(0, 0.55, 0.205)
	root.add_child(band)
	Mk.box(root, Vector3(length, 0.06, 0.44), Vector3(0, 1.03, 0), look["trim"])
	Mk.box(root, Vector3(length, 1.2, 0.05), Vector3(0, 1.65, 0.0), look["glass"])
	# Glass support posts every few metres
	var posts := int(length / 3.5)
	for i in posts + 1:
		var x := -length / 2.0 + i * (length / maxf(1.0, posts))
		Mk.box(root, Vector3(0.06, 1.25, 0.08), Vector3(x, 1.65, 0), Mk.mat(Color(0.75, 0.77, 0.8), 0.0, 1.0, 0.2))


func _build_walls() -> void:
	# Far side (-Z) faces +Z, near side (+Z) faces -Z.
	_wall(2.0 * HALF_X, Vector3(0, 0, -HALF_Z - 0.2), 0.0)
	_wall(2.0 * HALF_X, Vector3(0, 0, HALF_Z + 0.2), PI, true)
	var seg := HALF_Z - GOAL_HALF_W
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_wall(seg, Vector3(sx * (HALF_X + 0.2), 0, sz * (GOAL_HALF_W + seg / 2.0)), -sx * PI / 2.0, sz > 0.0)
	# Chamfered corners so the ball rolls back into play.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var n := Vector3(sx, 0, sz).normalized()
			var mid := Vector3(sx * (HALF_X - 1.0), 0, sz * (HALF_Z - 1.0)) + n * 0.2
			_wall(2.9, mid, atan2(-sx, -sz), sz > 0.0)


func _build_goals(colors: Array) -> void:
	for gi in 2:
		var sx := -1.0 if gi == 0 else 1.0
		var col: Color = colors[gi]
		var gm := Mk.mat(col, 2.5, 0.6, 0.2)
		goal_mats[gi] = gm
		var root := Node3D.new()
		root.position = Vector3(sx * HALF_X, 0, 0)
		add_child(root)
		var post_m := Mk.mat(Color(0.92, 0.93, 0.96), 0.0, 1.0, 0.12)
		for sz in [-1.0, 1.0]:
			Mk.cyl(root, 0.09, 0.09, 1.6, Vector3(0, 0.8, sz * GOAL_HALF_W), post_m)
			Mk.cyl(root, 0.1, 0.1, 0.06, Vector3(0, 0.03, sz * GOAL_HALF_W), gm)
		var bar := Mk.cyl(root, 0.09, 0.09, 2.0 * GOAL_HALF_W, Vector3(0, 1.6, 0), post_m)
		bar.rotation.x = PI / 2
		var strip := Mk.box(root, Vector3(0.04, 0.04, 2.0 * GOAL_HALF_W), Vector3(-sx * 0.1, 1.6, 0), gm)
		strip.name = "GoalStrip"
		# Pocket walls (collision) and nets (visual)
		Mk.static_box(self, Vector3(0.3, COLLIDE_H, 2.0 * GOAL_HALF_W + 0.6), Vector3(sx * (HALF_X + GOAL_DEPTH + 0.35), COLLIDE_H / 2.0, 0), wall_pm)
		for sz in [-1.0, 1.0]:
			Mk.static_box(self, Vector3(GOAL_DEPTH + 0.4, COLLIDE_H, 0.3), Vector3(sx * (HALF_X + GOAL_DEPTH / 2.0 + 0.2), COLLIDE_H / 2.0, sz * (GOAL_HALF_W + 0.15)), wall_pm)
		var nm := ShaderMaterial.new()
		nm.shader = load("res://shaders/net.gdshader")
		nm.set_shader_parameter("col", col.lightened(0.4))
		net_mats[gi] = nm
		_net(root, Vector3(sx * GOAL_DEPTH, 0.8, 0), Vector2(2.0 * GOAL_HALF_W, 1.6), PI / 2, Vector3.ZERO, nm, Vector2(14, 6))
		for sz in [-1.0, 1.0]:
			_net(root, Vector3(sx * GOAL_DEPTH / 2.0, 0.8, sz * GOAL_HALF_W), Vector2(GOAL_DEPTH, 1.6), 0.0, Vector3.ZERO, nm, Vector2(6, 6))
		_net(root, Vector3(sx * GOAL_DEPTH / 2.0, 1.6, 0), Vector2(GOAL_DEPTH, 2.0 * GOAL_HALF_W), 0.0, Vector3(PI / 2, 0, 0), nm, Vector2(6, 14))
		# Goal light
		var gl := OmniLight3D.new()
		gl.light_color = col
		gl.light_energy = 1.5
		gl.omni_range = 4.0
		gl.position = Vector3(sx * GOAL_DEPTH * 0.6, 1.0, 0)
		root.add_child(gl)
		# Trigger, fully behind the goal line
		var ash := BoxShape3D.new()
		ash.size = Vector3(GOAL_DEPTH - 0.5, 2.5, 2.0 * GOAL_HALF_W)
		var area := Mk.area(self, ash, Vector3(sx * (HALF_X + 0.5 + (GOAL_DEPTH - 0.5) / 2.0), 1.25, 0))
		goal_areas[gi] = area


func _net(parent: Node3D, pos: Vector3, size: Vector2, yaw: float, rot: Vector3, m: Material, cells: Vector2) -> void:
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = size
	mi.mesh = qm
	mi.material_override = m.duplicate()
	(mi.material_override as ShaderMaterial).set_shader_parameter("cells", cells)
	mi.position = pos
	mi.rotation = rot
	mi.rotation.y += yaw
	parent.add_child(mi)


## Recolour goals after the teams swap ends at half time.
func set_goal_colors(colors: Array) -> void:
	for gi in 2:
		var c: Color = colors[gi]
		goal_mats[gi].albedo_color = c
		goal_mats[gi].emission = c
	floor_mat.set_shader_parameter("team_a", colors[0])
	floor_mat.set_shader_parameter("team_b", colors[1])


# ---------------------------------------------------------------- stands

func _build_stands(colors: Array) -> void:
	var rows := 9
	var seat_m := Mk.mat(Color(0.2, 0.22, 0.27), 0.0, 0.2, 0.6)
	if style == "retro":
		seat_m = Mk.mat(Color(0.5, 0.33, 0.18), 0.0, 0.0, 0.7)
	elif style == "neon":
		seat_m = Mk.mat(Color(0.06, 0.05, 0.1), 0.0, 0.5, 0.3)
	var fans := []
	var sides := [
		{"origin": Vector3(0, 0, -HALF_Z - 1.6), "dir": Vector3(0, 0, -1), "len": 2.0 * HALF_X + 6.0, "yaw": 0.0},
		{"origin": Vector3(-HALF_X - GOAL_DEPTH - 1.8, 0, 0), "dir": Vector3(-1, 0, 0), "len": 2.0 * HALF_Z + 2.0, "yaw": PI / 2},
		{"origin": Vector3(HALF_X + GOAL_DEPTH + 1.8, 0, 0), "dir": Vector3(1, 0, 0), "len": 2.0 * HALF_Z + 2.0, "yaw": -PI / 2},
	]
	if style != "rooftop":
		sides.append({"origin": Vector3(0, 0, HALF_Z + 1.6), "dir": Vector3(0, 0, 1), "len": 2.0 * HALF_X + 6.0, "yaw": PI, "near": true})
	for sd in sides:
		var near: bool = sd.get("near", false)
		var nrows := 5 if near else rows
		var dir: Vector3 = sd["dir"]
		var along := dir.cross(Vector3.UP)
		for r in nrows:
			var h := 0.5 + r * (0.32 if near else 0.5)
			var center: Vector3 = sd["origin"] + dir * (r * 0.95 + 0.5)
			var step := Mk.box(self, Vector3(sd["len"], h, 0.95), center + Vector3(0, h / 2.0, 0), seat_m)
			step.rotation.y = sd["yaw"]
			var n := int(sd["len"] / 0.62)
			for i in n:
				if randf() < (0.15 if style != "retro" else 0.4):
					continue
				if OS.has_feature("web") and i % 2 == 1:
					continue  # lighter crowd in the browser
				var t: float = -sd["len"] / 2.0 + (i + 0.5) * (sd["len"] / n) + randf_range(-0.12, 0.12)
				var p: Vector3 = center + along * t + Vector3(0, h + 0.42, 0)
				var c: Color
				var roll := randf()
				if roll < 0.32:
					c = colors[0]
				elif roll < 0.6:
					c = colors[1]
				else:
					c = Color.from_hsv(randf(), randf_range(0.1, 0.6), randf_range(0.25, 0.9))
				fans.append([p, c])
	if fans.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var cap := CapsuleMesh.new()
	cap.radius = 0.19
	cap.height = 0.85
	cap.radial_segments = 8
	cap.rings = 3
	crowd_mat = ShaderMaterial.new()
	crowd_mat.shader = load("res://shaders/crowd.gdshader")
	cap.material = crowd_mat
	mm.mesh = cap
	mm.instance_count = fans.size()
	for i in fans.size():
		mm.set_instance_transform(i, Transform3D(Basis(), fans[i][0]))
		mm.set_instance_color(i, fans[i][1])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	# Heads, as a second multimesh sharing the same animation.
	var mm2 := MultiMesh.new()
	mm2.transform_format = MultiMesh.TRANSFORM_3D
	mm2.use_colors = true
	var head := SphereMesh.new()
	head.radius = 0.13
	head.height = 0.26
	head.radial_segments = 8
	head.rings = 4
	head.material = crowd_mat
	mm2.mesh = head
	mm2.instance_count = fans.size()
	var skins := [Color(0.95, 0.78, 0.62), Color(0.78, 0.58, 0.42), Color(0.55, 0.38, 0.25), Color(0.36, 0.24, 0.16)]
	for i in fans.size():
		mm2.set_instance_transform(i, Transform3D(Basis(), fans[i][0] + Vector3(0, 0.55, 0)))
		mm2.set_instance_color(i, skins[i % skins.size()])
	var mmi2 := MultiMeshInstance3D.new()
	mmi2.multimesh = mm2
	mmi2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi2)


func set_excitement(x: float) -> void:
	if crowd_mat:
		crowd_mat.set_shader_parameter("excite", clampf(x, 0.0, 1.0))


func flash_leds(on: bool) -> void:
	for m in led_mats:
		m.set_shader_parameter("flash", 1.0 if on else 0.0)


# ------------------------------------------------------------- scoreboard

func _build_scoreboard() -> void:
	var pos := Vector3(0, 9.0, -HALF_Z - 10.5)
	if style == "rooftop":
		pos = Vector3(0, 6.0, -HALF_Z - 6.0)
	var frame := Mk.box(self, Vector3(12.0, 4.2, 0.6), pos, Mk.mat(Color(0.05, 0.05, 0.06), 0.0, 0.5, 0.3))
	frame.name = "Scoreboard"
	var face := ShaderMaterial.new()
	face.shader = load("res://shaders/led.gdshader")
	face.set_shader_parameter("col_a", Color(0.05, 0.08, 0.15))
	face.set_shader_parameter("col_b", Color(0.08, 0.05, 0.15))
	face.set_shader_parameter("energy", 1.0)
	led_mats.append(face)
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(11.6, 3.8)
	qm.material = face
	q.mesh = qm
	q.position = pos + Vector3(0, 0, 0.31)
	add_child(q)
	score_label = Mk.label(self, "0 - 0", 220, pos + Vector3(0, 0.45, 0.35), Color(1, 1, 1), 0.012)
	clock_label = Mk.label(self, "4:00", 120, pos + Vector3(0, -1.2, 0.35), Color(1.0, 0.85, 0.3), 0.012)


func set_scoreboard(score_text: String, clock_text: String) -> void:
	if score_label:
		score_label.text = score_text
		clock_label.text = clock_text


# ----------------------------------------------------------- decoration

func _build_hall(wall_col: Color, banners: bool) -> void:
	var dark := Mk.mat(wall_col, 0.0, 0.1, 0.8)
	Mk.box(self, Vector3(70, 22, 1), Vector3(0, 11, -27), dark)
	Mk.box(self, Vector3(1, 22, 60), Vector3(-30, 11, 0), dark)
	Mk.box(self, Vector3(1, 22, 60), Vector3(30, 11, 0), dark)
	Mk.box(self, Vector3(70, 1, 60), Vector3(0, 17, 0), Mk.mat(wall_col.darkened(0.4), 0.0, 0.1, 0.9))
	# Roof truss with floodlights
	var steel := Mk.mat(Color(0.35, 0.37, 0.4), 0.0, 0.9, 0.35)
	for x in [-12.0, -4.0, 4.0, 12.0]:
		Mk.box(self, Vector3(0.4, 0.6, 30), Vector3(x, 12.5, 0), steel)
	for z in [-9.0, 0.0, 9.0]:
		Mk.box(self, Vector3(34, 0.3, 0.3), Vector3(0, 12.3, z), steel)
	var lamp := Mk.mat(Color(1.0, 0.98, 0.92), 6.0)
	var k := 0
	for x in [-12.0, -4.0, 4.0, 12.0]:
		for z in [-6.0, 6.0]:
			Mk.box(self, Vector3(1.2, 0.25, 0.8), Vector3(x, 12.05, z), lamp)
			var col := Color(1.0, 0.97, 0.9) if style == "indoor" else Color(0.85, 0.92, 1.0)
			_spot(Vector3(x, 12.0, z), Vector3(x * 0.6, 0, z * 0.4), col, 2.0, 38.0, k % 2 == 0)
			k += 1
	if banners:
		var team_cols := [game.team_color(0), game.team_color(1)] if game else [Color(0.2, 0.5, 1), Color(1, 0.3, 0.2)]
		for i in 8:
			var b := MeshInstance3D.new()
			var qm := QuadMesh.new()
			qm.size = Vector2(2.2, 4.5)
			qm.material = Mk.mat(team_cols[i % 2], 0.4, 0.0, 0.8)
			b.mesh = qm
			b.position = Vector3(-21 + i * 6.0, 13.5, -26.4)
			add_child(b)
		for t in ["RIM RUSH", "POWERCHAIR FOOTBALL", "SPIN TO WIN"]:
			var i: int = ["RIM RUSH", "POWERCHAIR FOOTBALL", "SPIN TO WIN"].find(t)
			Mk.label(self, t, 200, Vector3(-18 + i * 18, 19.5 - 3.0, -26.3), Color(1, 1, 1, 0.9), 0.02)
	if style == "ice":
		_snow()


func _snow() -> void:
	var p := GPUParticles3D.new()
	p.amount = 400
	p.lifetime = 8.0
	p.visibility_aabb = AABB(Vector3(-25, -2, -20), Vector3(50, 20, 40))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(22, 0.5, 15)
	pm.gravity = Vector3(0.2, -0.8, 0)
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.3
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.05, 0.05)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = Color(1, 1, 1, 0.8)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	q.material = m
	p.draw_pass_1 = q
	p.position = Vector3(0, 12, 0)
	add_child(p)


func _build_neon() -> void:
	var dark := Mk.mat(Color(0.02, 0.015, 0.04), 0.0, 0.5, 0.3)
	Mk.box(self, Vector3(70, 22, 1), Vector3(0, 11, -27), dark)
	Mk.box(self, Vector3(1, 22, 60), Vector3(-30, 11, 0), dark)
	Mk.box(self, Vector3(1, 22, 60), Vector3(30, 11, 0), dark)
	Mk.box(self, Vector3(70, 1, 60), Vector3(0, 17, 0), dark)
	var pinks := [Color(1.0, 0.15, 0.7), Color(0.1, 0.9, 1.0), Color(0.6, 0.2, 1.0), Color(1.0, 0.8, 0.1)]
	for i in 12:
		var c: Color = pinks[i % pinks.size()]
		Mk.box(self, Vector3(0.12, 14, 0.12), Vector3(-27 + i * 4.9, 8, -26.3), Mk.mat(c, 5.0))
	for y in [4.0, 9.0, 14.0]:
		Mk.box(self, Vector3(60, 0.1, 0.1), Vector3(0, y, -26.3), Mk.mat(Color(0.1, 0.9, 1.0), 4.0))
		Mk.box(self, Vector3(0.1, 0.1, 50), Vector3(-29.3, y, 0), Mk.mat(Color(1.0, 0.15, 0.7), 4.0))
		Mk.box(self, Vector3(0.1, 0.1, 50), Vector3(29.3, y, 0), Mk.mat(Color(1.0, 0.15, 0.7), 4.0))
	Mk.label(self, "NEON ARCADE", 260, Vector3(0, 14.5, -26.2), Color(1.0, 0.3, 0.9), 0.025)
	# Sweeping coloured spotlights
	var k := 0
	for x in [-10.0, 0.0, 10.0]:
		for z in [-5.0, 5.0]:
			var s := _spot(Vector3(x, 12.0, z), Vector3(x * 0.5, 0, 0), pinks[k % pinks.size()], 3.0, 26.0, k < 2)
			moving_lights.append([s, randf() * TAU, s.global_position])
			k += 1
	for x in [-12.0, 12.0]:
		_spot(Vector3(x, 12.0, 0), Vector3(x * 0.6, 0, 0), Color(0.9, 0.85, 1.0), 1.4, 45.0, true)


func _build_rooftop() -> void:
	# The roof deck around the court and a skyline in every direction.
	Mk.box(self, Vector3(80, 1, 60), Vector3(0, -0.6, 0), Mk.mat(Color(0.3, 0.3, 0.32), 0.0, 0.0, 0.9))
	var rail := Mk.mat(Color(0.8, 0.8, 0.85), 0.0, 1.0, 0.2)
	for i in 21:
		Mk.box(self, Vector3(0.08, 1.1, 0.08), Vector3(-20 + i * 2.0, 0.55, -18), rail)
	Mk.box(self, Vector3(40, 0.08, 0.08), Vector3(0, 1.1, -18), rail)
	var win := ShaderMaterial.new()
	win.shader = load("res://shaders/windows.gdshader")
	for i in 60:
		var a := randf() * TAU
		var d := randf_range(45.0, 110.0)
		var h := randf_range(10.0, 70.0)
		var w := randf_range(6.0, 16.0)
		var b := Mk.box(self, Vector3(w, h, w), Vector3(cos(a) * d, h / 2.0 - 20.0, sin(a) * d), win)
		b.rotation.y = randf() * PI
	# AC units and string lights
	for p in [Vector3(-19, 0.6, -14), Vector3(19, 0.6, -14), Vector3(-19, 0.6, 14)]:
		Mk.box(self, Vector3(2.0, 1.2, 1.6), p, Mk.mat(Color(0.6, 0.62, 0.65), 0.0, 0.7, 0.4))
	for i in 18:
		var x := -17.0 + i * 2.0
		Mk.sphere(self, 0.12, Vector3(x, 4.2 + sin(i * 0.9) * 0.3, -12.5), Mk.mat(Color(1.0, 0.8, 0.4), 6.0))
	for x in [-16.0, 16.0]:
		for z in [-10.0, 10.0]:
			Mk.cyl(self, 0.12, 0.15, 9.0, Vector3(x, 4.5, z), rail)
			_spot(Vector3(x, 9.0, z), Vector3(x * 0.3, 0, z * 0.3), Color(1.0, 0.95, 0.85), 1.2, 40.0, false)


func _build_retro() -> void:
	var brick := ShaderMaterial.new()
	brick.shader = load("res://shaders/brick.gdshader")
	Mk.box(self, Vector3(60, 24, 1), Vector3(0, 12, -24), brick)
	Mk.box(self, Vector3(1, 24, 60), Vector3(-27, 12, 0), brick)
	Mk.box(self, Vector3(1, 24, 60), Vector3(27, 12, 0), brick)
	Mk.box(self, Vector3(60, 1, 60), Vector3(0, 22, 0), Mk.mat(Color(0.3, 0.25, 0.2), 0.0, 0.0, 0.9))
	var lamp := Mk.mat(Color(1.0, 0.85, 0.6), 5.0)
	for x in [-12.0, 0.0, 12.0]:
		for z in [-5.0, 5.0]:
			Mk.cyl(self, 0.5, 0.8, 0.5, Vector3(x, 13.0, z), lamp)
			_spot(Vector3(x, 12.8, z), Vector3(x * 0.6, 0, z * 0.4), Color(1.0, 0.85, 0.65), 2.4, 42.0, x == 0.0)
	var pennant_cols := [Color(0.8, 0.15, 0.15), Color(0.9, 0.75, 0.2), Color(0.15, 0.3, 0.7)]
	for i in 6:
		var b := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(3.0, 1.4)
		qm.material = Mk.mat(pennant_cols[i % 3], 0.2, 0.0, 0.8)
		b.mesh = qm
		b.position = Vector3(-17 + i * 7.0, 11.5, -23.4)
		add_child(b)
		Mk.label(self, ["CHAMPS 1987", "STATE FINALS", "GO ROLLERS", "1992", "CITY CUP", "1979"][i], 90, b.position + Vector3(0, 0, 0.02), Color(1, 1, 1), 0.012)


# ------------------------------------------------------------------ pinball

func _build_pinball(colors: Array) -> void:
	var accent := Color(1.0, 0.75, 0.15)
	if style == "neon":
		accent = Color(1.0, 0.2, 0.8)
	elif style == "ice":
		accent = Color(0.3, 0.8, 1.0)
	if def["bumpers"]:
		for p in [Vector3(-5, 0, -5.2), Vector3(5, 0, -5.2), Vector3(-5, 0, 5.2), Vector3(5, 0, 5.2)]:
			var b := Pinball.Bumper.new()
			add_child(b)
			b.setup(game, p, accent)
			bumper_positions.append(p)
	if def["flippers"]:
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var f := Pinball.Flipper.new()
				add_child(f)
				f.setup(game, Vector3(sx * (HALF_X - 1.0), 0, sz * (HALF_Z - 2.6)), 0.0 if sz < 0 else PI, -sx * (1.0 if sz < 0 else -1.0), colors[0 if sx < 0 else 1])
				bumper_positions.append(Vector3(sx * (HALF_X - 1.6), 0, sz * (HALF_Z - 2.6)))
	if def["spinner"]:
		var s := Pinball.SpinnerGate.new()
		add_child(s)
		s.setup(game, Vector3(2.5, 0, -HALF_Z + 0.25), accent)
	if def["ramps"]:
		for sx in [-1.0, 1.0]:
			var r := Pinball.Ramp.new()
			add_child(r)
			r.setup(game, Vector3(sx * 5.5, 0, -HALF_Z + 0.9), 0.0, accent)
	if def["kickbacks"]:
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var kb := Pinball.Kickback.new()
				add_child(kb)
				kb.setup(game, Vector3(sx * (HALF_X - 0.5), 0, sz * (GOAL_HALF_W + 0.35)), sx)
				kickbacks.append(kb)
	if def["lanes"]:
		lane_positions = [Vector3(-9.5, 0, -HALF_Z + 0.75), Vector3(9.5, 0, -HALF_Z + 0.75), Vector3(-9.5, 0, HALF_Z - 0.75), Vector3(9.5, 0, HALF_Z - 0.75)]
		for i in 4:
			var lm := Mk.mat(Color(0.3, 0.3, 0.35), 0.3, 0.2, 0.3)
			lane_mats.append(lm)
			Mk.box(self, Vector3(2.6, 0.02, 0.9), lane_positions[i] + Vector3(0, 0.012, 0), lm)
			for e in [-1.0, 1.0]:
				Mk.box(self, Vector3(0.05, 0.03, 0.9), lane_positions[i] + Vector3(e * 1.3, 0.02, 0), Mk.mat(Color(1, 1, 1), 2.0))
			var lbl := Mk.label(self, ["G", "O", "A", "L"][i], 120, lane_positions[i] + Vector3(0, 0.04, 0), Color(1, 1, 1), 0.009)
			lbl.rotation.x = -PI / 2
			var lsh := BoxShape3D.new()
			lsh.size = Vector3(2.6, 1.2, 0.9)
			lane_areas.append(Mk.area(self, lsh, lane_positions[i] + Vector3(0, 0.6, 0)))
	# Jackpot target on the far wall (only lit during the jackpot event)
	var jsh := BoxShape3D.new()
	jsh.size = Vector3(2.0, 2.0, 1.0)
	jackpot_area = Mk.area(self, jsh, Vector3(-2.5, 1.0, -HALF_Z + 0.5))
	if not def["events"]:
		return
	jackpot_mat = Mk.mat(Color(0.55, 0.42, 0.12), 0.6, 0.8, 0.25)
	var jt := Mk.cyl(self, 0.8, 0.8, 0.08, Vector3(-2.5, 1.0, -HALF_Z + 0.02), jackpot_mat)
	jt.rotation.x = PI / 2
	var jr := Mk.torus(self, 0.8, 0.92, Vector3(-2.5, 1.0, -HALF_Z + 0.05), Mk.mat(Color(1.0, 0.85, 0.3), 2.5, 0.8, 0.2))
	jr.rotation.x = PI / 2
	Mk.label(self, "JACKPOT", 64, Vector3(-2.5, 2.1, -HALF_Z + 0.1), Color(1.0, 0.85, 0.3), 0.008)


func set_lane(i: int, col: Color, lit: bool, flash: bool) -> void:
	if i >= lane_mats.size():
		return
	var m: StandardMaterial3D = lane_mats[i]
	m.albedo_color = col
	m.emission = col
	m.emission_energy_multiplier = 6.0 if flash else (2.0 if lit else 0.3)


func set_jackpot(on: bool) -> void:
	if jackpot_mat == null:
		return
	var c := Color(1.0, 0.8, 0.2) if on else Color(0.55, 0.42, 0.12)
	jackpot_mat.albedo_color = c
	jackpot_mat.emission = c
	jackpot_mat.emission_energy_multiplier = 6.0 if on else 0.6


func set_blackout(on: bool) -> void:
	_blackout_target = 1.0 if on else 0.0


func _process(delta: float) -> void:
	_t += delta
	for ml in moving_lights:
		var s: SpotLight3D = ml[0]
		var ph: float = ml[1]
		var p0: Vector3 = ml[2]
		var tgt := Vector3(sin(_t * 0.6 + ph) * 9.0, 0, cos(_t * 0.45 + ph) * 5.0)
		s.look_at(tgt, Vector3.UP)
		s.global_position = p0
	if absf(_blackout - _blackout_target) > 0.001:
		_blackout = move_toward(_blackout, _blackout_target, delta * 2.0)
		for l in _light_base:
			(l as Light3D).light_energy = _light_base[l] * (1.0 - 0.9 * _blackout)
		env.ambient_light_energy = lerpf(_ambient_base, 0.05, _blackout)
		floor_mat.set_shader_parameter("blackout", _blackout)
		if crowd_mat:
			crowd_mat.set_shader_parameter("darken", _blackout)
