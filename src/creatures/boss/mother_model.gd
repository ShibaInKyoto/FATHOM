class_name MotherModel
extends RefCounted
## The Blind Mother's rigid parts and the pieces of her model built once:
## her skin's pattern, the shape of her head (the body is lofted on into it
## every frame: see [BlindMother]), the fangs, feelers and pores on it, her
## lower jaw, the glowing gills under her gill flaps, and the triangles of
## her body's skin.

static var _skin_tex: ImageTexture
static var head_mesh: ArrayMesh
static var jaw_mesh: ArrayMesh


## Her skin's pattern: deep wrinkles running round her, and soft darker
## blotches; seamless, built once.
static func skin() -> ImageTexture:
	if _skin_tex:
		return _skin_tex
	var wrinkles := FastNoiseLite.new()
	wrinkles.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	wrinkles.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	wrinkles.fractal_octaves = 3
	wrinkles.frequency = 0.025
	wrinkles.seed = 31
	var blotches := FastNoiseLite.new()
	blotches.frequency = 0.012
	blotches.fractal_octaves = 3
	blotches.seed = 77
	var size := 256
	var img := Image.create(size, size, true, Image.FORMAT_L8)
	for y in size:
		for x in size:
			# Sampled on a torus, so the pattern repeats without a seam.
			var u := TAU * x / size
			var v := TAU * y / size
			var r := size / TAU
			var w := wrinkles.get_noise_3d(cos(u) * r, sin(u) * r, v * r * 0.35)
			var b := blotches.get_noise_3d(cos(u) * r, sin(u) * r + 40.0, cos(v) * r + sin(v) * r)
			var h := 0.55 + 0.32 * w - 0.35 * smoothstep(0.05, 0.4, b)
			img.set_pixel(x, y, Color(clampf(h, 0.0, 1.0), 0.0, 0.0))
	img.generate_mipmaps()
	_skin_tex = ImageTexture.create_from_image(img)
	return _skin_tex


## The point on her head's skin at [param x], [param a] radians round from
## the back's midline (towards +Z first), as the head is lofted.
static func head_point(x: float, a: float) -> Vector3:
	var hw := BodyKit.at(BlindMother.HEAD, x, 1)
	var top := BodyKit.at(BlindMother.HEAD, x, 2)
	var low := BodyKit.at(BlindMother.HEAD, x, 3)
	var spine := BodyKit.at(BlindMother.HEAD, x, 4)
	var sc := signf(cos(a)) * pow(absf(cos(a)), 0.85)
	var ss := signf(sin(a)) * pow(absf(sin(a)), 0.85)
	return Vector3(x, spine + sc * (top if cos(a) >= 0.0 else low), ss * hw)


## Which way the skin faces there.
static func head_normal(x: float, a: float) -> Vector3:
	var e := 0.01
	var along := head_point(x + e, a) - head_point(x - e, a)
	var round := head_point(x, a + e) - head_point(x, a - e)
	return round.cross(along).normalized()


## The rigid parts of the head: the tube nostrils on the snout, long
## sensory feelers trailing from beside them (swaying more towards their
## tips), and the fangs down the upper jaw.
static func head_parts() -> ArrayMesh:
	var parts := []
	for sgn: float in [1.0, -1.0]:
		var base := head_point(2.55, PI * 0.3) * Vector3(1.0, 1.0, sgn)
		var tube := ArrayMesh.new()
		MeshKit.tube(tube, PackedVector3Array([base, base + Vector3(0.12, 0.1, 0.03 * sgn),
			base + Vector3(0.22, 0.16, 0.05 * sgn)]), PackedFloat32Array([0.07, 0.06, 0.05]), 8)
		parts.append([MeshKit.painted(tube, func(_v: Vector3) -> Color: return Color(0.0, 0.3, 0.0))])
		for k in 2:
			var root := head_point(2.4 - k * 0.32, PI * (0.56 + k * 0.06)) * Vector3(1.0, 1.0, sgn)
			var length := 2.6 - k * 0.7
			var pts := PackedVector3Array()
			var radii := PackedFloat32Array()
			for i in 15:
				var f := i / 14.0
				# Forward and out from the snout, then drooping and trailing
				# back beneath her chin.
				pts.append(root + Vector3(0.45 * f - length * 0.75 * f * f, -0.9 * f * f + 0.15 * f,
					(0.3 + 0.2 * f) * f * sgn))
				radii.append(lerpf(0.04, 0.006, pow(f, 0.8)))
			var feeler := ArrayMesh.new()
			MeshKit.tube(feeler, pts, radii, 6)
			parts.append([MeshKit.painted(feeler, func(v: Vector3) -> Color:
				return Color(0.0, 0.4, clampf(root.distance_to(v) / length * 1.4, 0.0, 1.0)))])
		# Sensory pores in rows over the snout and along the lips, glowing
		# when she listens.
		var pore := MeshKit.ball(0.035, 1.0, 6, 4)
		for row: Vector2 in [Vector2(0.62, 0.0), Vector2(0.78, 0.04), Vector2(0.3, 0.02)]:
			for i in 7:
				var x := lerpf(0.9, 2.6, i / 6.0) + row.y * i
				var a := PI * row.x if sgn > 0.0 else TAU - PI * row.x
				parts.append([pore, Transform3D(Basis(), head_point(x, a) - head_normal(x, a) * 0.012)])
		for t: Array in BodyKit.teeth_row(upper_lip(0.5, sgn), upper_lip(2.72, sgn), 15, 0.42,
				Vector3(0.1, -1.0, -0.3 * sgn), 51 if sgn > 0.0 else 52):
			parts.append([BodyKit.enamel(t[0]), t[1]])
	return MeshKit.merge(parts)


## The lower jaw (jaw space): long, deep at the hinge, fangs along its rim
## leaning in, a chin jutting a little past the snout.
static func jaw_parts() -> ArrayMesh:
	var parts := [[BodyKit.body(BlindMother.JAW, 40, 24)]]
	for sgn: float in [1.0, -1.0]:
		for t: Array in BodyKit.teeth_row(jaw_rim(0.45, sgn), jaw_rim(2.7, sgn), 13, 0.4,
				Vector3(-0.2, 1.0, -0.35 * sgn), 53 if sgn > 0.0 else 54):
			parts.append([BodyKit.enamel(t[0]), t[1], (t[1] as Transform3D).origin.x])
	return BodyKit.merged(parts)


## The upper jaw's edge on side [param sgn] at [param x].
static func upper_lip(x: float, sgn: float) -> Vector3:
	var head := BlindMother.HEAD
	return Vector3(x, BodyKit.at(head, x, 4) - BodyKit.at(head, x, 3) * 0.8, BodyKit.at(head, x, 1) * 0.74 * sgn)


## The lower jaw's rim on side [param sgn], [param u] along it (jaw space).
static func jaw_rim(u: float, sgn: float) -> Vector3:
	var jaw := BlindMother.JAW
	return Vector3(u, BodyKit.at(jaw, u, 4) + BodyKit.at(jaw, u, 2) * 0.8, BodyKit.at(jaw, u, 1) * 0.86 * sgn)


## The gills, glowing: behind each slit a ruffled frill lying just under
## the skin, hidden while the flap over it is shut.
static func gill_frills() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols := 10
	var rows := 4
	var at := 0
	for sgn: float in [1.0, -1.0]:
		for k in BlindMother.GILLS:
			var x0 := BlindMother.GILL_X + k * BlindMother.GILL_STEP
			for r in rows + 1:
				for c in cols + 1:
					var u := float(r) / rows
					var w := float(c) / cols
					var a := lerpf(BlindMother.GILL_A.x, BlindMother.GILL_A.y, w)
					var x := x0 + 0.15 * u
					var n := head_normal(x, a) * Vector3(1.0, 1.0, sgn)
					var ruffle := 0.05 * (0.5 + 0.5 * sin(w * 38.0 + k)) * sin(PI * u)
					var p := head_point(x, a) * Vector3(1.0, 1.0, sgn) + n * (0.004 + ruffle * (0.3 + 0.7 * u))
					st.set_normal(n)
					st.set_color(Color(0.4 + 0.6 * sin(PI * u), 0.5, 0.4 * u))
					st.add_vertex(p)
			for r in rows:
				for c in cols:
					var a := at + r * (cols + 1) + c
					var quad := [a, a + cols + 1, a + 1, a + 1, a + cols + 1, a + cols + 2]
					if sgn < 0.0:
						quad = [a, a + 1, a + cols + 1, a + 1, a + cols + 2, a + cols + 1]
					for q: int in quad:
						st.add_index(q)
			at += (rows + 1) * (cols + 1)
	return st.commit()


## The triangles: the same every frame.
static func indices(rings: int, body_rings: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var row := BlindMother.SIDES + 1
	for i in rings - 1:
		for j in BlindMother.SIDES:
			var a := i * row + j
			out.append_array([a, a + row, a + 1, a + 1, a + row, a + row + 1])
	var base := rings * row
	for f in 2:
		for face in 2:
			var b := base + (f * 2 + face) * body_rings * 2
			for i in body_rings - 1:
				var a := b + i * 2
				var flip := (face == 1) != (f == 1)
				out.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2] if not flip
					else [a, a + 2, a + 1, a + 1, a + 2, a + 3])
	return out
