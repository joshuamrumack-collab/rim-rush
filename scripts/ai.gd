extends RefCounted
## Team AI. AI chairs only use the same controls as the player: drive (as a
## world direction), boost, brake and spin. Roles: chaser, support, defender, keeper.

const HALF_X := 14.0
const HALF_Z := 8.0

var m  # the match
var think := {}
var spin := {}
var spin_time := {}
var stuck := {}
var unstick := {}


func _init(match_node) -> void:
	m = match_node


func register(c) -> void:
	think[c] = randf_range(0.0, 0.5)
	spin[c] = 0.0
	spin_time[c] = 0.0
	stuck[c] = 0.0
	unstick[c] = 0.0


func skill_of(c) -> float:
	return m.team_skill(c.team)


func nearest_ball(p: Vector3):
	var best = null
	var bd := 1e9
	for b in m.balls:
		var d: float = p.distance_to(b.global_position)
		if d < bd:
			bd = d
			best = b
	return best


func intent(c, dt: float) -> Dictionary:
	var it: Dictionary = c.blank_intent()
	var skill := skill_of(c)
	think[c] = maxf(0.0, think[c] - dt)
	var cp: Vector3 = c.global_position
	cp.y = 0.0
	var ball = nearest_ball(cp)
	if ball == null:
		return it
	var bp: Vector3 = ball.global_position
	bp.y = 0.0
	var atk: Vector3 = m.attack_dir(c.team)
	var opp_goal := atk * HALF_X
	var own_goal := -opp_goal

	# Finish a spin hit that is under way.
	if spin[c] != 0.0:
		spin_time[c] -= dt
		it["spin"] = spin[c]
		it["boost"] = c.chair_type != "Tank" and c.battery > 20.0
		if spin_time[c] <= 0.0:
			spin[c] = 0.0
			think[c] = randf_range(0.5, 1.1) * lerpf(1.6, 0.7, skill)
		return it

	var role: String = c.role
	var tactic: String = m.team_tactic(c.team)
	var target: Vector3
	if role == "keeper":
		if _keeper_should_chase(c, bp, own_goal):
			target = _chase(c, it, cp, bp, opp_goal, skill)
		else:
			target = _keeper_target(c, bp, own_goal, atk)
			var r0 := bp - cp
			if r0.length() < 2.0 and think[c] <= 0.0:
				var clear_dir := Vector3(0, 0, signf(bp.z) if absf(bp.z) > 0.2 else 1.0) + atk
				_try_spin(c, r0, clear_dir.normalized(), skill)
	elif _is_chaser(c, bp):
		target = _chase(c, it, cp, bp, opp_goal, skill)
	else:
		target = _support(c, cp, bp, atk, own_goal, opp_goal, tactic)

	target.x = clampf(target.x, -HALF_X + 0.8, HALF_X - 0.8)
	target.z = clampf(target.z, -HALF_Z + 0.8, HALF_Z - 0.8)
	var dvec := target - cp
	var want := Vector3.ZERO
	if dvec.length() > 0.35:
		want = dvec.normalized() * clampf(dvec.length() / 1.2, 0.35, 1.0)
	for bpos in m.arena.bumper_positions:
		var off: Vector3 = cp - bpos
		off.y = 0.0
		var dd := off.length()
		if dd < 2.0 and want.length() > 0.1:
			want += off.normalized() * (2.0 - dd) * 1.2
	if want.length() > 1.0:
		want = want.normalized()
	if unstick[c] > 0.0:
		unstick[c] -= dt
		want = (-c.forward()).rotated(Vector3.UP, 0.9)
	elif want.length() > 0.5 and c.linear_velocity.length() < 0.4:
		stuck[c] += dt
		if stuck[c] > 0.8:
			stuck[c] = 0.0
			unstick[c] = 0.6
	else:
		stuck[c] = 0.0
	it["move"] = want
	return it


func _is_chaser(c, bp: Vector3) -> bool:
	var my_d: float = c.global_position.distance_to(bp)
	for o in m.chairs:
		if o == c or o.team != c.team or o.role == "keeper":
			continue
		var d: float = o.global_position.distance_to(bp)
		if o == m.controlled and not m.autoplay:
			if d < my_d + 1.0:
				return false
			continue
		if d < my_d - 0.4:
			return false
		if absf(d - my_d) <= 0.4 and o.get_instance_id() < c.get_instance_id():
			return false
	return true


func _chase(c, it: Dictionary, cp: Vector3, bp: Vector3, opp_goal: Vector3, skill: float) -> Vector3:
	var to_goal := (opp_goal - bp).normalized()
	var behind := bp - to_goal * 1.5
	if (cp - bp).dot(to_goal) > -0.2:
		var side := to_goal.cross(Vector3.UP)
		var s := 1.0 if (cp - bp).dot(side) > 0.0 else -1.0
		behind = bp - to_goal * 1.6 + side * s * 1.7
	var target := behind
	var r := bp - cp
	var dist_ball := r.length()
	if dist_ball < 2.0:
		var facing: float = c.forward().dot(r.normalized())
		if facing > 0.6 and (cp - bp).dot(to_goal) < 0.0:
			target = bp + to_goal * 2.0
			if bp.distance_to(opp_goal) < 9.0 and c.battery > 25.0 and randf() < 0.5 + skill * 0.5:
				it["boost"] = true
		elif think[c] <= 0.0:
			_try_spin(c, r, to_goal, skill)
	if dist_ball > 6.0 and c.battery > 40.0 and randf() < skill:
		it["boost"] = true
	return target


## Spin so the foot guard sweeps the ball toward "want_dir". Better AIs pick right more often.
func _try_spin(c, r: Vector3, want_dir: Vector3, skill: float) -> void:
	var sweep := Vector3(0, -1, 0).cross(r)
	var d := sweep.normalized().dot(want_dir)
	if absf(d) > 0.3:
		var s := 1.0 if d > 0.0 else -1.0
		if randf() > 0.55 + skill * 0.45:
			s = -s  # a mistake
		spin[c] = s
		spin_time[c] = randf_range(0.25, 0.45)


func _support(c, _cp: Vector3, bp: Vector3, atk: Vector3, own_goal: Vector3, _opp_goal: Vector3, tactic: String) -> Vector3:
	var defend: bool = c.role == "defend"
	var ball_in_own_half: bool = (bp - own_goal).length() < HALF_X
	match tactic:
		"Press High":
			if defend:
				return own_goal.lerp(bp, 0.6)
			return bp + atk * 1.5 + Vector3(0, 0, -signf(bp.z + 0.01) * 2.5)
		"Park the Chair":
			var gz := clampf(bp.z * 0.4, -2.5, 2.5)
			return own_goal + atk * (3.0 if defend else 5.0) + Vector3(0, 0, gz + (1.5 if c.number % 2 == 0 else -1.5))
		"Pinball Hunt":
			if m.jackpot_open:
				return m.arena.jackpot_area.global_position * Vector3(1, 0, 1) + Vector3(0, 0, 2.0)
			if not defend and not m.arena.lane_positions.is_empty():
				var lp: Vector3 = m.arena.lane_positions[c.number % m.arena.lane_positions.size()]
				return lp * Vector3(1, 0, 0.85)
	if ball_in_own_half or defend:
		return own_goal.lerp(bp, 0.35) + Vector3(0, 0, 1.2 if c.number % 2 == 0 else -1.2)
	return bp - atk * 3.0 + Vector3(0, 0, -signf(bp.z + 0.01) * 3.0)


func _keeper_should_chase(c, bp: Vector3, own_goal: Vector3) -> bool:
	# Rush out only when the ball is close to goal and no team-mate is nearer.
	if bp.distance_to(own_goal) > 4.5:
		return false
	for o in m.chairs:
		if o != c and o.team == c.team and o.global_position.distance_to(bp) < c.global_position.distance_to(bp) - 0.5:
			return false
	return true


func _keeper_target(_c, bp: Vector3, own_goal: Vector3, atk: Vector3) -> Vector3:
	var gz := clampf(bp.z * 0.35, -1.6, 1.6)
	var depth := 1.4
	if bp.distance_to(own_goal) < 7.0:
		depth = 1.8
	return own_goal + atk * depth + Vector3(0, 0, gz)
