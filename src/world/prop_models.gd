class_name PropModels
extends RefCounted
## Meshes for the scattered props, a few variants of each, drawn by
## prop.gdshader (and prop_net.gdshader for sea fans). Every mesh stands on
## its base at y = 0 with "up" away from the rock.
##
## Vertex data the shaders read:
## - COLOR: rgb albedo, a glow mask.
## - UV: x how far the current bends this point (0 at the base, 1 at the
##   top); y how far along its frond or tentacle it is, for its own stir.
## - UV2: x the part's phase.
## - CUSTOM0: xyz the part's root (the centre its patterns are drawn round);
##   w its surface (see the KIND constants).
## - CUSTOM1: xyz how far the point moves when the prop shuts (anemones
##   closing up, tubeworm plumes ducking into their tubes).

const PLAIN := 0.0
const POLYPS := 1.0
const MEANDER := 2.0
const RINGS := 3.0
const BONE := 4.0
const NET := 5.0
const GILLS := 6.0
const SPOTS := 7.0
const CRYSTAL := 8.0
const CRUST := 9.0
const MATRIX := 10.0
const PORES := 11.0


static func variants(id: StringName) -> Array[Mesh]:
	var out: Array[Mesh] = []
	match id:
		&"kelp":
			out = [_kelp(4, 11), _kelp(3, 23), _kelp(6, 37)]
		&"rock":
			out = [_boulder(5, 0.0), _boulder(9, 1.0), _stones(13)]
		&"coral":
			out = [_staghorn(11), _brain(17), _table(29), _sponges(41)]
		&"anemone":
			out = [_anemones([Vector4(0, 0, 0, 1.25)], 3), _anemones([Vector4(-0.25, 0, 0.05, 0.95),
				Vector4(0.3, 0, -0.1, 0.7), Vector4(0.05, 0, 0.32, 0.5)], 5)]
		&"fan":
			out = [_fan(31, 1.25, 1.35), _fan(43, 1.55, 0.95)]
		&"crystal":
			out = [_crystals(23, 9, 0.55, Vector2(0.5, 1.7)), _crystals(47, 16, 0.95, Vector2(0.3, 0.9)),
				_crystals(59, 4, 0.35, Vector2(0.4, 2.1))]
		&"mushroom":
			out = [_mushrooms(7, 5), _mushrooms(19, 8)]
		&"spine":
			out = [_ribcage(3), _tail(5)]
		&"tubeworm":
			out = [_tubeworms(31, 14, Vector2(0.6, 1.5)), _tubeworms(53, 8, Vector2(0.9, 1.9))]
		&"chimney":
			out = [_chimney(3), _chimney(8)]
	return out


# --- Kelp ----------------------------------------------------------------------

## Giant kelp: a holdfast gripping the rock, [param stipes] stalks, and up each
## one a blade on a gas bladder every third of a metre or so.
static func _kelp(stipes: int, seed_value: int) -> ArrayMesh:
	var k := PropKit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	k.sway_height = 6.0
	var hold := Color(0.24, 0.19, 0.08, 0.0)
	for i in 11:
		var a := TAU * i / 11.0 + rng.randf_range(-0.25, 0.25)
		var out := Vector3(cos(a), 0, sin(a))
		var reach := rng.randf_range(0.35, 0.55)
		k.tube(PackedVector3Array([Vector3(0, 0.3, 0), out * reach * 0.35 + Vector3(0, 0.16, 0),
			out * reach * 0.7 + Vector3(0, 0.03, 0), out * reach + Vector3(0, -0.06, 0)]),
			PackedFloat32Array([0.06, 0.045, 0.03, 0.012]), 5, func(_t: float, _a: float) -> Color: return hold)
	for s in stipes:
		var h := rng.randf_range(3.6, 6.6)
		var lean := Vector3(rng.randf_range(-0.8, 0.8), 0, rng.randf_range(-0.5, 0.5))
		var base := Vector3(rng.randf_range(-0.12, 0.12), 0.22, rng.randf_range(-0.12, 0.12))
		var pts := PackedVector3Array()
		var radii := PackedFloat32Array()
		var n := 14
		for i in n + 1:
			var t := float(i) / n
			pts.append(base + Vector3(0, t * h, 0) + lean * t * t
				+ Vector3(sin(t * 5.0 + s * 2.0) * 0.09, 0, cos(t * 4.0 + s) * 0.06))
			radii.append(lerpf(0.05, 0.026, t))
		k.tube(pts, radii, 5, func(t: float, _a: float) -> Color:
			return Color(0.3 + t * 0.08, 0.24 + t * 0.06, 0.09, 0.0))
		var y := 0.55
		var turn := rng.randf() * TAU
		while y < h - 0.25:
			var t := y / h
			var at := _along(pts, t)
			turn += rng.randf_range(1.9, 2.6)
			var length := rng.randf_range(1.2, 1.8) * lerpf(1.0, 0.6, t)
			_kelp_blade(k, rng, at, Vector3(cos(turn), 0, sin(turn)), length, rng.randf_range(0.11, 0.15))
			y += rng.randf_range(0.3, 0.45)
		# The growing tip: a curled blade at the top of the stalk.
		_kelp_blade(k, rng, pts[n], (lean + Vector3(0.3, 0, 0)).normalized(), 0.7, 0.16)
	return k.commit()


## One kelp blade: a gas bladder on the stalk at [param at], then a ruffled
## ribbon reaching out along [param out] and up.
static func _kelp_blade(k: PropKit, rng: RandomNumberGenerator, at: Vector3, out: Vector3, length: float,
		width: float) -> void:
	k.phase = rng.randf()
	k.root = at
	k.stir = 1.0
	var d := (out * 0.42 + Vector3.UP * 0.9).normalized()
	var bladder := at + d * 0.08
	k.blob(bladder, d * 0.085, out.cross(Vector3.UP).normalized() * 0.05, Vector3.UP.cross(d).cross(d).normalized() * 0.05,
		Color(0.5, 0.38, 0.13, 0.0), 5, 3, 0.05)
	var across := d.cross(Vector3.UP).normalized()
	if across.length_squared() < 0.01:
		across = Vector3.RIGHT
	var face := across.cross(d).normalized()
	var rows: Array[PackedVector3Array] = []
	var facing := PackedVector3Array()
	var segs := 7
	for i in segs + 1:
		var s := float(i) / segs
		# Rises, then droops as it lengthens, twisting a little.
		var p := bladder + d * 0.1 + d * length * s + Vector3.UP * (-0.12 * s * s * length) + out * 0.3 * s * s * length
		var w := width * sin(minf(s * 2.5, 1.0) * PI * 0.5 + 0.1) * (1.0 - s * s * 0.8)
		var twist := across.rotated(d, s * 0.7 + rng.randf_range(-0.1, 0.1))
		var ruffle := face * sin(s * 31.0 + rng.randf()) * 0.03 * minf(s * 3.0, 1.0)
		rows.append(PackedVector3Array([p - twist * w + ruffle, p + face * 0.012, p + twist * w - ruffle]))
		facing.append(face.rotated(d, s * 0.7))
	var paint := func(i: int, j: int) -> Color:
		var s := float(i) / segs
		var edge := 1.0 if j != 1 else 0.0
		return Color(0.36 + s * 0.06 + edge * 0.05, 0.27 + s * 0.07 + edge * 0.04, 0.1 + s * 0.03, 0.0)
	k.sheet(rows, facing, paint, func(i: int, _j: int) -> float: return 0.1 + 0.9 * float(i) / segs)
	k.stir = 0.0


# --- Coral -------------------------------------------------------------------

## Staghorn coral: thick branches forking up and out, their pale tips alive
## with polyps.
static func _staghorn(seed_value: int) -> ArrayMesh:
	var k := PropKit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	k.sway_height = 2.0
	k.surface = POLYPS
	for i in 7:
		var a := TAU * i / 7.0 + rng.randf_range(-0.3, 0.3)
		var dir := (Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.9, 1.4) + Vector3.UP).normalized()
		_coral_branch(k, rng, Vector3(cos(a) * 0.1, -0.05, sin(a) * 0.1), dir, rng.randf_range(0.38, 0.5), 0.1, 0)
	return k.commit()


static func _coral_branch(k: PropKit, rng: RandomNumberGenerator, from: Vector3, dir: Vector3, length: float,
		radius: float, depth: int) -> void:
	var pts := PackedVector3Array()
	var radii := PackedFloat32Array()
	var bend := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * 0.25
	var last := depth >= 3
	var n := 3 if not last else 4
	for i in n + 1:
		var t := float(i) / n
		pts.append(from + (dir + bend * t + Vector3.UP * 0.25 * t).normalized() * length * t)
		radii.append(lerpf(radius, radius * 0.72, t) if not last or t < 0.99 else radius * 0.4)
	k.root = from
	var tip_glow := 0.25 * depth
	k.tube(pts, radii, 6, func(t: float, _a: float) -> Color:
		var g := tip_glow * t + (smoothstep(0.6, 1.0, t) * 0.9 if last else 0.0)
		var pale := 0.08 * depth + t * 0.08
		return Color(0.78 + pale, 0.7 + pale, 0.66 + pale, g))
	if last:
		return
	var end := pts[n]
	var forks := 2 if rng.randf() < 0.75 else 3
	var spin := rng.randf() * TAU
	for f in forks:
		var a := spin + TAU * f / forks
		var d := (dir + Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.5, 0.9)).normalized()
		d = (d + Vector3.UP * 0.55).normalized()
		_coral_branch(k, rng, end - dir * radius * 0.5, d, length * rng.randf_range(0.7, 0.85), radius * 0.74, depth + 1)


## Brain coral: a grooved dome half sunk in the rock, a smaller one beside
## it, and a few stubby finger corals.
static func _brain(seed_value: int) -> ArrayMesh:
	var k := PropKit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	k.sway_height = 2.0
	k.surface = MEANDER
	k.root = Vector3(0, 0, 0)
	k.dome(Vector3(0, -0.12, 0), 0.75, 0.62, 22, 9, func(p: Vector3) -> Color:
		return Color(0.82, 0.78, 0.62, 0.15 + smoothstep(0.2, 0.55, p.y) * 0.2))
	k.root = Vector3(0.75, 0, 0.25)
	k.dome(Vector3(0.75, -0.06, 0.25), 0.36, 0.3, 16, 6, func(p: Vector3) -> Color:
		return Color(0.76, 0.8, 0.66, 0.2))
	k.surface = POLYPS
	for i in 5:
		var a := rng.randf_range(-1.2, 1.6)
		var base := Vector3(cos(a) * 0.85 - 0.3, -0.05, sin(a) * 0.7)
		var h := rng.randf_range(0.3, 0.55)
		var lean := Vector3(rng.randf_range(-0.2, 0.2), 1.0, rng.randf_range(-0.2, 0.2)).normalized()
		k.root = base
		k.tube(PackedVector3Array([base, base + lean * h * 0.5, base + lean * h, base + lean * (h + 0.06)]),
			PackedFloat32Array([0.075, 0.065, 0.06, 0.0]), 7, func(t: float, _a: float) -> Color:
				return Color(0.86, 0.72, 0.7, smoothstep(0.5, 1.0, t) * 0.8))
	return k.commit()


## Table coral: a broad lobed plate on a short trunk, a smaller tier below,
## and a few finger corals round the foot.
static func _table(seed_value: int) -> ArrayMesh:
	var k := PropKit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	k.sway_height = 2.0
	k.surface = POLYPS
	k.root = Vector3.ZERO
	k.tube(PackedVector3Array([Vector3(0, -0.1, 0), Vector3(0.02, 0.25, 0), Vector3(0.05, 0.55, 0.02)]),
		PackedFloat32Array([0.2, 0.13, 0.17]), 9, func(_t: float, _a: float) -> Color:
			return Color(0.72, 0.66, 0.6, 0.0))
	_plate(k, Vector3(0.05, 0.56, 0.02), 1.0, rng.randf() * TAU, 0.0)
	k.tube(PackedVector3Array([Vector3(0.1, 0.1, 0.05), Vector3(-0.3, 0.28, 0.1), Vector3(-0.45, 0.32, 0.12)]),
		PackedFloat32Array([0.1, 0.08, 0.07]), 7, func(_t: float, _a: float) -> Color:
			return Color(0.72, 0.66, 0.6, 0.0))
	_plate(k, Vector3(-0.5, 0.33, 0.12), 0.45, rng.randf() * TAU, 0.1)
	for i in 4:
		var a := rng.randf() * TAU
		var base := Vector3(cos(a) * 0.55, -0.05, sin(a) * 0.45)
		var h := rng.randf_range(0.2, 0.35)
		k.root = base
		k.tube(PackedVector3Array([base, base + Vector3(0.02, h, 0), base + Vector3(0.03, h + 0.05, 0)]),
			PackedFloat32Array([0.06, 0.05, 0.0]), 6, func(t: float, _a: float) -> Color:
				return Color(0.8, 0.7, 0.75, smoothstep(0.5, 1.0, t) * 0.7))
	return k.commit()


## A flat coral plate of [param radius] round [param c], its rim lobed and
## lifted, polyps glowing at its edge.
static func _plate(k: PropKit, c: Vector3, radius: float, spin: float, tilt: float) -> void:
	var sides := 30
	var rings := 6
	k.root = c
	for face in 2:
		var start := k.verts.size()
		for i in rings + 1:
			var r := float(i) / rings
			for j in sides + 1:
				var a := TAU * j / sides
				var lobe := 1.0 + 0.13 * sin(a * 5.0 + spin) + 0.06 * sin(a * 11.0 + spin * 2.0)
				var rr := r * radius * lobe
				var y := 0.18 * radius * r * r + tilt * rr * cos(a) - 0.02 * face
				var p := c + Vector3(cos(a) * rr, y, sin(a) * rr)
				var n := Vector3(-cos(a) * 0.36 * r, 1.0, -sin(a) * 0.36 * r).normalized() * (1.0 if face == 0 else -1.0)
				k.add(p, n, Color(0.8 + r * 0.1, 0.72 + r * 0.08, 0.68 + r * 0.06, smoothstep(0.7, 1.0, r) * 0.9),
					0.0)
		var row := sides + 1
		for i in rings:
			for j in sides:
				var a := start + i * row + j
				k.quad(a, a + 1, a + row + 1, a + row)
	# The rim, joining the two faces.
	var rim := PackedVector3Array()
	for j in sides + 1:
		var a := TAU * j / sides
		var lobe := 1.0 + 0.13 * sin(a * 5.0 + spin) + 0.06 * sin(a * 11.0 + spin * 2.0)
		rim.append(c + Vector3(cos(a) * radius * lobe, 0.18 * radius + tilt * radius * lobe * cos(a), sin(a) * radius * lobe))
	var start := k.verts.size()
	for j in sides + 1:
		var out := (rim[j] - c) * Vector3(1, 0, 1)
		k.add(rim[j], out.normalized(), Color(0.95, 0.85, 0.8, 1.0), 0.0)
		k.add(rim[j] - Vector3(0, 0.025, 0), out.normalized(), Color(0.95, 0.85, 0.8, 1.0), 0.0)
	for j in sides:
		var a := start + j * 2
		k.quad(a, a + 2, a + 3, a + 1)


## Barrel sponges: open-mouthed vases of different sizes.
static func _sponges(seed_value: int) -> ArrayMesh:
	var k := PropKit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	k.sway_height = 2.0
	k.surface = PORES
	var spots := [Vector4(0, 0, 0, 1.0), Vector4(0.55, 0, 0.2, 0.65), Vector4(-0.45, 0, -0.15, 0.5)]
	for s: Vector4 in spots:
		var base := Vector3(s.x, -0.05, s.z)
		var size := s.w
		var lean := Vector3(rng.randf_range(-0.15, 0.15), 1.0, rng.randf_range(-0.15, 0.15)).normalized()
		k.root = base
		var outer := PackedVector3Array()
		var radii := PackedFloat32Array()
		var prof := [0.16, 0.24, 0.3, 0.32, 0.31, 0.3]
		for i in prof.size():
			var t := float(i) / (prof.size() - 1)
			outer.append(base + lean * t * 0.95 * size)
			radii.append(prof[i] * size)
		var flesh := func(_t: float, a: float) -> Color:
			var ridge := 0.04 * sin(a * 7.0)
			return Color(0.78 + ridge, 0.6 + ridge, 0.55, 0.0)
		k.tube(outer, radii, 14, flesh, func(_t: float, a: float) -> float: return 1.0 + 0.06 * sin(a * 7.0))
		# The lip, folding over into the dark inside.
		var top := base + lean * 0.95 * size
		var inner := PackedVector3Array([top, top + lean * 0.03 * size, top - lean * 0.08 * size, top - lean * 0.6 * size])
		k.tube(inner, PackedFloat32Array([0.3 * size, 0.27 * size, 0.24 * size, 0.18 * size]), 14,
			func(t: float, _a: float) -> Color:
				return Color(0.8 - t * 0.6, 0.62 - t * 0.5, 0.56 - t * 0.45, 0.3 * (1.0 - t)))
	return k.commit()


# --- Anemones ----------------------------------------------------------------

## Anemones at [param spots] (x, y, z, size): a ridged column, a striped
## oral disc and three rings of tentacles with glowing tips, which fold in
## when the sub comes near.
static func _anemones(spots: Array, seed_value: int) -> ArrayMesh:
	var k := PropKit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	k.sway_height = 1.0
	var column := func(t: float, a: float) -> Color:
		var stripe := 0.5 + 0.5 * sin(a * 8.0)
		return Color(0.3 + stripe * 0.2, 0.22 + stripe * 0.12, 0.3 + stripe * 0.06, 0.0) * (0.6 + t * 0.4)
	var tentacle := func(t: float, _a: float) -> Color:
		return Color(0.8 + t * 0.18, 0.62 + t * 0.25, 0.72 + t * 0.2, smoothstep(0.45, 1.0, t))
	for s: Vector4 in spots:
		var base := Vector3(s.x, -0.04, s.z)
		var size := s.w
		var top := base + Vector3(0, 0.2 * size, 0)
		# Shut, it squats into a fat column, its rim drawn in like a purse.
		var shut_top := base + Vector3(0, 0.15 * size, 0)
		var pursed := 0.38
		k.root = base
		k.tube_shutting(
			PackedVector3Array([base, base + Vector3(0, 0.03, 0) * size, base + Vector3(0, 0.1, 0) * size, top]),
			PackedFloat32Array([0.24 * size, 0.19 * size, 0.165 * size, 0.2 * size]),
			PackedVector3Array([base, base + Vector3(0, 0.035, 0) * size, base + Vector3(0, 0.1, 0) * size, shut_top]),
			PackedFloat32Array([0.25 * size, 0.215 * size, 0.19 * size, 0.2 * size * pursed]), 16, column,
			func(_t: float, a: float) -> float: return 1.0 + 0.05 * sin(a * 16.0))
		# The oral disc, its mouth at the centre, drawn in with the rim.
		var purse := Basis.from_scale(Vector3(pursed, 1.0, pursed))
		k.shut = Transform3D(purse, shut_top - purse * top)
		k.disc(top, 0.205 * size, 18, 3, Vector3.UP, func(r: float, a: float) -> Color:
			var ray := 0.5 + 0.5 * cos(a * 9.0)
			return Color(0.8 + ray * 0.15, 0.62 + ray * 0.15, 0.6, 0.3 + ray * 0.4 * r))
		k.shut = Transform3D.IDENTITY
		# Rings of tentacles, the inner ones upright, the outer ones arching out.
		var rings := [[0.06, 12, 0.4, 0.2], [0.1, 17, 0.48, 0.5], [0.14, 22, 0.54, 0.8], [0.18, 27, 0.56, 1.1]]
		for ring: Array in rings:
			var count := int(ring[1] * clampf(size, 0.6, 1.0))
			var spread: float = ring[3]
			for i in count:
				var a: float = TAU * (i + rng.randf_range(-0.25, 0.25)) / count + float(ring[0]) * 9.0
				var out := Vector3(cos(a), 0, sin(a))
				var length: float = ring[2] * size * rng.randf_range(0.85, 1.15)
				var root := top + out * float(ring[0]) * size + Vector3(0, 0.01, 0)
				var curl := rng.randf_range(0.7, 1.3)
				var lift := rng.randf_range(0.5, 1.0)
				var pts := PackedVector3Array()
				var radii := PackedFloat32Array()
				# Shut, each one is drawn down inside the column, out of sight.
				var tucked := PackedVector3Array()
				var tucked_radii := PackedFloat32Array()
				var p := root
				var q := shut_top + out * float(ring[0]) * size * pursed - Vector3(0, 0.01, 0)
				var down := (Vector3.DOWN * 0.8 - out * 0.4).normalized()
				for j in 6:
					var t := j / 5.0
					pts.append(p)
					var r := (0.019 - 0.005 * t + 0.004 * smoothstep(0.7, 0.95, t)) * size if j < 5 else 0.007 * size
					radii.append(r)
					tucked.append(q)
					tucked_radii.append(r * 0.7)
					# Out from the disc, then arching over, the tip lifting again.
					var bend := spread * curl * sin(t * PI * 0.8)
					var heading := (Vector3.UP * (1.0 - bend * 0.8 + lift * t * t * 0.6) + out * (0.25 + bend)).normalized()
					p += heading * length / 5.0
					q += down * 0.02 * size
				k.phase = rng.randf()
				k.stir = 1.0
				k.tube_shutting(pts, radii, tucked, tucked_radii, 4, tentacle)
		k.stir = 0.0
	return k.commit()


# --- Sea fans ----------------------------------------------------------------

## Gorgonian sea fan: a gently cupped net, [param width] across its spread
## and [param height] tall, held up by a trunk and forking branches.
static func _fan(seed_value: int, height: float, spread: float) -> ArrayMesh:
	var k := PropKit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	k.sway_height = height
	k.root = Vector3.ZERO
	var wobble := rng.randf() * TAU
	var at := func(a: float, r: float) -> Vector3:
		var reach := height * (1.0 - 0.42 * pow(a / spread, 2.0)) * (1.0 + 0.06 * sin(a * 9.0 + wobble))
		var rr := r * reach
		return Vector3(sin(a) * rr, 0.08 + cos(a) * rr, 0.14 * sin(a * 1.4 + wobble) * r * r + 0.04 * sin(r * 7.0 + a * 4.0))
	# The net.
	k.surface = NET
	var rows: Array[PackedVector3Array] = []
	var facing := PackedVector3Array()
	var cols := 18
	var steps := 11
	for i in steps + 1:
		var r := lerpf(0.12, 1.0, float(i) / steps)
		var row := PackedVector3Array()
		for j in cols + 1:
			var a := lerpf(-spread, spread, float(j) / cols)
			row.append(at.call(a, r))
		rows.append(row)
		facing.append(Vector3.BACK)
	var net := func(i: int, _j: int) -> Color: return Color(0.82, 0.72, 0.78, 0.15 + 0.5 * float(i) / steps)
	k.sheet(rows, facing, net, func(_i: int, _j: int) -> float: return 0.0)
	# The branches that hold it up, lying in it.
	k.surface = PLAIN
	k.tube(PackedVector3Array([Vector3(0, -0.05, 0), Vector3(0, 0.08, 0), at.call(0.0, 0.2)]),
		PackedFloat32Array([0.07, 0.055, 0.045]), 6, func(_t: float, _a: float) -> Color:
			return Color(0.6, 0.45, 0.5, 0.0))
	for b in 3:
		var a0 := lerpf(-spread * 0.55, spread * 0.55, b / 2.0) + rng.randf_range(-0.08, 0.08)
		_fan_branch(k, rng, at, a0, a0 * 0.15, 0.18, 0.3, 0.034, spread)
	return k.commit()


## A branch of the fan from (angle [param a_from], reach [param r0]) to
## (angle [param a0], reach [param r0] + [param span]), forking twice more
## towards the rim.
static func _fan_branch(k: PropKit, rng: RandomNumberGenerator, at: Callable, a0: float, a_from: float, r0: float,
		span: float, radius: float, spread: float) -> void:
	var pts := PackedVector3Array()
	var radii := PackedFloat32Array()
	var r1 := minf(r0 + span, 0.97)
	var n := 6
	for i in n + 1:
		var t := float(i) / n
		var a := lerpf(a_from, a0, smoothstep(0.0, 1.0, t)) + sin(t * 9.0 + a0 * 5.0) * 0.015
		var p: Vector3 = at.call(a, lerpf(r0, r1, t))
		pts.append(p + Vector3(0, 0, 0.012))
		radii.append(lerpf(radius, radius * 0.7, t))
	k.tube(pts, radii, 5, func(t: float, _a: float) -> Color:
		return Color(0.7, 0.55, 0.6, t * 0.3))
	if r1 >= 0.95 or radius < 0.008:
		return
	var fork := spread * 0.18 * (1.0 - r1 * 0.5)
	for side: float in [-1.0, 1.0]:
		var a := clampf(a0 + side * fork * rng.randf_range(0.6, 1.1), -spread * 0.97, spread * 0.97)
		_fan_branch(k, rng, at, a, a0, r1, (0.97 - r1) * rng.randf_range(0.45, 0.6) + 0.06, radius * 0.66, spread)


# --- Crystals ----------------------------------------------------------------

## A crystal cluster: [param count] six-sided points of [param lengths]
## sprouting from a rocky matrix, within [param spread] of upright.
static func _crystals(seed_value: int, count: int, spread: float, lengths: Vector2) -> ArrayMesh:
	var k := PropKit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	k.sway_height = 2.0
	k.surface = MATRIX
	k.root = Vector3.ZERO
	k.blob(Vector3(0, -0.12, 0), Vector3(0.42, 0, 0), Vector3(0, 0.22, 0), Vector3(0, 0, 0.36),
		Color(0.32, 0.3, 0.32, 0.0), 12, 6, 0.0, 0.25)
	k.surface = CRYSTAL
	for i in count:
		var tilt := spread * sqrt(rng.randf()) * (0.4 if i == 0 else 1.0)
		var spin := rng.randf() * TAU
		var axis := Vector3.UP.rotated(Vector3(cos(spin), 0, sin(spin)), tilt)
		var length := lerpf(lengths.y, lengths.x, sqrt(float(i) / count)) * rng.randf_range(0.8, 1.1)
		var radius := length * rng.randf_range(0.11, 0.16)
		var base := Vector3(rng.randf_range(-0.2, 0.2), -0.05, rng.randf_range(-0.18, 0.18))
		k.root = base
		k.phase = rng.randf()
		k.prism(base - axis * 0.08, axis, length, radius, rng.randf() * TAU, rng.randf_range(0.18, 0.3))
	return k.commit()


# --- Mushrooms ---------------------------------------------------------------

## A cluster of [param count] pale mushrooms with spotted caps and glowing
## gills underneath.
static func _mushrooms(seed_value: int, count: int) -> ArrayMesh:
	var k := PropKit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	k.sway_height = 1.6
	for i in count:
		var big := 1.0 if i == 0 else rng.randf_range(0.35, 0.8)
		var a := rng.randf() * TAU
		var base := Vector3.ZERO if i == 0 else Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.2, 0.5)
		base.y = -0.04
		var h := lerpf(0.35, 1.05, big)
		var cap := lerpf(0.16, 0.42, big)
		var lean := (Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.1, 0.35) * (0.0 if i == 0 else 1.0)
			+ Vector3.UP).normalized()
		var top := base + lean * h + Vector3(sin(a) * 0.04, 0, 0)
		var mid := base + lean * h * 0.5 + Vector3(sin(a + 1.0) * 0.04, 0, 0)
		k.phase = rng.randf()
		k.surface = PLAIN
		k.root = top
		k.tube(PackedVector3Array([base, base + lean * h * 0.12, mid, top]),
			PackedFloat32Array([cap * 0.34, cap * 0.26, cap * 0.18, cap * 0.2]), 9, func(t: float, _a: float) -> Color:
				return Color(0.62, 0.6, 0.6, 0.03 + t * 0.12))
		# A ragged ring round the stalk.
		var ring := base + lean * h * 0.72
		k.tube(PackedVector3Array([ring + lean * 0.02, ring - lean * 0.05]),
			PackedFloat32Array([cap * 0.2, cap * 0.34]), 10, func(_t: float, _a: float) -> Color:
				return Color(0.82, 0.8, 0.84, 0.2))
		var spin := rng.randf() * TAU
		k.surface = SPOTS
		k.cap(top, lean, cap, cap * rng.randf_range(0.5, 0.75), spin)
		k.surface = GILLS
		k.disc(top - lean * cap * 0.08, cap * 0.98, 24, 3, -lean, func(r: float, _a: float) -> Color:
			return Color(0.75, 0.75, 0.8, 0.35 + r * 0.65))
	return k.commit()


# --- Bones -------------------------------------------------------------------

## The ribcage of some enormous dead animal: its backbone half sunk in the
## floor, ribs arching up from both sides and raked back, some snapped short.
static func _ribcage(seed_value: int) -> ArrayMesh:
	var k := PropKit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	k.sway_height = 4.0
	k.surface = BONE
	var count := 7
	var spine := PackedVector3Array()
	for i in count:
		var x := lerpf(-2.6, 2.4, float(i) / (count - 1))
		spine.append(Vector3(x, 0.12 + 0.22 * (1.0 - pow(x / 2.8, 2.0)), -0.3))
	for i in count:
		_vertebra(k, rng, spine[i], Vector3.RIGHT, lerpf(0.75, 1.0, sin(PI * (i + 0.5) / count)))
		if i == 0 or i == count - 1:
			continue
		var size := sin(PI * float(i) / (count - 1))
		for side: float in [1.0, -1.0]:
			if rng.randf() < 0.12:
				continue
			var reach := lerpf(0.55, 1.0, size) * (2.0 if side > 0.0 else 1.7)
			var snapped := rng.randf_range(0.45, 0.7) if rng.randf() < 0.3 else 1.0
			_rib(k, spine[i] + Vector3(0, 0, 0.18 * side), side, reach, snapped)
	return k.commit()


## A sinuous tail of shrinking vertebrae arching out of the floor and back.
static func _tail(seed_value: int) -> ArrayMesh:
	var k := PropKit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	k.sway_height = 4.0
	k.surface = BONE
	var count := 13
	for i in count:
		var t := float(i) / (count - 1)
		var p := Vector3(lerpf(-2.2, 2.4, t), -0.25 + 1.7 * sin(t * PI * 0.92) - t * 0.4, 0.25 * sin(t * 4.0))
		var q := Vector3(lerpf(-2.2, 2.4, t + 0.01), -0.25 + 1.7 * sin((t + 0.01) * PI * 0.92) - (t + 0.01) * 0.4,
			0.25 * sin((t + 0.01) * 4.0))
		_vertebra(k, rng, p, (q - p).normalized(), lerpf(1.05, 0.45, t))
		if i % 3 == 1 and i < count - 2:
			_rib(k, p + Vector3(0, 0, 0.15), 1.0, lerpf(0.9, 0.4, t), rng.randf_range(0.5, 1.0))
	return k.commit()


## One vertebra at [param c] facing along [param along], [param size] its
## scale: a spool-shaped body, a spine up and back, and a wing to each side.
static func _vertebra(k: PropKit, rng: RandomNumberGenerator, c: Vector3, along: Vector3, size: float) -> void:
	var up := (Vector3.UP - along * along.dot(Vector3.UP)).normalized()
	var side := along.cross(up)
	var half := 0.24 * size
	var bone := func(t: float, _a: float) -> Color:
		return Color(0.86, 0.83, 0.74, 0.0)
	k.root = c
	k.tube(PackedVector3Array([c - along * half, c - along * half * 0.6, c + along * half * 0.6, c + along * half]),
		PackedFloat32Array([0.3 * size, 0.24 * size, 0.24 * size, 0.3 * size]), 10, bone)
	var tip := c + up * 0.55 * size - along * 0.18 * size
	k.tube(PackedVector3Array([c + up * 0.15 * size, c + up * 0.36 * size - along * 0.06 * size, tip]),
		PackedFloat32Array([0.14 * size, 0.1 * size, 0.06 * size]), 6, bone, Callable(), side, 0.45)
	for s: float in [1.0, -1.0]:
		var wing := c + side * s * 0.42 * size + up * 0.05 * size
		k.tube(PackedVector3Array([c + side * s * 0.15 * size, c + side * s * 0.32 * size, wing]),
			PackedFloat32Array([0.12 * size, 0.085 * size, 0.06 * size]), 6, bone, Callable(), up, 0.5)
	if rng.randf() < 0.3:
		# Bone-eating worms: a tuft of red fuzz.
		k.blob(c + up * 0.22 * size + side * 0.14 * size, Vector3(0.05, 0, 0) * size, Vector3(0, 0.035, 0) * size,
			Vector3(0, 0, 0.05) * size, Color(0.75, 0.18, 0.14, 0.6), 6, 3, 0.0, 0.3)


## A rib leaving the backbone at [param from] on [param side] (+z towards
## the camera): up, out and over, raked back; [param snapped] how much of it
## is left.
static func _rib(k: PropKit, from: Vector3, side: float, reach: float, snapped: float) -> void:
	var pts := PackedVector3Array()
	var radii := PackedFloat32Array()
	var n := 10
	for i in n + 1:
		var s := float(i) / n * snapped
		var phi := s * PI * 0.82
		pts.append(from + Vector3(-0.55 * reach * s * s, reach * sin(phi), side * reach * 0.55 * (1.0 - cos(phi))))
		radii.append(lerpf(0.17, 0.07, s) * (1.0 if i < n or snapped < 1.0 else 0.6))
	k.root = from
	var bone := func(t: float, _a: float) -> Color:
		var low := smoothstep(0.35, 0.0, t)
		return Color(0.86 - low * 0.2, 0.83 - low * 0.22, 0.74 - low * 0.22, 0.0)
	k.tube(pts, radii, 7, bone, Callable(), Vector3.RIGHT, 0.6)


# --- Vents -------------------------------------------------------------------

## A cluster of giant tubeworms: chitin tubes ringed with growth lines, and
## blood-red plumes that duck into them when the sub comes close.
static func _tubeworms(seed_value: int, count: int, heights: Vector2) -> ArrayMesh:
	var k := PropKit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	k.sway_height = 2.0
	for i in count:
		var a := rng.randf() * TAU
		var off := Vector3(cos(a), 0, sin(a)) * sqrt(rng.randf()) * 0.38
		var base := off + Vector3(0, -0.08, 0)
		var h := rng.randf_range(heights.x, heights.y) * (1.0 - off.length() * 0.6)
		var lean := (off * rng.randf_range(0.4, 0.9) + Vector3(rng.randf_range(-0.1, 0.1), 1.0, 0)).normalized()
		var bend := Vector3(rng.randf_range(-0.12, 0.12), 0, rng.randf_range(-0.12, 0.12))
		var pts := PackedVector3Array()
		var radii := PackedFloat32Array()
		for j in 7:
			var t := j / 6.0
			pts.append(base + lean * h * t + bend * t * t)
			radii.append(0.07 if j < 6 else 0.078)
		k.root = base
		k.surface = RINGS
		k.phase = rng.randf()
		k.tube(pts, radii, 8, func(t: float, _a: float) -> Color:
			var g := smoothstep(0.0, 0.5, t)
			return Color(0.42 + g * 0.46, 0.36 + g * 0.48, 0.3 + g * 0.48, 0.0))
		var mouth := pts[6]
		var axis := (pts[6] - pts[5]).normalized()
		k.root = mouth
		k.surface = PLAIN
		k.stir = 1.0
		# Shut, the plume draws together and slides down into the tube.
		var narrow := Basis.from_scale(Vector3.ONE * 0.6)
		k.shut = Transform3D(narrow, mouth - axis * 0.34 - narrow * mouth)
		_plume(k, rng, mouth, axis)
		k.shut = Transform3D.IDENTITY
		k.stir = 0.0
	return k.commit()


## A tubeworm's plume: a crown of red gill blades round a short stalk.
static func _plume(k: PropKit, rng: RandomNumberGenerator, mouth: Vector3, axis: Vector3) -> void:
	var side := axis.cross(Vector3.FORWARD if absf(axis.z) < 0.9 else Vector3.RIGHT).normalized()
	var red := func(t: float, _a: float) -> Color:
		return Color(0.85, 0.12 + t * 0.06, 0.08, 0.5 + t * 0.4)
	k.tube(PackedVector3Array([mouth - axis * 0.04, mouth + axis * 0.12, mouth + axis * 0.2]),
		PackedFloat32Array([0.05, 0.05, 0.02]), 6, red)
	var blades := 11
	var blade := func(i: int, _j: int) -> Color: return Color(0.8, 0.08, 0.07, 0.45 + 0.12 * i)
	for b in blades:
		var a := TAU * b / blades + rng.randf_range(-0.2, 0.2)
		var out := side.rotated(axis, a)
		var rows: Array[PackedVector3Array] = []
		var facing := PackedVector3Array()
		var across := axis.cross(out)
		for i in 5:
			var t := i / 4.0
			var p := mouth + axis * (0.02 + t * 0.24) + out * (0.025 + sin(t * PI * 0.75) * 0.05)
			var w := 0.04 * sin(minf(t * 1.3, 1.0) * PI * 0.5 + 0.2) * (1.0 - t * 0.5)
			rows.append(PackedVector3Array([p - across * w, p + across * w]))
			facing.append(out)
		k.sheet(rows, facing, blade, func(i: int, _j: int) -> float: return 0.25 + 0.75 * i / 4.0)


## A black smoker: a craggy mineral spire five metres tall with ledges down
## its sides, smaller spires at its foot, and hot cracks near its mouth.
static func _chimney(seed_value: int) -> ArrayMesh:
	var k := PropKit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	k.sway_height = 6.0
	k.surface = CRUST
	k.root = Vector3.ZERO
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 1.4
	var ledges := [rng.randf_range(1.0, 1.6), rng.randf_range(2.3, 3.0), rng.randf_range(3.5, 4.1)]
	_spire(k, noise, Vector3.ZERO, 5.0, 0.95, 0.34, ledges, Vector3(rng.randf_range(-0.15, 0.15), 0, 0))
	for i in 2:
		var a := rng.randf_range(-0.5, 0.5) + PI * i
		var at := Vector3(cos(a) * 0.75, 0, sin(a) * 0.45)
		_spire(k, noise, at, rng.randf_range(1.5, 2.6), 0.45, 0.16, [rng.randf_range(0.6, 1.0)],
			Vector3(cos(a) * 0.3, 0, 0))
	return k.commit()


static func _spire(k: PropKit, noise: FastNoiseLite, base: Vector3, h: float, r0: float, r1: float, ledges: Array,
		lean: Vector3) -> void:
	var pts := PackedVector3Array()
	var radii := PackedFloat32Array()
	var n := int(h * 6.0)
	for i in n + 1:
		var t := float(i) / n
		var y := t * h
		var r := lerpf(r0, r1, pow(t, 0.8))
		for l: float in ledges:
			r += 0.2 * r0 * exp(-pow((y - l) / 0.08, 2.0)) + 0.1 * r0 * exp(-pow((y - l + 0.18) / 0.2, 2.0))
		pts.append(base + Vector3(0, y - 0.3 * (1.0 - t), 0) + lean * t * t)
		radii.append(r)
	var top := pts[n]
	var crust := func(t: float, a: float) -> Color:
		var y := t * h
		var heat := smoothstep(h - 1.6, h, y)
		for l: float in ledges:
			heat = maxf(heat, exp(-pow((y - l + 0.05) / 0.12, 2.0)) * 0.6)
		var sulfide := clampf(noise.get_noise_2d(a * 2.0, y * 1.5) * 1.5 + 0.2, 0.0, 1.0)
		return Color(0.07 + sulfide * 0.22, 0.065 + sulfide * 0.12, 0.06 + sulfide * 0.03, heat)
	var craggy := func(t: float, a: float) -> float:
		var y := t * h
		var ledge := 0.0
		for l: float in ledges:
			ledge += exp(-pow((y - l) / 0.15, 2.0))
		# Ledges jut further on one side than the other.
		var lop := 1.0 + ledge * 0.35 * sin(a + y * 2.0)
		return (1.0 + noise.get_noise_3d(cos(a) * 1.5, y * 1.3, sin(a) * 1.5) * 0.3) * lop
	k.tube(pts, radii, 14, crust, craggy)
	# The mouth: a rim folding into the glowing throat.
	var axis := (pts[n] - pts[n - 1]).normalized()
	k.tube(PackedVector3Array([top, top + axis * 0.04, top - axis * 0.1, top - axis * 0.6]),
		PackedFloat32Array([radii[n], radii[n] * 0.85, radii[n] * 0.62, radii[n] * 0.4]), 14,
		func(t: float, _a: float) -> Color: return Color(0.25, 0.18, 0.12, 0.7 + t * 0.3))


# --- Rock --------------------------------------------------------------------

## A boulder: a lumpy ball, its underside flattened to sit on the floor;
## [param angular] cuts it with flat faces like a broken-off block.
static func _boulder(seed_value: int, angular: float) -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 1.6
	sphere.radial_segments = 26
	sphere.rings = 14
	var arrays := sphere.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.9
	noise.fractal_octaves = 4
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var cuts: Array[Plane] = []
	for i in 6:
		var n := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.3, 1), rng.randf_range(-1, 1)).normalized()
		cuts.append(Plane(n, rng.randf_range(0.55, 0.75)))
	for i in verts.size():
		var v := verts[i]
		v *= 1.0 + noise.get_noise_3dv(v * 1.3) * 0.42
		if angular > 0.0:
			for c in cuts:
				var over := c.distance_to(v)
				if over > 0.0:
					v -= c.normal * over * 0.92 * angular
		v.y = maxf(v.y, -0.55)
		verts[i] = v
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = null
	arrays[Mesh.ARRAY_TANGENT] = null
	var st := SurfaceTool.new()
	st.create_from_arrays(arrays)
	st.generate_normals()
	return MeshKit.painted(st.commit(), func(v: Vector3) -> Color:
		var g := 0.75 + noise.get_noise_3dv(v * 3.0) * 0.2
		return Color(g, g, g * 1.02, 0.0))


## A heap of three smaller stones.
static func _stones(seed_value: int) -> ArrayMesh:
	var a := _boulder(seed_value, 0.6)
	var b := _boulder(seed_value + 1, 0.0)
	var c := _boulder(seed_value + 2, 1.0)
	return MeshKit.merge([[a, Transform3D(Basis.from_scale(Vector3(0.7, 0.6, 0.65)), Vector3(-0.35, -0.12, 0))],
		[b, Transform3D(Basis(Vector3.UP, 1.0) * Basis.from_scale(Vector3(0.5, 0.45, 0.5)), Vector3(0.45, -0.2, 0.2))],
		[c, Transform3D(Basis(Vector3.UP, 2.0) * Basis.from_scale(Vector3(0.38, 0.4, 0.4)), Vector3(0.1, 0.25, -0.15))]])


# --- Helpers -----------------------------------------------------------------

## The point a fraction [param t] of the way up [param pts].
static func _along(pts: PackedVector3Array, t: float) -> Vector3:
	var f := clampf(t, 0.0, 1.0) * (pts.size() - 1)
	var i := mini(int(f), pts.size() - 2)
	return pts[i].lerp(pts[i + 1], f - i)
