class_name HullMesh
extends RefCounted
## Mesh builders for vehicles: smooth surfaces with true normals, UVs (copied
## into UV2) and tangents, so they can carry paint and normal maps.
## Vertex color R is how much paint is left (it wears off edges first) and G
## how clean the metal is (grime gathers in seams and crevices); 1 is pristine.


## A surface from [param fn] (func(u: float, v: float) -> Vector3, both 0..1)
## sampled on an [param nu] by [param nv] grid. Normals point along
## dP/du x dP/dv (pass [param flip] to turn them round). [param uv_fn]
## (func(u, v) -> Vector2) overrides the UVs; [param wear_fn]
## (func(u, v) -> Color) sets the vertex color.
static func surface(fn: Callable, nu: int, nv: int, flip := false, uv_fn: Callable = Callable(),
		wear_fn: Callable = Callable()) -> ArrayMesh:
	var row := nv + 1
	var pts := PackedVector3Array()
	pts.resize((nu + 1) * row)
	for i in nu + 1:
		for j in row:
			pts[i * row + j] = fn.call(float(i) / nu, float(j) / nv)
	var wrap_v := true
	var wrap_u := true
	for i in nu + 1:
		if pts[i * row].distance_squared_to(pts[i * row + nv]) > 1e-10:
			wrap_v = false
			break
	for j in row:
		if pts[j].distance_squared_to(pts[nu * row + j]) > 1e-10:
			wrap_u = false
			break
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	normals.resize(pts.size())
	tangents.resize(pts.size() * 4)
	var degenerate: Array[int] = []
	for i in nu + 1:
		for j in row:
			var du := pts[_wrap(i + 1, nu, wrap_u) * row + j] - pts[_wrap(i - 1, nu, wrap_u) * row + j]
			var dv := pts[i * row + _wrap(j + 1, nv, wrap_v)] - pts[i * row + _wrap(j - 1, nv, wrap_v)]
			var n := du.cross(dv)
			if flip:
				n = -n
			var k := i * row + j
			if n.length_squared() < 1e-14:
				degenerate.append(k)
				n = Vector3.UP
			normals[k] = n.normalized()
			_set_tangent(tangents, k, normals[k], du, dv)
	# Poles: take the average of the ring next to them.
	for k in degenerate:
		var i := k / row
		var near := i + 1 if i < nu else i - 1
		var sum := Vector3.ZERO
		for j in row:
			sum += normals[near * row + j]
		normals[k] = sum.normalized() if sum.length_squared() > 1e-10 else Vector3.UP
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	uvs.resize(pts.size())
	colors.resize(pts.size())
	for i in nu + 1:
		for j in row:
			var u := float(i) / nu
			var v := float(j) / nv
			uvs[i * row + j] = uv_fn.call(u, v) if uv_fn.is_valid() else Vector2(u, v)
			colors[i * row + j] = wear_fn.call(u, v) if wear_fn.is_valid() else Color.WHITE
	var indices := PackedInt32Array()
	for i in nu:
		for j in nv:
			var a := i * row + j
			_quad(indices, pts, normals, a, a + row, a + 1, a + row + 1)
	return _mesh(pts, normals, tangents, uvs, colors, indices)


## A body of revolution round the X axis from [param profile]: (x, radius)
## points traced with the outside on their left (along an outer face towards
## +X, inward across a front face, back along an inner face). A point given
## twice in a row is a hard edge; elsewhere the shading is smooth. Paint wears
## where the profile bends sharply.
static func lathe(profile: PackedVector2Array, sides := 24, wear := 1.0) -> ArrayMesh:
	var n := profile.size()
	var seg_n: Array[Vector2] = []
	for k in n - 1:
		var d := profile[k + 1] - profile[k]
		seg_n.append(Vector2(-d.y, d.x).normalized() if d.length_squared() > 1e-12 else Vector2.ZERO)
	var ring_p := PackedVector2Array()
	var ring_n := PackedVector2Array()
	var ring_w := PackedFloat32Array()
	var ring_u := PackedFloat32Array()
	var along := 0.0
	for k in n:
		if k > 0:
			along += profile[k].distance_to(profile[k - 1])
		var prev: Vector2 = seg_n[k - 1] if k > 0 else Vector2.ZERO
		var next: Vector2 = seg_n[k] if k < n - 1 else Vector2.ZERO
		var nrm: Vector2
		var bend := 0.0
		if k < n - 1 and next == Vector2.ZERO:
			nrm = prev
			bend = 1.0
		elif k > 0 and prev == Vector2.ZERO:
			nrm = next
			bend = 1.0
		elif prev == Vector2.ZERO or next == Vector2.ZERO:
			nrm = (prev + next).normalized()
		else:
			nrm = (prev + next).normalized()
			bend = clampf(absf(prev.angle_to(next)) / (PI / 3.0), 0.0, 1.0)
		ring_p.append(profile[k])
		ring_n.append(nrm)
		ring_w.append(bend * wear)
		ring_u.append(along)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var row := sides + 1
	tangents.resize(ring_p.size() * row * 4)
	for r in ring_p.size():
		var p := ring_p[r]
		var nr := ring_n[r]
		for s in row:
			var a := TAU * s / sides
			var c := cos(a)
			var si := sin(a)
			var k := verts.size()
			verts.append(Vector3(p.x, c * p.y, si * p.y))
			var nn := Vector3(nr.x, nr.y * c, nr.y * si).normalized()
			normals.append(nn)
			var t := Vector3(nr.y, -nr.x * c, -nr.x * si)
			_set_tangent(tangents, k, nn, t, Vector3(0.0, -si, c))
			uvs.append(Vector2(ring_u[r] / maxf(along, 1e-6), float(s) / sides))
			colors.append(Color(1.0 - ring_w[r], 1.0 - ring_w[r] * 0.3, 1.0))
	var indices := PackedInt32Array()
	for r in ring_p.size() - 1:
		if ring_p[r].distance_squared_to(ring_p[r + 1]) < 1e-12:
			continue
		for s in sides:
			var a := r * row + s
			_quad(indices, verts, normals, a, a + row, a + 1, a + row + 1)
	return _mesh(verts, normals, tangents, uvs, colors, indices)


## A box of [param size] with every edge rounded to [param radius].
static func rounded_box(size: Vector3, radius: float, segments := 2) -> ArrayMesh:
	var h := size * 0.5
	var r := minf(radius, minf(h.x, minf(h.y, h.z)) * 0.98)
	var inner := h - Vector3.ONE * r
	var coords: Array[PackedFloat32Array] = []
	for axis in 3:
		var list := PackedFloat32Array()
		for k in segments + 1:
			list.append(-h[axis] + r - r * cos(PI * 0.5 * k / segments))
		for k in range(segments, -1, -1):
			list.append(h[axis] - r + r * cos(PI * 0.5 * k / segments))
		coords.append(list)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for axis in 3:
		var b := (axis + 1) % 3
		var c := (axis + 2) % 3
		for sgn: float in [1.0, -1.0]:
			var base := verts.size()
			var lb := coords[b]
			var lc := coords[c]
			for i in lb.size():
				for j in lc.size():
					var q := Vector3.ZERO
					q[axis] = sgn * h[axis]
					q[b] = lb[i]
					q[c] = lc[j]
					var core := q.clamp(-inner, inner)
					var d := (q - core).normalized()
					var p := core + d * r
					verts.append(p)
					normals.append(d)
					var tb := Vector3.ZERO
					tb[b] = 1.0
					var tc := Vector3.ZERO
					tc[c] = 1.0
					tangents.resize(verts.size() * 4)
					_set_tangent(tangents, verts.size() - 1, d, tb, tc)
					uvs.append(Vector2(p[b], p[c]))
					var edge := smoothstep(0.97, 0.72, maxf(absf(d.x), maxf(absf(d.y), absf(d.z))))
					colors.append(Color(1.0 - edge, 1.0, 1.0))
			var cols := lc.size()
			for i in lb.size() - 1:
				for j in cols - 1:
					var a := base + i * cols + j
					_quad(indices, verts, normals, a, a + cols, a + 1, a + cols + 1)
	return _mesh(verts, normals, tangents, uvs, colors, indices)


## A round tube of [param radius] through [param points], its corners bent
## round with radius [param bend], capped at both ends unless [param open].
static func pipe(points: PackedVector3Array, radius: float, sides := 10, bend := 0.0, open := false) -> ArrayMesh:
	var path := _bent(points, bend) if bend > 0.0 else points
	var n := path.size()
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var fwd := (path[1] - path[0]).normalized()
	var side := fwd.cross(Vector3.UP)
	if side.length_squared() < 0.01:
		side = fwd.cross(Vector3.BACK)
	side = side.normalized()
	var along := 0.0
	var row := sides + 1
	for i in n:
		var dir: Vector3
		if i == 0:
			dir = path[1] - path[0]
		elif i == n - 1:
			dir = path[i] - path[i - 1]
		else:
			dir = (path[i + 1] - path[i]).normalized() + (path[i] - path[i - 1]).normalized()
		dir = dir.normalized()
		# Carry the frame along without twisting it.
		side = (side - dir * side.dot(dir)).normalized()
		var up := dir.cross(side).normalized()
		if i > 0:
			along += path[i].distance_to(path[i - 1])
		for s in row:
			var a := TAU * s / sides
			var out := side * cos(a) + up * sin(a)
			var k := verts.size()
			verts.append(path[i] + out * radius)
			normals.append(out)
			tangents.resize((k + 1) * 4)
			_set_tangent(tangents, k, out, dir, side * -sin(a) + up * cos(a))
			uvs.append(Vector2(along, float(s) / sides))
			colors.append(Color(1.0, 1.0, 1.0))
	for i in n - 1:
		for s in sides:
			var a := i * row + s
			_quad(indices, verts, normals, a, a + row, a + 1, a + row + 1)
	if not open:
		for end in 2:
			var i := 0 if end == 0 else n - 1
			var dir := (path[1] - path[0]).normalized() if end == 0 else (path[n - 1] - path[n - 2]).normalized()
			var nrm := -dir if end == 0 else dir
			var centre := verts.size()
			verts.append(path[i])
			normals.append(nrm)
			uvs.append(Vector2.ZERO)
			colors.append(Color.WHITE)
			tangents.resize(verts.size() * 4)
			_set_tangent(tangents, centre, nrm, side, nrm.cross(side))
			for s in row:
				verts.append(verts[i * row + s])
				normals.append(nrm)
				uvs.append(Vector2.ZERO)
				colors.append(Color(0.6, 1.0, 1.0))
				tangents.resize(verts.size() * 4)
				_set_tangent(tangents, verts.size() - 1, nrm, side, nrm.cross(side))
			for s in sides:
				_tri(indices, verts, nrm, centre, centre + 1 + s, centre + 2 + s)
	return _mesh(verts, normals, tangents, uvs, colors, indices)


## A fin or wing, its root on the XZ plane and its span up +Y: a rounded
## airfoil [param thickness] of its chord thick, from [param root] to
## [param tip] (each the x of its leading and trailing edge), rounded off at
## the tip. Edge curves below 1 bow an edge out early, above 1 late (a
## shark's dorsal fin is convex in front and hollow behind).
static func wing(root: Vector2, tip: Vector2, span: float, thickness := 0.12, rings := 10, sides := 20,
		le_curve := 1.0, te_curve := 1.0) -> ArrayMesh:
	var fn := func(u: float, v: float) -> Vector3:
		var le := lerpf(root.x, tip.x, pow(u, le_curve))
		var te := lerpf(root.y, tip.y, pow(u, te_curve))
		var phi := v * TAU
		var xi := 0.5 + 0.5 * cos(phi)
		var chord := absf(le - te)
		var round_tip := sqrt(maxf(1.0 - pow(u, 6.0), 0.0))
		var z := _naca(xi) * thickness * chord * round_tip * (1.0 if sin(phi) >= 0.0 else -1.0)
		return Vector3(lerpf(te, le, xi), u * span, z)
	var wear_fn := func(_u: float, v: float) -> Color:
		var edge := smoothstep(0.35, 0.5, absf(v - 0.5))
		return Color(1.0 - 0.6 * (1.0 - edge) * smoothstep(0.42, 0.5, 0.5 - absf(v - 0.5)) - 0.3 * edge, 1.0, 1.0)
	return surface(fn, rings, sides, true, Callable(), wear_fn)


## [param count] propeller blades round the X axis, from [param hub] out to
## [param radius]: twisted, raked airfoils that are wide at mid-span.
static func blades(count: int, hub: float, radius: float, chord: float, pitch := 0.9, skew := 0.25) -> ArrayMesh:
	var parts: Array = []
	for b in count:
		var fn := func(u: float, v: float) -> Vector3:
			var r := lerpf(hub * 0.9, radius, u)
			var width := chord * (0.55 + 0.9 * u * (1.0 - u) + 0.25 * u) * sqrt(maxf(1.0 - pow(u, 5.0), 0.0))
			var beta := atan2(pitch, TAU * maxf(r, 0.01))
			var phi := v * TAU
			var xi := 0.5 + 0.5 * cos(phi)
			var thick := _naca(xi) * 0.16 * width * (1.0 - 0.7 * u)
			var along := (xi - 0.4) * width + skew * chord * u * u
			var side := thick if sin(phi) >= 0.0 else -thick
			# Chord in the plane of rotation (Z) tilted towards the axis by beta.
			var cdir := Vector3(sin(beta), 0.0, cos(beta))
			var tdir := Vector3(cos(beta), 0.0, -sin(beta))
			return Vector3(0.0, r, 0.0) + cdir * along + tdir * side
		parts.append([surface(fn, 8, 16, false), Transform3D(Basis(Vector3.RIGHT, TAU * b / count), Vector3.ZERO)])
	return MeshKit.merge(parts)


## A ring of [param count] hex-headed bolts of radius [param size] on a
## circle of [param radius] in the YZ plane, facing +X.
static func bolt_ring(count: int, radius: float, size: float, phase := 0.0) -> ArrayMesh:
	var bolt := bolt_head(size)
	var parts: Array = []
	for i in count:
		var a := TAU * (i + phase) / count
		parts.append([bolt, Transform3D(Basis(), Vector3(0.0, cos(a) * radius, sin(a) * radius))])
	return MeshKit.merge(parts)


## One hex bolt head facing +X, its underside at x = 0.
static func bolt_head(size: float) -> ArrayMesh:
	return lathe(PackedVector2Array([Vector2(0.0, size * 1.25), Vector2(size * 0.15, size * 1.25),
		Vector2(size * 0.15, size * 1.25), Vector2(size * 0.15, size), Vector2(size * 0.15, size),
		Vector2(size * 0.6, size), Vector2(size * 0.75, size * 0.8), Vector2(size * 0.8, 0.0)]), 6, 1.0)


## Points along [param points] with each corner swapped for a curve.
static func _bent(points: PackedVector3Array, bend: float) -> PackedVector3Array:
	var out := PackedVector3Array([points[0]])
	for i in range(1, points.size() - 1):
		var p := points[i]
		var a := (p - points[i - 1])
		var b := (points[i + 1] - p)
		var turn := a.normalized().angle_to(b.normalized())
		if turn < 0.05:
			out.append(p)
			continue
		var t := minf(bend * tan(turn * 0.5), minf(a.length(), b.length()) * 0.49)
		var s := p - a.normalized() * t
		var e := p + b.normalized() * t
		var steps := maxi(3, int(turn / 0.2))
		for k in steps + 1:
			var f := float(k) / steps
			out.append(s.lerp(p, f).lerp(p.lerp(e, f), f))
	out.append(points[points.size() - 1])
	return out


## Half-thickness of a symmetric NACA airfoil at chord fraction [param x],
## for a 20% thick section (scaled by the caller).
static func _naca(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 5.0 * 0.2 * (0.2969 * sqrt(x) - 0.126 * x - 0.3516 * x * x + 0.2843 * x * x * x - 0.1036 * x * x * x * x)


static func _wrap(i: int, n: int, wrap: bool) -> int:
	if wrap:
		if i < 0:
			return n - 1
		if i > n:
			return 1
		return i
	return clampi(i, 0, n)


## Tangent along [param du] with the bitangent sign set so that "up" in a
## texture (falling v) runs against [param dv].
static func _set_tangent(tangents: PackedFloat32Array, k: int, n: Vector3, du: Vector3, dv: Vector3) -> void:
	var t := du - n * n.dot(du)
	if t.length_squared() < 1e-12:
		t = n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT)
	t = t.normalized()
	var w := 1.0 if n.cross(t).dot(-dv) >= 0.0 else -1.0
	tangents[k * 4] = t.x
	tangents[k * 4 + 1] = t.y
	tangents[k * 4 + 2] = t.z
	tangents[k * 4 + 3] = w


## Two triangles over a quad (a, b along one way, c, d the next row), wound
## to face the way their normals point (Godot's front faces are clockwise).
static func _quad(indices: PackedInt32Array, verts: PackedVector3Array, normals: PackedVector3Array,
		a: int, b: int, c: int, d: int) -> void:
	var n := normals[a] + normals[b] + normals[c] + normals[d]
	var g := (verts[b] - verts[a]).cross(verts[c] - verts[a])
	if g.length_squared() < 1e-16:
		g = (verts[d] - verts[b]).cross(verts[c] - verts[b])
	if g.dot(n) < 0.0:
		indices.append_array([a, b, c, b, d, c])
	else:
		indices.append_array([a, c, b, b, c, d])


static func _tri(indices: PackedInt32Array, verts: PackedVector3Array, n: Vector3, a: int, b: int, c: int) -> void:
	var g := (verts[b] - verts[a]).cross(verts[c] - verts[a])
	if g.dot(n) < 0.0:
		indices.append_array([a, b, c])
	else:
		indices.append_array([a, c, b])


static func _mesh(verts: PackedVector3Array, normals: PackedVector3Array, tangents: PackedFloat32Array,
		uvs: PackedVector2Array, colors: PackedColorArray, indices: PackedInt32Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
