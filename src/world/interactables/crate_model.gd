class_name CrateModel
extends RefCounted
## The salvage crate, as a cache is drawn and as a Mimic wears it: a painted
## steel case with bevelled edges, its lid closing on a seam a third of the
## way down, two steel bands round it, guards on its corners, latches front
## and back, handles at the ends and a signal beacon on top. Base and lid are
## built as trays (hollow, open towards the seam), so a crate that opens has
## an inside; closed, the two are one box. Crate space: X along its length,
## Y up, Z out of its face; centred on the box.

const HALF := Vector3(0.8, 0.55, 0.55)
## Height of the seam between base and lid.
const SEAM := 0.15
const WALL := 0.07
const BEVEL := 0.045
## Where the lid hinges (along its back end, at the seam).
const HINGE := Vector3(-0.8, SEAM, 0.0)
const BEACON_AT := Vector3(0.0, 0.64, 0.3)
const BAND_X := 0.52

static var _base: ArrayMesh
static var _lid: ArrayMesh
static var _paint: StandardMaterial3D
static var _steel: StandardMaterial3D


## The base, from the bottom up to the seam (open at the top).
static func base() -> ArrayMesh:
	_build()
	return _base


## The lid, from the seam to the top (open underneath), in crate space.
static func lid() -> ArrayMesh:
	_build()
	return _lid


## The beacon's light (blinking, it reads as a signal).
static func beacon(color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = MeshKit.sphere(0.075)
	mi.material_override = MeshKit.emissive_material(color, 8.0)
	mi.position = BEACON_AT
	return mi


static func _build() -> void:
	if _base:
		return
	_paint = StandardMaterial3D.new()
	_paint.albedo_texture = _weathering(
		[Color(0.5, 0.31, 0.11), Color(0.8, 0.52, 0.13), Color(0.85, 0.57, 0.15), Color(0.9, 0.65, 0.24)], 7, 11.0)
	_paint.metallic = 0.45
	_paint.roughness = 0.55
	_paint.uv1_triplanar = true
	_paint.uv1_scale = Vector3.ONE * 0.9
	_steel = StandardMaterial3D.new()
	_steel.albedo_texture = _weathering(
		[Color(0.3, 0.19, 0.11), Color(0.2, 0.2, 0.22), Color(0.23, 0.23, 0.25), Color(0.34, 0.34, 0.36)], 11, 14.0)
	_steel.metallic = 0.8
	_steel.roughness = 0.4
	_steel.uv1_triplanar = true
	_steel.uv1_scale = Vector3.ONE * 1.4
	var lo := -HALF
	var hi := HALF
	# The base: its tray, and its share of the bands, the bottom corner
	# guards, the latch hooks and the handles.
	_base = ArrayMesh.new()
	var st := _begin()
	_tray(st, lo, Vector3(hi.x, SEAM, hi.z), 1.0)
	st.commit(_base)
	st = _begin()
	for x: float in [-BAND_X, BAND_X]:
		var tall := (SEAM - 0.02 - lo.y) * 0.5
		for z: float in [-1.0, 1.0]:
			_box(st, Vector3(x, lo.y + tall, z * (hi.z + 0.012)), Vector3(0.06, tall, 0.02))
		_box(st, Vector3(x, lo.y - 0.012, 0.0), Vector3(0.06, 0.02, hi.z + 0.03))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_box(st, Vector3(sx * (hi.x - 0.055), lo.y + 0.055, sz * (hi.z - 0.055)), Vector3(0.07, 0.07, 0.07))
			_box(st, Vector3(sx * 0.28, SEAM - 0.07, sz * (hi.z + 0.02)), Vector3(0.05, 0.05, 0.025))
		# A handle at each end.
		for sz: float in [-1.0, 1.0]:
			_box(st, Vector3(sx * (hi.x + 0.04), -0.12, sz * 0.25), Vector3(0.04, 0.03, 0.03))
		_box(st, Vector3(sx * (hi.x + 0.08), -0.12, 0.0), Vector3(0.025, 0.025, 0.28))
	st.commit(_base)
	_base.surface_set_material(0, _paint)
	_base.surface_set_material(1, _steel)
	# The lid: its tray, the bands over it, the top corner guards, the latch
	# plates and the beacon's housing.
	_lid = ArrayMesh.new()
	st = _begin()
	_tray(st, Vector3(lo.x, SEAM, lo.z), hi, -1.0)
	st.commit(_lid)
	st = _begin()
	for x: float in [-BAND_X, BAND_X]:
		var tall := (hi.y - SEAM - 0.02) * 0.5
		for z: float in [-1.0, 1.0]:
			_box(st, Vector3(x, hi.y - tall, z * (hi.z + 0.012)), Vector3(0.06, tall, 0.02))
		_box(st, Vector3(x, hi.y + 0.012, 0.0), Vector3(0.06, 0.02, hi.z + 0.03))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_box(st, Vector3(sx * (hi.x - 0.055), hi.y - 0.055, sz * (hi.z - 0.055)), Vector3(0.07, 0.07, 0.07))
			_box(st, Vector3(sx * 0.28, SEAM + 0.07, sz * (hi.z + 0.015)), Vector3(0.07, 0.06, 0.02))
	_box(st, Vector3(BEACON_AT.x, hi.y + 0.03, BEACON_AT.z), Vector3(0.08, 0.03, 0.08))
	st.commit(_lid)
	_lid.surface_set_material(0, _paint)
	_lid.surface_set_material(1, _steel)


static func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


## Weathered paint: patches of [param ramp] colours (grime, two shades of
## the paint, worn bare) at about [param frequency] patches a metre.
static func _weathering(ramp: Array, seed_value: int, frequency: float) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = frequency / 256.0
	noise.fractal_octaves = 5
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.22, 0.72, 1.0])
	gradient.colors = PackedColorArray(ramp)
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = noise
	tex.color_ramp = gradient
	tex.generate_mipmaps = true
	return tex


## A polygon facing [param outward], flat shaded.
static func _poly(st: SurfaceTool, pts: Array, outward: Vector3) -> void:
	var p0: Vector3 = pts[0]
	var p1: Vector3 = pts[1]
	var p2: Vector3 = pts[2]
	if (p1 - p0).cross(p2 - p0).dot(outward) > 0.0:
		pts.reverse()
	for i in range(1, pts.size() - 1):
		for p: Vector3 in [pts[0], pts[i], pts[i + 1]]:
			st.set_normal(outward.normalized())
			st.add_vertex(p)


## A box with bevelled edges and corners, centred on [param centre].
static func _box(st: SurfaceTool, centre: Vector3, half: Vector3, open_side := 0.0, c := 0.012) -> void:
	# Each corner's three points: on its X, Y and Z faces.
	var pt := func(s: Vector3, axis: int) -> Vector3:
		var inset := half - Vector3.ONE * c
		inset[axis] = half[axis]
		return centre + s * inset
	var signs: Array[Vector3] = []
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				signs.append(Vector3(sx, sy, sz))
	for axis in 3:
		var u := (axis + 1) % 3
		var v := (axis + 2) % 3
		for s: float in [-1.0, 1.0]:
			if axis == 1 and s == open_side:
				continue
			var quad := []
			for k: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var sg := Vector3.ZERO
				sg[axis] = s
				sg[u] = k.x
				sg[v] = k.y
				quad.append(pt.call(sg, axis))
			var out := Vector3.ZERO
			out[axis] = s
			_poly(st, quad, out)
		# The bevels along the edges between this face's axis and the next.
		for sa: float in [-1.0, 1.0]:
			for sb: float in [-1.0, 1.0]:
				var a := axis
				var b := u
				var quad := []
				for t: float in [-1.0, 1.0]:
					var sg := Vector3.ZERO
					sg[a] = sa
					sg[b] = sb
					sg[v] = t
					quad.append(pt.call(sg, a))
				for t: float in [1.0, -1.0]:
					var sg := Vector3.ZERO
					sg[a] = sa
					sg[b] = sb
					sg[v] = t
					quad.append(pt.call(sg, b))
				var out := Vector3.ZERO
				out[a] = sa
				out[b] = sb
				_poly(st, quad, out)
	for s in signs:
		_poly(st, [pt.call(s, 0), pt.call(s, 1), pt.call(s, 2)], s)


## A crate half from [param lo] to [param hi]: a bevelled box, hollow, open
## towards [param open_side] (+1 up, -1 down), with a rim round its mouth.
static func _tray(st: SurfaceTool, lo: Vector3, hi: Vector3, open_side: float) -> void:
	var centre := (lo + hi) * 0.5
	var half := (hi - lo) * 0.5
	_box(st, centre, half, open_side, BEVEL)
	var mouth_y := centre.y + open_side * half.y
	var floor_y := centre.y - open_side * (half.y - WALL)
	var outer := Vector2(half.x - BEVEL, half.z - BEVEL)
	var inner := Vector2(half.x - WALL, half.z - WALL)
	var up := Vector3(0.0, open_side, 0.0)
	var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		var at := func(k: Vector2, r: Vector2, y: float) -> Vector3: return Vector3(centre.x + k.x * r.x, y,
			centre.z + k.y * r.y)
		# The rim, from the outside edge in to the wall's inner face.
		_poly(st, [at.call(a, outer, mouth_y), at.call(b, outer, mouth_y), at.call(b, inner, mouth_y),
			at.call(a, inner, mouth_y)], up)
		# The inside of the wall, facing in.
		var mid := (a + b) * 0.5
		_poly(st, [at.call(a, inner, mouth_y), at.call(b, inner, mouth_y), at.call(b, inner, floor_y),
			at.call(a, inner, floor_y)], -Vector3(mid.x, 0.0, mid.y))
	_poly(st, [Vector3(centre.x - inner.x, floor_y, centre.z - inner.y),
		Vector3(centre.x + inner.x, floor_y, centre.z - inner.y), Vector3(centre.x + inner.x, floor_y, centre.z + inner.y),
		Vector3(centre.x - inner.x, floor_y, centre.z + inner.y)], up)
