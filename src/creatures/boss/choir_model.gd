class_name ChoirModel
extends RefCounted
## The Choir's body, in its own shader's conventions (see choir.gdshaderinc:
## vertex colour R its lights, G its comb rows and iridescent edges, B its
## core; UV2.x how far a point lies from the heart, UV2.y how far along its
## comb row or strand).
## [br]- Its heart: a bell of see-through flesh fourteen metres tall, lobed
## between eight sculpted comb rows set with rows of comb plates that beat
## with rainbow light; a crown of curling, beaded fronds; a frilled skirt
## round its foot. Inside, its song organ: a column of glowing rings, lobed
## sacs about it, and a tree of vessels branching out to the skin, knotted
## with ganglia. At its front a throat closed by an iris of petals.
## [br]- Its tentacles: ringed, beaded with lights, a rippling frill down
## each flank, rebuilt every frame along whatever line they lie on.
## [br]- Its voice organs: a knobbed bulb rooted in the rock, a bundle of
## ribbed pipes rising from it with frilled, glowing mouths.

## The heart's outline: [height, radius] from its foot to its crown.
const PROFILE := [Vector2(-7.0, 0.0), Vector2(-6.6, 1.0), Vector2(-5.6, 2.4), Vector2(-3.8, 4.1),
	Vector2(-1.6, 5.2), Vector2(0.8, 5.5), Vector2(3.0, 4.9), Vector2(4.9, 3.6), Vector2(6.2, 2.0),
	Vector2(6.9, 0.8), Vector2(7.1, 0.0)]
## Its comb rows, running from foot to crown.
const COMBS := 8
## How far its lobes bulge between the grooves, and its comb rows stand.
const LOBE := 0.1
const RIDGE := 0.3
## The throat: how high on its front, how wide; the petals closing it.
const THROAT_Y := 0.6
const THROAT_R := 1.5
const PETALS := 9
## The fronds of its crown.
const FRONDS := 9
## Where its skirt grows from.
const SKIRT_Y := -4.3
## A voice organ's pipes: [angle up from its axis, angle round, length].
const PIPES := [Vector3(0.0, 0.0, 3.8), Vector3(0.22, 0.3, 3.1), Vector3(0.2, 1.9, 3.4), Vector3(0.24, 3.4, 2.7),
	Vector3(0.3, 5.0, 2.3), Vector3(0.36, 1.1, 1.9), Vector3(0.4, 2.7, 1.7), Vector3(0.42, 4.2, 1.6)]

static var _skin_mat: ShaderMaterial
static var _flesh_mat: ShaderMaterial
static var _core_mat: ShaderMaterial
static var _organ_mat: ShaderMaterial


## The see-through flesh of the heart's skin.
static func skin_material() -> ShaderMaterial:
	if _skin_mat == null:
		_skin_mat = ShaderMaterial.new()
		_skin_mat.shader = preload("res://src/fx/shaders/choir_glass.gdshader")
		_skin_mat.set_shader_parameter(&"body_color", Color(0.1, 0.05, 0.18))
		_skin_mat.set_shader_parameter(&"glow_strength", 1.8)
		_skin_mat.set_shader_parameter(&"alpha_face", 0.2)
		_skin_mat.set_shader_parameter(&"alpha_edge", 0.92)
		_skin_mat.set_shader_parameter(&"vein_scale", 0.3)
		_skin_mat.set_shader_parameter(&"vein_glow", 0.5)
		_skin_mat.set_shader_parameter(&"comb_glow", 2.0)
		_skin_mat.set_shader_parameter(&"cell_scale", 1.4)
		_skin_mat.set_shader_parameter(&"cell_relief", 0.03)
		_skin_mat.set_shader_parameter(&"freckles", 0.06)
		_skin_mat.set_shader_parameter(&"wrinkles", 0.012)
		_skin_mat.set_shader_parameter(&"iridescence", 0.3)
		_skin_mat.set_shader_parameter(&"rim_strength", 0.7)
		_skin_mat.set_shader_parameter(&"roughness", 0.15)
	return _skin_mat


## Its solid flesh: its tentacles, comb plates, crown, skirt and throat.
static func flesh_material() -> ShaderMaterial:
	if _flesh_mat == null:
		_flesh_mat = ShaderMaterial.new()
		_flesh_mat.shader = preload("res://src/fx/shaders/choir.gdshader")
		_flesh_mat.set_shader_parameter(&"body_color", Color(0.07, 0.035, 0.13))
		_flesh_mat.set_shader_parameter(&"glow_strength", 2.0)
		_flesh_mat.set_shader_parameter(&"rim_strength", 0.5)
		_flesh_mat.set_shader_parameter(&"cell_scale", 3.2)
		_flesh_mat.set_shader_parameter(&"cell_relief", 0.012)
		_flesh_mat.set_shader_parameter(&"freckles", 0.05)
		_flesh_mat.set_shader_parameter(&"wrinkles", 0.006)
		_flesh_mat.set_shader_parameter(&"iridescence", 0.15)
	return _flesh_mat


## The song organ inside its heart: dark flesh webbed with glowing veins.
static func core_material() -> ShaderMaterial:
	if _core_mat == null:
		_core_mat = flesh_material().duplicate() as ShaderMaterial
		_core_mat.set_shader_parameter(&"vein_scale", 0.85)
		_core_mat.set_shader_parameter(&"vein_glow", 0.6)
		_core_mat.set_shader_parameter(&"cell_scale", 2.4)
		_core_mat.set_shader_parameter(&"freckles", 0.1)
	return _core_mat


## A voice organ's flesh: veined more faintly than the heart's.
static func organ_material() -> ShaderMaterial:
	if _organ_mat == null:
		_organ_mat = flesh_material().duplicate() as ShaderMaterial
		_organ_mat.set_shader_parameter(&"vein_scale", 1.1)
		_organ_mat.set_shader_parameter(&"vein_glow", 0.5)
		_organ_mat.set_shader_parameter(&"cell_scale", 2.6)
		_organ_mat.set_shader_parameter(&"freckles", 0.08)
	return _organ_mat


## The heart, whole: the song organ inside it, its comb plates, crown and
## skirt, its skin, and the petals of its throat (in its "petals" meta, each
## a pivot that opens by turning about its own Y). Its "parts" meta lists
## its meshes, the song organ first.
static func build_heart() -> Node3D:
	var root := Node3D.new()
	root.name = "Heart"
	var core := _instance(heart_core(), core_material())
	root.add_child(core)
	var body := _instance(heart_body(), flesh_material())
	root.add_child(body)
	var skin := _instance(heart_skin(), skin_material())
	root.add_child(skin)
	var petals: Array[Node3D] = []
	var petal_mesh := petal()
	var throat := throat_centre()
	for i in PETALS:
		var a := TAU * i / PETALS
		var pivot := Node3D.new()
		pivot.position = throat + Vector3(cos(a), sin(a), 0.0) * THROAT_R
		# Each lies from the rim in towards the middle, its hinge along the rim.
		pivot.basis = Basis(Vector3.BACK, a + PI)
		pivot.add_child(_instance(petal_mesh, flesh_material()))
		root.add_child(pivot)
		petals.append(pivot)
	root.set_meta(&"petals", petals)
	root.set_meta(&"parts", [core, body, skin])
	return root


static func _instance(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## The heart's outline radius at height [param y].
static func _radius(y: float) -> float:
	for k in PROFILE.size() - 1:
		var a: Vector2 = PROFILE[k]
		var b: Vector2 = PROFILE[k + 1]
		if y <= b.x:
			var t := clampf((y - a.x) / (b.x - a.x), 0.0, 1.0)
			return lerpf(a.y, b.y, t * t * (3.0 - 2.0 * t))
	return 0.0


## How near a point [param a] radians round the heart lies to a comb row (1
## on it).
static func _crest(a: float) -> float:
	return pow(0.5 + 0.5 * cos(a * COMBS), 3.0)


## A point on the heart's skin at height [param y], [param a] radians round
## from its front (+Z) towards +X.
static func skin_point(y: float, a: float) -> Vector3:
	var crest := _crest(a)
	var ridge := smoothstep(0.86, 1.0, crest)
	var r := _radius(y) * (1.0 + LOBE * crest) + RIDGE * ridge * smoothstep(0.0, 1.2, _radius(y))
	# Shallow folds across the lobes, so the bell is not a smooth egg.
	r *= 1.0 + 0.025 * sin(y * 2.6 + sin(a * 3.0)) * (1.0 - ridge)
	return Vector3(sin(a) * r, y, cos(a) * r)


## Which way the heart's skin faces there.
static func _skin_normal(y: float, a: float) -> Vector3:
	var up := skin_point(y + 0.02, a) - skin_point(y - 0.02, a)
	var around := skin_point(y, a + 0.005) - skin_point(y, a - 0.005)
	return around.cross(up).normalized()


## Where the throat opens on the heart's front.
static func throat_centre() -> Vector3:
	return Vector3(0.0, THROAT_Y, _radius(THROAT_Y) * (1.0 + LOBE) - 0.15)


## The heart's skin: lobed between its comb rows, folded, membranous (in
## the shader), a ring of light round the throat.
static func heart_skin() -> ArrayMesh:
	var rings := 72
	var sides := 128
	var y0: float = PROFILE[0].x
	var y1: float = PROFILE[PROFILE.size() - 1].x
	var grid: Array[PackedVector3Array] = []
	for i in rings + 1:
		var ring := PackedVector3Array()
		var y := lerpf(y0, y1, float(i) / rings)
		for j in sides + 1:
			ring.append(skin_point(y, TAU * j / sides))
		grid.append(ring)
	var b := Builder.new()
	var throat := throat_centre()
	for i in rings + 1:
		for j in sides + 1:
			var a := TAU * j / sides
			var p := grid[i][j]
			var up := grid[mini(i + 1, rings)][j] - grid[maxi(i - 1, 0)][j]
			var around := grid[i][(j + 1) % sides] - grid[i][(j - 1 + sides) % sides]
			var n := around.cross(up)
			var comb := smoothstep(0.92, 1.0, _crest(a)) * smoothstep(0.8, 2.0, _radius(p.y)) * 0.6
			var lip := exp(-pow((p.distance_to(throat) - THROAT_R * 1.25) / 0.22, 2.0))
			b.add(p, n.normalized() if n.length_squared() > 1e-10 else (Vector3.UP if i > 0 else Vector3.DOWN),
				Color(lip * 0.8, comb, 0.0), Vector2(p.length() - 2.5, p.y + 7.0))
	var row := sides + 1
	for i in rings:
		for j in sides:
			var a := i * row + j
			b.indices.append_array([a, a + row, a + 1, a + 1, a + row, a + row + 1])
	return b.commit()


## The heart's solid outer parts: rows of comb plates down its comb rows,
## the crown of fronds curling from its top, and its frilled skirt.
static func heart_body() -> ArrayMesh:
	var b := Builder.new()
	# Comb plates: thin paddles standing across each row, smaller towards
	# the poles.
	for r in COMBS:
		var a := TAU * r / COMBS
		var y := -5.4
		while y < 6.2:
			var size := clampf(_radius(y) / 4.0, 0.3, 1.0)
			var p := skin_point(y, a)
			var n := _skin_normal(y, a)
			var along := (skin_point(y + 0.02, a) - skin_point(y - 0.02, a)).normalized()
			var across := n.cross(along).normalized()
			b.blob(p + n * 0.07 * size, across * 0.3 * size, along * 0.045 * size, n * 0.13 * size,
				Color(0.12, 1.0, 0.0), Vector2(p.length() - 2.5, y + 7.0), 8, 5)
			y += 0.3 + 0.12 * (1.0 - size)
	# The crown: fronds rising from round the top, curling out and down.
	for k in FRONDS:
		var a := TAU * (k + 0.5) / FRONDS
		var out := Vector3(sin(a), 0.0, cos(a))
		var base := skin_point(6.0, a) - out * 0.2
		var reach := 1.0 + 0.25 * sin(k * 2.3)
		var pts := _curve(PackedVector3Array([base, base + Vector3(0.0, 1.1, 0.0) + out * 0.5 * reach,
			base + Vector3(0.0, 2.1, 0.0) + out * 1.8 * reach, base + Vector3(0.0, 2.2, 0.0) + out * 3.2 * reach,
			base + Vector3(0.0, 1.4, 0.0) + out * 4.0 * reach, base + Vector3(0.0, 0.5, 0.0) + out * 4.1 * reach,
			base + out * 3.6 * reach]), 30)
		var radii := PackedFloat32Array()
		for s in pts.size():
			radii.append(lerpf(0.42, 0.04, pow(float(s) / (pts.size() - 1), 0.9)))
		b.strand(pts, radii, out.cross(Vector3.UP), 0.45, 8, 6.0, func(t: float, ang: float, dist: float) -> Color:
			var bead := smoothstep(0.88, 0.96, absf(fmod(dist / 0.55, 1.0) - 0.5) * 2.0) * smoothstep(0.6, 0.95, cos(ang))
			return Color(bead + smoothstep(0.85, 1.0, t), smoothstep(0.85, 1.0, absf(sin(ang))) * 0.7, 0.0))
	# The skirt: two frilled tiers round its foot, ruffled, their rims lit.
	for tier in 2:
		var y0 := SKIRT_Y - tier * 1.1
		var drop := 1.6 - tier * 0.5
		var spread := 1.9 - tier * 0.6
		var rows: Array[PackedVector3Array] = []
		var facing := PackedVector3Array()
		var count := 160
		for i in count + 1:
			var a := TAU * i / count
			var out := Vector3(sin(a), 0.0, cos(a))
			var root := skin_point(y0, a) - out * 0.15
			var row := PackedVector3Array()
			for k in 6:
				var v := k / 5.0
				var ruffle := pow(v, 1.5)
				row.append(root + out * (spread * pow(v, 0.8) + 0.3 * sin(a * 26.0 + tier) * ruffle)
					+ Vector3(0.0, -drop * pow(v, 1.3) + 0.3 * cos(a * 26.0 + 0.5 + tier) * ruffle, 0.0))
			rows.append(row)
			facing.append((Vector3.UP + out * 0.6).normalized())
		b.sheet(rows, facing, func(_i: int, k: int) -> Color:
			var v := k / 5.0
			return Color(smoothstep(0.8, 1.0, v) * 0.45, smoothstep(0.6, 1.0, v) * 0.45, 0.0),
			func(i: int, k: int) -> Vector2:
				return Vector2(rows[i][k].length() - 2.5, float(i) * 0.1))
	return b.commit()


## The song organ inside the heart: a column of glowing rings, lobed sacs
## round it, a tree of vessels branching out from it to the skin with
## ganglia at their forks, and the throat's maw: the song's light starts
## here.
static func heart_core() -> ArrayMesh:
	var b := Builder.new()
	var column := PackedVector3Array()
	var column_r := PackedFloat32Array()
	for s in 16:
		var y := lerpf(-3.8, 4.2, s / 15.0)
		column.append(Vector3(0.12 * sin(y * 1.3), y, 0.0))
		column_r.append(0.26 + 0.06 * sin(y * 4.0))
	b.strand(column, column_r, Vector3.BACK, 1.0, 10, 0.0, func(_t: float, _a: float, _d: float) -> Color:
		return Color(0.25, 0.0, 0.15))
	# Its rings, widest about the middle, each slung from the column by spokes.
	for k in 9:
		var y := lerpf(-3.3, 3.7, k / 8.0)
		var rr := 0.6 + 1.0 * sin(PI * (k + 0.5) / 9.0)
		var ring := PackedVector3Array()
		var ring_r := PackedFloat32Array()
		for s in 33:
			var a := TAU * s / 32.0
			ring.append(Vector3(sin(a) * rr, y + 0.06 * sin(a * 3.0 + k), cos(a) * rr))
			ring_r.append(0.1)
		b.strand(ring, ring_r, Vector3.UP, 1.0, 6, absf(y), func(_t: float, _a: float, _d: float) -> Color:
			return Color(0.6, 0.0, 0.1))
		for s in 4:
			var a := TAU * (s + 0.5 * (k % 2)) / 4.0
			b.strand(PackedVector3Array([Vector3(0.0, y, 0.0), Vector3(sin(a) * rr, y, cos(a) * rr)]),
				PackedFloat32Array([0.05, 0.03]), Vector3.UP, 1.0, 5, absf(y),
				func(_t: float, _a: float, _d: float) -> Color: return Color(0.35, 0.0, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	# Lobed sacs round the column.
	for k in 7:
		var a := TAU * k / 7.0 + 0.3
		var at := Vector3(sin(a) * 2.6, lerpf(-2.6, 2.8, fmod(k * 0.43, 1.0)), cos(a) * 2.6 * 0.8)
		for lobe in 3:
			var off := Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.6, 0.6), rng.randf_range(-0.5, 0.5))
			var r := rng.randf_range(0.55, 0.95) * (1.0 if lobe == 0 else 0.75)
			b.blob(at + off * float(lobe), Vector3(r, 0.0, 0.0), Vector3(0.0, r * 1.15, 0.0), Vector3(0.0, 0.0, r),
				Color(0.05, 0.0, 0.07), Vector2(2.0, 0.0), 14, 10)
	# The vessel tree.
	for k in 9:
		var a := TAU * k / 9.0 + rng.randf_range(-0.2, 0.2)
		var y := rng.randf_range(-3.0, 3.6)
		var dir := Vector3(sin(a), rng.randf_range(-0.5, 0.5), cos(a)).normalized()
		_branch(b, Vector3(0.0, y, 0.0), dir, 2.0, 0.16, 0, rng)
	# The throat's maw, ablaze behind its petals.
	var throat := throat_centre()
	b.blob(throat - Vector3(0.0, 0.0, 0.4), Vector3(THROAT_R * 0.9, 0.0, 0.0), Vector3(0.0, THROAT_R * 0.9, 0.0),
		Vector3(0.0, 0.0, THROAT_R * 0.35), Color(0.5, 0.0, 0.8), Vector2(0.0, 0.0), 18, 10)
	return b.commit()


## One vessel from [param from] along [param dir], wandering, forking twice
## more (to [param depth] 2), a glowing ganglion at each fork; never through
## the skin.
static func _branch(b: Builder, from: Vector3, dir: Vector3, length: float, radius: float, depth: int,
		rng: RandomNumberGenerator) -> void:
	var bend := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * 0.35
	var end := from + (dir + bend).normalized() * length
	var limit := _radius(end.y) * 0.88
	var flat := Vector2(end.x, end.z)
	if flat.length() > limit:
		flat = flat.normalized() * limit
		end = Vector3(flat.x, end.y, flat.y)
	var pts := PackedVector3Array()
	var radii := PackedFloat32Array()
	var mid := from.lerp(end, 0.5) + bend * length * 0.4
	for s in 9:
		var t := s / 8.0
		pts.append(from.lerp(mid, t).lerp(mid.lerp(end, t), t))
		radii.append(lerpf(radius, radius * 0.55, t))
	var start := from.length()
	b.strand(pts, radii, Vector3.UP, 1.0, 6, start, func(_t: float, _a: float, _d: float) -> Color:
		return Color(0.35, 0.0, 0.0))
	if depth >= 2:
		return
	b.blob(end, Vector3(radius * 1.9, 0.0, 0.0), Vector3(0.0, radius * 1.9, 0.0), Vector3(0.0, 0.0, radius * 1.9),
		Color(0.8, 0.0, 0.1), Vector2(start + length, 0.0), 8, 6)
	var d := (end - from).normalized()
	var side := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized()
	for sgn: float in [1.0, -1.0]:
		var child := d.rotated(side.rotated(d, rng.randf_range(0.0, TAU)), 0.55 * sgn)
		_branch(b, end, child, length * 0.7, radius * 0.6, depth + 1, rng)


## One petal of the throat's iris: a slender, cupped blade of flesh lying
## from its hinge (the origin, on the throat's rim) along +X in to the
## middle, its midrib and tip lit.
static func petal() -> ArrayMesh:
	var length := THROAT_R * 1.15
	var rings := 10
	return _loft_petal(rings, 8, func(i: int, a: float) -> Vector3:
		var u := float(i) / (rings - 1)
		var w := sin(PI * clampf(u * 0.95 + 0.05, 0.0, 1.0)) * 0.42 * (1.0 - 0.55 * u)
		var cup := 0.3 * u * u
		var thick := lerpf(0.15, 0.04, u)
		return Vector3(u * length, sin(a) * w, cos(a) * thick + cup),
		func(i: int, a: float) -> Color:
			var u := float(i) / (rings - 1)
			var midrib := exp(-pow(sin(a) / 0.18, 2.0)) * smoothstep(-0.2, 0.5, cos(a)) * 0.35
			return Color(0.05 + midrib + 0.6 * smoothstep(0.75, 1.0, u) * smoothstep(-0.2, 0.6, cos(a)),
				0.25 * exp(-pow(cos(a) / 0.3, 2.0)), 0.0))


static func _loft_petal(rings: int, sides: int, point: Callable, color: Callable) -> ArrayMesh:
	var grid: Array[PackedVector3Array] = []
	for i in rings:
		var ring := PackedVector3Array()
		for j in sides + 1:
			ring.append(point.call(i, TAU * j / sides))
		grid.append(ring)
	var b := Builder.new()
	for i in rings:
		for j in sides + 1:
			var a := TAU * j / sides
			var along := grid[mini(i + 1, rings - 1)][j] - grid[maxi(i - 1, 0)][j]
			var around := grid[i][(j + 1) % sides] - grid[i][(j - 1 + sides) % sides]
			var n := along.cross(around)
			b.add(grid[i][j], n.normalized() if n.length_squared() > 1e-10 else Vector3.RIGHT, color.call(i, a),
				Vector2(grid[i][j].x, grid[i][j].x))
	var row := sides + 1
	for i in rings - 1:
		for j in sides:
			var a := i * row + j
			b.indices.append_array([a, a + 1, a + row, a + 1, a + row + 1, a + row])
	return b.commit()


## Lofts a tentacle into [param mesh] along [param pts] (radii [param radii]):
## dark and ringed, a row of lights down its back and a fainter line down
## each flank, its tip aglow, and a frill down each flank, its edge lit with
## shifting colour, rippling ([param phase], seconds); [param from] is how
## far its root lies from the heart.
static func tentacle_into(mesh: ArrayMesh, pts: PackedVector3Array, radii: PackedFloat32Array, from: float,
		phase := 0.0) -> void:
	var n := pts.size()
	var sides := 10
	var row := sides + 1
	var frill_w := 3
	var count := n * row + 2 * 2 * n * frill_w
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uv2s := PackedVector2Array()
	verts.resize(count)
	normals.resize(count)
	colors.resize(count)
	uv2s.resize(count)
	var indices := PackedInt32Array()
	# The frame carried down it, so its row of lights never twists round.
	var ups := PackedVector3Array()
	var sides_v := PackedVector3Array()
	var dists := PackedFloat32Array()
	ups.resize(n)
	sides_v.resize(n)
	dists.resize(n)
	var up := Vector3.BACK
	var dist := 0.0
	for i in n:
		var fwd := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
		if i > 0:
			dist += pts[i].distance_to(pts[i - 1])
		up = (up - fwd * up.dot(fwd)).normalized()
		ups[i] = up
		sides_v[i] = fwd.cross(up)
		dists[i] = dist
	for i in n:
		var t := float(i) / (n - 1)
		var d := dists[i]
		var bead := smoothstep(0.9, 0.97, absf(fmod(d / 1.5, 1.0) - 0.5) * 2.0)
		# Ringed, like a worm's body.
		var r := radii[i] * (1.0 + 0.09 * sin(d * TAU / 0.7))
		for j in row:
			var a := TAU * j / sides
			var dir := ups[i] * cos(a) + sides_v[i] * sin(a)
			var k := i * row + j
			verts[k] = pts[i] + (ups[i] * cos(a) * 0.8 + sides_v[i] * sin(a)) * r
			normals[k] = dir
			var back := smoothstep(0.75, 1.0, cos(a))
			var flank := exp(-pow(cos(a) / 0.2, 2.0)) * 0.08
			colors[k] = Color(maxf(bead * back, flank) * (1.0 - 0.4 * t) + smoothstep(0.9, 1.0, t) * 0.8, 0.0, 0.0)
			uv2s[k] = Vector2(from + d, d)
	for i in n - 1:
		for j in sides:
			var a := i * row + j
			indices.append_array([a, a + row, a + 1, a + 1, a + row, a + row + 1])
	# The frills: a strip standing out from each flank, rippling as it goes,
	# drawn from both faces.
	var at := n * row
	for sgn: float in [1.0, -1.0]:
		for face in 2:
			var start := at
			var f := 1.0 if face == 0 else -1.0
			for i in n:
				var t := float(i) / (n - 1)
				var w := radii[i] * 1.15 * smoothstep(0.03, 0.15, t) * (1.0 - 0.55 * t) + 0.04
				var ripple := sin(dists[i] * 2.4 - phase * 3.0)
				var base := pts[i] + sides_v[i] * sgn * radii[i] * 0.8
				for k in frill_w:
					var u := float(k) / (frill_w - 1)
					verts[at] = base + sides_v[i] * sgn * w * u + ups[i] * (ripple * w * 0.45 * u * u + 0.006 * f)
					normals[at] = ups[i] * f
					colors[at] = Color(0.3 * u * u * u * (1.0 - 0.3 * t), 0.4 * u * u, 0.0)
					uv2s[at] = Vector2(from + dists[i], dists[i])
					at += 1
			# Facing out of the frill on this face (Godot's front faces wind
			# clockwise as seen).
			var flip := (sgn > 0.0) == (face == 0)
			for i in n - 1:
				for k in frill_w - 1:
					var a := start + i * frill_w + k
					if flip:
						indices.append_array([a, a + frill_w, a + 1, a + 1, a + frill_w, a + frill_w + 1])
					else:
						indices.append_array([a, a + 1, a + frill_w, a + 1, a + frill_w + 1, a + frill_w])
	mesh.clear_surfaces()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


## A smooth curve through [param pts], [param count] points along it.
static func curve(pts: PackedVector3Array, count: int) -> PackedVector3Array:
	return _curve(pts, count)


static func _curve(pts: PackedVector3Array, count: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	for s in count:
		var g := float(s) / (count - 1) * (pts.size() - 1)
		var k := mini(int(g), pts.size() - 2)
		out.append(pts[k].cubic_interpolate(pts[k + 1], pts[maxi(k - 1, 0)], pts[mini(k + 2, pts.size() - 1)], g - k))
	return out


## A voice organ's body (along +X, the way it sings): a knobbed, veined
## bulb, a lit collar where its pipes rise, and roots reaching back from it
## into the rock.
static func organ_body() -> ArrayMesh:
	var noise := FastNoiseLite.new()
	noise.seed = 12
	noise.frequency = 1.6
	var rings := 18
	var bulb := _loft_petal(rings, 20, func(i: int, a: float) -> Vector3:
		var u := float(i) / (rings - 1)
		var x := lerpf(-1.9, 1.0, u)
		var r := 1.3 * sqrt(maxf(1.0 - pow((x + 0.45) / 1.45, 2.0), 0.0))
		var p := Vector3(x, sin(a) * r, cos(a) * r * 1.05)
		return p * (1.0 + 0.14 * noise.get_noise_3dv(p * 1.3) + 0.05 * noise.get_noise_3dv(p * 4.0)),
		func(_i: int, _a: float) -> Color: return Color(0.04, 0.0, 0.0))
	var b := Builder.new()
	b.append_mesh(bulb, Transform3D.IDENTITY)
	var collar := PackedVector3Array()
	var collar_r := PackedFloat32Array()
	for s in 33:
		var a := TAU * s / 32.0
		collar.append(Vector3(0.85, sin(a) * 0.82, cos(a) * 0.82))
		collar_r.append(0.12 + 0.04 * sin(a * 8.0))
	b.strand(collar, collar_r, Vector3.RIGHT, 1.0, 6, 1.0, func(_t: float, _a: float, _d: float) -> Color:
		return Color(0.6, 0.3, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for k in 9:
		var a := TAU * k / 9.0 + rng.randf_range(-0.3, 0.3)
		var out := Vector3(0.0, cos(a), sin(a))
		var wander := Vector3(0.0, rng.randf_range(-0.6, 0.6), rng.randf_range(-0.6, 0.6))
		var reach := rng.randf_range(2.6, 3.8)
		var pts := PackedVector3Array()
		var radii := PackedFloat32Array()
		for s in 14:
			var t := s / 13.0
			pts.append(Vector3(-0.9 - reach * t, 0.0, 0.0) + out * (0.7 + 1.3 * t) + wander * sin(PI * t * 1.5)
				+ out.cross(Vector3.RIGHT) * 0.25 * sin(t * 9.0 + k))
			radii.append(lerpf(0.3, 0.025, pow(t, 0.8)))
		b.strand(pts, radii, out, 1.0, 7, 0.0, func(_t: float, _a: float, _d: float) -> Color:
			return Color(0.03, 0.0, 0.0))
	return b.commit()


## One of a voice organ's pipes, rising along +X from its foot (the
## origin) [param length] metres: ribbed, flaring to a wide mouth with a
## frilled, lit lip, its throat ablaze.
static func organ_pipe(length: float) -> ArrayMesh:
	var profile := [Vector2(0.0, 0.5), Vector2(0.12, 0.46), Vector2(0.24, 0.43), Vector2(0.36, 0.41),
		Vector2(0.48, 0.4), Vector2(0.6, 0.4), Vector2(0.72, 0.44), Vector2(0.84, 0.56), Vector2(0.93, 0.78),
		Vector2(0.99, 0.98), Vector2(1.0, 1.02), Vector2(0.99, 0.86), Vector2(0.94, 0.58), Vector2(0.8, 0.34),
		Vector2(0.7, 0.0)]
	var rings := profile.size()
	return _loft_petal(rings, 18, func(i: int, a: float) -> Vector3:
		var p: Vector2 = profile[i]
		# Ribbed below the bell; the lip frilled.
		var rib := 1.0 + (0.07 * float(i % 2) if i < 7 else 0.0)
		var frill := 1.0 + (0.1 * sin(a * 12.0) if i >= 9 and i <= 11 else 0.0)
		var r := p.y * rib * frill
		return Vector3(p.x * length + (0.04 * sin(a * 12.0) if i == 10 else 0.0), sin(a) * r, cos(a) * r),
		func(i: int, _a: float) -> Color:
			if i >= 12:
				return Color(1.0, 0.0, 0.5)
			var p: Vector2 = profile[i]
			return Color(0.02 + 0.12 * float(i % 2) * float(i < 7) + 0.6 * smoothstep(0.93, 1.0, p.x),
				0.5 * smoothstep(0.95, 1.0, p.x), 0.0))


## Gathers vertices for a mesh: tubes, sheets and blobs.
class Builder:
	extends RefCounted
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uv2s := PackedVector2Array()
	var indices := PackedInt32Array()

	func add(p: Vector3, n: Vector3, c: Color, uv2: Vector2) -> void:
		verts.append(p)
		normals.append(n)
		colors.append(c)
		uv2s.append(uv2)

	## A tube along [param pts] ([param radii]), its frame carried down it from
	## [param up0], flattened to [param flat] of its width in that direction;
	## [param paint] gives each vertex's colour from (t along it, angle round
	## it from its up, distance along it). UV2: [param from] plus the distance
	## along it, then that distance.
	func strand(pts: PackedVector3Array, radii: PackedFloat32Array, up0: Vector3, flat: float, sides: int,
			from: float, paint: Callable) -> void:
		var n := pts.size()
		var start := verts.size()
		var up := up0
		var dist := 0.0
		for i in n:
			var fwd := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
			if i > 0:
				dist += pts[i].distance_to(pts[i - 1])
			up = up - fwd * up.dot(fwd)
			if up.length_squared() < 1e-6:
				up = fwd.cross(Vector3.RIGHT if absf(fwd.x) < 0.9 else Vector3.UP)
			up = up.normalized()
			var side := fwd.cross(up)
			var t := float(i) / maxf(n - 1, 1)
			for j in sides + 1:
				var a := TAU * j / sides
				add(pts[i] + (up * cos(a) * flat + side * sin(a)) * radii[i],
					(up * cos(a) / maxf(flat, 0.05) + side * sin(a)).normalized(), paint.call(t, a, dist),
					Vector2(from + dist, dist))
		var row := sides + 1
		for i in n - 1:
			for j in sides:
				var a := start + i * row + j
				indices.append_array([a, a + row, a + 1, a + 1, a + row, a + row + 1])

	## A sheet drawn from both faces: [param rows] of points (along it, each
	## row across it), facing [param facing] (one per row) on its front;
	## [param paint] (row, point) its colour, [param uv2] (row, point) its UV2.
	func sheet(rows: Array[PackedVector3Array], facing: PackedVector3Array, paint: Callable, uv2: Callable) -> void:
		var w := rows[0].size()
		var ccw_out := (rows[1][0] - rows[0][0]).cross(rows[0][1] - rows[0][0]).dot(facing[0]) > 0.0
		for face in 2:
			var sgn := 1.0 if face == 0 else -1.0
			var start := verts.size()
			for i in rows.size():
				for k in w:
					add(rows[i][k] + facing[i] * 0.006 * sgn, facing[i] * sgn, paint.call(i, k), uv2.call(i, k))
			# Godot's front faces wind clockwise as seen.
			var use_a := (face == 0) != ccw_out
			for i in rows.size() - 1:
				for k in w - 1:
					var a := start + i * w + k
					if use_a:
						indices.append_array([a, a + w, a + 1, a + 1, a + w, a + w + 1])
					else:
						indices.append_array([a, a + 1, a + w, a + 1, a + w + 1, a + w])

	## An ellipsoid about [param c] with half-axes [param ax], [param ay],
	## [param az].
	func blob(c: Vector3, ax: Vector3, ay: Vector3, az: Vector3, color: Color, uv2: Vector2, sides: int,
			rings: int) -> void:
		if ax.cross(ay).dot(az) < 0.0:
			az = -az
		var start := verts.size()
		var inv := Basis(ax, ay, az).inverse().transposed()
		for i in rings + 1:
			var lat := lerpf(-PI * 0.5, PI * 0.5, float(i) / rings)
			for j in sides + 1:
				var lon := TAU * j / sides
				var u := Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon))
				add(c + ax * u.x + ay * u.y + az * u.z, (inv * u).normalized(), color, uv2)
		var row := sides + 1
		for i in rings:
			for j in sides:
				var a := start + i * row + j
				indices.append_array([a, a + 1, a + row, a + 1, a + row + 1, a + row])

	## [param mesh] (its first surface: vertices, normals, colours, UV2)
	## added as it is, moved by [param xf].
	func append_mesh(mesh: ArrayMesh, xf: Transform3D) -> void:
		var arrays := mesh.surface_get_arrays(0)
		var start := verts.size()
		var vs: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var ns: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var cs: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var us: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		for i in vs.size():
			add(xf * vs[i], (xf.basis * ns[i]).normalized(), cs[i], us[i])
		for q: int in arrays[Mesh.ARRAY_INDEX]:
			indices.append(start + q)

	func commit() -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_TEX_UV2] = uv2s
		arrays[Mesh.ARRAY_INDEX] = indices
		var out := ArrayMesh.new()
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return out
