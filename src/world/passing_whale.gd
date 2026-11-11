class_name PassingWhale
extends Entity
## In the second Sunlit Shelf zone a sperm whale passes through the open
## water behind the playfield, sixteen metres of it, on slow beats of its
## flukes. It does not see the sub as anything worth a look. Its clicks reach
## the sub's sonar: every few seconds the cave around it shows up on the
## chart as if pinged, without a sound a hunter would follow. The reef below
## is where whales come to rest (see [WhaleFall]).
## Built as the animal is: the great box of a head, a third of its length,
## blunt in front and overhanging a narrow, toothed lower jaw slung beneath
## it; a small eye at the corner of the mouth; short paddle flippers; a low
## hump on the back and a row of knuckles along the tail stock to broad,
## notched flukes. Its skin is painted all round it (tools/art/whale_skin.py):
## dark and wrinkled like a prune behind the head, the head itself paler and
## scarred white by the beaks and suckers of squid, the lips white, the
## blowhole an S at the front of the head, on its left. It swims on slow,
## deep strokes of its flukes, the body flexing up and down along its length
## while the head barely moves; now and then its jaw hangs open a little.

enum State { WAITING, PASSING, GONE }

const ZONE := 1
## How far behind the playfield it swims (in front of the cave's back wall).
const DEPTH := -4.5
const LENGTH := 16.0
const SPEED := 1.7
## Open water it needs along its way (a little less will do if a zone has
## nothing roomier), and how far its way must run.
const CLEARANCE := 3.0
const TIGHT_CLEARANCE := 2.6
const MIN_RUN := 24.0
## How close the sub comes before it appears, and before it is witnessed.
const TRIGGER_RANGE := 50.0
const WITNESS_RANGE := 16.0
const CLICK_PING_RANGE := 34.0
const CLICK_PING_EVERY := 3.0
const FADE := 3.0
const RESEARCH := 5
const SHADER := preload("res://src/fx/shaders/creature_fade.gdshader")
const SKIN_MAP := preload("res://assets/creatures/whale_skin.png")
## Body sections from the tail to the snout: [x, half width, height above
## the spine, depth below it, spine height, squareness (2 round, more boxy)].
const STATIONS := [[-8.0, 0.05, 0.1, 0.1, 0.05, 2.0], [-7.7, 0.15, 0.36, 0.32, 0.05, 2.2],
	[-6.8, 0.3, 0.58, 0.52, 0.05, 2.3], [-5.4, 0.56, 0.86, 0.8, 0.05, 2.3], [-3.6, 0.94, 1.16, 1.1, 0.04, 2.3],
	[-1.2, 1.28, 1.4, 1.38, 0.0, 2.4], [1.4, 1.42, 1.52, 1.48, 0.0, 2.6], [3.8, 1.4, 1.58, 1.4, 0.04, 3.0],
	[6.2, 1.32, 1.6, 1.28, 0.08, 3.4], [7.35, 1.22, 1.56, 1.15, 0.1, 3.6], [7.8, 1.02, 1.38, 0.95, 0.1, 3.2],
	[8.0, 0.5, 0.75, 0.5, 0.1, 2.4]]
## The low hump on the back, and the knuckles behind it down the tail stock
## (x, height, width).
const RIDGE := [Vector3(-3.3, 0.36, 0.6), Vector3(-4.6, 0.15, 0.2), Vector3(-5.25, 0.12, 0.18),
	Vector3(-5.85, 0.1, 0.17), Vector3(-6.4, 0.075, 0.15), Vector3(-6.9, 0.05, 0.13)]
## The lower jaw's hinge, its length, and where the eye and flippers sit.
const JAW_HINGE := Vector3(2.5, -1.3, 0.0)
const JAW_L := 4.8
const EYE_X := 2.95
const FLIPPER_X := 2.0
## Seconds a beat of the flukes takes.
const STROKE := 4.0
## UV2.y for parts the skin is not painted over (see creature.gdshader).
const UNPAINTED := 999.0

static var _material: ShaderMaterial
## Behind the title the scene is lit brighter: less light from above.
static var _backdrop_material: ShaderMaterial
static var _body_mesh: ArrayMesh
static var _jaw_mesh: ArrayMesh

var state := State.WAITING
## The stretch of open water it swims along (left to right).
var from := Vector2.ZERO
var to := Vector2.ZERO
var heading := 1.0
var witnessed := false
## Behind the title screen: it passes again and again, and is never witnessed.
var backdrop := false
var _x := 0.0
var _t := 0.0
var _click_in := 0.5
var _ping_in := 1.5
var _rest := 4.0
var _rng := RandomNumberGenerator.new()
var _rig: Node3D
var _body: MeshInstance3D
var _jaw: MeshInstance3D
var _fade := 0.0
var _gape := 0.0
var _gape_in := 6.0


## A level stretch of open water through [param p] (along the row
## [param rise] metres above it), as [from, to], or [] if it is too short.
static func stretch_through(field: TerrainField, p: Vector2, rise: float) -> Array[Vector2]:
	var y := p.y + rise
	if field.sample(Vector2(p.x, y)) <= CLEARANCE:
		return []
	var a := p.x
	while a > p.x - 40.0 and field.sample(Vector2(a - 1.0, y)) > CLEARANCE:
		a -= 1.0
	var b := p.x
	while b < p.x + 40.0 and field.sample(Vector2(b + 1.0, y)) > CLEARANCE:
		b += 1.0
	if b - a < MIN_RUN:
		return []
	return [Vector2(a, y), Vector2(b, y)]


## Finds the longest level stretch of open water in the zone, at least
## [constant MIN_RUN] long; returns the whale waiting there, or null.
static func place(level: Level) -> PassingWhale:
	for clearance in [CLEARANCE, TIGHT_CLEARANCE]:
		var whale := _place_with(level, clearance)
		if whale:
			return whale
	return null


static func _place_with(level: Level, clearance: float) -> PassingWhale:
	var field := level.field
	var size := level.layout.size()
	var best_len := 0.0
	var best_a := Vector2.ZERO
	var best_b := Vector2.ZERO
	var y := -8.0
	while y > -(size.y - 8.0):
		var run_start := -1.0
		var x := 4.0
		while x < size.x - 4.0:
			var open := field.sample(Vector2(x, y)) > clearance
			if open and run_start < 0.0:
				run_start = x
			if (not open or x + 1.0 >= size.x - 4.0) and run_start >= 0.0:
				# The run ends at the last open sample.
				var end_x := x if open else x - 1.0
				if end_x - run_start > best_len:
					best_len = end_x - run_start
					best_a = Vector2(run_start, y)
					best_b = Vector2(end_x, y)
				run_start = -1.0
			x += 1.0
		y -= 2.0
	if best_len < MIN_RUN:
		return null
	var whale := PassingWhale.new()
	whale.from = best_a
	whale.to = best_b
	whale.pos = (best_a + best_b) * 0.5
	level.add_entity(whale)
	return whale


func setup() -> void:
	radius = 0.0
	active_radius = 1.0e6
	_rng.seed = hash(from)
	_rig = Node3D.new()
	_rig.top_level = true
	_rig.visible = false
	add_child(_rig)
	_build()


func _build() -> void:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
		_configure(_material)
		_backdrop_material = _material.duplicate()
		_backdrop_material.set_shader_parameter(&"sky_light", 0.15)
		_body_mesh = _body_parts()
		_jaw_mesh = _jaw_parts()
	_body = MeshInstance3D.new()
	_body.mesh = _body_mesh
	var mat := _backdrop_material if backdrop else _material
	_body.material_override = mat
	_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rig.add_child(_body)
	_jaw = MeshInstance3D.new()
	_jaw.mesh = _jaw_mesh
	_jaw.material_override = mat
	_jaw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_jaw.position = JAW_HINGE
	_jaw.set_instance_shader_parameter(&"body_offset", JAW_HINGE)
	_rig.add_child(_jaw)
	_pose(0.0)


static func _configure(m: ShaderMaterial) -> void:
	m.set_shader_parameter(&"back_color", Color(0.26, 0.25, 0.24))
	m.set_shader_parameter(&"belly_color", Color(0.8, 0.79, 0.76))
	m.set_shader_parameter(&"glow_strength", 0.0)
	m.set_shader_parameter(&"rim_strength", 0.65)
	# Lit from the sunlit water above, so it shows against the dark rock.
	m.set_shader_parameter(&"sky_light", 1.6)
	m.set_shader_parameter(&"roughness", 0.62)
	m.set_shader_parameter(&"metallic", 0.0)
	m.set_shader_parameter(&"tooth_color", Color(0.86, 0.83, 0.74))
	m.set_shader_parameter(&"mottle", 0.25)
	m.set_shader_parameter(&"paint_top", SKIN_MAP)
	m.set_shader_parameter(&"paint_box", Vector4(-LENGTH * 0.5, -1.0, LENGTH, 2.0))
	m.set_shader_parameter(&"paint_wrap", true)
	m.set_shader_parameter(&"paint_relief", 0.012)
	# Up and down: a slow wave down the body, growing to the flukes, the
	# great head all but still.
	m.set_shader_parameter(&"body_length", LENGTH)
	m.set_shader_parameter(&"swim_amp", 1.0)
	m.set_shader_parameter(&"swim_freq", TAU)
	m.set_shader_parameter(&"swim_wave", 0.3)
	m.set_shader_parameter(&"swim_vertical", 1.0)
	m.set_shader_parameter(&"swim_head", 0.05)
	m.set_shader_parameter(&"swim_still", 0.3)
	# The flukes trail the stroke, angling into it.
	m.set_shader_parameter(&"fin_lag", 0.55)


# --- The model ---------------------------------------------------------------

## The body (its skin painted), with the flippers, eyes and flukes.
static func _body_parts() -> ArrayMesh:
	var parts := [[_loft()]]
	# Short paddle flippers low behind the head, angled down and back.
	# (A rounded paddle, thick at its root and thin at its edges, along -Y.)
	var paddle := MeshKit.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.12, 0.72), Vector2(0.45, 1.0),
		Vector2(0.8, 0.82), Vector2(1.0, 0.5)]), 1.15, 14, 10, 0.06, 0.24)
	paddle = MeshKit.transformed(paddle, Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0.0, -0.5, 0.0)))
	var flipper := _unpainted(paddle, 0.05)
	for side: float in [1.0, -1.0]:
		var root := _surface(FLIPPER_X, PI * 0.7 if side > 0.0 else TAU - PI * 0.7)
		# Swept back and held in against the flank.
		var xf := Transform3D(Basis(Vector3.UP, side * 0.15) * Basis(Vector3.RIGHT, -side * 0.35)
			* Basis(Vector3.BACK, -0.95), root)
		parts.append([flipper, xf, FLIPPER_X])
		# The eye, small, low on the head by the corner of the mouth.
		var eye := _unpainted(MeshKit.ball(0.075, 0.0, 10, 6), 0.0)
		var at := _surface(EYE_X, PI * 0.66 if side > 0.0 else TAU - PI * 0.66)
		parts.append([eye, Transform3D(Basis.from_scale(Vector3(1.3, 1.0, 0.7)), at), EYE_X])
	# The flukes, flat and broad, notched in the middle, each vertex hanging
	# from its own place along the spine so they flex with the stroke.
	var half := PackedVector2Array([Vector2(0.25, 0.0), Vector2(0.05, 0.35), Vector2(-0.3, 0.95),
		Vector2(-0.8, 1.65), Vector2(-1.2, 2.15), Vector2(-1.45, 2.25), Vector2(-1.38, 1.85),
		Vector2(-1.22, 1.2), Vector2(-1.1, 0.55), Vector2(-1.0, 0.12)])
	var outline := PackedVector2Array()
	for k in half.size():
		outline.append(half[k])
	outline.append(Vector2(-0.88, 0.0))
	for k in range(half.size() - 1, 0, -1):
		outline.append(Vector2(half[k].x, -half[k].y))
	var flukes := MeshKit.fin(outline, 0.1)
	var tail := Vector3(-LENGTH * 0.5 + 0.1, 0.05, 0.0)
	flukes = MeshKit.transformed(flukes, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), tail))
	flukes = _unpainted(flukes, 0.0)
	# How far back from the stock: the free edges trail the most.
	flukes = MeshKit.painted(flukes, func(v: Vector3) -> Color:
		return Color(0.0, 0.0, clampf((-LENGTH * 0.5 + 0.1 - v.x) / 1.4, 0.0, 1.0)))
	parts.append([flukes])
	return BodyKit.merged(parts)


## The lower jaw, from its hinge (+X towards its tip): long and narrow, dark
## outside with pale lips, a row of conical teeth along each side.
static func _jaw_parts() -> ArrayMesh:
	var profile := PackedVector2Array([Vector2(0.0, 0.9), Vector2(0.25, 1.0), Vector2(0.7, 0.75),
		Vector2(0.92, 0.55), Vector2(0.985, 0.35), Vector2(1.0, 0.0)])
	var jaw := MeshKit.lathe(profile, JAW_L, 14, 20, 0.24, 0.3)
	jaw = MeshKit.transformed(jaw, Transform3D(Basis(), Vector3(JAW_L * 0.5, -0.1, 0.0)))
	jaw = MeshKit.painted(jaw, func(v: Vector3) -> Color:
		# Pale along the top where the lips are, and towards the tip.
		return Color(0.0, clampf(smoothstep(-0.02, 0.1, v.y) + smoothstep(3.6, 4.6, v.x) * 0.6, 0.0, 1.0), 0.0))
	var parts := [[_unpainted(jaw, -1.0)]]
	for side: float in [1.0, -1.0]:
		for t: Array in BodyKit.teeth_row(Vector3(0.9, 0.08, 0.16 * side), Vector3(4.4, 0.0, 0.06 * side), 18, 0.13,
				Vector3(0.0, 1.0, -0.15 * side).normalized(), 5 + int(side), false):
			parts.append([BodyKit.enamel(_unpainted(t[0], -1.0)), t[1]])
	return BodyKit.merged(parts)


## [param mesh] marked as left unpainted (UV2), with [param belly] for its
## belly blend if 0 or more (left as it is otherwise).
static func _unpainted(mesh: ArrayMesh, belly: float) -> ArrayMesh:
	var out := ArrayMesh.new()
	for si in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(si)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uv2 := PackedVector2Array()
		uv2.resize(verts.size())
		uv2.fill(Vector2(0.0, UNPAINTED))
		arrays[Mesh.ARRAY_TEX_UV2] = uv2
		if belly >= 0.0:
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			for k in colors.size():
				colors[k] = Color(0.0, belly, 0.0, colors[k].a)
			arrays[Mesh.ARRAY_COLOR] = colors
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


## The body, lofted through [constant STATIONS] with the hump and knuckles
## raised along the back and both ends closed. UV.x is where each point
## hangs from along the spine, UV.y the way round it from the back's
## midline; UV2 says where the painted skin lies (see creature.gdshader).
static func _loft() -> ArrayMesh:
	var rings := 110
	var sides := 40
	var x0: float = STATIONS[0][0]
	var x1: float = STATIONS[STATIONS.size() - 1][0]
	var grid: Array[PackedVector3Array] = []
	for i in rings + 1:
		var x := lerpf(x0, x1, float(i) / rings)
		var ring := PackedVector3Array()
		for j in sides + 1:
			ring.append(_surface(x, TAU * j / sides))
		grid.append(ring)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in rings + 1:
		var arcs := PackedFloat32Array([0.0])
		for j in sides:
			arcs.append(arcs[j] + grid[i][j].distance_to(grid[i][j + 1]))
		var full := arcs[sides]
		for j in sides + 1:
			var p := grid[i][j]
			var a := TAU * j / sides
			var round_share := (arcs[j] if a <= PI else arcs[j] - full) / (full * 0.5)
			# Normals from the neighbours all round, so no seam shows.
			var along := grid[mini(i + 1, rings)][j] - grid[maxi(i - 1, 0)][j]
			var around := grid[i][(j + 1) % sides] - grid[i][(j - 1 + sides) % sides]
			st.set_normal(around.cross(along).normalized())
			st.set_color(Color(0.0, smoothstep(0.1, -0.7, cos(a)), 0.0))
			st.set_uv(Vector2(p.x, minf(arcs[j], full - arcs[j])))
			st.set_uv2(Vector2(p.x, clampf(round_share, -1.0, 1.0)))
			st.add_vertex(p)
	var row := sides + 1
	for i in rings:
		for j in sides:
			var a := i * row + j
			for k: int in [a, a + row, a + 1, a + 1, a + row, a + row + 1]:
				st.add_index(k)
	# Close both ends.
	for end in 2:
		var i := 0 if end == 0 else rings
		var centre := Vector3.ZERO
		for j in sides:
			centre += grid[i][j]
		centre /= sides
		centre.x += -0.04 if end == 0 else 0.06
		var c := (rings + 1) * row + end
		st.set_normal(Vector3.LEFT if end == 0 else Vector3.RIGHT)
		st.set_color(Color(0.0, 0.3, 0.0))
		st.set_uv(Vector2(centre.x, 0.0))
		st.set_uv2(Vector2(centre.x, 0.0))
		st.add_vertex(centre)
		for j in sides:
			var a := i * row + j
			var tri := [c, a, a + 1] if end == 0 else [c, a + 1, a]
			for k: int in tri:
				st.add_index(k)
	return st.commit()


## The point on the skin at [param x] along the body, [param a] radians round
## from the back's midline (towards +Z first).
static func _surface(x: float, a: float) -> Vector3:
	var n := STATIONS.size()
	var k := 0
	while k < n - 2 and x > float(STATIONS[k + 1][0]):
		k += 1
	var b: Array = STATIONS[k]
	var c: Array = STATIONS[k + 1]
	var pa: Array = STATIONS[maxi(k - 1, 0)]
	var pd: Array = STATIONS[mini(k + 2, n - 1)]
	var t := clampf((x - float(b[0])) / maxf(float(c[0]) - float(b[0]), 0.0001), 0.0, 1.0)
	var f := PackedFloat32Array()
	for idx in range(1, 6):
		f.append(maxf(cubic_interpolate(float(b[idx]), float(c[idx]), float(pa[idx]), float(pd[idx]), t), 0.01))
	var ca := cos(a)
	var sa := sin(a)
	var top := f[1]
	for r: Vector3 in RIDGE:
		top += r.y * exp(-pow((x - r.x) / r.z, 2.0)) * pow(maxf(ca, 0.0), 6.0)
	var e := 2.0 / f[4]
	var r := top if ca >= 0.0 else f[2]
	return Vector3(x, f[3] + signf(ca) * pow(absf(ca), e) * r, signf(sa) * pow(absf(sa), e) * f[0])


func tick(delta: float) -> void:
	var sub := level.player
	match state:
		State.WAITING:
			if backdrop:
				_rest -= delta
				if _rest <= 0.0:
					_set_off(-heading)
			elif sub and sub.alive and sub.pos.distance_to(pos) < TRIGGER_RANGE:
				_begin(sub)
		State.PASSING:
			_swim(delta, sub)


## Sets off from the end of its stretch farther from the sub, so it passes it.
func _begin(sub: Submarine) -> void:
	_set_off(1.0 if sub.pos.distance_to(from) > sub.pos.distance_to(to) else -1.0)


func _set_off(dir: float) -> void:
	state = State.PASSING
	heading = dir
	_x = _start_x()
	_t = 0.0
	_rig.visible = true
	_rig.rotation.y = 0.0 if heading > 0.0 else PI
	_gape_in = _rng.randf_range(5.0, 9.0)


func _swim(delta: float, sub: Submarine) -> void:
	_t += delta
	_x += heading * SPEED * delta
	var start_x := _start_x()
	var end_x := _end_x()
	var gone := absf(_x - start_x)
	var left := absf(end_x - _x)
	if left <= 0.0 or signf(end_x - _x) != heading:
		# Behind the title it comes round again after a while.
		state = State.WAITING if backdrop else State.GONE
		_rest = _rng.randf_range(10.0, 16.0)
		_rig.visible = false
		return
	# Out of the blue and back into it.
	_fade = clampf(minf(gone, left) / (SPEED * FADE), 0.0, 1.0)
	var at := Vector2(_x, from.y + 0.25 * sin(_t * 0.5))
	_rig.position = Vector3(at.x, at.y, DEPTH)
	_pose(delta)
	var head := at + Vector2(heading * LENGTH * 0.45, 0.0)
	_click_in -= delta
	if _click_in <= 0.0:
		_click_in = _rng.randf_range(0.55, 0.9)
		if _rng.randf() < 0.12:
			Audio.play_at(&"whale_creak", head, -6.0, 0.05)
		else:
			Audio.play_at(&"whale_click", head, -8.0, 0.1)
	# Its clicks chart the cave on the sub's sonar.
	_ping_in -= delta
	if _ping_in <= 0.0 and _fade > 0.5 and not backdrop:
		_ping_in = CLICK_PING_EVERY
		level.ping(head, CLICK_PING_RANGE, 2.0, true)
	var seen := _fade > 0.5 and sub and sub.alive and sub.pos.distance_to(at) < WITNESS_RANGE
	if seen and not witnessed and not backdrop:
		witnessed = true
		Wonders.witness("whale")
		sub.run.research += RESEARCH
		sub.show_gain(RESEARCH, " research", UiTheme.ACCENT)
		Events.toast.emit("A sperm whale passes, clicking. Its clicks show the cave on your sonar.", UiTheme.ACCENT)


## The stroke: the flukes beat slowly down and up, the body flexing along
## its length (in the shader); the whole of it heaves gently against each
## beat and pitches with it. Now and then its jaw hangs open a little, and
## closes again.
func _pose(delta: float) -> void:
	var ph := _t / STROKE * TAU
	_rig.position.y += -0.18 * sin(ph - 0.6)
	_rig.rotation.z = 0.03 * cos(ph)
	# The last five seconds before it comes round again, the jaw drops open
	# and closes.
	_gape_in -= delta
	if _gape_in <= 0.0:
		_gape_in = _rng.randf_range(9.0, 15.0)
	var g := 0.13 * smoothstep(5.0, 3.4, _gape_in) * smoothstep(0.0, 1.6, _gape_in)
	_gape = lerpf(_gape, g, 1.0 - exp(-2.0 * delta)) if delta > 0.0 else g
	_jaw.rotation.z = -_gape
	for mi: MeshInstance3D in [_body, _jaw]:
		mi.set_instance_shader_parameter(&"swim_clock", _t / STROKE)
		mi.set_instance_shader_parameter(&"swim_power", 1.0)
		mi.set_instance_shader_parameter(&"fade", _fade)


## Where its middle turns back into the blue: far enough in from either end
## of the open stretch (which itself stops short of the rock) that its head
## and tail never reach the rock.
func _start_x() -> float:
	return from.x + _margin() if heading > 0.0 else to.x - _margin()


func _end_x() -> float:
	return to.x - _margin() if heading > 0.0 else from.x + _margin()


static func _margin() -> float:
	return LENGTH * 0.5 - TIGHT_CLEARANCE + 0.5


## Where it is now, for tests and previews (INF when it is not passing).
func whale_pos() -> Vector2:
	return Vector2(_x, from.y) if state == State.PASSING else Vector2.INF
