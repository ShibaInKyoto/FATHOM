class_name ChoirBoss
extends Entity
## The Choir: a colossal singer at the bottom of the trench.
##
## It sings in expanding waves. A wave that reaches the submarine hurts and
## drains the battery, unless the pilot answers it with a sonar ping as it
## arrives (an answered ping costs nothing). The song comes in three parts:
## [br]- The Call: each answer leaves the four voice organs open for a moment;
## every organ lost makes the song faster and denser.
## [br]- The Reach: with its organs gone the heart surges forward. Waves now
## come from voices all round the arena as well as the heart, tentacles rise
## into the water and slam down across it, and each answer opens the heart's
## throat to the harpoon.
## [br]- The Duet: wounded enough, the heart falls silent and listens. Its
## hunters hang still. It sings on, faster and faster, and only a long run of
## answers in a row ends the song.
## Its body is built by [ChoirModel]: a heart of see-through flesh behind the
## water the sub swims in, its comb rows ever beating with rainbow light,
## breathing slowly, squeezing and swelling as it sings while the light of
## each song races out from its glowing chambers over its skin and down its
## seven tentacles; the petals of its throat part whenever it lies open; in
## the duet its light turns the colour of the answers, and when the song
## ends its light goes out.

signal defeated

enum Part { CALL, REACH, DUET }

const ANSWER_EARLY := 0.5
const ANSWER_LATE := 0.32
## Shorter than the gap between waves, so the organs open and close to the song.
const OPEN_TIME := 3.0
const WAVE_DAMAGE := 14.0
## Waves never reach the sub closer together than this (a ping cannot be
## repeated faster than the arena's sonar recharges).
const ANSWER_GAP := 1.2
## Summoned hunters arrive at least this far from the sub, dazed for this long.
const SUMMON_CLEARANCE := 16.0
const SUMMON_DAZE := 1.5
const RING_SHADER := preload("res://src/fx/shaders/song_ring.gdshader")
## Per phase (organs destroyed): seconds between waves, wave speed, chance of a double wave.
const INTERVAL: Array[float] = [3.6, 3.2, 2.8, 2.5]
const SPEED: Array[float] = [13.0, 14.5, 16.0, 17.5]
const DOUBLE: Array[float] = [0.0, 0.25, 0.4, 0.55]
## The Reach: song from the heart and from voices round the arena.
const REACH_INTERVAL := 2.9
const REACH_SPEED := 15.0
## How far the heart surges forward out of the dark (towards the play plane).
const HEART_Z := Vector2(-9.0, -3.5)
## Tentacle slams in the Reach: one every so often. A tentacle rises and
## follows the sub, glowing brighter; then it stops following (the moment to
## move off its line) and slams down along it.
const SLAM_EVERY := 6.0
const SLAM_TRACK := 1.0
const SLAM_LOCK := 0.7
const SLAM_TIME := 0.3
const SLAM_HOLD := 0.6
const SLAM_DAMAGE := 18.0
const SLAM_REACH := 1.6
## The Duet: answers needed in a row; waves come faster the longer it runs.
const DUET_NEED := 12
const DUET_INTERVAL := Vector2(3.0, 1.6)
const DUET_SPEED := Vector2(14.0, 18.0)
## A miss in the Duet costs this many answers off the run.
const DUET_SLIP := 4

var center := Vector2.ZERO
var arena_radius := 30.0
var organs: Array[ChoirOrgan] = []
var phase := 0
var active := false
## Seconds the organs (or in the Reach, the heart's throat) stay open after
## an answered wave.
var vulnerable := 0.0
var part := Part.CALL
## Its heart as a target, from the Reach on.
var heart: ChoirHeart
## Answers in a row during the Duet.
var duet := 0
## For the HUD bar: what the part is called and how far it has gone.
var title := "THE CHOIR"
var meter := 1.0
var meter_max := 1.0

## Each wave: {radius, speed, resolved, arrived, deadline, mesh, mat}
var _waves: Array[Dictionary] = []
var _pulse_timer := 2.5
var _queued_double := -1.0
var _last_ping := -100.0
var _done := false
var _t := 0.0
var _answer_streak := 0
var _heart: Node3D
var _heart_parts: Array[GeometryInstance3D] = []
var _petals: Array[Node3D] = []
var _light: OmniLight3D
var _tentacles: Array[ArrayMesh] = []
var _tentacle_nodes: Array[MeshInstance3D] = []
## How bright each tentacle burns (1 at rest).
var _tentacle_glow: Array[float] = []
var _tentacle_dirs: Array[Vector2] = []
var _hinted := false
var _beat := 0.0
## Seconds since it last sang; how far its throat's petals have parted; how
## much of its light is left (it goes out when the song ends).
var _song := 99.0
var _open := 0.0
var _fade := 1.0
## How far each tentacle has risen into the play plane (0 = trailing in the dark).
var _tentacle_rise: Array[float] = []
var _tentacle_home: Array[Vector2] = []
var _heart_k := 0.0
var _voices: Array[Vector2] = []
var _voice := 0
var _slam := -1
var _slam_t := 0.0
var _slam_timer := SLAM_EVERY
var _slam_angle := 0.0
var _slam_hit := false
var _taught_slam := false


func setup() -> void:
	radius = 0.0
	active_radius = 1000.0
	targetable = false
	pos = center + Vector2(0, 4.0)
	_build_heart()
	_spawn_organs()
	Events.sonar_pinged.connect(_on_ping)


## A still copy of the heart with its tentacles trailing from it, for the
## codex viewport.
static func specimen() -> Node3D:
	var holder := Node3D.new()
	holder.add_child(ChoirModel.build_heart())
	for i in 5:
		var a := PI + PI * (i + 0.5) / 5.0
		var dir := Vector3(cos(a), sin(a), 0.0)
		var pts := PackedVector3Array()
		for k in 8:
			var u := k / 7.0
			pts.append(dir * (4.5 + u * 12.0) + Vector3(-dir.y, dir.x, 0.0) * sin(i * 1.7 + u * 4.0) * 1.5 * u
				+ Vector3(0.0, 0.0, -2.0 * u))
		var fine := ChoirModel.curve(pts, 30)
		var radii := PackedFloat32Array()
		for k in fine.size():
			radii.append(lerpf(0.9, 0.06, float(k) / (fine.size() - 1)))
		var mesh := ArrayMesh.new()
		ChoirModel.tentacle_into(mesh, fine, radii, 4.5)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = ChoirModel.flesh_material()
		holder.add_child(mi)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.35, 0.85)
	light.omni_range = 30.0
	light.position = Vector3(0.0, 0.0, 9.0)
	holder.add_child(light)
	return holder


func _build_heart() -> void:
	_heart = ChoirModel.build_heart()
	_heart.position = Vector3(0, 0, HEART_Z.x)
	add_child(_heart)
	for part: GeometryInstance3D in _heart.get_meta(&"parts"):
		_heart_parts.append(part)
	for pivot: Node3D in _heart.get_meta(&"petals"):
		_petals.append(pivot)
		_heart_parts.append(pivot.get_child(0) as GeometryInstance3D)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.35, 0.85)
	_light.omni_range = 55.0
	_light.light_energy = 1.2
	_light.light_volumetric_fog_energy = 2.0
	_light.omni_attenuation = 0.8
	_light.position = Vector3(0, 0, -2.0)
	add_child(_light)
	for i in 7:
		var mesh := ArrayMesh.new()
		_tentacles.append(mesh)
		var a := PI + PI * (i + 0.5) / 7.0
		_tentacle_dirs.append(Vector2(cos(a), sin(a)))
		_tentacle_home.append(Vector2(cos(a), sin(a)))
		_tentacle_rise.append(0.0)
		_tentacle_glow.append(1.0)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = ChoirModel.flesh_material()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.top_level = true
		add_child(mi)
		_tentacle_nodes.append(mi)


func _spawn_organs() -> void:
	var angles: Array[float] = [160.0, 20.0, 215.0, 325.0]
	for deg in angles:
		var dir := Vector2.from_angle(deg_to_rad(deg))
		var p := center + Vector2(dir.x * arena_radius, dir.y * arena_radius * 0.75) * 0.55
		# Walk outwards until close to the arena wall.
		for _i in 40:
			if level.field.sample(p + dir * 1.0) < 4.0:
				break
			p += dir * 1.0
		var organ := ChoirOrgan.new()
		organ.boss = self
		organ.pos = p
		level.add_entity(organ)
		organs.append(organ)


func tick(delta: float) -> void:
	_t += delta
	vulnerable = maxf(vulnerable - delta, 0.0)
	_animate(delta)
	if _done:
		_update_waves(delta)
		return
	var sub := level.player
	if not active:
		if sub and sub.alive and sub.pos.distance_to(center) < arena_radius * 0.95:
			_begin()
		return
	_pulse_timer -= delta
	if _pulse_timer <= 0.0:
		_sing()
	if _queued_double > 0.0:
		_queued_double -= delta
		if _queued_double <= 0.0:
			if _crowds(pos, _wave_speed()):
				_queued_double = 0.2
			else:
				_emit_wave(_wave_speed())
	if part == Part.REACH:
		_tick_slam(delta)
	_update_waves(delta)
	_update_meter()


## The next wave (or two) of whichever part of the song it is in.
func _sing() -> void:
	match part:
		Part.CALL:
			var p := mini(phase, INTERVAL.size() - 1)
			_pulse_timer = INTERVAL[p]
			_emit_wave(SPEED[p])
			if level.rng.randf() < DOUBLE[p]:
				_queued_double = 1.05
		Part.REACH:
			# Every other wave comes from one of the voices round the arena -
			# but never one that would reach the sub too hard on the heels of
			# another to answer both: a voice that would waits its turn.
			var origin := _voices[(_voice / 2) % _voices.size()] if _voice % 2 == 0 else pos
			if _crowds(origin, REACH_SPEED):
				_pulse_timer = 0.3
				return
			_voice += 1
			_pulse_timer = REACH_INTERVAL
			_emit_wave(REACH_SPEED, origin)
		Part.DUET:
			if _crowds(pos, _wave_speed()):
				_pulse_timer = 0.2
				return
			var k := clampf(float(duet) / DUET_NEED, 0.0, 1.0)
			_pulse_timer = lerpf(DUET_INTERVAL.x, DUET_INTERVAL.y, k)
			_emit_wave(_wave_speed())
			if duet >= DUET_NEED / 3 and level.rng.randf() < 0.3 + 0.3 * k:
				_queued_double = 0.95


## Whether a wave sung now from [param origin] would reach the sub within
## an answer's reach of another still on its way there.
func _crowds(origin: Vector2, speed: float) -> bool:
	var sub := level.player
	if sub == null:
		return false
	var eta := sub.pos.distance_to(origin) / speed
	for w in _waves:
		if w.resolved:
			continue
		var d := sub.pos.distance_to(w.origin)
		var other: float = w.arrived - level.time if w.deadline >= 0.0 else (d - w.radius) / w.speed
		if absf(eta - other) < ANSWER_GAP:
			return true
	return false


func _wave_speed() -> float:
	match part:
		Part.REACH:
			return REACH_SPEED
		Part.DUET:
			return lerpf(DUET_SPEED.x, DUET_SPEED.y, clampf(float(duet) / DUET_NEED, 0.0, 1.0))
	return SPEED[mini(phase, SPEED.size() - 1)]


func _update_meter() -> void:
	match part:
		Part.CALL:
			title = "THE CHOIR  -  THE CALL"
			meter = 0.0
			meter_max = 0.0
			for o in organs:
				meter += o.hp
				meter_max += o.max_hp
			# Organs already silenced count as empty.
			meter_max = maxf(meter_max * 4.0 / maxf(organs.size(), 1.0), 1.0)
		Part.REACH:
			title = "THE CHOIR  -  THE REACH"
			meter_max = heart.max_hp if is_instance_valid(heart) else 1.0
			meter = heart.hp if is_instance_valid(heart) else 0.0
		Part.DUET:
			title = "THE DUET  -  KEEP ANSWERING"
			meter_max = DUET_NEED
			meter = duet


func _begin() -> void:
	active = true
	# The boss track is mastered quieter (its dense mix clips otherwise).
	Audio.play_music(&"boss", 1.5, 3.0)
	Audio.play(&"choir_call", 2.0)
	Events.banner.emit("THE CHOIR", "Answer it.  Keep answering.")
	Events.shake_requested.emit(0.6)
	# The Choir's resonance supercharges the sonar for the duration.
	var stats := level.player.stats
	stats.sonar_cooldown = minf(stats.sonar_cooldown, 0.75)
	stats.sonar_cost = minf(stats.sonar_cost, 2.0)
	# Short-range answers keep the screen readable at this ping rate.
	stats.sonar_range = minf(stats.sonar_range, 38.0)
	get_tree().create_timer(3.5).timeout.connect(func() -> void:
		Events.toast.emit("Ping as each song wave reaches you to answer it.", UiTheme.ACCENT)
		Events.toast.emit("Answered waves open its voice organs - strike them.", UiTheme.ACCENT))


func _emit_wave(speed: float, origin := Vector2.INF) -> void:
	if origin == Vector2.INF:
		origin = pos
	var mat := ShaderMaterial.new()
	mat.shader = RING_SHADER
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	mi.mesh = quad
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	add_child(mi)
	mi.global_position = Vector3(origin.x, origin.y, 0.4)
	mi.scale = Vector3.ONE * 0.5
	_waves.append({"radius": 0.5, "speed": speed, "resolved": false, "arrived": 0.0, "deadline": -1.0, "mesh": mi,
			"mat": mat, "origin": origin})
	_beat = 1.0
	_song = 0.0
	Audio.play(&"choir_wave", -1.0, randf_range(0.9, 1.1))
	level.emit_noise(origin, 20.0, self)
	if origin != pos:
		Fx.shockwave(level, origin, 3.0, Color(1.0, 0.35, 0.85))


func _update_waves(delta: float) -> void:
	var sub := level.player
	var now := level.time
	for w in _waves.duplicate():
		w.radius += w.speed * delta
		var mi: MeshInstance3D = w.mesh
		mi.scale = Vector3.ONE * w.radius
		var fade := clampf(1.0 - (w.radius - arena_radius * (1.0 if w.origin == pos else 1.8)) / 25.0, 0.0, 1.0)
		(w.mat as ShaderMaterial).set_shader_parameter(&"intensity", 2.2 * fade)
		if not w.resolved and sub and sub.alive and not _done:
			if w.deadline < 0.0 and w.radius >= sub.pos.distance_to(w.origin):
				# The wave arrives: a ping just before it counts as an answer...
				if now - _last_ping <= ANSWER_EARLY * Settings.timing_window_mult():
					_answer(w)
				else:
					w.arrived = now
					w.deadline = now + ANSWER_LATE * Settings.timing_window_mult()
			elif w.deadline >= 0.0:
				# ...and so does one shortly after.
				if _last_ping >= w.arrived:
					_answer(w)
				elif now > w.deadline:
					_miss(w)
		if fade <= 0.0:
			mi.queue_free()
			_waves.erase(w)


func _on_ping(origin: Vector2, _range: float) -> void:
	if level.player and origin.distance_to(level.player.pos) < 1.0:
		_last_ping = level.time


func _answer(w: Dictionary) -> void:
	w.resolved = true
	(w.mat as ShaderMaterial).set_shader_parameter(&"ring_color", Color(0.5, 1.0, 1.0))
	vulnerable = OPEN_TIME if part != Part.DUET else 0.0
	_answer_streak += 1
	if part == Part.DUET:
		duet += 1
		if duet >= DUET_NEED:
			_defeat()
	# The answering resonance gives back what the ping cost: only misses drain the cells.
	var sub := level.player
	sub.run.battery = minf(sub.run.battery + sub.stats.sonar_cost, sub.stats.max_battery)
	Audio.play(&"choir_answer", 0.0, 1.0 + minf(_answer_streak, 6) * 0.04)
	Fx.shockwave(level, sub.pos, 4.0, Color(0.3, 0.7, 0.7))
	if not _hinted:
		_hinted = true
		Events.toast.emit("Answered! Its organs are open - harpoon them!", UiTheme.GOOD)


func _miss(w: Dictionary) -> void:
	w.resolved = true
	_answer_streak = 0
	var sub := level.player
	if part == Part.DUET:
		var slipped := mini(duet, DUET_SLIP)
		duet -= slipped
		if slipped > 0:
			Events.toast.emit("The duet falters...", UiTheme.WARN)
	sub.take_damage(WAVE_DAMAGE * (0.6 if part == Part.DUET else 1.0), w.origin, self)
	sub.run.battery = maxf(sub.run.battery - 6.0, 0.0)
	sub.vel += (sub.pos - pos).normalized() * 7.0


## Predicted seconds until the next unresolved wave reaches [param p]
## (negative inside the late-answer window), or INF if none is coming.
func next_arrival(p: Vector2) -> float:
	var best := INF
	for w in _waves:
		if w.resolved:
			continue
		var d := p.distance_to(w.origin)
		if w.deadline >= 0.0:
			best = minf(best, w.arrived - level.time)
		elif w.radius < d:
			best = minf(best, (d - w.radius) / w.speed)
	return best


func on_organ_destroyed(organ: ChoirOrgan) -> void:
	organs.erase(organ)
	phase += 1
	Audio.play(&"choir_call", 3.0, 0.9 + phase * 0.05)
	if organs.is_empty():
		_begin_reach()
		return
	var remaining := organs.size()
	Events.toast.emit("The song falters... %d voice%s remain." % [remaining, "" if remaining == 1 else "s"],
			UiTheme.ACCENT)
	_summon(phase)


## The song calls hunters out of the dark: never on top of the pilot, and
## dazed for a moment as they arrive, so each one can be seen coming.
func _summon(p: int) -> void:
	var count := 1 + p
	var sub := level.player
	for i in count:
		var c: Creature = Lancer.new() if i % 2 == 0 else Jelly.new()
		var spot := Vector2.ZERO
		for _try in 6:
			var a := level.rng.randf() * TAU
			spot = level.field.resolve_circle(center + Vector2(cos(a), sin(a) * 0.6) * arena_radius * 0.6, 1.0)
			if sub == null or spot.distance_to(sub.pos) > SUMMON_CLEARANCE:
				break
		c.pos = spot
		level.add_entity(c)
		c.stun(SUMMON_DAZE)
		Fx.shockwave(level, spot, 3.0, Color(1.0, 0.35, 0.85))


## Its organs gone, the heart surges forward and the song comes from everywhere.
func _begin_reach() -> void:
	part = Part.REACH
	vulnerable = 0.0
	_pulse_timer = 3.0
	_slam_timer = 4.0
	for deg: float in [150.0, 30.0, 255.0, 285.0]:
		var dir := Vector2.from_angle(deg_to_rad(deg))
		_voices.append(level.field.resolve_circle(center + Vector2(dir.x, dir.y * 0.75) * arena_radius * 0.75, 2.0))
	heart = ChoirHeart.new()
	heart.boss = self
	heart.pos = pos
	level.add_entity(heart)
	create_tween().tween_property(self, ^"_heart_k", 1.0, 3.0).set_trans(Tween.TRANS_SINE)
	Audio.play(&"choir_call", 4.0, 0.7)
	Events.shake_requested.emit(0.9)
	Fx.flash(level, pos, Color(1.0, 0.4, 0.9), 50.0, 1.2)
	Events.banner.emit("THE REACH", "Its voices are everywhere now. Answer, and strike the heart.")


## Wounded heart: hunters answer at two thirds and one third.
func on_heart_hurt(frac: float) -> void:
	var want := 4 + (0 if frac > 0.66 else (1 if frac > 0.33 else 2))
	if want > phase:
		phase = want
		_summon(phase - 3)


## Silenced, the heart listens: its hunters hang still, and only a long run
## of answers will end the song.
func begin_duet() -> void:
	if part == Part.DUET:
		return
	part = Part.DUET
	duet = 0
	vulnerable = 0.0
	_slam = -1
	_pulse_timer = 3.5
	for w in _waves:
		w.resolved = true
	for e in level.entities:
		var c := e as Creature
		if c and c.alive and not c is ChoirOrgan and not c is ChoirHeart and c.pos.distance_to(center) < arena_radius * 1.4:
			c.entranced = true
			c.entranced_facing = (pos - c.pos).normalized()
	Audio.play(&"choir_death", -4.0, 1.4)
	Events.shake_requested.emit(0.7)
	Events.banner.emit("THE DUET", "It has stopped singing at you. It is singing with you. Keep answering.")


## The Reach: a tentacle rises and follows the sub, locks on, and slams down
## along its line.
func _tick_slam(delta: float) -> void:
	var sub := level.player
	if _slam < 0:
		_slam_timer -= delta
		if _slam_timer <= 0.0 and sub and sub.alive:
			_begin_slam(sub)
		return
	_slam_t += delta
	var i := _slam
	if _slam_t < SLAM_TRACK:
		if sub and sub.alive:
			_slam_angle = (sub.pos - pos).angle()
		var k := _slam_t / SLAM_TRACK
		_tentacle_rise[i] = k * 0.6
		_tentacle_dirs[i] = _tentacle_dirs[i].slerp(Vector2.from_angle(_slam_angle), 1.0 - exp(-6.0 * delta))
		_tentacle_glow[i] = lerpf(1.0, 2.2, k)
	elif _slam_t < SLAM_TRACK + SLAM_LOCK:
		# Locked on: it stops following and flares.
		_tentacle_dirs[i] = _tentacle_dirs[i].slerp(Vector2.from_angle(_slam_angle), 1.0 - exp(-12.0 * delta))
		_tentacle_glow[i] = 3.8 + 1.2 * sin(_slam_t * 40.0)
	elif _slam_t < SLAM_TRACK + SLAM_LOCK + SLAM_TIME:
		var k := (_slam_t - SLAM_TRACK - SLAM_LOCK) / SLAM_TIME
		_tentacle_rise[i] = lerpf(0.6, 1.0, k)
		if not _slam_hit and k > 0.6:
			_slam_hit = true
			Events.shake_requested.emit(0.5)
			Audio.play(&"impact_rock", -2.0, 0.5)
			if sub and sub.alive and _tentacle_distance(i, sub.pos) < SLAM_REACH + Submarine.RADIUS:
				sub.take_damage(SLAM_DAMAGE, pos, self)
				sub.vel += (sub.pos - pos).normalized() * 10.0
	elif _slam_t < SLAM_TRACK + SLAM_LOCK + SLAM_TIME + SLAM_HOLD:
		_tentacle_glow[i] = 1.3
	else:
		var k := clampf((_slam_t - SLAM_TRACK - SLAM_LOCK - SLAM_TIME - SLAM_HOLD) / 1.2, 0.0, 1.0)
		_tentacle_rise[i] = 1.0 - k
		_tentacle_dirs[i] = Vector2.from_angle(_slam_angle).slerp(_tentacle_home[i], k)
		_tentacle_glow[i] = lerpf(1.3, 1.0, k)
		if k >= 1.0:
			_slam = -1
			_slam_timer = SLAM_EVERY * level.rng.randf_range(0.8, 1.2)


func _begin_slam(sub: Submarine) -> void:
	var at := (sub.pos - pos).angle()
	var best := 0
	for i in _tentacle_home.size():
		if absf(angle_difference(_tentacle_home[i].angle(), at)) < absf(angle_difference(_tentacle_home[best].angle(), at)):
			best = i
	_slam = best
	_slam_t = 0.0
	_slam_hit = false
	_slam_angle = at
	Audio.play(&"choir_tone", -2.0, 0.6)
	if not _taught_slam:
		_taught_slam = true
		Events.toast.emit("A tentacle is rising to follow you. When it stops following and flares, get off its line!",
			UiTheme.DANGER)


## The angle round the heart a locked-on tentacle will slam down along, or
## NAN while none is about to.
func slam_line() -> float:
	return _slam_angle if _slam >= 0 and _slam_t >= SLAM_TRACK * 0.7 and not _slam_hit else NAN


## The points along a tentacle in the play plane (where it is drawn).
func _tentacle_points(i: int) -> PackedVector2Array:
	var dir := _tentacle_dirs[i]
	var pts := PackedVector2Array()
	for k in 14:
		var t := k / 13.0
		var side := Vector2(-dir.y, dir.x) * sin(_t * 0.7 + i * 1.3 + t * 4.0) * 4.0 * t * (1.0 - _tentacle_rise[i] * 0.7)
		pts.append(pos + dir * (5.0 + t * arena_radius * 1.1) + side)
	return pts


func _tentacle_distance(i: int, p: Vector2) -> float:
	var pts := _tentacle_points(i)
	var best := INF
	for k in range(1, pts.size()):
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, pts[k - 1], pts[k])))
	return best


func _defeat() -> void:
	_done = true
	active = false
	vulnerable = 0.0
	Audio.stop_music(2.0)
	Audio.play(&"choir_death", 4.0)
	Events.shake_requested.emit(1.0)
	Fx.flash(level, pos, Color(1.0, 0.8, 1.0), 80.0, 3.0)
	Fx.shockwave(level, pos, 60.0, Color(1.0, 0.6, 1.0))
	var tween := create_tween()
	tween.tween_property(_light, ^"light_energy", 6.0, 1.0)
	tween.tween_property(_light, ^"light_energy", 0.0, 4.0)
	tween.parallel().tween_property(self, ^"_fade", 0.12, 4.0)
	if not Game.meta.logs_found.has(String(SignalLogs.FINAL.id)):
		Game.meta.logs_found.append(String(SignalLogs.FINAL.id))
	get_tree().create_timer(2.0).timeout.connect(func() -> void:
		Events.log_found.emit(&"log_final"))
	get_tree().create_timer(12.0).timeout.connect(func() -> void: defeated.emit())


func _animate(delta: float) -> void:
	_beat = maxf(_beat - delta * 2.5, 0.0)
	_song += delta
	# It breathes slowly; each time it sings it squeezes, then swells.
	var s := 1.0 + 0.03 * sin(_t * 1.3) + (0.0 if _done else 0.07 * _beat * (1.0 - 2.0 * _beat))
	_heart.scale = Vector3(s, s, s)
	_heart.rotation = Vector3(0.0, sin(_t * 0.21) * 0.08, sin(_t * 0.3) * 0.04)
	var boost := 1.0
	var tint := 0.0
	if not _done and part == Part.DUET:
		# The longer the duet runs, the more its light takes the colour of the answers.
		var k := clampf(float(duet) / DUET_NEED, 0.0, 1.0)
		tint = k
		_light.light_energy = 1.2 + k * 2.0 + sin(_t * 2.0) * 0.3
		_light.light_color = Color(1.0, 0.35, 0.85).lerp(Color(0.5, 1.0, 1.0), k)
	elif not _done:
		_light.light_energy = 1.2 + (1.5 if vulnerable > 0.0 else 0.0) + sin(_t * 2.0) * 0.3
		_light.light_color = Color(1.0, 0.95, 0.7) if vulnerable > 0.0 else Color(1.0, 0.35, 0.85)
		boost = 1.5 if vulnerable > 0.0 and part == Part.REACH else 1.0
	else:
		tint = 1.0 if duet >= DUET_NEED else 0.0
	_heart.position.z = lerpf(HEART_Z.x, HEART_Z.y, _heart_k)
	# Its throat parts whenever it lies open to the harpoon; listening in the
	# duet it stays a little parted; and when the song ends it opens.
	var want := 0.0
	if _done:
		want = 0.7
	elif part == Part.REACH and vulnerable > 0.0:
		want = 1.0
	elif part == Part.DUET:
		want = 0.25
	_open = lerpf(_open, want, 1.0 - exp(-(7.0 if want > _open else 2.5) * delta))
	for i in _petals.size():
		var a := TAU * i / _petals.size()
		var flutter := 1.0 + 0.08 * sin(_t * 3.0 + i * 1.9)
		_petals[i].basis = Basis(Vector3.BACK, a + PI) * Basis(Vector3.UP, -_open * 1.15 * flutter)
	var glow := boost * _fade
	var tint_color := Color(0.5, 1.0, 1.0, tint)
	for part_mesh in _heart_parts:
		part_mesh.set_instance_shader_parameter(&"song", _song)
		part_mesh.set_instance_shader_parameter(&"glow_boost", glow)
		part_mesh.set_instance_shader_parameter(&"tint", tint_color)
	# Laid open, its chambers blaze gold behind the parted petals.
	var core := _heart_parts[0]
	core.set_instance_shader_parameter(&"tint", Color(1.0, 0.72, 0.3, 0.8 * _open) if part == Part.REACH
		and not _done else tint_color)
	core.set_instance_shader_parameter(&"flare", 0.5 * _open if part == Part.REACH and not _done else 0.0)
	# Tentacles trail from the heart into the dark, swaying slowly; one about
	# to slam rises into the water the sub swims in.
	for i in _tentacles.size():
		var flat := _tentacle_points(i)
		var pts := PackedVector3Array()
		var rise := _tentacle_rise[i]
		for k in flat.size():
			var t := k / 13.0
			var z := lerpf(-9.0, -7.0 + sin(i + _t * 0.4) * 1.2, t)
			pts.append(Vector3(flat[k].x, flat[k].y, lerpf(z, lerpf(-4.0, 0.0, t), rise)))
		var fine := ChoirModel.curve(pts, 44)
		var radii := PackedFloat32Array()
		for k in fine.size():
			radii.append(lerpf(0.95, 0.08, float(k) / (fine.size() - 1)) * (1.0 + rise * 0.4))
		ChoirModel.tentacle_into(_tentacles[i], fine, radii, 5.0, _t + i * 0.7)
		var node := _tentacle_nodes[i]
		node.set_instance_shader_parameter(&"song", _song)
		node.set_instance_shader_parameter(&"glow_boost", _tentacle_glow[i] * _fade)
		node.set_instance_shader_parameter(&"tint", tint_color)
		# Rising to strike, it lights up all along.
		node.set_instance_shader_parameter(&"flare", clampf((_tentacle_glow[i] - 1.0) / 3.0, 0.0, 1.0) * _fade)


## Seconds since it last sang (its voice organs sing with it).
func song_age() -> float:
	return _song
