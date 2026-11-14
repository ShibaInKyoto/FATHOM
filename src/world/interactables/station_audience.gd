class_name StationAudience
extends Entity
## "The fauna gathers around the station at night. Lancers, jellies, things I
## have no names for, all facing the floor, perfectly still. Like an
## audience. Every time the tone changes pitch, they turn together." (log_05)
## Over the ruins of Meridian Deep hangs a great gathering held by the
## Choir's tone, arched over the station in tiers like a gallery: hundreds
## of small fish (an [AudienceCrowd]) and among them the hunters (lancers,
## ghostfins, jellies, puffers), all watching one spot on the station, deaf
## to sonar and engines, biting nothing, each hunter with a faint violet
## glow. Each time the tone shifts a pulse rises from the deep through the
## station and up the tiers: as it reaches them their lights flare, they
## jolt, a ring of light passes through each hunter and they turn as one to
## where the tone now seems to come from, tier after tier. Hurt or bump a hunter and
## every member near it wakes and turns on the sub, and the small fish bolt.

const MEMBERS: Array[StringName] = [&"lancer", &"lancer", &"lancer", &"lancer", &"lancer", &"ghostfin",
	&"ghostfin", &"ghostfin", &"ghostfin", &"ghostfin", &"jelly", &"jelly", &"jelly", &"jelly", &"puffer", &"puffer",
	&"puffer"]
## How far below the station's floor the pulses rise from (the tiers are
## arcs round that point, so a pulse reaches each tier all at once).
const DEEP := 18.0
## The hunters' tiers (their distance from where the pulses rise), and how
## high over the floor they keep, so the gallery floor stays passable.
const HUNTER_TIERS: Array[float] = [26.0, 28.6, 31.2, 33.8]
const HUNTER_FLOOR := 6.0
## The small fish's tiers.
const CROWD_TIERS := Vector2(21.0, 35.5)
## Where on the station they watch, from its middle (x flips side with
## each shift of the tone).
const FOCUS := Vector2(6.5, 1.0)
## How far each pulse charts the cave as it rises.
const PULSE_RANGE := 46.0
## How long the ring of each shift takes to swell and fade.
const PULSE_TIME := 1.6
const HALO_SHADER := preload("res://src/fx/shaders/trance_halo.gdshader")
const WAVE_SHADER := preload("res://src/fx/shaders/echo_wave.gdshader")
## Seconds between changes of the tone.
const TONE_PERIOD := Vector2(7.0, 11.0)
## A member that wakes wakes the rest within this range.
const WAKE_RADIUS := 10.0
const HEARING := 60.0
const NOTICE_RANGE := 28.0

## Shown once per session, the first time the sub comes near.
static var _explained := false

var members: Array[Creature] = []
var turns := 0
var _tone_in := 3.0
var _side := 1.0
## While the lullaby is sung back, they hold still, facing the station.
var _listening := 0.0
## Where the pulses rise from.
var _deep := Vector2.ZERO
## The station's floor, which they watch.
var _stage := Vector2.ZERO
var _crowd: AudienceCrowd
var _pulse_began := -100.0
var _wave: MeshInstance3D
## When each member's ring began (by instance id), in [member Level.time].
var _pulsed := {}
var _halos: MultiMeshInstance3D


## Gathers the audience in the water over [param station]; returns it.
static func gather(level: Level, station: MeridianStation) -> StationAudience:
	var audience := StationAudience.new()
	audience.pos = station.pos + Vector2(0.0, 7.0)
	audience._deep = station.pos - Vector2(0.0, DEEP)
	audience._stage = station.pos
	level.add_entity(audience)
	var rng := level.rng
	var focus := audience.focus()
	# The hunters' seats: spread round their tiers, clear of each other.
	var seats := PackedVector2Array()
	for r in HUNTER_TIERS:
		var steps := 9
		for i in steps:
			var a := PI * (i + rng.randf_range(0.25, 0.75)) / steps
			var p := audience._deep + Vector2(cos(a), sin(a)) * r
			if absf(p.x - station.pos.x) > 17.0 or p.y < station.pos.y + HUNTER_FLOOR:
				continue
			if level.field.sample(p) >= 2.0:
				seats.append(p)
	var placed := PackedVector2Array()
	for id in MEMBERS:
		while not seats.is_empty():
			var p: Vector2 = seats[rng.randi_range(0, seats.size() - 1)]
			seats.remove_at(seats.find(p))
			if not AudienceCrowd._clear_of(p, placed, 2.6):
				continue
			var c: Creature = LevelPopulator.SPECIES[id].new()
			c.pos = p
			c.entranced = true
			c.entranced_facing = (focus - p).normalized()
			c.facing = c.entranced_facing
			level.add_entity(c)
			audience.members.append(c)
			placed.append(p)
			break
	# The small fish fill the tiers round them.
	audience._crowd = AudienceCrowd.new()
	audience.add_child(audience._crowd)
	audience._crowd.gather(level, audience._deep, station.pos, CROWD_TIERS, focus, placed)
	return audience


## Where on the station the audience watches: the tone seems to come from
## over one module, then the other.
func focus() -> Vector2:
	return _stage + Vector2(FOCUS.x * _side, FOCUS.y)


func setup() -> void:
	radius = 0.0
	active_radius = 1.0e6


func tick(delta: float) -> void:
	# Killed members are freed: check before touching them (a typed lambda
	# would choke on the freed instance).
	var still: Array[Creature] = []
	for m: Variant in members:
		if is_instance_valid(m) and (m as Creature).alive:
			still.append(m)
	members = still
	_show_halos()
	# One that has left the trance (hurt, bumped) brings the rest with it,
	# and the small fish bolt.
	for m in members:
		if not m.entranced:
			_wake_near(m.pos)
			if _crowd:
				_crowd.scatter(level.time, m.pos)
	var sub := level.player
	if _crowd:
		_crowd.tick(delta, level.time, sub.pos if sub else Vector2.INF)
	if _wave and _wave.visible and level.time - _pulse_began > PULSE_RANGE / Level.ECHO_SPEED + 3.0:
		_wave.visible = false
	if sub and sub.alive and sub.pos.distance_to(pos) < NOTICE_RANGE \
			and members.any(func(m: Creature) -> bool: return m.entranced):
		Wonders.witness("audience")
	if not _explained and sub and sub.alive and sub.pos.distance_to(pos) < NOTICE_RANGE \
			and members.any(func(m: Creature) -> bool: return m.entranced):
		_explained = true
		Events.toast.emit("Hunters hang over the station, facing the floor, perfectly still. Do not wake them.",
			UiTheme.WARN)
	# Once the Choir is singing to the sub, the tone is its own.
	if level.boss and level.boss.active:
		return
	_listening = maxf(_listening - delta, 0.0)
	if _listening > 0.0:
		return
	_tone_in -= delta
	if _tone_in <= 0.0:
		_tone_in = level.rng.randf_range(TONE_PERIOD.x, TONE_PERIOD.y)
		_shift_tone()


## The lullaby sung back from below: they turn to face the station's speakers.
func listen() -> void:
	_listening = 26.0
	for m in members:
		if m.entranced:
			m.entranced_facing = (pos + Vector2(0.0, -2.0) - m.pos).normalized()
			m.entranced_lag = 0.0
			_pulsed[m.get_instance_id()] = level.time
	if _crowd:
		_crowd.pulse(level.time, pos + Vector2(0.0, -2.0), true)


func _wake_near(p: Vector2) -> void:
	for m in members:
		if m.entranced and m.pos.distance_to(p) < WAKE_RADIUS:
			m.entranced = false
			m.alert()


## The tone changes pitch: a pulse rises from the deep through the station
## and up the tiers, and as it reaches them the audience turns together,
## tier after tier.
func _shift_tone() -> void:
	_side = -_side
	turns += 1
	var at := focus()
	_pulse_began = level.time
	for m in members:
		if m.entranced:
			var lag := AudienceCrowd.arrival(_deep, m.pos)
			m.entranced_facing = (at - m.pos).normalized()
			m.entranced_lag = lag + 0.15
			_pulsed[m.get_instance_id()] = level.time + lag
	if _crowd:
		_crowd.pulse(level.time, at)
	# Seen rising through the water and charting the cave as it goes.
	RenderingServer.global_shader_parameter_set(&"echo_ping", Vector4(_deep.x, _deep.y, level.time, PULSE_RANGE))
	_show_wave()
	var sub := level.player
	if sub and sub.pos.distance_to(pos) < HEARING:
		Audio.play_at(&"choir_tone", pos + Vector2(0.0, -8.0), -6.0, 0.0, 1.0 if _side > 0.0 else 0.84)


## The sheet the pulse is seen crossing open water on.
func _show_wave() -> void:
	if _wave == null:
		_wave = MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE * PULSE_RANGE * 2.2
		_wave.mesh = quad
		var mat := ShaderMaterial.new()
		mat.shader = WAVE_SHADER
		mat.set_shader_parameter(&"strength", 0.2)
		_wave.material_override = mat
		_wave.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_wave.top_level = true
		add_child(_wave)
	_wave.global_position = Vector3(_deep.x, _deep.y, -0.6)
	_wave.visible = true


## The glow on each member still held, and the rings passing through them.
func _show_halos() -> void:
	if _halos == null:
		_halos = MultiMeshInstance3D.new()
		_halos.top_level = true
		_halos.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE
		mm.mesh = quad
		mm.instance_count = MEMBERS.size()
		_halos.multimesh = mm
		var mat := ShaderMaterial.new()
		mat.shader = HALO_SHADER
		_halos.material_override = mat
		add_child(_halos)
	var mm := _halos.multimesh
	var shown := 0
	for m in members:
		if not m.entranced or shown >= mm.instance_count:
			continue
		var size := maxf(m.radius, 0.6) * 4.5
		mm.set_instance_transform(shown, Transform3D(Basis().scaled(Vector3.ONE * size),
			Vector3(m.pos.x, m.pos.y, -0.6)))
		var since: float = level.time - float(_pulsed.get(m.get_instance_id(), -100.0))
		var swell := since / PULSE_TIME if since >= 0.0 else 2.0
		mm.set_instance_custom_data(shown, Color(swell, 1.0, 0.0, 0.0))
		shown += 1
	mm.visible_instance_count = shown
