class_name BodyKit
extends RefCounted
## Building blocks for creature models, in the creature shader's conventions
## (body along +X with the head forward, vertex color R the glow mask, G the
## belly blend and B how freely a part flutters, UV.x the point of the spine
## a vertex hangs from): a body lofted through cross-sections along the
## spine, fin membranes with rays, and rows of teeth.
## A fin, spine or tooth hangs from the spot where it meets the body, so when
## the body bends it turns with that section as one rigid piece instead of
## being bent along its own length (see [method placed]).

## A walking leg's mark in UV2.y (see [method legged]).
const LEG_MARK := 1000.0


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
	var uvs := PackedVector2Array()
	for i in rings + 1:
		var t := float(i) / rings
		# UV.y: the distance round the section from the back's midline, the same
		# on both flanks, so the skin's scales keep their size all round.
		var arcs := PackedFloat32Array([0.0])
		for j in sides:
			arcs.append(arcs[j] + grid[i][j].distance_to(grid[i][j + 1]))
		var full := arcs[sides]
		for j in sides + 1:
			var p := grid[i][j]
			uvs.append(Vector2(p.x, minf(arcs[j], full - arcs[j])))
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
	return _mesh(verts, normals, colors, indices, uvs)


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
	var uvs := PackedVector2Array()
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
				# Each ray hangs from where it meets the body.
				uvs.append(Vector2(base[c].x, 0.0))
		for r in rows:
			for c in cols - 1:
				var a := start + r * cols + c
				if side == 0:
					indices.append_array([a, a + cols, a + 1, a + 1, a + cols, a + cols + 1])
				else:
					indices.append_array([a, a + 1, a + cols, a + 1, a + cols + 1, a + cols])
	return _mesh(verts, normals, colors, indices, uvs)


## A spiny fin in the XY plane: rays from [param roots] to [param tips] (one
## each), with a membrane stretched between them that dips between each pair
## of rays by [param notch] of their length, ray tips standing
## [param tip_out] of their length beyond it. Rays and membrane are one mesh:
## they ripple together (vertex color B), and every part of a ray hangs from
## its root (UV.x), so nothing pokes through anything as the fin flutters or
## the body bends. [param glow] lights the rays towards their tips.
static func ray_fin(roots: PackedVector2Array, tips: PackedVector2Array, notch := 0.2, tip_out := 0.08,
		ray_radius := 0.035, thickness := 0.03, glow := 0.0, between := 3, rows := 7) -> ArrayMesh:
	var n := roots.size()
	var base := PackedVector2Array()
	var edge := PackedVector2Array()
	for i in n:
		var reach_i := (tips[i] - roots[i]) / (1.0 + tip_out)
		base.append(roots[i])
		edge.append(roots[i] + reach_i)
		if i == n - 1:
			break
		var reach_j := (tips[i + 1] - roots[i + 1]) / (1.0 + tip_out)
		for k in range(1, between + 1):
			var u := float(k) / (between + 1)
			var root := roots[i].lerp(roots[i + 1], u)
			var reach := reach_i.lerp(reach_j, u) * (1.0 - notch * sin(PI * u))
			base.append(root)
			edge.append(root + reach)
	var parts := [[membrane(base, edge, thickness, 0, 0.0, rows)]]
	for i in n:
		var dir := tips[i] - roots[i]
		var reach := dir.length() / (1.0 + tip_out)
		var pts := PackedVector3Array()
		var radii := PackedFloat32Array()
		for k in 7:
			var f := k / 6.0
			var p := roots[i] + dir * f
			pts.append(Vector3(p.x, p.y, 0.0))
			radii.append(ray_radius * lerpf(1.0, 0.18, f))
		var tube := ArrayMesh.new()
		MeshKit.tube(tube, pts, radii, 5)
		var root := roots[i]
		var unit := dir / maxf(dir.length(), 0.0001)
		tube = MeshKit.painted(tube, func(v: Vector3) -> Color:
			# How far out along the ray, as the membrane counts it (1 at its edge).
			var f := (Vector2(v.x, v.y) - root).dot(unit) / maxf(reach, 0.0001)
			return Color(glow * smoothstep(0.35, 1.0, f), 0.3, maxf(f, 0.02)))
		parts.append([tube, Transform3D.IDENTITY, root.x])
	return merged(parts)


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
## [param to] (model space), about [param length] long, each pointing along
## [param down] (a unit vector) with a little jitter so the row looks grown,
## not machined.
static func teeth_row(from: Vector3, to: Vector3, count: int, length: float, down: Vector3, seed_value := 1,
		fangs := true) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var parts := []
	for i in count:
		var f := (i + 0.5) / count
		var at := from.lerp(to, f)
		# Longest towards the front of the row (its end), a fang or two among
		# them; or (without [param fangs]) a fine, even comb.
		var l := length * rng.randf_range(0.8, 1.1)
		if fangs:
			l *= lerpf(0.45, 1.0, f) / 0.95
			if rng.randf() < 0.25 and f > 0.4:
				l *= 1.45
		var dir := (down.normalized() + Vector3(rng.randf_range(-0.12, 0.12), 0.0, rng.randf_range(-0.08, 0.08)))
		var basis := Basis(Quaternion(Vector3.DOWN, dir.normalized()))
		parts.append([tooth(l * 0.11, l, 0.22), Transform3D(basis, at)])
	return parts


## [param mesh] moved by [param xf], hanging from the spine at model X
## [param anchor]: a spine, tooth or bead given one turns as one rigid piece
## with the body there. Without one, a mesh from [method body] or
## [method membrane] keeps its own anchors (shifted with it) and any other
## mesh hangs each vertex from its own spot.
static func placed(mesh: Mesh, xf := Transform3D.IDENTITY, anchor := NAN) -> ArrayMesh:
	var out := ArrayMesh.new()
	var moved := MeshKit.transformed(mesh, xf)
	for si in moved.get_surface_count():
		var arrays := moved.surface_get_arrays(si)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var old: Variant = arrays[Mesh.ARRAY_TEX_UV]
		var uvs := PackedVector2Array()
		uvs.resize(verts.size())
		for i in verts.size():
			if not is_nan(anchor):
				uvs[i] = Vector2(anchor, 0.0)
			elif old != null and (old as PackedVector2Array).size() == verts.size():
				var o: Vector2 = (old as PackedVector2Array)[i]
				uvs[i] = Vector2(o.x + xf.origin.x, o.y)
			else:
				uvs[i] = Vector2(verts[i].x, 0.0)
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


## Bakes [param parts] ([mesh, transform, anchor], the last two optional; see
## [method placed]) into one mesh.
static func merged(parts: Array) -> ArrayMesh:
	var baked := []
	for part: Array in parts:
		var xf: Transform3D = part[1] if part.size() > 1 else Transform3D.IDENTITY
		baked.append([placed(part[0], xf, float(part[2]) if part.size() > 2 else NAN)])
	return MeshKit.merge(baked)


## A mesh that changes shape: [param from] as it stands, carrying the
## positions and normals of [param to] (built from the same parts in the same
## order, so vertex for vertex the same) for creature.gdshader to blend
## towards by its puff.
static func morph(from: ArrayMesh, to: ArrayMesh) -> ArrayMesh:
	var a := from.surface_get_arrays(0)
	var b := to.surface_get_arrays(0)
	var vb: PackedVector3Array = b[Mesh.ARRAY_VERTEX]
	var nb: PackedVector3Array = b[Mesh.ARRAY_NORMAL]
	assert((a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() == vb.size(), "morph targets differ")
	var c0 := PackedFloat32Array()
	var c1 := PackedFloat32Array()
	c0.resize(vb.size() * 4)
	c1.resize(vb.size() * 4)
	for i in vb.size():
		for k in 3:
			c0[i * 4 + k] = vb[i][k]
			c1[i * 4 + k] = nb[i][k]
	a[Mesh.ARRAY_CUSTOM0] = c0
	a[Mesh.ARRAY_CUSTOM1] = c1
	var flags := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
		| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a, [], {}, flags)
	return out


## [param mesh] (a leg, in model space) marked as a walking leg for
## creature.gdshader: hinged at [param hip], on side [param side] (+1 or -1)
## at [param phase] (radians) in the gait. It hangs from its hip's place on
## the spine. (UV2.y: the side times [constant LEG_MARK] plus the phase.)
static func legged(mesh: ArrayMesh, hip: Vector3, phase: float, side: float) -> ArrayMesh:
	var arrays := mesh.surface_get_arrays(0)
	var n := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	uv.resize(n)
	uv2.resize(n)
	uv.fill(Vector2(hip.x, hip.y))
	uv2.fill(Vector2(hip.z, side * (LEG_MARK + fposmod(phase, TAU))))
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


## The point on the skin of a body built from [param stations] at model x
## [param x], [param a] radians round from the back's midline (as
## [method body] lofts it).
static func surface(stations: Array, x: float, a: float) -> Vector3:
	var st := _station(stations, x)
	var c := cos(a)
	var r := st[1] if c >= 0.0 else st[2]
	var sc := signf(c) * pow(absf(c), 0.85)
	var ss := signf(sin(a)) * pow(absf(sin(a)), 0.85)
	return Vector3(x, st[3] + sc * r, ss * st[0])


## [param mesh] painted as enamel (teeth, claws): see creature.gdshader.
static func enamel(mesh: ArrayMesh) -> ArrayMesh:
	return MeshKit.painted(mesh, func(_v: Vector3) -> Color: return Color(0.0, 0.0, 0.0, 0.0))


## The Catmull-Rom interpolated [param stations] value [param field] (1 half
## width, 2 top, 3 bottom, 4 spine height) at [param x], for seating fins
## and spines on a body built by [method body].
static func at(stations: Array, x: float, field: int) -> float:
	return _station(stations, x)[field - 1]


static func _mesh(verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray,
		indices: PackedInt32Array, uvs := PackedVector2Array()) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	if not uvs.is_empty():
		arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
