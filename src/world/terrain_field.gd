class_name TerrainField
extends RefCounted
## Signed distance field of the cave on the XY gameplay plane.
##
## Values are distances in meters to the nearest rock surface: positive in open
## water, negative inside rock. Samples sit on a regular grid with [member cell]
## meters between them. World position (x, y) maps to grid coordinates
## (x / cell, -y / cell), so the zone extends from y = 0 downwards.
##
## The same field drives collision, creature steering, projectiles and rendering
## (it is uploaded to the GPU by [TerrainRenderer]).

## Value returned for any point outside the grid: solid rock.
const OUTSIDE := -6.0

var width: int
var height: int
var cell: float
var data: PackedFloat32Array


func _init(w: int, h: int, cell_size: float) -> void:
	width = w
	height = h
	cell = cell_size
	data = PackedFloat32Array()
	data.resize(w * h)


## Size of the field in world meters.
func world_size() -> Vector2:
	return Vector2((width - 1) * cell, (height - 1) * cell)


func contains(p: Vector2) -> bool:
	var s := world_size()
	return p.x >= 0.0 and p.x <= s.x and p.y <= 0.0 and p.y >= -s.y


## Raw grid value; out-of-range indices are clamped to the border.
func at(ix: int, iy: int) -> float:
	ix = clampi(ix, 0, width - 1)
	iy = clampi(iy, 0, height - 1)
	return data[iy * width + ix]


## Bilinearly interpolated signed distance at world position [param p].
func sample(p: Vector2) -> float:
	var gx := p.x / cell
	var gy := -p.y / cell
	if gx < 0.0 or gy < 0.0 or gx > width - 1 or gy > height - 1:
		return OUTSIDE
	var ix := int(gx)
	var iy := int(gy)
	var fx := gx - ix
	var fy := gy - iy
	var i := iy * width + ix
	var ix1 := 1 if ix < width - 1 else 0
	var iy1 := width if iy < height - 1 else 0
	var a := data[i]
	var b := data[i + ix1]
	var c := data[i + iy1]
	var d := data[i + iy1 + ix1]
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)


## Gradient of the field (points away from rock, towards open water).
func gradient(p: Vector2) -> Vector2:
	var h := cell * 0.75
	var dx := sample(p + Vector2(h, 0.0)) - sample(p - Vector2(h, 0.0))
	var dy := sample(p + Vector2(0.0, h)) - sample(p - Vector2(0.0, h))
	return Vector2(dx, dy) / (2.0 * h)


## Unit surface normal pointing into open water. Falls back to up if flat.
func normal(p: Vector2) -> Vector2:
	var g := gradient(p)
	var l := g.length()
	return g / l if l > 0.0001 else Vector2.UP


func is_free(p: Vector2, radius: float) -> bool:
	return sample(p) > radius


## Pushes a circle out of the rock. Returns the corrected position.
func resolve_circle(p: Vector2, radius: float) -> Vector2:
	for _i in 4:
		var d := sample(p)
		if d >= radius:
			break
		p += normal(p) * (radius - d + 0.001)
	return p


## Sphere-traces a moving circle from [param from] to [param to].
## Returns the travelled fraction in [0, 1]; 1.0 means no hit.
func cast(from: Vector2, to: Vector2, radius := 0.0) -> float:
	var delta := to - from
	var total := delta.length()
	if total < 0.00001:
		return 1.0 if sample(from) > radius else 0.0
	var dir := delta / total
	var t := 0.0
	for _i in 48:
		var d := sample(from + dir * t) - radius
		if d < 0.02:
			return t / total
		t += maxf(d, 0.05)
		if t >= total:
			return 1.0
	return 1.0


## True if a straight line between two points stays in open water.
func line_of_sight(a: Vector2, b: Vector2, radius := 0.0) -> bool:
	return cast(a, b, radius) >= 1.0


## Converts the field into a half-float image for the GPU. Half floats are
## used because linear filtering of 32-bit float textures is optional on
## some hardware, and the relief depends on smooth interpolation.
## The grid cells covering the world rectangle [param r], clamped to the grid.
func cells_in(r: Rect2) -> Rect2i:
	var x0 := clampi(floori(r.position.x / cell), 0, width)
	var x1 := clampi(ceili(r.end.x / cell) + 1, 0, width)
	var y0 := clampi(floori(-r.end.y / cell), 0, height)
	var y1 := clampi(ceili(-r.position.y / cell) + 1, 0, height)
	return Rect2i(x0, y0, x1 - x0, y1 - y0)


## World position of grid cell ([param ix], [param iy]).
func cell_pos(ix: int, iy: int) -> Vector2:
	return Vector2(ix * cell, -iy * cell)


## Values of the cells in [param cells], row by row.
func read_cells(cells: Rect2i) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(cells.size.x * cells.size.y)
	var i := 0
	for iy in range(cells.position.y, cells.end.y):
		for ix in range(cells.position.x, cells.end.x):
			out[i] = data[iy * width + ix]
			i += 1
	return out


## Overwrites the cells in [param cells] with [param values] (as read_cells
## returns them). Edits the grid in place, so callers never copy it.
func write_cells(cells: Rect2i, values: PackedFloat32Array) -> void:
	var i := 0
	for iy in range(cells.position.y, cells.end.y):
		for ix in range(cells.position.x, cells.end.x):
			data[iy * width + ix] = values[i]
			i += 1


## Overwrites the cells at grid indices [param indices] with [param values].
func write_indices(indices: PackedInt32Array, values: PackedFloat32Array) -> void:
	for j in indices.size():
		data[indices[j]] = values[j]


func to_image() -> Image:
	var img := Image.create_from_data(width, height, false, Image.FORMAT_RF, data.to_byte_array())
	img.convert(Image.FORMAT_RH)
	return img
