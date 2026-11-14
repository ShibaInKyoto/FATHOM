class_name StalactiteModel
extends RefCounted
## A loose stalactite, in its own space (it hangs centred on the origin,
## the ceiling's face at y = [constant CEILING]): the plug of ceiling rock it
## grew from, cracked round its rim where it has come loose; the spike
## itself, shouldered, kneed where its growth paused, fluted where water ran
## down it, bending a little, ending in a thin straw; a lesser spike fused to
## its side; soda straws hanging round its root. Built in three sections (the
## root with the plug, the middle, the tip) that break apart when it
## shatters.
##
## Vertex data (for dripstone.gdshader): COLOR.r how far down the spike a
## point is (0 at the ceiling, 1 at the tip), COLOR.g a shade of its own
## (the flutes), COLOR.b the part (0 spike, 0.5 plug, 1 straw), COLOR.a how
## near the plug's crack.

const LENGTH := 3.6
const CEILING := 1.3
## Where the sections split (in y).
const SPLITS: Array[float] = [0.45, -0.6]
const VARIANTS := 3

static var _variants: Array = []


## The sections of variant [param k] (0 the root with its plug, 1 the
## middle, 2 the tip).
static func sections(k: int) -> Array[ArrayMesh]:
	if _variants.is_empty():
		for v in VARIANTS:
			_variants.append(_build(v))
	var out: Array[ArrayMesh] = []
	out.assign(_variants[k % VARIANTS])
	return out


static func _build(variant: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7001 + variant * 31
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 1.1
	var parts := [ModelBuilder.new(), ModelBuilder.new(), ModelBuilder.new()]
	var bend := Vector2(rng.randf_range(-0.12, 0.12), rng.randf_range(-0.08, 0.08))
	var knees := [rng.randf_range(0.28, 0.36), rng.randf_range(0.55, 0.65)]
	var spike := SpikeShape.new(Vector3(0.0, LENGTH * 0.5, 0.0), LENGTH, 0.5, bend, knees, noise, rng.randf() * 10.0)
	spike.build(parts, true)
	# A lesser spike fused to its root.
	var side_a := rng.randf() * TAU
	var side := SpikeShape.new(Vector3(cos(side_a) * 0.3, CEILING + 0.1, sin(side_a) * 0.3), LENGTH * 0.38, 0.2,
		Vector2(cos(side_a), sin(side_a)) * 0.15, [0.4], noise, rng.randf() * 10.0)
	side.build(parts, false)
	# The plug of ceiling rock, its crack round its rim.
	_plug(parts[0] as ModelBuilder, noise, rng)
	# Soda straws round the root.
	for k in 4:
		var a := TAU * (k + rng.randf_range(0.2, 0.8)) / 4.0
		var at := Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(0.48, 0.75) + Vector3(0.0, CEILING + 0.05, 0.0)
		var length := rng.randf_range(0.18, 0.5)
		(parts[0] as ModelBuilder).tube(PackedVector3Array([at, at - Vector3(0.0, length, 0.0)]),
			PackedFloat32Array([0.022, 0.016]), 6, Color(1.0, 0.5, 1.0, 0.0))
		(parts[0] as ModelBuilder).disc(at - Vector3(0.0, length, 0.0), Vector3.DOWN, 0.016,
			Color(1.0, 0.5, 1.0, 0.0), 6)
	var out := []
	for p: ModelBuilder in parts:
		out.append(p.commit())
	return out


## The plug of ceiling rock the spike hangs from: a closed, lumpy slab of
## rock whose underside stands a little out of the ceiling (ringed by the
## crack it is coming loose along) and whose broken top encloses the
## spike's root, so it reads as solid rock when it falls.
static func _plug(b: ModelBuilder, noise: FastNoiseLite, rng: RandomNumberGenerator) -> void:
	var around := 28
	var radius := rng.randf_range(0.7, 0.8)
	var thick := LENGTH * 0.5 - CEILING + 0.15
	var centre := Vector3(0.0, CEILING + thick * 0.4, 0.0)
	# Each ring: [radius fraction, height over the ceiling's face, crack]. The
	# top is a broken, lumpy dome of rock, narrower than the underside.
	var profile := [[0.0, -0.1, 0.0], [0.4, -0.08, 0.0], [0.72, -0.04, 0.2], [0.92, 0.0, 0.6], [1.0, 0.08, 1.0],
		[0.97, thick * 0.4, 0.6], [0.82, thick * 0.75, 0.0], [0.6, thick * 0.95, 0.0], [0.3, thick + 0.05, 0.0],
		[0.0, thick + 0.08, 0.0]]
	var jag := FastNoiseLite.new()
	jag.seed = rng.randi()
	jag.frequency = 2.2
	var rows := []
	var cols := []
	for ring: Array in profile:
		var row := PackedVector3Array()
		var crow := PackedColorArray()
		var f: float = ring[0]
		var upper := float(ring[1]) > thick * 0.9
		for j in around + 1:
			var a := TAU * (j % around) / around
			var d := Vector3(cos(a), 0.0, sin(a))
			var lump := 1.0 + noise.get_noise_2d(cos(a) * 3.0, sin(a) * 3.0) * 0.22
			# Broken faces above: bigger lumps, growing smoothly up the sides so
			# the rings never cross.
			lump += jag.get_noise_2d(d.x * 2.0, d.z * 2.0) * 0.18 * clampf(float(ring[1]) / thick, 0.0, 1.0)
			var r := radius * f * lump
			var y: float = CEILING + float(ring[1])
			y += jag.get_noise_2d(d.x * 3.0, d.z * 3.0) * (0.07 if upper else 0.03) * (1.0 - 0.5 * f)
			row.append(Vector3(cos(a) * r, y, sin(a) * r))
			crow.append(Color(0.0, 0.5, 0.5, ring[2]))
		rows.append(row)
		cols.append(crow)
	var start := b.verts.size()
	var count := rows.size()
	for i in count:
		var row: PackedVector3Array = rows[i]
		for j in row.size():
			var across := row[(j + 1) % around] - row[(j + around - 1) % around]
			var along: Vector3 = (rows[mini(i + 1, count - 1)] as PackedVector3Array)[j] \
				- (rows[maxi(i - 1, 0)] as PackedVector3Array)[j]
			var n := across.cross(along).normalized()
			if i == 0 or i == count - 1 or n == Vector3.ZERO:
				n = Vector3.DOWN if i == 0 else Vector3.UP
			if n.dot(row[j] - centre) < 0.0:
				n = -n
			b.add(row[j], n, (cols[i] as PackedColorArray)[j])
	var w := around + 1
	for i in count - 1:
		for j in around:
			var a := start + i * w + j
			b.quad(a, a + 1, a + w + 1, a + w)


## One spike: its profile, and the rows of it in each section.
class SpikeShape:
	extends RefCounted
	var top: Vector3
	var length: float
	var radius: float
	var bend: Vector2
	var knees: Array
	var noise: FastNoiseLite
	var shift: float

	func _init(top_at: Vector3, len_m: float, r: float, lean: Vector2, knee_at: Array, n: FastNoiseLite,
			seed_shift: float) -> void:
		top = top_at
		length = len_m
		radius = r
		bend = lean
		knees = knee_at
		noise = n
		shift = seed_shift

	## The centre of the spike [param t] of the way down it.
	func centre(t: float) -> Vector3:
		var sway := sin(t * PI) * 0.6 + t * t
		return top + Vector3(bend.x * sway * length * 0.25, -t * length, bend.y * sway * length * 0.25)

	## Its radius at [param t] round angle [param a], and how its flute shades it.
	func radius_at(t: float, a: float) -> Vector2:
		# Shouldered at the root, swelling at each knee, tapering to a straw.
		var r := radius * pow(1.0 - minf(t, 0.96), 1.35) * (1.0 + 0.25 * exp(-pow(t / 0.08, 2.0)))
		for k: float in knees:
			r *= 1.0 + 0.12 * exp(-pow((t - k) / 0.035, 2.0))
		r = maxf(r, radius * 0.045)
		var flute := sin(a * 8.0 + shift + noise.get_noise_2d(t * 5.0, shift) * 2.5)
		flute = signf(flute) * pow(absf(flute), 0.55)
		var depth := 0.13 * smoothstep(0.03, 0.2, t) * (1.0 - smoothstep(0.7, 0.9, t))
		var lump := 1.0 + noise.get_noise_3d(cos(a) * 1.4, t * length * 1.6 + shift, sin(a) * 1.4) * 0.14
		r *= lump * (1.0 + depth * flute)
		# Fine growth rings.
		r *= 1.0 + 0.025 * sin(t * length * 22.0 + shift)
		return Vector2(r, 0.5 + 0.5 * flute)

	## Adds the spike's rows to the section builders [param parts], split at
	## [constant SPLITS]; [param main] caps the breaks (the side spike lies
	## wholly in the root section).
	func build(parts: Array, main: bool) -> void:
		var rings := 64 if main else 24
		var around := 26 if main else 14
		var section := 0
		var rows := []
		var ts := PackedFloat32Array()
		for i in rings + 1:
			var t := float(i) / rings
			var c := centre(t)
			if main and section < SPLITS.size() and c.y < SPLITS[section]:
				_emit(parts[section], rows, ts, around)
				_cap(parts[section], rows[rows.size() - 1], c, true)
				# The next section starts on the same ring.
				var last: PackedVector3Array = rows[rows.size() - 1]
				var last_t := ts[ts.size() - 1]
				rows = [last]
				ts = PackedFloat32Array([last_t])
				section += 1
				_cap(parts[section], last, centre(last_t), false)
			var row := PackedVector3Array()
			for j in around + 1:
				var a := TAU * (j % around) / around
				var rr := radius_at(t, a)
				row.append(c + Vector3(cos(a), 0.0, sin(a)) * rr.x)
			rows.append(row)
			ts.append(t)
		_emit(parts[section], rows, ts, around)

	func _emit(b: ModelBuilder, rows: Array, ts: PackedFloat32Array, around: int) -> void:
		var start := b.verts.size()
		var count := rows.size()
		for i in count:
			var row: PackedVector3Array = rows[i]
			var c := centre(ts[i])
			for j in around + 1:
				var a := TAU * (j % around) / around
				var across: Vector3 = row[(j + 1) % around] - row[(j + around - 1) % around]
				var along: Vector3 = (rows[mini(i + 1, count - 1)] as PackedVector3Array)[j] \
					- (rows[maxi(i - 1, 0)] as PackedVector3Array)[j]
				var n := across.cross(along).normalized()
				if n.dot(row[j] - c) < 0.0:
					n = -n
				var shade := radius_at(ts[i], a).y
				b.add(row[j], n, Color(ts[i], shade, 0.0, 0.0))
		var w := around + 1
		for i in count - 1:
			for j in around:
				var a := start + i * w + j
				b.quad(a, a + 1, a + w + 1, a + w)

	## A rough cap over a break (hidden until it shatters).
	func _cap(b: ModelBuilder, ring: PackedVector3Array, c: Vector3, below: bool) -> void:
		var n := Vector3.DOWN if below else Vector3.UP
		var centre_i := b.add(c + n * 0.02, n, Color(0.5, 0.3, 0.0, 0.0))
		var first := b.verts.size()
		for p in ring:
			b.add(p, n, Color(0.5, 0.3, 0.0, 0.0))
		for k in ring.size() - 1:
			b.tri(centre_i, first + k, first + k + 1)
