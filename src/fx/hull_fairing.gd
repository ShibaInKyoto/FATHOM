class_name HullFairing
extends RefCounted
## A submarine's fairing: a smooth body lofted through superellipse sections
## set at stations along it. Its UVs are spaced evenly by distance so painted
## lettering keeps its shape: u runs from stern to bow, v round each section
## from the keel, up the near (+Z) side (0.25), over the deck (0.5) and down
## the far side (0.75). tools/art/hull_maps.py paints maps to fit.

## Stations: x, centre height, height above and below the centre, half-width,
## and how square the upper and lower halves are (2 is round).
var stations: Array
var x0: float
var x1: float
var nu: int
var nv: int
var _grid := PackedVector3Array()
var _theta_cache: Dictionary[Vector2i, float] = {}


func _init(rows: Array, along := 72, around := 80) -> void:
	stations = rows
	x0 = rows[0][0]
	x1 = rows[rows.size() - 1][0]
	nu = along
	nv = around


## The section at [param x], eased between the stations: x, centre, heights,
## half-width and squareness, as in a station row.
func station(x: float) -> PackedFloat32Array:
	var n := stations.size()
	x = clampf(x, x0, x1)
	var k := 0
	while k < n - 2 and x > float(stations[k + 1][0]):
		k += 1
	var sx0: float = stations[k][0]
	var sx1: float = stations[k + 1][0]
	var h := sx1 - sx0
	var t := (x - sx0) / h
	var out := PackedFloat32Array([x])
	for c in range(1, 7):
		var v0: float = stations[k][c]
		var v1: float = stations[k + 1][c]
		var m0 := _slope(k, c) * h
		var m1 := _slope(k + 1, c) * h
		var t2 := t * t
		var t3 := t2 * t
		out.append((2 * t3 - 3 * t2 + 1) * v0 + (t3 - 2 * t2 + t) * m0 + (-2 * t3 + 3 * t2) * v1 + (t3 - t2) * m1)
	return out


## Height of the top of the fairing at [param x], [param z] from the centreline.
func deck_y(x: float, z: float) -> float:
	var s := station(x)
	var f := clampf(absf(z) / s[4], 0.0, 1.0)
	return s[1] + s[2] * pow(1.0 - pow(f, s[5]), 1.0 / s[5])


## Height of the underside of the fairing at [param x], [param z] from the centreline.
func keel_y(x: float, z: float) -> float:
	var s := station(x)
	var f := clampf(absf(z) / s[4], 0.0, 1.0)
	return s[1] - s[3] * pow(1.0 - pow(f, s[6]), 1.0 / s[6])


## Half-width of the fairing at [param x] and height [param y].
func side_z(x: float, y: float) -> float:
	var s := station(x)
	var above := y >= s[1]
	var f := clampf(absf(y - s[1]) / (s[2] if above else s[3]), 0.0, 1.0)
	var n := s[5] if above else s[6]
	return s[4] * pow(1.0 - pow(f, n), 1.0 / n)


## The skin on its nu by nv grid: rows from stern to bow, each running round
## its section by even steps of distance.
func grid() -> PackedVector3Array:
	if not _grid.is_empty():
		return _grid
	var fine := 160
	for i in nu + 1:
		var x := lerpf(x0, x1, float(i) / nu)
		var s := station(x)
		var ring := PackedVector3Array()
		var lengths := PackedFloat32Array()
		for k in fine + 1:
			var p := section_point(s, -PI * 0.5 + TAU * k / fine)
			lengths.append(0.0 if k == 0 else lengths[k - 1] + p.distance_to(ring[k - 1]))
			ring.append(p)
		var total := lengths[fine]
		var k := 0
		for j in nv + 1:
			var target := total * j / nv
			while k < fine - 1 and lengths[k + 1] < target:
				k += 1
			var f := clampf((target - lengths[k]) / maxf(lengths[k + 1] - lengths[k], 1e-9), 0.0, 1.0)
			var p := ring[k].lerp(ring[k + 1], f)
			_grid.append(Vector3(x, p.y, p.z))
	return _grid


## The skin as a mesh; [param wear] (func(u, v) -> Color) marks wear and grime.
func mesh(wear: Callable = Callable()) -> ArrayMesh:
	var g := grid()
	var row := nv + 1
	var along := nu
	var around := nv
	var fn := func(u: float, v: float) -> Vector3:
		return g[roundi(u * along) * row + roundi(v * around)]
	return HullMesh.surface(fn, nu, nv, false, Callable(), wear)


## A point [param lift] off the skin at [param x], [param v] of the way round.
func on_skin(x: float, v: float, lift: float) -> Vector3:
	var s := station(x)
	var key := Vector2i(roundi(x * 1000.0), roundi(v * 1000.0))
	if not _theta_cache.has(key):
		_theta_cache[key] = _theta_for(s, v)
	var theta: float = _theta_cache[key]
	var a := section_point(s, -PI * 0.5 + TAU * theta)
	var b := section_point(s, -PI * 0.5 + TAU * theta + 0.01)
	var tangent := (b - a).normalized()
	var out := Vector3(0.0, -tangent.z, tangent.y)
	return Vector3(x, a.y, a.z) + out * lift


## The outward normal of the skin at [param x], [param v] of the way round.
func normal_at(x: float, v: float) -> Vector3:
	return (on_skin(x, v, 0.05) - on_skin(x, v, 0.0)).normalized()


static func section_point(s: PackedFloat32Array, theta: float) -> Vector3:
	var sn := sin(theta)
	var cs := cos(theta)
	var n := s[5] if sn >= 0.0 else s[6]
	var y := s[1] + (s[2] if sn >= 0.0 else s[3]) * signf(sn) * pow(absf(sn), 2.0 / n)
	var z := s[4] * signf(cs) * pow(absf(cs), 2.0 / n)
	return Vector3(0.0, y, z)


## The angle (as a share of a turn from the keel) [param v] of the way round a section by distance.
func _theta_for(s: PackedFloat32Array, v: float) -> float:
	var fine := 160
	var prev := section_point(s, -PI * 0.5)
	var lengths := PackedFloat32Array([0.0])
	for k in range(1, fine + 1):
		var p := section_point(s, -PI * 0.5 + TAU * k / fine)
		lengths.append(lengths[k - 1] + p.distance_to(prev))
		prev = p
	var target := lengths[fine] * v
	for k in fine:
		if lengths[k + 1] >= target:
			return (k + (target - lengths[k]) / maxf(lengths[k + 1] - lengths[k], 1e-9)) / fine
	return 1.0


func _slope(k: int, c: int) -> float:
	var n := stations.size()
	var a := maxi(k - 1, 0)
	var b := mini(k + 1, n - 1)
	var rise: float = stations[b][c] - stations[a][c]
	var run: float = stations[b][0] - stations[a][0]
	return rise / run
