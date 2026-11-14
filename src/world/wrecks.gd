class_name Wrecks
extends RefCounted
## The "wreck field" zone event: the broken hulls of an earlier expedition's
## research submersibles, snapped in two and settled on the floor behind the
## playfield with their salvage spilled around them.

const COUNT := 3
const MIN_SPACING := 30.0
const SHADER := preload("res://src/fx/shaders/station.gdshader")

static var _mesh: ArrayMesh


## Lays wrecks on suitable floor and returns a water point beside each one,
## where the populator spills their salvage.
static func scatter(level: Level, rng: RandomNumberGenerator, avoid: PackedVector2Array) -> PackedVector2Array:
	var layout := level.layout
	var spots := PackedVector2Array()
	var xforms: Array[Transform3D] = []
	var anchors := layout.anchors.duplicate()
	for i in range(anchors.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp: LevelLayout.Anchor = anchors[i]
		anchors[i] = anchors[j]
		anchors[j] = tmp
	for a: LevelLayout.Anchor in anchors:
		if xforms.size() >= COUNT:
			break
		if a.normal.y < 0.7 or a.pos.distance_to(layout.start) < 25.0:
			continue
		var water := a.pos + a.normal * 3.0
		if not layout.is_reachable(water) or _near(water, spots, MIN_SPACING) or _near(water, avoid, 8.0):
			continue
		var z := rng.randf_range(-3.4, -2.4)
		# Hull axis about a radius above the floor, settled a little into the silt.
		var base := a.pos + a.normal * (PropScatter.surface_offset(z) + 0.9)
		var basis := Basis(Vector3.BACK, a.normal.angle() - PI * 0.5) * Basis(Vector3.UP, rng.randf_range(-0.45, 0.45))
		basis = basis * Basis(Vector3.RIGHT, rng.randf_range(-0.5, 0.5)) * Basis(Vector3.BACK, rng.randf_range(-0.12, 0.12))
		xforms.append(Transform3D(basis.scaled(Vector3.ONE * rng.randf_range(0.85, 1.2)), Vector3(base.x, base.y, z)))
		spots.append(water)
	if xforms.is_empty():
		return spots
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _wreck_mesh()
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_custom_data(i, Color(0.0, rng.randf(), rng.randf_range(0.85, 1.05), 0.0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _material(level.biome)
	level.add_child(mmi)
	return spots


static func _near(p: Vector2, points: PackedVector2Array, dist: float) -> bool:
	for q in points:
		if q.distance_squared_to(p) < dist * dist:
			return true
	return false


static func _material(biome: BiomeDef) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter(&"sediment_tint", biome.sediment_tint)
	m.set_shader_parameter(&"decay", 1.0)
	m.set_shader_parameter(&"steady_energy", 0.0)
	m.set_shader_parameter(&"failing_energy", 0.0)
	return m


## A research submersible snapped in two (in the station's materials: see
## [StationModel]): the bow with its ribbed pressure hull, its sail and dead
## viewports and the dome it looked out of; the stern bent away from the
## break with its shrouded propeller, planes and rudder; both ends of the
## break jagged and open, pipes and torn plating spilling from them.
static func _wreck_mesh() -> ArrayMesh:
	if _mesh:
		return _mesh
	var b := ModelBuilder.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	var r := 1.1
	var hull := Color(0.66, 0.52, 0.22, StationModel.PAINT)
	var band := Color(0.85, 0.82, 0.74, StationModel.PAINT)
	var steel := Color(StationModel.FRAME_TINT, StationModel.STEEL)
	var dark := Color(0.06, 0.06, 0.06, StationModel.DARK)
	# The bow: hull from the break forward, ribbed, its dome at the nose.
	_hull(b, rng, 0.3, 3.5, r, hull, band, true)
	var nose: Array = []
	for k in 9:
		var t := k / 8.0
		nose.append(Vector2(3.5 + 0.9 * sin(t * PI * 0.5), r * cos(t * PI * 0.5) + 0.001))
	_lathe(b, nose, band)
	b.torus(Vector3(4.15, 0.25, 0.0), Vector3.RIGHT, 0.55, 0.07, steel, 24, 6)
	b.ellipsoid(Vector3(4.2, 0.25, 0.0), Vector3(0.12, 0.5, 0.5), Color(0.0, 0.3, 0.0, StationModel.WINDOW), 16, 10)
	# Its sail, its ports and hatch, the mast bent over.
	b.rounded_box(Vector3(2.2, r + 0.45, 0.0), Vector3(0.8, 0.6, 0.38), 4.0, hull, 16, 8)
	for x: float in [1.75, 2.05, 2.35]:
		b.disc(Vector3(x, r + 0.72, 0.385), Vector3.BACK, 0.07, Color(0.0, 0.6, 0.0, StationModel.WINDOW), 10)
		b.torus(Vector3(x, r + 0.72, 0.39), Vector3.BACK, 0.075, 0.015, steel, 12, 5)
	b.box(Vector3(2.75, r + 0.4, 0.39), Vector3.RIGHT * 0.16, Vector3.UP * 0.3, Vector3.BACK * 0.02, dark)
	b.cylinder(Vector3(2.0, r + 1.0, 0.0), Vector3(2.0, r + 1.12, 0.0), 0.3, band, 16)
	b.tube(PackedVector3Array([Vector3(2.6, r + 1.0, 0.0), Vector3(2.65, r + 1.6, 0.0), Vector3(2.2, r + 1.9, 0.1)]),
		PackedFloat32Array([0.05, 0.04, 0.03]), 6, steel)
	# Skids under the bow, one torn loose.
	b.beam(Vector3(0.6, -r - 0.2, 0.55), Vector3(3.6, -r - 0.2, 0.55), Vector2(0.08, 0.06), steel)
	b.beam(Vector3(1.4, -r - 0.2, -0.55), Vector3(3.6, -r - 0.35, -0.75), Vector2(0.08, 0.06), steel)
	# The stern, bent away from the break.
	var keep := b.xf
	b.xf = Transform3D(Basis(Vector3.BACK, -0.28) * Basis(Vector3.UP, 0.3), Vector3(-0.6, -0.35, 0.3))
	_hull(b, rng, -2.9, -0.3, r, hull, band, false)
	_lathe(b, [Vector2(-4.0, 0.42), Vector2(-3.5, 0.75), Vector2(-2.9, r)], hull)
	b.torus(Vector3(-4.2, 0.0, 0.0), Vector3.RIGHT, 0.78, 0.09, steel, 28, 8)
	_lathe(b, [Vector2(-4.45, 0.75), Vector2(-3.95, 0.82)], Color(hull, StationModel.PAINT))
	b.cylinder(Vector3(-4.35, 0.0, 0.0), Vector3(-4.0, 0.0, 0.0), 0.12, dark, 10)
	for k in 4:
		var a := TAU * k / 4.0 + 0.4
		var d := Vector3(0.0, cos(a), sin(a))
		var bent := Vector3(0.12 if k == 1 else 0.0, 0.0, 0.0)
		b.plate([Vector3(-4.2, 0.0, 0.0) + d * 0.12, Vector3(-4.1, 0.0, 0.0) + d * 0.12,
			Vector3(-4.05, 0.0, 0.0) + d * 0.68 + bent, Vector3(-4.3, 0.0, 0.0) + d * 0.66 + bent], steel)
	for k in 4:
		var a := TAU * k / 4.0
		var d := Vector3(0.0, cos(a), sin(a))
		b.plate([Vector3(-3.0, 0.0, 0.0) + d * r * 0.85, Vector3(-3.6, 0.0, 0.0) + d * 0.6,
			Vector3(-3.9, 0.0, 0.0) + d * 1.25, Vector3(-3.3, 0.0, 0.0) + d * 1.4], hull)
	b.xf = keep
	# Pipes spilling from the break, torn plating, a loose thruster pod.
	for k in 4:
		var a := rng.randf() * TAU
		var d := Vector3(0.0, cos(a), sin(a)) * rng.randf_range(0.3, 0.8)
		b.tube(PackedVector3Array([Vector3(0.6, 0.0, 0.0) + d, Vector3(0.1, 0.0, 0.0) + d * 1.05,
			Vector3(-0.3 - rng.randf() * 0.4, -0.2, 0.0) + d * 1.3]), PackedFloat32Array([0.05, 0.05, 0.045]), 6,
			steel if k % 2 == 0 else dark)
	for k in 3:
		var at := Vector3(rng.randf_range(-1.0, 1.2), -r - 0.05, rng.randf_range(0.6, 1.6) * (1.0 if k % 2 else -1.0))
		var u := Vector3(rng.randf_range(0.5, 0.9), rng.randf_range(0.0, 0.2), 0.0)
		var v := Vector3(0.0, rng.randf_range(0.05, 0.3), rng.randf_range(0.4, 0.7))
		b.plate([at, at + u, at + u + v + Vector3(0.0, 0.1, 0.0), at + v], hull)
	b.capsule(Vector3(-1.4, -r + 0.15, 1.7), Vector3(-0.6, -r + 0.25, 1.9), 0.22, dark)
	_mesh = b.commit()
	return _mesh


## A length of pressure hull from [param x0] to [param x1], ribbed, banded
## near its sound end, its other end torn ragged at the break and open
## ([param break_low]: the break at x0, else at x1).
static func _hull(b: ModelBuilder, rng: RandomNumberGenerator, x0: float, x1: float, r: float, paint: Color,
		band: Color, break_low: bool) -> void:
	var around := 32
	var rows := 10
	var jag := PackedFloat32Array()
	for j in around + 1:
		jag.append(rng.randf_range(0.0, 0.45) * (1.0 if j % 3 else 0.5))
	jag[around] = jag[0]
	var start := b.verts.size()
	for i in rows + 1:
		var t := float(i) / rows
		for j in around + 1:
			var a := TAU * j / around
			var x := lerpf(x0, x1, t)
			var torn := (t == 0.0 and break_low) or (t == 1.0 and not break_low)
			if torn:
				x += jag[j] * (1.0 if break_low else -1.0)
			# Dented where it hit.
			var rr := r * (1.0 - 0.06 * float(torn) - 0.05 * sin(a * 3.0 + x) * float(i % 4 == 0))
			var d := Vector3(0.0, cos(a), sin(a))
			var near_band := absf(x - (x1 - 0.5 if break_low else x0 + 0.5)) < 0.25
			b.add_uv(Vector3(x, 0.0, 0.0) + d * rr, d, band if near_band else paint,
				Vector2(x, a * r) + Vector2.ONE * 100.0)
	for i in rows:
		for j in around:
			var a := start + i * (around + 1) + j
			b.quad(a, a + 1, a + around + 2, a + around + 1)
	# Its inside, dark, seen through the break.
	var inner_x := x0 if break_low else x1
	var depth := (x1 - x0) * 0.8 * (1.0 if break_low else -1.0)
	b.tube(PackedVector3Array([Vector3(inner_x, 0.0, 0.0), Vector3(inner_x + depth, 0.0, 0.0)]),
		PackedFloat32Array([r * 0.97, r * 0.97]), around, Color(0.05, 0.05, 0.05, StationModel.DARK), true)
	# Ribs.
	var x := x0 + 0.4
	while x < x1 - 0.3:
		b.torus(Vector3(x, 0.0, 0.0), Vector3.RIGHT, r + 0.01, 0.04, paint, around, 5)
		x += 0.75


## A surface of revolution about x through [param prof] (x, radius).
static func _lathe(b: ModelBuilder, prof: Array, color: Color) -> void:
	var around := 32
	var start := b.verts.size()
	var count := prof.size()
	for i in count:
		var p: Vector2 = prof[i]
		var d: Vector2 = (prof[mini(i + 1, count - 1)] as Vector2) - prof[maxi(i - 1, 0)]
		var nn := Vector2(-d.y, d.x).normalized()
		for j in around + 1:
			var a := TAU * j / around
			var dir := Vector3(0.0, cos(a), sin(a))
			b.add(Vector3(p.x, 0.0, 0.0) + dir * p.y, Vector3(nn.x, 0.0, 0.0) + dir * nn.y, color)
	for i in count - 1:
		for j in around:
			var a := start + i * (around + 1) + j
			b.quad(a, a + 1, a + around + 2, a + around + 1)
