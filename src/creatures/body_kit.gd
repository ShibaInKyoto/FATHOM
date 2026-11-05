class_name BodyKit
extends RefCounted
## Building blocks for creature models, in the creature shader's conventions
## (body along +X with the head forward, vertex color R the glow mask, G the
## belly blend and B how freely a part flutters):
## a body lofted through cross-sections along the spine, fin membranes with
## rays, and rows of teeth.


## A body lofted through [param stations], each [x, half width, height above
## the spine, depth below it, spine height] (x from tail to nose), smoothly
## interpolated into [param rings] sections of [param sides] sides each.
## [param glow] (optional) is called with (t along the body 0..1 from the
## tail, angle round it with 0 on top, position) for the glow mask.
static func body(stations: Array, rings := 48, sides := 24, glow: Callable = Callable()) -> ArrayMesh:
	var grid: Array[PackedVector3Array] = []
	var x0: float = stations[0][0]
	var x1: float = stations[stations.size() - 1][0]
	for i in rings + 1:
		var t := float(i) / rings
		var x := lerpf(x0, x1, t)
		var st := _station(stations, x)
		var ring := PackedVector3Array()
		for j in sides + 1:
			var a := TAU * j / sides
			var c := cos(a)
			var r := st[1] if c >= 0.0 else st[2]
			# A slightly squared section reads as muscle rather than tube.
			var sc := signf(c) * pow(absf(c), 0.85)
			var ss := signf(sin(a)) * pow(absf(sin(a)), 0.85)
			ring.append(Vector3(x, st[3] + sc * r, ss * st[0]))
		grid.append(ring)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for i in rings + 1:
		var t := float(i) / rings
		for j in sides + 1:
			var p := grid[i][j]
			var along := grid[mini(i + 1, rings)][j] - grid[maxi(i - 1, 0)][j]
			var round := grid[i][(j + 1) % sides] - grid[i][(j - 1 + sides) % sides]
			var n := round.cross(along).normalized()
			if n.length_squared() < 0.5:
				n = Vector3(0.0, cos(TAU * j / sides), sin(TAU * j / sides))
			verts.append(p)
			normals.append(n)
			var a := TAU * j / sides
			var g := 0.0 if glow.is_null() else float(glow.call(t, a, p))
			colors.append(Color(g, smoothstep(0.1, -0.7, cos(a)), 0.0))
	var indices := PackedInt32Array()
	var row := sides + 1
	for i in rings:
		for j in sides:
			var a := i * row + j
			indices.append_array([a, a + row, a + 1, a + 1, a + row, a + row + 1])
	return _mesh(verts, normals, colors, indices)


## The body's section at [param x]: half width, height above and depth below
## the spine, and the spine's height (Catmull-Rom through the stations).
static func _station(stations: Array, x: float) -> PackedFloat32Array:
	var n := stations.size()
	var k := 0
	while k < n - 2 and x > float(stations[k + 1][0]):
		k += 1
	var a: Array = stations[maxi(k - 1, 0)]
	var b: Array = stations[k]
	var c: Array = stations[k + 1]
	var d: Array = stations[mini(k + 2, n - 1)]
	var t := clampf((x - float(b[0])) / maxf(float(c[0]) - float(b[0]), 0.0001), 0.0, 1.0)
	var out := PackedFloat32Array()
	for f in range(1, 5):
		var v := _catmull(float(a[f]), float(b[f]), float(c[f]), float(d[f]), t)
		out.append(maxf(v, 0.002) if f < 4 else v)
	return out


static func _catmull(p0: float, p1: float, p2: float, p3: float, t: float) -> float:
	var t2 := t * t
	return 0.5 * (2.0 * p1 + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (3.0 * p1 - p0 - 3.0 * p2 + p3) * t2 * t)


## A fin membrane in the XY plane: from [param base] (where it meets the
## body) out to [param edge] (its free edge), the two lines with as many
## points each. It is pleated along [param rays] spines, thin at the edge,
## and flutters more the further out (vertex color B). [param glow] lights
## its outer edge.
static func membrane(base: PackedVector2Array, edge: PackedVector2Array, thickness := 0.05, rays := 0,
		glow := 0.0, rows := 6) -> ArrayMesh:
	var cols := base.size()
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for side in 2:
		var sgn := 1.0 if side == 0 else -1.0
		var start := verts.size()
		for r in rows + 1:
			var f := float(r) / rows
			for c in cols:
				var p := base[c].lerp(edge[c], f)
				# Pleats along the rays, fading out at the edge.
				var pleat := 0.0
				if rays > 0:
					pleat = absf(sin(PI * rays * c / maxf(cols - 1, 1))) * (1.0 - f * 0.6)
				var z := sgn * thickness * 0.5 * (1.0 - f * 0.7) + pleat * thickness * 0.6
				verts.append(Vector3(p.x, p.y, z))
				var tilt := cos(PI * rays * c / maxf(cols - 1, 1)) * 0.35 if rays > 0 else 0.0
				normals.append(Vector3(tilt * sgn, 0.0, sgn).normalized())
				colors.append(Color(glow * smoothstep(0.6, 1.0, f), 0.3, maxf(f, 0.02)))
		for r in rows:
			for c in cols - 1:
				var a := start + r * cols + c
				if side == 0:
					indices.append_array([a, a + cols, a + 1, a + 1, a + cols, a + cols + 1])
				else:
					indices.append_array([a, a + 1, a + cols, a + 1, a + cols + 1, a + cols])
	return _mesh(verts, normals, colors, indices)


## A curved tooth from its root at the origin, [param length] long, pointing
## down -Y and curving back (-X) towards its tip.
static func tooth(radius: float, length: float, curve := 0.25, sides := 5) -> ArrayMesh:
	var pts := PackedVector3Array()
	var radii := PackedFloat32Array()
	for i in 5:
		var f := i / 4.0
		pts.append(Vector3(-curve * length * f * f, -length * f, 0.0))
		radii.append(radius * (1.0 - f * 0.92))
	var mesh := ArrayMesh.new()
	MeshKit.tube(mesh, pts, radii, sides)
	return mesh


## A row of [param count] teeth along a jaw line from [param from] to
## [param to] (model space), [param length] long at the middle of the row and
## shorter at its ends, each pointing along [param down] (a unit vector) with
## a little jitter so the row looks grown, not machined.
static func teeth_row(from: Vector3, to: Vector3, count: int, length: float, down: Vector3, seed_value := 1) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var parts := []
	for i in count:
		var f := (i + 0.5) / count
		var at := from.lerp(to, f)
		var l := length * (0.55 + 0.45 * sin(PI * f)) * rng.randf_range(0.75, 1.15)
		var dir := (down + Vector3(rng.randf_range(-0.15, 0.15), 0.0, rng.randf_range(-0.1, 0.1))).normalized()
		var basis := Basis(Quaternion(Vector3.DOWN, dir))
		parts.append([tooth(l * 0.16, l, 0.2), Transform3D(basis, at)])
	return parts


## [param mesh] painted as enamel (teeth, claws): see creature.gdshader.
static func enamel(mesh: ArrayMesh) -> ArrayMesh:
	return MeshKit.painted(mesh, func(_v: Vector3) -> Color: return Color(0.0, 0.0, 0.0, 0.0))


## The Catmull-Rom interpolated [param stations] value [param field] (1 half
## width, 2 top, 3 bottom, 4 spine height) at [param x], for seating fins
## and spines on a body built by [method body].
static func at(stations: Array, x: float, field: int) -> float:
	return _station(stations, x)[field - 1]


static func _mesh(verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray,
		indices: PackedInt32Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
