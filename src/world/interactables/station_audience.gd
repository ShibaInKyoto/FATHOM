class_name StationAudience
extends Entity
## "The fauna gathers around the station at night. Lancers, jellies, things I
## have no names for, all facing the floor, perfectly still. Like an
## audience. Every time the tone changes pitch, they turn together." (log_05)
## Over the ruins of Meridian Deep hangs a gathering of hunters held by the
## Choir's tone, in two loose rows over the roof like seats in a gallery:
## deaf to sonar and engines, biting nothing, a faint violet glow on each.
## Each time the tone shifts it passes through them as a ring of light, and
## they turn as one, the turn running across the rows. Hurt or bump one,
## and every member near it wakes and turns on the sub.

const MEMBERS: Array[StringName] = [&"lancer", &"lancer", &"lancer", &"lancer", &"ghostfin", &"ghostfin", &"ghostfin",
	&"jelly", &"jelly"]
## Their seats over the station: two rows above its roof (x across, height
## over the floor), the middle of each kept clear of the mast.
const SEATS: Array[Vector2] = [Vector2(-10.5, 7.0), Vector2(-7.0, 7.4), Vector2(-3.5, 7.1), Vector2(3.8, 7.3),
	Vector2(7.3, 7.0), Vector2(10.8, 7.4), Vector2(-8.8, 10.0), Vector2(-5.2, 10.3), Vector2(-1.8, 10.6),
	Vector2(2.2, 10.4), Vector2(5.6, 10.1), Vector2(9.1, 10.3)]
## How long a turn takes to run from one end of the rows to the other.
const RIPPLE := 0.7
## How long the ring of each shift takes to swell and fade.
const PULSE_TIME := 1.6
const HALO_SHADER := preload("res://src/fx/shaders/trance_halo.gdshader")
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
## When each member's ring began (by instance id), in [member Level.time].
var _pulsed := {}
var _halos: MultiMeshInstance3D


## Gathers the audience in the water over [param station]; returns it.
static func gather(level: Level, station: MeridianStation) -> StationAudience:
	var audience := StationAudience.new()
	audience.pos = station.pos + Vector2(0.0, 7.0)
	level.add_entity(audience)
	var rng := level.rng
	var seats := SEATS.duplicate()
	var heading := Vector2(0.45, -1.0).normalized()
	for id in MEMBERS:
		while not seats.is_empty():
			var seat: Vector2 = seats.pop_at(rng.randi_range(0, seats.size() - 1))
			var p := Vector2.INF
			# Where the cave is low, the seat drops a little.
			for drop: float in [0.0, -1.2, 1.2, -2.4]:
				var q := station.pos + seat + Vector2(rng.randf_range(-0.5, 0.5), drop + rng.randf_range(-0.3, 0.3))
				if level.field.sample(q) >= 2.0:
					p = q
					break
			if p == Vector2.INF:
				continue
			var c: Creature = LevelPopulator.SPECIES[id].new()
			c.pos = p
			c.entranced = true
			c.entranced_facing = heading
			c.facing = heading
			level.add_entity(c)
			audience.members.append(c)
			break
	return audience


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
	# One that has left the trance (hurt, bumped) brings the rest with it.
	for m in members:
		if not m.entranced:
			_wake_near(m.pos)
	var sub := level.player
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


func _wake_near(p: Vector2) -> void:
	for m in members:
		if m.entranced and m.pos.distance_to(p) < WAKE_RADIUS:
			m.entranced = false
			m.alert()


## The tone changes pitch, and the audience turns together, the turn (and
## the ring of light that comes with it) running across the rows from the
## side they turn away from.
func _shift_tone() -> void:
	_side = -_side
	turns += 1
	var heading := Vector2(0.45 * _side, -1.0).normalized()
	var lo := INF
	var hi := -INF
	for m in members:
		lo = minf(lo, m.pos.x)
		hi = maxf(hi, m.pos.x)
	for m in members:
		if m.entranced:
			var along := inverse_lerp(lo, hi, m.pos.x) if hi > lo else 0.5
			var lag := RIPPLE * (along if _side > 0.0 else 1.0 - along)
			m.entranced_facing = heading
			m.entranced_lag = lag
			_pulsed[m.get_instance_id()] = level.time + lag
	var sub := level.player
	if sub and sub.pos.distance_to(pos) < HEARING:
		Audio.play_at(&"choir_tone", pos + Vector2(0.0, -8.0), -6.0, 0.0, 1.0 if _side > 0.0 else 0.84)


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
