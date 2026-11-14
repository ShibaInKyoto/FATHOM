class_name ModelBuilder
extends RefCounted
## Builds a model's mesh from rounded boxes, tubes, cylinders, tori and the
## like, every vertex coloured with its part's material (for the shader that
## draws it: see [DroneModel] and [StationModel]), every triangle wound to
## face the way its normals point.

var verts := PackedVector3Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()
var indices := PackedInt32Array()
var uvs := PackedVector2Array()
## Where the parts added next go: built in their own space, placed by this.
var xf := Transform3D.IDENTITY
## The UV the vertices added next carry (for parts whose shader wants one).
var uv := Vector2.ZERO
var _has_uv := false


func add(p: Vector3, n: Vector3, c: Color) -> int:
	verts.append(xf * p)
	normals.append((xf.basis * n).normalized())
	colors.append(c)
	uvs.append(uv)
	_has_uv = _has_uv or uv != Vector2.ZERO
	return verts.size() - 1


## A vertex carrying its own UV.
func add_uv(p: Vector3, n: Vector3, c: Color, at: Vector2) -> int:
	var keep := uv
	uv = at
	var i := add(p, n, c)
	uv = keep
	return i


## A triangle, wound so its front faces the way its vertices' normals point.
func tri(a: int, b: int, c: int) -> void:
	var n := normals[a] + normals[b] + normals[c]
	var cr := (verts[b] - verts[a]).cross(verts[c] - verts[a])
	# Godot's front faces wind clockwise as seen.
	if cr.dot(n) > 0.0:
		indices.append_array([a, c, b])
	else:
		indices.append_array([a, b, c])


func quad(a: int, b: int, c: int, d: int) -> void:
	tri(a, b, c)
	tri(a, c, d)


## A grid of rings (each [param cols] + 1 points, the last repeating the
## first) with normals [param ns], joined into a surface.
func grid(rows: Array, ns: Array, c: Color) -> void:
	var start := verts.size()
	var w: int = (rows[0] as PackedVector3Array).size()
	for i in rows.size():
		for j in w:
			add(rows[i][j], ns[i][j], c)
	for i in rows.size() - 1:
		for j in w - 1:
			var a := start + i * w + j
			quad(a, a + 1, a + w + 1, a + w)


## A rounded box: a superellipsoid of exponent [param e] (higher, squarer).
func rounded_box(c: Vector3, half: Vector3, e: float, color: Color, around: int, rings: int) -> void:
	var rows := []
	var ns := []
	for i in rings + 1:
		var lat := lerpf(-PI * 0.5, PI * 0.5, float(i) / rings)
		var row := PackedVector3Array()
		var nrow := PackedVector3Array()
		for j in around + 1:
			var lon := TAU * j / around
			var d := Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon))
			var k := pow(pow(absf(d.x), e) + pow(absf(d.y), e) + pow(absf(d.z), e), -1.0 / e)
			var u := d * k
			row.append(c + u * half)
			nrow.append(Vector3(signf(u.x) * pow(absf(u.x), e - 1.0) / half.x,
				signf(u.y) * pow(absf(u.y), e - 1.0) / half.y, signf(u.z) * pow(absf(u.z), e - 1.0) / half.z))
		rows.append(row)
		ns.append(nrow)
	grid(rows, ns, color)


func ellipsoid(c: Vector3, half: Vector3, color: Color, around: int, rings: int) -> void:
	rounded_box(c, half, 2.0, color, around, rings)


## A capsule from [param a] to [param b].
func capsule(a: Vector3, b: Vector3, r: float, color: Color) -> void:
	var axis := (b - a).normalized()
	var pts := PackedVector3Array()
	var radii := PackedFloat32Array()
	for k in 5:
		var t := k / 4.0
		pts.append(a - axis * r * cos(t * PI * 0.5))
		radii.append(r * maxf(sin(t * PI * 0.5), 0.01) if k < 4 else r)
	pts.append(b)
	radii.append(r)
	for k in range(1, 5):
		var t := k / 4.0
		pts.append(b + axis * r * sin(t * PI * 0.5))
		radii.append(r * maxf(cos(t * PI * 0.5), 0.01))
	tube(pts, radii, 16, color)


## A cylinder from [param a] to [param b], its ends capped.
func cylinder(a: Vector3, b: Vector3, r: float, color: Color, sides: int) -> void:
	tube(PackedVector3Array([a, b]), PackedFloat32Array([r, r]), sides, color)
	var axis := (b - a).normalized()
	disc(b, axis, r, color, sides)
	disc(a, -axis, r, color, sides)


## A flat disc of [param r] at [param c] facing [param n].
func disc(c: Vector3, n: Vector3, r: float, color: Color, sides: int) -> void:
	var u := n.cross(Vector3.FORWARD if absf(n.z) < 0.9 else Vector3.RIGHT).normalized()
	var v := n.cross(u)
	var centre := add(c, n, color)
	var first := verts.size()
	for k in sides:
		var a := TAU * k / sides
		add(c + (u * cos(a) + v * sin(a)) * r, n, color)
	for k in sides:
		tri(centre, first + k, first + (k + 1) % sides)


## A torus round [param c], its ring square to [param axis].
func torus(c: Vector3, axis: Vector3, major: float, minor: float, color: Color, around: int, sides: int) -> void:
	var u := axis.cross(Vector3.FORWARD if absf(axis.z) < 0.9 else Vector3.RIGHT).normalized()
	var v := axis.cross(u)
	var rows := []
	var ns := []
	for i in around + 1:
		var a := TAU * i / around
		var out := u * cos(a) + v * sin(a)
		var row := PackedVector3Array()
		var nrow := PackedVector3Array()
		for j in sides + 1:
			var b := TAU * j / sides
			var n := out * cos(b) + axis * sin(b)
			row.append(c + out * major + n * minor)
			nrow.append(n)
		rows.append(row)
		ns.append(nrow)
	grid(rows, ns, color)


## A tube along [param pts]; [param open_ends] leaves its ends uncapped
## (a duct); [param up0] and [param flat] flatten it across that direction.
func tube(pts: PackedVector3Array, radii: PackedFloat32Array, sides: int, color: Color, open_ends := false,
		up0 := Vector3.ZERO, flat := 1.0) -> void:
	var n := pts.size()
	var rows := []
	var ns := []
	var fwd0 := (pts[1] - pts[0]).normalized()
	var up := up0 if up0 != Vector3.ZERO else fwd0.cross(Vector3.FORWARD if absf(fwd0.z) < 0.9 else Vector3.RIGHT)
	for i in n:
		var fwd := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
		up = (up - fwd * up.dot(fwd)).normalized()
		var side := fwd.cross(up)
		var row := PackedVector3Array()
		var nrow := PackedVector3Array()
		for j in sides + 1:
			var a := TAU * j / sides
			row.append(pts[i] + (up * cos(a) * flat + side * sin(a)) * radii[i])
			nrow.append(up * cos(a) / flat + side * sin(a))
		rows.append(row)
		ns.append(nrow)
	grid(rows, ns, color)
	if open_ends:
		# The inside of the duct, seen through its mouth.
		var inner := []
		var inns := []
		for i in n:
			var row := PackedVector3Array()
			var nrow := PackedVector3Array()
			for j in sides + 1:
				var p: Vector3 = rows[i][j]
				row.append(pts[i] + (p - pts[i]) * 0.9)
				nrow.append(-(ns[i][j] as Vector3))
			inner.append(row)
			inns.append(nrow)
		grid(inner, inns, color)


## A tube round the closed loop [param loop] (its points in order, the
## first not repeated), [param axis] square to the loop's plane.
func ring_tube(loop: PackedVector3Array, axis: Vector3, r: float, sides: int, color: Color) -> void:
	var n := loop.size()
	var centre := Vector3.ZERO
	for p in loop:
		centre += p / n
	var rows := []
	var ns := []
	for i in n + 1:
		var p := loop[i % n]
		var fwd := (loop[(i + 1) % n] - loop[(i + n - 1) % n]).normalized()
		var out := (p - centre)
		out = (out - fwd * out.dot(fwd) - axis * out.dot(axis)).normalized()
		var row := PackedVector3Array()
		var nrow := PackedVector3Array()
		for j in sides + 1:
			var a := TAU * j / sides
			var d := out * cos(a) + axis * sin(a)
			row.append(p + d * r)
			nrow.append(d)
		rows.append(row)
		ns.append(nrow)
	grid(rows, ns, color)


## A beam of rectangular section from [param a] to [param b].
func beam(a: Vector3, b: Vector3, half: Vector2, color: Color) -> void:
	var fwd := (b - a).normalized()
	var side := fwd.cross(Vector3.BACK if absf(fwd.z) < 0.9 else Vector3.UP).normalized()
	var up := side.cross(fwd)
	box((a + b) * 0.5, fwd * a.distance_to(b) * 0.5, up * half.x, side * half.y, color)


## A box at [param c] with half-axes [param ax], [param ay], [param az].
func box(c: Vector3, ax: Vector3, ay: Vector3, az: Vector3, color: Color) -> void:
	for axis: Array in [[ax, ay, az], [ay, az, ax], [az, ax, ay]]:
		for sgn: float in [-1.0, 1.0]:
			var n: Vector3 = axis[0] * sgn
			var p0 := c + n
			var u: Vector3 = axis[1]
			var v: Vector3 = axis[2]
			var a := add(p0 - u - v, n, color)
			var b2 := add(p0 + u - v, n, color)
			var c2 := add(p0 + u + v, n, color)
			var d := add(p0 - u + v, n, color)
			quad(a, b2, c2, d)


## A thin flat plate through four points (both faces).
func plate(pts: Array, color: Color) -> void:
	var n: Vector3 = ((pts[1] as Vector3) - pts[0]).cross((pts[2] as Vector3) - pts[0]).normalized()
	for sgn: float in [1.0, -1.0]:
		var ids := []
		for p: Vector3 in pts:
			ids.append(add(p + n * 0.006 * sgn, n * sgn, color))
		quad(ids[0], ids[1], ids[2], ids[3])


func commit() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	if _has_uv:
		arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
