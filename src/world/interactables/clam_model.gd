class_name ClamModel
extends RefCounted
## The giant clam's pieces, in the clam's own space (about three metres
## across before scaling, hinge at the back on -X, the lips meeting round
## y = 0): two heavy valves thrown into big radial folds whose scalloped
## lips interlock when shut, ribbed with growth lines and crusted with
## barnacles; the mantle that swells out between them as they part; the
## frilled siphon and the soft bed the pearl lies on.
##
## Valves: UV.x is how far out from the middle a point is (1 at the lip),
## COLOR.rgb the shell's own tint, COLOR.a 1 on barnacles. The mantle: UV.x
## is how far up the curtain between the lips a point is (0 on the bottom
## valve, 1 on the top), UV.y how far round; CUSTOM0.xyz is where its top
## edge sits on the top valve while shut, which clam_mantle.gdshader swings
## open with the hinge.

const HALF_LENGTH := 1.4
const HALF_WIDTH := 1.05
const HINGE := Vector3(-1.35, 0.0, 0.0)
## The folds: how many across the front, and how deep at the lip.
const FOLDS := 7.0
const FOLD_DEPTH := 0.17
const DOME_TOP := 0.5
const DOME_BOTTOM := 0.62
const RINGS := 12
const AROUND := 72


## The height of the lip at angle [param phi] round the shell: the folds.
static func lip(phi: float) -> float:
	return _fold(_outline(phi, 1.0))


## A valve: the top one domed up, the bottom one deeper and domed down,
## their lips meeting on the same zigzag.
static func valve(top: bool, seed_value: int) -> ArrayMesh:
	var b := Builder.new()
	var grid: Array[PackedVector3Array] = []
	for i in RINGS + 1:
		var r := float(i) / RINGS
		var row := PackedVector3Array()
		for j in AROUND + 1:
			var phi := TAU * j / AROUND
			var p := _outline(phi, r)
			var dome := pow(maxf(1.0 - r * r, 0.0), 0.55)
			p.y = (DOME_TOP * dome if top else -DOME_BOTTOM * dome) + _fold(p) * smoothstep(0.0, 0.5, r)
			row.append(p)
		grid.append(row)
	var inner := Vector3(0.0, -0.3 if top else 0.3, 0.0)
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 1.3
	var start := b.verts.size()
	for i in RINGS + 1:
		for j in AROUND + 1:
			var p := grid[i][j]
			var along := grid[mini(i + 1, RINGS)][j] - grid[maxi(i - 1, 0)][j]
			var round := grid[i][(j + 1) % AROUND] - grid[i][(j + AROUND - 1) % AROUND]
			var n := along.cross(round).normalized() if i > 0 else Vector3(0.0, 1.0 if top else -1.0, 0.0)
			if n.dot(p - inner) < 0.0:
				n = -n
			var g := 0.86 + noise.get_noise_3dv(p) * 0.18
			b.add(p, n, Color(g, g * 0.97, g * 0.92, 0.0), Vector2(float(i) / RINGS, float(j) / AROUND))
	for i in RINGS:
		for j in AROUND:
			var a := start + i * (AROUND + 1) + j
			b.quad(a, a + 1, a + AROUND + 2, a + AROUND + 1)
	# The lip rolled thick, so the shell has some weight to it.
	var lip_ring := PackedVector3Array()
	for j in AROUND + 1:
		lip_ring.append(grid[RINGS][j])
	b.ring_tube(lip_ring, 0.035, 6)
	if top:
		# Barnacles crusting the top valve, thickest towards the hinge.
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		for k in 9:
			var i := rng.randi_range(3, 9)
			var j := rng.randi_range(0, AROUND - 1)
			var p := grid[i][j]
			if p.x > 0.6:
				continue
			b.barnacle(p, (p - inner).normalized(), rng.randf_range(0.05, 0.1))
	return b.commit()


## The mantle's curtain between the lips, all round the front, and the bed
## of mantle inside the bottom valve with its siphon.
static func mantle() -> ArrayMesh:
	var b := Builder.new()
	# Two frilled lips, one lining each valve's edge, the gap between them
	# left open so the bed and the pearl show.
	var rows := 4
	for lip_range: Vector2 in [Vector2(0.0, 0.24), Vector2(1.0, 0.76)]:
		var start := b.verts.size()
		for j in AROUND + 1:
			var phi := TAU * j / AROUND
			var rim := _outline(phi, 0.95)
			rim.y = _fold(_outline(phi, 1.0)) - 0.015
			var out := Vector3(rim.x, 0.0, rim.z).normalized()
			# Not over the hinge: the valves stay joined there.
			var hinge_side := smoothstep(-0.55, -0.85, cos(phi))
			for i in rows + 1:
				var s := lerpf(lip_range.x, lip_range.y, float(i) / rows)
				var shade := Color(1, 1, 1, float(i) / rows * (1.0 - hinge_side))
				b.add_mantle(rim, out, rim, Vector2(lerpf(lip_range.x, s, 1.0 - hinge_side), float(j) / AROUND), shade)
		for j in AROUND:
			for i in rows:
				var a := start + j * (rows + 1) + i
				b.quad(a, a + 1, a + rows + 2, a + rows + 1)
	# The bed: a soft floor of mantle inside the bottom valve.
	var bed_start := b.verts.size()
	var bed_rings := 5
	for i in bed_rings + 1:
		var r := lerpf(0.05, 0.94, float(i) / bed_rings)
		for j in AROUND + 1:
			var phi := TAU * j / AROUND
			var p := _outline(phi, r)
			p.y = -0.03 - 0.06 * (1.0 - r * r) + _fold(_outline(phi, 1.0)) * smoothstep(0.6, 0.94, r)
			b.add_mantle(p, Vector3.UP, p, Vector2(0.0, float(j) / AROUND), Color(1, 1, 1, 0.0))
	for i in bed_rings:
		for j in AROUND:
			var a := bed_start + i * (AROUND + 1) + j
			b.quad(a, a + 1, a + AROUND + 2, a + AROUND + 1)
	# The siphon: a dark frilled mouth towards the back.
	var mouth := PackedVector3Array()
	for k in 25:
		var a := TAU * k / 24.0
		var frill := 1.0 + 0.12 * sin(a * 9.0)
		mouth.append(Vector3(-0.45 + cos(a) * 0.2 * frill, 0.0, sin(a) * 0.13 * frill))
	b.ring_tube(mouth, 0.035, 6, true)
	return b.commit()


## The pearl.
static func pearl() -> SphereMesh:
	return MeshKit.sphere(0.27, 20, 10)


## Where a point a fraction [param r] of the way out to the lip, at angle
## [param phi], lies in plan (y left at 0).
static func _outline(phi: float, r: float) -> Vector3:
	# A little fuller at the front than at the hinge end.
	var front := 1.0 + 0.08 * cos(phi)
	return Vector3(cos(phi) * HALF_LENGTH * r * front, 0.0, sin(phi) * HALF_WIDTH * r)


## How far the folds lift (or drop) the shell at [param p], growing from
## nothing at the hinge to their full depth at the front.
static func _fold(p: Vector3) -> float:
	var away := Vector2(p.x - HINGE.x, p.z)
	var psi := atan2(away.y, away.x)
	var wave := sin(psi * FOLDS * 1.9)
	# Rounded troughs, sharper crests.
	wave = signf(wave) * pow(absf(wave), 0.7)
	return wave * FOLD_DEPTH * smoothstep(0.3, 2.7, away.length())


## Accumulates the clam's meshes.
class Builder:
	extends RefCounted
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var custom := PackedFloat32Array()
	var indices := PackedInt32Array()

	func add(p: Vector3, n: Vector3, c: Color, uv: Vector2) -> int:
		verts.append(p)
		normals.append(n)
		colors.append(c)
		uvs.append(uv)
		custom.append_array([p.x, p.y, p.z, 0.0])
		return verts.size() - 1

	## A mantle vertex: [param top] is where it goes on the top valve.
	func add_mantle(p: Vector3, n: Vector3, top: Vector3, uv: Vector2, c := Color.WHITE) -> int:
		var i := add(p, n, c, uv)
		custom[i * 4] = top.x
		custom[i * 4 + 1] = top.y
		custom[i * 4 + 2] = top.z
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

	## A tube round the closed loop [param loop] (first point repeated last).
	func ring_tube(loop: PackedVector3Array, radius: float, sides: int, dark := false) -> void:
		var start := verts.size()
		var n := loop.size()
		var centre := Vector3.ZERO
		for p in loop:
			centre += p
		centre /= n
		for i in n:
			var fwd := (loop[(i + 1) % (n - 1)] - loop[(i + n - 2) % (n - 1)]).normalized()
			var out := (loop[i] - centre)
			out = (out - fwd * out.dot(fwd)).normalized()
			var up := fwd.cross(out).normalized()
			for k in sides + 1:
				var a := TAU * k / sides
				var d := out * cos(a) + up * sin(a)
				var c := Color(0.25, 0.12, 0.3, 0.0) if dark else Color(0.92, 0.9, 0.84, 0.0)
				add(loop[i] + d * radius, d, c, Vector2(1.0, float(i) / (n - 1)))
		for i in n - 1:
			for k in sides:
				var a := start + i * (sides + 1) + k
				quad(a, a + 1, a + sides + 2, a + sides + 1)

	## A barnacle: a little ridged cone with a slit at its top, at [param p]
	## standing out along [param n].
	func barnacle(p: Vector3, n: Vector3, size: float) -> void:
		var u := n.cross(Vector3.FORWARD if absf(n.z) < 0.9 else Vector3.RIGHT).normalized()
		var v := n.cross(u)
		var start := verts.size()
		var sides := 8
		var profile := [[0.0, 1.0], [0.55, 0.75], [0.8, 0.4], [0.75, 0.25]]
		for ring: Array in profile:
			for k in sides + 1:
				var a := TAU * k / sides
				var ridge := 1.0 + 0.12 * cos(a * 4.0)
				var d := u * cos(a) + v * sin(a)
				add(p + n * ring[0] * size + d * ring[1] * size * ridge, (d + n * 0.5).normalized(),
					Color(0.8, 0.78, 0.72, 1.0), Vector2(0.0, 0.0))
		for r in profile.size() - 1:
			for k in sides:
				var a := start + r * (sides + 1) + k
				quad(a, a + 1, a + sides + 2, a + sides + 1)

	func commit() -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_CUSTOM0] = custom
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {},
			Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
		return mesh
