class_name StationModel
extends RefCounted
## Meridian Deep, in its rig's own space (x along the station, y up, z
## towards the camera): two habitat modules, their hulls banded and ribbed
## at the ends, flanking a domed hub, joined to it by flanged tunnels (the
## right one through a bellows, where that module has settled); each module
## on saddles and skids whose legs stand in the floor wherever it lies; a
## lattice mast over the hub carrying the beacon; the empty berth of the
## last escape pod on the left module; the escape lock at the right module's
## far end (which the rock has swallowed: see [MeridianStation]).
##
## COLOR.a is each part's material, for station.gdshader: 0 paint (COLOR.rgb
## its colour; UV, offset by 100, where it lies on its hull, for the plate
## seams), 0.2 frame steel (COLOR.rgb a tint), 0.3 dark fittings and rubber,
## 0.6 a viewport (COLOR.r 1 lit, 0.5 failing, 0 dead; COLOR.g which room is
## behind it; UV across the pane in metres), 0.8 a floodlight's lens
## (COLOR.r 1 if it still works), 1 the beacon's lens.

const PAINT := 0.0
const STEEL := 0.2
const DARK := 0.3
const WINDOW := 0.6
const LENS := 0.8
const BEACON := 1.0

const CREAM := Color(0.76, 0.74, 0.66)
const ORANGE := Color(0.86, 0.4, 0.1)
const YELLOW := Color(0.84, 0.62, 0.12)
const FRAME_TINT := Color(0.55, 0.58, 0.62)

const MODULE_R := 1.45
const MODULE_HALF := 3.0
const CAP := 0.62
const RIB_W := 0.07
## Ribs stiffen each end (bounding its orange band); the middle is smooth,
## welded plate.
const RIBS: Array[float] = [-3.0, -2.0, 2.0, 3.0]
const LEFT := Vector3(-6.6, 2.75, 0.0)
const RIGHT := Vector3(6.6, 2.5, 0.0)
## The right module has settled, nose down.
const RIGHT_TILT := -0.05
const HUB := Vector3(0.0, 2.95, 0.0)
const HUB_R := 2.1
const MAST_X := 0.6
const MAST_FOOT := 4.98
## The mast's top, where the cave leaves room for it (it is cut down to
## fit under a lower roof), and the beacon's lens over it.
const MAST_TOP := 8.6
const MAST_LOWEST := 6.6
const BEACON_ABOVE := 0.41
## The cradles under each module, and where their legs stand (module space).
const CRADLES: Array[float] = [-2.0, 2.0]
const LEG_Z: Array[float] = [-0.95, 1.25]
const BEAM_Y := -(MODULE_R + 0.3)
## The viewports: their size, and how far up the hull from its front.
const WINDOW_SIZE := Vector2(0.5, 0.36)
const WINDOW_UP := 0.22
## Where the name is painted: how far round the hull (below the windows).
const NAME_UP := -0.3
## The pod berth on top of the left module (module space).
const BERTH_X := 1.4
## The escape lock: how far it runs past the right module's nose.
const LOCK_FROM := MODULE_HALF + CAP - 0.3
const LOCK_TO := MODULE_HALF + CAP + 1.45
const LOCK_R := 0.95


## Where the left module lies.
static func left_xf() -> Transform3D:
	return Transform3D(Basis(), LEFT)


## Where the right module lies.
static func right_xf() -> Transform3D:
	return Transform3D(Basis(Vector3.BACK, RIGHT_TILT), RIGHT)


## Where the beacon is on a mast topped at [param mast_top].
static func beacon_at(mast_top := MAST_TOP) -> Vector3:
	return Vector3(MAST_X, mast_top + BEACON_ABOVE, 0.0)


## The whole station; [param floor_at] gives the floor's height (y) under a
## point (x, z), for its legs to stand in; [param mast_top] how high its
## mast reaches.
static func build(floor_at: Callable, mast_top := MAST_TOP) -> ArrayMesh:
	var b := ModelBuilder.new()
	var rooms := [[0.0, 1.0, 1.0, 0.5], [0.5, 0.0, 1.0, 0.0]]
	var xfs := [left_xf(), right_xf()]
	for m in 2:
		b.xf = xfs[m]
		_hull(b)
		for i in 4:
			_window(b, -1.5 + i, rooms[m][i], float(i * 3 + m) / 8.0)
		_rails(b)
		_conduits(b)
		_tank(b)
	b.xf = left_xf()
	_end_hatch(b)
	_berth(b)
	b.xf = right_xf()
	_lock(b)
	b.xf = Transform3D.IDENTITY
	_hub(b)
	_tunnels(b)
	for m in 2:
		_cradles(b, xfs[m], floor_at)
	_hub_stand(b, floor_at)
	_mast(b, mast_top)
	_lamps(b, mast_top)
	return b.commit()


## The direction round a module's hull at [param a] (0 the front, towards
## the camera; PI / 2 the top).
static func round_dir(a: float) -> Vector3:
	return Vector3(0.0, sin(a), cos(a))


## A surface of revolution round the x axis through [param profile]
## (x, radius; running towards +x). [param arc] scales the angle round into
## the seam UV (0: no seams).
static func _lathe(b: ModelBuilder, profile: PackedVector2Array, color: Color, around := 40, arc := 0.0) -> void:
	var start := b.verts.size()
	var count := profile.size()
	for i in count:
		var p := profile[i]
		var d := profile[mini(i + 1, count - 1)] - profile[maxi(i - 1, 0)]
		var nn := Vector2(-d.y, d.x).normalized()
		for j in around + 1:
			var a := TAU * j / around
			var dir := round_dir(a)
			var uv := Vector2(p.x, a * arc) + Vector2.ONE * 100.0 if arc > 0.0 else Vector2.ZERO
			b.add_uv(Vector3(p.x, 0.0, 0.0) + dir * p.y, Vector3(nn.x, 0.0, 0.0) + dir * nn.y, color, uv)
	for i in count - 1:
		for j in around:
			var a := start + i * (around + 1) + j
			b.quad(a, a + 1, a + around + 2, a + around + 1)


## A module's hull, in its own space: a cylinder along x with ellipsoidal
## ends, ribbed where the orange band runs round each end.
static func _hull(b: ModelBuilder) -> void:
	var r := MODULE_R
	var paint := Color(CREAM, PAINT)
	var band := Color(ORANGE, PAINT)
	var spans: Array = [[-MODULE_HALF, -2.0, band], [-2.0, 2.0, paint], [2.0, MODULE_HALF, band]]
	for s: Array in spans:
		_lathe(b, PackedVector2Array([Vector2(s[0] + RIB_W, r), Vector2(s[1] - RIB_W, r)]), s[2], 48, r)
	for x: float in RIBS:
		_lathe(b, PackedVector2Array([Vector2(x - RIB_W, r), Vector2(x - RIB_W * 0.45, r + 0.05),
			Vector2(x + RIB_W * 0.45, r + 0.05), Vector2(x + RIB_W, r)]), paint, 48)
	for sgn: float in [-1.0, 1.0]:
		var prof := PackedVector2Array()
		for k in 13:
			var t := k / 12.0 if sgn > 0.0 else 1.0 - k / 12.0
			prof.append(Vector2(sgn * (MODULE_HALF + RIB_W + CAP * sin(t * PI * 0.5)), r * cos(t * PI * 0.5)))
		_lathe(b, prof, paint, 48, r)


## The corners of a rounded rectangle round [param c] across [param u] and
## [param v], [param half] its half size, its corners of radius [param r].
static func _rounded_rect(c: Vector3, u: Vector3, v: Vector3, half: Vector2, r: float,
		steps := 4) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var corners := [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]
	for k in 4:
		var s: Vector2 = corners[k]
		var cc := Vector2(s.x * (half.x - r), s.y * (half.y - r))
		for i in steps + 1:
			var a := PI * 0.5 * (k + float(i) / steps)
			var q := cc + Vector2(cos(a), sin(a)) * r
			pts.append(c + u * q.x + v * q.y)
	return pts


## A pane fanned from its centre [param c] round [param loop], facing
## [param n], [param u] and [param v] across it (its UV), [param bulge] how
## far its middle stands proud.
static func _pane(b: ModelBuilder, c: Vector3, loop: PackedVector3Array, n: Vector3, u: Vector3, v: Vector3,
		color: Color, bulge := 0.0) -> void:
	var centre := b.add_uv(c + n * bulge, n, color, Vector2.ZERO)
	var first := b.verts.size()
	for p in loop:
		var q := p - c
		b.add_uv(p, (n + q * bulge * 4.0).normalized(), color, Vector2(q.dot(u), q.dot(v)))
	for k in loop.size():
		b.tri(centre, first + k, first + (k + 1) % loop.size())


## A viewport in a module's hull at [param x], [param state] its light (1
## lit, 0.5 failing, 0 dead), [param room] which room is behind it.
static func _window(b: ModelBuilder, x: float, state: float, room: float) -> void:
	var n := round_dir(WINDOW_UP)
	var up := round_dir(WINDOW_UP + PI * 0.5)
	var c := Vector3(x, 0.0, 0.0) + n * (MODULE_R + 0.014)
	var half := WINDOW_SIZE * 0.5
	_pane(b, c, _rounded_rect(c, Vector3.RIGHT, up, half, 0.09), n, Vector3.RIGHT, up,
		Color(state, room, 0.0, WINDOW), 0.006)
	# Its retaining frame, bolted round, and the eyebrow over it that keeps
	# the silt off.
	var frame := _rounded_rect(c + n * 0.006, Vector3.RIGHT, up, half + Vector2(0.035, 0.035), 0.11)
	b.ring_tube(frame, n, 0.034, 8, Color(FRAME_TINT, STEEL))
	for k in 10:
		var p := frame[int(k * frame.size() / 10.0)]
		b.cylinder(p + (p - c).normalized() * 0.035, p + (p - c).normalized() * 0.035 + n * 0.03, 0.013,
			Color(FRAME_TINT, STEEL), 6)
	var brow := c + up * (half.y + 0.09)
	b.box(brow + n * 0.03, Vector3.RIGHT * (half.x + 0.06), up * 0.012, n * 0.05, Color(CREAM, PAINT))


## A handrail along the top of a module, on yellow stanchions.
static func _rails(b: ModelBuilder) -> void:
	var a := 1.12
	var d := round_dir(a)
	var rail := Color(YELLOW, PAINT)
	for k in 6:
		var x := -2.5 + k
		if absf(x - BERTH_X) < 0.7:
			continue
		b.cylinder(Vector3(x, 0, 0) + d * (MODULE_R - 0.02), Vector3(x, 0, 0) + d * (MODULE_R + 0.34), 0.022, rail, 6)
	b.capsule(Vector3(-2.6, 0, 0) + d * (MODULE_R + 0.34), Vector3(0.55, 0, 0) + d * (MODULE_R + 0.34), 0.026,
		rail)
	b.capsule(Vector3(2.15, 0, 0) + d * (MODULE_R + 0.34), Vector3(2.6, 0, 0) + d * (MODULE_R + 0.34), 0.026,
		rail)


## Conduits running along a module's front, low down, clamped at each rib
## and turning into the hull at their ends.
static func _conduits(b: ModelBuilder) -> void:
	for k in 2:
		var a := -0.5 - k * 0.14
		var d := round_dir(a)
		var r := MODULE_R + 0.11
		var pts := PackedVector3Array([Vector3(-3.25, 0, 0) + d * (MODULE_R - 0.05), Vector3(-3.2, 0, 0) + d * r,
			Vector3(-3.05, 0, 0) + d * r, Vector3(3.05, 0, 0) + d * r, Vector3(3.2, 0, 0) + d * r,
			Vector3(3.25, 0, 0) + d * (MODULE_R - 0.05)])
		var radii := PackedFloat32Array()
		for p in pts:
			radii.append(0.045 - k * 0.012)
		b.tube(pts, radii, 8, Color(0.5, 0.5, 0.5, STEEL))
	for x: float in [-2.6, -1.0, 0.6, 2.6]:
		var d := round_dir(-0.57)
		var up := round_dir(-0.57 + PI * 0.5)
		b.box(Vector3(x, 0, 0) + d * (MODULE_R + 0.1), Vector3.RIGHT * 0.04, up * 0.16, d * 0.06,
			Color(0.08, 0.08, 0.08, DARK))


## The gas tank slung under a module's front, on its straps.
static func _tank(b: ModelBuilder) -> void:
	var y := -1.5
	var z := 0.95
	b.capsule(Vector3(-1.55, y, z), Vector3(1.55, y, z), 0.3, Color(YELLOW, PAINT))
	for x: float in [-0.9, 0.9]:
		b.torus(Vector3(x, y, z), Vector3.RIGHT, 0.315, 0.025, Color(0.1, 0.1, 0.1, DARK), 20, 6)
		b.beam(Vector3(x, y + 0.2, z - 0.2), Vector3(x, -0.95, 0.55), Vector2(0.03, 0.05), Color(FRAME_TINT, STEEL))
	# Its valve and gauge.
	b.cylinder(Vector3(1.85, y, z), Vector3(2.0, y, z), 0.06, Color(0.6, 0.6, 0.6, STEEL), 8)
	b.torus(Vector3(2.02, y, z), Vector3.RIGHT, 0.07, 0.012, Color(0.1, 0.1, 0.1, DARK), 12, 5)


## The hatch on the left module's outer end.
static func _end_hatch(b: ModelBuilder) -> void:
	var tip := -(MODULE_HALF + RIB_W + CAP)
	var c := Vector3(tip - 0.02, -0.15, 0.0)
	b.cylinder(c + Vector3(0.3, 0, 0), c - Vector3(0.12, 0, 0), 0.5, Color(ORANGE, PAINT), 20)
	b.cylinder(c - Vector3(0.12, 0, 0), c - Vector3(0.2, 0, 0), 0.44, Color(CREAM, PAINT), 20)
	_wheel(b, c - Vector3(0.28, 0, 0), Vector3.LEFT, 0.2)
	b.box(c + Vector3(-0.15, 0.5, 0.0), Vector3.RIGHT * 0.06, Vector3.UP * 0.06, Vector3.BACK * 0.2,
		Color(FRAME_TINT, STEEL))


## A hatch's handwheel at [param c] facing [param n].
static func _wheel(b: ModelBuilder, c: Vector3, n: Vector3, r: float) -> void:
	var dark := Color(0.12, 0.12, 0.12, DARK)
	b.torus(c, n, r, 0.022, dark, 20, 6)
	b.cylinder(c - n * 0.1, c + n * 0.01, 0.04, dark, 8)
	var u := n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized()
	var v := n.cross(u)
	for k in 3:
		var a := TAU * k / 3.0 + 0.3
		b.beam(c, c + (u * cos(a) + v * sin(a)) * r, Vector2(0.012, 0.012), dark)


## The berth the last escape pod left from (log_10): an open docking ring
## on the left module's back, its clamps sprung wide, the umbilicals torn
## off and trailing down the hull.
static func _berth(b: ModelBuilder) -> void:
	var top := Vector3(BERTH_X, MODULE_R, 0.0)
	b.cylinder(top - Vector3(0, 0.3, 0), top + Vector3(0, 0.28, 0), 0.62, Color(ORANGE, PAINT), 28)
	b.torus(top + Vector3(0, 0.3, 0), Vector3.UP, 0.6, 0.075, Color(0.6, 0.6, 0.62, STEEL), 32, 8)
	# The mouth the pod sealed against, and the dark hatch below it.
	b.disc(top + Vector3(0, 0.29, 0), Vector3.UP, 0.53, Color(0.03, 0.03, 0.03, DARK), 28)
	b.torus(top + Vector3(0, 0.3, 0), Vector3.UP, 0.42, 0.03, Color(0.1, 0.1, 0.1, DARK), 28, 6)
	for k in 4:
		var a := TAU * (k + 0.5) / 4.0
		var out := Vector3(cos(a), 0.0, sin(a))
		var hinge := top + out * 0.66 + Vector3(0, 0.26, 0)
		var tip := hinge + (out * 0.55 + Vector3(0, 0.5, 0)).normalized() * 0.55
		b.beam(hinge, tip, Vector2(0.05, 0.07), Color(FRAME_TINT, STEEL))
		b.box(tip, out * 0.06, Vector3.UP * 0.05, out.cross(Vector3.UP) * 0.08, Color(0.1, 0.1, 0.1, DARK))
	# The umbilicals, torn and hanging down the hull's front.
	var hose := Color(0.07, 0.07, 0.07, DARK)
	for h in 2:
		var pts := PackedVector3Array()
		var radii := PackedFloat32Array()
		var x0 := BERTH_X - 0.25 + h * 0.45
		for k in 9:
			var t := k / 8.0
			var a := lerpf(1.25, 0.62 - h * 0.12, t)
			var x := x0 + t * (0.3 + h * 0.35)
			pts.append(Vector3(x, 0, 0) + round_dir(a) * (MODULE_R + 0.07 + 0.08 * sin(t * PI)))
			radii.append(0.05 - h * 0.012)
		# Its torn end hangs free.
		var last := pts[pts.size() - 1]
		pts.append(last + Vector3(0.05, -0.25, 0.12))
		radii.append(0.04 - h * 0.012)
		b.tube(pts, radii, 8, hose)


## The escape lock beyond the right module's nose, in its own space.
static func _lock(b: ModelBuilder) -> void:
	var orange := Color(ORANGE, PAINT)
	_lathe(b, PackedVector2Array([Vector2(LOCK_FROM, LOCK_R), Vector2(LOCK_TO - 0.15, LOCK_R)]), orange, 32, LOCK_R)
	for x: float in [LOCK_FROM + 0.15, LOCK_TO - 0.15]:
		b.torus(Vector3(x, 0, 0), Vector3.RIGHT, LOCK_R + 0.02, 0.06, Color(FRAME_TINT, STEEL), 32, 6)
	b.cylinder(Vector3(LOCK_TO - 0.15, 0, 0), Vector3(LOCK_TO, 0, 0), LOCK_R * 0.86, Color(CREAM, PAINT), 28)
	_wheel(b, Vector3(LOCK_TO + 0.06, 0, 0), Vector3.RIGHT, 0.28)


## The hub: a sphere banded at its middle, a heavy porthole facing out of
## the trench, dead side ports, the hatch on its crown and the mast's socket.
static func _hub(b: ModelBuilder) -> void:
	var keep := b.xf
	# Its sphere, turned so its poles are up and down.
	b.xf = Transform3D(Basis(Vector3.BACK, PI * 0.5), HUB)
	var prof := PackedVector2Array()
	for k in 25:
		var t := -PI * 0.5 + PI * k / 24.0
		prof.append(Vector2(sin(t) * HUB_R, cos(t) * HUB_R))
	_lathe(b, prof, Color(CREAM, PAINT), 56, HUB_R)
	b.xf = keep
	b.torus(HUB, Vector3.UP, HUB_R + 0.01, 0.065, Color(ORANGE, PAINT), 56, 8)
	b.torus(HUB + Vector3(0, 1.05, 0), Vector3.UP, sqrt(HUB_R * HUB_R - 1.05 * 1.05) + 0.01, 0.035,
		Color(CREAM, PAINT), 48, 6)
	_porthole(b, Vector3(0.0, sin(0.14), cos(0.14)), 0.44, 1.0, 0.95)
	for s: float in [-1.0, 1.0]:
		_porthole(b, Vector3(sin(0.9) * s, sin(0.1), cos(0.9)).normalized(), 0.26, 0.0, 0.3)
	# The crown hatch, leaning off the mast's way.
	var up := Vector3(-sin(0.38), cos(0.38), 0.0)
	var side := up.cross(Vector3.BACK).normalized()
	var base := HUB + up * (HUB_R - 0.2)
	b.cylinder(base, base + up * 0.45, 0.48, Color(CREAM, PAINT), 24)
	b.cylinder(base + up * 0.45, base + up * 0.53, 0.54, Color(ORANGE, PAINT), 24)
	_wheel(b, base + up * 0.6, up, 0.22)
	b.box(base + up * 0.5 + side * 0.56, side * 0.07, up * 0.06, Vector3.BACK * 0.18, Color(FRAME_TINT, STEEL))
	# Pad eyes for the crane that lowered it.
	for k in 4:
		var a := TAU * (k + 0.5) / 4.0
		var d := Vector3(cos(a) * 0.55, 0.83, sin(a) * 0.55).normalized()
		b.torus(HUB + d * (HUB_R + 0.06), Vector3(-sin(a), 0, cos(a)), 0.08, 0.022, Color(FRAME_TINT, STEEL), 12, 5)
	# The mast's socket.
	b.cylinder(Vector3(MAST_X, MAST_FOOT - 0.5, 0), Vector3(MAST_X, MAST_FOOT + 0.12, 0), 0.27,
		Color(FRAME_TINT, STEEL), 16)


## A porthole in the hub facing [param d]: a domed pane of [param r] in a
## heavy bolted flange.
static func _porthole(b: ModelBuilder, d: Vector3, r: float, state: float, room: float) -> void:
	d = d.normalized()
	var u := Vector3.UP.cross(d).normalized()
	var v := d.cross(u)
	var c := HUB + d * (HUB_R + 0.04)
	var loop := PackedVector3Array()
	for k in 28:
		var a := TAU * k / 28.0
		loop.append(c + (u * cos(a) + v * sin(a)) * r)
	_pane(b, c, loop, d, u, v, Color(state, room, 0.0, WINDOW), 0.03)
	var steel := Color(FRAME_TINT, STEEL)
	b.cylinder(c - d * 0.2, c + d * 0.02, r * 1.4, Color(CREAM, PAINT), 32)
	b.torus(c + d * 0.02, d, r + 0.03, 0.05, steel, 32, 8)
	for k in 12:
		var a := TAU * k / 12.0
		var p := c + (u * cos(a) + v * sin(a)) * r * 1.22
		b.cylinder(p, p + d * 0.04, 0.022, steel, 6)


## The tunnels from the hub to each module: flanged at both ends, the right
## one through a bellows.
static func _tunnels(b: ModelBuilder) -> void:
	var steel := Color(FRAME_TINT, STEEL)
	for s: float in [-1.0, 1.0]:
		var y := LEFT.y if s < 0.0 else (right_xf() * Vector3(-MODULE_HALF, 0, 0)).y
		var a := Vector3(s * 1.85, y, 0.0)
		var c := Vector3(s * 3.2, y, 0.0)
		var r := 0.66
		var paint := Color(CREAM, PAINT)
		if s < 0.0:
			b.cylinder(a, c, r, paint, 28)
		else:
			# A bellows: the right module has settled, and pulls against it.
			var prof := PackedVector2Array()
			for k in 13:
				var t := k / 12.0
				prof.append(Vector2(lerpf(2.25, 2.95, t), r + (0.06 if k % 2 == 1 else 0.0)))
			var keep := b.xf
			b.xf = Transform3D(Basis(), Vector3(0, y, 0))
			_lathe(b, prof, Color(0.1, 0.1, 0.1, DARK), 28)
			b.xf = keep
			b.cylinder(a, Vector3(2.3, y, 0), r, paint, 28)
			b.cylinder(Vector3(2.9, y, 0), c, r, paint, 28)
		for x: float in [2.12, 3.05]:
			var f := Vector3(s * x, y, 0.0)
			b.cylinder(f - Vector3(0.05, 0, 0), f + Vector3(0.05, 0, 0), r + 0.12, steel, 28)
			for k in 10:
				var ang := TAU * k / 10.0
				var p := f + Vector3(0.0, sin(ang), cos(ang)) * (r + 0.07)
				b.cylinder(p - Vector3(0.08, 0, 0), p + Vector3(0.08, 0, 0), 0.02, steel, 6)


## The saddles under a module, the skids joining them and their legs down
## to mud mats in the floor.
static func _cradles(b: ModelBuilder, xf: Transform3D, floor_at: Callable) -> void:
	var steel := Color(FRAME_TINT, STEEL)
	for x: float in CRADLES:
		# The saddle hugging the hull's underside, round the rib.
		var arc := []
		for k in 13:
			arc.append(-PI + 0.55 + (PI - 1.1) * k / 12.0)
		for k in 12:
			var a0: float = arc[k]
			var a1: float = arc[k + 1]
			var p0 := Vector3(x, 0, 0) + round_dir(a0) * (MODULE_R + 0.1)
			var p1 := Vector3(x, 0, 0) + round_dir(a1) * (MODULE_R + 0.1)
			var mid := (p0 + p1) * 0.5
			var t := (p1 - p0) * 0.5
			var out := round_dir((a0 + a1) * 0.5)
			_xbox(b, xf, mid, Vector3.RIGHT * 0.11, t * 1.08, out * 0.05, steel)
		# Its web down to the cross-beam.
		for a: float in [-PI * 0.5 - 0.75, -PI * 0.5, -PI * 0.5 + 0.75]:
			var top := Vector3(x, 0, 0) + round_dir(a) * (MODULE_R + 0.12)
			_xbeam(b, xf, top, Vector3(x, BEAM_Y, top.z), Vector2(0.05, 0.035), steel)
		_xbeam(b, xf, Vector3(x, BEAM_Y, LEG_Z[0] - 0.12), Vector3(x, BEAM_Y, LEG_Z[1] + 0.12), Vector2(0.1, 0.07),
			steel)
	# Skids along each side, joining the cradles.
	for z: float in LEG_Z:
		_xbeam(b, xf, Vector3(CRADLES[0] - 0.6, BEAM_Y, z), Vector3(CRADLES[1] + 0.6, BEAM_Y, z), Vector2(0.08, 0.06),
			steel)
	# Legs: straight down from each cradle's ends into the floor.
	var feet := []
	for x: float in CRADLES:
		for z: float in LEG_Z:
			var top := xf * Vector3(x, BEAM_Y - 0.08, z)
			var ground: float = floor_at.call(top.x, top.z)
			if ground > top.y - 0.15:
				feet.append([top, top])
				continue
			var foot := Vector3(top.x, ground, top.z)
			b.beam(top, foot - Vector3(0, 0.25, 0), Vector2(0.075, 0.075), steel)
			_mat(b, foot, floor_at)
			feet.append([top, foot])
	# Cross-braced between the cradles, front and back.
	for side in 2:
		var a: Array = feet[side]
		var c: Array = feet[2 + side]
		if (a[0] as Vector3).distance_to(a[1]) < 0.4 or (c[0] as Vector3).distance_to(c[1]) < 0.4:
			continue
		for pair: Array in [[a[0], c[1]], [c[0], a[1]]]:
			var p: Vector3 = pair[0]
			var q: Vector3 = pair[1]
			b.beam(p.lerp(q, 0.04), p.lerp(q, 0.96) + Vector3(0, 0.12, 0), Vector2(0.05, 0.015), steel)


## A box in the space [param xf].
static func _xbox(b: ModelBuilder, xf: Transform3D, c: Vector3, ax: Vector3, ay: Vector3, az: Vector3,
		color: Color) -> void:
	b.box(xf * c, xf.basis * ax, xf.basis * ay, xf.basis * az, color)


## A beam in the space [param xf].
static func _xbeam(b: ModelBuilder, xf: Transform3D, p: Vector3, q: Vector3, half: Vector2, color: Color) -> void:
	b.beam(xf * p, xf * q, half, color)


## A mud mat under a leg at [param foot], laid on the floor's slope.
static func _mat(b: ModelBuilder, foot: Vector3, floor_at: Callable) -> void:
	var e := 0.3
	var hx: float = floor_at.call(foot.x + e, foot.z) - floor_at.call(foot.x - e, foot.z)
	var hz: float = floor_at.call(foot.x, foot.z + e) - floor_at.call(foot.x, foot.z - e)
	var n := Vector3(-hx / (2.0 * e), 1.0, -hz / (2.0 * e)).normalized()
	var u := n.cross(Vector3.BACK).normalized()
	var v := u.cross(n)
	b.box(foot - n * 0.01, u * 0.3, n * 0.035, v * 0.3, Color(FRAME_TINT * 0.8, STEEL))


## The hub's stand: a ring under it and four splayed legs.
static func _hub_stand(b: ModelBuilder, floor_at: Callable) -> void:
	var steel := Color(FRAME_TINT, STEEL)
	var ring_y := HUB.y - 1.72
	var ring_r := sqrt(HUB_R * HUB_R - 1.72 * 1.72) + 0.06
	b.torus(Vector3(0, ring_y, 0), Vector3.UP, ring_r, 0.08, steel, 32, 8)
	for k in 4:
		var a := TAU * (k + 0.5) / 4.0
		var top := Vector3(cos(a) * ring_r, ring_y, sin(a) * ring_r)
		var at := Vector3(cos(a) * (ring_r + 0.7), 0.0, sin(a) * (ring_r + 0.45))
		var ground: float = floor_at.call(at.x, at.z)
		if ground > top.y - 0.2:
			continue
		var foot := Vector3(at.x, ground, at.z)
		b.cylinder(top, foot + (foot - top).normalized() * 0.25, 0.085, steel, 10)
		_mat(b, foot, floor_at)


## The lattice mast over the hub, its spar with an antenna and a dish
## hanging loose, and the beacon at its top.
static func _mast(b: ModelBuilder, top: float) -> void:
	var steel := Color(FRAME_TINT, STEEL)
	var chords := []
	for k in 3:
		var a := PI * 0.5 + TAU * k / 3.0
		chords.append(Vector3(MAST_X + cos(a) * 0.19, 0.0, sin(a) * 0.19))
	for c: Vector3 in chords:
		b.cylinder(c + Vector3(0, MAST_FOOT, 0), c + Vector3(0, top, 0), 0.032, steel, 6)
	var step := 0.42
	var levels := int((top - MAST_FOOT) / step)
	for i in levels:
		var y0 := MAST_FOOT + i * step
		for k in 3:
			var c0: Vector3 = chords[k]
			var c1: Vector3 = chords[(k + 1) % 3]
			var from := c0 if i % 2 == 0 else c1
			var to := c1 if i % 2 == 0 else c0
			b.cylinder(from + Vector3(0, y0, 0), to + Vector3(0, y0 + step, 0), 0.016, steel, 5)
			if i % 2 == 0:
				b.cylinder(c0 + Vector3(0, y0, 0), c1 + Vector3(0, y0, 0), 0.018, steel, 5)
	# The spar, its whip antenna and the dish that has come loose.
	var spar_y := top - 0.95
	b.beam(Vector3(MAST_X - 1.25, spar_y, 0), Vector3(MAST_X + 1.05, spar_y, 0), Vector2(0.045, 0.045), steel)
	var whip := Vector3(MAST_X + 0.98, spar_y, 0)
	b.tube(PackedVector3Array([whip, whip + Vector3(0.03, 0.6, 0), whip + Vector3(0.1, 1.15, 0.02)]),
		PackedFloat32Array([0.02, 0.014, 0.006]), 5, steel)
	var hang := Vector3(MAST_X - 1.18, spar_y - 0.05, 0)
	var dish_at := hang + Vector3(-0.05, -0.42, 0.1)
	var facing := Vector3(-0.35, -0.75, 0.55).normalized()
	b.cylinder(hang, dish_at, 0.018, steel, 5)
	var keep := b.xf
	var dx := facing
	var dy := dx.cross(Vector3.UP).normalized()
	b.xf = Transform3D(Basis(dx, dy, dx.cross(dy)), dish_at)
	var prof := PackedVector2Array()
	for k in 7:
		var r := 0.38 * k / 6.0
		prof.append(Vector2(r * r * 0.9, r))
	_lathe(b, prof, Color(CREAM, PAINT), 24)
	b.cylinder(Vector3.ZERO, Vector3(0.22, 0, 0), 0.02, steel, 5)
	b.xf = keep
	# The beacon: a lens in a cage under a cap.
	var dark := Color(0.08, 0.08, 0.08, DARK)
	b.cylinder(Vector3(MAST_X, top, 0), Vector3(MAST_X, top + 0.06, 0), 0.32, steel, 16)
	b.cylinder(Vector3(MAST_X, top + 0.06, 0), Vector3(MAST_X, top + 0.16, 0), 0.2, dark, 16)
	b.cylinder(Vector3(MAST_X, top + 0.16, 0), Vector3(MAST_X, top + 0.66, 0), 0.16,
		Color(1, 1, 1, BEACON), 16)
	for k in 4:
		var a := TAU * (k + 0.5) / 4.0
		var p := Vector3(MAST_X + cos(a) * 0.22, 0, sin(a) * 0.22)
		b.cylinder(p + Vector3(0, top + 0.1, 0), p + Vector3(0, top + 0.72, 0), 0.016, dark, 5)
	b.cylinder(Vector3(MAST_X, top + 0.7, 0), Vector3(MAST_X, top + 0.76, 0), 0.25, dark, 16)
	b.tube(PackedVector3Array([Vector3(MAST_X, top + 0.76, 0), Vector3(MAST_X, top + 0.9, 0)]),
		PackedFloat32Array([0.2, 0.03]), 12, dark)


## Floodlights on brackets: one on the hub still lit, the rest dead.
static func _lamps(b: ModelBuilder, mast_top: float) -> void:
	var hub_dir := Vector3(-0.45, -0.42, 0.79).normalized()
	var left_dir := round_dir(0.95)
	var right_dir := round_dir(0.95)
	var lamps := [[HUB + hub_dir * (HUB_R - 0.05), hub_dir, Vector3(-0.2, -0.45, 1.0), 1.0],
		[left_xf() * (Vector3(-2.55, 0, 0) + left_dir * (MODULE_R - 0.05)), left_dir, Vector3(0.1, -0.2, 1.0), 0.0],
		[right_xf() * (Vector3(2.55, 0, 0) + right_dir * (MODULE_R - 0.05)), right_xf().basis * right_dir,
			Vector3(0.25, -0.3, 1.0), 0.0],
		[Vector3(MAST_X, lerpf(MAST_FOOT, mast_top, 0.45), 0.2), Vector3.BACK, Vector3(-0.2, -0.8, 1.0), 0.0]]
	var dark := Color(0.12, 0.12, 0.12, DARK)
	for l: Array in lamps:
		var mount: Vector3 = l[0]
		var at: Vector3 = mount + (l[1] as Vector3) * 0.3
		var d: Vector3 = (l[2] as Vector3).normalized()
		b.beam(mount, at, Vector2(0.035, 0.035), Color(FRAME_TINT, STEEL))
		b.rounded_box(at, Vector3(0.13, 0.13, 0.13), 4.0, dark, 12, 6)
		b.cylinder(at, at + d * 0.2, 0.14, dark, 12)
		b.disc(at + d * 0.205, d, 0.115, Color(l[3], 0.0, 0.0, LENS), 12)
