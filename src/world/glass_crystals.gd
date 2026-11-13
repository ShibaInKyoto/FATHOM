class_name GlassCrystals
extends RefCounted
## The crystals coating the singing glass, packed close like the inside of
## a geode: six-sided prisms with pointed tips (the larger ones with
## bevelled edges), flat-faced so each face catches the light on its own,
## built in world space over the seam.
##
## Vertex data (for crystal.gdshader): UV.x how far up its crystal a point
## is (0 at the base, 1 at the tip), UV.y 1 on a bevel; CUSTOM0 the crystal's
## base (xyz) and radius (w); CUSTOM1 its axis (xyz) and length (w).

## Bevels: how much of a face's width each edge takes.
const BEVEL := 0.13


## One crystal growing from [param base] along [param axis]; [param radius]
## its girth, [param length] its reach, [param rng] for the small
## irregularities that make each one its own.
static func add_crystal(b: Builder, base: Vector3, axis: Vector3, radius: float, length: float,
		rng: RandomNumberGenerator, bevelled := true) -> void:
	axis = axis.normalized()
	var side := axis.cross(Vector3.FORWARD if absf(axis.z) < 0.9 else Vector3.RIGHT).normalized()
	var other := axis.cross(side)
	var spin := rng.randf() * TAU
	# The six corners, each face its own width.
	var corners := PackedVector2Array()
	for k in 6:
		var a := spin + TAU * k / 6.0 + rng.randf_range(-0.08, 0.08)
		corners.append(Vector2(cos(a), sin(a)) * rng.randf_range(0.88, 1.1))
	# Each corner cut back into a narrow bevel: twelve points round (the
	# smallest are left sharp: six).
	var ring := PackedVector2Array()
	var bevel := PackedByteArray()
	if bevelled:
		for k in 6:
			var c := corners[k]
			var prev := corners[(k + 5) % 6]
			var next := corners[(k + 1) % 6]
			ring.append(c + (prev - c) * BEVEL)
			ring.append(c + (next - c) * BEVEL)
		# Faces: from point 2k to 2k+1 a bevel, from 2k+1 to 2k+2 a main face.
		for k in 12:
			bevel.append(1 if k % 2 == 0 else 0)
	else:
		ring = corners
		for k in 6:
			bevel.append(0)
	var count := ring.size()
	var tip := clampf(rng.randf_range(0.22, 0.3), 0.0, 0.5)
	var shoulder := length * (1.0 - tip)
	var taper := rng.randf_range(0.86, 0.96)
	var apex_off := Vector2(rng.randf_range(-0.12, 0.12), rng.randf_range(-0.12, 0.12)) * radius
	var lo := PackedVector3Array()
	var hi := PackedVector3Array()
	for p in ring:
		lo.append(base + (side * p.x + other * p.y) * radius)
		hi.append(base + axis * shoulder + (side * p.x + other * p.y) * radius * taper)
	var apex := base + axis * length + side * apex_off.x + other * apex_off.y
	b.crystal = [base, radius, axis, length]
	for k in count:
		var k1 := (k + 1) % count
		var is_bevel := bevel[k] == 1
		# The prism's side.
		b.face([lo[k], lo[k1], hi[k1], hi[k]], [0.0, 0.0, 1.0 - tip, 1.0 - tip], is_bevel, base + axis * shoulder * 0.5)
		# Its tip.
		b.face([hi[k], hi[k1], apex], [1.0 - tip, 1.0 - tip, 1.0], is_bevel, base + axis * shoulder)


## Accumulates crystals into one mesh.
class Builder:
	extends RefCounted
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var custom0 := PackedFloat32Array()
	var custom1 := PackedFloat32Array()
	var indices := PackedInt32Array()
	## The crystal the faces added next belong to: [base, radius, axis, length].
	var crystal: Array = [Vector3.ZERO, 1.0, Vector3.UP, 1.0]

	## A flat face through [param pts] (3 or 4, in order round it), facing
	## away from [param inside]; [param heights] how far up the crystal each
	## point is.
	func face(pts: Array, heights: Array, is_bevel: bool, inside: Vector3) -> void:
		var n: Vector3 = ((pts[1] as Vector3) - pts[0]).cross((pts[2] as Vector3) - pts[0]).normalized()
		var centre := Vector3.ZERO
		for p: Vector3 in pts:
			centre += p
		centre /= pts.size()
		if n.dot(centre - inside) < 0.0:
			n = -n
		var start := verts.size()
		var base: Vector3 = crystal[0]
		var axis: Vector3 = crystal[2]
		for i in pts.size():
			verts.append(pts[i])
			normals.append(n)
			uvs.append(Vector2(heights[i], 1.0 if is_bevel else 0.0))
			custom0.append_array([base.x, base.y, base.z, crystal[1]])
			custom1.append_array([axis.x, axis.y, axis.z, crystal[3]])
		var tris := [[0, 1, 2]] if pts.size() == 3 else [[0, 1, 2], [0, 2, 3]]
		for t: Array in tris:
			var a: Vector3 = pts[t[0]]
			var cr := ((pts[t[1]] as Vector3) - a).cross((pts[t[2]] as Vector3) - a)
			# Godot's front faces wind clockwise as seen.
			if cr.dot(n) > 0.0:
				indices.append_array([start + t[0], start + t[2], start + t[1]])
			else:
				indices.append_array([start + t[0], start + t[1], start + t[2]])

	func commit() -> ArrayMesh:
		var mesh := ArrayMesh.new()
		if verts.is_empty():
			return mesh
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_CUSTOM0] = custom0
		arrays[Mesh.ARRAY_CUSTOM1] = custom1
		arrays[Mesh.ARRAY_INDEX] = indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {},
			(Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
			| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT))
		return mesh
