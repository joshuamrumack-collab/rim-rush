extends RigidBody3D
## The oversized powerchair football ball. All ball handling is physical: when
## a chair's body or foot guard hits it, the ball leaves with the speed of the
## part of the chair that hit it (so a fast spin hits much harder than a push).

const RADIUS := 0.4
const MAX_SPEED := 21.0
const MAX_UP := 3.0
const GUARD_SPRING := 0.5  # extra bounce off a chair, scaled by the chair's "shot" stat

var game
var last_team := -1
var last_chair = null
var touched_wall := false   # since the last chair touch (bank shot challenge)
var _hit_cd := {}
var _lob_time := 0.0
var _pending_reset := false
var _reset_pos := Vector3.ZERO
var _trail: GPUParticles3D
var _mat: ShaderMaterial
var _light: OmniLight3D


func setup(g) -> void:
	game = g


func _ready() -> void:
	mass = 1.0
	linear_damp = 0.35
	angular_damp = 0.6
	continuous_cd = true
	can_sleep = false
	contact_monitor = true
	max_contacts_reported = 6
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.55
	pm.friction = 0.5
	physics_material_override = pm
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = RADIUS
	cs.shape = sh
	add_child(cs)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = RADIUS
	sm.height = RADIUS * 2.0
	sm.radial_segments = 48
	sm.rings = 24
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/ball.gdshader")
	sm.material = _mat
	mi.mesh = sm
	add_child(mi)
	_light = OmniLight3D.new()
	_light.light_color = Color(1, 0.95, 0.85)
	_light.light_energy = 0.6
	_light.omni_range = 2.0
	add_child(_light)
	if game and game.get("fx"):
		_trail = game.fx.make_trail(self, Color(1, 1, 1), Vector3.ZERO, 0.5, 60, 0.35)
	body_entered.connect(_on_body_entered)


func _process(_delta: float) -> void:
	if _trail:
		_trail.emitting = linear_velocity.length() > 9.0
		_trail.global_rotation = Vector3.ZERO
	if last_team >= 0 and game:
		_mat.set_shader_parameter("accent", game.team_color(last_team).darkened(0.35))


func set_glow(g: float) -> void:
	_mat.set_shader_parameter("glow", g)
	_light.light_energy = 0.6 + g * 4.0


func _on_body_entered(b: Node) -> void:
	if b.has_method("is_chair"):
		last_team = b.team
		last_chair = b
		touched_wall = false
	elif b is StaticBody3D:
		touched_wall = true
		if game and linear_velocity.length() > 5.0:
			game.on_ball_wall(self)


func kick(vel: Vector3, team: int, chair) -> void:
	linear_velocity = vel
	last_team = team
	last_chair = chair


## A lob from a ramp: allowed to fly higher for a moment.
func lob(vel: Vector3) -> void:
	linear_velocity = vel
	_lob_time = 1.2


func reset_to(pos: Vector3) -> void:
	_reset_pos = pos
	_pending_reset = true
	last_team = -1
	last_chair = null
	touched_wall = false


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _pending_reset:
		state.transform = Transform3D(Basis(), _reset_pos)
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		_pending_reset = false
		return
	var v := state.linear_velocity
	for k in _hit_cd.keys():
		_hit_cd[k] -= state.step
		if _hit_cd[k] <= 0.0:
			_hit_cd.erase(k)
	for i in state.get_contact_count():
		var other = state.get_contact_collider_object(i)
		if other == null or not other.has_method("is_chair") or _hit_cd.has(other):
			continue
		var n := state.transform.origin - state.get_contact_collider_position(i)
		n.y = 0.0
		if n.length() < 0.001:
			continue
		n = n.normalized()
		var hit_v := state.get_contact_collider_velocity_at_position(i)
		var approach := hit_v.dot(n) - v.dot(n)
		if approach > 0.4:
			var spring := 1.0 + GUARD_SPRING * float(other.stats["shot"])
			v += n * approach * spring
			v.y += minf(1.6, approach * 0.08)
			last_team = other.team
			last_chair = other
			touched_wall = false
			_hit_cd[other] = 0.12
			if game:
				v = game.on_ball_hit(self, other, v, approach)
	_lob_time = maxf(0.0, _lob_time - state.step)
	if v.y > MAX_UP and _lob_time <= 0.0:
		v.y = MAX_UP
	if game:
		v += game.ball_extra_force(self) * state.step
	var flat_speed := Vector2(v.x, v.z).length()
	if flat_speed > MAX_SPEED:
		var k := MAX_SPEED / flat_speed
		v.x *= k
		v.z *= k
	state.linear_velocity = v
