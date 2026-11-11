class_name Mimic
extends Creature
## Looks exactly like a salvage cache until something gets close. Sonar marks
## it as hostile, which is the only tell. Worth a lot of salvage if killed.
## The crate is its shell (the same crate a cache is: see [CrateModel]), and
## the beacon blinking on its lid is a lure that keeps a cache's time. Asleep
## it all but passes for one: it breathes, just, and now and then its lid
## lifts a crack and something glows inside before it shuts again.
## Woken, it hunts in bites: it closes in, holding just out of reach, rears
## back with its jaw gaping on a wet red maw (teeth crowding both rims, eyes
## glowing under the lid, the tongue sliding out), snaps forward and slams
## the jaw shut, then recoils and comes again. Its tentacles pull it along
## in strokes together, like an octopus's, coil as it rears and sweep back
## as it strikes. When it gives up it settles, draws them in, shuts, and its
## lure blinks again.

enum State { DORMANT, LUNGE, CHASE, SETTLE }
## A bite: closing in, rearing back, the snap, and the recoil.
enum Bite { APPROACH, WINDUP, SNAP, RECOIL }

const TENTACLES := 6
const TENTACLE_L := 1.5
const TONGUE_L := 0.9
## Where the tentacles grow from, under the base (crate space).
const ROOTS := [Vector3(0.52, -0.5, 0.3), Vector3(0.52, -0.5, -0.3), Vector3(0.0, -0.52, 0.36),
	Vector3(0.0, -0.52, -0.36), Vector3(-0.52, -0.5, 0.3), Vector3(-0.52, -0.5, -0.3)]
const LURE := Color(1.0, 0.75, 0.2)
## Where it holds off its prey before striking (centre to centre), and how
## close it must be to strike.
const STAND_OFF := 2.8
const STRIKE_RANGE := 3.7
const WINDUP_TIME := 0.3
const SNAP_TIME := 0.22
const SNAP_SPEED := 12.0
const RECOIL_TIME := 0.45
const RECOIL_SPEED := 5.0
const GAPE := 1.25
## Strings of slime from the base's rim to the lid's (crate space), that
## stretch thin as the jaw opens and part when it gapes.
const STRANDS := [[Vector3(0.62, 0.11, -0.3), Vector3(0.6, 0.19, -0.26)],
	[Vector3(0.66, 0.11, 0.12), Vector3(0.63, 0.19, 0.18)], [Vector3(0.3, 0.11, 0.42), Vector3(0.36, 0.19, 0.4)],
	[Vector3(0.08, 0.11, -0.42), Vector3(0.02, 0.19, -0.41)], [Vector3(0.45, 0.1, 0.0), Vector3(0.5, 0.2, 0.05)]]

static var _meshes: Dictionary[StringName, ArrayMesh] = {}

var state := State.DORMANT
var _bite := Bite.APPROACH
var _bite_t := 0.0
var _timer := 0.0
var _t := 0.0
var _body: Node3D
var _hinge: Node3D
var _beacon: MeshInstance3D
var _lure_lit: Material
var _lure_blink: Material
var _tongue: MeshInstance3D
var _roof: MeshInstance3D
var _tentacles: Array[MeshInstance3D] = []
var _strands: Array[MeshInstance3D] = []
## How far the jaw is open (radians), and how fast it is moving.
var _jaw := 0.0
var _jaw_v := 0.0
## How far the tentacles are out (0 tucked away, 1 out).
var _reach := 0.0
var _turn := 0.0
var _faces := 1.0
var _pitch := 0.0
var _pull := 0.0
var _tilt := 0.0
## Where it is going for (the direction to its prey), the way its tentacles
## trail (world space), and how far the tongue is out.
var _aim := Vector2.RIGHT
var _trail := Vector2(0.0, -1.0)
var _tongue_out := 0.0


func setup() -> void:
	species = &"mimic"
	max_hp = 55.0
	radius = 1.0
	mass = 3.0
	contact_damage = 18.0
	salvage_drop = 26
	glow_color = Color(1.0, 0.45, 0.1)
	super.setup()
	scannable = false
	lock_facing = true
	# Lying at a slant like any cache (a cache draws its slant from the
	# level's stream; this one must not, or the world would change).
	_tilt = (fposmod(_phase * 7.13, 1.0) - 0.5) * 0.8
	for k in TENTACLES:
		_tentacles[k].set_instance_shader_parameter(&"phase", _phase + k * 1.3)
	_update_visuals(0.0)


func build_model() -> void:
	var glow := glow_color
	var flesh := species_material(func(m: ShaderMaterial) -> void:
		m.set_shader_parameter(&"back_color", Color(0.3, 0.04, 0.07))
		m.set_shader_parameter(&"belly_color", Color(0.72, 0.28, 0.3))
		m.set_shader_parameter(&"glow_color", glow)
		m.set_shader_parameter(&"glow_strength", 3.0)
		m.set_shader_parameter(&"glow_pulse", 0.25)
		m.set_shader_parameter(&"rim_strength", 0.25)
		m.set_shader_parameter(&"roughness", 0.24)
		m.set_shader_parameter(&"metallic", 0.0)
		m.set_shader_parameter(&"skin_pits", 0.005)
		m.set_shader_parameter(&"mottle", 0.5)
		m.set_shader_parameter(&"tooth_color", Color(0.74, 0.67, 0.5))
		m.set_shader_parameter(&"swim_amp", 0.0), &"flesh")
	var limbs := species_material(func(m: ShaderMaterial) -> void:
		m.set_shader_parameter(&"back_color", Color(0.34, 0.12, 0.08))
		m.set_shader_parameter(&"belly_color", Color(0.86, 0.7, 0.62))
		m.set_shader_parameter(&"glow_strength", 0.0)
		m.set_shader_parameter(&"rim_strength", 0.25)
		m.set_shader_parameter(&"roughness", 0.32)
		m.set_shader_parameter(&"metallic", 0.0)
		m.set_shader_parameter(&"mottle", 0.45)
		m.set_shader_parameter(&"spots", 0.35)
		m.set_shader_parameter(&"spot_size", 0.05)
		_writhe(m, TENTACLE_L, 0.12, 3.2, 0.5), &"limbs")
	var tongue := species_material(func(m: ShaderMaterial) -> void:
		m.set_shader_parameter(&"back_color", Color(0.5, 0.1, 0.13))
		m.set_shader_parameter(&"belly_color", Color(0.78, 0.34, 0.36))
		m.set_shader_parameter(&"glow_strength", 0.0)
		m.set_shader_parameter(&"rim_strength", 0.3)
		m.set_shader_parameter(&"roughness", 0.2)
		m.set_shader_parameter(&"metallic", 0.0)
		m.set_shader_parameter(&"skin_pits", 0.005)
		m.set_shader_parameter(&"mottle", 0.3)
		_writhe(m, TONGUE_L, 0.08, 6.0, 1.0), &"tongue")
	_build_meshes()
	_body = Node3D.new()
	model.add_child(_body)
	_shell(CrateModel.base(), _body)
	_part(_meshes[&"maw"], flesh, _body)
	_tongue = _part(_meshes[&"tongue"], tongue, _body)
	for k in TENTACLES:
		_tentacles.append(_part(_meshes[&"tentacle"], limbs, _body))
	for k in STRANDS.size():
		_strands.append(_part(_meshes[&"strand"], flesh, _body))
	_hinge = Node3D.new()
	_hinge.position = CrateModel.HINGE
	_body.add_child(_hinge)
	var lid := Node3D.new()
	lid.position = -CrateModel.HINGE
	_hinge.add_child(lid)
	_shell(CrateModel.lid(), lid)
	_roof = _part(_meshes[&"palate"], flesh, lid)
	_beacon = CrateModel.beacon(LURE)
	_lure_blink = _beacon.material_override
	_lure_lit = MeshKit.emissive_material(Color(1.0, 0.3, 0.08), 10.0)
	lid.add_child(_beacon)


## A tentacle's (or the tongue's) writhing: each hangs from its root (model
## +X) and waves in slow curls that run out to its tip.
static func _writhe(m: ShaderMaterial, length: float, amp: float, wave: float, vertical: float) -> void:
	m.set_shader_parameter(&"body_length", length)
	m.set_shader_parameter(&"swim_amp", amp)
	m.set_shader_parameter(&"swim_freq", 1.0)
	m.set_shader_parameter(&"swim_wave", wave)
	m.set_shader_parameter(&"swim_vertical", vertical)
	m.set_shader_parameter(&"swim_head", 0.0)
	m.set_shader_parameter(&"swim_still", 0.0)
	m.set_shader_parameter(&"bend_pivot", length * 0.5)


## The crate it wears, drawn exactly as a cache's is.
func _shell(mesh: Mesh, parent: Node3D) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	parent.add_child(mi)


func _part(mesh: Mesh, mat: Material, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	visuals.append(mi)
	return mi


# --- Meshes -----------------------------------------------------------------

static func _build_meshes() -> void:
	if not _meshes.is_empty():
		return
	_meshes[&"maw"] = _maw()
	_meshes[&"palate"] = _palate()
	_meshes[&"tongue"] = _tongue_mesh()
	_meshes[&"tentacle"] = _tentacle_mesh()
	var strand := ArrayMesh.new()
	var pts := PackedVector3Array()
	var radii := PackedFloat32Array()
	for i in 9:
		var f := i / 8.0
		pts.append(Vector3(0.0, f, 0.0))
		radii.append(lerpf(0.004, 0.013, pow(absf(f - 0.5) * 2.0, 2.0)))
	MeshKit.tube(strand, pts, radii, 5)
	_meshes[&"strand"] = MeshKit.painted(strand, func(_v: Vector3) -> Color: return Color(0.0, 0.95, 0.0))


## The inside of the base: a wet, lumpy bed of flesh filling it, folded
## and creased, sinking into a dark gullet at the back and rising into
## gums along the walls, crowded with teeth along its rim.
static func _maw() -> ArrayMesh:
	var bed := _lining(-0.02, 1.0, 0.13, func(x: float, z: float) -> float:
		var lumps := 0.035 * sin(x * 13.0 + z * 4.0) * sin(z * 11.0 - x * 3.0) + 0.015 * sin(x * 29.0 - z * 17.0)
		var gullet := -0.16 * exp(-pow((x + 0.56) / 0.14, 2.0) - pow(z / 0.17, 2.0))
		return lumps + gullet)
	return MeshKit.merge([[bed], [_teeth(CrateModel.SEAM - 0.05, 1.0, 11)]])


## The inside of the lid: a ridged palate rising into gums at its walls, a
## row of teeth along its rim, and a cluster of glowing eyes at its front.
static func _palate() -> ArrayMesh:
	var palate := _lining(0.37, -1.0, 0.16, func(x: float, _z: float) -> float:
		return -0.025 * absf(sin(x * 18.0)))
	var parts := [[palate], [_teeth(CrateModel.SEAM + 0.05, -1.0, 23)]]
	var look := Vector3(0.45, -0.9, 0.0).normalized()
	for e: Vector4 in [Vector4(0.38, 0.33, -0.22, 0.06), Vector4(0.43, 0.315, -0.04, 0.08),
			Vector4(0.36, 0.335, 0.13, 0.05), Vector4(0.41, 0.325, 0.27, 0.065), Vector4(0.24, 0.345, 0.04, 0.04)]:
		var centre := Vector3(e.x, e.y, e.z)
		var r := e.w
		# Glowing, bulging from the palate, each with a dark slit of pupil
		# looking down out of it (out of the mouth, once the jaw is open).
		var eye := MeshKit.painted(MeshKit.ball(r, 1.0, 12, 8), func(v: Vector3) -> Color:
			var pupil := v.dot(look) > r * 0.6 and absf(v.z) < r * 0.28
			return Color(0.0 if pupil else 1.0, 0.0 if pupil else 0.6, 0.0))
		parts.append([eye, Transform3D(Basis(), centre)])
	return MeshKit.merge(parts)


## A lining of flesh over the inside of a crate half: at [param level],
## rising [param gum] towards the walls on the side the half opens to
## ([param side] +1 up, -1 down), with [param relief] (x, z) -> height.
static func _lining(level: float, side: float, gum: float, relief: Callable) -> ArrayMesh:
	var inner := Vector2(CrateModel.HALF.x - CrateModel.WALL, CrateModel.HALF.z - CrateModel.WALL) - Vector2.ONE * 0.005
	var nx := 40
	var nz := 26
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in nx + 1:
		for j in nz + 1:
			var x := lerpf(-inner.x, inner.x, float(i) / nx)
			var z := lerpf(-inner.y, inner.y, float(j) / nz)
			var to_wall := minf(inner.x - absf(x), inner.y - absf(z))
			var rise := gum * (1.0 - smoothstep(0.0, 0.14, to_wall))
			var bump := float(relief.call(x, z))
			var y := level + side * (rise + bump)
			# Darker down in the creases and the gullet, paler on the swells.
			var shade := smoothstep(-0.05, 0.04, bump) * smoothstep(0.02, 0.2, to_wall)
			st.set_color(Color(0.0, lerpf(0.12, 0.75, shade), 0.0))
			st.add_vertex(Vector3(x, y, z))
	for i in nx:
		for j in nz:
			var a := i * (nz + 1) + j
			var quad := [a, a + nz + 1, a + 1, a + 1, a + nz + 1, a + nz + 2]
			if side < 0.0:
				quad = [a, a + 1, a + nz + 1, a + 1, a + nz + 2, a + nz + 1]
			for q: int in quad:
				st.add_index(q)
	st.generate_normals()
	return st.commit()


## Teeth crowding a crate half's rim (front and both sides), rooted at
## [param root_y] and pointing [param side] (+1 up, -1 down), leaning in.
static func _teeth(root_y: float, side: float, seed_value: int) -> ArrayMesh:
	var inner := Vector2(CrateModel.HALF.x - CrateModel.WALL, CrateModel.HALF.z - CrateModel.WALL) - Vector2.ONE * 0.04
	var up := Vector3(0.0, side, 0.0)
	var parts := []
	# An outer row of long, uneven fangs, and smaller teeth crowding in
	# behind them.
	for row in 2:
		var k := 1.0 - row * 0.4
		var r := inner - Vector2.ONE * 0.07 * row
		var y := root_y - side * 0.03 * row
		parts.append_array(BodyKit.teeth_row(Vector3(r.x, y, -r.y), Vector3(r.x, y, r.y), 9 + row * 3, 0.2 * k,
			(up - Vector3.RIGHT * (0.25 + 0.2 * row)).normalized(), seed_value + row * 31, row == 0))
		for s: float in [-1.0, 1.0]:
			parts.append_array(BodyKit.teeth_row(Vector3(-0.45, y, s * r.y), Vector3(r.x - 0.06, y, s * r.y),
				10 + row * 3, 0.19 * k, (up - Vector3(0.0, 0.0, s * (0.3 + 0.2 * row))).normalized(),
				seed_value + int(s * 7.0) + row * 31))
	return BodyKit.enamel(MeshKit.merge(parts))


## The tongue, its root at model +X and its tip at -X: thick, flattened,
## blunt, with a furrow down its middle.
static func _tongue_mesh() -> ArrayMesh:
	var profile := PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.05, 0.55), Vector2(0.16, 0.8), Vector2(0.5, 1.0),
		Vector2(1.0, 0.9)])
	var tongue := MeshKit.lathe(profile, TONGUE_L, 14, 16, 0.042, 0.15)
	return MeshKit.painted(tongue, func(v: Vector3) -> Color:
		return Color(0.0, 0.3 + 0.5 * smoothstep(0.0, 0.03, absf(v.z)), 0.0))


## A tentacle, its root at model +X and its tip at -X, tapering, with two
## rows of pale suckers down its underside.
static func _tentacle_mesh() -> ArrayMesh:
	var top := TENTACLE_L * 0.5
	var pts := PackedVector3Array()
	var radii := PackedFloat32Array()
	for i in 25:
		var f := i / 24.0
		pts.append(Vector3(top - TENTACLE_L * f, 0.0, 0.0))
		radii.append(lerpf(0.085, 0.01, pow(f, 0.85)))
	var tube := ArrayMesh.new()
	MeshKit.tube(tube, pts, radii, 9)
	var parts := [[MeshKit.painted(tube, func(v: Vector3) -> Color:
		return Color(0.0, 0.15 + 0.5 * smoothstep(0.0, -0.06, v.y), 0.0))]]
	var sucker := MeshKit.painted(MeshKit.ball(1.0, 0.0, 6, 4), func(_v: Vector3) -> Color:
		return Color(0.0, 1.0, 0.0))
	for i in 16:
		var f := 0.06 + i * 0.055
		var r := lerpf(0.085, 0.01, pow(f, 0.85))
		for s: float in [-1.0, 1.0]:
			var at := Vector3(top - TENTACLE_L * f, -r * 0.8, s * r * 0.45)
			parts.append([sucker, Transform3D(Basis.from_scale(Vector3.ONE * r * 0.35), at)])
	return MeshKit.merge(parts)


# --- Behaviour --------------------------------------------------------------

func think() -> void:
	if state == State.DORMANT:
		var sub := level.player
		if sub and sub.alive and sub.pos.distance_to(pos) < 4.8:
			_wake()


## It springs: a short rear, the jaw thrown open, and it strikes.
func _wake() -> void:
	alert()
	state = State.LUNGE
	_timer = 0.8
	_bite = Bite.WINDUP
	_bite_t = 0.18
	scannable = true
	Audio.play_at(&"lurelight_snap", pos, 3.0)


func behave(delta: float) -> void:
	_t += delta
	var sub := level.player
	var hunting := sub != null and sub.alive
	if hunting:
		_aim = (sub.pos - pos).normalized()
	match state:
		State.DORMANT:
			vel = vel.lerp(Vector2(0, -0.6), 1.0 - exp(-1.2 * delta))
		State.LUNGE, State.CHASE:
			_timer -= delta
			if hunting:
				_hunt(sub, delta)
			if _timer <= 0.0:
				if state == State.LUNGE:
					state = State.CHASE
					_timer = 7.0
				elif _bite != Bite.SNAP:
					state = State.SETTLE
		State.SETTLE:
			vel = vel.lerp(Vector2(0, -1.0), 1.0 - exp(-1.0 * delta))
			if sub and sub.pos.distance_to(pos) < 4.0:
				_wake()


## One bite after another: close in to just out of reach, rear back, snap
## forward, recoil.
func _hunt(sub: Submarine, delta: float) -> void:
	var to := sub.pos - pos
	var d := to.length()
	match _bite:
		Bite.APPROACH:
			seek(sub.pos - _aim * STAND_OFF, 6.5, 2.0, delta)
			if d < STRIKE_RANGE:
				_bite = Bite.WINDUP
				_bite_t = WINDUP_TIME
		Bite.WINDUP:
			# Drawing back, almost still, before the strike.
			vel = vel.lerp(-_aim * 1.5, 1.0 - exp(-8.0 * delta))
			_bite_t -= delta
			if _bite_t <= 0.0:
				_bite = Bite.SNAP
				_bite_t = SNAP_TIME
				vel = _aim * SNAP_SPEED
		Bite.SNAP:
			_bite_t -= delta
			if _bite_t <= 0.0:
				_recoil()
		Bite.RECOIL:
			vel = vel.lerp(Vector2.ZERO, 1.0 - exp(-3.0 * delta))
			_bite_t -= delta
			if _bite_t <= 0.0:
				_bite = Bite.APPROACH


func _recoil() -> void:
	_bite = Bite.RECOIL
	_bite_t = RECOIL_TIME
	vel = -_aim * RECOIL_SPEED


# --- Drawing ----------------------------------------------------------------

## Asleep it is a crate and nothing more, or nearly: it breathes, and now and
## then its lid lifts a crack and shuts. Hunting, each part plays its part
## in the bite (see _hunt); settling, it all draws back in and the lure
## blinks as a cache's beacon does.
func _update_visuals(delta: float) -> void:
	var awake := state == State.LUNGE or state == State.CHASE
	var striking := awake and (_bite == Bite.WINDUP or _bite == Bite.SNAP)
	var jaw_want := 0.0
	var jaw_rate := 12.0
	if state == State.DORMANT:
		jaw_want = _peek()
		jaw_rate = 4.0
	elif awake:
		match _bite:
			Bite.APPROACH:
				jaw_want = 0.32 + 0.06 * sin(_t * 2.2)
			Bite.WINDUP:
				jaw_want = GAPE
				jaw_rate = 16.0
			Bite.SNAP:
				# Wide until the last moment, then slammed shut.
				jaw_want = GAPE if _bite_t > SNAP_TIME * 0.4 else 0.0
				jaw_rate = 16.0 if _bite_t > SNAP_TIME * 0.4 else 45.0
			Bite.RECOIL:
				jaw_want = 0.0 if _bite_t > RECOIL_TIME - 0.18 else 0.35
	var spring := _spring(_jaw, _jaw_v, jaw_want, jaw_rate, delta)
	_jaw = clampf(spring.x, 0.0, GAPE + 0.1)
	_jaw_v = spring.y
	_hinge.rotation.z = _jaw
	_reach = lerpf(_reach, 1.0 if awake else 0.0, 1.0 - exp(-(9.0 if awake else 1.6) * delta))
	# Its tentacles pull in strokes, quicker the faster it goes; they hold
	# still, coiled, while it rears.
	if _reach > 0.02 and not striking:
		_pull += delta * TAU * (0.7 + vel.length() * 0.12)
	# The lure: blinking in a cache's time while it sleeps; lit while it hunts.
	_beacon.material_override = _lure_lit if _reach > 0.3 else _lure_blink
	_beacon.visible = _reach > 0.3 or fmod(_t, 1.2) < 0.6
	# Its eyes, under the lid: asleep, they kindle only as the lid lifts, a
	# glint in the crack.
	var peeking := clampf(_jaw / 0.05, 0.0, 1.0) * (1.0 - _reach)
	_roof.set_instance_shader_parameter(&"glow_boost", (1.6 if striking else 1.0) if awake else 0.3 + 2.5 * peeking)
	_pose_body(delta, awake, striking)
	_pose_tongue(delta, awake)
	_pose_tentacles(delta, striking)
	_pose_strands()
	for v in visuals:
		v.set_instance_shader_parameter(&"marked", _marked / _mark_total if _marked > 0.0 else 0.0)
		v.set_instance_shader_parameter(&"hit_flash", _flash)
		v.set_instance_shader_parameter(&"swim_clock", _pull)
		v.set_instance_shader_parameter(&"swim_power", _reach)


## Asleep, how far its lid lifts: every so often (never in step with another
## mimic), slowly a crack, held a moment, and shut.
func _peek() -> float:
	var every := 8.0 + 4.0 * fposmod(_phase * 3.7, 1.0)
	var c := fposmod(_t + _phase * 5.0, every)
	return 0.05 * smoothstep(0.0, 0.9, c) * (1.0 - smoothstep(1.7, 2.4, c))


## Its mouth turned on its prey: it keeps the side it faces until its prey
## is well behind it, never turning mid-strike, and pitches its mouth up or
## down at it; it rears back as it winds up and dips into the snap. Asleep,
## the crate's slant, and a breath so faint it is barely there.
func _pose_body(delta: float, awake: bool, striking: bool) -> void:
	if awake and not striking:
		if _aim.x < -0.3:
			_faces = -1.0
		elif _aim.x > 0.3:
			_faces = 1.0
	var want_turn := 0.0 if _faces > 0.0 else PI
	_turn = lerp_angle(_turn, want_turn, 1.0 - exp(-4.0 * delta)) if delta > 0.0 else want_turn
	var want_pitch := 0.0
	if awake:
		want_pitch = clampf(atan2(_aim.y, _aim.x * _faces), -0.7, 0.7)
		if _bite == Bite.WINDUP:
			want_pitch += 0.22
		elif _bite == Bite.SNAP:
			want_pitch -= 0.12
	if not striking or _bite == Bite.WINDUP:
		_pitch = lerpf(_pitch, want_pitch, 1.0 - exp(-7.0 * delta)) if delta > 0.0 else want_pitch
	var surge := sin(_pull) * 0.04 * _reach
	_body.basis = Basis(Vector3.UP, _turn) * Basis(Vector3.BACK, lerpf(_tilt, _pitch + surge, _reach))
	var breath := 0.007 * sin(_t * 1.1) * (1.0 - _reach)
	_body.scale = Vector3(1.0, 1.0 + breath + 0.02 * sin(_pull) * _reach, 1.0)


## The tongue slides out along the jaw as it rears, and is whipped back in
## before the jaw slams shut.
func _pose_tongue(delta: float, awake: bool) -> void:
	var want := 1.0 if awake and _bite == Bite.WINDUP else (0.3 if awake and _bite == Bite.APPROACH else 0.0)
	var rate := 7.0 if want > _tongue_out else 25.0
	_tongue_out = lerpf(_tongue_out, want, 1.0 - exp(-rate * delta)) if delta > 0.0 else want
	_tongue.visible = _jaw > 0.15 and _tongue_out > 0.02
	var lift := 0.12 + 0.08 * _tongue_out
	var turned := Basis(Vector3.BACK, PI + lift)
	var basis := Basis(turned.x * lerpf(0.6, 1.25, _tongue_out), turned.y, turned.z)
	_tongue.transform = Transform3D(basis, Vector3(-0.35, 0.03, 0.0) + basis.x * -TONGUE_L * 0.5)
	_tongue.set_instance_shader_parameter(&"bend", 1.2 * _tongue_out)


## The slime strings stretch from rim to rim, thinning as the jaw opens.
func _pose_strands() -> void:
	var lid := Basis(Vector3.BACK, _jaw)
	for k in _strands.size():
		var a: Vector3 = STRANDS[k][0]
		var b: Vector3 = CrateModel.HINGE + lid * (STRANDS[k][1] - CrateModel.HINGE)
		var span := b - a
		var length := span.length()
		var strand := _strands[k]
		# Each lets go at its own gape.
		strand.visible = _jaw > 0.06 and _jaw < 0.75 + k * 0.08 and length > 0.02
		if not strand.visible:
			continue
		var side := span.cross(Vector3.BACK).normalized()
		var thin := clampf(0.12 / length, 0.35, 1.0)
		strand.transform = Transform3D(Basis(side * thin, span, span.cross(side).normalized() * thin), a)


## The tentacles stream behind it as it swims and hang below it otherwise,
## always below the crate. They stroke together: spreading and curling, then
## sweeping back as one; coiled as it rears, swept straight back as it
## strikes. Tucked away (and hidden) while it sleeps.
func _pose_tentacles(delta: float, striking: bool) -> void:
	var show := _reach > 0.02
	var want := (Vector2(0.0, -1.0) - vel * 0.1).normalized()
	_trail = _trail.lerp(want, 1.0 - exp(-6.0 * delta)).normalized() if delta > 0.0 else want
	var local := Vector3.DOWN
	if is_inside_tree():
		local = ((model.global_basis * _body.basis).inverse() * Vector3(_trail.x, _trail.y, 0.0)).normalized()
	local.y = minf(local.y, -0.35)
	var stroke := 0.5 + 0.5 * sin(_pull)
	var curl := lerpf(0.15, 0.85, stroke)
	var fan := lerpf(0.25, 0.6, stroke)
	if striking:
		curl = 1.3 if _bite == Bite.WINDUP else 0.05
		fan = 0.7 if _bite == Bite.WINDUP else 0.15
	for k in TENTACLES:
		var t := _tentacles[k]
		t.visible = show
		if not show:
			continue
		var root: Vector3 = ROOTS[k]
		var dir := (local.normalized() + Vector3(root.x, 0.0, root.z) * fan).normalized()
		var along := -dir
		var side := along.cross(Vector3.BACK if absf(along.z) < 0.9 else Vector3.RIGHT).normalized()
		var up := side.cross(along)
		var thick := lerpf(0.4, 1.0, _reach)
		var basis := Basis(along * _reach, up * thick, side * thick)
		t.transform = Transform3D(basis, root - along * _reach * TENTACLE_L * 0.5)
		t.set_instance_shader_parameter(&"bend", curl + (1.0 - _reach) * 1.2 + 0.05 * sin(k * 2.1))


func on_harpoon_hit(harpoon: Node, damage: float) -> HarpoonReaction:
	if state == State.DORMANT:
		_wake()
	return super.on_harpoon_hit(harpoon, damage)


func on_touch_player(sub: Submarine) -> void:
	if state == State.DORMANT:
		_wake()
	sub.take_damage(contact_damage, pos, self)
	Audio.play_at(&"stalker_bite", pos, -2.0)
	# Its teeth in, it lets go and draws back for the next bite.
	if state != State.DORMANT:
		_aim = (sub.pos - pos).normalized()
		_recoil()


func die() -> void:
	Pickup.scatter(level, pos, &"power", 20, 1.0)
	super.die()


## Shown as a specimen (the codex): awake, so what it really is shows.
func reveal() -> void:
	state = State.CHASE
	_bite = Bite.WINDUP
	_bite_t = 99.0
	_jaw = 0.9
	_reach = 1.0
	_update_visuals(0.0)
