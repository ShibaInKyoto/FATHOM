class_name PropKit
extends RefCounted
## Builds one prop mesh for [PropModels], stamping each vertex with the part
## it belongs to (see PropModels for what the shaders read from it).

var verts := PackedVector3Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()
var uvs := PackedVector2Array()
var uv2s := PackedVector2Array()
var custom := PackedFloat32Array()
var shut_offsets := PackedFloat32Array()
var indices := PackedInt32Array()
## The height at which the current bends a point fully.
var sway_height := 1.0
## Stamped on the vertices added next: the part's phase, root and surface,
## and whether it stirs on its own (1).
var phase := 0.0
var root := Vector3.ZERO
var surface := 0.0
var stir := 0.0
## Where the vertices added next go when the prop shuts.
var shut := Transform3D.IDENTITY


## Adds a vertex [param along] its part (0 at its root, 1 at its tip).
## [param closed] is where it sits when the prop has shut; by default
## [member shut] moves it there.
func add(p: Vector3, n: Vector3, c: Color, along: float, closed := Vector3.INF) -> int:
	verts.append(p)
	normals.append(n)
	colors.append(c)
	uvs.append(Vector2(pow(clampf(p.y / sway_height, 0.0, 1.0), 1.5), along * stir))
	uv2s.append(Vector2(phase, 0.0))
	custom.append_array([root.x, root.y, root.z, surface])
	var to := (shut * p if closed == Vector3.INF else closed) - p
	shut_offsets.append_array([to.x, to.y, to.z, 0.0])
	return verts.size() - 1


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


## A tube along [param pts] with [param radii]; [param paint] (t along it,
## angle round it) gives its colours, [param shape] (t, angle) scales its
## radius round about; [param up0] and [param flat] flatten it across that
## direction.
func tube(pts: PackedVector3Array, radii: PackedFloat32Array, sides: int, paint: Callable,
		shape: Callable = Callable(), up0 := Vector3.ZERO, flat := 1.0) -> void:
	_tube(pts, radii, sides, paint, shape, up0, flat, PackedVector3Array(), PackedFloat32Array())


## A tube that takes another shape when the prop shuts: along
## [param shut_pts] with [param shut_radii] (as many of each as it has).
func tube_shutting(pts: PackedVector3Array, radii: PackedFloat32Array, shut_pts: PackedVector3Array,
		shut_radii: PackedFloat32Array, sides: int, paint: Callable, shape: Callable = Callable()) -> void:
	_tube(pts, radii, sides, paint, shape, Vector3.ZERO, 1.0, shut_pts, shut_radii)


func _tube(pts: PackedVector3Array, radii: PackedFloat32Array, sides: int, paint: Callable, shape: Callable,
		up0: Vector3, flat: float, shut_pts: PackedVector3Array, shut_radii: PackedFloat32Array) -> void:
	var n := pts.size()
	var start := verts.size()
	var rings := _rings(pts, radii, sides, shape, up0, flat)
	var shut_rings := _rings(shut_pts, shut_radii, sides, shape, up0, flat) if not shut_pts.is_empty() else []
	for i in n:
		var t := float(i) / (n - 1)
		var ring: Array = rings[i]
		for j in sides + 1:
			var a := TAU * j / sides
			var closed: Vector3 = (shut_rings[i][0][j] as Vector3) if not shut_rings.is_empty() else Vector3.INF
			add(ring[0][j], ring[1][j], paint.call(t, a), t, closed)
	var row := sides + 1
	for i in n - 1:
		for j in sides:
			var a := start + i * row + j
			quad(a, a + 1, a + row + 1, a + row)


## The rings of points and normals round a tube along [param pts], its
## frame carried down it so it does not twist.
func _rings(pts: PackedVector3Array, radii: PackedFloat32Array, sides: int, shape: Callable, up0: Vector3,
		flat: float) -> Array:
	var n := pts.size()
	var out := []
	var fwd0 := (pts[1] - pts[0]).normalized()
	var up := up0 if up0 != Vector3.ZERO else fwd0.cross(Vector3.FORWARD if absf(fwd0.z) < 0.9 else Vector3.RIGHT)
	for i in n:
		var fwd := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
		up = up - fwd * up.dot(fwd)
		if up.length_squared() < 1e-6:
			up = fwd.cross(Vector3.RIGHT if absf(fwd.x) < 0.9 else Vector3.UP)
		up = up.normalized()
		var side := fwd.cross(up)
		var t := float(i) / (n - 1)
		var dr := (radii[mini(i + 1, n - 1)] - radii[maxi(i - 1, 0)]) \
			/ maxf(pts[mini(i + 1, n - 1)].distance_to(pts[maxi(i - 1, 0)]), 0.0001)
		var ring_pts := PackedVector3Array()
		var ring_normals := PackedVector3Array()
		for j in sides + 1:
			var a := TAU * j / sides
			var s := 1.0 if shape.is_null() else float(shape.call(t, a))
			var dir := up * cos(a) * flat + side * sin(a)
			var nrm := (up * cos(a) / maxf(flat, 0.05) + side * sin(a)).normalized() - fwd * dr
			ring_pts.append(pts[i] + dir * radii[i] * s)
			ring_normals.append(nrm.normalized())
		out.append([ring_pts, ring_normals])
	return out


## A sheet through [param rows] of points, its front facing [param facing]
## (one per row); cull_disabled draws its back as well.
func sheet(rows: Array[PackedVector3Array], facing: PackedVector3Array, paint: Callable, along: Callable) -> void:
	var w := rows[0].size()
	var start := verts.size()
	for i in rows.size():
		for j in w:
			add(rows[i][j], facing[i], paint.call(i, j), along.call(i, j))
	for i in rows.size() - 1:
		for j in w - 1:
			var a := start + i * w + j
			quad(a, a + 1, a + w + 1, a + w)


## An ellipsoid about [param c] with half-axes [param ax], [param ay],
## [param az]; [param bumps] roughens it.
func blob(c: Vector3, ax: Vector3, ay: Vector3, az: Vector3, color: Color, sides: int, rings: int,
		along: float, bumps := 0.0) -> void:
	var start := verts.size()
	var inv := Basis(ax, ay, az).inverse().transposed()
	for i in rings + 1:
		var lat := lerpf(-PI * 0.5, PI * 0.5, float(i) / rings)
		for j in sides + 1:
			var lon := TAU * j / sides
			var u := Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon))
			var bump := 1.0 + bumps * sin(lon * 3.0 + lat * 5.0) * sin(lon * 5.0 - lat * 3.0)
			add(c + (ax * u.x + ay * u.y + az * u.z) * bump, (inv * u).normalized(), color, along)
	var row := sides + 1
	for i in rings:
		for j in sides:
			var a := start + i * row + j
			quad(a, a + 1, a + row + 1, a + row)


## A dome over [param c], [param radius] wide and [param height] tall.
func dome(c: Vector3, radius: float, height: float, sides: int, rings: int, paint: Callable) -> void:
	var start := verts.size()
	for i in rings + 1:
		var lat := PI * 0.5 * float(i) / rings
		for j in sides + 1:
			var lon := TAU * j / sides
			var p := c + Vector3(cos(lat) * cos(lon) * radius, sin(lat) * height, cos(lat) * sin(lon) * radius)
			var n := Vector3(cos(lat) * cos(lon) / radius, sin(lat) / height, cos(lat) * sin(lon) / radius)
			add(p, n.normalized(), paint.call(p - c), 0.0)
	var row := sides + 1
	for i in rings:
		for j in sides:
			var a := start + i * row + j
			quad(a, a + 1, a + row + 1, a + row)


## A flat disc of [param radius] round [param c] facing [param n];
## [param paint] (fraction out, angle) its colours.
func disc(c: Vector3, radius: float, sides: int, rings: int, n: Vector3, paint: Callable) -> void:
	var u := n.cross(Vector3.RIGHT if absf(n.x) < 0.9 else Vector3.FORWARD).normalized()
	var v := n.cross(u)
	var start := verts.size()
	for i in rings + 1:
		var r := lerpf(0.08, 1.0, float(i) / rings)
		for j in sides + 1:
			var a := TAU * j / sides
			add(c + (u * cos(a) + v * sin(a)) * r * radius - n * 0.03 * radius * (1.0 - r), n, paint.call(r, a), 0.0)
	var row := sides + 1
	for i in rings:
		for j in sides:
			var a := start + i * row + j
			quad(a, a + 1, a + row + 1, a + row)


## A mushroom cap over [param top] along [param axis]: [param radius]
## wide, [param height] tall, its margin waved and curled under.
func cap(top: Vector3, axis: Vector3, radius: float, height: float, spin: float) -> void:
	var u := axis.cross(Vector3.RIGHT if absf(axis.x) < 0.9 else Vector3.FORWARD).normalized()
	var v := axis.cross(u)
	var sides := 20
	var rings := 7
	var start := verts.size()
	for i in rings + 1:
		var f := float(i) / rings
		var lat := f * PI * 0.56
		for j in sides + 1:
			var a := TAU * j / sides
			var wave := 1.0 + 0.06 * sin(a * 6.0 + spin) * f
			var r := sin(lat) * radius * wave
			var y := (cos(lat) - 0.12) * height - smoothstep(0.75, 1.0, f) * 0.05 * radius
			var out := u * cos(a) + v * sin(a)
			var n := (out * sin(lat) * height + axis * cos(lat) * radius).normalized()
			var umbo := 1.0 - f * 0.35
			add(top + out * r + axis * y, n, Color(0.34 * umbo, 0.3 * umbo, 0.36 * umbo, 1.0), 0.0)
	var row := sides + 1
	for i in rings:
		for j in sides:
			var a := start + i * row + j
			quad(a, a + 1, a + row + 1, a + row)


## A crystal point from [param base] along [param axis]: a six-sided
## prism [param length] long ending in a six-faced tip [param tip] of its
## length, each face flat.
func prism(base: Vector3, axis: Vector3, length: float, radius: float, spin: float, tip: float) -> void:
	var u := axis.cross(Vector3.RIGHT if absf(axis.x) < 0.9 else Vector3.FORWARD).normalized()
	var v := axis.cross(u)
	var shoulder := base + axis * length * (1.0 - tip)
	var apex := base + axis * length
	var ring_lo := PackedVector3Array()
	var ring_hi := PackedVector3Array()
	for j in 6:
		var a := spin + TAU * j / 6.0
		var out := u * cos(a) + v * sin(a)
		var r := radius * (1.0 + 0.12 * sin(a * 3.0 + spin))
		ring_lo.append(base + out * r * 0.92)
		ring_hi.append(shoulder + out * r)
	for j in 6:
		var k2 := (j + 1) % 6
		var mid := (ring_lo[j] + ring_lo[k2] + ring_hi[j] + ring_hi[k2]) * 0.25
		var n := (mid - (base + shoulder) * 0.5)
		n = (n - axis * n.dot(axis)).normalized()
		var glow := 0.3 + 0.25 * sin(float(j) * 2.3 + spin)
		var a := add(ring_lo[j], n, Color(0.85, 0.88, 0.95, glow), 0.0)
		var b := add(ring_lo[k2], n, Color(0.85, 0.88, 0.95, glow), 0.0)
		var c := add(ring_hi[k2], n, Color(0.92, 0.94, 1.0, glow + 0.35), 0.0)
		var d := add(ring_hi[j], n, Color(0.92, 0.94, 1.0, glow + 0.35), 0.0)
		quad(a, b, c, d)
		var tn := (ring_hi[j] - apex).cross(ring_hi[k2] - apex).normalized()
		if tn.dot(mid - base) < 0.0:
			tn = -tn
		var e := add(ring_hi[j], tn, Color(0.95, 0.97, 1.0, glow + 0.4), 0.0)
		var f := add(ring_hi[k2], tn, Color(0.95, 0.97, 1.0, glow + 0.4), 0.0)
		var g := add(apex, tn, Color(1.0, 1.0, 1.0, 1.0), 0.0)
		tri(e, f, g)


func commit() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_CUSTOM0] = custom
	arrays[Mesh.ARRAY_CUSTOM1] = shut_offsets
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {},
		(Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
		| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT))
	return mesh
