class_name Flowstone
extends RefCounted
## Helpers for rock that has flowed over something like wax (the cave wall
## over Vasquez's drone): what it covers rasterised into a height grid,
## widened and blurred into the rounded mound the rock sets in.


## The highest of the triangles [param idx] of [param pts] (in grid space:
## x and y across the grid, z the height) over each cell of an [param nx] by
## [param ny] grid of [param cell] metres from [param lo]; -INF where none.
static func raster(pts: PackedVector3Array, idx: PackedInt32Array, lo: Vector2, cell: float, nx: int,
		ny: int) -> PackedFloat32Array:
	var top := PackedFloat32Array()
	top.resize(nx * ny)
	top.fill(-INF)
	for t in range(0, idx.size(), 3):
		var a := pts[idx[t]]
		var b := pts[idx[t + 1]]
		var c := pts[idx[t + 2]]
		# Each corner marks its own cell (for triangles smaller than a cell)...
		for v: Vector3 in [a, b, c]:
			var kx := roundi((v.x - lo.x) / cell)
			var ky := roundi((v.y - lo.y) / cell)
			if kx >= 0 and kx < nx and ky >= 0 and ky < ny:
				top[ky * nx + kx] = maxf(top[ky * nx + kx], v.z)
		# ...and every cell centre the triangle covers takes its height there.
		var x0 := maxi(ceili((minf(a.x, minf(b.x, c.x)) - lo.x) / cell), 0)
		var x1 := mini(floori((maxf(a.x, maxf(b.x, c.x)) - lo.x) / cell), nx - 1)
		var y0 := maxi(ceili((minf(a.y, minf(b.y, c.y)) - lo.y) / cell), 0)
		var y1 := mini(floori((maxf(a.y, maxf(b.y, c.y)) - lo.y) / cell), ny - 1)
		var den := (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
		if absf(den) < 1e-9:
			continue
		for iy in range(y0, y1 + 1):
			for ix in range(x0, x1 + 1):
				var px := lo.x + ix * cell
				var py := lo.y + iy * cell
				var wa := ((b.y - c.y) * (px - c.x) + (c.x - b.x) * (py - c.y)) / den
				var wb := ((c.y - a.y) * (px - c.x) + (a.x - c.x) * (py - c.y)) / den
				var wc := 1.0 - wa - wb
				if wa < -0.001 or wb < -0.001 or wc < -0.001:
					continue
				var k := iy * nx + ix
				top[k] = maxf(top[k], a.z * wa + b.z * wb + c.z * wc)
	return top


## [param values] (an [param nx] by [param ny] grid) with each cell raised
## to the highest within [param r] cells.
static func widen(values: PackedFloat32Array, nx: int, ny: int, r: int) -> PackedFloat32Array:
	var out := values.duplicate()
	for iy in ny:
		for ix in nx:
			var m := values[iy * nx + ix]
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					var x := clampi(ix + dx, 0, nx - 1)
					var y := clampi(iy + dy, 0, ny - 1)
					m = maxf(m, values[y * nx + x])
			out[iy * nx + ix] = m
	return out


## [param values] blurred, [param sigma] cells across.
static func blur(values: PackedFloat32Array, nx: int, ny: int, sigma: float) -> PackedFloat32Array:
	var r := int(ceil(sigma * 2.0))
	var weights := PackedFloat32Array()
	var total := 0.0
	for d in range(-r, r + 1):
		var w := exp(-float(d * d) / (2.0 * sigma * sigma))
		weights.append(w)
		total += w
	var pass1 := PackedFloat32Array()
	pass1.resize(nx * ny)
	for iy in ny:
		for ix in nx:
			var sum := 0.0
			for d in range(-r, r + 1):
				sum += values[iy * nx + clampi(ix + d, 0, nx - 1)] * weights[d + r]
			pass1[iy * nx + ix] = sum / total
	var out := PackedFloat32Array()
	out.resize(nx * ny)
	for iy in ny:
		for ix in nx:
			var sum := 0.0
			for d in range(-r, r + 1):
				sum += pass1[clampi(iy + d, 0, ny - 1) * nx + ix] * weights[d + r]
			out[iy * nx + ix] = sum / total
	return out
