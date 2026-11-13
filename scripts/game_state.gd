extends Node
## Autoload "Game": settings, save data, teams, chair parts, the current match
## setup and the input map. Everything that survives between scenes lives here.

const SAVE_PATH := "user://rimrush_save.json"

# ------------------------------------------------------------------ teams
const PLAYER_TEAM := {"name": "Blue Rollers", "short": "BLU", "color": Color(0.2, 0.5, 1.0), "color2": Color(0.9, 0.95, 1.0),
	"chairs": ["All-rounder", "Tank", "Spinner", "Glider"], "skill": 0.7}

const RIVALS := [
	{"name": "Neon Knights", "short": "NEO", "color": Color(0.65, 0.3, 1.0), "color2": Color(0.2, 1.0, 0.9), "chairs": ["Spinner", "Tank", "Glider", "Sprinter"], "skill": 0.55},
	{"name": "Harbor Sharks", "short": "HAR", "color": Color(0.1, 0.75, 0.7), "color2": Color(1, 1, 1), "chairs": ["Sprinter", "Tank", "All-rounder", "Glider"], "skill": 0.6},
	{"name": "Iron Wheels", "short": "IRN", "color": Color(0.95, 0.5, 0.1), "color2": Color(0.25, 0.25, 0.28), "chairs": ["Tank", "Tank", "All-rounder", "Spinner"], "skill": 0.65},
	{"name": "Thunder Spin", "short": "THU", "color": Color(1.0, 0.85, 0.1), "color2": Color(0.1, 0.1, 0.15), "chairs": ["Spinner", "Spinner", "Tank", "Sprinter"], "skill": 0.75},
	{"name": "Frost Gliders", "short": "FRO", "color": Color(0.7, 0.9, 1.0), "color2": Color(0.2, 0.35, 0.8), "chairs": ["Glider", "Glider", "Tank", "Spinner"], "skill": 0.7},
	{"name": "Red Comets", "short": "RED", "color": Color(1.0, 0.25, 0.2), "color2": Color(1, 0.9, 0.7), "chairs": ["Sprinter", "Spinner", "Tank", "All-rounder"], "skill": 0.85},
	{"name": "Forest Foxes", "short": "FOX", "color": Color(0.3, 0.8, 0.3), "color2": Color(1.0, 0.6, 0.2), "chairs": ["All-rounder", "Glider", "Tank", "Sprinter"], "skill": 0.9},
]

# ----------------------------------------------------------------- arenas
const ARENAS := [
	{"name": "Indoor Court", "desc": "Classic sports hall. Wood floor, big crowd, G-O-A-L lanes.", "style": "indoor",
		"bumpers": false, "lanes": true, "flippers": false, "spinner": false, "ramps": false, "kickbacks": false, "events": false, "grip": 1.0},
	{"name": "Neon Arcade", "desc": "A pinball table you can drive on. Bumpers, flippers, ramps and arena events.", "style": "neon",
		"bumpers": true, "lanes": true, "flippers": true, "spinner": true, "ramps": true, "kickbacks": true, "events": true, "grip": 1.0},
	{"name": "Rooftop City", "desc": "Open air at sunset. Flippers, ramps and wind gusts.", "style": "rooftop",
		"bumpers": false, "lanes": true, "flippers": true, "spinner": true, "ramps": true, "kickbacks": false, "events": true, "grip": 1.0},
	{"name": "Retro Gym", "desc": "Old-school gym. No pinball, Pro rules by default.", "style": "retro",
		"bumpers": false, "lanes": false, "flippers": false, "spinner": false, "ramps": false, "kickbacks": false, "events": false, "grip": 1.0},
	{"name": "Ice Rink", "desc": "Low grip, long drifts. Bumpers and lanes.", "style": "ice",
		"bumpers": true, "lanes": true, "flippers": false, "spinner": true, "ramps": false, "kickbacks": true, "events": true, "grip": 0.55},
]

# ------------------------------------------------------------ chair parts
## Each option multiplies stats. Parts soften a con but never remove it.
const PARTS := {
	"frame": [
		{"name": "Medium", "cost": 0, "mods": {}},
		{"name": "Light", "cost": 150, "mods": {"max_speed": 1.06, "mass": 0.85, "accel": 1.05}},
		{"name": "Heavy", "cost": 150, "mods": {"max_speed": 0.94, "mass": 1.22, "accel": 0.95}},
	],
	"guard": [
		{"name": "Flat", "cost": 0, "mods": {}},
		{"name": "Curved", "cost": 200, "mods": {"shot": 1.12, "guard_w": 0.95}},
		{"name": "Wide", "cost": 200, "mods": {"shot": 0.92, "guard_w": 1.2}},
	],
	"motor": [
		{"name": "Standard", "cost": 0, "mods": {}},
		{"name": "Sprint", "cost": 250, "mods": {"max_speed": 1.07, "accel": 0.92}},
		{"name": "Torque", "cost": 250, "mods": {"accel": 1.15, "max_speed": 0.95, "spin": 1.04}},
	],
	"battery": [
		{"name": "Standard", "cost": 0, "mods": {}},
		{"name": "Large", "cost": 150, "mods": {"drain": 0.8, "recharge": 0.85}},
		{"name": "Fast-charge", "cost": 150, "mods": {"recharge": 1.3, "drain": 1.1}},
	],
	"wheels": [
		{"name": "Standard", "cost": 0, "mods": {}},
		{"name": "Grip", "cost": 120, "mods": {"grip": 1.3, "max_speed": 0.97}},
		{"name": "Slick", "cost": 120, "mods": {"grip": 0.75, "spin": 1.08}},
	],
}
const PART_ORDER := ["frame", "guard", "motor", "battery", "wheels"]
const PAINTS := [Color(0.18, 0.19, 0.22), Color(0.85, 0.85, 0.9), Color(0.9, 0.2, 0.25), Color(1.0, 0.6, 0.1),
	Color(1.0, 0.9, 0.2), Color(0.2, 0.85, 0.4), Color(0.2, 0.8, 1.0), Color(0.7, 0.3, 1.0), Color(1.0, 0.4, 0.75)]

const TACTICS := ["Balanced", "Press High", "Park the Chair", "Pinball Hunt"]

const CHALLENGES := [
	{"id": "power", "name": "Power Spin", "desc": "Spin into the ball as hard as you can. 5 tries. Best speed counts.", "stars": [12.0, 16.0, 19.0], "unit": "m/s", "higher": true},
	{"id": "targets", "name": "Target Practice", "desc": "Knock the ball through the 6 glowing rings in order.", "stars": [120.0, 80.0, 55.0], "unit": "s", "higher": false},
	{"id": "slalom", "name": "Slalom", "desc": "Drive through the 8 gates in order. Practise turning and drifting.", "stars": [50.0, 35.0, 26.0], "unit": "s", "higher": false},
	{"id": "bank", "name": "Bank Shots", "desc": "Score 3 goals, but each one must bounce off a side wall first.", "stars": [120.0, 75.0, 50.0], "unit": "s", "higher": false},
	{"id": "keeper", "name": "Keeper Saves", "desc": "Play keeper. Stop as many of the 10 shots as you can.", "stars": [4.0, 6.0, 8.0], "unit": "saves", "higher": true},
]

# --------------------------------------------------------------- settings
var settings := {
	"one_hand": false,        # left stick points where to go, one button spins toward the ball
	"game_speed": 1.0,        # 0.6 .. 1.0 (single player)
	"assist": 0.3,            # 0 .. 1, nudges hard hits toward the opponent goal
	"shapes": false,          # colour-blind team shapes above chairs
	"reduce_flash": false,    # no blackout event, softer flashes
	"auto_switch": true,      # switch to the team-mate nearest the ball
	"volume": 0.8,
	"chase_cam": false,
	"difficulty": 1,          # 0 easy, 1 normal, 2 hard
	"team_size": 3,
	"shake": true,
}

# -------------------------------------------------------------- save data
var save := {
	"coins": 300,
	"owned": ["frame:Medium", "guard:Flat", "motor:Standard", "battery:Standard", "wheels:Standard"],
	"build": {"type": "All-rounder", "frame": "Medium", "guard": "Flat", "motor": "Standard", "battery": "Standard", "wheels": "Standard", "paint": 0},
	"stars": {},   # challenge id -> stars (0..3)
	"best": {},    # challenge id -> best value
	"season": {},
	"played": 0, "wins": 0,
}

## The match that is about to be played. Set by the menu, read by match.gd.
var match_config := {}
var last_result := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	load_game()
	apply_volume()


# ------------------------------------------------------------------ input

func _add_action(action: String, keys: Array, buttons: Array = [], axis := -1, axis_val := 0.0) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.25)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)
	for b in buttons:
		var j := InputEventJoypadButton.new()
		j.button_index = b
		InputMap.action_add_event(action, j)
	if axis >= 0:
		var m := InputEventJoypadMotion.new()
		m.axis = axis as JoyAxis
		m.axis_value = axis_val
		InputMap.action_add_event(action, m)


func _setup_input() -> void:
	_add_action("move_left", [KEY_A], [], JOY_AXIS_LEFT_X, -1.0)
	_add_action("move_right", [KEY_D], [], JOY_AXIS_LEFT_X, 1.0)
	_add_action("move_up", [KEY_W], [], JOY_AXIS_LEFT_Y, -1.0)
	_add_action("move_down", [KEY_S], [], JOY_AXIS_LEFT_Y, 1.0)
	_add_action("spin_left", [KEY_LEFT, KEY_J], [], JOY_AXIS_RIGHT_X, -1.0)
	_add_action("spin_right", [KEY_RIGHT, KEY_L], [], JOY_AXIS_RIGHT_X, 1.0)
	_add_action("boost", [KEY_SHIFT], [], JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_add_action("brake", [KEY_SPACE], [], JOY_AXIS_TRIGGER_LEFT, 1.0)
	_add_action("one_hand_spin", [KEY_K], [JOY_BUTTON_A])
	_add_action("switch", [KEY_Q], [JOY_BUTTON_LEFT_SHOULDER])
	_add_action("camera", [KEY_C], [JOY_BUTTON_Y])
	_add_action("tactic_next", [KEY_E], [JOY_BUTTON_DPAD_UP])
	_add_action("tactic_prev", [KEY_R], [JOY_BUTTON_DPAD_DOWN])
	_add_action("pause", [KEY_ESCAPE, KEY_P], [JOY_BUTTON_START])
	_add_action("skip", [KEY_ENTER, KEY_SPACE], [JOY_BUTTON_A, JOY_BUTTON_B])
	_add_action("help", [KEY_F1], [])


# ------------------------------------------------------------- save/load

func save_game() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"settings": settings, "save": save}))


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return
	if data.has("settings"):
		for k in data["settings"]:
			settings[k] = data["settings"][k]
	if data.has("save"):
		for k in data["save"]:
			save[k] = data["save"][k]
	settings["difficulty"] = int(settings["difficulty"])
	settings["team_size"] = int(settings["team_size"])
	save["coins"] = int(save["coins"])
	save["build"]["paint"] = int(save["build"]["paint"])


func apply_volume() -> void:
	var v: float = settings["volume"]
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(v, 0.0001)))


# ----------------------------------------------------------------- chairs

func part_option(slot: String, part_name: String) -> Dictionary:
	for o in PARTS[slot]:
		if o["name"] == part_name:
			return o
	return PARTS[slot][0]


func owns(slot: String, part_name: String) -> bool:
	return (slot + ":" + part_name) in save["owned"]


## Stats for a chair type with a build's parts applied.
func build_stats(base: Dictionary, build: Dictionary) -> Dictionary:
	var s := base.duplicate()
	if not s.has("guard_w"):
		s["guard_w"] = 1.0
	for slot in PART_ORDER:
		if not build.has(slot):
			continue
		var mods: Dictionary = part_option(slot, build[slot])["mods"]
		for k in mods:
			s[k] = float(s.get(k, 1.0)) * float(mods[k])
	return s


func team_def(id: int) -> Dictionary:
	return PLAYER_TEAM if id < 0 else RIVALS[id]


# ----------------------------------------------------------------- season

func new_season() -> void:
	var order := range(RIVALS.size())
	order.shuffle()
	var table := {}
	for id in [-1] + range(RIVALS.size()):
		table[str(id)] = {"p": 0, "w": 0, "d": 0, "l": 0, "gf": 0, "ga": 0, "pts": 0}
	save["season"] = {"round": 0, "fixtures": order, "table": table, "results": [], "done": false}
	save_game()


func record_result(table: Dictionary, a: int, b: int, ga: int, gb: int) -> void:
	var ra: Dictionary = table[str(a)]
	var rb: Dictionary = table[str(b)]
	ra["p"] += 1
	rb["p"] += 1
	ra["gf"] += ga
	ra["ga"] += gb
	rb["gf"] += gb
	rb["ga"] += ga
	if ga > gb:
		ra["w"] += 1
		rb["l"] += 1
		ra["pts"] += 3
	elif gb > ga:
		rb["w"] += 1
		ra["l"] += 1
		rb["pts"] += 3
	else:
		ra["d"] += 1
		rb["d"] += 1
		ra["pts"] += 1
		rb["pts"] += 1


## Plays the player's season match result into the table and simulates the rest of the round.
func season_play_round(player_goals: int, opp_goals: int) -> void:
	var s: Dictionary = save["season"]
	var rnd: int = s["round"]
	var opp: int = int(s["fixtures"][rnd])
	record_result(s["table"], -1, opp, player_goals, opp_goals)
	s["results"].append({"opp": opp, "gf": player_goals, "ga": opp_goals})
	# Other rivals play each other.
	var others := []
	for id in range(RIVALS.size()):
		if id != opp:
			others.append(id)
	others.shuffle()
	while others.size() >= 2:
		var a: int = others.pop_back()
		var b: int = others.pop_back()
		var sa: float = RIVALS[a]["skill"]
		var sb: float = RIVALS[b]["skill"]
		var g_a := _sim_goals(sa - sb)
		var g_b := _sim_goals(sb - sa)
		record_result(s["table"], a, b, g_a, g_b)
	s["round"] = rnd + 1
	if s["round"] >= RIVALS.size():
		s["done"] = true
	save_game()


func _sim_goals(edge: float) -> int:
	var g := 0
	for i in 5:
		if randf() < 0.32 + edge * 0.4:
			g += 1
	return g


func season_sorted() -> Array:
	var rows := []
	var t: Dictionary = save["season"]["table"]
	for k in t:
		var r: Dictionary = t[k].duplicate()
		r["id"] = int(k)
		rows.append(r)
	rows.sort_custom(func(x, y):
		if x["pts"] != y["pts"]:
			return x["pts"] > y["pts"]
		return (x["gf"] - x["ga"]) > (y["gf"] - y["ga"]))
	return rows
