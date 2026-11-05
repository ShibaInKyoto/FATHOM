class_name Gulper
extends Creature
## Gulper eel living in a wall burrow. It feels vibrations: subs that pass
## fast, loud or with a lamp in its face get struck by a lunge from the rock.
## The entity position is the head; the body runs back into the burrow.
## A real gulper's head: a slender upper jaw with pin eyes at its tip over a
## pair of long thin jaw bones holding a vast black pouch. Lurking, the
## mouth hangs a little open, breathing, its lips aglow; striking, the jaws
## drop wide and the pouch balloons, then snap shut. The burrow is a rocky
## rim in the cave face, dark inside, prey bones strewn on it, and the body
## arcs out of it, swaying.

enum State { LURK, STRIKE, RETRACT, HIDE }

const REACH := 9.5
const STRIKE_TIME := 0.32
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
		m.set_shader_parameter(&"back_color", Color(0.085, 0.08, 0.095))
		m.set_shader_parameter(&"belly_color", Color(0.2, 0.1, 0.11))
		m.set_shader_parameter(&"glow_color", Color(1.0, 0.3, 0.45))
		m.set_shader_parameter(&"glow_strength", 2.5)
		m.set_shader_parameter(&"glow_pulse", 0.4)
		# Velvet, not plastic: matte skin with a soft sheen where it turns
		# away, finely pitted.
		m.set_shader_parameter(&"roughness", 0.58)
		m.set_shader_parameter(&"metallic", 0.0)
		m.set_shader_parameter(&"rim_strength", 0.4)
		m.set_shader_parameter(&"skin_pits", 0.006)
		m.set_shader_parameter(&"body_length", 1.6)
		m.set_shader_parameter(&"swim_amp", 0.0)
		m.set_shader_parameter(&"flutter_amp", 0.03)
		m.set_shader_parameter(&"flutter_freq", 6.0)
		m.set_shader_parameter(&"flutter_wave", 4.0)
		m.set_shader_parameter(&"tooth_color", Color(0.82, 0.78, 0.72)))
	var parts := [[BodyKit.body(HEAD, 36, BODY_SIDES)]]
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
			st.set_uv(Vector2(p.x, 0.0))
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
		state = State.STRIKE
		_timer = STRIKE_TIME
		_strike_from = pos
		_strike_to = _rest + (sub.pos - _rest).limit_length(REACH)
		Audio.play_at(&"gulper_strike", pos, 2.0)


func behave(delta: float) -> void:
	_t += delta
	_cooldown = maxf(_cooldown - delta, 0.0)
	match state:
		State.LURK:
			var sway := Vector2(-wall_normal.y, wall_normal.x) * sin(_t * 0.9) * 0.5
			pos = pos.lerp(_rest + sway, 1.0 - exp(-3.0 * delta))
		State.STRIKE:
			_timer -= delta
			var f := 1.0 - _timer / STRIKE_TIME
			pos = _strike_from.lerp(_strike_to, ease(f, 0.4))
			if _timer <= 0.0:
				state = State.RETRACT
				_timer = 1.2
		State.RETRACT, State.HIDE:
			_timer -= delta
			var target := _rest if state == State.RETRACT else _burrow
			pos = pos.lerp(target, 1.0 - exp(-3.0 * delta))
			if _timer <= 0.0:
				state = State.LURK
				_cooldown = 2.0
	vel = Vector2.ZERO
	# The mouth hangs open, breathing, the dark of the pouch showing;
	# striking, it drops wide and snaps shut at the end of the lunge.
	var want := 0.16 + 0.05 * sin(_t * 1.3)
	if state == State.STRIKE:
		var f := 1.0 - _timer / STRIKE_TIME
		want = 1.0 * sin(minf(f / 0.75, 1.0) * PI * 0.5) if f < 0.8 else 0.1
	_gape = lerpf(_gape, want, 1.0 - exp(-(22.0 if want < _gape else 14.0) * delta))
	var to_head := pos - _burrow
	facing = to_head.normalized() if to_head.length() > 0.1 else wall_normal


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
				st.set_uv(Vector2(grid[k * cols + j].x, 0.0))
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
	# The last stretch runs dead straight along the head's line into the
	# neck, so the body enters it square; before that, a smooth curve from
	# the burrow's line to the head's, and before that, straight up the
	# burrow (stopping short of the neck when the head sits close by).
	var neck := joint - face * 0.45
	var run := clampf((neck - start).dot(out) - 0.4, 0.3, 2.45)
	var lip := start + out * run
	var pts := PackedVector3Array()
	for i in 5:
		pts.append(start.lerp(lip, i / 5.0))
	var gap := lip.distance_to(neck)
	var t0 := out * gap * 0.8
	var t1 := face * gap * 0.8
	for i in 22:
		var t := float(i) / 21.0
		var t2 := t * t
		var t3 := t2 * t
		pts.append(lip * (2.0 * t3 - 3.0 * t2 + 1.0) + t0 * (t3 - 2.0 * t2 + t) + neck * (-2.0 * t3 + 3.0 * t2)
			+ t1 * (t3 - t2))
	for i in range(1, 4):
		pts.append(neck.lerp(joint, i / 3.0))
	var n := pts.size()
	# A slow sway runs up the body from the burrow: little when only a short
	# neck is out, less again when stretched out in a strike; none on the
	# last stretch into the head.
	var stretch := clampf(gap / 5.0, 0.0, 1.0)
	var sway := 0.22 * clampf((gap - 0.8) / 2.5, 0.12, 1.0) * (1.0 - stretch * 0.7)
	for i in range(6, 26):
		var t := float(i - 5) / 21.0
		var tangent := (pts[i + 1] - pts[i - 1]).normalized()
		var side := tangent.cross(Vector3.BACK).normalized()
		pts[i] += side * sin(t * TAU * 1.1 - _t * 2.6) * sway * sin(t * PI) * (1.0 - smoothstep(0.6, 0.95, t))
	# Into the head's own space (where the model will be this frame).
	var to_local := Transform3D(model.basis, Vector3(pos.x, pos.y, 0.0)).affine_inverse()
	for i in pts.size():
		pts[i] = to_local * pts[i]
	_body_tube(pts)


## Builds the body along [param pts] (burrow to neck, in the head's own
## space): dark above, reddish below, and a low fin along the back with a
## faint glowing seam at its root. Its sections are the neck's (round,
## slightly squared, as BodyKit lofts them), its last one the neck's last
## ring exactly, its colors and normals worked out the same way, so head
## and body read as one skin.
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
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n:
		for j in BODY_SIDES + 1:
			var a := TAU * j / BODY_SIDES
			var along := grid[mini(i + 1, n - 1)][j] - grid[maxi(i - 1, 0)][j]
			var round := grid[i][(j + 1) % BODY_SIDES] - grid[i][(j - 1 + BODY_SIDES) % BODY_SIDES]
			st.set_normal(round.cross(along).normalized())
			st.set_color(Color(0.0, smoothstep(0.1, -0.7, cos(a)), 0.0))
			st.set_uv(Vector2(grid[i][j].x, 0.0))
			st.add_vertex(grid[i][j])
	var row := BODY_SIDES + 1
	for i in n - 1:
		for j in BODY_SIDES:
			var a := i * row + j
			for k: int in [a, a + row, a + 1, a + 1, a + row, a + row + 1]:
				st.add_index(k)
	# The fin, both faces, each with its own normals.
	var base := n * row
	for side in 2:
		for i in n:
			var normal := tangents[i].cross(backs[i]) * (1.0 if side == 0 else -1.0)
			st.set_normal(normal)
			st.set_color(Color(0.06 * smoothstep(0.2, 0.5, float(i) / (n - 1)), 0.1, 0.0))
			st.set_uv(Vector2(fin[i].x, 0.0))
			st.add_vertex(fin[i])
			st.set_normal(normal)
			st.set_color(Color(0.0, 0.1, 1.0))
			st.set_uv(Vector2(fin_tip[i].x, 0.0))
			st.add_vertex(fin_tip[i])
		var b := base + side * n * 2
		for i in n - 1:
			var a := b + i * 2
			var quad := [a, a + 1, a + 2, a + 1, a + 3, a + 2] if side == 0 else [a, a + 2, a + 1, a + 1, a + 2, a + 3]
			for k: int in quad:
				st.add_index(k)
	_body_mesh.clear_surfaces()
	st.commit(_body_mesh)


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
