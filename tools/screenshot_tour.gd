extends Node
## Dev tool: renders the menu and every arena and saves screenshots to
## res://screenshots/, then quits. Run this scene, not the game.

var shots := [
	["menu", "res://menu.tscn", {}, 4.0],
	["indoor", "res://match.tscn", {"mode": "arcade", "arena": 0, "team_size": 3, "rules": "arcade", "opponent": 2, "half_len": 120.0}, 9.0],
	["neon", "res://match.tscn", {"mode": "arcade", "arena": 1, "team_size": 3, "rules": "arcade", "opponent": 0, "half_len": 120.0}, 9.0],
	["rooftop", "res://match.tscn", {"mode": "arcade", "arena": 2, "team_size": 3, "rules": "arcade", "opponent": 4, "half_len": 120.0}, 9.0],
	["retro", "res://match.tscn", {"mode": "classic", "arena": 3, "team_size": 4, "rules": "pro", "opponent": 5, "half_len": 120.0}, 9.0],
	["ice", "res://match.tscn", {"mode": "arcade", "arena": 4, "team_size": 3, "rules": "arcade", "opponent": 6, "half_len": 120.0}, 9.0],
	["garage", "res://menu.tscn", {}, 4.5],
	["chase", "res://match.tscn", {"mode": "arcade", "arena": 0, "team_size": 3, "rules": "arcade", "opponent": 1, "half_len": 120.0}, 11.0],
]
var i := -1
var t := 0.0
var current: Node


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://screenshots"))
	_next()


func _next() -> void:
	if current:
		current.queue_free()
		current = null
	i += 1
	if i >= shots.size():
		Game.settings["chase_cam"] = false
		get_tree().quit()
		return
	var s: Array = shots[i]
	Game.match_config = s[2]
	Game.settings["chase_cam"] = s[0] == "chase"
	current = load(s[1]).instantiate()
	if s[1] == "res://match.tscn":
		current.autoplay = true
	add_child(current)
	if s[0] == "garage":
		current._garage()
	t = 0.0


func _process(delta: float) -> void:
	t += delta
	if i < shots.size() and t >= shots[i][3]:
		var img := get_viewport().get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path("res://screenshots/%s.png" % shots[i][0]))
		print("saved ", shots[i][0])
		_next()
