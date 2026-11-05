class_name Gulper
extends Creature
## Gulper eel living in a wall burrow. It feels vibrations: subs that pass
## fast, loud or with a lamp in its face get struck by a lunge from the rock.
## The entity position is the head; the body runs back into the burrow.
## A real gulper's head: a slender upper jaw with pin eyes at its tip over a
## pair of long thin jaw bones holding a vast black pouch. Lurking, the
## mouth hangs open, breathing, now and then gulping. Before it strikes it
## draws back into a coil, jaws clamped, turning to aim; then it lunges, the
## jaw dropping wide and the pouch ballooning, and bites shut at the end,
## and draws back into its burrow. Hurt, it snaps back into the hole and
## only slowly comes out again. The burrow is a rocky rim in the cave face,
## dark inside, prey bones strewn on it. Head and body are one skin, the
## body following the head with a lag, whipping out behind a lunge and
## bunching into curves as it pulls back, a wave running down it.

enum State { LURK, STRIKE, RETRACT, HIDE, WINDUP }

const REACH := 9.5
const STRIKE_TIME := 0.32
## The coil before a strike: a tell, as long as a blink.
const WINDUP_TIME := 0.22
const SENSE_RANGE := 10.0
## Model space: the head, x from where the body joins it to the snout.
## Stations as in [method BodyKit.body].
## The back of the skull runs down into a neck, round and as thick as the
## body, whose last ring the body meets edge to edge (see [method _body_tube]).
const HEAD := [[-1.05, NECK_R, NECK_R, NECK_R, 0.0], [-0.85, 0.125, 0.13, 0.12, 0.0],
	[-0.62, 0.16, 0.165, 0.1, 0.01], [-0.4, 0.18, 0.17, 0.06, 0.02], [-0.1, 0.13, 0.12, 0.04, 0.04],
	[0.3, 0.08, 0.07, 0.03, 0.045], [0.7, 0.045, 0.045, 0.02, 0.045], [0.92, 0.012, 0.016, 0.01, 0.04]]
const HINGE := Vector3(-0.42, -0.05, 0.0)
const NECK_X := -1.05
const NECK_R := 0.115
## Sides round the body, as round the head (BodyKit.body), so the two meet
## vertex to vertex.
const BODY_SIDES := 16
const JAW_LEN := 1.32
## Sections down the jaw and points across each, for the pouch.
const POUCH_ROWS := 20
const POUCH_COLS := 12
const ROCK_SHADER := preload("res://src/fx/shaders/burrow_rock.gdshader")

## Wrinkled skin, shared by every gulper (see _skin()).
static var _skin_tex: NoiseTexture2D

var wall_normal := Vector2.UP
var state := State.LURK
var _burrow := Vector2.ZERO
var _rest := Vector2.ZERO
var _strike_from := Vector2.ZERO
var _strike_to := Vector2.ZERO
var _timer := 0.0
var _cooldown := 0.0
var _t := 0.0
var _body_mesh := ArrayMesh.new()
var _body: MeshInstance3D
var _head: MeshInstance3D
var _jaw: MeshInstance3D
var _pouch_mesh := ArrayMesh.new()
var _gape := 0.16
## Where the burrow opens in the rock face (3D) and the way it points out;
## none until the eel is found to sit against rock.
var _mouth := Vector3.INF
var _axis := Vector3.UP
## Two points a third and two thirds of the way along the body (world
## space), following where the head pulls it with a lag; the body is a
## smooth curve through them.
var _bends := PackedVector3Array()
var _last_pos := Vector2.ZERO
var _dt := 0.0
## How hard the body is waving (speed), how coiled it is (the wind-up), the
## wave's phase, the shake of a bite, a gulp's progress and the wait for the
## next, and how shy it is after hiding.
var _wiggle := 0.0
var _coil := 0.0
var _wave := 0.0
var _bite := 0.0
var _gulp := 1.0
var _gulp_wait := 5.0
var _shy := 0.0
## The head's skin (skull and neck) in model space, lofted once and joined
## to the body every frame.
var _head_rings: Array[PackedVector3Array] = []


func setup() -> void:
	species = &"gulper"
	max_hp = 42.0
	radius = 0.75
	mass = 10.0
	contact_damage = 20.0
	salvage_drop = 6
	glow_color = Color(1.0, 0.35, 0.5)
	_burrow = pos - wall_normal * 1.2
	_rest = pos + wall_normal * 0.8
	pos = _rest
	super.setup()
	lock_facing = true
	facing = wall_normal
	# Turned to face out of the wall before the body is laid out in its space
	# (a specimen on show is never ticked).
	model.basis = Basis(Vector3.BACK, facing.angle())
	_rebuild_body()


func build_model() -> void:
	var mat := species_material(func(m: ShaderMaterial) -> void:
		m.set_shader_parameter(&"back_color", Color(0.09, 0.083, 0.095))
		m.set_shader_parameter(&"belly_color", Color(0.15, 0.09, 0.1))
		m.set_shader_parameter(&"glow_color", Color(1.0, 0.3, 0.45))
		m.set_shader_parameter(&"glow_strength", 2.5)
		m.set_shader_parameter(&"glow_pulse", 0.4)
		# Velvet, not plastic: matte skin with a soft sheen where it turns
		# away, finely pitted.
		m.set_shader_parameter(&"roughness", 0.7)
		m.set_shader_parameter(&"metallic", 0.0)
		m.set_shader_parameter(&"rim_strength", 0.3)
		m.set_shader_parameter(&"skin_pits", 0.004)
		# Fine wrinkled skin, laid on the skin's own coordinates so it stays put
		# as the body bends and slides.
		m.set_shader_parameter(&"skin_on_uv", true)
		m.set_shader_parameter(&"skin_tex", _skin())
		m.set_shader_parameter(&"skin_tex_scale", 2.6)
		m.set_shader_parameter(&"skin_tex_depth", 0.006)
		m.set_shader_parameter(&"skin_tex_shade", 0.22)
		m.set_shader_parameter(&"body_length", 1.6)
		m.set_shader_parameter(&"swim_amp", 0.0)
		m.set_shader_parameter(&"flutter_amp", 0.03)
		m.set_shader_parameter(&"flutter_freq", 6.0)
		m.set_shader_parameter(&"flutter_wave", 4.0)
		m.set_shader_parameter(&"tooth_color", Color(0.82, 0.78, 0.72)))
	# The skull and neck are lofted with the body (see _body_tube).
	var parts := []
	# Glowing lips along the upper jaw, and needle teeth inside them.
	for sgn: float in [1.0, -1.0]:
		var lip := PackedVector3Array()
		var radii := PackedFloat32Array()
		for i in 12:
			var x := lerpf(HINGE.x + 0.08, 0.9, i / 11.0)
			lip.append(_upper_lip(x, sgn))
			radii.append(0.009)
		var tube := ArrayMesh.new()
		MeshKit.tube(tube, lip, radii, 5)
		parts.append([MeshKit.painted(tube, func(_v: Vector3) -> Color: return Color(0.0, 0.5, 0.0))])
		for t: Array in BodyKit.teeth_row(_upper_lip(-0.2, sgn) - Vector3(0.0, 0.0, 0.025 * sgn),
				_upper_lip(0.84, sgn) - Vector3(0.0, 0.0, 0.01 * sgn), 14, 0.06, Vector3(0.0, -1.0, -0.15 * sgn),
				3 if sgn > 0.0 else 4, false):
			parts.append([BodyKit.enamel(t[0]), t[1]])
	_head = add_visual(BodyKit.merged(parts), mat)
	# The lower jaw: two long, thin, blade-like jaw bones under the skin,
	# needle teeth along them.
	var jaw_parts := []
	for sgn: float in [1.0, -1.0]:
		jaw_parts.append([_jaw_blade(sgn)])
		for t: Array in BodyKit.teeth_row(_mandible(0.12, sgn) + Vector3(0.0, 0.02, -0.005 * sgn),
				_mandible(0.95, sgn) + Vector3(0.0, 0.012, 0.0), 13, 0.055, Vector3(0.0, 1.0, -0.15 * sgn),
				5 if sgn > 0.0 else 6, false):
			jaw_parts.append([BodyKit.enamel(t[0]), t[1]])
	_jaw = add_visual(BodyKit.merged(jaw_parts), mat, Transform3D(Basis(), HINGE))
	var pouch := MeshInstance3D.new()
	pouch.mesh = _pouch_mesh
	pouch.material_override = mat
	pouch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.add_child(pouch)
	visuals.append(pouch)
	add_eyes(Vector3(0.74, 0.065, 0.042), 0.026, Color(0.6, 0.22, 0.28), 0.45, Eye.FISH)
	# The body is rebuilt every frame, in the head's own space so its skin
	# runs on unbroken from the neck.
	_body = MeshInstance3D.new()
	_body.mesh = _body_mesh
	_body.material_override = mat
	_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.add_child(_body)
	visuals.append(_body)
	_rebuild_pouch()


## The skin's wrinkles: creased ridged noise, tiling, built once.
static func _skin() -> NoiseTexture2D:
	if _skin_tex == null:
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
		noise.fractal_octaves = 4
		noise.frequency = 0.012
		noise.seed = 7
		_skin_tex = NoiseTexture2D.new()
		_skin_tex.width = 256
		_skin_tex.height = 256
		_skin_tex.seamless = true
		_skin_tex.generate_mipmaps = true
		_skin_tex.noise = noise
	return _skin_tex


## The upper jaw's lip on side [param sgn] at model x [param x].
static func _upper_lip(x: float, sgn: float) -> Vector3:
	return Vector3(x, BodyKit.at(HEAD, x, 4) - BodyKit.at(HEAD, x, 3) * 0.85, BodyKit.at(HEAD, x, 1) * 0.86 * sgn)


## One side of the lower jaw (jaw space): a flattened blade along the jaw
## bone, deep at the hinge and tapering to the chin, pale beneath.
static func _jaw_blade(sgn: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := 18
	var sides := 10
	for i in rows + 1:
		var u := i / float(rows)
		var p := _mandible(u, sgn)
		var ahead := _mandible(minf(u + 0.02, 1.0), sgn) - _mandible(maxf(u - 0.02, 0.0), sgn)
		var tangent := ahead.normalized()
		var side := tangent.cross(Vector3.UP).normalized()
		var up := side.cross(tangent)
		var w := lerpf(0.02, 0.006, u)
		var h := lerpf(0.055, 0.012, u)
		for j in sides + 1:
			var a := TAU * j / sides
			st.set_color(Color(0.0, smoothstep(0.2, -0.6, sin(a)), 0.0))
			st.set_uv(Vector2(0.92 - HINGE.x - p.x, a * w * 0.55))
			st.add_vertex(p + side * cos(a) * w + up * sin(a) * h)
	var row := sides + 1
	for i in rows:
		for j in sides:
			var a := i * row + j
			st.add_index(a)
			st.add_index(a + 1)
			st.add_index(a + row)
			st.add_index(a + 1)
			st.add_index(a + row + 1)
			st.add_index(a + row)
	st.generate_normals()
	return st.commit()


## A lower jaw bone on side [param sgn], [param u] of the way from the hinge
## to the chin (jaw space).
static func _mandible(u: float, sgn: float) -> Vector3:
	return Vector3(u * JAW_LEN, 0.06 * u * u, lerpf(0.16, 0.015, pow(u, 1.1)) * sgn)


func think() -> void:
	if state != State.LURK or _cooldown > 0.0:
		return
	var sub := level.player
	if sub == null or not sub.alive:
		return
	var d := sub.pos.distance_to(_rest)
	if d > SENSE_RANGE:
		return
	var noticed := sub.noise_radius > 7.0 or sub.vel.length() > 5.5 or sub.illuminates(pos, radius) or d < 3.5
	if noticed and level.field.line_of_sight(_rest, sub.pos, 0.3):
		alert()
		state = State.WINDUP
		_timer = WINDUP_TIME
		_strike_to = _rest + (sub.pos - _rest).limit_length(REACH)
		Audio.play_at(&"gulper_strike", pos, 2.0)


func behave(delta: float) -> void:
	_t += delta
	_dt = delta
	_cooldown = maxf(_cooldown - delta, 0.0)
	_shy = maxf(_shy - delta, 0.0)
	var out := wall_normal
	var aim := out
	var want := 0.16 + 0.05 * sin(_t * 1.3)
	match state:
		State.LURK:
			# A slow, wandering drift that never quite repeats, and the odd nod;
			# just out of hiding it creeps.
			var side := Vector2(-out.y, out.x)
			var drift := side * (sin(_t * 0.61) * 0.32 + sin(_t * 1.73 + 1.3) * 0.1) + out * sin(_t * 0.43 + 0.7) * 0.18
			pos = pos.lerp(_rest + drift, 1.0 - exp(-lerpf(2.2, 0.6, _shy / 2.5) * delta))
			aim = (pos - _burrow).normalized().rotated(sin(_t * 0.83 + 0.4) * 0.14)
			# Now and then a slow gulp: the jaw sags wide and the pouch fills.
			_gulp_wait -= delta
			if _gulp_wait <= 0.0:
				_gulp = 0.0
				_gulp_wait = 4.0 + 4.0 * fposmod(sin(_t * 12.9898) * 43758.5453, 1.0)
			_gulp = minf(_gulp + delta / 1.6, 1.0)
			want += 0.45 * pow(sin(PI * _gulp), 2.0)
		State.WINDUP:
			# Draws back and down into a coil, jaws clamped, turning to aim.
			_timer -= delta
			var to := (_strike_to - pos).normalized()
			pos = pos.lerp(_rest - to * 0.6 - out * 0.35, 1.0 - exp(-9.0 * delta))
			aim = to
			want = 0.02 + 0.3 * smoothstep(0.6, 1.0, 1.0 - _timer / WINDUP_TIME)
			if _timer <= 0.0:
				state = State.STRIKE
				_timer = STRIKE_TIME
				_strike_from = pos
		State.STRIKE:
			_timer -= delta
			var f := 1.0 - _timer / STRIKE_TIME
			pos = _strike_from.lerp(_strike_to, ease(f, 0.4))
			aim = (_strike_to - _strike_from).normalized()
			# Wide as it closes in; shut on the bite.
			want = sin(minf(f / 0.85, 1.0) * PI * 0.5) if f < 0.88 else 0.03
			if _timer <= 0.0:
				state = State.RETRACT
				_timer = 1.2
				_bite = 1.0
		State.RETRACT:
			_timer -= delta
			pos = pos.lerp(_rest, 1.0 - exp(-2.6 * delta))
			# Still facing its strike, turning back as it settles.
			var struck := (_strike_to - _strike_from).normalized()
			aim = (pos - _burrow).normalized().slerp(struck, clampf((_timer - 0.4) / 0.8, 0.0, 1.0))
			if _timer > 0.95:
				want = 0.03
			if _timer <= 0.0:
				state = State.LURK
				_cooldown = 2.0
		State.HIDE:
			# Snaps back into the hole, and stays there.
			_timer -= delta
			var hole := Vector2(_mouth.x, _mouth.y) if _mouth != Vector3.INF else _burrow
			pos = pos.lerp(hole - out * 0.4, 1.0 - exp(-7.0 * delta))
			want = 0.05
			if _timer <= 0.0:
				state = State.LURK
				_cooldown = 2.0
				_shy = 2.5
	vel = Vector2.ZERO
	# A bite shakes the head.
	_bite = maxf(_bite - delta * 3.0, 0.0)
	aim = aim.rotated(sin(_t * 38.0) * 0.16 * _bite)
	var turn := 16.0 if state == State.WINDUP or state == State.STRIKE else 5.0
	facing = facing.slerp(aim, 1.0 - exp(-turn * delta)).normalized()
	_gape = lerpf(_gape, want, 1.0 - exp(-(30.0 if want < _gape else 12.0) * delta))
	# The body waves with the head's speed, and coils as it winds up.
	var speed := pos.distance_to(_last_pos) / maxf(delta, 0.001)
	_last_pos = pos
	_wiggle = lerpf(_wiggle, clampf(speed / 10.0, 0.0, 1.0), 1.0 - exp(-6.0 * delta))
	_coil = lerpf(_coil, 1.0 if state == State.WINDUP else 0.0, 1.0 - exp(-12.0 * delta))
	_wave += delta * (1.6 + 9.0 * _wiggle + 4.0 * _coil)


func tick(delta: float) -> void:
	super.tick(delta)
	_rebuild_body()


## The head never collides with rock: it is anchored to the burrow.
func move_and_collide_field(_delta: float, _bounce := 0.1) -> Vector2:
	return Vector2.ZERO


func _update_visuals(delta: float) -> void:
	super._update_visuals(delta)
	_jaw.rotation.z = -_gape
	_rebuild_pouch()


## The pouch: loose skin slung between the two jaw bones, a bag under the
## throat even when shut, ballooning as the jaw drops; black outside, the
## inside dark red with a faint glow deep in it.
func _rebuild_pouch() -> void:
	var rot := Basis(Vector3.BACK, -_gape)
	var sag := 0.1 + 0.4 * clampf(_gape / 0.9, 0.0, 1.0)
	var cols := POUCH_COLS + 1
	var grid := PackedVector3Array()
	for k in POUCH_ROWS + 1:
		var u := k / float(POUCH_ROWS)
		var left := _mandible(u, 1.0)
		var right := _mandible(u, -1.0)
		# Deepest a little behind the middle of the jaw, gathered to the
		# hinge and the chin.
		var depth := sag * pow(sin(PI * pow(u, 0.8)), 0.9)
		for j in cols:
			var f := j / float(POUCH_COLS)
			var p := left.lerp(right, f)
			# Inset a touch under the bones so its edge tucks into them.
			p.y -= 0.02 + depth * pow(sin(PI * f), 0.75)
			p.z *= 1.0 + 0.25 * depth * sin(PI * f)
			grid.append(HINGE + rot * p)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in 2:
		# Each face of the skin keeps its own normals (the two share points).
		st.set_smooth_group(side)
		for k in POUCH_ROWS + 1:
			for j in cols:
				var deep := smoothstep(0.1, 0.4, minf(j, POUCH_COLS - j) / float(POUCH_COLS))
				st.set_color(Color(0.0, 0.55, 0.0) if side == 0 else Color(0.07 * deep, 1.0, 0.0))
				st.set_uv(Vector2(0.92 - grid[k * cols + j].x, 0.4 + j / float(POUCH_COLS) * 0.35))
				st.add_vertex(grid[k * cols + j])
		var base := side * (POUCH_ROWS + 1) * cols
		for k in POUCH_ROWS:
			for j in cols - 1:
				var a := base + k * cols + j
				if side == 0:
					st.add_index(a)
					st.add_index(a + cols)
					st.add_index(a + 1)
					st.add_index(a + 1)
					st.add_index(a + cols)
					st.add_index(a + cols + 1)
				else:
					st.add_index(a)
					st.add_index(a + 1)
					st.add_index(a + cols)
					st.add_index(a + 1)
					st.add_index(a + cols + 1)
					st.add_index(a + cols)
	st.generate_normals()
	_pouch_mesh.clear_surfaces()
	st.commit(_pouch_mesh)


func _rebuild_body() -> void:
	if _mouth == Vector3.INF and level and level.field.sample(_rest) < 2.0:
		_dig_burrow()
	# The body ends at the neck's last ring, along the head's own line.
	var head := pos - facing * -NECK_X
	var joint := Vector3(head.x, head.y, 0.0)
	var face := Vector3(facing.x, facing.y, 0.0)
	var start: Vector3
	var out: Vector3
	if _mouth != Vector3.INF:
		start = _mouth - _axis * 2.2
		out = _axis
	else:
		# No rock to burrow in (a specimen shown in open water): it trails away.
		start = joint - Vector3(wall_normal.x, wall_normal.y, 0.0) * 3.0
		out = Vector3(wall_normal.x, wall_normal.y, 0.0)
	# Straight up the burrow (stopping short of the neck when the head sits
	# close by), a smooth curve from the burrow's line to the head's, and the
	# last stretch dead straight along the head's line into the neck.
	var neck := joint - face * 0.45
	var run := clampf((neck - start).dot(out) - 0.4, 0.3, 2.45)
	var lip := start + out * run
	var gap := lip.distance_to(neck)
	# Where the body would lie at rest: a smooth curve from the burrow's line
	# to the head's. Its two inner points follow there with a lag (the one
	# nearer the burrow the slower), so the body bows out behind a lunge and
	# bunches as it is drawn back, and yet is always one smooth curve.
	var rest := [_hermite(lip, out * gap * 0.8, neck, face * gap * 0.8, 1.0 / 3.0),
		_hermite(lip, out * gap * 0.8, neck, face * gap * 0.8, 2.0 / 3.0)]
	if _bends.size() != 2 or _dt <= 0.0:
		_bends = PackedVector3Array(rest)
	else:
		for k in 2:
			var want: Vector3 = rest[k]
			var p := _bends[k].lerp(want, 1.0 - exp(-(8.0 if k == 0 else 12.0) * _dt))
			# Only bowing out to the side: lagging along the body would fold it
			# back on itself.
			var chord := (neck - lip).normalized()
			var off := p - want
			off -= chord * off.dot(chord)
			_bends[k] = want + off.limit_length(gap * 0.3)
	var knots := [lip, _bends[0], _bends[1], neck]
	var target := PackedVector3Array()
	for seg in 3:
		var a: Vector3 = knots[seg]
		var b: Vector3 = knots[seg + 1]
		var span := a.distance_to(b)
		var ta: Vector3 = out * span if seg == 0 else ((b - (knots[seg - 1] as Vector3)) * 0.5)
		var tb: Vector3 = face * span if seg == 2 else (((knots[seg + 2] as Vector3) - a) * 0.5)
		for i in 7:
			target.append(_hermite(a, ta, b, tb, i / 7.0))
	target.append(neck)
	# A wave runs down the body from the head: slow and slight lurking, quick
	# and deeper when it lunges or pulls back, an S when it coils.
	var arc := 0.0
	for i in range(20, 0, -1):
		arc += target[i + 1].distance_to(target[i])
		var t := float(i) / 21.0
		var tangent := (target[i + 1] - target[i - 1]).normalized()
		var side := tangent.cross(Vector3.BACK).normalized()
		var amp := (0.05 + 0.14 * _wiggle + 0.28 * _coil) * clampf(gap / 1.5, 0.3, 1.0)
		target[i] += side * sin(arc * TAU / 2.4 - _wave) * amp * sin(PI * t) * (1.0 - smoothstep(0.7, 1.0, t))
	var pts := PackedVector3Array()
	for i in 5:
		pts.append(start.lerp(lip, i / 5.0))
	pts.append_array(target)
	for i in range(1, 4):
		pts.append(neck.lerp(joint, i / 3.0))
	# Smoothed, so the lagging body bends in curves, never in kinks (the
	# burrow's line and the last stretch into the neck kept as they are).
	for _pass in 4:
		var smooth := pts.duplicate()
		for i in range(4, pts.size() - 4):
			smooth[i] = pts[i] * 0.5 + (pts[i - 1] + pts[i + 1]) * 0.25
		pts = smooth
	# Into the head's own space (where the model will be this frame).
	var to_local := Transform3D(model.basis, Vector3(pos.x, pos.y, 0.0)).affine_inverse()
	for i in pts.size():
		pts[i] = to_local * pts[i]
	_body_tube(pts)


## Builds the eel's skin, body and head in one: the body along
## [param pts] (burrow to neck, in the head's own space) in round, slightly
## squared sections (as BodyKit lofts them), then on without a break through
## the neck and skull; dark above, reddish below, its normals worked out
## across the whole, and a low fin along the body's back with a faint
## glowing seam at its root.
func _body_tube(pts: PackedVector3Array) -> void:
	var n := pts.size()
	# Each section's "back" is carried down the body from the head's, turned
	# only as much as the body bends, so it never flips over in a tight turn.
	var tangents := PackedVector3Array()
	tangents.resize(n)
	for i in n:
		tangents[i] = (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
	tangents[n - 1] = Vector3.RIGHT
	var backs := PackedVector3Array()
	backs.resize(n)
	var carried := Vector3.UP
	for i in range(n - 1, -1, -1):
		var b := carried - tangents[i] * carried.dot(tangents[i])
		carried = b.normalized() if b.length_squared() > 1e-6 else carried
		backs[i] = carried
	pts[n - 1] = Vector3(NECK_X, 0.0, 0.0)
	var grid: Array[PackedVector3Array] = []
	var fin := PackedVector3Array()
	var fin_tip := PackedVector3Array()
	for i in n:
		var t := float(i) / (n - 1)
		var side := tangents[i].cross(backs[i])
		# Thickening a little up the body, easing to the neck's girth.
		var r := lerpf(0.1, 0.118, smoothstep(0.0, 0.8, t))
		r = lerpf(r, NECK_R, smoothstep(0.85, 1.0, t))
		var ring := PackedVector3Array()
		for j in BODY_SIDES + 1:
			var a := TAU * j / BODY_SIDES
			var sc := signf(cos(a)) * pow(absf(cos(a)), 0.85)
			var ss := signf(sin(a)) * pow(absf(sin(a)), 0.85)
			ring.append(pts[i] + backs[i] * sc * r + side * ss * r)
		grid.append(ring)
		var h := 0.09 * sin(PI * clampf((i - 6.0) / 18.0, 0.0, 1.0))
		if _mouth != Vector3.INF:
			# None of it until the body is clear of the burrow's mouth (the
			# mouth and its axis brought into the head's space).
			var to_local := Transform3D(model.basis, Vector3(pos.x, pos.y, 0.0)).affine_inverse()
			h *= smoothstep(0.1, 0.5, (pts[i] - to_local * _mouth).dot(to_local.basis * _axis))
		fin.append(pts[i] + backs[i] * (r * 0.9))
		fin_tip.append(pts[i] + backs[i] * (r + h))
	# On through the neck and skull, which meet the body's last ring.
	if _head_rings.is_empty():
		_head_rings = _loft_head()
	grid.append_array(_head_rings)
	var rings := grid.size()
	# The skin's coordinates: how far back from the snout, and how far round
	# from the back's midline (mirrored on the two flanks, and squeezed, so
	# the wrinkles run round the body like an eel's).
	var along := PackedFloat32Array()
	along.resize(rings)
	for i in range(rings - 1, -1, -1):
		if i >= n:
			along[i] = HEAD[HEAD.size() - 1][0] - grid[i][0].x
		else:
			var next := grid[i + 1][0].lerp(grid[i + 1][BODY_SIDES / 2], 0.5)
			along[i] = along[i + 1] + next.distance_to(grid[i][0].lerp(grid[i][BODY_SIDES / 2], 0.5))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in rings:
		var arcs := PackedFloat32Array([0.0])
		for j in BODY_SIDES:
			arcs.append(arcs[j] + grid[i][j].distance_to(grid[i][j + 1]))
		for j in BODY_SIDES + 1:
			var a := TAU * j / BODY_SIDES
			var ahead := grid[mini(i + 1, rings - 1)][j] - grid[maxi(i - 1, 0)][j]
			var round := grid[i][(j + 1) % BODY_SIDES] - grid[i][(j - 1 + BODY_SIDES) % BODY_SIDES]
			st.set_normal(round.cross(ahead).normalized())
			st.set_color(Color(0.0, smoothstep(0.1, -0.7, cos(a)), 0.0))
			st.set_uv(Vector2(along[i], minf(arcs[j], arcs[BODY_SIDES] - arcs[j]) * 0.55))
			st.add_vertex(grid[i][j])
	var row := BODY_SIDES + 1
	for i in rings - 1:
		for j in BODY_SIDES:
			var a := i * row + j
			for k: int in [a, a + row, a + 1, a + 1, a + row, a + row + 1]:
				st.add_index(k)
	# The fin, both faces, each with its own normals.
	var base := rings * row
	for side in 2:
		for i in n:
			var normal := tangents[i].cross(backs[i]) * (1.0 if side == 0 else -1.0)
			st.set_normal(normal)
			st.set_color(Color(0.015 * smoothstep(0.2, 0.5, float(i) / (n - 1)), 0.1, 0.0))
			st.set_uv(Vector2(along[i], 0.0))
			st.add_vertex(fin[i])
			st.set_normal(normal)
			st.set_color(Color(0.0, 0.1, 1.0))
			st.set_uv(Vector2(along[i], 0.05))
			st.add_vertex(fin_tip[i])
		var b := base + side * n * 2
		for i in n - 1:
			var a := b + i * 2
			var quad := [a, a + 1, a + 2, a + 1, a + 3, a + 2] if side == 0 else [a, a + 2, a + 1, a + 1, a + 2, a + 3]
			for k: int in quad:
				st.add_index(k)
	_body_mesh.clear_surfaces()
	st.commit(_body_mesh)


## A cubic Hermite curve from [param a] (heading [param ta]) to [param b]
## (heading [param tb]), at [param t].
static func _hermite(a: Vector3, ta: Vector3, b: Vector3, tb: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return a * (2.0 * t3 - 3.0 * t2 + 1.0) + ta * (t3 - 2.0 * t2 + t) + b * (-2.0 * t3 + 3.0 * t2) + tb * (t3 - t2)


## The neck and skull, lofted from [constant HEAD] as BodyKit lofts a body,
## less the neck's last ring (the body's).
static func _loft_head() -> Array[PackedVector3Array]:
	var out: Array[PackedVector3Array] = []
	var x1: float = HEAD[HEAD.size() - 1][0]
	for i in range(1, 37):
		var x := lerpf(NECK_X, x1, i / 36.0)
		var hw := BodyKit.at(HEAD, x, 1)
		var top := BodyKit.at(HEAD, x, 2)
		var low := BodyKit.at(HEAD, x, 3)
		var spine := BodyKit.at(HEAD, x, 4)
		var ring := PackedVector3Array()
		for j in BODY_SIDES + 1:
			var a := TAU * j / BODY_SIDES
			var sc := signf(cos(a)) * pow(absf(cos(a)), 0.85)
			var ss := signf(sin(a)) * pow(absf(sin(a)), 0.85)
			ring.append(Vector3(x, spine + sc * (top if cos(a) >= 0.0 else low), ss * hw))
		out.append(ring)
	return out


## Finds where the burrow opens in the rock face behind the eel and builds
## its rim there, on the cave floor's edge at the play plane (the cave rock
## rises towards the camera below it: see terrain.gdshader, so the rim's
## front settles into that face).
func _dig_burrow() -> void:
	var surface := _rest - wall_normal * level.field.sample(_rest)
	var into := surface - wall_normal * 0.1
	# Near the play plane, so the neck rises straight out of it, tipped a
	# little towards the viewer so the dark of the hole shows.
	_mouth = Vector3(into.x, into.y, 0.12)
	_axis = Vector3(wall_normal.x * 3.5, wall_normal.y * 3.5, 1.0).normalized()
	var rim := MeshInstance3D.new()
	# Seeded by where it is: drawing from the level's random stream would
	# change the rest of the world a seed grows.
	var seed_value := int(floorf(_mouth.x * 7.0)) * 92821 + int(floorf(_mouth.y * 7.0))
	rim.mesh = _burrow_mesh(seed_value)
	var rock := ShaderMaterial.new()
	rock.shader = ROCK_SHADER
	rock.set_shader_parameter(&"rock_albedo", TerrainRenderer.ROCK_ALBEDO)
	rock.set_shader_parameter(&"rock_rough", TerrainRenderer.ROCK_ROUGH)
	rock.set_shader_parameter(&"rock_tint", level.biome.rock_tint)
	rock.set_shader_parameter(&"throat_glow", Color(0.07, 0.012, 0.025))
	rim.material_override = rock
	rim.top_level = true
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rim)
	var basis := Basis(Quaternion(Vector3.UP, _axis))
	rim.global_transform = Transform3D(basis, _mouth)
	var bones := MeshInstance3D.new()
	bones.mesh = _prey_bones(seed_value)
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.5, 0.47, 0.42)
	white.roughness = 0.75
	bones.material_override = white
	bones.top_level = true
	bones.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bones)
	bones.global_transform = rim.global_transform


## The burrow's rim, built along +Y (out of the hole): a rough ring of rock
## round a dark throat, its outer slope buried in the cave face.
static func _burrow_mesh(seed_value: int) -> ArrayMesh:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 1.6
	# (radius, height) from the throat's floor (a dark plug, faintly lit by
	# the eel's glow) up its walls, over the lip and down the outer slope
	# into the rock.
	var profile := [Vector2(0.0, -0.32), Vector2(0.2, -0.3), Vector2(0.32, -0.26), Vector2(0.34, -0.12),
		Vector2(0.38, 0.06), Vector2(0.5, 0.17), Vector2(0.66, 0.15), Vector2(0.85, 0.0), Vector2(1.1, -0.4)]
	var shade := [0.0, 0.0, 0.05, 0.25, 0.7, 1.0, 1.0, 1.0, 1.0]
	var sides := 28
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in profile.size():
		var pr: Vector2 = profile[i]
		for j in sides + 1:
			var a := TAU * j / sides
			var bump := noise.get_noise_2d(cos(a) * 2.0, sin(a) * 2.0 + i * 0.7) * 0.18 * (1.0 if i > 1 else 0.3)
			var r := pr.x * (1.0 + bump)
			var sh := float(shade[i])
			st.set_color(Color(sh, sh, sh, minf(sh * 4.0, 1.0)))
			st.add_vertex(Vector3(cos(a) * r, pr.y + bump * 0.5, sin(a) * r))
	var row := sides + 1
	for i in profile.size() - 1:
		for j in sides:
			var a := i * row + j
			st.add_index(a)
			st.add_index(a + row)
			st.add_index(a + 1)
			st.add_index(a + 1)
			st.add_index(a + row)
			st.add_index(a + row + 1)
	st.generate_normals()
	return st.commit()


## A few pale bones of the eel's last meals, strewn on its rim.
static func _prey_bones(seed_value: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var bones := []
	for k in 4:
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.55, 0.8)
		var bone := ArrayMesh.new()
		var l := rng.randf_range(0.05, 0.1)
		MeshKit.tube(bone, PackedVector3Array([Vector3(-l, 0, 0), Vector3(0, 0.01, 0), Vector3(l, 0, 0)]),
			PackedFloat32Array([0.011, 0.006, 0.011]), 5)
		bones.append([bone, Transform3D(Basis(Vector3.UP, rng.randf() * TAU),
			Vector3(cos(a) * r, 0.17 - maxf(r - 0.6, 0.0) * 0.8, sin(a) * r))])
	return MeshKit.merge(bones)


func on_touch_player(sub: Submarine) -> void:
	sub.take_damage(contact_damage if state == State.STRIKE else 6.0, pos, self)
	if state == State.STRIKE:
		state = State.RETRACT
		_timer = 1.2


func on_damaged(_amount: float, _from: Vector2) -> void:
	state = State.HIDE
	_timer = 4.0
