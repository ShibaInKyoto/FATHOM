class_name DroneModel
extends RefCounted
## MD-02, Meridian Deep's work drone, as a model (nose along +X, its top up
## along +Y, its near side, the arm's side, towards +Z; about 3.6 metres
## from the rear thrusters to the saw before scaling): a rounded float of
## orange syntactic foam over an open tubular frame, the pilot's acrylic
## sphere in a titanium ring at the front, a lamp bar with two work lamps,
## ducted thrusters, a transponder whip, and a hydraulic manipulator arm with
## its hoses ending in a guarded diamond-segment rock saw.
##
## For drone.gdshader: COLOR.a is the part's material (see the constants),
## COLOR.rgb a value of its own (a lamp lens: 1 for the lamp still working).

const PAINT := 0.0
const METAL := 0.2
const RUBBER := 0.4
const GLASS := 0.6
const LENS := 0.8
const STATUS := 1.0
const DARK := 0.3

## The float: its centre and half-size.
const FLOAT_AT := Vector3(0.0, 0.42, 0.0)
const FLOAT_HALF := Vector3(1.2, 0.27, 0.62)
## The pilot's sphere.
const SPHERE_AT := Vector3(0.95, -0.15, 0.0)
const SPHERE_R := 0.45
## The near work lamp's lens, and the status lamp (for their lights).
const NEAR_LAMP := Vector3(1.4, 0.2, 0.45)
const STATUS_LAMP := Vector3(0.85, 0.72, 0.36)
## The saw's hub.
const SAW_AT := Vector3(2.32, -0.58, 0.88)


static func build() -> ArrayMesh:
	var b := Builder.new()
	_float(b)
	_frame(b)
	_sphere(b)
	_lamps(b)
	_thrusters(b)
	_arm(b)
	# The status lamp, the transponder whip, and the tether stub at the rear.
	b.ellipsoid(STATUS_LAMP, Vector3(0.07, 0.05, 0.07), Color(1, 1, 1, STATUS), 10, 6)
	b.cylinder(STATUS_LAMP - Vector3(0, 0.05, 0), STATUS_LAMP - Vector3(0, 0.02, 0), 0.085, Color(0, 0, 0, DARK), 10)
	b.tube(PackedVector3Array([Vector3(-0.6, 0.66, -0.3), Vector3(-0.66, 0.95, -0.33), Vector3(-0.8, 1.3, -0.38),
		Vector3(-0.98, 1.55, -0.42)]), PackedFloat32Array([0.025, 0.014, 0.01, 0.006]), 5, Color(0, 0, 0, DARK))
	b.ellipsoid(Vector3(-0.98, 1.56, -0.42), Vector3.ONE * 0.02, Color(1, 1, 1, METAL), 6, 4)
	b.tube(PackedVector3Array([Vector3(-1.15, 0.25, -0.2), Vector3(-1.45, 0.18, -0.25), Vector3(-1.75, -0.1, -0.3),
		Vector3(-2.0, -0.45, -0.32)]), PackedFloat32Array([0.05, 0.05, 0.05, 0.05]), 8, Color(0.9, 0.85, 0.2, RUBBER))
	return b.commit()


## The buoyancy float: a rounded block, its edges softened, with a raised
## lifting point and grab rails along its top.
static func _float(b: Builder) -> void:
	b.rounded_box(FLOAT_AT, FLOAT_HALF, 7.0, Color(1, 1, 1, PAINT), 40, 20)
	# A lifting eye on top.
	b.torus(FLOAT_AT + Vector3(0.1, FLOAT_HALF.y + 0.06, 0.0), Vector3.FORWARD, 0.07, 0.02, Color(1, 1, 1, METAL), 12, 6)
	# Grab rails along the top edges.
	for sz: float in [-0.48, 0.48]:
		var y := FLOAT_AT.y + FLOAT_HALF.y + 0.05
		b.tube(PackedVector3Array([Vector3(-0.9, y - 0.07, sz), Vector3(-0.85, y, sz), Vector3(0.75, y, sz),
			Vector3(0.8, y - 0.07, sz)]), PackedFloat32Array([0.02, 0.02, 0.02, 0.02]), 6, Color(1, 1, 1, METAL))


## The open frame under the float: posts, rails and skids, with brackets
## at the joints, and the pressure housings and electronics pod inside it.
static func _frame(b: Builder) -> void:
	var c := Color(1, 1, 1, METAL)
	var r := 0.042
	var top := FLOAT_AT.y - FLOAT_HALF.y + 0.02
	var low := -0.62
	for sx: float in [-0.95, 0.55]:
		for sz: float in [-0.55, 0.55]:
			b.tube(PackedVector3Array([Vector3(sx, low, sz), Vector3(sx, top, sz)]), PackedFloat32Array([r, r]), 8, c)
			for y: float in [low, top]:
				b.rounded_box(Vector3(sx, y, sz), Vector3.ONE * 0.065, 4.0, Color(0, 0, 0, DARK), 8, 6)
		b.tube(PackedVector3Array([Vector3(sx, low, -0.55), Vector3(sx, low, 0.55)]), PackedFloat32Array([r, r]), 8, c)
		b.tube(PackedVector3Array([Vector3(sx, top, -0.55), Vector3(sx, top, 0.55)]), PackedFloat32Array([r, r]), 8, c)
	for sz: float in [-0.55, 0.55]:
		b.tube(PackedVector3Array([Vector3(-1.05, low, sz), Vector3(0.65, low, sz)]), PackedFloat32Array([r, r]), 8, c)
		b.tube(PackedVector3Array([Vector3(-0.95, top, sz), Vector3(0.55, top, sz)]), PackedFloat32Array([r, r]), 8, c)
		# A diagonal brace on each side.
		b.tube(PackedVector3Array([Vector3(-0.95, low, sz), Vector3(0.55, top, sz)]), PackedFloat32Array([0.03, 0.03]), 6,
			c)
		# Skids, turned up at the front under the sphere.
		b.tube(PackedVector3Array([Vector3(-0.95, low - 0.16, sz * 0.9), Vector3(0.6, low - 0.16, sz * 0.9),
			Vector3(1.05, low - 0.1, sz * 0.9), Vector3(1.28, low + 0.08, sz * 0.85)]),
			PackedFloat32Array([0.05, 0.05, 0.05, 0.045]), 8, Color(1, 1, 1, PAINT))
		for sx: float in [-0.75, 0.35]:
			b.tube(PackedVector3Array([Vector3(sx, low, sz), Vector3(sx, low - 0.16, sz * 0.9)]),
				PackedFloat32Array([0.03, 0.03]), 6, c)
	# Two white pressure housings and a dark electronics pod.
	for sz: float in [-0.26, 0.26]:
		b.capsule(Vector3(-0.8, -0.22, sz), Vector3(0.35, -0.22, sz), 0.13, Color(0.92, 0.92, 0.9, METAL))
	b.rounded_box(Vector3(-0.3, -0.48, 0.0), Vector3(0.38, 0.1, 0.22), 5.0, Color(0, 0, 0, DARK), 14, 8)


## The pilot's acrylic sphere, seated in a titanium ring with its bolts.
static func _sphere(b: Builder) -> void:
	b.ellipsoid(SPHERE_AT, Vector3.ONE * SPHERE_R, Color(1, 1, 1, GLASS), 28, 18)
	var ring_x := SPHERE_AT.x - 0.18
	var ring_r := sqrt(SPHERE_R * SPHERE_R - 0.18 * 0.18)
	b.torus(Vector3(ring_x, SPHERE_AT.y, SPHERE_AT.z), Vector3.RIGHT, ring_r + 0.02, 0.05, Color(0.8, 0.8, 0.85, METAL),
		28, 8)
	for k in 14:
		var a := TAU * k / 14.0
		var at := Vector3(ring_x + 0.04, SPHERE_AT.y + cos(a) * (ring_r + 0.02), SPHERE_AT.z + sin(a) * (ring_r + 0.02))
		b.ellipsoid(at, Vector3(0.025, 0.02, 0.02), Color(0, 0, 0, DARK), 6, 4)


## The lamp bar across the front and its two work lamps.
static func _lamps(b: Builder) -> void:
	var y := 0.2
	b.tube(PackedVector3Array([Vector3(1.18, y, -0.58), Vector3(1.18, y, 0.58)]), PackedFloat32Array([0.035, 0.035]), 8,
		Color(1, 1, 1, METAL))
	for sz: float in [-0.45, 0.45]:
		var near := sz > 0.0
		b.cylinder(Vector3(1.1, y, sz), Vector3(1.36, y, sz), 0.1, Color(0, 0, 0, DARK), 14)
		b.torus(Vector3(1.37, y, sz), Vector3.RIGHT, 0.095, 0.022, Color(1, 1, 1, METAL), 16, 6)
		b.disc(Vector3(1.375, y, sz), Vector3.RIGHT, 0.085, Color(1.0 if near else 0.0, 1, 1, LENS), 16)
		# Cooling fins round the back of each can.
		for k in 4:
			b.torus(Vector3(1.13 + k * 0.04, y, sz), Vector3.RIGHT, 0.1, 0.012, Color(0, 0, 0, DARK), 14, 4)


## Ducted thrusters: two through the float's top, two at the rear.
static func _thrusters(b: Builder) -> void:
	for sx: float in [-0.55, 0.42]:
		var at := Vector3(sx, FLOAT_AT.y + FLOAT_HALF.y + 0.02, 0.0)
		b.torus(at, Vector3.UP, 0.2, 0.05, Color(0, 0, 0, DARK), 20, 8)
		_propeller(b, at - Vector3(0, 0.02, 0), Vector3.UP, 0.17)
	for sz: float in [-0.38, 0.38]:
		var at := Vector3(-1.32, 0.05, sz)
		b.tube(PackedVector3Array([at - Vector3(0.08, 0, 0), at + Vector3(0.12, 0, 0)]), PackedFloat32Array([0.19, 0.19]),
			20, Color(0, 0, 0, DARK), true)
		b.torus(at + Vector3(0.12, 0, 0), Vector3.RIGHT, 0.19, 0.03, Color(1, 1, 1, PAINT), 20, 6)
		_propeller(b, at, Vector3.RIGHT, 0.16)
		b.tube(PackedVector3Array([at + Vector3(0.12, 0.1, 0), Vector3(-0.95, 0.2, sz)]), PackedFloat32Array([0.03, 0.03]),
			6, Color(1, 1, 1, METAL))


## A propeller in its duct: a hub and four twisted blades.
static func _propeller(b: Builder, at: Vector3, axis: Vector3, radius: float) -> void:
	b.ellipsoid(at, Vector3.ONE * 0.045, Color(1, 1, 1, METAL), 8, 6)
	var u := axis.cross(Vector3.FORWARD if absf(axis.z) < 0.9 else Vector3.RIGHT).normalized()
	var v := axis.cross(u)
	for k in 4:
		var a := TAU * k / 4.0
		var out := u * cos(a) + v * sin(a)
		var side := axis.cross(out).normalized()
		var twist := (side * 0.8 + axis * 0.6).normalized()
		var pts := [at + out * 0.04 - twist * 0.03, at + out * 0.04 + twist * 0.03,
			at + out * radius + twist * 0.045, at + out * radius - twist * 0.045]
		b.plate(pts, Color(0, 0, 0, DARK))


## The manipulator arm on the near side: a turret, upper arm and forearm
## each worked by a hydraulic ram, hoses running along it, and the saw.
static func _arm(b: Builder) -> void:
	var steel := Color(1, 1, 1, METAL)
	var dark := Color(0, 0, 0, DARK)
	var shoulder := Vector3(0.75, -0.42, 0.7)
	var elbow := Vector3(1.6, 0.02, 0.8)
	var wrist := Vector3(2.12, -0.42, 0.84)
	b.cylinder(Vector3(0.7, -0.52, 0.55), Vector3(0.7, -0.52, 0.72), 0.12, dark, 14)
	b.rounded_box(shoulder, Vector3(0.11, 0.1, 0.09), 4.0, Color(1, 1, 1, PAINT), 10, 8)
	# Upper arm and forearm: squared-off beams.
	b.beam(shoulder, elbow, Vector2(0.075, 0.06), Color(1, 1, 1, PAINT))
	b.beam(elbow, wrist, Vector2(0.06, 0.05), Color(1, 1, 1, PAINT))
	for p in [shoulder, elbow, wrist]:
		b.cylinder(p - Vector3(0, 0, 0.1), p + Vector3(0, 0, 0.1), 0.07, dark, 14)
	# Hydraulic rams: a cylinder and its chrome rod.
	_ram(b, shoulder + Vector3(0.1, -0.12, 0.02), elbow + Vector3(-0.25, -0.08, 0.02), 0.035)
	_ram(b, elbow + Vector3(0.08, 0.1, 0.03), wrist + Vector3(-0.12, 0.12, 0.03), 0.028)
	# The wrist rotator and the saw.
	var along := (wrist - elbow).normalized()
	b.cylinder(wrist, wrist + along * 0.14, 0.065, steel, 14)
	_saw(b, SAW_AT)
	b.beam(wrist + along * 0.12, SAW_AT, Vector2(0.04, 0.03), dark)
	# Hoses along the arm, sagging between their clips.
	for k in 2:
		var o := Vector3(0, 0.05 - k * 0.1, 0.09 + k * 0.02)
		b.tube(PackedVector3Array([Vector3(0.4, -0.3, 0.62) + o, shoulder + o + Vector3(0, 0.08, 0),
			shoulder.lerp(elbow, 0.5) + o + Vector3(0, -0.06, 0), elbow + o, elbow.lerp(wrist, 0.5) + o + Vector3(0, -0.05, 0),
			wrist + o]), PackedFloat32Array([0.018, 0.018, 0.018, 0.018, 0.018, 0.018]), 6,
			Color(0, 0, 0, RUBBER) if k == 0 else Color(0.9, 0.85, 0.2, RUBBER))


static func _ram(b: Builder, from: Vector3, to: Vector3, r: float) -> void:
	var mid := from.lerp(to, 0.55)
	b.cylinder(from, mid, r, Color(0, 0, 0, DARK), 10)
	b.cylinder(mid, to, r * 0.55, Color(1.4, 1.4, 1.4, METAL), 8)


## The rock saw facing the camera: a steel disc rimmed with diamond
## segments, its hub, and a guard over its upper half.
static func _saw(b: Builder, hub: Vector3) -> void:
	var r := 0.38
	var steel := Color(1.1, 1.1, 1.1, METAL)
	b.cylinder(hub - Vector3(0, 0, 0.015), hub + Vector3(0, 0, 0.015), r, steel, 40)
	b.cylinder(hub - Vector3(0, 0, 0.05), hub + Vector3(0, 0, 0.05), 0.08, Color(0, 0, 0, DARK), 14)
	b.cylinder(hub + Vector3(0, 0, 0.05), hub + Vector3(0, 0, 0.07), 0.05, steel, 12)
	var segments := 20
	for k in segments:
		var a := TAU * (k + 0.5) / segments
		var out := Vector3(cos(a), sin(a), 0.0)
		var side := Vector3(-sin(a), cos(a), 0.0)
		b.box(hub + out * (r + 0.015), out * 0.022, side * 0.045, Vector3(0, 0, 0.024), Color(0.35, 0.35, 0.35, DARK))
	# The guard: a shell over the top half, its sides closing over the disc.
	var arc := PackedVector3Array()
	var radii := PackedFloat32Array()
	for k in 13:
		var a := lerpf(0.15, PI - 0.15, k / 12.0)
		arc.append(hub + Vector3(cos(a), sin(a), 0.0) * (r + 0.07))
		radii.append(0.06)
	b.tube(arc, radii, 8, Color(1, 1, 1, PAINT), false, Vector3(0, 0, 1), 0.55)


## Accumulates the model's mesh.
class Builder:
	extends RefCounted
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	func add(p: Vector3, n: Vector3, c: Color) -> int:
		verts.append(p)
		normals.append(n.normalized())
		colors.append(c)
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
			pts.append(a - axis * r * (1.0 - sin(t * PI * 0.5)))
			radii.append(r * maxf(cos((1.0 - t) * PI * 0.5), 0.01) if k < 4 else r)
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

	## A beam of rectangular section from [param a] to [param b].
	func beam(a: Vector3, b: Vector3, half: Vector2, color: Color) -> void:
		var fwd := (b - a).normalized()
		var side := fwd.cross(Vector3.BACK).normalized()
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
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh
