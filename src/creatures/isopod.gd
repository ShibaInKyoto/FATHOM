class_name Isopod
extends Creature
## Armored scavenger that crawls along the cave walls, leaps at passing subs
## and latches on, chewing through power lines until shaken off by boosting
## or a shock pulse.
## A giant isopod: a flattened oval of overlapping armour plates, iron-
## stained, heat glowing faintly along their seams, big dark compound eyes,
## long feeling antennae, a spined tail shield and paddle-like uropods, and
## seven pairs of legs walking in a ripple down each side (animated by the
## creature shader: one mesh, see BodyKit.legged). It lies belly to whatever
## wall it walks and turns round on it; the plates move as rigid segments,
## so it arches as it leaps and curls up, legs flailing, as it falls.

enum State { CRAWL, LEAP, LATCHED, FALL }

const LEAP_RANGE := 7.5
const LEAP_SPEED := 14.0
const SHAKE_OFF_TIME := 1.1
## The body (x from the tail shield's rim to the head; stations as in
## [method BodyKit.body]): flattened, a low dome over a flat belly.
const BODY := [[-0.66, 0.2, 0.04, 0.02, -0.02], [-0.6, 0.3, 0.07, 0.04, -0.01], [-0.48, 0.32, 0.12, 0.06, 0.0],
	[-0.3, 0.38, 0.17, 0.08, 0.0], [-0.05, 0.43, 0.2, 0.09, 0.0], [0.2, 0.44, 0.21, 0.09, 0.0],
	[0.42, 0.4, 0.19, 0.09, 0.0], [0.55, 0.33, 0.15, 0.08, 0.0], [0.64, 0.2, 0.09, 0.06, -0.01],
	[0.68, 0.06, 0.03, 0.03, -0.02]]
## Where each armour plate's rear edge lies, head first: the head shield,
## seven body plates, four narrow tail rings, then the tail shield.
const PLATES := [0.44, 0.33, 0.22, 0.11, 0.0, -0.1, -0.2, -0.3, -0.35, -0.39, -0.43, -0.47, -0.68]
## Below the body its feet stand on the wall this far down (model space).
const FOOT_Y := -0.21

var wall_normal := Vector2.UP
var state := State.CRAWL
var _dir := 1.0
var _timer := 0.0
var _latch_offset := Vector2.ZERO
var _shake := 0.0
var _cooldown := 0.0
var _t := 0.0
## The gait clock, how hard it is walking, how curled it is, and how far it
## is tucked into its plates; and its body's place against the wall.
var _gait := 0.0
var _gait_amp := 0.0
var _curl := 0.0
var _tuck := 0.0
var _up := Vector3.UP
var _tumble := 0.0


func setup() -> void:
	species = &"isopod"
	max_hp = 16.0
	radius = 0.6
	mass = 0.8
	contact_damage = 4.0
	salvage_drop = 3
	glow_color = Color(1.0, 0.6, 0.2)
	body_span = 1.34
	super.setup()
	_dir = 1.0 if level.rng.randf() < 0.5 else -1.0


func build_model() -> void:
	var mat := species_material(func(m: ShaderMaterial) -> void:
		m.set_shader_parameter(&"back_color", Color(0.26, 0.19, 0.15))
		m.set_shader_parameter(&"belly_color", Color(0.5, 0.42, 0.36))
		m.set_shader_parameter(&"glow_color", Color(1.0, 0.5, 0.15))
		m.set_shader_parameter(&"glow_strength", 1.8)
		m.set_shader_parameter(&"metallic", 0.12)
		m.set_shader_parameter(&"roughness", 0.46)
		m.set_shader_parameter(&"rim_strength", 0.25)
		m.set_shader_parameter(&"skin_pits", 0.003)
		m.set_shader_parameter(&"mottle", 0.6)
		m.set_shader_parameter(&"spots", 0.35)
		m.set_shader_parameter(&"spot_size", 0.07)
		m.set_shader_parameter(&"body_length", 1.34)
		m.set_shader_parameter(&"swim_amp", 0.0)
		m.set_shader_parameter(&"anchored", true)
		# The antennae (the only "fins") feel about slowly.
		m.set_shader_parameter(&"flutter_amp", 0.06)
		m.set_shader_parameter(&"flutter_freq", 2.6)
		m.set_shader_parameter(&"flutter_wave", 3.0)
		m.set_shader_parameter(&"fin_color", Color(0.55, 0.42, 0.32, 0.6))
		m.set_shader_parameter(&"tooth_color", Color(0.07, 0.07, 0.08))
		m.set_shader_parameter(&"stride", 0.38)
		m.set_shader_parameter(&"leg_lift", 0.4))
	add_visual(_mesh(), mat)


## The whole animal as one mesh: body, plates, eyes, antennae, tail, legs.
static func _mesh() -> ArrayMesh:
	var parts := [[BodyKit.body(BODY, 36, 20)]]
	# Armour plates: each a shell a little proud of the body, its rear edge
	# lipped and glowing faintly, its front tucked under the plate before;
	# each turns as one rigid piece with its section, so they slide over one
	# another as the body arches and curls.
	for k in PLATES.size() - 1:
		var front: float = PLATES[k]
		var rear: float = PLATES[k + 1]
		if k == 0:
			front = 0.69
		var mid := (front + rear) * 0.5
		var tail := k == PLATES.size() - 2
		var st := []
		for f: float in [0.0, 0.5, 1.0]:
			var x := lerpf(rear, front + 0.035, f)
			var lip := 1.0 - f
			var grow := 1.0 + 0.05 * lip
			st.append([x, BodyKit.at(BODY, x, 1) * grow + 0.012, BodyKit.at(BODY, x, 2) * grow + 0.012 * (1.0 + lip),
				BodyKit.at(BODY, x, 3) * 0.6, BodyKit.at(BODY, x, 4)])
		var plate := BodyKit.body(st, 10, 20, func(t: float, a: float, _p: Vector3) -> float:
			return 0.14 * (1.0 - smoothstep(0.0, 0.12, t)) * smoothstep(-0.3, 0.2, cos(a)) if not tail else 0.0)
		parts.append([plate, Transform3D.IDENTITY, mid])
	# The tail shield's rim of spines, and the uropods either side.
	var spike := ArrayMesh.new()
	MeshKit.tube(spike, PackedVector3Array([Vector3.ZERO, Vector3(-0.06, 0.0, 0.0)]),
		PackedFloat32Array([0.014, 0.002]), 5)
	for i in 9:
		var a := lerpf(-1.2, 1.2, i / 8.0)
		var at := Vector3(-0.66 + 0.06 * (1.0 - cos(a)), 0.02, sin(a) * 0.2)
		parts.append([spike, Transform3D(Basis(Vector3.UP, a), at), -0.6])
	for sgn: float in [1.0, -1.0]:
		var uro := BodyKit.membrane(PackedVector2Array([Vector2(-0.5, 0.0), Vector2(-0.56, 0.0)]),
			PackedVector2Array([Vector2(-0.68, 0.14), Vector2(-0.74, 0.06)]), 0.02)
		uro = MeshKit.painted(uro, func(_v: Vector3) -> Color: return Color(0.0, 0.2, 0.0))
		parts.append([uro, Transform3D(Basis(Vector3.RIGHT, -PI * 0.5 * sgn), Vector3(0.0, -0.01, 0.26 * sgn)), -0.52])
	# The compound eyes: big, dark, glossy, wrapping the front corners.
	for sgn: float in [1.0, -1.0]:
		var eye := BodyKit.enamel(MeshKit.ball(1.0, 0.0, 12, 8))
		parts.append([eye, Transform3D(Basis(Vector3.UP, 0.55 * sgn).scaled(Vector3(0.1, 0.055, 0.06)),
			Vector3(0.56, 0.07, 0.27 * sgn)), 0.56])
	# Antennae: long whips from under the head that sweep out and back along
	# the flanks, and short ones forward; they feel about (fin flutter).
	for sgn: float in [1.0, -1.0]:
		for long: bool in [true, false]:
			var pts := PackedVector3Array()
			var radii := PackedFloat32Array()
			var n := 16 if long else 8
			for i in n:
				var f := i / (n - 1.0)
				var p: Vector3
				if long:
					# Out ahead and to the side, then sweeping back along the flank.
					var path := [Vector3(0.64, 0.02, 0.1), Vector3(0.82, 0.03, 0.22), Vector3(0.84, 0.03, 0.42),
						Vector3(0.62, 0.01, 0.58), Vector3(0.22, -0.01, 0.66), Vector3(-0.2, -0.03, 0.66)]
					var g := f * (path.size() - 1)
					var k := mini(int(g), path.size() - 2)
					var c: Vector3 = (path[k] as Vector3).lerp(path[k + 1], g - k)
					p = Vector3(c.x, c.y, c.z * sgn)
				else:
					p = Vector3(0.66 + f * 0.22, 0.04 + f * 0.05, (0.07 + f * 0.1) * sgn)
				pts.append(p)
				radii.append(lerpf(0.018 if long else 0.014, 0.004, f))
			var tube := ArrayMesh.new()
			MeshKit.tube(tube, pts, radii, 5)
			parts.append([MeshKit.painted(tube, func(v: Vector3) -> Color:
				var d := Vector2(v.x - 0.64, v.z).length()
				return Color(0.0, 0.6, clampf(d * 1.2, 0.0, 1.0))), Transform3D.IDENTITY, 0.62])
	# Seven pairs of walking legs, jointed, hinged under the plates' flanges;
	# neighbours a third of a stride apart, the two sides half a stride.
	for i in 7:
		var x := lerpf(0.36, -0.3, i / 6.0)
		var hw := BodyKit.at(BODY, x, 1)
		for sgn: float in [1.0, -1.0]:
			var hip := Vector3(x, -0.06, hw * 0.62 * sgn)
			var knee := hip + Vector3(0.02, 0.0, 0.17 * sgn)
			var ankle := Vector3(x - 0.02 - i * 0.008, FOOT_Y + 0.08, (hw * 0.62 + 0.24) * sgn)
			var foot := Vector3(x - 0.05 - i * 0.012, FOOT_Y, (hw * 0.62 + 0.25) * sgn)
			var leg := ArrayMesh.new()
			MeshKit.tube(leg, PackedVector3Array([hip, hip.lerp(knee, 0.5), knee * 0.97 + hip * 0.03, knee,
				knee.lerp(ankle, 0.5), ankle, foot]), PackedFloat32Array([0.034, 0.036, 0.03, 0.028, 0.026, 0.02,
				0.006]), 6)
			leg = MeshKit.painted(leg, func(_v: Vector3) -> Color: return Color(0.0, 0.8, 0.0))
			var phase := i * TAU / 3.0 + (PI if sgn < 0.0 else 0.0)
			parts.append([BodyKit.legged(leg, hip, phase, sgn)])
	return BodyKit.merged(parts)


func think() -> void:
	if state != State.CRAWL or _cooldown > 0.0:
		return
	var sub := level.player
	if sub and sub.alive and sub.pos.distance_to(pos) < LEAP_RANGE and level.field.line_of_sight(pos, sub.pos):
		alert()
		state = State.LEAP
		_timer = 0.9
		vel = (sub.pos + sub.vel * 0.3 - pos).normalized() * LEAP_SPEED
		Audio.play_at(&"isopod_leap", pos, -2.0)


func behave(delta: float) -> void:
	_t += delta
	_cooldown = maxf(_cooldown - delta, 0.0)
	match state:
		State.CRAWL:
			_crawl(delta)
		State.LEAP:
			_timer -= delta
			vel *= exp(-0.8 * delta)
			if _timer <= 0.0:
				state = State.FALL
				_timer = 2.0
		State.FALL:
			_timer -= delta
			vel = vel.lerp(Vector2(0, -3.0), 1.0 - exp(-1.5 * delta))
			if level.field.sample(pos) < radius + 0.4 or _timer <= 0.0:
				state = State.CRAWL
				_cooldown = 1.5
		State.LATCHED:
			_ride(delta)


func _crawl(delta: float) -> void:
	var field := level.field
	var d := field.sample(pos)
	var n := field.normal(pos)
	wall_normal = n
	var tangent := Vector2(-n.y, n.x) * _dir
	# Hold ~0.3 m off the surface while walking along it.
	var hold := n * (radius + 0.3 - d) * 6.0
	vel = vel.lerp(tangent * 1.6 + hold, 1.0 - exp(-6.0 * delta))
	if d > radius + 3.0:
		state = State.FALL
		_timer = 2.0
	if level.rng.randf() < delta * 0.15:
		_dir = -_dir
	facing = tangent
	lock_facing = true


func _ride(delta: float) -> void:
	var sub := level.player
	if sub == null or not sub.alive:
		_detach()
		return
	pos = sub.pos + _latch_offset
	vel = sub.vel
	facing = -_latch_offset.normalized()
	sub.drain(1.2 * delta, 3.5 * delta)
	sub.run.last_hit_by = species
	if sub.boosting:
		_shake += delta
		if _shake > SHAKE_OFF_TIME:
			_detach()
			vel = _latch_offset.normalized() * 8.0
	else:
		_shake = maxf(_shake - delta * 0.5, 0.0)


func move_and_collide_field(delta: float, bounce := 0.1) -> Vector2:
	if state == State.LATCHED:
		return Vector2.ZERO
	return super.move_and_collide_field(delta, bounce)


func on_touch_player(sub: Submarine) -> void:
	if state == State.LEAP or state == State.FALL:
		state = State.LATCHED
		_latch_offset = (pos - sub.pos).normalized() * (Submarine.RADIUS + 0.35)
		_shake = 0.0
		lock_facing = true
		Audio.play_at(&"isopod_latch", pos, 0.0)
		Events.toast.emit("Isopod latched on! Boost or shock to shake it off", UiTheme.WARN)
	elif state == State.CRAWL:
		sub.take_damage(contact_damage, pos, self)


func _detach() -> void:
	state = State.FALL
	_timer = 2.0
	_cooldown = 3.0


func stun(duration: float) -> void:
	super.stun(duration)
	if state == State.LATCHED:
		_detach()
		vel = _latch_offset.normalized() * 6.0


func is_latched() -> bool:
	return state == State.LATCHED


## Lies belly to the wall it walks (or the hull it clings to), facing along
## it; turns round on it about its own back rather than flipping over; in
## the water, it tumbles slowly.
func _turn_body(delta: float) -> void:
	var want_up: Vector3
	match state:
		State.CRAWL:
			want_up = Vector3(wall_normal.x, wall_normal.y, 0.0)
		State.LATCHED:
			want_up = Vector3(_latch_offset.x, _latch_offset.y, 0.0).normalized()
		_:
			# Leaping or falling, its back turns over slowly.
			_tumble += delta * (0.6 if state == State.LEAP else 1.6)
			want_up = Vector3(-sin(_tumble), cos(_tumble), 0.0)
	if want_up.length_squared() < 0.5:
		want_up = _up
	_up = _up.slerp(want_up.normalized(), 1.0 - exp(-8.0 * delta)).normalized() if delta > 0.0 else want_up
	var fwd := Vector3(facing.x, facing.y, 0.0)
	fwd = (fwd - _up * fwd.dot(_up))
	if fwd.length_squared() < 1e-4:
		fwd = _up.cross(Vector3.BACK)
	fwd = fwd.normalized()
	var target := Basis(fwd, _up, fwd.cross(_up)).orthonormalized()
	if is_nan(_elev) or delta <= 0.0:
		_elev = 0.0
		model.basis = target
		return
	var q := Quaternion(model.basis.orthonormalized()).slerp(Quaternion(target), 1.0 - exp(-9.0 * delta))
	model.basis = Basis(q)


func _update_visuals(delta: float) -> void:
	# Walking it steps in time with its pace; leaping its legs reach out,
	# falling they flail; latched they grip and knead.
	var speed := vel.length()
	var amp := 0.0
	var tuck := 0.0
	var curl := 0.0
	match state:
		State.CRAWL:
			amp = clampf(speed / 1.2, 0.0, 1.0)
			_gait += delta * (1.5 + speed * 7.0)
		State.LEAP:
			amp = 0.25
			_gait += delta * 4.0
			curl = 0.25
		State.FALL:
			amp = 1.0
			_gait += delta * 16.0
			curl = -1.1
			tuck = 0.35
		State.LATCHED:
			amp = 0.35
			_gait += delta * 9.0
			tuck = -0.25
			curl = -0.25 + sin(_t * 11.0) * 0.06
	_gait_amp = lerpf(_gait_amp, amp, 1.0 - exp(-6.0 * delta))
	_tuck = lerpf(_tuck, tuck, 1.0 - exp(-6.0 * delta))
	_curl = lerpf(_curl, curl, 1.0 - exp(-7.0 * delta))
	_local_bend = _curl
	super._update_visuals(delta)
	# Standing on the wall, the body sits low on its legs.
	var low := 0.68 if state == State.CRAWL else 0.0
	model.position = model.position.lerp(-_up * low, 1.0 - exp(-6.0 * delta))
	for v in visuals:
		v.set_instance_shader_parameter(&"bend", _curl)
		v.set_instance_shader_parameter(&"gait", _gait)
		v.set_instance_shader_parameter(&"gait_amp", _gait_amp)
		v.set_instance_shader_parameter(&"leg_tuck", _tuck)
