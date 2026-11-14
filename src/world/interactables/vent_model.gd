class_name VentModel
extends RefCounted
## A thermal vent, in its holder's space (+Y out of the floor, Z across the
## cave towards the camera): a mound of sulfide rock settled into the floor's
## rise behind the play plane, a main chimney ringed with the ledges that
## grow as it vents, two lesser spires leaning off it, each throat glowing,
## and clusters of tube worms round the foot.
##
## COLOR.a is each part's material, for vent.gdshader: 0 the mound, 0.2 a
## chimney (COLOR.r how far up it a point is), 0.4 a glowing throat, 0.6 a
## worm's tube, 0.8 a worm's plume.

const MOUND := 0.0
const CHIMNEY := 0.2
const THROAT := 0.4
const TUBE := 0.6
const PLUME := 0.8
## The main chimney's foot and height (its throat is where the column rises).
const MAIN_AT := Vector3(0.05, 0.0, -0.35)
const MAIN_HEIGHT := 1.55


## The vent's mesh; [param sink] how far its holder sits out of the floor.
static func build(rng: RandomNumberGenerator, sink: float) -> ArrayMesh:
	var b := ModelBuilder.new()
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 1.6
	var floor_at := func(z: float) -> float: return PropScatter.surface_offset(z) - sink
	_mound(b, noise, floor_at)
	var top: float = mound_height(MAIN_AT, floor_at)
	_chimney(b, noise, MAIN_AT + Vector3(0.0, top - 0.15, 0.0), MAIN_HEIGHT, 0.44, Vector2(0.06, -0.04))
	var spires := [[Vector3(-0.72, 0.0, 0.2), 0.75, 0.24, Vector2(-0.35, 0.1)],
		[Vector3(0.78, 0.0, 0.3), 0.5, 0.17, Vector2(0.4, 0.15)]]
	for s: Array in spires:
		var at: Vector3 = s[0]
		_chimney(b, noise, at + Vector3(0.0, mound_height(at, floor_at) - 0.1, 0.0), s[1], s[2], s[3])
	for k in 2:
		var centre := Vector3(-1.05 if k == 0 else 1.15, 0.0, 0.55 - k * 0.15)
		_worms(b, rng, centre, floor_at)
	return b.commit()


## The mound's height over the floor at [param p] (x, z), plus the floor's.
static func mound_height(p: Vector3, floor_at: Callable) -> float:
	var r := Vector2(p.x / 1.7, p.z / 1.35).length()
	return float(floor_at.call(p.z)) + 0.55 * pow(maxf(1.0 - r * r, 0.0), 1.3)


## A lumpy mound of sulfide, its edge sunk into the floor all round.
static func _mound(b: ModelBuilder, noise: FastNoiseLite, floor_at: Callable) -> void:
	var rings := 10
	var around := 36
	var rows := []
	for i in rings + 1:
		var r := float(i) / rings * 1.12
		var row := PackedVector3Array()
		for j in around + 1:
			var a := TAU * (j % around) / around
			var p := Vector3(cos(a) * r * 1.7, 0.0, sin(a) * r * 1.35)
			var lump := noise.get_noise_2d(p.x * 1.3, p.z * 1.3) * 0.14 * minf(r * 3.0, 1.0)
			p.y = mound_height(p, floor_at) + lump - 0.2 * smoothstep(0.9, 1.12, r)
			row.append(p)
		rows.append(row)
	b.grid(rows, _normals(rows, Vector3.UP), Color(0.0, 0.0, 0.0, MOUND))


## Normals of a grid of rows (each a closed ring), turned towards [param up].
static func _normals(rows: Array, up: Vector3) -> Array:
	var ns := []
	var count := rows.size()
	for i in count:
		var row: PackedVector3Array = rows[i]
		var w := row.size() - 1
		var nrow := PackedVector3Array()
		for j in w + 1:
			var across: Vector3 = row[(j + 1) % w] - row[(j + w - 1) % w]
			var along: Vector3 = (rows[mini(i + 1, count - 1)] as PackedVector3Array)[j] \
				- (rows[maxi(i - 1, 0)] as PackedVector3Array)[j]
			var n := across.cross(along).normalized()
			if n.dot(up) < 0.0:
				n = -n
			if along.length_squared() < 1e-8:
				n = up
			nrow.append(n)
		ns.append(nrow)
	return ns


## Normals of a tube's rings, turned out from each ring's centre.
static func _ring_normals(rows: Array, centres: PackedVector3Array) -> Array:
	var ns := []
	var count := rows.size()
	for i in count:
		var row: PackedVector3Array = rows[i]
		var w := row.size() - 1
		var nrow := PackedVector3Array()
		for j in w + 1:
			var across: Vector3 = row[(j + 1) % w] - row[(j + w - 1) % w]
			var along: Vector3 = (rows[mini(i + 1, count - 1)] as PackedVector3Array)[j] \
				- (rows[maxi(i - 1, 0)] as PackedVector3Array)[j]
			var n := across.cross(along).normalized()
			if n.dot(row[j] - centres[i]) < 0.0:
				n = -n
			nrow.append(n)
		ns.append(nrow)
	return ns


## A chimney from [param foot], [param height] tall and [param radius] wide
## at its foot, leaning by [param lean] (x, z per metre): tapering, lumpy,
## ringed with ledges, its throat open and glowing.
static func _chimney(b: ModelBuilder, noise: FastNoiseLite, foot: Vector3, height: float, radius: float,
		lean: Vector2) -> void:
	var rings := maxi(int(height / 0.07), 8)
	var around := 18
	var rows := []
	var centres := PackedVector3Array()
	for i in rings + 1:
		var t := float(i) / rings
		var c := foot + Vector3(lean.x * t * t * height, t * height, lean.y * t * t * height)
		centres.append(c)
		# Narrowing as it rises, then flaring a little into its lip; ledges
		# where it grew in fits.
		var r := radius * lerpf(1.0, 0.6, pow(t, 0.8)) * (1.0 + 0.15 * smoothstep(0.88, 1.0, t))
		var ledge := 0.07 * radius * pow(maxf(sin(t * height * 17.0 + foot.x * 5.0), 0.0), 6.0)
		var row := PackedVector3Array()
		for j in around + 1:
			var a := TAU * (j % around) / around
			var d := Vector3(cos(a), 0.0, sin(a))
			var lump := 1.0 + noise.get_noise_3dv(c * 2.0 + d * 1.5) * 0.25
			row.append(c + d * (r * lump + ledge))
		rows.append(row)
	var shade := []
	for i in rings + 1:
		shade.append(float(i) / rings)
	var start := b.verts.size()
	var ns := _ring_normals(rows, centres)
	for i in rows.size():
		var ring: PackedVector3Array = rows[i]
		for j in ring.size():
			b.add(ring[j], (ns[i] as PackedVector3Array)[j], Color(shade[i], 0.0, 0.0, CHIMNEY))
	var w := around + 1
	for i in rows.size() - 1:
		for j in around:
			var a := start + i * w + j
			b.quad(a, a + 1, a + w + 1, a + w)
	# The lip rolled over into the throat...
	var lip: PackedVector3Array = rows[rows.size() - 1]
	var top := centres[centres.size() - 1]
	var roll := []
	for k in 3:
		var ring := PackedVector3Array()
		var f: float = [1.05, 0.88, 0.7][k]
		var up: float = [0.03, 0.05, 0.0][k]
		for p in lip:
			ring.append(top + (p - top) * f + Vector3(0.0, up, 0.0))
		roll.append(ring)
	_rings(b, [lip] + roll, top + Vector3(0.0, -0.2, 0.0), Color(1.0, 0.0, 0.0, CHIMNEY), false)
	# ...and the throat glowing down inside it, following the chimney's lean.
	var throat := []
	var deepest := top
	for k in 3:
		var ring := PackedVector3Array()
		var f: float = [0.7, 0.6, 0.5][k]
		var down: float = [0.0, 0.18, 0.5][k]
		var c := centres[maxi(rings - int(down / height * rings), 0)]
		deepest = c
		for p in lip:
			ring.append(c + (p - top) * f)
		throat.append(ring)
	_rings(b, throat, deepest, Color(1.0, 0.0, 0.0, THROAT), true)
	b.disc(deepest + Vector3(0.0, 0.02, 0.0), Vector3.UP, radius * 0.3, Color(0.3, 0.0, 0.0, THROAT), 12)


## Joins [param rings] (closed loops of matching size) into a surface,
## facing away from [param axis_point] ([param inward]: towards it).
static func _rings(b: ModelBuilder, rings: Array, axis_point: Vector3, color: Color, inward: bool) -> void:
	var start := b.verts.size()
	var w: int = (rings[0] as PackedVector3Array).size()
	for i in rings.size():
		var ring: PackedVector3Array = rings[i]
		for j in w:
			var n := (ring[j] - axis_point).normalized()
			b.add(ring[j], -n if inward else n, color)
	for i in rings.size() - 1:
		for j in w - 1:
			var a := start + i * w + j
			b.quad(a, a + 1, a + w + 1, a + w)


## A cluster of tube worms round [param centre], rooted in the floor: white
## tubes, each crowned with a red plume.
static func _worms(b: ModelBuilder, rng: RandomNumberGenerator, centre: Vector3, floor_at: Callable) -> void:
	for k in 9:
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.0, 0.32)
		var root := centre + Vector3(cos(a) * r, 0.0, sin(a) * r * 0.8)
		root.y = mound_height(root, floor_at) - 0.08
		var length := rng.randf_range(0.28, 0.62)
		var lean := Vector3(rng.randf_range(-0.25, 0.25), 1.0, rng.randf_range(-0.2, 0.2)).normalized()
		var bend := Vector3(rng.randf_range(-0.12, 0.12), 0.0, rng.randf_range(-0.1, 0.1))
		var pts := PackedVector3Array()
		var radii := PackedFloat32Array()
		for i in 5:
			var t := i / 4.0
			pts.append(root + lean * length * t + bend * t * t)
			radii.append(lerpf(0.026, 0.021, t))
		b.tube(pts, radii, 7, Color(rng.randf_range(0.85, 1.0), 0.0, 0.0, TUBE))
		var tip := pts[4]
		var dir := (pts[4] - pts[3]).normalized()
		b.tube(PackedVector3Array([tip - dir * 0.01, tip + dir * 0.05, tip + dir * 0.1]),
			PackedFloat32Array([0.022, 0.045, 0.012]), 8, Color(rng.randf(), 0.0, 0.0, PLUME))
