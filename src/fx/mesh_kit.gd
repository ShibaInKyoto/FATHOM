class_name MeshKit
extends RefCounted
## Procedural mesh helpers for creatures and props. Meshes carry vertex
## colors read by creature.gdshader: R = glow mask, G = belly blend.


## Body of revolution along X, from x = -length/2 (tail) to +length/2 (head).
## [param profile] holds (t, radius) pairs with t from 0 (tail) to 1 (head).
## [param glow] is an optional func(t: float, angle: float) -> float.
static func lathe(profile: PackedVector2Array, length: float, sides := 14, rings := 18,
		y_scale := 1.0, z_scale := 1.0, glow: Callable = Callable()) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for i in rings + 1:
		var t := float(i) / rings
		var r := _profile_at(profile, t)
		var dr := (_profile_at(profile, minf(t + 0.01, 1.0)) - _profile_at(profile, maxf(t - 0.01, 0.0))) / (0.02 * length)
		var x := -length * 0.5 + t * length
		for j in sides + 1:
			var a := TAU * j / sides
			var cy := cos(a)
			var sz := sin(a)
			verts.append(Vector3(x, cy * r * y_scale, sz * r * z_scale))
			normals.append(Vector3(-dr, cy / maxf(y_scale, 0.01), sz / maxf(z_scale, 0.01)).normalized())
			var g := 0.0 if glow.is_null() else float(glow.call(t, a))
			colors.append(Color(g, smoothstep(0.1, -0.7, cy), 0.0))
	var row := sides + 1
	for i in rings:
		for j in sides:
			var a := i * row + j
			indices.append_array([a, a + row, a + 1, a + 1, a + row, a + row + 1])
	return _mesh(verts, normals, colors, indices)


## Flat double-sided fin from an outline in the XY plane.
static func fin(outline: PackedVector2Array, thickness := 0.03, glow := 0.0, belly := 0.0) -> ArrayMesh:
	var tris := Geometry2D.triangulate_polygon(outline)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for side in 2:
		var z := thickness * (0.5 if side == 0 else -0.5)
		var n := Vector3(0, 0, 1 if side == 0 else -1)
		var base := verts.size()
		for p in outline:
			verts.append(Vector3(p.x, p.y, z))
			normals.append(n)
			colors.append(Color(glow, belly, 0.0))
		for k in range(0, tris.size(), 3):
			if side == 0:
				indices.append_array([base + tris[k], base + tris[k + 2], base + tris[k + 1]])
			else:
				indices.append_array([base + tris[k], base + tris[k + 1], base + tris[k + 2]])
	return _mesh(verts, normals, colors, indices)


## Simple sphere with uniform vertex color.
static func ball(radius: float, glow := 0.0, sides := 12, rings := 8) -> ArrayMesh:
	var profile := PackedVector2Array()
	for i in rings + 1:
		var t := float(i) / rings
		profile.append(Vector2(t, sin(t * PI) * radius))
	return lathe(profile, radius * 2.0, sides, rings, 1.0, 1.0, func(_t: float, _a: float) -> float: return glow)


## Low-poly UV sphere (Godot primitive) for small details.
static func sphere(radius: float, segments := 8, rings := 4) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = segments
	s.rings = rings
	return s


## Unshaded glowing material for lamps, eyes and indicator lights.
static func emissive_material(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


## Cone along +X (tip at +length).
static func spike(radius: float, length: float, glow := 0.0, sides := 6) -> ArrayMesh:
	var mesh := lathe(PackedVector2Array([Vector2(0, radius), Vector2(1, 0.0)]), length, sides, 1, 1.0, 1.0,
		func(_t: float, _a: float) -> float: return glow)
	return transformed(mesh, Transform3D(Basis(), Vector3(length * 0.5, 0, 0)))


## Bakes several meshes with transforms into a single mesh (one draw call).
static func merge(parts: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part: Array in parts:
		var m: Mesh = part[0]
		var xf: Transform3D = part[1] if part.size() > 1 else Transform3D.IDENTITY
		for s in m.get_surface_count():
			st.append_from(m, s, xf)
	return st.commit()


## Copy of [param mesh] with vertex colors from [param painter]
## (func(vertex: Vector3) -> Color), for meshes drawn by the prop shaders.
static func painted(mesh: ArrayMesh, painter: Callable) -> ArrayMesh:
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colors := PackedColorArray()
		colors.resize(verts.size())
		for i in verts.size():
			colors[i] = painter.call(verts[i])
		arrays[Mesh.ARRAY_COLOR] = colors
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


static func transformed(mesh: Mesh, xf: Transform3D) -> ArrayMesh:
	return merge([[mesh, xf]])


## Tube through [param points] (in the XY plane) with per-point radii;
## [param glow_tail] scales the glowing bands along it.
## Writes into [param target] so callers can rebuild a mesh every frame.
static func tube(target: ArrayMesh, points: PackedVector3Array, radii: PackedFloat32Array, sides := 8,
		glow_tail := 0.0) -> void:
	target.clear_surfaces()
	var n := points.size()
	if n < 2:
		return
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for i in n:
		var fwd: Vector3
		if i == 0:
			fwd = points[1] - points[0]
		elif i == n - 1:
			fwd = points[i] - points[i - 1]
		else:
			fwd = points[i + 1] - points[i - 1]
		fwd = fwd.normalized()
		# Ring round the tube, square to it (for a tube in the XY plane, the
		# ring's up is +Z); a tube heading along Z takes its frame from X.
		var side := fwd.cross(Vector3.BACK if absf(fwd.z) < 0.9 else Vector3.RIGHT).normalized()
		var up := side.cross(fwd)
		var t := float(i) / (n - 1)
		for j in sides + 1:
			var a := TAU * j / sides
			var dir := side * cos(a) + up * sin(a)
			verts.append(points[i] + dir * radii[i])
			normals.append(dir)
			# Photophore bands along the body, brightest on the camera-facing side.
			var band := 1.0 if fmod(t * 8.0, 1.0) < 0.2 else 0.08
			colors.append(Color(glow_tail * band * (0.4 + 0.6 * maxf(sin(a), 0.0)), smoothstep(0.2, -0.8, cos(a)), 0.0))
	var row := sides + 1
	for i in n - 1:
		for j in sides:
			var a := i * row + j
			indices.append_array([a, a + 1, a + row, a + 1, a + row + 1, a + row])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	target.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


static func _profile_at(profile: PackedVector2Array, t: float) -> float:
	if t <= profile[0].x:
		return profile[0].y
	for i in range(1, profile.size()):
		if t <= profile[i].x:
			var a := profile[i - 1]
			var b := profile[i]
			var f := (t - a.x) / maxf(b.x - a.x, 0.0001)
			# Smooth interpolation keeps bodies rounded between stations.
			return lerpf(a.y, b.y, f * f * (3.0 - 2.0 * f))
	return profile[profile.size() - 1].y


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
