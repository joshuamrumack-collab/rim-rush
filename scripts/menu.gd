extends Node3D
## Main menu with a live 3D arena behind it: match setup, season, training,
## garage (chair parts and paint) and settings.

const Arena = preload("res://scripts/arena.gd")
const Chair = preload("res://scripts/chair.gd")
const Fx = preload("res://scripts/fx.gd")
const UiTheme = preload("res://scripts/ui_theme.gd")

var fx: Fx
var arena: Arena
var camera: Camera3D
var ui: Control
var screen: VBoxContainer
var side: VBoxContainer
var coins_label: Label
var showcase: Array = []
var preview: Chair
var cam_mode := "orbit"
var _t := 0.0
var setup := {"mode": "arcade", "arena": 1, "opponent": 0, "team_size": 3, "rules": "arcade", "half_len": 120.0}
var team_defs := [Game.PLAYER_TEAM, Game.RIVALS[0]]


func team_color(i: int) -> Color:
	return team_defs[i]["color"]


func is_ball(_b) -> bool:
	return false


func is_player_chair(_c) -> bool:
	return false


func on_chair_contact(_a, _b) -> void:
	pass


func on_pinball(_k, _p, _b) -> void:
	pass


func _ready() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	fx = Fx.new()
	add_child(fx)
	arena = Arena.new()
	add_child(arena)
	arena.build(Game.ARENAS[0], self, [team_color(0), team_color(1)])
	camera = Camera3D.new()
	camera.fov = 48.0
	camera.far = 400.0
	add_child(camera)
	_spawn_showcase()
	setup["team_size"] = int(Game.settings["team_size"])
	setup["opponent"] = randi() % Game.RIVALS.size()
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.theme = UiTheme.make(Game.PLAYER_TEAM["color"])
	var layer := CanvasLayer.new()
	add_child(layer)
	layer.add_child(ui)
	_build_frame()
	_main()
	Sfx.start_ambience()
	Sfx.set_crowd(0.2)
	Sfx.set_motor(0.0)


func _spawn_showcase() -> void:
	var spots := [[Vector3(-3.0, 0, 1.5), 0, "Spinner"], [Vector3(3.0, 0, 1.5), 1, "Tank"], [Vector3(-6.5, 0, -2.5), 0, "Glider"], [Vector3(6.5, 0, -2.5), 1, "Sprinter"]]
	for s in spots:
		var c := Chair.new()
		c.position = s[0] + Vector3(0, 0.5, 0)
		add_child(c)
		c.setup(self, s[1], team_defs[s[1]], s[2], "attack", [9, 4, 7, 11][showcase.size()])
		c.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		c.freeze = true
		c.rotation.y = randf() * TAU
		showcase.append(c)
	preview = Chair.new()
	preview.position = Vector3(0, 0.5, 4.5)
	add_child(preview)
	_rebuild_preview()
	preview.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	preview.freeze = true


func _rebuild_preview() -> void:
	var b: Dictionary = Game.save["build"]
	if preview.stats.is_empty():
		preview.setup(self, 0, Game.PLAYER_TEAM, b["type"], "attack", 9, b)
	else:
		preview.build = b
		preview.paint = Game.PAINTS[int(b["paint"])]
		preview.set_type(b["type"])
	preview.set_controlled(true)


func _process(delta: float) -> void:
	_t += delta
	if cam_mode == "garage":
		preview.rotation.y += delta * 0.6
		camera.position = camera.position.lerp(Vector3(1.6, 1.6, 8.3), minf(1.0, delta * 3.0))
		camera.look_at(preview.global_position + Vector3(-0.9, 0.2, 0), Vector3.UP)
	else:
		var a := _t * 0.07
		camera.position = camera.position.lerp(Vector3(sin(a) * 15.0, 5.5 + sin(_t * 0.2) * 1.0, cos(a) * 15.0), minf(1.0, delta * 1.5))
		camera.look_at(Vector3(0, 0.6, 0), Vector3.UP)
		preview.rotation.y += delta * 0.4
	for c in showcase:
		c.rotation.y += sin(_t * 1.3 + c.number) * delta * 0.5
	arena.set_excitement(0.15 + 0.1 * sin(_t * 0.5))
	if coins_label:
		coins_label.text = "%d coins" % int(Game.save["coins"])


# ---------------------------------------------------------------- frame

func _build_frame() -> void:
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0, 0, 0, 0.0)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(shade)
	var grad := TextureRect.new()
	var gt := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.0, 0.0, 0.02, 0.92))
	g.set_color(1, Color(0.0, 0.0, 0.02, 0.0))
	gt.gradient = g
	gt.fill_to = Vector2(1, 0)
	grad.texture = gt
	grad.anchor_bottom = 1.0
	grad.offset_right = 900
	grad.stretch_mode = TextureRect.STRETCH_SCALE
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(grad)
	var title := UiTheme.label("RIM RUSH", 92, Color(1, 1, 1))
	title.position = Vector2(70, 40)
	title.add_theme_constant_override("outline_size", 12)
	ui.add_child(title)
	var tag := UiTheme.label("POWERCHAIR FOOTBALL", 24, Color(0.45, 0.75, 1.0))
	tag.position = Vector2(76, 150)
	ui.add_child(tag)
	coins_label = UiTheme.label("", 26, Color(1.0, 0.85, 0.3))
	coins_label.anchor_left = 1.0
	coins_label.anchor_right = 1.0
	coins_label.offset_left = -260
	coins_label.offset_top = 30
	ui.add_child(coins_label)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(70, 210)
	scroll.size = Vector2(560, 660)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ui.add_child(scroll)
	screen = VBoxContainer.new()
	screen.custom_minimum_size = Vector2(540, 0)
	screen.add_theme_constant_override("separation", 10)
	scroll.add_child(screen)
	side = VBoxContainer.new()
	side.anchor_left = 1.0
	side.anchor_right = 1.0
	side.offset_left = -720
	side.offset_right = -40
	side.offset_top = 90
	side.add_theme_constant_override("separation", 8)
	ui.add_child(side)


func _clear() -> void:
	for c in screen.get_children():
		c.queue_free()
	for c in side.get_children():
		c.queue_free()


func _btn(text: String, cb: Callable, parent: Control = null) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(520, 54)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(func(): Sfx.play("click", -6.0))
	b.pressed.connect(cb)
	b.focus_entered.connect(func(): Sfx.play("click", -18.0))
	(parent if parent else screen).add_child(b)
	return b


## A button that cycles a value: press / right = next, left = previous.
func _cycler(label_fn: Callable, change_fn: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(520, 54)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text = label_fn.call()
	b.pressed.connect(func():
		change_fn.call(1)
		b.text = label_fn.call()
		Sfx.play("click", -6.0))
	b.gui_input.connect(func(ev: InputEvent):
		if ev.is_action_pressed("ui_left"):
			change_fn.call(-1)
			b.text = label_fn.call()
			Sfx.play("click", -6.0)
			b.accept_event()
		elif ev.is_action_pressed("ui_right"):
			change_fn.call(1)
			b.text = label_fn.call()
			Sfx.play("click", -6.0)
			b.accept_event())
	screen.add_child(b)
	return b


func _heading(text: String) -> void:
	screen.add_child(UiTheme.label(text, 34, Color(1, 1, 1)))


func _focus_first() -> void:
	await get_tree().process_frame
	for c in screen.get_children():
		if c is Button and not c.disabled:
			c.grab_focus()
			return


# ----------------------------------------------------------------- main

func _main() -> void:
	_clear()
	cam_mode = "orbit"
	_btn("Quick Match", func():
		setup = {"mode": "quick", "arena": randi() % Game.ARENAS.size(), "opponent": randi() % Game.RIVALS.size(), "team_size": int(Game.settings["team_size"]), "rules": "arcade", "half_len": 120.0}
		_start(setup))
	_btn("Arcade Match", func(): _match_setup("arcade"))
	_btn("Classic Match  (Pro rules, no pinball)", func(): _match_setup("classic"))
	_btn("Multiball Mayhem", func(): _match_setup("multiball"))
	_btn("Season", _season)
	_btn("Training", _training)
	_btn("Garage", _garage)
	_btn("Settings", _settings)
	_btn("Quit", func(): get_tree().quit())
	var info := UiTheme.label("Played %d   Won %d" % [int(Game.save["played"]), int(Game.save["wins"])], 18, Color(1, 1, 1, 0.6))
	screen.add_child(info)
	_focus_first()


func _start(cfg: Dictionary) -> void:
	Game.match_config = cfg.duplicate(true)
	Game.save_game()
	get_tree().change_scene_to_file("res://match.tscn")


# ---------------------------------------------------------- match setup

func _match_setup(mode: String) -> void:
	_clear()
	setup["mode"] = mode
	if mode == "classic":
		setup["rules"] = "pro"
		setup["arena"] = 3
	elif mode == "multiball":
		setup["arena"] = 1
	_heading({"arcade": "Arcade Match", "classic": "Classic Match", "multiball": "Multiball Mayhem"}[mode])
	if mode != "classic":
		_cycler(_setup_label.bind("arena"), _setup_change.bind("arena"))
	_cycler(_setup_label.bind("opponent"), _setup_change.bind("opponent"))
	_cycler(_setup_label.bind("team_size"), _setup_change.bind("team_size"))
	if mode != "classic":
		_cycler(_setup_label.bind("rules"), _setup_change.bind("rules"))
	_cycler(_setup_label.bind("half_len"), _setup_change.bind("half_len"))
	_cycler(_setup_label.bind("difficulty"), _setup_change.bind("difficulty"))
	var start := _btn("START MATCH", func(): _start(setup))
	start.add_theme_color_override("font_color", Color(0.5, 1.0, 0.6))
	_btn("Back", _main)
	_show_arena_info()
	_focus_first()


func _setup_label(key: String) -> String:
	match key:
		"arena": return "Arena:  " + Game.ARENAS[setup["arena"]]["name"]
		"opponent": return "Opponent:  " + Game.RIVALS[setup["opponent"]]["name"]
		"team_size": return "Teams:  %dv%d%s" % [setup["team_size"], setup["team_size"], "  (with keepers)" if setup["team_size"] >= 3 else ""]
		"rules": return "Rules:  " + ("Pro (2-on-1 and goal-area fouls)" if setup["rules"] == "pro" else "Arcade (only fouls from behind)")
		"half_len": return "Half length:  %d min" % int(setup["half_len"] / 60.0)
		"difficulty": return "Difficulty:  " + ["Easy", "Normal", "Hard"][int(Game.settings["difficulty"])]
	return key


func _setup_change(d: int, key: String) -> void:
	match key:
		"arena": setup["arena"] = posmod(int(setup["arena"]) + d, Game.ARENAS.size())
		"opponent": setup["opponent"] = posmod(int(setup["opponent"]) + d, Game.RIVALS.size())
		"team_size": setup["team_size"] = posmod(int(setup["team_size"]) - 2 + d, 3) + 2
		"rules": setup["rules"] = "pro" if setup["rules"] == "arcade" else "arcade"
		"half_len": setup["half_len"] = clampf(float(setup["half_len"]) + d * 60.0, 60.0, 300.0)
		"difficulty": Game.settings["difficulty"] = posmod(int(Game.settings["difficulty"]) + d, 3)
	_show_arena_info()


func _show_arena_info() -> void:
	for c in side.get_children():
		c.queue_free()
	var a: Dictionary = Game.ARENAS[setup["arena"]]
	var r: Dictionary = Game.RIVALS[setup["opponent"]]
	var pc := PanelContainer.new()
	side.add_child(pc)
	var vb := VBoxContainer.new()
	pc.add_child(vb)
	vb.add_child(UiTheme.label(a["name"], 30, Color(1, 1, 1)))
	var d := UiTheme.label(a["desc"], 18, Color(1, 1, 1, 0.75))
	d.autowrap_mode = TextServer.AUTOWRAP_WORD
	d.custom_minimum_size = Vector2(620, 0)
	vb.add_child(d)
	var feats := []
	for k in ["bumpers", "flippers", "lanes", "spinner", "ramps", "kickbacks", "events"]:
		if a[k]:
			feats.append(k.capitalize())
	vb.add_child(UiTheme.label("Pinball: " + (", ".join(feats) if not feats.is_empty() else "none"), 16, Color(1.0, 0.8, 0.4)))
	vb.add_child(UiTheme.label(" ", 8))
	vb.add_child(UiTheme.label("vs  " + r["name"], 28, r["color"]))
	vb.add_child(UiTheme.label("Chairs: " + ", ".join(r["chairs"]), 16, Color(1, 1, 1, 0.75)))
	vb.add_child(UiTheme.label("Skill: " + "*".repeat(int(round(r["skill"] * 5.0))), 16, Color(1, 1, 1, 0.75)))
	team_defs[1] = r


# ---------------------------------------------------------------- season

func _season() -> void:
	_clear()
	if Game.save["season"].is_empty():
		Game.new_season()
	var s: Dictionary = Game.save["season"]
	_heading("Season")
	if s["done"]:
		var rows := Game.season_sorted()
		var pos := 1
		for r in rows:
			if r["id"] == -1:
				break
			pos += 1
		screen.add_child(UiTheme.label("Season over! You finished #%d" % pos, 24, Color(1.0, 0.85, 0.3)))
		if pos == 1 and not s.get("paid", false):
			s["paid"] = true
			Game.save["coins"] += 500
			Game.save_game()
			screen.add_child(UiTheme.label("CHAMPIONS!  +500 coins", 24, Color(0.5, 1.0, 0.6)))
		_btn("Start a new season", func(): Game.new_season(); _season())
	else:
		var opp: int = int(s["fixtures"][s["round"]])
		var arena_i: int = [0, 2, 4, 1, 3, 0, 2][int(s["round"]) % 7]
		screen.add_child(UiTheme.label("Round %d of %d" % [int(s["round"]) + 1, Game.RIVALS.size()], 22, Color(1, 1, 1, 0.75)))
		screen.add_child(UiTheme.label("Next: vs " + Game.RIVALS[opp]["name"], 26, Game.RIVALS[opp]["color"]))
		screen.add_child(UiTheme.label("at " + Game.ARENAS[arena_i]["name"], 20, Color(1, 1, 1, 0.75)))
		_btn("Play next match", func():
			_start({"mode": "season", "arena": arena_i, "opponent": opp, "team_size": int(Game.settings["team_size"]), "rules": "pro" if arena_i == 3 else "arcade", "half_len": 90.0}))
		_btn("Restart season", func(): Game.new_season(); _season())
	_btn("Back", _main)
	_season_table()
	_focus_first()


func _season_table() -> void:
	var pc := PanelContainer.new()
	side.add_child(pc)
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 22)
	pc.add_child(grid)
	for h in ["#", "Team", "P", "W", "D", "L", "GD", "Pts"]:
		grid.add_child(UiTheme.label(h, 18, Color(1, 1, 1, 0.6)))
	var rows := Game.season_sorted()
	for i in rows.size():
		var r: Dictionary = rows[i]
		var td := Game.team_def(r["id"])
		var col: Color = Color(1.0, 0.9, 0.4) if r["id"] == -1 else Color(1, 1, 1)
		grid.add_child(UiTheme.label(str(i + 1), 20, col))
		grid.add_child(UiTheme.label(td["name"] + (" (you)" if r["id"] == -1 else ""), 20, col))
		for k in ["p", "w", "d", "l"]:
			grid.add_child(UiTheme.label(str(int(r[k])), 20, col))
		grid.add_child(UiTheme.label("%+d" % int(r["gf"] - r["ga"]), 20, col))
		grid.add_child(UiTheme.label(str(int(r["pts"])), 20, col))


# -------------------------------------------------------------- training

func _training() -> void:
	_clear()
	_heading("Training")
	for ch in Game.CHALLENGES:
		var stars := int(Game.save["stars"].get(ch["id"], 0))
		var star_txt := "*".repeat(stars) + "-".repeat(3 - stars)
		var id: String = ch["id"]
		var b := _btn("%s   [%s]" % [ch["name"], star_txt], func():
			_start({"mode": "training", "challenge": id, "arena": 0, "opponent": 0, "team_size": 1, "rules": "arcade", "half_len": 999.0}))
		b.focus_entered.connect(_show_challenge.bind(ch))
	_btn("Back", _main)
	_show_challenge(Game.CHALLENGES[0])
	_focus_first()


func _show_challenge(ch: Dictionary) -> void:
	for c in side.get_children():
		c.queue_free()
	var pc := PanelContainer.new()
	side.add_child(pc)
	var vb := VBoxContainer.new()
	pc.add_child(vb)
	vb.add_child(UiTheme.label(ch["name"], 30, Color(1, 1, 1)))
	var d := UiTheme.label(ch["desc"], 18, Color(1, 1, 1, 0.8))
	d.autowrap_mode = TextServer.AUTOWRAP_WORD
	d.custom_minimum_size = Vector2(620, 0)
	vb.add_child(d)
	var th: Array = ch["stars"]
	vb.add_child(UiTheme.label("Stars at:  %s / %s / %s %s" % [th[0], th[1], th[2], ch["unit"]], 18, Color(1.0, 0.85, 0.4)))
	var best = Game.save["best"].get(ch["id"], null)
	vb.add_child(UiTheme.label("Best: " + ("%.1f %s" % [float(best), ch["unit"]] if best != null else "not played yet"), 18, Color(1, 1, 1, 0.75)))
	vb.add_child(UiTheme.label("Each new star: +40 coins", 16, Color(1, 1, 1, 0.6)))


# ---------------------------------------------------------------- garage

func _garage() -> void:
	_clear()
	cam_mode = "garage"
	_heading("Garage")
	_cycler(_garage_label.bind("type"), _garage_change.bind("type"))
	for slot in Game.PART_ORDER:
		_cycler(_garage_label.bind(slot), _garage_change.bind(slot))
	_cycler(_garage_label.bind("paint"), _garage_change.bind("paint"))
	_btn("Buy selected parts", _buy_parts)
	_btn("Back", _garage_back)
	_garage_info()
	_focus_first()


func _garage_back() -> void:
	_fix_unowned()
	_rebuild_preview()
	Game.save_game()
	_main()


func _garage_label(slot: String) -> String:
	var b: Dictionary = Game.save["build"]
	if slot == "type":
		return "Chair:  " + b["type"]
	if slot == "paint":
		return "Paint:  colour %d of %d" % [int(b["paint"]) + 1, Game.PAINTS.size()]
	var o := Game.part_option(slot, b[slot])
	var owned := Game.owns(slot, b[slot])
	return "%s:  %s%s" % [slot.capitalize(), o["name"], "" if owned else "   (buy: %d coins)" % o["cost"]]


func _garage_change(d: int, slot: String) -> void:
	var b: Dictionary = Game.save["build"]
	if slot == "type":
		var i := Chair.TYPE_ORDER.find(b["type"])
		b["type"] = Chair.TYPE_ORDER[posmod(i + d, Chair.TYPE_ORDER.size())]
	elif slot == "paint":
		b["paint"] = posmod(int(b["paint"]) + d, Game.PAINTS.size())
	else:
		var opts: Array = Game.PARTS[slot]
		var idx := 0
		for k in opts.size():
			if opts[k]["name"] == b[slot]:
				idx = k
		b[slot] = opts[posmod(idx + d, opts.size())]["name"]
	_garage_changed()


func _garage_changed() -> void:
	_rebuild_preview()
	_garage_info()


func _buy_parts() -> void:
	var b: Dictionary = Game.save["build"]
	var cost := 0
	for slot in Game.PART_ORDER:
		if not Game.owns(slot, b[slot]):
			cost += int(Game.part_option(slot, b[slot])["cost"])
	if cost == 0:
		return
	if int(Game.save["coins"]) < cost:
		Sfx.play("foul", -8.0)
		return
	Game.save["coins"] -= cost
	for slot in Game.PART_ORDER:
		if not Game.owns(slot, b[slot]):
			Game.save["owned"].append(slot + ":" + b[slot])
	Sfx.play("jackpot", -6.0)
	Game.save_game()
	_garage()


## Parts you looked at but didn't buy go back to the free option.
func _fix_unowned() -> void:
	var b: Dictionary = Game.save["build"]
	for slot in Game.PART_ORDER:
		if not Game.owns(slot, b[slot]):
			b[slot] = Game.PARTS[slot][0]["name"]


func _garage_info() -> void:
	for c in side.get_children():
		c.queue_free()
	var b: Dictionary = Game.save["build"]
	var st := Game.build_stats(Chair.TYPES[b["type"]], b)
	var base: Dictionary = Chair.TYPES[b["type"]]
	var pc := PanelContainer.new()
	pc.size_flags_horizontal = Control.SIZE_SHRINK_END
	side.add_child(pc)
	var vb := VBoxContainer.new()
	pc.add_child(vb)
	vb.add_child(UiTheme.label(b["type"], 30, Color(1, 1, 1)))
	var d := UiTheme.label(base["desc"], 17, Color(1, 1, 1, 0.75))
	d.autowrap_mode = TextServer.AUTOWRAP_WORD
	d.custom_minimum_size = Vector2(380, 0)
	vb.add_child(d)
	var rows := [["Top speed", "max_speed", 8.5], ["Acceleration", "accel", 11.0], ["Spin", "spin", 20.0], ["Hit power", "shot", 1.5], ["Weight", "mass", 200.0], ["Grip", "grip", 10.0], ["Boost recharge", "recharge", 25.0]]
	for r in rows:
		var hb := HBoxContainer.new()
		var l := UiTheme.label(r[0], 16, Color(1, 1, 1, 0.8))
		l.custom_minimum_size = Vector2(150, 0)
		hb.add_child(l)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(220, 14)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.show_percentage = false
		bar.max_value = 1.0
		bar.step = 0.001
		bar.value = float(st[r[1]]) / float(r[2])
		hb.add_child(bar)
		vb.add_child(hb)
	var cost := 0
	for slot in Game.PART_ORDER:
		if not Game.owns(slot, b[slot]):
			cost += int(Game.part_option(slot, b[slot])["cost"])
	if cost > 0:
		vb.add_child(UiTheme.label("Cost of new parts: %d coins" % cost, 18, Color(1.0, 0.8, 0.3)))
	vb.add_child(UiTheme.label("Parts soften a weakness, never remove it.", 14, Color(1, 1, 1, 0.55)))


# -------------------------------------------------------------- settings

func _settings() -> void:
	_clear()
	_heading("Settings")
	for key in ["one_hand", "auto_switch", "shapes", "reduce_flash", "shake", "chase_cam", "game_speed", "assist", "volume", "difficulty", "team_size"]:
		_cycler(_setting_label.bind(key), _setting_change.bind(key))
	_btn("Back", func():
		Game.save_game()
		_main())
	var pc := PanelContainer.new()
	side.add_child(pc)
	var l := UiTheme.label("One-hand mode: the left stick points where to go,\nA (or K) spins you toward the ball.\n\nGame speed slows the whole match down.\nAim assist nudges your hard hits toward goal.\n\nLeft / right changes a setting.", 18, Color(1, 1, 1, 0.8))
	pc.add_child(l)
	_focus_first()


const SETTING_NAMES := {"one_hand": "One-hand mode", "auto_switch": "Auto-switch player", "shapes": "Colour-blind team shapes",
	"reduce_flash": "Reduce flashing (no blackout)", "shake": "Camera shake", "chase_cam": "Chase camera by default"}


func _setting_label(key: String) -> String:
	var s: Dictionary = Game.settings
	match key:
		"game_speed": return "Game speed:  %d%%" % int(round(float(s["game_speed"]) * 100.0))
		"assist": return "Aim assist:  %d%%" % int(round(float(s["assist"]) * 100.0))
		"volume": return "Volume:  %d%%" % int(round(float(s["volume"]) * 100.0))
		"difficulty": return "Difficulty:  " + ["Easy", "Normal", "Hard"][int(s["difficulty"])]
		"team_size": return "Default team size:  %dv%d" % [int(s["team_size"]), int(s["team_size"])]
	return "%s:  %s" % [SETTING_NAMES[key], "ON" if s[key] else "OFF"]


func _setting_change(d: int, key: String) -> void:
	var s: Dictionary = Game.settings
	match key:
		"game_speed": s["game_speed"] = clampf(float(s["game_speed"]) + d * 0.1, 0.6, 1.0)
		"assist": s["assist"] = clampf(float(s["assist"]) + d * 0.1, 0.0, 1.0)
		"volume":
			s["volume"] = clampf(float(s["volume"]) + d * 0.1, 0.0, 1.0)
			Game.apply_volume()
		"difficulty": s["difficulty"] = posmod(int(s["difficulty"]) + d, 3)
		"team_size": s["team_size"] = posmod(int(s["team_size"]) - 2 + d, 3) + 2
		_: s[key] = not s[key]
