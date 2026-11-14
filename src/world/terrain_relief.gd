class_name TerrainRelief
extends RefCounted
## The height of the terrain's surface (towards the camera, +z) at a point on
## the play plane, worked out on the CPU exactly as terrain.gdshader's
## relief() does on the GPU, so things set into the rock (crystals, the
## flowstone over Vasquez's drone) can sit in it, not float over it or cut
## through it.

## The terrain's detail noise as an image.
static var _noise_img: Image


## The surface height at [param p] in [param field]; [param glass] is the
## singing glass's share there (0..1), which smooths the rock into a swell.
static func height(field: TerrainField, p: Vector2, glass := 0.0) -> float:
	var s := field.sample(p)
	var n := noise(p * 0.021) - 0.5
	var n2 := noise(p * 0.083 + Vector2(0.37, 0.71)) - 0.5
	if s < 0.0:
		var t := tanh(-s / 2.0)
		var lumps := (n * 4.0 + n2 * 0.8) * (1.0 - glass * 0.85)
		return t * (TerrainRenderer.ROCK_HEIGHT + lumps * t * t + glass * 0.6)
	var tw := tanh(s / 2.4)
	var deep := TerrainRenderer.BACK_DEPTH + clampf(s - 4.0, 0.0, 12.0) * 0.35
	return -tw * (deep + (n * 4.0 + n2 * 0.8) * tw * tw)


## The surface's normal at [param p] (pointing out of the rock).
static func normal(field: TerrainField, p: Vector2) -> Vector3:
	var e := 0.08
	var hx := height(field, p + Vector2(e, 0.0)) - height(field, p - Vector2(e, 0.0))
	var hy := height(field, p + Vector2(0.0, e)) - height(field, p - Vector2(0.0, e))
	return Vector3(-hx / (2.0 * e), -hy / (2.0 * e), 1.0).normalized()


## The terrain's detail noise at [param uv], filtered as the GPU does
## (bilinear, repeating).
static func noise(uv: Vector2) -> float:
	if _noise_img == null:
		var tex := TerrainRenderer.detail_noise()
		_noise_img = (tex.noise as FastNoiseLite).get_seamless_image(tex.width, tex.height)
	var w := _noise_img.get_width()
	var h := _noise_img.get_height()
	var x := uv.x * w - 0.5
	var y := uv.y * h - 0.5
	var x0 := floori(x)
	var y0 := floori(y)
	var fx := x - x0
	var fy := y - y0
	var a := _noise_img.get_pixel(posmod(x0, w), posmod(y0, h)).r
	var b := _noise_img.get_pixel(posmod(x0 + 1, w), posmod(y0, h)).r
	var c := _noise_img.get_pixel(posmod(x0, w), posmod(y0 + 1, h)).r
	var d := _noise_img.get_pixel(posmod(x0 + 1, w), posmod(y0 + 1, h)).r
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)
