extends Node3D
## One match (or training challenge). Reads Game.match_config, builds the arena,
## spawns teams, runs the rules, events, replays and the HUD.

const Chair = preload("res://scripts/chair.gd")
const Ball = preload("res://scripts/ball.gd")
const Arena = preload("res://scripts/arena.gd")
const Fx = preload("res://scripts/fx.gd")
const Hud = preload("res://scripts/hud.gd")
const AI = preload("res://scripts/ai.gd")
const Mk = preload("res://scripts/mk.gd")

const HALF_X := 14.0
const HALF_Z := 8.0
const REPLAY_SECS := 4.0

var cfg := {}
var mode := "arcade"
var rules := "arcade"
var team_ids := [-1, 0]
var team_defs: Array = []
var arena: Arena
var fx: Fx
var hud: Hud
var ai: AI
var camera: Camera3D
var balls: Array = []
var ball: Ball
var chairs: Array = []
var controlled: Chair = null
var autoplay := false

var score := [0, 0]
var multiplier := [1, 1]
var lanes := [[false, false, false, false], [false, false, false, false]]
var lane_flash := [0.0, 0.0, 0.0, 0.0]
var stats := [{}, {}]
var attack_sign := [1.0, -1.0]
var half := 1
var half_len := 120.0
var time_left := 120.0
var state := "intro"
var state_timer := 0.0
var golden := false
var fever := false
var need_winner := true
var tactic := 0
var paused := false

var event := ""
var event_time := 0.0
var event_warn := 0.0
var next_event := 60.0
var pending_event := ""
var jackpot_open := false
var jackpot_team := -1
var jackpot_time := 0.0
var wind := Vector3.ZERO
var wind_time := 0.0

var foul_timers := {}
var freekick_reason := ""
var excitement := 0.3
var _switch_timer := 0.0
var _replay_buf: Array = []
var _replay_i := 0.0
var _replay_cam_pos := Vector3.ZERO
var _intro_t := 0.0
var _cam_target := Vector3.ZERO
var _last_goal_side := 1.0

# training
var training := ""
var tdata := {}


func _ready() -> void:
	Game.apply_quality()
	cfg = Game.match_config.duplicate(true)
	if cfg.is_empty():
		cfg = {"mode": "arcade", "arena": 1, "team_size": 3, "rules": "arcade", "opponent": randi() % Game.RIVALS.size(), "half_len": 120.0}
	mode = cfg.get("mode", "arcade")
	rules = cfg.get("rules", "arcade")
	half_len = float(cfg.get("half_len", 120.0))
	time_left = half_len
	need_winner = mode != "season"
	training = cfg.get("challenge", "") if mode == "training" else ""
	team_ids = [-1, int(cfg.get("opponent", 0))]
	team_defs = [Game.team_def(team_ids[0]), Game.team_def(team_ids[1])]
	for i in 2:
		stats[i] = {"shots": 0, "spin": 0, "bumps": 0, "poss": 0.0, "fouls": 0}

	fx = Fx.new()
	add_child(fx)
	arena = Arena.new()
	add_child(arena)
	var adef: Dictionary = Game.ARENAS[int(cfg.get("arena", 0))]
	if mode == "classic":
		adef = Game.ARENAS[3]
	arena.build(adef, self, goal_colors())
	for gi in 2:
		arena.goal_areas[gi].body_entered.connect(_on_goal_body.bind(gi))
	for i in arena.lane_areas.size():
		arena.lane_areas[i].body_entered.connect(_on_lane_body.bind(i))
	arena.jackpot_area.body_entered.connect(_on_jackpot_body)

	camera = Camera3D.new()
	camera.fov = 50.0
	camera.far = 400.0
	add_child(camera)
	camera.position = Vector3(0, 30, 40)
	camera.look_at(Vector3.ZERO, Vector3.UP)

	hud = Hud.new()
	add_child(hud)
	hud.build(team_defs[0]["color"])
	hud.set_help_text(Game.settings["one_hand"])
	hud.pause_toggle = func():
		if state != "fulltime" and state != "halftime":
			_set_paused(not paused)

	ai = AI.new(self)
	ball = _spawn_ball(Vector3(0, 0.45, 0))
	if training == "":
		var size := int(cfg.get("team_size", 3))
		for t in 2:
			_spawn_team(t, size)
		if mode == "multiball":
			_spawn_ball(Vector3(0, 0.45, 3))
			_spawn_ball(Vector3(0, 0.45, -3))
		_set_controlled(_first_outfield(0))
		_kickoff(true)
		state = "intro"
		_intro_t = 0.0
		hud.message(team_defs[0]["name"] + "  vs  " + team_defs[1]["name"], 3.0, arena.def["name"] + ("   |   PRO RULES" if rules == "pro" else "   |   ARCADE RULES"))
	else:
		_setup_training()
	Sfx.start_ambience()
	Sfx.set_crowd(0.4)
	if not autoplay:
		Engine.time_scale = float(Game.settings["game_speed"])


func _exit_tree() -> void:
	Engine.time_scale = 1.0
	Sfx.stop_ambience()


# ------------------------------------------------------------- helpers

func team_color(i: int) -> Color:
	return team_defs[i]["color"] if team_defs.size() > i else Color(1, 1, 1)


func team_skill(i: int) -> float:
	var base: float = team_defs[i]["skill"]
	if i == 0:
		return 0.75
	var d: int = Game.settings["difficulty"]
	return clampf(base + [-0.35, 0.0, 0.25][d], 0.05, 1.0)


func team_tactic(i: int) -> String:
	if i == 0:
		return Game.TACTICS[tactic]
	return "Press High" if score[1] < score[0] else "Balanced"


func attack_dir(t: int) -> Vector3:
	return Vector3(attack_sign[t], 0, 0)


## Goal colours: index 0 = goal at -X, coloured by the team that defends it.
func goal_colors() -> Array:
	var def_neg := 0 if attack_sign[0] > 0.0 else 1
	return [team_color(def_neg), team_color(1 - def_neg)]


func is_ball(b) -> bool:
	return b in balls


func is_player_chair(c) -> bool:
	return c == controlled


func _spawn_ball(pos: Vector3) -> Ball:
	var b := Ball.new()
	b.setup(self)
	b.position = pos
	add_child(b)
	balls.append(b)
	return b


func _remove_extra_balls() -> void:
	while balls.size() > 1:
		var b: Ball = balls.pop_back()
		b.queue_free()


func _spawn_team(t: int, size: int) -> void:
	var tdef: Dictionary = team_defs[t]
	var roles := ["attack", "defend"]
	if size == 3:
		roles = ["attack", "defend", "keeper"]
	elif size >= 4:
		roles = ["attack", "attack", "defend", "keeper"]
	for i in size:
		var c := Chair.new()
		c.position = Vector3(-attack_sign[t] * (3.0 + i * 2.5), 0.5, (i - 1) * 2.0)
		add_child(c)
		var type_name: String = tdef["chairs"][i % tdef["chairs"].size()]
		var b := {}
		if t == 0 and i == 0:
			b = Game.save["build"]
			type_name = b["type"]
		c.setup(self, t, tdef, type_name, roles[i], [9, 4, 1, 7][i] if roles[i] != "keeper" else 1, b)
		c.grip_mult = float(arena.def["grip"])
		if t == 1 or i > 0:
			c.speed_scale = lerpf(0.86, 1.0, team_skill(t))
		chairs.append(c)
		ai.register(c)


func _first_outfield(t: int) -> Chair:
	for c in chairs:
		if c.team == t and c.role != "keeper":
			return c
	return null


func _set_controlled(c: Chair) -> void:
	if c == null:
		return
	if controlled:
		controlled.set_controlled(false)
	controlled = c
	c.set_controlled(true)


func _formation(t: int) -> Array:
	var sgn: float = -attack_sign[t]
	var out := []
	for c in chairs:
		if c.team != t:
			continue
		out.append(c)
	var spots := []
	var outfield := 0
	for c in out:
		var p: Vector3
		if c.role == "keeper":
			p = Vector3(sgn * (HALF_X - 1.4), 0, 0)
		elif c.role == "defend":
			p = Vector3(sgn * 8.5, 0, 1.5 if outfield % 2 == 0 else -1.5)
			outfield += 1
		else:
			p = Vector3(sgn * (2.6 + outfield * 1.2), 0, [0.0, 3.0, -3.0][outfield % 3])
			outfield += 1
		spots.append([c, p])
	return spots


func _kickoff(first := false) -> void:
	_remove_extra_balls_unless_mayhem()
	for i in balls.size():
		balls[i].reset_to(Vector3(0, 0.45, [0.0, 3.0, -3.0][i % 3]))
	for t in 2:
		for e in _formation(t):
			e[0].reset_to(e[1], attack_dir(t))
			e[0].frozen_flag = true
	for c in chairs:
		c.freeze = false
	state = "countdown"
	state_timer = 3.0
	if not first:
		hud.clear_message()


func _remove_extra_balls_unless_mayhem() -> void:
	if mode == "multiball":
		return
	_remove_extra_balls()


func _freeze_all(on: bool) -> void:
	for c in chairs:
		c.frozen_flag = on


# ------------------------------------------------------------ main loop

func _process(delta: float) -> void:
	if Input.is_action_just_pressed("help"):
		hud.toggle_help()
	if paused:
		return
	if Input.is_action_just_pressed("camera"):
		Game.settings["chase_cam"] = not Game.settings["chase_cam"]
	if Input.is_action_just_pressed("tactic_next"):
		tactic = (tactic + 1) % Game.TACTICS.size()
		hud.banner("Tactic: " + Game.TACTICS[tactic], 1.5)
	if Input.is_action_just_pressed("tactic_prev"):
		tactic = (tactic + Game.TACTICS.size() - 1) % Game.TACTICS.size()
		hud.banner("Tactic: " + Game.TACTICS[tactic], 1.5)

	match state:
		"intro":
			_intro_t += delta
			if _intro_t > 3.0 or Input.is_action_just_pressed("skip"):
				state = "countdown"
				state_timer = 3.0
		"countdown":
			var before := int(ceil(state_timer))
			state_timer -= delta
			var now := int(ceil(state_timer))
			if now != before and now > 0:
				Sfx.play("beep", -4.0)
				hud.message(str(now), 0.9)
			if state_timer <= 0.0:
				state = "play"
				_freeze_all(false)
				Sfx.play("whistle", -6.0)
				hud.message("GO!", 0.7)
				if training == "":
					_maybe_banner_fever()
		"play":
			if training != "":
				_training_process(delta)
			else:
				_play_process(delta)
		"goal":
			state_timer -= delta
			if state_timer <= 0.0:
				if training != "":
					_training_after_goal()
				elif _replay_buf.size() > 30:
					_start_replay()
				else:
					_after_goal()
		"replay":
			_replay_process(delta)
		"freekick":
			state_timer -= delta
			if state_timer <= 0.0:
				state = "play"
				_freeze_all(false)
				Sfx.play("whistle", -6.0)
		"halftime":
			pass

	_update_lanes(delta)
	_update_camera(delta)
	_update_hud()
	excitement = lerpf(excitement, _base_excitement(), minf(1.0, delta * 1.5))
	arena.set_excitement(excitement)
	Sfx.set_crowd(excitement)
	if controlled:
		Sfx.set_motor(controlled.linear_velocity.length() / 7.0 + absf(controlled.angular_velocity.y) / 30.0)
	arena.set_scoreboard("%d - %d" % [score[0], score[1]], _clock_text())


func _base_excitement() -> float:
	var x := 0.25
	for b in balls:
		var d: float = minf(absf(b.global_position.x - HALF_X), absf(b.global_position.x + HALF_X))
		x = maxf(x, 0.25 + clampf((6.0 - d) / 6.0, 0.0, 1.0) * 0.5)
	if fever or golden:
		x += 0.2
	if state == "goal":
		x = 1.0
	return clampf(x, 0.0, 1.0)


func _play_process(delta: float) -> void:
	time_left -= delta if not golden else 0.0
	if not golden and half == 2 and time_left <= 30.0 and not fever:
		fever = true
		hud.banner("OVERTIME FEVER!  Goals count double", 3.0)
		Sfx.play("siren", -6.0)
		arena.flash_leds(true)
	if time_left <= 0.0 and not golden:
		_end_half()
		return
	_update_possession(delta)
	if rules == "pro":
		_check_pro_rules(delta)
	_update_events(delta)
	_auto_switch(delta)
	if wind_time > 0.0:
		wind_time -= delta


func _physics_process(delta: float) -> void:
	for b in balls:
		var bp: Vector3 = b.global_position
		if bp.y < -2.0 or absf(bp.x) > HALF_X + 3.5 or absf(bp.z) > HALF_Z + 1.5:
			b.reset_to(Vector3(0, 1.0, 0))
	if state == "replay":
		return
	if state != "play" or paused:
		for c in chairs:
			c.intent = Chair.blank_intent()
		return
	if Input.is_action_just_pressed("switch") and controlled and not Game.settings["one_hand"]:
		_switch_to_next()
	for c in chairs:
		if c == controlled and not autoplay:
			c.intent = _player_intent(c)
		else:
			c.intent = ai.intent(c, delta)
	_record_replay()


func _player_intent(c: Chair) -> Dictionary:
	var it := Chair.blank_intent()
	if Game.settings["one_hand"]:
		# Stick points where to go (relative to the camera); one button spins toward the ball.
		var v := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		var cf := -camera.global_transform.basis.z
		cf.y = 0.0
		cf = cf.normalized()
		var cr := camera.global_transform.basis.x
		cr.y = 0.0
		cr = cr.normalized()
		it["move"] = (cr * v.x - cf * v.y)
		it["boost"] = Input.is_action_pressed("boost")
		if Input.is_action_pressed("one_hand_spin"):
			var b = ai.nearest_ball(c.global_position)
			if b:
				var r: Vector3 = b.global_position - c.global_position
				r.y = 0.0
				var sweep := Vector3(0, -1, 0).cross(r)
				it["spin"] = 1.0 if sweep.dot(attack_dir(c.team)) >= 0.0 else -1.0
				it["boost"] = true
		return it
	it["relative"] = true
	it["throttle"] = Input.get_axis("move_down", "move_up")
	it["steer"] = Input.get_axis("move_left", "move_right")
	it["boost"] = Input.is_action_pressed("boost")
	it["brake"] = Input.is_action_pressed("brake")
	it["spin"] = Input.get_axis("spin_left", "spin_right")
	return it


func _switch_to_next() -> void:
	var mates := []
	for c in chairs:
		if c.team == controlled.team:
			mates.append(c)
	var i := mates.find(controlled)
	_set_controlled(mates[(i + 1) % mates.size()])
	Sfx.play("click", -8.0)


func _auto_switch(delta: float) -> void:
	if not (Game.settings["auto_switch"] or Game.settings["one_hand"]) or controlled == null:
		return
	var b = ai.nearest_ball(controlled.global_position)
	var my_d: float = controlled.global_position.distance_to(b.global_position)
	if my_d < 2.5:
		_switch_timer = 0.0
		return
	var best: Chair = null
	var bd := my_d - 3.0
	for c in chairs:
		if c.team != controlled.team or c == controlled:
			continue
		if c.role == "keeper" and absf(b.global_position.x - (-attack_sign[0] * HALF_X)) > 5.0:
			continue
		var d: float = c.global_position.distance_to(b.global_position)
		if d < bd:
			bd = d
			best = c
	if best:
		_switch_timer += delta
		if _switch_timer > 0.45:
			_set_controlled(best)
			_switch_timer = 0.0
	else:
		_switch_timer = 0.0


func _update_possession(delta: float) -> void:
	if ball.last_team >= 0:
		stats[ball.last_team]["poss"] += delta


# ----------------------------------------------------------- ball events

func on_ball_hit(b: Ball, chair, v: Vector3, approach: float) -> Vector3:
	var strength := clampf(approach / 14.0, 0.0, 1.0)
	var spinning := absf(chair.angular_velocity.y) > 4.0
	if spinning:
		stats[chair.team]["spin"] += 1
	# Assist: nudge hard hits toward the opponent goal (yours from settings, AI by skill).
	var assist: float = Game.settings["assist"] if chair.team == 0 else team_skill(chair.team) * 0.5
	if approach > 5.0 and assist > 0.0:
		var goal := attack_dir(chair.team) * HALF_X
		var to_goal := goal - b.global_position
		to_goal.y = 0.0
		var flat := Vector3(v.x, 0, v.z)
		var ang := flat.signed_angle_to(to_goal, Vector3.UP)
		if absf(ang) < 1.0:
			flat = flat.rotated(Vector3.UP, clampf(ang, -0.35, 0.35) * assist)
			v = Vector3(flat.x, v.y, flat.z)
	var flat_dir := Vector3(v.x, 0, v.z)
	if flat_dir.length() > 9.0 and flat_dir.normalized().dot(attack_dir(chair.team)) > 0.5:
		stats[chair.team]["shots"] += 1
	if approach > 7.0:
		Sfx.play("hit_hard", lerpf(-8.0, 0.0, strength), 0.9 + strength * 0.2)
	else:
		Sfx.play("hit_soft", lerpf(-16.0, -6.0, strength))
	fx.hit(b.global_position, team_color(chair.team), strength)
	excitement = minf(1.0, excitement + strength * 0.3)
	if training == "power" and tdata.get("measuring", false):
		tdata["best_try"] = maxf(float(tdata.get("best_try", 0.0)), v.length())
	return v


func on_ball_wall(_b: Ball) -> void:
	Sfx.play("bump", -18.0, 1.6)


func ball_extra_force(b: Ball) -> Vector3:
	var f := Vector3.ZERO
	if event == "magnet":
		var to_c: Vector3 = -b.global_position
		to_c.y = 0.0
		if to_c.length() < 7.0:
			f += to_c.normalized() * 6.0
	if wind_time > 0.0:
		f += wind
	return f


func on_chair_contact(a: Chair, b) -> void:
	if a.get_instance_id() > b.get_instance_id():
		return  # handle each pair once
	var rel: float = (a.linear_velocity - b.linear_velocity).length()
	if rel < 2.0:
		return
	var mid: Vector3 = (a.global_position + b.global_position) * 0.5
	Sfx.play("bump", lerpf(-14.0, -2.0, clampf(rel / 9.0, 0.0, 1.0)), 1.0 + randf() * 0.2)
	fx.bump(mid)
	if a.team != b.team:
		stats[a.team]["bumps"] += 1
		stats[b.team]["bumps"] += 1
		if rules == "arcade" and state == "play":
			# Foul: a fast hit from behind.
			for pair in [[a, b], [b, a]]:
				var hitter = pair[0]
				var victim = pair[1]
				var hv: Vector3 = hitter.linear_velocity
				if hv.length() > 5.0 and victim.forward().dot((hitter.global_position - victim.global_position).normalized()) < -0.6:
					hitter.lockout = 3.0
					hitter.battery = 0.0
					stats[hitter.team]["fouls"] += 1
					Sfx.play("foul", -6.0)
					hud.banner("FOUL! Hit from behind. %s boost locked" % team_defs[hitter.team]["short"], 2.0)
					break


func on_pinball(kind: String, pos: Vector3, b) -> void:
	match kind:
		"bumper":
			Sfx.play("ding", -6.0)
			fx.ring(pos, Color(1.0, 0.8, 0.3))
		"flipper":
			Sfx.play("flipper", -4.0)
		"spinner":
			Sfx.play("lane", -6.0, 1.3)
			if b.last_team >= 0:
				for c in chairs:
					if c.team == b.last_team:
						c.battery = minf(100.0, c.battery + 30.0)
				hud.banner("SPINNER! %s boost +30" % team_defs[b.last_team]["short"], 1.5)
		"ramp":
			Sfx.play("boost", -4.0, 1.4)
		"kickback":
			Sfx.play("ding", -4.0, 0.7)
			hud.banner("KICKBACK SAVE!", 1.5)
	fx.hit(pos + Vector3.UP * 0.5, Color(1, 0.9, 0.5), 0.5)


func _on_lane_body(body: Node, i: int) -> void:
	if not is_ball(body) or state != "play":
		return
	var t: int = body.last_team
	lane_flash[i] = 0.4
	if t < 0 or lanes[t][i]:
		return
	lanes[t][i] = true
	Sfx.play("lane", -6.0)
	if not (false in lanes[t]):
		multiplier[t] = 2
		lanes[t] = [false, false, false, false]
		hud.banner("G-O-A-L lit! Next %s goal counts x2" % team_defs[t]["short"], 2.5)
		Sfx.play("jackpot", -4.0)


func _on_jackpot_body(body: Node) -> void:
	if not jackpot_open or not is_ball(body) or body.last_team < 0:
		return
	jackpot_open = false
	arena.set_jackpot(false)
	jackpot_team = body.last_team
	jackpot_time = 10.0
	Sfx.play("jackpot", 0.0)
	hud.banner("JACKPOT! %s: score in 10 s for x3" % team_defs[jackpot_team]["short"], 3.0)
	fx.goal(body.global_position, Color(1.0, 0.8, 0.2))


func _on_goal_body(body: Node, gi: int) -> void:
	if not is_ball(body) or state != "play":
		return
	var gx := -1.0 if gi == 0 else 1.0
	var scorer := 0 if attack_sign[0] == gx else 1
	if training != "":
		_training_goal(body, scorer)
		return
	var pts: int = multiplier[scorer]
	multiplier[scorer] = 1
	if jackpot_team == scorer and jackpot_time > 0.0:
		pts *= 3
		jackpot_team = -1
	if fever:
		pts *= 2
	score[scorer] += pts
	var txt: String = "GOAL!"
	var sub: String = team_defs[scorer]["name"]
	if pts > 1:
		sub += "   +%d" % pts
	hud.message(txt, 2.6, sub)
	Sfx.play("horn", -2.0)
	Sfx.play("cheer", -2.0)
	fx.goal(Vector3(gx * HALF_X, 0, 0), team_color(scorer))
	arena.flash_leds(true)
	excitement = 1.0
	_last_goal_side = gx
	state = "goal"
	state_timer = 2.6
	if golden:
		state_timer = 2.6
		golden = false
		time_left = 0.0


func _after_goal() -> void:
	arena.flash_leds(fever)
	if time_left <= 0.0 and half >= 2:
		_full_time()
		return
	_kickoff()


# ---------------------------------------------------------------- halves

func _clock_text() -> String:
	if golden:
		return "GOLDEN"
	var t := int(ceil(maxf(time_left, 0.0)))
	return "%d:%02d" % [floori(t / 60.0), t % 60]


func _maybe_banner_fever() -> void:
	pass


func _end_half() -> void:
	_freeze_all(true)
	Sfx.play("whistle", -4.0)
	if half == 1:
		state = "halftime"
		hud.show_panel("HALF TIME", _stat_rows(), [["Second half", _start_second_half]], "Teams swap ends")
	else:
		if score[0] == score[1] and need_winner:
			golden = true
			hud.message("GOLDEN GOAL", 2.0, "Next goal wins")
			Sfx.play("siren", -6.0)
			_kickoff()
		else:
			_full_time()


func _start_second_half() -> void:
	hud.hide_panel()
	half = 2
	time_left = half_len
	attack_sign = [-attack_sign[0], -attack_sign[1]]
	arena.set_goal_colors(goal_colors())
	_kickoff()


func _stat_rows() -> Array:
	var total: float = maxf(0.1, stats[0]["poss"] + stats[1]["poss"])
	return [
		[team_defs[0]["short"], "", team_defs[1]["short"]],
		[score[0], "Goals", score[1]],
		[stats[0]["shots"], "Shots", stats[1]["shots"]],
		[stats[0]["spin"], "Spin hits", stats[1]["spin"]],
		[stats[0]["bumps"], "Bumps", stats[1]["bumps"]],
		["%d%%" % int(stats[0]["poss"] / total * 100.0), "Possession", "%d%%" % int(stats[1]["poss"] / total * 100.0)],
		[stats[0]["fouls"], "Fouls", stats[1]["fouls"]],
	]


func _full_time() -> void:
	state = "fulltime"
	_freeze_all(true)
	Sfx.play("whistle", -2.0)
	Sfx.play("horn", -6.0)
	var won: bool = score[0] > score[1]
	var drew: bool = score[0] == score[1]
	var mult: float = [0.8, 1.0, 1.3][int(Game.settings["difficulty"])]
	var coins := int(((150 if won else (80 if drew else 40)) + score[0] * 10) * mult)
	Game.save["coins"] += coins
	Game.save["played"] += 1
	if won:
		Game.save["wins"] += 1
	var title := "YOU WIN!" if won else ("DRAW" if drew else "DEFEAT")
	var sub := "%s %d - %d %s     +%d coins" % [team_defs[0]["name"], score[0], score[1], team_defs[1]["name"], coins]
	if mode == "season":
		Game.season_play_round(score[0], score[1])
	Game.save_game()
	Game.last_result = {"score": score.duplicate(), "coins": coins}
	hud.show_panel(title, _stat_rows(), [["Continue", _to_menu], ["Rematch", _restart]], sub)


func _set_paused(on: bool) -> void:
	paused = on
	get_tree().paused = on
	if on:
		hud.show_pause(true, [["Resume", func(): _set_paused(false)], ["Restart", _restart], ["Quit to menu", _to_menu]])
	else:
		hud.show_pause(false)


func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _to_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://menu.tscn")


# ---------------------------------------------------------------- events

func _update_events(delta: float) -> void:
	if jackpot_time > 0.0:
		jackpot_time -= delta
		if jackpot_time <= 0.0:
			jackpot_team = -1
	if not arena.def["events"] or mode == "classic":
		return
	if event != "":
		event_time -= delta
		if event_time <= 0.0:
			_end_event()
		return
	if pending_event != "":
		event_warn -= delta
		if event_warn <= 0.0:
			_start_event(pending_event)
			pending_event = ""
		return
	next_event -= delta
	if next_event <= 0.0:
		var options := ["multiball", "jackpot", "magnet"]
		if not Game.settings["reduce_flash"]:
			options.append("blackout")
		if arena.style == "rooftop":
			options.append("wind")
			options.append("wind")
		if mode == "multiball":
			options.erase("multiball")
		pending_event = options[randi() % options.size()]
		event_warn = 3.0
		var names := {"multiball": "MULTIBALL", "jackpot": "JACKPOT", "magnet": "MAGNET FIELD", "blackout": "BLACKOUT", "wind": "WIND GUST"}
		hud.banner("%s in 3..." % names[pending_event], 3.0)
		Sfx.play("siren", -10.0)


func _start_event(e: String) -> void:
	event = e
	match e:
		"multiball":
			event_time = 20.0
			for z in [2.5, -2.5]:
				var nb := _spawn_ball(Vector3(0, 2.5, z))
				nb.linear_velocity = Vector3(randf_range(-3, 3), 0, z)
			hud.banner("MULTIBALL!  Every goal counts", 2.5)
			Sfx.play("jackpot", -2.0)
		"jackpot":
			event_time = 15.0
			jackpot_open = true
			arena.set_jackpot(true)
			hud.banner("JACKPOT OPEN!  Hit the gold target", 2.5)
		"magnet":
			event_time = 15.0
			hud.banner("MAGNET FIELD!", 2.0)
		"blackout":
			event_time = 12.0
			arena.set_blackout(true)
			for b in balls:
				b.set_glow(2.0)
			hud.banner("BLACKOUT!", 2.0)
		"wind":
			event_time = 10.0
			wind_time = 10.0
			wind = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * 3.5
			hud.banner("WIND GUST!", 2.0)


func _end_event() -> void:
	match event:
		"multiball":
			if state == "play":
				_remove_extra_balls()
		"jackpot":
			jackpot_open = false
			arena.set_jackpot(false)
		"blackout":
			arena.set_blackout(false)
			for b in balls:
				b.set_glow(0.25)
		"wind":
			wind_time = 0.0
	event = ""
	next_event = randf_range(25.0, 40.0)


# ------------------------------------------------------------- pro rules

func _check_pro_rules(delta: float) -> void:
	var bp := ball.global_position
	var carrier := -1
	var cd := 1.8
	for c in chairs:
		var d: float = c.global_position.distance_to(bp)
		if d < cd:
			cd = d
			carrier = c.team
	for t in 2:
		var key2 := "2v1_%d" % t
		var keyg := "area_%d" % t
		# 2-on-1: only one defender within 3 m of an opponent with the ball.
		var near := 0
		if carrier >= 0 and carrier != t:
			for c in chairs:
				if c.team == t and c.global_position.distance_to(bp) < 3.0:
					near += 1
		foul_timers[key2] = foul_timers.get(key2, 0.0) + delta if near >= 2 else 0.0
		# Goal area: keeper + one defender at most.
		var own_x: float = -attack_sign[t] * HALF_X
		var inside := 0
		for c in chairs:
			if c.team == t and absf(c.global_position.x - own_x) < 4.0 and absf(c.global_position.z) < 3.5:
				inside += 1
		foul_timers[keyg] = foul_timers.get(keyg, 0.0) + delta if inside > 2 else 0.0
		if foul_timers[key2] > 1.2:
			_free_kick(1 - t, bp, "2-on-1 rule")
			return
		if foul_timers[keyg] > 1.0:
			_free_kick(1 - t, Vector3(own_x + attack_sign[t] * 5.5, 0, 0), "Too many in the goal area")
			return


func _free_kick(team: int, spot: Vector3, reason: String) -> void:
	foul_timers.clear()
	stats[1 - team]["fouls"] += 1
	spot.x = clampf(spot.x, -HALF_X + 2.0, HALF_X - 2.0)
	spot.z = clampf(spot.z, -HALF_Z + 1.5, HALF_Z - 1.5)
	_remove_extra_balls_unless_mayhem()
	ball.reset_to(Vector3(spot.x, 0.45, spot.z))
	var taker: Chair = null
	var td := 1e9
	for c in chairs:
		if c.team == team and c.role != "keeper":
			var d: float = c.global_position.distance_to(spot)
			if d < td:
				td = d
				taker = c
	for c in chairs:
		var p: Vector3 = c.global_position
		if c == taker:
			c.reset_to(spot - attack_dir(team) * 1.9, attack_dir(team))
		elif c.team != team and p.distance_to(spot) < 5.0:
			var away := (p - spot)
			away.y = 0.0
			away = away.normalized() if away.length() > 0.1 else -attack_dir(team)
			var np := spot + away * 5.2
			np.x = clampf(np.x, -HALF_X + 1.0, HALF_X - 1.0)
			np.z = clampf(np.z, -HALF_Z + 1.0, HALF_Z - 1.0)
			c.reset_to(np, (spot - np).normalized())
		c.frozen_flag = true
	state = "freekick"
	state_timer = 2.5
	Sfx.play("whistle", -4.0)
	hud.banner("FREE KICK %s  (%s)" % [team_defs[team]["short"], reason], 2.5)
	if team == 0:
		_set_controlled(taker)


# ---------------------------------------------------------------- replay

func _record_replay() -> void:
	var frame := [ball.global_transform]
	for c in chairs:
		frame.append(c.global_transform)
	_replay_buf.append(frame)
	var maxf_ := int(REPLAY_SECS * Engine.physics_ticks_per_second)
	if _replay_buf.size() > maxf_:
		_replay_buf.pop_front()


func _start_replay() -> void:
	state = "replay"
	_replay_i = 0.0
	hud.set_replay(true)
	hud.clear_message()
	for c in chairs:
		c.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		c.freeze = true
	ball.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	ball.freeze = true
	for b in balls:
		if b != ball:
			b.visible = false
	_replay_cam_pos = Vector3(_last_goal_side * (HALF_X - 3.0), 2.2, 6.5)


func _replay_process(delta: float) -> void:
	_replay_i += delta * Engine.physics_ticks_per_second * 0.5
	var i := int(_replay_i)
	if i >= _replay_buf.size() or Input.is_action_just_pressed("skip"):
		_end_replay()
		return
	var frame: Array = _replay_buf[i]
	ball.global_transform = frame[0]
	for k in chairs.size():
		chairs[k].global_transform = frame[k + 1]


func _end_replay() -> void:
	hud.set_replay(false)
	_replay_buf.clear()
	for c in chairs:
		c.freeze = false
	ball.freeze = false
	for b in balls:
		b.visible = true
	_after_goal()


# ---------------------------------------------------------------- camera

func _update_camera(delta: float) -> void:
	var shake := fx.shake
	fx.shake = maxf(0.0, fx.shake - delta * 1.8)
	var focus := ball.global_position
	if state == "intro":
		var t := clampf(_intro_t / 3.0, 0.0, 1.0)
		var a := lerpf(-1.2, 0.0, t)
		var pos := Vector3(sin(a) * 26.0, lerpf(22.0, 16.0, t), cos(a) * 26.0 * lerpf(1.0, 0.68, t))
		camera.position = pos
		camera.look_at(Vector3(0, 0, 1.0), Vector3.UP)
		return
	if state == "replay":
		camera.position = camera.position.lerp(_replay_cam_pos, minf(1.0, delta * 4.0))
		camera.look_at(ball.global_position + Vector3.UP * 0.3, Vector3.UP)
		return
	if state == "halftime" or state == "fulltime":
		var a2 := Time.get_ticks_msec() / 8000.0
		camera.position = camera.position.lerp(Vector3(sin(a2) * 24.0, 13.0, cos(a2) * 24.0), minf(1.0, delta))
		camera.look_at(Vector3.ZERO, Vector3.UP)
		return
	if Game.settings["chase_cam"] and controlled:
		var f := controlled.forward()
		var cpos := controlled.global_position
		var want := cpos - f * 6.0 + Vector3.UP * 3.6
		camera.position = camera.position.lerp(want, minf(1.0, delta * 6.0))
		_cam_target = _cam_target.lerp(cpos + f * 3.0, minf(1.0, delta * 8.0))
	else:
		var tx := clampf(focus.x * 0.55, -6.0, 6.0)
		var want2 := Vector3(tx, 16.0, 17.0)
		camera.position = camera.position.lerp(want2, minf(1.0, delta * 3.0))
		_cam_target = _cam_target.lerp(Vector3(camera.position.x, 0, 2.2), minf(1.0, delta * 6.0))
	if shake > 0.0:
		camera.position += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * shake * 0.35
	camera.look_at(_cam_target, Vector3.UP)


# ------------------------------------------------------------------ HUD

func _update_lanes(delta: float) -> void:
	for i in arena.lane_mats.size():
		lane_flash[i] = maxf(0.0, lane_flash[i] - delta)
		var c := Color(0.3, 0.3, 0.35)
		var lit := false
		if lanes[0][i] and lanes[1][i]:
			c = team_color(0).lerp(team_color(1), 0.5)
			lit = true
		elif lanes[0][i]:
			c = team_color(0)
			lit = true
		elif lanes[1][i]:
			c = team_color(1)
			lit = true
		arena.set_lane(i, c, lit, lane_flash[i] > 0.0)


func _update_hud() -> void:
	var half_txt := "TRAINING" if training != "" else ("GOLDEN" if golden else ("1ST" if half == 1 else "2ND"))
	if fever:
		half_txt += "  FEVER x2"
	hud.set_score([team_defs[0]["short"], team_defs[1]["short"]], [team_color(0), team_color(1)], score, _clock_text() if training == "" else _training_clock(), half_txt)
	if training == "" and not arena.lane_mats.is_empty():
		var parts := []
		for t in 2:
			var s: String = team_defs[t]["short"] + "  "
			for i in 4:
				s += (["G", "O", "A", "L"][i] if lanes[t][i] else "_") + " "
			if multiplier[t] > 1:
				s += " x%d" % multiplier[t]
			parts.append(s)
		hud.set_lanes(parts[0] + "      " + parts[1])
	if controlled:
		hud.set_player("#%d  %s%s" % [controlled.number, controlled.chair_type, "  (keeper)" if controlled.role == "keeper" else ""],
			controlled.stats["desc"], controlled.battery, "Tactic: " + Game.TACTICS[tactic] if training == "" else "")


# -------------------------------------------------------------- training

func _setup_training() -> void:
	hud.set_lanes("")
	var tdef: Dictionary = team_defs[0]
	var c := Chair.new()
	c.position = Vector3(-6, 0.5, 0)
	add_child(c)
	c.setup(self, 0, tdef, Game.save["build"]["type"], "keeper" if training == "keeper" else "attack", 9, Game.save["build"])
	c.grip_mult = float(arena.def["grip"])
	chairs.append(c)
	ai.register(c)
	_set_controlled(c)
	var info: Dictionary = {}
	for ch in Game.CHALLENGES:
		if ch["id"] == training:
			info = ch
	tdata = {"info": info, "time": 0.0, "done": false}
	hud.message(info.get("name", "Training"), 2.5, info.get("desc", ""))
	match training:
		"power":
			tdata["try"] = 0
			tdata["best"] = 0.0
			_power_setup()
		"targets":
			tdata["targets"] = [Vector3(-3, 0, -4), Vector3(5, 0, 3), Vector3(9, 0, -5), Vector3(0, 0, 5), Vector3(-8, 0, 4), Vector3(-10, 0, -4)]
			tdata["idx"] = 0
			_make_target()
			c.reset_to(Vector3(-6, 0, 0), Vector3.RIGHT)
			ball.reset_to(Vector3(-4, 0.45, 0))
		"slalom":
			tdata["gates"] = []
			tdata["idx"] = 0
			for i in 8:
				var gp := Vector3(-10 + i * 2.9, 0, (3.0 if i % 2 == 0 else -3.0))
				tdata["gates"].append(_make_gate(gp, i))
			ball.reset_to(Vector3(0, 0.45, 7.0))
			c.reset_to(Vector3(-13, 0, 0), Vector3.RIGHT)
		"bank":
			tdata["goals"] = 0
			c.reset_to(Vector3(-4, 0, 0), Vector3.RIGHT)
			ball.reset_to(Vector3(-1, 0.45, 0))
		"keeper":
			tdata["shots"] = 0
			tdata["saves"] = 0
			tdata["shot_t"] = 2.0
			tdata["live"] = false
			c.reset_to(Vector3(-HALF_X + 1.4, 0, 0), Vector3.RIGHT)
			ball.reset_to(Vector3(0, 0.45, 0))
	state = "countdown"
	state_timer = 3.0


func _training_clock() -> String:
	match training:
		"power":
			return "Try %d/5" % mini(5, int(tdata.get("try", 0)) + 1)
		"keeper":
			return "Shot %d/10" % mini(10, int(tdata.get("shots", 0)))
	var t := float(tdata.get("time", 0.0))
	return "%d:%04.1f" % [floori(t / 60.0), fmod(t, 60.0)]


func _power_setup() -> void:
	var c: Chair = chairs[0]
	c.reset_to(Vector3(0, 0, 0), Vector3.RIGHT)
	ball.reset_to(Vector3(0.5, 0.45, 1.3))
	tdata["measuring"] = true
	tdata["best_try"] = 0.0
	tdata["try_t"] = 0.0
	hud.set_objective("Spin into the ball: boost + right stick (or Shift + arrows)")


func _make_target() -> void:
	if tdata.has("target_node"):
		tdata["target_node"].queue_free()
	var idx: int = tdata["idx"]
	if idx >= tdata["targets"].size():
		return
	var p: Vector3 = tdata["targets"][idx]
	var n := Node3D.new()
	n.position = p
	add_child(n)
	var ring := Mk.torus(n, 1.05, 1.2, Vector3(0, 0.05, 0), Mk.mat(Color(1.0, 0.8, 0.2), 5.0))
	ring.name = "Ring"
	var tl := Mk.label(n, str(idx + 1), 140, Vector3(0, 2.0, 0), Color(1, 0.9, 0.4), 0.012)
	tl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	var sh := CylinderShape3D.new()
	sh.radius = 1.1
	sh.height = 2.0
	var a := Mk.area(n, sh, Vector3(0, 1.0, 0))
	a.body_entered.connect(_on_target_body)
	tdata["target_node"] = n
	hud.set_objective("Target %d of %d" % [idx + 1, tdata["targets"].size()])


func _on_target_body(b: Node) -> void:
	if is_ball(b) and tdata.has("target_node"):
		_target_hit()


func _target_hit() -> void:
	Sfx.play("lane", -2.0)
	fx.goal(tdata["target_node"].global_position, Color(1.0, 0.8, 0.2))
	tdata["idx"] += 1
	if tdata["idx"] >= tdata["targets"].size():
		tdata["target_node"].queue_free()
		tdata.erase("target_node")
		_training_finish(float(tdata["time"]))
	else:
		call_deferred("_make_target")


func _make_gate(p: Vector3, i: int) -> Dictionary:
	var n := Node3D.new()
	n.position = p
	add_child(n)
	var m := Mk.mat(Color(1.0, 0.5, 0.1), 2.0)
	for sz in [-1.2, 1.2]:
		Mk.cyl(n, 0.12, 0.2, 1.0, Vector3(0, 0.5, sz), m)
	var bar := Mk.box(n, Vector3(0.05, 0.05, 2.4), Vector3(0, 1.0, 0), m)
	bar.name = "Bar"
	var gl := Mk.label(n, str(i + 1), 100, Vector3(0, 1.6, 0), Color(1, 1, 1), 0.01)
	gl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.6, 2.0, 2.2)
	var a := Mk.area(n, sh, Vector3(0, 1.0, 0))
	a.body_entered.connect(_on_gate_body.bind(i))
	return {"node": n, "mat": m}


func _on_gate_body(b: Node, i: int) -> void:
	if b == controlled:
		_gate_hit(i)


func _gate_hit(i: int) -> void:
	if i != tdata["idx"]:
		return
	var g: Dictionary = tdata["gates"][i]
	g["mat"].albedo_color = Color(0.2, 1.0, 0.4)
	g["mat"].emission = Color(0.2, 1.0, 0.4)
	Sfx.play("lane", -6.0)
	tdata["idx"] += 1
	hud.set_objective("Gate %d of 8" % mini(8, tdata["idx"] + 1))
	if tdata["idx"] >= 8:
		_training_finish(float(tdata["time"]))


func _training_process(delta: float) -> void:
	if tdata.get("done", false):
		return
	tdata["time"] = float(tdata["time"]) + delta
	match training:
		"power":
			tdata["try_t"] = float(tdata["try_t"]) + delta
			var speed := float(tdata.get("best_try", 0.0))
			hud.set_speed_text("%.1f m/s" % speed if speed > 0.0 else "")
			if (speed > 0.0 and tdata["try_t"] > 2.0) or tdata["try_t"] > 7.0:
				tdata["best"] = maxf(float(tdata["best"]), speed)
				hud.banner("Try %d: %.1f m/s" % [int(tdata["try"]) + 1, speed], 1.5)
				tdata["try"] = int(tdata["try"]) + 1
				if tdata["try"] >= 5:
					_training_finish(float(tdata["best"]))
				else:
					_power_setup()
					_freeze_all(true)
					state = "countdown"
					state_timer = 1.0
		"targets":
			pass
		"slalom":
			pass
		"bank":
			hud.set_objective("Goals: %d / 3   (must touch a side wall first)" % tdata["goals"])
		"keeper":
			_keeper_training(delta)


func _keeper_training(delta: float) -> void:
	hud.set_objective("Saves: %d   Shots: %d / 10" % [tdata["saves"], tdata["shots"]])
	if tdata["live"]:
		tdata["live_t"] = float(tdata["live_t"]) + delta
		var bx: float = ball.global_position.x
		if tdata["live_t"] > 3.0 or (bx > -HALF_X + 6.0 and ball.linear_velocity.x > 0.5 and tdata["live_t"] > 0.6):
			tdata["saves"] += 1
			tdata["live"] = false
			Sfx.play("cheer", -10.0)
			hud.banner("SAVE!", 1.0)
			tdata["shot_t"] = 1.2
		return
	tdata["shot_t"] = float(tdata["shot_t"]) - delta
	if tdata["shot_t"] <= 0.0:
		if tdata["shots"] >= 10:
			_training_finish(float(tdata["saves"]))
			return
		var from := Vector3(randf_range(-6.0, 0.0), 0.45, randf_range(-5.0, 5.0))
		ball.reset_to(from)
		tdata["shots"] += 1
		tdata["live"] = true
		tdata["live_t"] = 0.0
		get_tree().create_timer(0.05).timeout.connect(func():
			var aim := Vector3(-HALF_X - 0.5, 0, randf_range(-1.8, 1.8))
			var d := (aim - from)
			d.y = 0.0
			ball.linear_velocity = d.normalized() * randf_range(10.0, 14.0) + Vector3.UP * 0.6
			Sfx.play("hit_hard", -4.0))


func _training_goal(b, scorer: int) -> void:
	match training:
		"bank":
			if scorer == 0:
				if b.touched_wall:
					tdata["goals"] += 1
					Sfx.play("horn", -6.0)
					fx.goal(b.global_position, team_color(0))
					hud.message("GOAL!", 1.2)
				else:
					Sfx.play("foul", -6.0)
					hud.message("NO WALL TOUCH", 1.2, "Bounce it off a side wall first")
			state = "goal"
			state_timer = 1.3
		"keeper":
			if tdata["live"]:
				tdata["live"] = false
				Sfx.play("foul", -8.0)
				hud.banner("Goal...", 1.0)
				tdata["shot_t"] = 1.2
		_:
			b.reset_to(Vector3(0, 0.45, 0))


func _training_after_goal() -> void:
	if training == "bank":
		if tdata["goals"] >= 3:
			_training_finish(float(tdata["time"]))
			return
		ball.reset_to(Vector3(-1, 0.45, randf_range(-3, 3)))
		chairs[0].reset_to(Vector3(-5, 0, 0), Vector3.RIGHT)
		_freeze_all(true)
		state = "countdown"
		state_timer = 1.0
	else:
		state = "play"


func _training_finish(value: float) -> void:
	tdata["done"] = true
	state = "fulltime"
	_freeze_all(true)
	hud.set_speed_text("")
	hud.set_objective("")
	var info: Dictionary = tdata["info"]
	var th: Array = info["stars"]
	var stars := 0
	for k in 3:
		var ok: bool = value >= th[k] if info["higher"] else value <= th[k]
		if ok:
			stars = k + 1
	var id: String = info["id"]
	var old_stars := int(Game.save["stars"].get(id, 0))
	var coins := maxi(0, stars - old_stars) * 40
	Game.save["stars"][id] = maxi(old_stars, stars)
	var prev = Game.save["best"].get(id, null)
	if prev == null or (info["higher"] and value > float(prev)) or (not info["higher"] and value < float(prev)):
		Game.save["best"][id] = value
	Game.save["coins"] += coins
	Game.save_game()
	Sfx.play("jackpot" if stars > 0 else "foul", -4.0)
	var star_txt := "%d / 3  " % stars
	for k in 3:
		star_txt += "* " if k < stars else "- "
	var unit: String = info["unit"]
	var val_txt := ("%.1f %s" % [value, unit]) if unit != "saves" else ("%d saves" % int(value))
	var rows := [["", "Result", val_txt], ["", "Stars", star_txt]]
	rows.append(["", "Targets", "%s / %s / %s" % [th[0], th[1], th[2]]])
	hud.show_panel(info["name"], rows, [["Try again", _restart], ["Back to menu", _to_menu]], ("+%d coins" % coins) if coins > 0 else "")
