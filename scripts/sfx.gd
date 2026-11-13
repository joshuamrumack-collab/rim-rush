extends Node
## Autoload "Sfx": every sound is synthesized at startup, so the game needs no
## audio files. Call Sfx.play("hit_hard"), Sfx.set_crowd(0..1), Sfx.set_motor(0..1).

const RATE := 22050

var _streams := {}
var _pool: Array = []
var _next := 0
var _crowd: AudioStreamPlayer
var _motor: AudioStreamPlayer
var _crowd_target := 0.3
var _motor_target := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	seed(1234)
	_make_all()
	randomize()
	for i in 16:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	_crowd = AudioStreamPlayer.new()
	_crowd.stream = _streams["crowd"]
	_crowd.volume_db = -40.0
	add_child(_crowd)
	_motor = AudioStreamPlayer.new()
	_motor.stream = _streams["motor"]
	_motor.volume_db = -60.0
	add_child(_motor)


func play(sound: String, volume_db := 0.0, pitch := 1.0) -> void:
	if not _streams.has(sound):
		return
	var p: AudioStreamPlayer = _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = _streams[sound]
	p.volume_db = volume_db
	p.pitch_scale = pitch * randf_range(0.97, 1.03)
	p.play()


func start_ambience() -> void:
	if not _crowd.playing:
		_crowd.play()
	if not _motor.playing:
		_motor.play()


func stop_ambience() -> void:
	_crowd.stop()
	_motor.stop()


## 0 = quiet murmur, 1 = roaring
func set_crowd(level: float) -> void:
	_crowd_target = clampf(level, 0.0, 1.0)


## 0 = still, 1 = full speed (pitch and volume of your chair's motor)
func set_motor(level: float) -> void:
	_motor_target = clampf(level, 0.0, 1.5)


func _process(delta: float) -> void:
	if _crowd.playing:
		var want := lerpf(-24.0, -6.0, _crowd_target)
		_crowd.volume_db = lerpf(_crowd.volume_db, want, minf(1.0, delta * 2.0))
	if _motor.playing:
		var mv := lerpf(-34.0, -14.0, clampf(_motor_target, 0.0, 1.0))
		_motor.volume_db = lerpf(_motor.volume_db, mv if _motor_target > 0.02 else -50.0, minf(1.0, delta * 8.0))
		_motor.pitch_scale = lerpf(_motor.pitch_scale, 0.7 + _motor_target * 0.8, minf(1.0, delta * 8.0))


# ------------------------------------------------------------- synthesis

func _to_stream(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32000.0)
		data.encode_s16(i * 2, v)
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = samples.size()
	return s


func _buf(secs: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(secs * RATE))
	return b


func _env(t: float, attack: float, decay: float) -> float:
	if t < attack:
		return t / attack
	return exp(-(t - attack) / decay)


func _tone(b: PackedFloat32Array, freq: float, amp: float, attack: float, decay: float, start := 0.0, sweep := 0.0) -> void:
	var phase := 0.0
	var i0 := int(start * RATE)
	for i in range(i0, b.size()):
		var t := float(i - i0) / RATE
		var f := freq + sweep * t
		phase += TAU * f / RATE
		b[i] += sin(phase) * amp * _env(t, attack, decay)


func _noise(b: PackedFloat32Array, amp: float, attack: float, decay: float, lowpass := 1.0, start := 0.0) -> void:
	var y := 0.0
	var i0 := int(start * RATE)
	for i in range(i0, b.size()):
		var t := float(i - i0) / RATE
		y += (randf_range(-1.0, 1.0) - y) * lowpass
		b[i] += y * amp * _env(t, attack, decay)


func _make_all() -> void:
	var b: PackedFloat32Array

	b = _buf(0.18)
	_tone(b, 140.0, 0.6, 0.002, 0.05, 0.0, -200.0)
	_noise(b, 0.25, 0.001, 0.02, 0.5)
	_streams["hit_soft"] = _to_stream(b)

	b = _buf(0.4)
	_tone(b, 95.0, 0.8, 0.001, 0.09, 0.0, -120.0)
	_noise(b, 0.5, 0.001, 0.04, 0.7)
	_tone(b, 920.0, 0.12, 0.001, 0.12)
	_tone(b, 1380.0, 0.07, 0.001, 0.08)
	_streams["hit_hard"] = _to_stream(b)

	b = _buf(0.35)
	_tone(b, 62.0, 0.9, 0.002, 0.1, 0.0, -40.0)
	_noise(b, 0.5, 0.001, 0.06, 0.12)
	_streams["bump"] = _to_stream(b)

	b = _buf(0.6)
	_tone(b, 1320.0, 0.35, 0.001, 0.18)
	_tone(b, 1980.0, 0.25, 0.001, 0.14)
	_tone(b, 2640.0, 0.1, 0.001, 0.08)
	_streams["ding"] = _to_stream(b)

	b = _buf(0.18)
	_noise(b, 0.6, 0.001, 0.025, 0.8)
	_tone(b, 320.0, 0.4, 0.001, 0.05)
	_streams["flipper"] = _to_stream(b)

	b = _buf(0.45)
	for k in 3:
		_tone(b, [880.0, 1108.0, 1318.0][k], 0.3, 0.002, 0.07, k * 0.09)
	_streams["lane"] = _to_stream(b)

	b = _buf(0.9)
	var ph := 0.0
	for i in b.size():
		var t := float(i) / RATE
		ph += TAU * (2900.0 + sin(t * TAU * 28.0) * 120.0) / RATE
		var e := minf(1.0, t / 0.02) * (1.0 if t < 0.7 else maxf(0.0, 1.0 - (t - 0.7) / 0.2))
		b[i] = sin(ph) * 0.35 * e
	_noise(b, 0.05, 0.01, 0.6, 0.9)
	_streams["whistle"] = _to_stream(b)

	b = _buf(1.8)
	for f in [110.0, 165.0, 220.0, 277.0]:
		var p2 := 0.0
		for i in b.size():
			var t := float(i) / RATE
			p2 += TAU * f * (1.0 + sin(t * 30.0) * 0.004) / RATE
			var saw := fmod(p2 / TAU, 1.0) * 2.0 - 1.0
			var e := minf(1.0, t / 0.05) * (1.0 if t < 1.4 else maxf(0.0, 1.0 - (t - 1.4) / 0.4))
			b[i] += saw * 0.14 * e
	_streams["horn"] = _to_stream(b)

	# Crowd murmur loop: band-limited noise with slow swells.
	b = _buf(4.0)
	var y1 := 0.0
	var y2 := 0.0
	for i in b.size():
		var t := float(i) / RATE
		y1 += (randf_range(-1.0, 1.0) - y1) * 0.22
		y2 += (y1 - y2) * 0.3
		var sw := 0.75 + 0.25 * sin(t * TAU / 4.0) * sin(t * TAU / 2.0 + 1.0)
		b[i] = (y1 - y2) * 1.6 * sw
	_streams["crowd"] = _to_stream(b, true)

	b = _buf(2.8)
	_noise(b, 0.8, 0.35, 1.0, 0.3)
	_noise(b, 0.3, 0.2, 0.8, 0.8)
	_streams["cheer"] = _to_stream(b)

	b = _buf(0.18)
	_tone(b, 880.0, 0.35, 0.002, 0.08)
	_streams["beep"] = _to_stream(b)
	b = _buf(0.45)
	_tone(b, 1320.0, 0.4, 0.002, 0.18)
	_tone(b, 660.0, 0.2, 0.002, 0.18)
	_streams["go"] = _to_stream(b)

	b = _buf(0.9)
	for k in 6:
		_tone(b, 523.0 * pow(2.0, k / 5.0), 0.25, 0.002, 0.1, k * 0.08)
	_streams["jackpot"] = _to_stream(b)

	b = _buf(1.3)
	var p3 := 0.0
	for i in b.size():
		var t := float(i) / RATE
		p3 += TAU * (600.0 + 500.0 * abs(sin(t * TAU * 1.5))) / RATE
		b[i] = sin(p3) * 0.3 * minf(1.0, (1.3 - t) * 4.0)
	_streams["siren"] = _to_stream(b)

	b = _buf(0.06)
	_tone(b, 1800.0, 0.25, 0.001, 0.015)
	_streams["click"] = _to_stream(b)

	# Electric motor loop
	b = _buf(1.0)
	var p4 := 0.0
	for i in b.size():
		p4 += TAU * 120.0 / RATE
		b[i] = (sin(p4) * 0.3 + sin(p4 * 2.0) * 0.2 + sin(p4 * 3.01) * 0.1 + randf_range(-0.04, 0.04))
	_streams["motor"] = _to_stream(b, true)

	b = _buf(0.5)
	var y3 := 0.0
	for i in b.size():
		var t := float(i) / RATE
		y3 += (randf_range(-1.0, 1.0) - y3) * (0.05 + t * 1.2)
		b[i] = y3 * 0.9 * minf(1.0, t / 0.05) * maxf(0.0, 1.0 - t / 0.5)
	_streams["boost"] = _to_stream(b)

	b = _buf(0.7)
	_tone(b, 220.0, 0.4, 0.01, 0.25, 0.0, 300.0)
	_tone(b, 330.0, 0.25, 0.01, 0.25, 0.0, 450.0)
	_streams["foul"] = _to_stream(b)
