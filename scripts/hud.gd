extends CanvasLayer
## In-match HUD: broadcast score bug, lanes, banners, player card, help,
## pause menu and the half-time / full-time panels.

const UiTheme = preload("res://scripts/ui_theme.gd")

var root: Control
var _bug_names: Array = []
var _bug_scores: Array = []
var _bug_colors: Array = []
var _clock: Label
var _half: Label
var _lanes: Label
var _banner: Label
var _banner_panel: PanelContainer
var _banner_t := 0.0
var _msg: Label
var _msg_t := 0.0
var _sub: Label
var _player_name: Label
var _player_desc: Label
var _boost: ProgressBar
var _tactic: Label
var _help: PanelContainer
var _pause: Control
var _panel: Control
var _replay: Label
var _objective: Label
var _speed: Label
var pause_toggle: Callable


func build(accent: Color) -> void:
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTheme.make(accent)
	add_child(root)

	# Score bug (top-left)
	var bug := PanelContainer.new()
	bug.position = Vector2(24, 20)
	bug.add_theme_stylebox_override("panel", UiTheme.panel_style(Color(0.03, 0.04, 0.07, 0.88), Color(1, 1, 1, 0.1), 10))
	root.add_child(bug)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	bug.add_child(hb)
	for i in 2:
		var sw := ColorRect.new()
		sw.custom_minimum_size = Vector2(8, 38)
		hb.add_child(sw)
		_bug_colors.append(sw)
		var n := UiTheme.label("", 26)
		hb.add_child(n)
		_bug_names.append(n)
		var sc := UiTheme.label("0", 34, Color(1, 1, 1))
		sc.custom_minimum_size = Vector2(30, 0)
		sc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hb.add_child(sc)
		_bug_scores.append(sc)
		if i == 0:
			hb.add_child(UiTheme.label("|", 26, Color(1, 1, 1, 0.3)))
	hb.add_child(UiTheme.label("  ", 10))
	_clock = UiTheme.label("4:00", 30, Color(1.0, 0.88, 0.35))
	hb.add_child(_clock)
	_half = UiTheme.label("1ST", 18, Color(1, 1, 1, 0.6))
	hb.add_child(_half)

	_lanes = UiTheme.label("", 18)
	_lanes.position = Vector2(30, 84)
	root.add_child(_lanes)

	_banner_panel = PanelContainer.new()
	_banner_panel.add_theme_stylebox_override("panel", UiTheme.panel_style(Color(0.08, 0.05, 0.15, 0.9), accent, 12))
	_banner_panel.anchor_left = 0.5
	_banner_panel.anchor_right = 0.5
	_banner_panel.offset_top = 22
	_banner_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner_panel.visible = false
	root.add_child(_banner_panel)
	_banner = UiTheme.label("", 30, Color(1, 1, 1))
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_panel.add_child(_banner)

	_objective = UiTheme.label("", 24, Color(1, 1, 1))
	_objective.anchor_left = 0.5
	_objective.anchor_right = 0.5
	_objective.offset_top = 100
	_objective.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_objective)

	_msg = UiTheme.label("", 84, Color(1, 1, 1))
	_msg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_msg.offset_bottom = -140
	_msg.add_theme_constant_override("outline_size", 14)
	root.add_child(_msg)
	_sub = UiTheme.label("", 28, Color(1, 1, 1, 0.85))
	_sub.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_sub.offset_top = 0
	_sub.offset_bottom = 0
	root.add_child(_sub)

	_replay = UiTheme.label("REPLAY   A / Space to skip", 26, Color(1.0, 0.3, 0.3))
	_replay.position = Vector2(30, 140)
	_replay.visible = false
	root.add_child(_replay)

	_speed = UiTheme.label("", 40, Color(1.0, 0.85, 0.3))
	_speed.anchor_left = 0.5
	_speed.anchor_right = 0.5
	_speed.offset_top = 150
	_speed.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_speed.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_speed)

	# Player card (bottom-left)
	var card := PanelContainer.new()
	card.anchor_top = 1.0
	card.anchor_bottom = 1.0
	card.offset_left = 24
	card.offset_top = -150
	card.offset_right = 470
	card.offset_bottom = -20
	card.add_theme_stylebox_override("panel", UiTheme.panel_style(Color(0.03, 0.04, 0.07, 0.82), Color(1, 1, 1, 0.08), 12))
	root.add_child(card)
	var vb := VBoxContainer.new()
	card.add_child(vb)
	_player_name = UiTheme.label("", 24, Color(1, 1, 1))
	vb.add_child(_player_name)
	_player_desc = UiTheme.label("", 15, Color(1, 1, 1, 0.7))
	_player_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	_player_desc.custom_minimum_size = Vector2(420, 0)
	vb.add_child(_player_desc)
	var row := HBoxContainer.new()
	vb.add_child(row)
	row.add_child(UiTheme.label("BOOST", 16, Color(0.5, 0.9, 1.0)))
	_boost = ProgressBar.new()
	_boost.custom_minimum_size = Vector2(250, 16)
	_boost.show_percentage = false
	_boost.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_boost)
	_tactic = UiTheme.label("", 15, Color(1, 1, 1, 0.75))
	row.add_child(_tactic)

	# Controls help (top-right)
	_help = PanelContainer.new()
	_help.anchor_left = 1.0
	_help.anchor_right = 1.0
	_help.offset_left = -400
	_help.offset_right = -20
	_help.offset_top = 20
	_help.add_theme_stylebox_override("panel", UiTheme.panel_style(Color(0.03, 0.04, 0.07, 0.72), Color(1, 1, 1, 0.06), 12))
	root.add_child(_help)
	var hl := UiTheme.label("", 15, Color(1, 1, 1, 0.85))
	hl.name = "Text"
	_help.add_child(hl)
	set_help_text(false)


func set_help_text(one_hand: bool) -> void:
	var l: Label = _help.get_node("Text")
	if one_hand:
		l.text = "ONE-HAND MODE                  F1 hide\n" \
			+ "Point where to go ...... L-stick / WASD\n" \
			+ "Spin hit toward goal .. A / K\n" \
			+ "Players switch automatically"
	else:
		l.text = "CONTROLS                          F1 hide\n" \
			+ "No kick button: bump or spin into the ball\n" \
			+ "Forward / back ...... L-stick up/down, W/S\n" \
			+ "Turn ................ L-stick left/right, A/D\n" \
			+ "Spin ................ R-stick, arrows or J/L\n" \
			+ "Boost (faster spins)  RT / Shift\n" \
			+ "Brake / drift ....... LT / Space\n" \
			+ "Switch player ....... LB / Q\n" \
			+ "Tactics ............. D-pad up/down, E/R\n" \
			+ "Camera .............. Y / C\n" \
			+ "Pause ............... Start / Esc"


func toggle_help() -> void:
	_help.visible = not _help.visible


func set_score(names: Array, cols: Array, scores: Array, clock: String, half: String) -> void:
	for i in 2:
		_bug_names[i].text = names[i]
		_bug_scores[i].text = str(scores[i])
		_bug_colors[i].color = cols[i]
	_clock.text = clock
	_half.text = half


func set_lanes(text: String) -> void:
	_lanes.text = text


func set_player(name_text: String, desc: String, boost: float, tactic: String) -> void:
	_player_name.text = name_text
	_player_desc.text = desc
	_boost.value = boost
	_tactic.text = "   " + tactic


func set_objective(text: String) -> void:
	_objective.text = text


func set_speed_text(text: String) -> void:
	_speed.text = text


func banner(text: String, secs := 2.5) -> void:
	_banner.text = text
	_banner_panel.visible = true
	_banner_t = secs
	_banner_panel.offset_left = 0
	_banner_panel.offset_right = 0


func message(text: String, secs := 1.5, sub := "") -> void:
	_msg.text = text
	_sub.text = sub
	_sub.offset_top = 120 if sub != "" else 0
	_msg_t = secs
	_msg.scale = Vector2.ONE
	_msg.pivot_offset = _msg.size / 2.0


func clear_message() -> void:
	_msg.text = ""
	_sub.text = ""


func set_replay(on: bool) -> void:
	_replay.visible = on


func _process(delta: float) -> void:
	if Input.is_action_just_pressed("pause") and pause_toggle.is_valid():
		pause_toggle.call()
	if _banner_t > 0.0:
		_banner_t -= delta
		if _banner_t <= 0.0:
			_banner_panel.visible = false
	if _msg_t > 0.0:
		_msg_t -= delta
		if _msg_t <= 0.0:
			clear_message()


# ------------------------------------------------------------ pause menu

func show_pause(on: bool, buttons: Array = []) -> void:
	if _pause:
		_pause.queue_free()
		_pause = null
	if not on:
		return
	_pause = _overlay("PAUSED", [], buttons)


## A centred panel: title, rows of [left, right] text, and buttons [[text, callable], ...].
func show_panel(title: String, rows: Array, buttons: Array, subtitle := "") -> void:
	hide_panel()
	_panel = _overlay(title, rows, buttons, subtitle)


func hide_panel() -> void:
	if _panel:
		_panel.queue_free()
		_panel = null


func _overlay(title: String, rows: Array, buttons: Array, subtitle := "") -> Control:
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.add_child(center)
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(620, 0)
	center.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	pc.add_child(vb)
	var t := UiTheme.label(title, 44, Color(1, 1, 1))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	if subtitle != "":
		var s := UiTheme.label(subtitle, 22, Color(1, 1, 1, 0.75))
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		s.autowrap_mode = TextServer.AUTOWRAP_WORD
		vb.add_child(s)
	if not rows.is_empty():
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 30)
		vb.add_child(grid)
		for r in rows:
			for k in 3:
				var l := UiTheme.label(str(r[k]) if k < r.size() else "", 22, Color(1, 1, 1) if k != 1 else Color(1, 1, 1, 0.6))
				l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				grid.add_child(l)
	var first: Button = null
	for b in buttons:
		var btn := Button.new()
		btn.text = b[0]
		btn.custom_minimum_size = Vector2(0, 52)
		btn.pressed.connect(b[1])
		btn.pressed.connect(func(): Sfx.play("click", -6.0))
		btn.focus_entered.connect(func(): Sfx.play("click", -16.0))
		vb.add_child(btn)
		if first == null:
			first = btn
	if first:
		first.call_deferred("grab_focus")
	return shade
