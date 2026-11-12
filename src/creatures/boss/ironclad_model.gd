class_name IroncladModel
extends RefCounted
## The Ironclad's model, built once, in the creature shader's conventions
## (see [BodyKit]): a colossal isopod armoured in riveted iron. Thirteen
## plates and a tail shield over a body of molten flesh, each plate studded
## with knobs, a row of rivets along its trailing edge, the body plates'
## flanks drawn back into spikes; its skin painted (heat tints along every
## plate's trailing edge, rust, scrapes, sulphur crust: see
## tools/art/ironclad_skin.py). On its back stand the vent chimneys it has
## grown, which it spits scalding water from. Big ember-dark eyes, long
## feelers and heavy mandibles (separate meshes, so they move), and seven
## pairs of jointed, spined legs that walk in a ripple down each side (the
## shader's gait). It carries a second shape, the shell split open by heat,
## every plate lifted on its front edge over the glowing flesh beneath
## ([method BodyKit.morph]: the shader's puff).

## UV2.y of the parts the painted skin leaves alone (legs carry their own
## marks).
const UNPAINTED := 999.0
## The body (x from the tail to the nose; stations as in [method BodyKit.body]):
## a high dome over a flat belly, broadest mid-back, the head narrower.
const BODY := [[-2.3, 0.3, 0.04, 0.03, -0.06], [-2.12, 0.92, 0.2, 0.1, -0.04], [-1.8, 1.12, 0.4, 0.18, -0.02],
	[-1.2, 1.27, 0.64, 0.27, 0.0], [-0.4, 1.36, 0.84, 0.33, 0.0], [0.4, 1.38, 0.88, 0.35, 0.0],
	[1.05, 1.3, 0.8, 0.34, 0.0], [1.45, 1.12, 0.64, 0.3, 0.0], [1.7, 0.84, 0.5, 0.27, -0.01],
	[2.0, 0.76, 0.42, 0.25, -0.03], [2.22, 0.56, 0.26, 0.19, -0.05], [2.32, 0.12, 0.05, 0.05, -0.07]]
## Where each plate's trailing edge lies, head first: the head shield, seven
## body plates, five narrow tail rings, then the tail shield.
const PLATES := [1.58, 1.2, 0.84, 0.48, 0.12, -0.24, -0.6, -0.96, -1.1, -1.24, -1.38, -1.52, -1.66, -2.34]
## The head shield's front.
const NOSE := 2.36
## How far each plate's front lies tucked under the plate ahead of it.
const TUCK := 0.1
## The body plates' flanks: round from the back's midline (radians), where
## each flank's flange rises out of the plate and where it dies away again
## (x, y; z, w); how far its trailing corner is drawn back, and how far the
## flange stands out from the body.
const EPIMERA := Vector4(1.3, 1.7, 2.0, 2.35)
const FLANK_BACK := 0.12
const FLARE := 0.09
## How far below its spine its feet stand.
const FLOOR := -0.75
## The chimneys on its back: [x, z, height above the shell], the first the
## one it spits from.
const CHIMNEYS := [[-0.08, 0.3, 0.6], [-0.78, -0.3, 0.38], [0.42, -0.26, 0.22]]
## Where the left feeler and mandible are rooted (mirrored on the right).
const FEELER_ROOT := Vector3(2.18, -0.04, 0.3)
const JAW_ROOT := Vector3(2.1, -0.24, 0.17)
## The shell split open by heat: how far each plate's trailing edge tips up
## about its front (radians) and how far the whole plate rises.
const OPEN_TILT := 0.3
const OPEN_RISE := 0.07
## Its painted skin and where it lies (see creature.gdshader: paint_wrap),
## x along it and from the back's midline (0) round to the belly's (1).
const SKIN := preload("res://assets/creatures/ironclad_skin.png")
const PAINT_BOX := Vector4(-2.4, 0.0, 4.8, 1.0)

static var _mesh: ArrayMesh


## The whole animal but its feelers and mandibles, its shell split open as
## its second shape.
static func mesh() -> ArrayMesh:
	if _mesh == null:
		_mesh = BodyKit.morph(_build(false), _build(true))
	return _mesh


## Where chimney [param i]'s mouth is (model space).
static func chimney_mouth(i: int) -> Vector3:
	var c: Array = CHIMNEYS[i]
	return _chimney_base(i) + Vector3(0.0, float(c[2]), 0.0)


static func _build(open: bool) -> ArrayMesh:
	var parts := [[_body()]]
	for k in PLATES.size():
		var lift := _lift(k) if open else Transform3D.IDENTITY
		parts.append([_plate(k), lift])
		for stud: Array in _studs(k):
			parts.append([stud[0], lift * (stud[1] as Transform3D)])
		for i in CHIMNEYS.size():
			if _plate_at(float(CHIMNEYS[i][0])) == k:
				parts.append([_chimney(i), lift * Transform3D(Basis(), _chimney_base(i))])
	for sgn: float in [1.0, -1.0]:
		for i in 7:
			parts.append([_leg(i, sgn)])
		parts.append_array(_face(sgn))
	return BodyKit.merged(parts)


## How plate [param k] moves as the shell splits open: tipped up about its
## front edge and lifted (the head shield stays put).
static func _lift(k: int) -> Transform3D:
	if k == 0:
		return Transform3D.IDENTITY
	var front := float(PLATES[k - 1]) + TUCK
	var hinge := Vector3(front, 0.0, 0.0)
	var tilt := OPEN_TILT * (0.6 if k > 7 else 1.0)
	var xf := Transform3D(Basis(Vector3.BACK, -tilt), Vector3.ZERO)
	return Transform3D(Basis(), hinge + Vector3(0.0, OPEN_RISE, 0.0)) * xf * Transform3D(Basis(), -hinge)


## Which plate covers the back at [param x].
static func _plate_at(x: float) -> int:
	for k in PLATES.size():
		if x >= float(PLATES[k]):
			return k
	return PLATES.size() - 1


## A loft, ring by ring: [param point] gives ring i's point [param a]
## radians round from the back's midline (towards +Z first), [param color]
## its colour. UV.x is where each point hangs along the body, UV2 where the
## painted skin lies there.
static func _loft(rings: int, sides: int, point: Callable, color: Callable) -> ArrayMesh:
	var grid: Array[PackedVector3Array] = []
	for i in rings:
		var ring := PackedVector3Array()
		for j in sides + 1:
			ring.append(point.call(i, TAU * j / sides))
		grid.append(ring)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in rings:
		for j in sides + 1:
			var a := TAU * j / sides
			var p := grid[i][j]
			var along := grid[mini(i + 1, rings - 1)][j] - grid[maxi(i - 1, 0)][j]
			var around := grid[i][(j + 1) % sides] - grid[i][(j - 1 + sides) % sides]
			var n := around.cross(along)
			# A ring drawn to a point (a closed end) faces straight out along.
			st.set_normal(n.normalized() if n.length_squared() > 1e-10 else
				(Vector3.LEFT if i == 0 else Vector3.RIGHT))
			st.set_color(color.call(i, a))
			st.set_uv(Vector2(p.x, 0.0))
			st.set_uv2(Vector2(p.x, absf(wrapf(a, -PI, PI)) / PI))
			st.add_vertex(p)
	var row := sides + 1
	for i in rings - 1:
		for j in sides:
			var a := i * row + j
			for q: int in [a, a + row, a + 1, a + 1, a + row, a + row + 1]:
				st.add_index(q)
	return st.commit()


## The body under the plates: molten along its back (seen only where the
## plates part).
static func _body() -> ArrayMesh:
	var x0: float = BODY[0][0]
	var x1: float = BODY[BODY.size() - 1][0]
	var rings := 80
	return _loft(rings + 1, 32, func(i: int, a: float) -> Vector3:
		return BodyKit.surface(BODY, lerpf(x0, x1, float(i) / rings), a),
		func(i: int, a: float) -> Color:
			var x := lerpf(x0, x1, float(i) / rings)
			var molten := smoothstep(-0.15, 0.3, cos(a)) * (1.0 - smoothstep(1.45, 1.6, x))
			return Color(molten, smoothstep(0.1, -0.7, cos(a)), 0.0))


## How far round towards each flank's flange a point [param w] radians
## from the back's midline is (0 to 1 and back to 0).
static func _flank(w: float) -> float:
	return smoothstep(EPIMERA.x, EPIMERA.y, w) * (1.0 - smoothstep(EPIMERA.z, EPIMERA.w, w))


## A point on plate [param k]'s outer face, [param f] along it from its
## trailing edge (0) to its front (1; below 0, the lip dropping from the
## edge under the skin; above 1, the head shield closing over the nose),
## [param a] radians round from the back's midline.
static func _plate_point(k: int, f: float, a: float) -> Vector3:
	var rear: float = PLATES[k]
	var front: float = NOSE if k == 0 else float(PLATES[k - 1]) + TUCK
	var w := absf(wrapf(a, -PI, PI))
	if f > 1.5:
		return Vector3(NOSE + 0.03, BodyKit.at(BODY, NOSE, 4), 0.0)
	if f < -0.5 and k == PLATES.size() - 1:
		return Vector3(rear - 0.03, BodyKit.at(BODY, rear, 4), 0.0)
	var flank := _flank(w) if k >= 1 and k <= 7 else 0.0
	var x := lerpf(rear - FLANK_BACK * flank, front, maxf(f, 0.0))
	var skin := BodyKit.surface(BODY, x, a)
	var out := skin - Vector3(x, BodyKit.at(BODY, x, 4), 0.0)
	out.x = 0.0
	return skin + out.normalized() * _proud(k, f, w, flank)


## How far plate [param k] stands proud of the skin there (below it, under
## the skin): thick along its trailing edge, a keel down the back, the
## flanks' flanges standing out; its front dives under the plate ahead,
## and round under the belly it sinks into the body.
static func _proud(k: int, f: float, w: float, flank: float) -> float:
	if f < 0.0:
		return -0.03
	var p := 0.035 + 0.045 * (1.0 - smoothstep(0.0, 0.3, f))
	if k > 0:
		p += 0.025 * exp(-pow(w / 0.16, 2.0))
		p += FLARE * flank
		p *= 1.0 - 0.85 * smoothstep(0.6, 1.0, f)
	else:
		# The head shield's front a heavy brow over the face.
		p += 0.05 * smoothstep(0.6, 0.92, f) * (1.0 - smoothstep(1.2, 1.7, w))
	return p - 0.16 * smoothstep(2.05, 2.5, w)


## Which way plate [param k]'s face looks there.
static func _plate_normal(k: int, f: float, a: float) -> Vector3:
	var along := _plate_point(k, f + 0.01, a) - _plate_point(k, f - 0.01, a)
	var around := _plate_point(k, f, a + 0.01) - _plate_point(k, f, a - 0.01)
	return around.cross(along).normalized()


## Plate [param k]: its front (hidden under the plate ahead, but for the
## head shield) glows, as the flesh does, wherever the plates part.
static func _plate(k: int) -> ArrayMesh:
	var steps := PackedFloat32Array([-1.0, 0.0, 0.03, 0.08, 0.16, 0.26, 0.38, 0.5, 0.62, 0.74, 0.84, 0.92, 1.0])
	if k == 0:
		steps.append(2.0)
	# Where it slides under the plate ahead: a sliver of glow shows there.
	var hidden := 1.0 - TUCK / (float(PLATES[maxi(k - 1, 0)]) + TUCK - float(PLATES[k]))
	return _loft(steps.size(), 40, func(i: int, a: float) -> Vector3:
		return _plate_point(k, steps[i], a),
		func(i: int, a: float) -> Color:
			var seam := smoothstep(hidden - 0.05, hidden + 0.06, steps[i]) if k > 0 and steps[i] <= 1.0 else 0.0
			return Color(seam, smoothstep(0.1, -0.7, cos(a)), 0.0))


## A blunt knob [param r] across and [param h] tall, standing up along +Y.
static func _knob(r: float, h: float) -> ArrayMesh:
	var profile := [Vector2(-0.03, r), Vector2(h * 0.35, r * 0.9), Vector2(h * 0.7, r * 0.62),
		Vector2(h * 0.9, r * 0.32), Vector2(h, 0.004)]
	return _loft(profile.size(), 8, func(i: int, a: float) -> Vector3:
		var ring: Vector2 = profile[i]
		return Vector3(sin(a) * ring.y, ring.x, cos(a) * ring.y),
		func(_i: int, _a: float) -> Color: return Color())


## A horn [param r] across at its foot and [param h] tall, standing up along
## +Y and sweeping [param sweep] back (-X) towards its tip.
static func _horn(r: float, h: float, sweep: float) -> ArrayMesh:
	var rings := 7
	return _loft(rings, 8, func(i: int, a: float) -> Vector3:
		var u := float(i) / (rings - 1)
		var rr := lerpf(r, 0.004, pow(u, 0.8))
		return Vector3(sin(a) * rr - sweep * u * u, lerpf(-0.03, h, u), cos(a) * rr),
		func(_i: int, _a: float) -> Color: return Color())


## [param mesh] coloured [param color] all over and painted (UV2) as the
## skin at [param uv2].
static func _skinned(mesh: ArrayMesh, color: Color, uv2: Vector2) -> ArrayMesh:
	var arrays := mesh.surface_get_arrays(0)
	var n := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var colors := PackedColorArray()
	colors.resize(n)
	colors.fill(color)
	var uv2s := PackedVector2Array()
	uv2s.resize(n)
	uv2s.fill(uv2)
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


## A transform standing a part up along [param n] at [param at].
static func _on(at: Vector3, n: Vector3) -> Transform3D:
	return Transform3D(Basis(Quaternion(Vector3.UP, n.normalized())), at)


## Plate [param k]'s knobs, rivets and flank spikes: [mesh, transform].
static func _studs(k: int) -> Array:
	var out := []
	var body_plate := k >= 1 and k <= 7
	var knobs: Array[Vector3] = []
	if body_plate:
		# Five across, the middle one biggest: [round from the midline, size, f along].
		knobs = [Vector3(0.0, 1.0, 0.42), Vector3(0.6, 0.82, 0.42), Vector3(-0.6, 0.82, 0.42),
			Vector3(1.1, 0.7, 0.42), Vector3(-1.1, 0.7, 0.42)]
	elif k == 0:
		knobs = [Vector3(0.45, 0.7, 0.35), Vector3(-0.45, 0.7, 0.35)]
	elif k == PLATES.size() - 1:
		knobs = [Vector3(0.0, 0.8, 0.55), Vector3(0.5, 0.6, 0.35), Vector3(-0.5, 0.6, 0.35),
			Vector3(0.25, 0.55, 0.15), Vector3(-0.25, 0.55, 0.15)]
	else:
		knobs = [Vector3(0.0, 0.6, 0.4)]
	for kb: Vector3 in knobs:
		var at := _plate_point(k, kb.z, kb.x)
		var knob := _knob(0.085 * kb.y, 0.11 * kb.y)
		# Down the middle of the body plates, a crest of horns swept back.
		if body_plate and kb.x == 0.0:
			knob = _horn(0.085, 0.2 - 0.015 * absf(k - 4.0), 0.1)
		out.append([_skinned(knob, Color(0.0, 0.0, 0.0), Vector2(at.x, absf(kb.x) / PI)),
			_on(at, _plate_normal(k, kb.z, kb.x))])
	# Over the eyes, a pair of brow horns jutting forward.
	if k == 0:
		for sgn: float in [1.0, -1.0]:
			var at := _plate_point(k, 0.7, 0.8 * sgn)
			var dir := Vector3(0.75, 0.55, 0.3 * sgn).normalized()
			out.append([_skinned(_horn(0.055, 0.17, -0.05), Color(0.0, 0.0, 0.0), Vector2(at.x, 0.8 / PI)),
				_on(at, dir)])
	# Rivets along the trailing edge.
	if k >= 1 and k < PLATES.size() - 1:
		var count := 11 if body_plate else 7
		var spread := 1.45 if body_plate else 1.2
		var rivet := MeshKit.ball(0.022, 0.0, 6, 4)
		for i in count:
			var a := lerpf(-spread, spread, i / (count - 1.0))
			var n := _plate_normal(k, 0.07, a)
			var at := _plate_point(k, 0.07, a) - n * 0.006
			out.append([_skinned(rivet, Color(0.0, 0.0, 0.0), Vector2(at.x, absf(a) / PI)), _on(at, n)])
	# Each body plate's flank drawn back into a spike, longer towards the tail.
	if body_plate:
		var a_corner := (EPIMERA.y + EPIMERA.z) * 0.5
		for sgn: float in [1.0, -1.0]:
			var at := _plate_point(k, 0.02, a_corner * sgn)
			var dir := Vector3(-1.0, -0.2, 0.42 * sgn).normalized()
			var spike := MeshKit.spike(0.045, 0.2 + 0.02 * k, 0.0, 6)
			out.append([_skinned(spike, Color(0.0, 0.3, 0.0), Vector2(at.x, a_corner / PI)),
				Transform3D(Basis(Quaternion(Vector3.RIGHT, dir)), at - dir * 0.04)])
	# The tail shield's rim of spines.
	if k == PLATES.size() - 1:
		var spine := MeshKit.spike(0.034, 0.17, 0.0, 6)
		for x: float in [-1.86, -1.98, -2.1, -2.2, -2.28]:
			for sgn: float in [1.0, -1.0]:
				var z := BodyKit.at(BODY, x, 1) + 0.04
				var slope := (BodyKit.at(BODY, x + 0.02, 1) - BodyKit.at(BODY, x - 0.02, 1)) / 0.04
				var dir := (Vector3(-slope, 0.0, 1.0).normalized() + Vector3(-0.5, 0.0, 0.0)).normalized()
				dir.z *= sgn
				var at := Vector3(x, BodyKit.at(BODY, x, 4), z * sgn)
				out.append([_skinned(spine, Color(0.0, 0.3, 0.0), Vector2(x, 0.5)),
					Transform3D(Basis(Quaternion(Vector3.RIGHT, dir)), at - dir * 0.05)])
		var tip := Vector3(float(PLATES[k]) - 0.02, BodyKit.at(BODY, -2.3, 4), 0.0)
		out.append([_skinned(MeshKit.spike(0.04, 0.2, 0.0, 6), Color(0.0, 0.3, 0.0), Vector2(tip.x, 0.0)),
			Transform3D(Basis(Quaternion(Vector3.RIGHT, Vector3.LEFT)), tip + Vector3(0.04, 0.0, 0.0))])
	return out


## Where chimney [param i] stands on the shell (model space, the shell at
## rest).
static func _chimney_base(i: int) -> Vector3:
	var c: Array = CHIMNEYS[i]
	var x := float(c[0])
	var k := _plate_at(x)
	var f := (x - float(PLATES[k])) / ((NOSE if k == 0 else float(PLATES[k - 1]) + TUCK) - float(PLATES[k]))
	# The angle round the back whose point lies over the chimney's z.
	var best := Vector3.ZERO
	for s in 61:
		var p := _plate_point(k, f, lerpf(-1.2, 1.2, s / 60.0))
		if s == 0 or absf(p.z - float(c[1])) < absf(best.z - float(c[1])):
			best = p
	return best


## Chimney [param i], from its base on the shell: a lumpy, crusted stack,
## pale with sulphur below and dark with soot at its lip; its throat glows.
static func _chimney(i: int) -> ArrayMesh:
	var h := float(CHIMNEYS[i][2])
	var r0 := 0.07 + 0.14 * h
	var noise := FastNoiseLite.new()
	noise.seed = 70 + i
	noise.frequency = 6.0
	# Rings up the outside, over the lip and down into the throat: [y, radius].
	var rings := [Vector2(-0.1, r0 * 1.1), Vector2(0.0, r0 * 1.05), Vector2(h * 0.2, r0 * 0.9),
		Vector2(h * 0.45, r0 * 0.76), Vector2(h * 0.7, r0 * 0.68), Vector2(h * 0.9, r0 * 0.66),
		Vector2(h - 0.01, r0 * 0.76), Vector2(h + 0.015, r0 * 0.64), Vector2(h - 0.005, r0 * 0.46),
		Vector2(h - 0.08, r0 * 0.38), Vector2(h - 0.12, 0.0)]
	var stack := _loft(rings.size(), 14, func(ri: int, a: float) -> Vector3:
		var ring: Vector2 = rings[ri]
		var lump := 1.0 + 0.16 * noise.get_noise_2d(a * 1.3, ring.x * 4.0) if ri < 7 else 1.0
		return Vector3(sin(a) * ring.y * lump, ring.x, cos(a) * ring.y * lump),
		func(_ri: int, _a: float) -> Color: return Color())
	var parts := [[stack]]
	# Crust heaped round its foot.
	var lump_mesh := MeshKit.ball(1.0, 0.0, 8, 6)
	for j in 4:
		var a := TAU * (j + 0.3 * i) / 4.0
		parts.append([lump_mesh, Transform3D(Basis().scaled(Vector3(r0 * 0.75, r0 * 0.4, r0 * 0.75)),
			Vector3(sin(a) * r0 * 1.15, -0.02, cos(a) * r0 * 1.15))])
	# Pale crust below, sooty towards the lip; the throat aglow.
	return _unpainted(MeshKit.painted(MeshKit.merge(parts), func(v: Vector3) -> Color:
		if v.y < h - 0.02 or Vector2(v.x, v.z).length() > r0 * 0.6:
			return Color(0.0 if v.y < h * 0.85 else 0.45, lerpf(1.0, 0.25, smoothstep(h * 0.4, h, v.y)), 0.0)
		return Color(1.0, 0.1, 0.0)))


## [param mesh] left unpainted by the skin (UV2).
static func _unpainted(mesh: ArrayMesh) -> ArrayMesh:
	var arrays := mesh.surface_get_arrays(0)
	var uv2 := PackedVector2Array()
	uv2.resize((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
	uv2.fill(Vector2(0.0, UNPAINTED))
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


## A smooth curve through [param pts], [param count] points along it.
static func _curve(pts: Array, count: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	for s in count:
		var g := float(s) / (count - 1) * (pts.size() - 1)
		var k := mini(int(g), pts.size() - 2)
		var p0: Vector3 = pts[maxi(k - 1, 0)]
		var p3: Vector3 = pts[mini(k + 2, pts.size() - 1)]
		out.append((pts[k] as Vector3).cubic_interpolate(pts[k + 1], p0, p3, g - k))
	return out


## Walking leg [param i] (front first) on side [param sgn]: out from under
## the flank's flange, up to a knee, down to a hooked claw on the floor,
## spined along its shin; front legs reach forward, hind legs back.
## Neighbours step a third of a stride apart, the two sides half a stride.
static func _leg(i: int, sgn: float) -> ArrayMesh:
	var x := (float(PLATES[i]) + float(PLATES[i + 1])) * 0.5
	var lean := lerpf(0.55, -0.6, i / 6.0)
	var hw := BodyKit.at(BODY, x, 1)
	var hip := Vector3(x, -0.24, hw * 0.62 * sgn)
	var coxa := Vector3(x + lean * 0.04, -0.3, hw * 0.95 * sgn)
	var knee := Vector3(x + lean * 0.25, -0.2, (hw + 0.32) * sgn)
	var ankle := Vector3(x + lean * 0.45, FLOOR + 0.3, (hw + 0.52) * sgn)
	var foot := Vector3(x + lean * 0.56, FLOOR, (hw + 0.6) * sgn)
	var pts := _curve([hip, coxa, knee, ankle, ankle.lerp(foot, 0.6) + Vector3(0.0, 0.03, 0.03 * sgn), foot], 26)
	var radii := PackedFloat32Array()
	for s in pts.size():
		var t := float(s) / (pts.size() - 1)
		var r := lerpf(0.1, 0.05, t) if t < 0.8 else lerpf(0.05, 0.006, (t - 0.8) / 0.2)
		# The joints swell.
		for j: float in [0.2, 0.4, 0.62]:
			r *= 1.0 + 0.18 * exp(-pow((t - j) / 0.03, 2.0))
		radii.append(r)
	var tube := ArrayMesh.new()
	MeshKit.tube(tube, pts, radii, 7)
	var parts := [[tube]]
	var spine := MeshKit.spike(0.018, 0.1, 0.0, 5)
	for j in 3:
		var at := knee.lerp(ankle, 0.3 + 0.25 * j)
		var dir := Vector3(-0.5 - lean * 0.3, -0.6, 0.35 * sgn).normalized()
		parts.append([spine, Transform3D(Basis(Quaternion(Vector3.RIGHT, dir)), at)])
	var leg := MeshKit.painted(MeshKit.merge(parts), func(v: Vector3) -> Color:
		# The claw is bare, glossy horn.
		return Color(0.0, 0.15, 0.0, 0.0 if v.distance_to(foot) < 0.17 else 1.0))
	return BodyKit.legged(leg, hip, i * TAU / 3.0 + (PI if sgn < 0.0 else 0.0), sgn)


## The face's fixed parts on side [param sgn]: the eye, the short first
## feeler, the mouthparts over the mandibles, and the tail's paddles.
static func _face(sgn: float) -> Array:
	var out := []
	# A big kidney-shaped eye, dark and glossy with an ember sheen.
	var a := 1.12 * sgn
	var n := _plate_normal(0, 0.45, a)
	var along := (_plate_point(0, 0.5, a) - _plate_point(0, 0.4, a)).normalized()
	var side := along.cross(n).normalized()
	var eye := MeshKit.painted(MeshKit.ball(1.0, 0.0, 16, 10), func(_v: Vector3) -> Color:
		return Color(0.12, 0.0, 0.0, 0.0))
	out.append([_unpainted(eye), Transform3D(Basis(along * 0.2, n * 0.08, side * 0.13),
		_plate_point(0, 0.45, a) - n * 0.02)])
	var feeler := ArrayMesh.new()
	MeshKit.tube(feeler, PackedVector3Array([Vector3(2.28, 0.0, 0.12 * sgn), Vector3(2.42, 0.06, 0.2 * sgn),
		Vector3(2.55, 0.1, 0.26 * sgn), Vector3(2.63, 0.12, 0.3 * sgn)]),
		PackedFloat32Array([0.03, 0.025, 0.017, 0.005]), 6)
	out.append([_unpainted(MeshKit.painted(feeler, func(_v: Vector3) -> Color: return Color(0.0, 0.2, 0.0)))])
	var lip := _unpainted(MeshKit.painted(MeshKit.ball(1.0, 0.0, 10, 6), func(_v: Vector3) -> Color:
		return Color(0.0, 0.3, 0.0)))
	out.append([lip, Transform3D(Basis().scaled(Vector3(0.17, 0.045, 0.09)), Vector3(2.16, -0.27, 0.1 * sgn))])
	# The uropods: a broad paddle each side of the tail.
	var paddle := _unpainted(MeshKit.painted(MeshKit.ball(1.0, 0.0, 12, 6), func(_v: Vector3) -> Color:
		return Color(0.0, 0.2, 0.0)))
	out.append([paddle, Transform3D(Basis(Vector3.UP, 0.5 * sgn) * Basis.from_scale(Vector3(0.36, 0.035, 0.13)),
		Vector3(-1.98, -0.1, 0.86 * sgn))])
	return out


## The left or right ([param sgn]) long feeler, from its root (see
## [constant FEELER_ROOT]): forward and out, then sweeping back past its
## flank, jointed at the base and beaded along its whip. It quivers more
## towards its tip.
static func feeler(sgn: float) -> ArrayMesh:
	var pts := _curve([Vector3.ZERO, Vector3(0.22, 0.04, 0.1), Vector3(0.4, 0.08, 0.32), Vector3(0.42, 0.11, 0.62),
		Vector3(0.24, 0.13, 0.95), Vector3(-0.12, 0.13, 1.25), Vector3(-0.7, 0.1, 1.46), Vector3(-1.4, 0.05, 1.58)],
		80)
	for s in pts.size():
		pts[s] = pts[s] * Vector3(1.0, 1.0, sgn)
	var radii := PackedFloat32Array()
	var length := 0.0
	for s in pts.size():
		if s > 0:
			length += pts[s].distance_to(pts[s - 1])
		var t := float(s) / (pts.size() - 1)
		var r := lerpf(0.06, 0.04, t / 0.25) if t < 0.25 else lerpf(0.032, 0.006, (t - 0.25) / 0.75)
		var seg := 0.16 if t < 0.25 else 0.07
		r *= 1.0 + 0.16 * smoothstep(0.75, 1.0, fposmod(length / seg, 1.0))
		radii.append(r)
	var tube := ArrayMesh.new()
	MeshKit.tube(tube, pts, radii, 6)
	return _unpainted(MeshKit.painted(tube, func(v: Vector3) -> Color:
		return Color(0.0, 0.25, clampf(v.length() / 2.6, 0.0, 1.0))))


## The left or right ([param sgn]) mandible, from its hinge (see
## [constant JAW_ROOT]): a heavy hooked blade curving in under the face,
## toothed along its inner edge.
static func mandible(sgn: float) -> ArrayMesh:
	var pts := _curve([Vector3.ZERO, Vector3(0.1, -0.02, -0.02 * sgn), Vector3(0.2, -0.04, -0.07 * sgn),
		Vector3(0.27, -0.05, -0.13 * sgn), Vector3(0.3, -0.04, -0.18 * sgn)], 14)
	var radii := PackedFloat32Array()
	for s in pts.size():
		radii.append(lerpf(0.065, 0.008, pow(float(s) / (pts.size() - 1), 1.4)))
	var blade := ArrayMesh.new()
	MeshKit.tube(blade, pts, radii, 7)
	var parts := [[blade]]
	var tooth := MeshKit.spike(0.016, 0.06, 0.0, 5)
	for j in 3:
		var at := pts[4 + j * 3]
		parts.append([tooth, Transform3D(Basis(Quaternion(Vector3.RIGHT, Vector3(0.3, -0.2, -sgn).normalized())), at)])
	return _unpainted(BodyKit.enamel(MeshKit.merge(parts)))
