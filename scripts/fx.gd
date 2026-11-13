extends Node3D
## Particle effects and camera shake. One instance lives in the match scene.

var shake := 0.0
var _quad_cache := {}


func _particle_mesh(col: Color, size: float, energy := 3.0) -> QuadMesh:
	var key := "%s_%f" % [col.to_html(), size]
	if _quad_cache.has(key):
		return _quad_cache[key]
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	# HDR albedo so particles bloom; a radial texture makes them round.
	m.albedo_color = Color(col.r * energy, col.g * energy, col.b * energy, 1.0)
	m.albedo_texture = _dot_texture()
	q.material = m
	_quad_cache[key] = q
	return q


var _dot: GradientTexture2D


func _dot_texture() -> GradientTexture2D:
	if _dot == null:
		_dot = GradientTexture2D.new()
		_dot.fill = GradientTexture2D.FILL_RADIAL
		_dot.fill_from = Vector2(0.5, 0.5)
		_dot.fill_to = Vector2(1.0, 0.5)
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		_dot.gradient = g
		_dot.width = 64
		_dot.height = 64
	return _dot


func _burst(pos: Vector3, col: Color, amount: int, speed: float, life: float, size: float, gravity := -6.0, spread := 180.0, dir := Vector3.UP) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = amount
	p.lifetime = life
	var pm := ParticleProcessMaterial.new()
	pm.direction = dir
	pm.spread = spread
	pm.initial_velocity_min = speed * 0.4
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, gravity, 0)
	pm.damping_min = 1.0
	pm.damping_max = 3.0
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	var grad := Gradient.new()
	grad.set_color(0, Color(col, 1.0))
	grad.set_color(1, Color(col, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	p.draw_pass_1 = _particle_mesh(Color(1, 1, 1), size)
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(life + 0.5).timeout.connect(p.queue_free)
	return p


## Sparks where the ball got hit; strength 0..1
func hit(pos: Vector3, col: Color, strength: float) -> void:
	var n := int(lerpf(6.0, 40.0, clampf(strength, 0.0, 1.0)))
	_burst(pos, col.lightened(0.3), n, lerpf(2.0, 9.0, strength), 0.45, 0.09)
	if strength > 0.6:
		add_shake(strength * 0.25)


func bump(pos: Vector3) -> void:
	_burst(pos + Vector3.UP * 0.4, Color(1.0, 0.9, 0.6), 14, 4.0, 0.35, 0.07)
	add_shake(0.12)


func goal(pos: Vector3, col: Color) -> void:
	_burst(pos + Vector3.UP * 0.6, col, 160, 14.0, 1.6, 0.16, -4.0)
	_burst(pos + Vector3.UP * 0.6, Color(1, 1, 1), 80, 10.0, 1.2, 0.1, -3.0)
	# Confetti
	for c in [col, Color(1, 1, 1), col.lightened(0.5), Color(1, 0.85, 0.2)]:
		_burst(pos + Vector3.UP * 4.0, c, 50, 7.0, 3.0, 0.14, -1.5, 70.0)
	var light := OmniLight3D.new()
	light.light_color = col
	light.light_energy = 12.0
	light.omni_range = 14.0
	add_child(light)
	light.global_position = pos + Vector3.UP * 2.0
	var tw := create_tween()
	tw.tween_property(light, "light_energy", 0.0, 1.2)
	tw.tween_callback(light.queue_free)
	add_shake(0.7)


func ring(pos: Vector3, col: Color) -> void:
	_burst(pos + Vector3.UP * 0.5, col, 30, 6.0, 0.4, 0.08, 0.0, 10.0, Vector3.RIGHT)
	_burst(pos + Vector3.UP * 0.5, col, 30, 6.0, 0.4, 0.08, 0.0, 10.0, Vector3.LEFT)


func add_shake(a: float) -> void:
	if Game.settings["shake"]:
		shake = minf(1.0, shake + a)


## Continuous emitter attached to a node (boost trail, ball trail).
func make_trail(parent: Node3D, col: Color, offset: Vector3, size: float, amount := 40, life := 0.5) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 25.0
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.8
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.6
	pm.scale_max = 1.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var grad := Gradient.new()
	grad.set_color(0, Color(col, 0.9))
	grad.set_color(1, Color(col, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	p.draw_pass_1 = _particle_mesh(Color(1, 1, 1), size, 1.4)
	p.position = offset
	p.emitting = false
	parent.add_child(p)
	return p
