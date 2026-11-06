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
const WINDUP_TIME := 0.25
const SENSE_RANGE := 10.0
## Model space: the head, x from where the body joins it to the snout.
## Stations as in [method BodyKit.body].
## The back of the skull runs down into a neck, round and as thick as the
## body, whose last ring the body meets edge to edge (see [method _body_tube]).
const HEAD := [[-1.05, NECK_R, NECK_R, NECK_R, 0.0], [-0.85, 0.125, 0.13, 0.12, 0.0],
	[-0.62, 0.16, 0.165, 0.1, 0.01], [-0.4, 0.18, 0.17, 0.06, 0.02], [-0.1, 0.13, 0.12, 0.04, 0.04],
	[0.3, 0.08, 0.07, 0.03, 0.045], [0.7, 0.045, 0.045, 0.02, 0.045], [0.92, 0.012, 0.016, 0.01, 0.04]]
## The jaw's hinge, inside the back of the skull: the jaw bones grow out of
## the head's underside and swing down from within it.
const HINGE := Vector3(-0.5, -0.02, 0.0)
const NECK_X := -1.05
const NECK_R := 0.115
## Sides round the body, as round the head (BodyKit.body), so the two meet
## vertex to vertex.
const BODY_SIDES := 16
const JAW_LEN := 1.4
## How far along the jaw (0 hinge .. 1 chin) the corner of the mouth lies:
## behind it, cheek skin joins the upper jaw to the lower.
const CORNER_U := 0.26
## Sections down the jaw and points across each, for the pouch.
const POUCH_ROWS := 20
const POUCH_COLS := 12
const ROCK_SHADER := preload("res://src/fx/shaders/burrow_rock.gdshader")
## The body is drawn in sections this far apart (metres).
const LINK := 0.2
## How far behind the head the body runs straight along the head's line.
const NECK_RUN := 0.4
## How far behind the head the body begins: the neck.
const NECK_BACK := -NECK_X + NECK_RUN
## How far into the burrow the body is drawn (beyond that it is out of sight).
const SHOWN_DEPTH := 1.6

## Wrinkled skin, shared by every gulper (see _skin()).
static var _skin_tex: NoiseTexture2D

var wall_normal := Vector2.UP
var state := State.LURK
## The body as last drawn (world space, burrow to neck), for checking.
var drawn := PackedVector3Array()
var _burrow := Vector2.ZERO
var _rest := Vector2.ZERO
var _strike_from := Vector2.ZERO
var _strike_to := Vector2.ZERO
## Which way it faced as it began to coil.
var _coil_from := Vector2.UP
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
## The body's sideways bow (metres at its middle) and how fast it is
## swinging: thrown out by the head's sideways acceleration, it swings back
## and settles like a spring; and the head's velocity a step ago.
var _bow := 0.0
var _bow_v := 0.0
var _last_vel := Vector2.ZERO
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
	# Needle teeth along the upper jaw.
	for sgn: float in [1.0, -1.0]:
		for t: Array in BodyKit.teeth_row(_upper_lip(-0.12, sgn) - Vector3(0.0, 0.0, 0.025 * sgn),
				_upper_lip(0.84, sgn) - Vector3(0.0, 0.0, 0.01 * sgn), 14, 0.06, Vector3(0.0, -1.0, -0.15 * sgn),
				3 if sgn > 0.0 else 4, false):
			parts.append([BodyKit.enamel(t[0]), t[1]])
	_head = add_visual(BodyKit.merged(parts), mat)
	# The lower jaw: two long, thin, blade-like jaw bones under the skin,
	# needle teeth along them.
	var jaw_parts := []
	for sgn: float in [1.0, -1.0]:
		jaw_parts.append([_jaw_blade(sgn)])
		for t: Array in BodyKit.teeth_row(_mandible(0.3, sgn) + Vector3(0.0, 0.02, -0.005 * sgn),
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
		# Growing out of the skull at the hinge, drawn to a point at the chin.
		var grow := (0.55 + 0.45 * smoothstep(0.0, 0.15, u)) * (1.0 - 0.85 * smoothstep(0.9, 1.0, u))
		var w := lerpf(0.02, 0.006, u) * grow + 0.002
		var h := lerpf(0.05, 0.012, u) * grow + 0.002
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
	# The joint at the hinge: a rounded knob, so the bone has no open end.
	var knob := MeshKit.ball(1.0, 0.0, 10, 6)
	st.append_from(knob, 0, Transform3D(Basis().scaled(Vector3(0.035, 0.03, 0.016)), _mandible(0.0, sgn)))
	st.generate_normals()
	return st.commit()


## A lower jaw bone on side [param sgn], [param u] of the way from the hinge
## to the chin (jaw space).
static func _mandible(u: float, sgn: float) -> Vector3:
	return Vector3(u * JAW_LEN, 0.05 * u * u, lerpf(0.13, 0.015, pow(u, 1.1)) * sgn)


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
		_strike_from = pos
		_coil_from = facing
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
			var drift := side * (sin(_t * 0.47) * 0.24 + sin(_t * 1.31 + 1.3) * 0.06) + out * sin(_t * 0.37 + 0.7) * 0.12
			pos = pos.lerp(_rest + drift, 1.0 - exp(-lerpf(1.8, 0.6, _shy / 2.5) * delta))
			aim = (pos - _burrow).normalized().rotated(sin(_t * 0.71 + 0.4) * 0.1)
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
			var to := (_strike_to - _rest).normalized()
			var w := 1.0 - _timer / WINDUP_TIME
			# Low and turned to its mark: striking straight out it sinks back
			# into the hole; striking aside it swings round, its neck kept out
			# ahead of the hole that way so the body behind bends, never folds.
			var turn_by := acos(clampf(to.dot(out), -1.0, 1.0))
			var rise := lerpf(-0.5, 0.9, smoothstep(0.0, 1.6, turn_by))
			var ahead := 0.2 + 0.9 * smoothstep(0.4, 2.0, turn_by)
			var coil := _hole() + out * rise + to * (ahead + NECK_BACK)
			# It turns as it moves, the two together, so the neck never swings
			# behind the hole on the way.
			var e := smoothstep(0.0, 1.0, w)
			pos = _strike_from.lerp(coil, e)
			aim = _coil_from.slerp(to, e)
			want = 0.02 + 0.35 * smoothstep(0.75, 1.0, w)
			if _timer <= 0.0:
				state = State.STRIKE
				_timer = STRIKE_TIME
				_strike_from = pos
		State.STRIKE:
			_timer -= delta
			var f := clampf(1.0 - _timer / STRIKE_TIME, 0.0, 1.0)
			# Out like a spring, a hair past the mark, settling onto it.
			var g := f - 1.0
			pos = _strike_from.lerp(_strike_to, 1.0 + 1.5 * g * g * g + 0.5 * g * g)
			aim = (_strike_to - _strike_from).normalized()
			# Wide as it closes in; shut on the bite.
			want = sin(minf(f / 0.85, 1.0) * PI * 0.5) if f < 0.88 else 0.03
			if _timer <= 0.0:
				state = State.RETRACT
				_timer = 1.2
				_bite = 1.0
		State.RETRACT:
			_timer -= delta
			# A quick recoil, then drawn slowly home.
			pos = pos.lerp(_rest, 1.0 - exp(-(6.0 if _timer > 0.9 else 2.2) * delta))
			# Still facing its strike, turning back to face out of its hole as it
			# nears home.
			var struck := (_strike_to - _strike_from).normalized()
			var home := (pos - _burrow).normalized()
			aim = home.slerp(struck, smoothstep(1.2, 4.5, pos.distance_to(_rest)) * clampf(_timer / 0.6, 0.0, 1.0))
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
	aim = aim.rotated(sin(_t * 30.0) * 0.09 * _bite)
	# Coiling and drawing back it turns as fast as it moves (its aim is set
	# to match), striking a little slower, lurking lazily.
	var turn := 5.0
	if state == State.WINDUP or state == State.RETRACT:
		turn = 40.0
	elif state == State.STRIKE:
		turn = 16.0
	facing = facing.slerp(aim, 1.0 - exp(-turn * delta)).normalized()
	_gape = lerpf(_gape, want, 1.0 - exp(-(30.0 if want < _gape else 12.0) * delta))
	# The body waves with the head's speed, and coils as it winds up.
	var head_vel := (pos - _last_pos) / maxf(delta, 0.001)
	var speed := head_vel.length()
	_last_pos = pos
	# The bow: the head's acceleration across the body throws the middle of
	# the body the other way; a spring, a little under-damped, brings it back.
	var root := Vector2(_mouth.x, _mouth.y) if _mouth != Vector3.INF else _burrow
	var chord := (pos - root).normalized() if pos.distance_to(root) > 0.1 else wall_normal
	var across := Vector2(-chord.y, chord.x)
	var accel := (head_vel - _last_vel) / maxf(delta, 0.001)
	_last_vel = head_vel
	# (+_bow lies to the right of the line from the burrow to the head.)
	_bow_v += (-70.0 * _bow - 9.0 * _bow_v + clampf(accel.dot(across), -400.0, 400.0) * 0.006) * delta
	_bow += _bow_v * delta
	var span := pos.distance_to(root)
	_bow = clampf(_bow, -0.14 * span, 0.14 * span)
	_wiggle = lerpf(_wiggle, clampf(speed / 10.0, 0.0, 1.0), 1.0 - exp(-6.0 * delta))
	_coil = lerpf(_coil, 1.0 if state == State.WINDUP else 0.0, 1.0 - exp(-12.0 * delta))
	_wave += delta * (1.4 + 5.0 * _wiggle + 3.0 * _coil)


func tick(delta: float) -> void:
	super.tick(delta)
	_rebuild_body()


## Where the burrow opens, on the play plane.
func _hole() -> Vector2:
	return Vector2(_mouth.x, _mouth.y) if _mouth != Vector3.INF else _burrow + wall_normal * 1.2


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
				st.set_color(Color(0.0, 0.55, 0.0) if side == 0 else Color(0.02 * deep, 1.0, 0.0))
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
	_cheeks(st, rot, (POUCH_ROWS + 1) * cols * 2)
	st.generate_normals()
	_pouch_mesh.clear_surfaces()
	st.commit(_pouch_mesh)


## The corners of the mouth: on each side, skin from the upper jaw's edge
## down to the jaw bone, from the hinge forward to [constant CORNER_U],
## stretching into a web as the jaw drops and bellying out a little.
## Appended to [param st] from vertex [param base], with the jaw turned by
## [param rot].
func _cheeks(st: SurfaceTool, rot: Basis, base: int) -> void:
	var rows := 8
	var cols := 5
	var at := base
	for sgn: float in [1.0, -1.0]:
		var grid := PackedVector3Array()
		for k in rows + 1:
			var t := k / float(rows)
			for j in cols + 1:
				var f := j / float(cols)
				# The free edge curves back between the jaws, like the corner of
				# a mouth, rather than running straight across.
				var u := CORNER_U * t * (1.0 - 0.45 * sin(PI * f) * t)
				var bone := HINGE + rot * (_mandible(u, sgn) + Vector3(0.0, 0.01, 0.008 * sgn))
				var lip := _upper_lip(HINGE.x + u * JAW_LEN, sgn)
				var p := lip.lerp(bone, f)
				p.z += sgn * sin(PI * f) * (0.01 + 0.04 * _gape) * sin(PI * 0.5 * t)
				grid.append(p)
		for side in 2:
			st.set_smooth_group(10 + side)
			for k in rows + 1:
				for j in cols + 1:
					var g := grid[k * (cols + 1) + j]
					st.set_color(Color(0.0, lerpf(0.2, 0.6, j / float(cols)), 0.0) if side == 0
						else Color(0.0, 1.0, 0.0))
					st.set_uv(Vector2(0.92 - g.x, 0.3 + j * 0.02))
					st.add_vertex(g)
			var start := at + side * (rows + 1) * (cols + 1)
			var outward := (side == 0) != (sgn > 0.0)
			for k in rows:
				for j in cols:
					var a := start + k * (cols + 1) + j
					var quad := [a, a + 1, a + cols + 1, a + 1, a + cols + 2, a + cols + 1] if outward \
						else [a, a + cols + 1, a + 1, a + 1, a + cols + 1, a + cols + 2]
					for i: int in quad:
						st.add_index(i)
		at += (rows + 1) * (cols + 1) * 2


func _rebuild_body() -> void:
	if _mouth == Vector3.INF and level and level.field.sample(_rest) < 2.0:
		_dig_burrow()
	var face := Vector3(facing.x, facing.y, 0.0)
	# The neck: where the body meets the head, on the head's own line; the
	# body runs straight back along that line a little way.
	var joint := Vector3(pos.x, pos.y, 0.0) + face * NECK_X
	var neck := joint - face * NECK_RUN
	var root: Vector3
	var out: Vector3
	var pts := PackedVector3Array()
	if _mouth != Vector3.INF:
		out = _axis
		# The curve starts at the mouth, or deeper down the burrow when the
		# neck sits close by or off to the side, so it always runs forwards
		# and has room to swing across.
		var rel := neck - _mouth
		var depth := rel.dot(out)
		var lateral := (rel - out * depth).length()
		root = _mouth + out * minf(0.0, depth - maxf(1.0, 2.2 * lateral))
		# Up the burrow to there.
		var steps := int(SHOWN_DEPTH / LINK)
		for i in steps:
			pts.append(root - out * (SHOWN_DEPTH - i * LINK))
	else:
		# No rock to burrow in (a specimen shown in open water): it trails away.
		out = Vector3(wall_normal.x, wall_normal.y, 0.0)
		root = neck - out * 3.0
	# From the mouth to the neck, one smooth curve: it leaves the hole along
	# the burrow's line and meets the neck along the head's, so there is
	# nothing to kink. Sampled evenly along its length.
	var gap := root.distance_to(neck)
	var c1 := root + out * gap * 0.42
	var c2 := neck - face * gap * 0.42
	var dense := PackedVector3Array()
	var lengths := PackedFloat32Array([0.0])
	for i in 97:
		var t := i / 96.0
		var a := 1.0 - t
		dense.append(root * a * a * a + c1 * 3.0 * a * a * t + c2 * 3.0 * a * t * t + neck * t * t * t)
		if i > 0:
			lengths.append(lengths[i - 1] + dense[i].distance_to(dense[i - 1]))
	var total := lengths[96]
	var count := maxi(int(ceil(total / LINK)), 2)
	var k := 0
	var curve := PackedVector3Array()
	for i in count + 1:
		var want := total * i / count
		while k < 95 and lengths[k + 1] < want:
			k += 1
		var f := (want - lengths[k]) / maxf(lengths[k + 1] - lengths[k], 1e-5)
		curve.append(dense[k].lerp(dense[k + 1], clampf(f, 0.0, 1.0)))
	# The bow and a slow muscle wave running down from the head, both smooth
	# across the whole curve and gone at its ends; drawn taut, the body runs
	# nearly straight.
	var slack := 1.0 - 0.8 * smoothstep(3.0, 7.0, gap)
	var amp := (0.035 + 0.06 * _wiggle + 0.12 * _coil) * clampf(gap / 2.5, 0.2, 1.0) * slack
	var bow := clampf(_bow, -0.12 * gap, 0.12 * gap)
	var offsets := PackedFloat32Array()
	offsets.resize(count + 1)
	for i in range(1, count):
		var t := float(i) / count
		var from_head := (1.0 - t) * total
		# Both shapes fall to nothing, and level out, at the burrow and the
		# neck, so the body still leaves the one and meets the other square.
		var hump := 16.0 * t * t * (1.0 - t) * (1.0 - t)
		var wave := sin(from_head * TAU / 2.8 - _wave) * amp * smoothstep(0.0, 0.3, t) * smoothstep(0.0, 1.2, from_head)
		offsets[i] = bow * hump + wave
	for i in range(1, count):
		var tangent := (curve[i + 1] - curve[i - 1]).normalized()
		curve[i] += tangent.cross(Vector3.BACK).normalized() * offsets[i]
	pts.append_array(curve)
	for i in range(1, 3):
		pts.append(neck.lerp(joint, i / 2.0))
	drawn = pts.duplicate()
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
		# How far back from the neck (near enough).
		var back_by := (n - 1 - i) * LINK
		var side := tangents[i].cross(backs[i])
		# Slimming a little down the body from the neck's girth.
		var r := lerpf(NECK_R, 0.1, smoothstep(0.3, 6.0, back_by))
		var ring := PackedVector3Array()
		for j in BODY_SIDES + 1:
			var a := TAU * j / BODY_SIDES
			var sc := signf(cos(a)) * pow(absf(cos(a)), 0.85)
			var ss := signf(sin(a)) * pow(absf(sin(a)), 0.85)
			ring.append(pts[i] + backs[i] * sc * r + side * ss * r)
		grid.append(ring)
		var h := 0.09 * smoothstep(0.4, 1.2, back_by) * (1.0 - smoothstep(4.0, 7.0, back_by))
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
