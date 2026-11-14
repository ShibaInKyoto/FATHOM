class_name AudienceCrowd
extends Node3D
## The small fish of the audience over Meridian Deep (see [StationAudience]):
## hundreds of lanternfish, deep-bodied hatchetfish and bigger lanternfish
## hanging in tiers that arch over the station like the rows of a gallery,
## every one facing down to the same point on the station (where the tone
## seems to come from). The tiers are arcs round the deep the Choir's
## pulses rise from, so a pulse reaches each tier all at once: as it passes,
## the tier's lights flare, its fish jolt up and beat their fins, then turn
## to the new tone, tier after tier up the dome. They part round the sub and
## close behind it; when the audience wakes they bolt and are gone.
## Only drawn: they bite nothing and are not targets.

## Kinds of fish: how each is scaled (x along the body, y its depth), and
## the light along its belly.
const KINDS := [
	{"scale": Vector3(1.7, 1.7, 1.7), "glow": Color(0.0, 0.0, 0.0), "belly": Color(0.78, 0.83, 0.88)},
	{"scale": Vector3(1.4, 3.2, 1.7), "glow": Color(0.62, 0.36, 1.0), "belly": Color(0.86, 0.88, 0.92)},
	{"scale": Vector3(3.2, 3.2, 3.2), "glow": Color(0.0, 0.0, 0.0), "belly": Color(0.6, 0.66, 0.72)},
]
## How common each kind is.
const KIND_WEIGHTS := [0.6, 0.28, 0.12]
## Spacing along a tier, and between tiers.
const SPACING := 1.15
const TIER_STEP := 1.6
## How far from the arc a fish may hang, and how far in depth.
const JITTER := 0.18
const DEPTH_RANGE := Vector2(-3.2, 1.2)
## The jolt as a pulse passes: how far, how fast it rings, how fast it dies.
const JOLT := 0.6
const JOLT_FREQ := 9.0
const JOLT_DAMP := 3.2
## How far a fish holds off the sub, and how fast it eases back.
const MAKE_WAY := 2.6
## Seconds a pulse keeps a fish moving after it passes.
const ACTIVE := 3.5
const SCATTER_TIME := 3.0

static var _mesh: ArrayMesh

## Where the pulses rise from, and each fish's home, kind, tier, lag behind
## the front, its own phase.
var origin := Vector2.ZERO
var home := PackedVector3Array()
var kind := PackedInt32Array()
var tier := PackedInt32Array()
var _dist := PackedFloat32Array()
var _phase := PackedFloat32Array()
## Each fish's heading: its turn about the vertical (0 facing +x, -PI
## facing -x) and its climb, current and wanted, with the spring's speed.
var _yaw := PackedFloat32Array()
var _yaw_v := PackedFloat32Array()
var _yaw_to := PackedFloat32Array()
var _elev := PackedFloat32Array()
var _elev_to := PackedFloat32Array()
## How far it has been pushed aside by the sub.
var _aside := PackedVector3Array()
## Its slot in its MultiMesh.
var _slot := PackedInt32Array()
var _mm: Array[MultiMesh] = []
var _mmi: Array[MultiMeshInstance3D] = []
var _tiers := 0
## Each tier's distance from [member origin], and the furthest fish's.
var _tier_dist := PackedFloat32Array()
var _furthest := 0.0
## When the last pulse began (in level time), and when the crowd bolted.
var _pulse_at := -100.0
var _scatter_at := -1.0
var _scatter_from := Vector2.ZERO
var _vel := PackedVector3Array()
var _clock := 0.0
var _dirty := true


## The fish's shared mesh: the shoal's lanternfish.
static func fish_mesh() -> ArrayMesh:
	if _mesh == null:
		_mesh = Shoal.fish_mesh()
	return _mesh


## Fills the tiers over [param station] with fish, the pulses rising from
## [param from]; [param focus] where they face to begin with. Fish are kept
## out of the rock and clear of [param avoid] (the hunters' places).
func gather(level: Level, from: Vector2, station: Vector2, radii: Vector2, focus: Vector2,
		avoid: PackedVector2Array) -> void:
	origin = from
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(station) + 3
	var r := radii.x
	while r <= radii.y:
		var t := _tiers
		# Round the arc, as far as the gallery's walls allow.
		var steps := int(PI * r / SPACING)
		for i in steps:
			var a := PI * (i + rng.randf_range(0.2, 0.8)) / steps
			var rr := r + rng.randf_range(-JITTER, JITTER)
			var p := from + Vector2(cos(a), sin(a)) * rr
			if absf(p.x - station.x) > 19.0 or p.y < station.y + 1.4:
				continue
			if level.field.sample(p) < 1.2 or not _clear_of(p, avoid, 1.6):
				continue
			var z := rng.randf_range(DEPTH_RANGE.x, DEPTH_RANGE.y)
			# Behind the play plane the rock rises: keep in front of it.
			if TerrainRelief.height(level.field, p) > z - 0.4:
				z = rng.randf_range(0.0, DEPTH_RANGE.y)
			var roll := rng.randf()
			var k := 0
			while k < KIND_WEIGHTS.size() - 1 and roll > KIND_WEIGHTS[k]:
				roll -= KIND_WEIGHTS[k]
				k += 1
			home.append(Vector3(p.x, p.y, z))
			kind.append(k)
			tier.append(t)
			_dist.append(p.distance_to(from))
			_phase.append(rng.randf())
			_phase.append(rng.randf())
			var h := _facing(p, focus, _phase[_phase.size() - 1])
			_phase.remove_at(_phase.size() - 1)
			_yaw.append(0.0 if h.x >= 0.0 else -PI)
			_yaw_to.append(_yaw[_yaw.size() - 1])
			_yaw_v.append(0.0)
			_elev.append(atan2(h.y, absf(h.x)))
			_elev_to.append(_elev[_elev.size() - 1])
			_aside.append(Vector3.ZERO)
			_vel.append(Vector3.ZERO)
		_tiers += 1
		_tier_dist.append(r)
		r += TIER_STEP
	for d in _dist:
		_furthest = maxf(_furthest, d)
	_build(level)
	_dirty = true


static func _clear_of(p: Vector2, points: PackedVector2Array, dist: float) -> bool:
	for q in points:
		if q.distance_squared_to(p) < dist * dist:
			return false
	return true


## One MultiMesh per tier and kind, so each tier's lights can flare on
## their own.
func _build(level: Level) -> void:
	var mats: Array[ShaderMaterial] = []
	for k in KINDS.size():
		var mat := ShaderMaterial.new()
		mat.shader = Creature.SHADER
		var glow: Color = KINDS[k]["glow"]
		Shoal.configure_material(mat, glow if glow != Color(0, 0, 0) else level.biome.glow_color)
		mat.set_shader_parameter(&"belly_color", KINDS[k]["belly"])
		mats.append(mat)
	var counts := {}
	_slot.resize(home.size())
	for i in home.size():
		var key := tier[i] * KINDS.size() + kind[i]
		_slot[i] = counts.get(key, 0)
		counts[key] = _slot[i] + 1
	_mm.resize(_tiers * KINDS.size())
	_mmi.resize(_tiers * KINDS.size())
	for key in _tiers * KINDS.size():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = fish_mesh()
		mm.instance_count = counts.get(key, 0)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mats[key % KINDS.size()]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.top_level = true
		mmi.visible = mm.instance_count > 0
		add_child(mmi)
		_mm[key] = mm
		_mmi[key] = mmi


func count() -> int:
	return home.size()


## A pulse of the Choir's tone rises from [member origin], starting at
## [param now]; as it reaches each fish it turns to face [param focus].
## [param all_at_once]: no pulse, they all stir and turn together.
func pulse(now: float, focus: Vector2, all_at_once := false) -> void:
	_pulse_at = now - (_furthest / Level.ECHO_SPEED if all_at_once else 0.0)
	for i in home.size():
		var h := _facing(Vector2(home[i].x, home[i].y), focus, _phase[i])
		_yaw_to[i] = 0.0 if h.x >= 0.0 else -PI
		_elev_to[i] = atan2(h.y, absf(h.x))


## The way a fish at [param p] faces to look at [param focus], turned a
## little its own way ([param phase]).
static func _facing(p: Vector2, focus: Vector2, phase: float) -> Vector2:
	return (focus - p).normalized().rotated(sin(phase * 40.0) * 0.12)


## Seconds after a pulse begins before it reaches [param p].
static func arrival(from: Vector2, p: Vector2) -> float:
	return p.distance_to(from) / Level.ECHO_SPEED


## The audience has woken: every fish bolts away from [param from].
func scatter(now: float, from: Vector2) -> void:
	if _scatter_at >= 0.0:
		return
	_scatter_at = now
	_scatter_from = from
	for i in home.size():
		var away := Vector2(home[i].x, home[i].y) - from
		var dir := (away.normalized() + Vector2(0.0, 0.4)).normalized()
		_vel[i] = Vector3(dir.x, dir.y, 0.0) * (2.0 + _phase[i] * 2.0)


func tick(delta: float, now: float, sub: Vector2) -> void:
	_clock += delta
	for mmi in _mmi:
		mmi.set_instance_shader_parameter(&"swim_clock", _clock)
	if _scatter_at >= 0.0:
		_bolt(delta, now)
		return
	var since := now - _pulse_at
	# Each tier's lights flare as the pulse passes it.
	for t in _tiers:
		var at := since - _tier_dist[t] / Level.ECHO_SPEED
		var flare := 1.0 + (4.0 * exp(-at * 2.2) if at >= 0.0 else 0.0)
		for k in KINDS.size():
			_mmi[t * KINDS.size() + k].set_instance_shader_parameter(&"glow_boost", flare)
	var moving := since < _furthest / Level.ECHO_SPEED + ACTIVE
	# Make way for the sub: only the fish near it move.
	var near := false
	for i in home.size():
		var d := Vector2(home[i].x + _aside[i].x, home[i].y + _aside[i].y) - sub
		var want := Vector3.ZERO
		if d.length_squared() < MAKE_WAY * MAKE_WAY:
			var push := d.normalized() * (MAKE_WAY - d.length())
			want = Vector3(push.x, push.y, 0.0)
		if want != Vector3.ZERO or _aside[i] != Vector3.ZERO:
			near = true
			_aside[i] = _aside[i].lerp(want, 1.0 - exp(-(6.0 if want != Vector3.ZERO else 1.5) * delta))
			if _aside[i].length_squared() < 0.0001 and want == Vector3.ZERO:
				_aside[i] = Vector3.ZERO
	if not (moving or near or _dirty):
		return
	_dirty = false
	for i in home.size():
		var at := since - _dist[i] / Level.ECHO_SPEED
		var jolt := 0.0
		var power := -0.7
		if at >= 0.0 and at < ACTIVE:
			jolt = JOLT * exp(-at * JOLT_DAMP) * sin(at * JOLT_FREQ)
			power = -0.7 + 1.4 * exp(-at * 1.5)
			# It turns once the jolt has passed.
			if at > 0.15:
				var s := _spring(_yaw[i], _yaw_v[i], _yaw_to[i], 9.0, delta)
				_yaw[i] = s.x
				_yaw_v[i] = s.y
				_elev[i] = lerpf(_elev[i], _elev_to[i], 1.0 - exp(-4.0 * delta))
		var up := (Vector2(home[i].x, home[i].y) - origin).normalized()
		var p := home[i] + _aside[i] + Vector3(up.x, up.y, 0.0) * jolt
		_place(i, p, power)


func _place(i: int, p: Vector3, power: float) -> void:
	var key := tier[i] * KINDS.size() + kind[i]
	var size: Vector3 = KINDS[kind[i]]["scale"]
	var b := Basis(Vector3.UP, _yaw[i]) * Basis(Vector3.BACK, _elev[i]) * Basis.from_scale(size)
	_mm[key].set_instance_transform(_slot[i], Transform3D(b, p))
	_mm[key].set_instance_custom_data(_slot[i], Color(_phase[i], 0.0, power, 0.0))


## Bolting: every fish darts away, turning to face its way, and is gone.
func _bolt(delta: float, now: float) -> void:
	var t := now - _scatter_at
	if t > SCATTER_TIME:
		visible = false
		return
	for i in home.size():
		_vel[i] *= 1.0 + delta * 2.5
		home[i] += _vel[i] * delta
		var v := Vector2(_vel[i].x, _vel[i].y)
		_yaw_to[i] = 0.0 if v.x >= 0.0 else -PI
		var s := _spring(_yaw[i], _yaw_v[i], _yaw_to[i], 16.0, delta)
		_yaw[i] = s.x
		_yaw_v[i] = s.y
		_elev[i] = lerpf(_elev[i], atan2(v.y, absf(v.x)), 1.0 - exp(-8.0 * delta))
		_place(i, home[i], 0.6)
	for mmi in _mmi:
		mmi.set_instance_shader_parameter(&"glow_boost", 1.0 + 3.0 * exp(-t * 3.0))


## A critically damped spring from [param x] (moving at [param v]) towards
## [param to]; returns the new position and speed.
static func _spring(x: float, v: float, to: float, k: float, delta: float) -> Vector2:
	var a := k * k * (to - x) - 2.0 * k * v
	v += a * delta
	x += v * delta
	return Vector2(x, v)
